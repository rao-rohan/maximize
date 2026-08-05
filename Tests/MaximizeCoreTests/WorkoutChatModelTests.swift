import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// FR-2.1–2.4, D10: drives `WorkoutChatModel` end-to-end against `InMemoryWorkoutStore`,
/// `FakeChatThreadRepository` and `FakeStreamingChatModelInvoking` — the seam MAX-050
/// built specifically so this ticket needs neither SwiftData, a simulator, nor a device.
@MainActor
final class WorkoutChatModelTests: XCTestCase {

    // MARK: - Fixtures

    private func metrics(planVersion: Int = 1) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            averageCadenceStepsPerMinute: 167,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 3_000)]),
            planVersion: PlanVersion(planVersion)
        )
    }

    /// A store with a scored workout — the state `WorkoutChatModel.load()` needs to
    /// reach `.ready`. Callers that want `.notYetScored` skip `seedScore`.
    private func readyStore(seedScore: Bool = true) async throws -> InMemoryWorkoutStore {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        try await store.store(Fixture.workout())
        try await store.store(metrics())
        if seedScore {
            store.seedScore(try Fixture.score(points: 88))
        }
        return store
    }

    private func model(
        store: InMemoryWorkoutStore? = nil,
        threadRepository: FakeChatThreadRepository = FakeChatThreadRepository(),
        chatClient: FakeStreamingChatModelInvoking = FakeStreamingChatModelInvoking(),
        now: @escaping @Sendable () -> Date = { Fixture.epoch }
    ) async throws -> (WorkoutChatModel, InMemoryWorkoutStore?) {
        let resolvedStore: InMemoryWorkoutStore
        if let store {
            resolvedStore = store
        } else {
            resolvedStore = try await readyStore()
        }
        let workoutModel = WorkoutChatModel(
            workoutID: Fixture.workoutID,
            workoutRepository: resolvedStore,
            scoreRepository: resolvedStore,
            planRepository: resolvedStore,
            chatThreadRepository: threadRepository,
            chatClient: chatClient,
            timeZone: TimeZone(identifier: "UTC") ?? .current,
            now: now
        )
        return (workoutModel, resolvedStore)
    }

    // MARK: - Loading

    func testAllRepositoriesNilFailsRatherThanLookingEmpty() async throws {
        let workoutModel = WorkoutChatModel(
            workoutID: Fixture.workoutID,
            workoutRepository: nil,
            scoreRepository: nil,
            planRepository: nil,
            chatThreadRepository: nil,
            chatClient: FakeStreamingChatModelInvoking()
        )
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .failed)
    }

    func testOneNilRepositoryAmongFourStillFails() async throws {
        let store = try await readyStore()
        let workoutModel = WorkoutChatModel(
            workoutID: Fixture.workoutID,
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            chatThreadRepository: nil,
            chatClient: FakeStreamingChatModelInvoking()
        )
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .failed)
    }

    func testUnknownWorkoutFails() async throws {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        let (workoutModel, _) = try await model(store: store)
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .failed)
    }

    /// The load-bearing state this ticket adds: an unscored workout has no stored
    /// classification, so chat is not available yet — and that is ordinary, not a
    /// failure.
    func testUnscoredWorkoutIsNotYetScoredRatherThanFailed() async throws {
        let store = try await readyStore(seedScore: false)
        let (workoutModel, _) = try await model(store: store)
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .notYetScored)
        XCTAssertTrue(workoutModel.messages.isEmpty)
    }

    func testChatThreadReadFailurePropagatesAsFailed() async throws {
        let store = try await readyStore()
        let threadRepository = FakeChatThreadRepository()
        struct Boom: Error {}
        threadRepository.failReads(with: Boom())
        let (workoutModel, _) = try await model(store: store, threadRepository: threadRepository)
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .failed)
    }

    func testReadyLoadsAnEmptyThreadWhenNoneIsStoredYet() async throws {
        let (workoutModel, _) = try await model()
        await workoutModel.load()
        XCTAssertEqual(workoutModel.loadState, .ready)
        XCTAssertTrue(workoutModel.messages.isEmpty)
    }

    /// A stored thread's visible turns restore in order; a `.system` seed row (the
    /// domain type permits one — `ChatThreadTests.testSeedContextIsNotAVisibleTurn`)
    /// is never shown as a bubble.
    func testReadyRestoresAnExistingThreadsVisibleMessages() async throws {
        let threadRepository = FakeChatThreadRepository()
        var thread = try ChatThread(id: UUID(), workoutID: Fixture.workoutID)
        thread = try thread.appending(
            ChatMessage(id: UUID(), role: .system, content: "seed", timestamp: Fixture.epoch)
        )
        thread = try thread.appending(
            ChatMessage(id: UUID(), role: .user, content: "Was that on plan?", timestamp: Fixture.epoch.addingTimeInterval(1))
        )
        thread = try thread.appending(
            ChatMessage(id: UUID(), role: .assistant, content: "Yes, right on the cap.", timestamp: Fixture.epoch.addingTimeInterval(2))
        )
        try await threadRepository.store(thread)

        let (workoutModel, _) = try await model(threadRepository: threadRepository)
        await workoutModel.load()

        XCTAssertEqual(workoutModel.loadState, .ready)
        XCTAssertEqual(workoutModel.messages.map(\.text), ["Was that on plan?", "Yes, right on the cap."])
        XCTAssertEqual(workoutModel.messages.map(\.kind), [.user, .assistant])
    }

    // MARK: - Sending: the happy path

    func testCanSendRequiresReadyNonEmptyComposerAndNotAlreadyStreaming() async throws {
        let (workoutModel, _) = try await model()
        XCTAssertFalse(workoutModel.canSend, "not ready yet")

        await workoutModel.load()
        XCTAssertFalse(workoutModel.canSend, "composer is empty")

        workoutModel.composerText = "   "
        XCTAssertFalse(workoutModel.canSend, "whitespace-only")

        workoutModel.composerText = "How was my drift?"
        XCTAssertTrue(workoutModel.canSend)
    }

    func testSendIsANoOpWhenItCannotSend() async throws {
        let (workoutModel, _) = try await model()
        await workoutModel.load()
        // composerText is empty; canSend is false.
        await workoutModel.send()
        XCTAssertTrue(workoutModel.messages.isEmpty)
    }

    /// FR-2.4: the reveal actually streams (each token visible before the turn ends),
    /// and D6/FR-2.3: a completed turn is persisted as one user+assistant pair.
    func testSendStreamsThenPersistsBothTurnsOnCompletion() async throws {
        let threadRepository = FakeChatThreadRepository()
        let chatClient = FakeStreamingChatModelInvoking(
            events: [.text("You "), .text("held the cap "), .text("the whole way."), .completed(.endTurn)]
        )
        let (workoutModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "Was that on plan?"
        await workoutModel.send()

        XCTAssertFalse(workoutModel.isStreaming)
        XCTAssertEqual(workoutModel.streamingText, "", "cleared once the turn is over")
        XCTAssertEqual(workoutModel.composerText, "")
        XCTAssertEqual(workoutModel.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(workoutModel.messages.map(\.text), ["Was that on plan?", "You held the cap the whole way."])
        XCTAssertFalse(workoutModel.messages[1].wasTruncated)
        XCTAssertFalse(workoutModel.messages[1].wasInterruptedByFailure)

        XCTAssertEqual(threadRepository.writes, 1)
        let stored = try XCTUnwrap(threadRepository.allThreads.first)
        XCTAssertEqual(stored.visibleMessages.map(\.content), ["Was that on plan?", "You held the cap the whole way."])
        XCTAssertEqual(stored.visibleMessages.map(\.role), [.user, .assistant])
    }

    func testTruncatedCompletionIsPersistedAndFlagged() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("A long reply…"), .completed(.truncated)])
        let threadRepository = FakeChatThreadRepository()
        let (workoutModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "Tell me everything about this run."
        await workoutModel.send()

        XCTAssertTrue(workoutModel.messages.last?.wasTruncated ?? false)
        XCTAssertEqual(threadRepository.writes, 1, "a truncated reply is still real and storable")
    }

    /// D3: the fact sheet is the same string every time — never re-assembled — and the
    /// full history (including the just-completed turn) reaches the next instruction.
    func testFactSheetIsIdenticalAcrossTurnsAndHistoryAccumulates() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("Answer one."), .completed(.endTurn)])
        let (workoutModel, _) = try await model(chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "First question?"
        await workoutModel.send()

        chatClient.events = [.text("Answer two."), .completed(.endTurn)]
        workoutModel.composerText = "Second question?"
        await workoutModel.send()

        XCTAssertEqual(chatClient.callCount, 2)
        let first = chatClient.receivedInstructions[0]
        let second = chatClient.receivedInstructions[1]
        XCTAssertEqual(first.factSheet, second.factSheet)
        XCTAssertEqual(first.task, second.task)
        XCTAssertEqual(first.turns.map(\.text), ["First question?"])
        XCTAssertEqual(
            second.turns.map(\.text),
            ["First question?", "Answer one.", "Second question?"]
        )
        XCTAssertEqual(second.turns.first?.speaker, .user)
    }

    // MARK: - Sending: failure

    /// Constraint: partial text survives a failure, on screen, and is never persisted.
    func testFailedStreamKeepsPartialTextVisibleButPersistsNothing() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("Partial rep"), .failed(.interrupted)])
        let threadRepository = FakeChatThreadRepository()
        let (workoutModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "Why did my HR spike?"
        await workoutModel.send()

        XCTAssertFalse(workoutModel.isStreaming)
        XCTAssertEqual(workoutModel.messages.map(\.kind), [.user, .assistant, .notice])
        XCTAssertEqual(workoutModel.messages[1].text, "Partial rep")
        XCTAssertTrue(workoutModel.messages[1].wasInterruptedByFailure)
        XCTAssertEqual(threadRepository.writes, 0, "only completed turns are persisted")
        XCTAssertEqual(threadRepository.threadCount, 0)
    }

    func testFailureWithNoTextYetShowsOnlyANotice() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.failed(.requestFailed)])
        let (workoutModel, _) = try await model(chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "Was that hard?"
        await workoutModel.send()

        XCTAssertEqual(workoutModel.messages.map(\.kind), [.user, .notice])
    }

    /// "No key stored" is the app's ordinary day-one state (constraint #5): a plain
    /// message pointing at Settings, not a crash or a stuck spinner.
    func testNoAPIKeyStoredPointsAtSettings() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.failed(.noAPIKeyStored)])
        let (workoutModel, _) = try await model(chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "How did I do?"
        await workoutModel.send()

        XCTAssertFalse(workoutModel.isStreaming, "never a spinner that never resolves")
        let notice = try XCTUnwrap(workoutModel.messages.last)
        XCTAssertEqual(notice.kind, .notice)
        XCTAssertTrue(notice.text.contains("Settings"), notice.text)
    }

    /// A retry after a failure is a fresh question, not a resumed one — the previous
    /// attempt's unsent question and partial reply are not spliced into the next
    /// instruction, since neither was ever persisted.
    func testRetryAfterFailureDoesNotReplayTheDroppedTurn() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("half…"), .failed(.interrupted)])
        let (workoutModel, _) = try await model(chatClient: chatClient)
        await workoutModel.load()

        workoutModel.composerText = "First try?"
        await workoutModel.send()

        chatClient.events = [.text("Full answer."), .completed(.endTurn)]
        workoutModel.composerText = "Second try?"
        await workoutModel.send()

        let secondInstruction = try XCTUnwrap(chatClient.receivedInstructions.last)
        XCTAssertEqual(secondInstruction.turns.map(\.text), ["Second try?"])
    }
}
