import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// FR-2.1–2.4, D10, A11: drives `ChatModel` end-to-end against `InMemoryWorkoutStore`,
/// `FakeChatThreadRepository` and `FakeStreamingChatModelInvoking` — the seam MAX-050
/// built specifically so this ticket needs neither SwiftData, a simulator, nor a device.
///
/// The workout half of this file is MAX-051's suite, unchanged except for the type's
/// name and the subject it is handed. That is deliberate, and it is the regression:
/// MAX-096 generalised the model, and a workout thread must behave exactly as it did
/// before.
@MainActor
final class ChatModelTests: XCTestCase {

    // MARK: - Fixtures

    private let utc = TimeZone(identifier: "UTC") ?? .current

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

    /// A store with a scored workout — the state `ChatModel.load()` needs to reach
    /// `.ready`. Callers that want `.notYetScored` skip `seedScore`.
    private func readyStore(
        seedScore: Bool = true,
        activityType: ActivityType = .running
    ) async throws -> InMemoryWorkoutStore {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        try await store.store(Fixture.workout(activityType: activityType))
        try await store.store(metrics())
        if seedScore {
            store.seedScore(try Fixture.score(points: 88))
        }
        return store
    }

    /// The week `Fixture.workout()` falls in — Thursday 2026-01-01 through the following
    /// Wednesday, deliberately *not* Monday-aligned so `ChatModel`'s C1 widening is
    /// exercised rather than assumed.
    private func scope() throws -> TrainingScope {
        try Fixture.scope(from: (2026, 1, 1), through: (2026, 1, 7))
    }

    private func model(
        subject: ChatSubject = .workout(Fixture.workoutID),
        store: InMemoryWorkoutStore? = nil,
        threadRepository: FakeChatThreadRepository = FakeChatThreadRepository(),
        chatClient: FakeStreamingChatModelInvoking = FakeStreamingChatModelInvoking(),
        now: @escaping @Sendable () -> Date = { Fixture.epoch }
    ) async throws -> (ChatModel, InMemoryWorkoutStore) {
        let resolvedStore: InMemoryWorkoutStore
        if let store {
            resolvedStore = store
        } else {
            resolvedStore = try await readyStore()
        }
        let chatModel = ChatModel(
            subject: subject,
            workoutRepository: resolvedStore,
            scoreRepository: resolvedStore,
            planRepository: resolvedStore,
            settingsRepository: resolvedStore,
            chatThreadRepository: threadRepository,
            chatClient: chatClient,
            timeZone: utc,
            now: now
        )
        return (chatModel, resolvedStore)
    }

    /// Opens by thread id rather than by subject (§2.3, MAX-097's review). Mirrors
    /// `model(subject:...)` in every other respect.
    private func model(
        threadID: UUID,
        store: InMemoryWorkoutStore? = nil,
        threadRepository: FakeChatThreadRepository = FakeChatThreadRepository(),
        chatClient: FakeStreamingChatModelInvoking = FakeStreamingChatModelInvoking(),
        now: @escaping @Sendable () -> Date = { Fixture.epoch }
    ) async throws -> (ChatModel, InMemoryWorkoutStore) {
        let resolvedStore: InMemoryWorkoutStore
        if let store {
            resolvedStore = store
        } else {
            resolvedStore = try await readyStore()
        }
        let chatModel = ChatModel(
            threadID: threadID,
            workoutRepository: resolvedStore,
            scoreRepository: resolvedStore,
            planRepository: resolvedStore,
            settingsRepository: resolvedStore,
            chatThreadRepository: threadRepository,
            chatClient: chatClient,
            timeZone: utc,
            now: now
        )
        return (chatModel, resolvedStore)
    }

    /// Opens by minting a fresh thread rather than resolving one — MAX-185's
    /// **New chat**. Mirrors `model(subject:...)` in every other respect.
    private func model(
        startingNewThreadFor subject: ChatSubject,
        store: InMemoryWorkoutStore? = nil,
        threadRepository: FakeChatThreadRepository = FakeChatThreadRepository(),
        chatClient: FakeStreamingChatModelInvoking = FakeStreamingChatModelInvoking(),
        now: @escaping @Sendable () -> Date = { Fixture.epoch }
    ) async throws -> (ChatModel, InMemoryWorkoutStore) {
        let resolvedStore: InMemoryWorkoutStore
        if let store {
            resolvedStore = store
        } else {
            resolvedStore = try await readyStore()
        }
        let chatModel = ChatModel(
            startingNewThreadFor: subject,
            workoutRepository: resolvedStore,
            scoreRepository: resolvedStore,
            planRepository: resolvedStore,
            settingsRepository: resolvedStore,
            chatThreadRepository: threadRepository,
            chatClient: chatClient,
            timeZone: utc,
            now: now
        )
        return (chatModel, resolvedStore)
    }

    // MARK: - Loading

    func testAllRepositoriesNilFailsRatherThanLookingEmpty() async throws {
        let chatModel = ChatModel(
            subject: .workout(Fixture.workoutID),
            workoutRepository: nil,
            scoreRepository: nil,
            planRepository: nil,
            settingsRepository: nil,
            chatThreadRepository: nil,
            chatClient: FakeStreamingChatModelInvoking()
        )
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .failed)
    }

    func testOneNilRepositoryAmongFiveStillFails() async throws {
        let store = try await readyStore()
        let chatModel = ChatModel(
            subject: .workout(Fixture.workoutID),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: nil,
            chatClient: FakeStreamingChatModelInvoking()
        )
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .failed)
    }

    func testUnknownWorkoutFails() async throws {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .failed)
    }

    /// The load-bearing state MAX-051 added: an unscored workout has no stored
    /// classification, so chat is not available yet — and that is ordinary, not a
    /// failure.
    func testUnscoredWorkoutIsNotYetScoredRatherThanFailed() async throws {
        let store = try await readyStore(seedScore: false)
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .notYetScored)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// MAX-126. Same missing ledger, different reason, and the difference is the whole
    /// point: `.notYetScored` renders as "chat opens once it has a score", which for a
    /// ride is a door that never opens — no band in any rubric describes one, and none
    /// can be authored.
    ///
    /// **The lift moved to the other side in MAX-168** (`testAnUnscoredLiftIsAWait`
    /// below): once the ingestion gate offers a lift a score, the door does open, so this
    /// case is now about the activities it stays shut for.
    func testAnUnscoredRideHasNoVerdictRatherThanNotYetScored() async throws {
        let store = try await readyStore(
            seedScore: false,
            activityType: .cycling
        )
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .noVerdict)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// MAX-168, the other half: an unscored lift is waiting, not settled. Its score
    /// arrives once the athlete has said what it worked (A22) and a plan version can
    /// judge the day — both reachable, which is exactly what `.notYetScored` means.
    func testAnUnscoredLiftIsAWait() async throws {
        let store = try await readyStore(
            seedScore: false,
            activityType: .traditionalStrengthTraining
        )
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .notYetScored)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// D8, from chat's side: a lift that *was* scored before MAX-111 still has a stored
    /// classification, so its thread still opens. Nothing here reaches back and closes a
    /// conversation that already worked.
    func testAnAlreadyScoredLiftStillReachesReady() async throws {
        let store = try await readyStore(activityType: .traditionalStrengthTraining)
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .ready)
    }

    func testChatThreadReadFailurePropagatesAsFailed() async throws {
        let store = try await readyStore()
        let threadRepository = FakeChatThreadRepository()
        struct Boom: Error {}
        threadRepository.failReads(with: Boom())
        let (chatModel, _) = try await model(store: store, threadRepository: threadRepository)
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .failed)
    }

    func testReadyLoadsAnEmptyThreadWhenNoneIsStoredYet() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// A stored thread's visible turns restore in order; a `.system` seed row (the
    /// domain type permits one — `ChatThreadTests.testSeedContextIsNotAVisibleTurn`)
    /// is never shown as a bubble.
    func testReadyRestoresAnExistingThreadsVisibleMessages() async throws {
        let threadRepository = FakeChatThreadRepository()
        var thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
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

        let (chatModel, _) = try await model(threadRepository: threadRepository)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.messages.map(\.text), ["Was that on plan?", "Yes, right on the cap."])
        XCTAssertEqual(chatModel.messages.map(\.kind), [.user, .assistant])
    }

    // MARK: - Title and subtitle (MAX-097, §2.2/§2.4/§3.6(b))

    /// Before `load()` resolves a thread, the title is a neutral placeholder — matching
    /// what this screen's navigation title always read before the sheet needed a real
    /// one.
    func testTitleIsAPlaceholderBeforeLoading() async throws {
        let (chatModel, _) = try await model()
        XCTAssertEqual(chatModel.title, "Chat")
    }

    /// Once ready, the workout thread's title is `ChatThreadTitle`'s own derivation —
    /// this type calls it, it does not recompute it.
    func testAWorkoutThreadsTitleIsTheRunsDateAndActivity() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.title, "1 Jan 2026 · Running")
    }

    /// The subtitle needs no load at all — it is known from `subject` alone.
    func testSubtitleIsKnownImmediatelyFromTheSubject() async throws {
        let (chatModel, _) = try await model()
        XCTAssertEqual(chatModel.subtitle, "This run")
    }

    func testATrainingThreadsSubtitleStatesTheFrozenWindow() async throws {
        let (chatModel, _) = try await model(subject: .training(try scope()))
        XCTAssertEqual(chatModel.subtitle, (try scope()).label)
    }

    /// An empty training thread's title falls back to its window label — same value the
    /// subtitle already states, and both are correct at once (§2.4's own documented
    /// fallback).
    func testAnEmptyTrainingThreadsTitleFallsBackToItsWindow() async throws {
        let (chatModel, _) = try await model(subject: .training(try scope()))
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.title, (try scope()).label)
    }

    /// Once the athlete has asked something, the title follows the question — and the
    /// subtitle keeps stating the window regardless, which is the whole of §3.6(b)'s
    /// "state it everywhere it could matter."
    func testATrainingThreadsTitleFollowsTheFirstQuestionWhileSubtitleStaysTheWindow() async throws {
        let threadRepository = FakeChatThreadRepository()
        let chatClient = FakeStreamingChatModelInvoking(
            events: [.text("Slightly, yes."), .completed(.endTurn)]
        )
        let (chatModel, _) = try await model(
            subject: .training(try scope()),
            threadRepository: threadRepository,
            chatClient: chatClient
        )
        await chatModel.load()
        chatModel.composerText = "Has my drift flattened?"
        await chatModel.send()

        XCTAssertEqual(chatModel.title, "Has my drift flattened?")
        XCTAssertEqual(chatModel.subtitle, (try scope()).label)
    }

    // MARK: - Opening by thread id (§2.3, review follow-up)

    /// **The regression the review caught.** Two training threads over an identical,
    /// frozen window are legitimately allowed to coexist —
    /// `ChatThreadRepository`'s own contract deliberately does not deduplicate training
    /// subjects, because **New chat** over an unchanged window is still a real action.
    /// Resolving *by subject* after a thread-list tap would silently open whichever one
    /// is newest, not the one actually tapped. This is the test that would have caught
    /// it, and it fails without `init(threadID:...)` reading the exact thread rather
    /// than re-resolving its subject.
    func testOpeningByIDReturnsExactlyThatThreadEvenWhenAnotherSharesItsScope() async throws {
        let threadRepository = FakeChatThreadRepository()
        let sharedScope = try scope()

        var older = try Fixture.thread(subject: .training(sharedScope), lastActivityAt: Fixture.at(0))
        older = try older.appending(try Fixture.message(.user, "What did week one look like?", at: 0))
        var newer = try Fixture.thread(subject: .training(sharedScope), lastActivityAt: Fixture.at(100))
        newer = try newer.appending(try Fixture.message(.user, "Has drift flattened?", at: 100))
        try await threadRepository.store(older)
        try await threadRepository.store(newer)

        // Sanity check that the fixture actually reproduces the ambiguity: resolving by
        // subject really does pick the newer one — that is the defect opening by id has
        // to avoid, not a hypothetical.
        let bySubject = try await threadRepository.mostRecentThread(for: .training(sharedScope))
        XCTAssertEqual(bySubject?.id, newer.id)

        let (chatModel, _) = try await model(threadID: older.id, threadRepository: threadRepository)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.thread?.id, older.id)
        XCTAssertEqual(chatModel.subject, .training(sharedScope))
        XCTAssertEqual(chatModel.messages.map(\.text), ["What did week one look like?"])
    }

    /// The subject is read off the stored thread, not supplied by a caller — exercised
    /// on the workout path too, not only the training path the defect above was found on.
    func testOpeningAWorkoutThreadByIDResolvesItsSubjectFromTheStoredThread() async throws {
        let threadRepository = FakeChatThreadRepository()
        let thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        try await threadRepository.store(thread)

        let (chatModel, _) = try await model(threadID: thread.id, threadRepository: threadRepository)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.subject, .workout(Fixture.workoutID))
        XCTAssertEqual(chatModel.thread?.id, thread.id)
    }

    /// A thread id that no longer resolves is what a delete on another screen leaves
    /// behind — an ordinary, real state, not a crash and not `.failed`.
    func testOpeningANonexistentThreadIDIsThreadNotFoundRatherThanFailed() async throws {
        let (chatModel, _) = try await model(threadID: UUID())
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .threadNotFound)
        XCTAssertNil(chatModel.subject)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// `subject` is set as soon as the stored thread is read, *before* the rest of
    /// `load()` runs — so a state that returns early from further down, like
    /// `.notYetScored`, still has it. Without this a thread-id-opened sheet would show a
    /// blank subtitle for a run that just has not been scored yet.
    func testOpeningByIDStillKnowsTheSubjectWhenNotYetScored() async throws {
        let threadRepository = FakeChatThreadRepository()
        let thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        try await threadRepository.store(thread)
        let unscoredStore = try await readyStore(seedScore: false)

        let (chatModel, _) = try await model(threadID: thread.id, store: unscoredStore, threadRepository: threadRepository)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .notYetScored)
        XCTAssertEqual(chatModel.subject, .workout(Fixture.workoutID))
        XCTAssertEqual(chatModel.subtitle, "This run")
    }

    // MARK: - New chat (MAX-185)

    /// **The regression this ticket fixes.** A populated thread already exists for the
    /// scope; `init(startingNewThreadFor:...)` must not silently reopen it the way
    /// `init(subject:...)` — and the toolbar button's old implementation — did.
    func testStartingNewThreadNeverResolvesToAnExistingThreadOnTheSameSubject() async throws {
        let threadRepository = FakeChatThreadRepository()
        let sharedScope = try scope()
        var existing = try Fixture.thread(subject: .training(sharedScope), lastActivityAt: Fixture.at(0))
        existing = try existing.appending(try Fixture.message(.user, "What did week one look like?", at: 0))
        try await threadRepository.store(existing)

        let (chatModel, _) = try await model(
            startingNewThreadFor: .training(sharedScope),
            threadRepository: threadRepository
        )
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.subject, .training(sharedScope))
        XCTAssertNotEqual(chatModel.thread?.id, existing.id)
        XCTAssertTrue(chatModel.messages.isEmpty, "a new thread starts with nothing said in it")
    }

    /// Every mint is distinct — pressing **New chat** twice must not converge on the
    /// same thread the second time, which is what would leave the second tap inert too.
    func testStartingNewThreadMintsADistinctThreadEachTime() async throws {
        let threadRepository = FakeChatThreadRepository()
        let (first, _) = try await model(startingNewThreadFor: .training(try scope()), threadRepository: threadRepository)
        await first.load()
        let (second, _) = try await model(startingNewThreadFor: .training(try scope()), threadRepository: threadRepository)
        await second.load()

        XCTAssertEqual(first.loadState, .ready)
        XCTAssertEqual(second.loadState, .ready)
        XCTAssertNotEqual(first.thread?.id, second.thread?.id)
    }

    /// A14/"only completed turns are persisted": minting a thread for **New chat** must
    /// not write anything by itself — the repository sees no new row until a turn
    /// completes, exactly as the resolve-or-create path already behaves.
    func testStartingNewThreadWritesNothingUntilATurnIsSent() async throws {
        let threadRepository = FakeChatThreadRepository()
        let (chatModel, _) = try await model(startingNewThreadFor: .training(try scope()), threadRepository: threadRepository)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(threadRepository.writes, 0)
        XCTAssertEqual(threadRepository.threadCount, 0)
    }

    /// The minted thread's title and subtitle degrade exactly the way any other empty
    /// training thread's do (§2.4) — **New chat** is not a second, unstyled state.
    func testAFreshlyStartedThreadsTitleFallsBackToItsWindowLikeAnyEmptyOne() async throws {
        let (chatModel, _) = try await model(startingNewThreadFor: .training(try scope()))
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertEqual(chatModel.title, (try scope()).label)
        XCTAssertEqual(chatModel.subtitle, (try scope()).label)
    }

    // MARK: - Sending: the happy path

    func testCanSendRequiresReadyNonEmptyComposerAndNotAlreadyStreaming() async throws {
        let (chatModel, _) = try await model()
        XCTAssertFalse(chatModel.canSend, "not ready yet")

        await chatModel.load()
        XCTAssertFalse(chatModel.canSend, "composer is empty")

        chatModel.composerText = "   "
        XCTAssertFalse(chatModel.canSend, "whitespace-only")

        chatModel.composerText = "How was my drift?"
        XCTAssertTrue(chatModel.canSend)
    }

    func testSendIsANoOpWhenItCannotSend() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()
        // composerText is empty; canSend is false.
        await chatModel.send()
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    /// FR-2.4: the reveal actually streams (each token visible before the turn ends),
    /// and D6/FR-2.3: a completed turn is persisted as one user+assistant pair.
    func testSendStreamsThenPersistsBothTurnsOnCompletion() async throws {
        let threadRepository = FakeChatThreadRepository()
        let chatClient = FakeStreamingChatModelInvoking(
            events: [.text("You "), .text("held the cap "), .text("the whole way."), .completed(.endTurn)]
        )
        let (chatModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "Was that on plan?"
        await chatModel.send()

        XCTAssertFalse(chatModel.isStreaming)
        XCTAssertEqual(chatModel.streamingText, "", "cleared once the turn is over")
        XCTAssertEqual(chatModel.composerText, "")
        XCTAssertEqual(chatModel.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(chatModel.messages.map(\.text), ["Was that on plan?", "You held the cap the whole way."])
        XCTAssertFalse(chatModel.messages[1].wasTruncated)
        XCTAssertFalse(chatModel.messages[1].wasInterruptedByFailure)

        XCTAssertEqual(threadRepository.writes, 1)
        let stored = try XCTUnwrap(threadRepository.allThreads.first)
        XCTAssertEqual(stored.visibleMessages.map(\.content), ["Was that on plan?", "You held the cap the whole way."])
        XCTAssertEqual(stored.visibleMessages.map(\.role), [.user, .assistant])
    }

    func testTruncatedCompletionIsPersistedAndFlagged() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("A long reply…"), .completed(.truncated)])
        let threadRepository = FakeChatThreadRepository()
        let (chatModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "Tell me everything about this run."
        await chatModel.send()

        XCTAssertTrue(chatModel.messages.last?.wasTruncated ?? false)
        XCTAssertEqual(threadRepository.writes, 1, "a truncated reply is still real and storable")
    }

    /// D3: the fact sheet is the same string every time — never re-assembled — and the
    /// full history (including the just-completed turn) reaches the next instruction.
    func testFactSheetIsIdenticalAcrossTurnsAndHistoryAccumulates() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("Answer one."), .completed(.endTurn)])
        let (chatModel, _) = try await model(chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "First question?"
        await chatModel.send()

        chatClient.events = [.text("Answer two."), .completed(.endTurn)]
        chatModel.composerText = "Second question?"
        await chatModel.send()

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
        let (chatModel, _) = try await model(threadRepository: threadRepository, chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "Why did my HR spike?"
        await chatModel.send()

        XCTAssertFalse(chatModel.isStreaming)
        XCTAssertEqual(chatModel.messages.map(\.kind), [.user, .assistant, .notice])
        XCTAssertEqual(chatModel.messages[1].text, "Partial rep")
        XCTAssertTrue(chatModel.messages[1].wasInterruptedByFailure)
        XCTAssertEqual(threadRepository.writes, 0, "only completed turns are persisted")
        XCTAssertEqual(threadRepository.threadCount, 0)
    }

    func testFailureWithNoTextYetShowsOnlyANotice() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.failed(.requestFailed)])
        let (chatModel, _) = try await model(chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "Was that hard?"
        await chatModel.send()

        XCTAssertEqual(chatModel.messages.map(\.kind), [.user, .notice])
    }

    /// "No key stored" is the app's ordinary day-one state (constraint #5): a plain
    /// message pointing at Settings, not a crash or a stuck spinner.
    func testNoAPIKeyStoredPointsAtSettings() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.failed(.noAPIKeyStored)])
        let (chatModel, _) = try await model(chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "How did I do?"
        await chatModel.send()

        XCTAssertFalse(chatModel.isStreaming, "never a spinner that never resolves")
        let notice = try XCTUnwrap(chatModel.messages.last)
        XCTAssertEqual(notice.kind, .notice)
        XCTAssertEqual(notice.text, "Add an Anthropic API key in Settings to chat about this workout.")
    }

    /// A retry after a failure is a fresh question, not a resumed one — the previous
    /// attempt's unsent question and partial reply are not spliced into the next
    /// instruction, since neither was ever persisted.
    func testRetryAfterFailureDoesNotReplayTheDroppedTurn() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.text("half…"), .failed(.interrupted)])
        let (chatModel, _) = try await model(chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "First try?"
        await chatModel.send()

        chatClient.events = [.text("Full answer."), .completed(.endTurn)]
        chatModel.composerText = "Second try?"
        await chatModel.send()

        let secondInstruction = try XCTUnwrap(chatClient.receivedInstructions.last)
        XCTAssertEqual(secondInstruction.turns.map(\.text), ["Second try?"])
    }

    // MARK: - The training subject (MAX-096)

    func testTrainingThreadLoadsAndOpensReady() async throws {
        let (chatModel, _) = try await model(subject: .training(try scope()))
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertTrue(chatModel.messages.isEmpty)
    }

    // MARK: - The runs strip (§2.2, §6.2, MAX-103)

    /// A workout thread's sheet already sits on top of that run's own screen (§6.1), so
    /// there is nothing to strip — `runsStripData` is nil unconditionally, not merely
    /// empty.
    func testRunsStripDataIsNilForAWorkoutSubject() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertNil(chatModel.runsStripData)
    }

    /// `runsStripData` reads the exact `TrainingContext` `load()` built for this thread's
    /// prompt — `Fixture.workout()` (1 Jan 2026, running) is the one session `readyStore()`
    /// seeds inside `scope()`'s window, so the strip must name exactly that run.
    func testRunsStripDataNamesTheSessionInThisThreadsContext() async throws {
        let (chatModel, _) = try await model(subject: .training(try scope()))
        await chatModel.load()

        guard case let .chips(chips, omittedCount) = try XCTUnwrap(chatModel.runsStripData) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(omittedCount, 0)
        XCTAssertEqual(chips.map(\.workoutID), [Fixture.workoutID])
        XCTAssertEqual(chips.map(\.label), ["1 Jan 2026 · Running"])
    }

    /// A training window with nothing recorded is a real, worded absence — not the
    /// generic "nothing loaded" a nil would leave a view to guess at.
    func testRunsStripDataIsAWordedAbsenceForAnEmptyWindow() async throws {
        let empty = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        let (chatModel, _) = try await model(subject: .training(try scope()), store: empty)
        await chatModel.load()

        XCTAssertEqual(chatModel.runsStripData, .empty(.noSessionsInWindow))
    }

    /// A training window with nothing in it is not a failure and not a missing verdict —
    /// it is a window the roll-up describes as empty. The two workout-only states must
    /// stay unreachable here, or a view will offer to wait for a score on a month.
    func testATrainingWindowWithNoSessionsStillOpens() async throws {
        let empty = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        let (chatModel, _) = try await model(subject: .training(try scope()), store: empty)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
    }

    /// An athlete who has authored no plan still has a window worth describing — the
    /// opposite of the workout path, where a missing plan calendar is a load failure
    /// because there is nothing to measure the run against.
    func testATrainingWindowOpensBeforeAnyPlanIsAuthored() async throws {
        let store = InMemoryWorkoutStore(planCalendar: nil)
        try await store.store(Fixture.workout())
        let (chatModel, _) = try await model(subject: .training(try scope()), store: store)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
    }

    /// The training path streams, appends and persists exactly as the workout path does —
    /// everything after `load()` is written once and does not branch on the subject.
    func testTrainingThreadStreamsAndAppendsACompletedTurn() async throws {
        let threadRepository = FakeChatThreadRepository()
        let chatClient = FakeStreamingChatModelInvoking(
            events: [.text("Your drift has flattened."), .completed(.endTurn)]
        )
        let (chatModel, _) = try await model(
            subject: .training(try scope()),
            threadRepository: threadRepository,
            chatClient: chatClient
        )
        await chatModel.load()

        chatModel.composerText = "Has my drift flattened this week?"
        await chatModel.send()

        XCTAssertEqual(chatModel.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(threadRepository.writes, 1)
        let stored = try XCTUnwrap(threadRepository.allThreads.first)
        XCTAssertEqual(stored.subject, .training(try scope()))
        XCTAssertEqual(
            stored.visibleMessages.map(\.content),
            ["Has my drift flattened this week?", "Your drift has flattened."]
        )
    }

    /// A11's payoff: the thread the model opens is the one for *this* subject. A workout
    /// thread stored for the same run must not surface in a training conversation.
    func testATrainingThreadDoesNotOpenAWorkoutThread() async throws {
        let threadRepository = FakeChatThreadRepository()
        var workoutThread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        workoutThread = try workoutThread.appending(try Fixture.message(.user, "About that run", at: 1))
        try await threadRepository.store(workoutThread)

        let (chatModel, _) = try await model(
            subject: .training(try scope()),
            threadRepository: threadRepository
        )
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertTrue(chatModel.messages.isEmpty, "the run's own conversation is a different thread")
    }

    /// §3.5: a training turn is asked to do a different job, against a different fact
    /// sheet. Both halves of the instruction change with the subject, and neither is
    /// composed anywhere but `ContextBuilder` and this model (A12).
    func testTrainingAndWorkoutTurnsSendDifferentTasksAndFactSheets() async throws {
        let store = try await readyStore()
        let threadRepository = FakeChatThreadRepository()

        let workoutClient = FakeStreamingChatModelInvoking(events: [.text("A."), .completed(.endTurn)])
        let (workoutModel, _) = try await model(
            store: store,
            threadRepository: threadRepository,
            chatClient: workoutClient
        )
        await workoutModel.load()
        workoutModel.composerText = "How was it?"
        await workoutModel.send()

        let trainingClient = FakeStreamingChatModelInvoking(events: [.text("B."), .completed(.endTurn)])
        let (trainingModel, _) = try await model(
            subject: .training(try scope()),
            store: store,
            threadRepository: threadRepository,
            chatClient: trainingClient
        )
        await trainingModel.load()
        trainingModel.composerText = "How was the week?"
        await trainingModel.send()

        let workoutInstruction = try XCTUnwrap(workoutClient.receivedInstructions.last)
        let trainingInstruction = try XCTUnwrap(trainingClient.receivedInstructions.last)
        XCTAssertEqual(workoutInstruction.task, ChatModel.workoutTask)
        XCTAssertEqual(trainingInstruction.task, ChatModel.trainingTask)
        XCTAssertNotEqual(workoutInstruction.factSheet, trainingInstruction.factSheet)
    }

    func testNoAPIKeyNoticeIsWordedForTheTrainingSubject() async throws {
        let chatClient = FakeStreamingChatModelInvoking(events: [.failed(.noAPIKeyStored)])
        let (chatModel, _) = try await model(subject: .training(try scope()), chatClient: chatClient)
        await chatModel.load()

        chatModel.composerText = "How am I doing?"
        await chatModel.send()

        let notice = try XCTUnwrap(chatModel.messages.last)
        XCTAssertEqual(notice.text, "Add an Anthropic API key in Settings to chat about your training.")
    }

    // MARK: - The door to the plan's conversation (MAX-194)

    /// A training thread already *is* the conversation the door leads to — offering a
    /// door there would be a door to itself. `canDraftPlan`'s own training-only gate
    /// governs what happens once there; this property is unconditionally nil on that
    /// side.
    func testPlanConversationDoorIsNilForATrainingSubject() async throws {
        let (chatModel, _) = try await model(subject: .training(try scope()))
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertNil(chatModel.planConversationDoor)
    }

    /// Nil before `load()` has built a context — the same degrade-before-ready rule
    /// `runsStripData`, `title` and `subtitle` all follow.
    func testPlanConversationDoorIsNilBeforeLoad() async throws {
        let (chatModel, _) = try await model()
        XCTAssertNil(chatModel.planConversationDoor)
    }

    /// `Fixture.workout()` sits on Thursday 2026-01-01 — its Monday-first week is
    /// **29 Dec 2025 – 4 Jan 2026**. The door must target exactly that week, not the
    /// dashboard's current one (`scope()`'s Thu-through-Wed window, deliberately
    /// different, is never consulted here — a workout thread has no `currentInterval`
    /// input to this decision at all).
    func testPlanConversationDoorTargetsTheRunsOwnMondayFirstWeek() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()

        let offer = try XCTUnwrap(chatModel.planConversationDoor)
        XCTAssertEqual(offer.scope.from, try Fixture.day(2025, 12, 29))
        XCTAssertEqual(offer.scope.through, try Fixture.day(2026, 1, 4))
    }

    /// `Fixture.plan()` is effective from 1 Jan 2026, so it governs the fixture week —
    /// the button reads the "a plan is in force" wording.
    func testPlanConversationDoorLabelWhenAPlanGovernsTheWeek() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()

        let offer = try XCTUnwrap(chatModel.planConversationDoor)
        XCTAssertEqual(offer.buttonLabel, "Ask about the plan")
    }

    /// The continuity note names this exact run, the same way its own thread title does
    /// — `Fixture.workout()` is a run on 1 Jan 2026.
    func testPlanConversationDoorContinuityNoteNamesThisRun() async throws {
        let (chatModel, _) = try await model()
        await chatModel.load()

        let offer = try XCTUnwrap(chatModel.planConversationDoor)
        XCTAssertEqual(offer.continuityNote, "Continued from 1 Jan 2026 · Running.")
    }

    /// A lift's own activity type reaches the note — nothing here assumes "Running".
    func testPlanConversationDoorContinuityNoteNamesALift() async throws {
        let store = try await readyStore(activityType: .traditionalStrengthTraining)
        let (chatModel, _) = try await model(store: store)
        await chatModel.load()

        let offer = try XCTUnwrap(chatModel.planConversationDoor)
        XCTAssertTrue(offer.continuityNote.contains("Strength training"), offer.continuityNote)
    }

    // MARK: - The task texts (§3.5)

    /// §3.6(b)'s mechanism, asserted rather than assumed: a frozen scope only becomes
    /// legible if every aggregate the model quotes carries the window it was measured
    /// over. This is the clause that turns a mismatch into a labelled difference rather
    /// than an ambush, so it does not get quietly reworded away.
    func testTrainingTaskRequiresNamingTheWindowBesideEveryAggregate() async {
        let task = ChatModel.trainingTask
        XCTAssertTrue(task.contains("name the window you measured it over"), task)
        XCTAssertTrue(task.contains("in the same sentence"), task)
    }

    /// D8 from chat's side: a model invited to re-score in prose produces a correction
    /// recorded nowhere, which is the opposite of the divergence signal PRD §2 wants.
    func testTrainingTaskForbidsRevisingAScore() async {
        let task = ChatModel.trainingTask
        XCTAssertTrue(task.contains("not up for revision"), task)
        XCTAssertTrue(task.contains("never re-score a session"), task)
        XCTAssertTrue(task.contains("record on the run itself"), task)
    }

    /// The remaining three §3.5 requirements, so a future edit cannot drop one silently.
    func testTrainingTaskStatesTheSummarysLimitsAndRefusesMedicalAdvice() async {
        let task = ChatModel.trainingTask
        XCTAssertTrue(task.contains("Answer using only that summary"), task)
        XCTAssertTrue(task.contains("Never invent a figure"), task)
        XCTAssertTrue(task.contains("no kilometre"), task)
        XCTAssertTrue(task.contains("heart-rate curve"), task)
        XCTAssertTrue(task.contains("that run's own conversation"), task)
        XCTAssertTrue(task.contains("No medical advice"), task)
    }

    /// Neither task may carry a number, a date or anything else about this athlete —
    /// that is what lets it travel as a cacheable block shared by every thread of its
    /// kind, and it is the same contract `ScoringInstruction.task` carries.
    func testNeitherTaskCarriesHealthData() async {
        for task in [ChatModel.workoutTask, ChatModel.trainingTask] {
            XCTAssertNil(task.rangeOfCharacter(from: .decimalDigits), task)
        }
    }

    // MARK: - The transcript cap (§8.2, A14)

    private func alternatingTurns(_ count: Int) throws -> [ChatTurn] {
        try (0..<count).map { index in
            try ChatTurn(speaker: index.isMultiple(of: 2) ? .user : .assistant, text: "turn \(index)")
        }
    }

    func testATranscriptWithinTheCapIsReplayedWhole() async throws {
        let all = try alternatingTurns(ChatInstruction.maximumReplayedTurns)
        let instruction = try ChatInstruction(task: "task", factSheet: "sheet", turns: all)

        XCTAssertEqual(instruction.droppedTurnCount, 0)
        XCTAssertEqual(instruction.turns, all)
    }

    /// The cap keeps the *most recent* turns — the ones a question is most likely to
    /// depend on — and drops from the front.
    func testTheCapDropsTheOldestTurns() async throws {
        let all = try alternatingTurns(ChatInstruction.maximumReplayedTurns + 6)
        let instruction = try ChatInstruction(task: "task", factSheet: "sheet", turns: all)

        XCTAssertEqual(instruction.droppedTurnCount, 6)
        XCTAssertEqual(instruction.turns.last, all.last)
        XCTAssertFalse(instruction.turns.contains(all[0]), "the oldest turn is gone")
        XCTAssertFalse(instruction.turns.contains(all[5]), "so are the five after it")
        XCTAssertTrue(instruction.turns.contains(all[6]), "and the window opens on the seventh")
    }

    /// A14's reason for the notice, stated as a test: a model answering confidently as
    /// though it had seen the start of a conversation it did not is worse than one that
    /// says it lost the thread. So when turns are dropped the instruction says so — in
    /// the transcript itself, where nothing downstream has to remember to render it.
    func testDroppedTurnsAreAnnouncedInTheTranscript() async throws {
        let all = try alternatingTurns(ChatInstruction.maximumReplayedTurns + 3)
        let instruction = try ChatInstruction(task: "task", factSheet: "sheet", turns: all)

        let leading = try XCTUnwrap(instruction.turns.first)
        XCTAssertEqual(leading.speaker, .user, "the Messages API needs the user to speak first")
        XCTAssertEqual(leading.text, ChatInstruction.droppedTurnsNotice(3))
        XCTAssertTrue(leading.text.contains("3 turns"), leading.text)
        XCTAssertEqual(
            instruction.turns.count,
            ChatInstruction.maximumReplayedTurns + 1,
            "the notice rides on top of a full window; it does not displace a turn"
        )
    }

    func testNoNoticeIsAddedWhenNothingWasDropped() async throws {
        let instruction = try ChatInstruction(
            task: "task",
            factSheet: "sheet",
            turns: try alternatingTurns(4)
        )
        XCTAssertEqual(instruction.turns.map(\.text), ["turn 0", "turn 1", "turn 2", "turn 3"])
    }

    /// The bound is enforced by the type rather than by the caller remembering: a model
    /// that simply hands over the whole stored thread still cannot send more than the
    /// cap, and the model does exactly that.
    func testALongThreadReachesTheModelCappedAndAnnounced() async throws {
        let threadRepository = FakeChatThreadRepository()
        var thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        // 50 stored turns, so the 51st — the question being asked — pushes 11 off the
        // front of the window.
        for index in 0..<50 {
            thread = try thread.appending(try Fixture.message(
                index.isMultiple(of: 2) ? .user : .assistant,
                "stored turn \(index)",
                at: Double(index + 1)
            ))
        }
        try await threadRepository.store(thread)

        let chatClient = FakeStreamingChatModelInvoking(events: [.text("Answer."), .completed(.endTurn)])
        let (chatModel, _) = try await model(
            threadRepository: threadRepository,
            chatClient: chatClient,
            // Later than every stored turn, so appending the new pair stays in order.
            now: { Fixture.at(1_000) }
        )
        await chatModel.load()
        chatModel.composerText = "And now?"
        await chatModel.send()

        let instruction = try XCTUnwrap(chatClient.receivedInstructions.last)
        XCTAssertEqual(instruction.droppedTurnCount, 11)
        XCTAssertEqual(instruction.turns.count, ChatInstruction.maximumReplayedTurns + 1)
        XCTAssertEqual(instruction.turns.first?.text, ChatInstruction.droppedTurnsNotice(11))
        XCTAssertEqual(instruction.turns.last?.text, "And now?")
        XCTAssertFalse(
            instruction.turns.contains { $0.text == "stored turn 0" },
            "the start of the conversation is not replayed"
        )
    }

    /// The cap trims the conversation and nothing else. The fact sheet is not shortened
    /// alongside it — it is what the answer is built from, and D3 forbids trimming it
    /// here or anywhere.
    func testTheCapNeverTouchesTheFactSheet() async throws {
        let sheet = String(repeating: "fact sheet line\n", count: 200)
        let instruction = try ChatInstruction(
            task: "task",
            factSheet: sheet,
            turns: try alternatingTurns(ChatInstruction.maximumReplayedTurns * 2)
        )
        XCTAssertEqual(instruction.factSheet, sheet)
    }
}
