import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// MAX-152, at the seam: `ChatModel` feeding the ladder from a real stream, and the
/// retry that hangs off its failure rungs.
///
/// `ChatReplyPhaseTests` owns the transitions themselves — which event lands on which
/// rung — because those are a pure function and belong tested as one. What is left here
/// is wiring: that a stream of `ChatStreamEvent`s produces the rung the ladder says it
/// should, that each failure reaches the transcript in `ChatFailureNotice`'s words rather
/// than a diagnostic's, and that "Try again" asks the same question once per tap and
/// never on its own.
@MainActor
final class ChatReplyLadderModelTests: XCTestCase {

    // MARK: - Fixtures
    //
    // Mirrors `ChatModelTests`' own, deliberately: a second suite over the same view
    // model should stand the model up the same way, or a difference in behaviour becomes
    // a difference in scaffolding.

    private let utc = TimeZone(identifier: "UTC") ?? .current

    private func metrics() throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            averageCadenceStepsPerMinute: 167,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 3_000)]),
            planVersion: PlanVersion(1)
        )
    }

    private func readyStore() async throws -> InMemoryWorkoutStore {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        try await store.store(Fixture.workout())
        try await store.store(try metrics())
        store.seedScore(try Fixture.score(points: 88))
        return store
    }

    private func readyModel(
        events: [ChatStreamEvent],
        threadRepository: FakeChatThreadRepository = FakeChatThreadRepository()
    ) async throws -> (ChatModel, FakeStreamingChatModelInvoking, FakeChatThreadRepository) {
        let store = try await readyStore()
        let chatClient = FakeStreamingChatModelInvoking(events: events)
        let chatModel = ChatModel(
            subject: .workout(Fixture.workoutID),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: threadRepository,
            chatClient: chatClient,
            timeZone: utc,
            now: { Fixture.epoch }
        )
        await chatModel.load()
        XCTAssertEqual(chatModel.loadState, .ready)
        return (chatModel, chatClient, threadRepository)
    }

    private func ask(_ model: ChatModel, _ question: String = "Was that on plan?") async {
        model.composerText = question
        await model.send()
    }

    // MARK: - Where a stream leaves the ladder

    func testNothingIsPendingUntilSomethingIsSent() async throws {
        let (model, _, _) = try await readyModel(events: [.text("Hi."), .completed(.endTurn)])
        XCTAssertEqual(model.replyPhase, .idle)
        XCTAssertFalse(model.isStreaming)
        XCTAssertFalse(model.canRetry)
    }

    func testACompletedReplyLandsOnTheCompleteRung() async throws {
        let (model, _, threads) = try await readyModel(
            events: [.text("You held "), .text("the cap."), .completed(.endTurn)]
        )
        await ask(model)

        XCTAssertEqual(model.replyPhase, .complete)
        XCTAssertFalse(model.isStreaming)
        XCTAssertEqual(model.streamingText, "")
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(threads.writes, 1)
    }

    func testATruncatedReplyLandsOnItsOwnRungAndIsStillStored() async throws {
        let (model, _, threads) = try await readyModel(
            events: [.text("A long answer…"), .completed(.truncated)]
        )
        await ask(model)

        XCTAssertEqual(model.replyPhase, .truncated)
        XCTAssertTrue(model.messages.last?.wasTruncated ?? false)
        XCTAssertEqual(threads.writes, 1, "a truncated reply is real and storable")
    }

    /// Heartbeats are consumed by the ladder and are not text, not a terminal event, and
    /// not something that can corrupt a reply passing through them.
    func testHeartbeatsMidReplyDoNotBecomePartOfTheAnswer() async throws {
        let (model, _, _) = try await readyModel(events: [
            .text("Yes"), .heartbeat, .heartbeat, .text(", comfortably."), .completed(.endTurn),
        ])
        await ask(model)

        XCTAssertEqual(model.replyPhase, .complete)
        XCTAssertEqual(model.messages.last?.text, "Yes, comfortably.")
    }

    /// The failure that happened, carried on the rung rather than flattened into "it
    /// broke" — which is what makes the surface able to say which one it was.
    func testAFailedStreamCarriesWhichFailureItWas() async throws {
        let (model, _, threads) = try await readyModel(events: [.failed(.rateLimited)])
        await ask(model)

        XCTAssertEqual(model.replyPhase, .failed(.rateLimited))
        XCTAssertEqual(threads.writes, 0)
    }

    /// The words in the transcript are `ChatFailureNotice`'s, not
    /// `ChatStreamError.description`'s. This is the regression that matters most: the
    /// sentence the owner hit on a device came from the latter.
    func testAFailureReachesTheTranscriptInTheNoticesWordsNotTheDiagnostics() async throws {
        for error in ChatReplyPhaseTests.everyStreamError {
            let (model, _, _) = try await readyModel(events: [.failed(error)])
            await ask(model)

            let notice = try XCTUnwrap(model.messages.last)
            XCTAssertEqual(notice.kind, .notice)
            XCTAssertEqual(
                notice.text,
                ChatFailureNotice.notice(for: error, subject: .workout).message,
                "\(error)"
            )
            XCTAssertNotEqual(notice.text, error.description, "\(error)")
        }
    }

    /// Constraint #4, restated against the ladder: partial text survives, on screen,
    /// flagged as unfinished, and the rung says the connection is what stopped it.
    func testAPartialReplySurvivesAFailureAndIsNotPresentedAsComplete() async throws {
        let (model, _, threads) = try await readyModel(
            events: [.text("Your drift was"), .failed(.interrupted)]
        )
        await ask(model)

        XCTAssertEqual(model.replyPhase, .failed(.interrupted))
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant, .notice])
        XCTAssertEqual(model.messages[1].text, "Your drift was")
        XCTAssertTrue(model.messages[1].wasInterruptedByFailure)
        XCTAssertFalse(model.messages[1].wasTruncated, "unfinished is not the same as cut short")
        XCTAssertEqual(threads.writes, 0, "a partial reply is never persisted")
    }

    /// A stream that stops without a terminal event is forbidden by `ChatStreamEvent`'s
    /// contract and handled anyway — as the interruption it would be, with the same words
    /// a real interruption gets.
    func testAStreamThatJustStopsIsReportedAsAnInterruption() async throws {
        let (model, _, _) = try await readyModel(events: [.text("Half a thought")])
        await ask(model)

        XCTAssertEqual(model.replyPhase, .failed(.interrupted))
        XCTAssertEqual(
            model.messages.last?.text,
            ChatFailureNotice.notice(for: .interrupted, subject: .workout).message
        )
    }

    /// The request worked and produced nothing. Neither a dropped connection nor an
    /// answer, and it says so in its own words.
    func testAnEmptyReplyIsItsOwnRungAndItsOwnSentence() async throws {
        let (model, _, threads) = try await readyModel(events: [.completed(.endTurn)])
        await ask(model)

        XCTAssertEqual(model.replyPhase, .emptyReply)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .notice])
        XCTAssertEqual(model.messages.last?.text, ChatFailureNotice.emptyReply.message)
        XCTAssertEqual(threads.writes, 0)
    }

    /// The reply is real, the write is not. It stays on screen, and the notice says what
    /// becomes of it rather than leaving the transcript and the store to disagree
    /// silently.
    func testAReplyThatCouldNotBeSavedStaysOnScreenAndSaysSo() async throws {
        let threads = FakeChatThreadRepository()
        let (model, _, _) = try await readyModel(
            events: [.text("Saved nowhere."), .completed(.endTurn)],
            threadRepository: threads
        )
        struct Boom: Error {}
        threads.failWrites(with: Boom())
        await ask(model)

        XCTAssertEqual(model.replyPhase, .complete)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant, .notice])
        XCTAssertEqual(model.messages[1].text, "Saved nowhere.")
        XCTAssertEqual(model.messages.last?.text, ChatFailureNotice.couldNotSaveReply.message)
        XCTAssertFalse(model.canRetry, "asking Claude again cannot fix a local write")
    }

    // MARK: - `isStreaming` is the ladder, not a second flag

    func testIsStreamingIsExactlyWhetherTheRungIsLive() async throws {
        let (model, _, _) = try await readyModel(events: [.text("Done."), .completed(.endTurn)])
        XCTAssertEqual(model.isStreaming, model.replyPhase.isLive)
        await ask(model)
        XCTAssertEqual(model.isStreaming, model.replyPhase.isLive)
        XCTAssertFalse(model.isStreaming, "never a spinner that never resolves")
        // And the composer is usable again, which is what the flag actually gates.
        model.composerText = "And the cadence?"
        XCTAssertTrue(model.canSend)
    }

    // MARK: - Retry: a button, never a policy

    func testATransientFailureOffersARetryAndAPermanentOneDoesNot() async throws {
        let (transient, _, _) = try await readyModel(events: [.failed(.requestFailed)])
        await ask(transient)
        XCTAssertTrue(transient.canRetry)

        let (permanent, _, _) = try await readyModel(events: [.failed(.noAPIKeyStored)])
        await ask(permanent)
        XCTAssertFalse(permanent.canRetry, "there is nothing to retry until a key is added")
    }

    func testASuccessfulReplyLeavesNothingToRetry() async throws {
        let (model, _, _) = try await readyModel(events: [.text("All good."), .completed(.endTurn)])
        await ask(model)
        XCTAssertFalse(model.canRetry)
    }

    /// One tap, one call — and the failed attempt is not spent again by anything but a
    /// tap. Nothing in `send()` or `load()` re-asks on its own (A14).
    func testNothingRetriesWithoutBeingAsked() async throws {
        let (model, client, _) = try await readyModel(events: [.failed(.requestFailed)])
        await ask(model)

        XCTAssertEqual(client.callCount, 1, "one call per tap, and the tap has happened once")
        await model.load()
        XCTAssertEqual(client.callCount, 1, "a reload reads storage; it never streams")
    }

    /// The retry asks the *same* question, without a second question bubble and without
    /// replaying the dropped attempt into the instruction — the failed turn was never
    /// persisted, so the history it is asked against has not moved.
    func testRetryAsksTheSameQuestionAgainAndStoresTheAnswerThatArrives() async throws {
        let threads = FakeChatThreadRepository()
        let (model, client, _) = try await readyModel(
            events: [.text("Your drift "), .failed(.interrupted)],
            threadRepository: threads
        )
        await ask(model, "Did my drift flatten?")
        XCTAssertTrue(model.canRetry)

        client.events = [.text("Yes — it flattened after week two."), .completed(.endTurn)]
        await model.retry()

        XCTAssertEqual(client.callCount, 2)
        XCTAssertEqual(
            client.receivedInstructions.map { $0.turns.map(\.text) },
            [["Did my drift flatten?"], ["Did my drift flatten?"]],
            "the same question, asked from the same history"
        )
        XCTAssertEqual(model.replyPhase, .complete)
        XCTAssertFalse(model.canRetry, "the question has an answer now")

        // Nothing is erased: the dropped attempt and its notice stay above the answer,
        // because they happened. Only the completed pair reaches disk.
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant, .notice, .assistant])
        XCTAssertEqual(model.messages.filter { $0.kind == .user }.count, 1, "one question, asked once")
        XCTAssertEqual(threads.writes, 1)
        let stored = try XCTUnwrap(threads.allThreads.first)
        XCTAssertEqual(
            stored.visibleMessages.map(\.content),
            ["Did my drift flatten?", "Yes — it flattened after week two."]
        )
    }

    /// A retry that fails again is still just a failure — it does not escalate, and it
    /// does not start asking on its own.
    func testARetryThatFailsAgainStaysARetryableFailureWithoutRetryingItself() async throws {
        let (model, client, _) = try await readyModel(events: [.failed(.serverUnavailable(statusCode: 503))])
        await ask(model)
        await model.retry()

        XCTAssertEqual(client.callCount, 2, "exactly one call per tap, and there were two taps")
        XCTAssertEqual(model.replyPhase, .failed(.serverUnavailable(statusCode: 503)))
        XCTAssertTrue(model.canRetry)
    }

    func testRetryIsANoOpWhenItIsNotOffered() async throws {
        let (model, client, _) = try await readyModel(events: [.failed(.refused)])
        await ask(model)
        let messagesAfterFailure = model.messages.count

        await model.retry()

        XCTAssertEqual(client.callCount, 1, "a refusal is not asked again")
        XCTAssertEqual(model.messages.count, messagesAfterFailure)
    }

    func testRetryIsANoOpBeforeAnythingHasBeenSent() async throws {
        let (model, client, _) = try await readyModel(events: [.text("Hi."), .completed(.endTurn)])
        await model.retry()
        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(model.replyPhase, .idle)
    }

    // MARK: - A reload abandons the request it described

    func testAReloadClearsTheLadderAndWithdrawsTheRetryOffer() async throws {
        let (model, _, _) = try await readyModel(events: [.text("Half"), .failed(.interrupted)])
        await ask(model)
        XCTAssertTrue(model.canRetry)

        await model.load()

        XCTAssertEqual(model.replyPhase, .idle)
        XCTAssertFalse(model.canRetry, "the question it would ask again is no longer in the transcript")
        XCTAssertEqual(model.streamingText, "")
    }
}
