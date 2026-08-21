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
        // MAX-195: a clean completion has nothing to caption, and the roles this reply
        // is actually made of are exactly the ones `ChatMessageRendering` says get
        // which treatment — asked of the messages `send()` produced, not of a
        // `DisplayMessage` built for the assertion.
        XCTAssertNil(model.messages[1].trailingCaption)
        XCTAssertFalse(ChatMessageRendering.isMarkdown(for: model.messages[0].kind), "the athlete's own turn")
        XCTAssertTrue(ChatMessageRendering.isMarkdown(for: model.messages[1].kind), "the model's own reply")
    }

    func testATruncatedReplyLandsOnItsOwnRungAndIsStillStored() async throws {
        let (model, _, threads) = try await readyModel(
            events: [.text("A long answer…"), .completed(.truncated)]
        )
        await ask(model)

        XCTAssertEqual(model.replyPhase, .truncated)
        XCTAssertTrue(model.messages.last?.wasTruncated ?? false)
        XCTAssertEqual(threads.writes, 1, "a truncated reply is real and storable")
        // MAX-195: the folded caption, read off the row `send()` actually produced.
        XCTAssertEqual(model.messages.last?.trailingCaption, ChatConversationCopy.truncatedCaption)
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
            // MAX-195: app copy is never Markdown-eligible, whichever failure produced it.
            XCTAssertFalse(ChatMessageRendering.isMarkdown(for: notice.kind), "\(error)")
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
        // MAX-195
        XCTAssertEqual(model.messages[1].trailingCaption, ChatConversationCopy.interruptedByFailureCaption)
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

    // MARK: - MAX-197: stopping a reply in flight

    /// Sends a question and stops the reply immediately before the stream's `index`-th
    /// event is produced.
    ///
    /// The fake produces one event per read, so a hook that runs before event *n* runs
    /// after events *0..n-1* have been consumed in full — which is what puts the tap
    /// between two frames of a live stream deterministically, with no sleeping, no
    /// polling and no second task racing the first.
    private func askAndStop(
        _ model: ChatModel,
        _ client: FakeStreamingChatModelInvoking,
        beforeEvent index: Int,
        sampling probe: StreamProbe? = nil
    ) async {
        client.beforeEachEvent = { [weak model] produced in
            guard let model else { return }
            probe?.sample(model)
            guard produced == index else { return }
            model.stop()
        }
        await ask(model)
    }

    /// The decision this ticket is mostly about: what happens to a reply that was
    /// half-read when the athlete ended it.
    func testStoppingMidReplyKeepsWhatArrivedAndPersistsNothing() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("Your drift was "),
            .text("under three percent."),
            .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(
            model.messages[1].text,
            "Your drift was ",
            "what is kept is exactly what was on screen when the tap landed"
        )
        XCTAssertTrue(model.messages[1].wasStoppedByAthlete)
        XCTAssertFalse(model.messages[1].wasInterruptedByFailure, "nothing failed")
        XCTAssertFalse(model.messages[1].wasTruncated, "stopped is not cut short")
        XCTAssertEqual(threads.writes, 0, "a stopped turn is never written")
        XCTAssertEqual(model.streamingText, "")
        // MAX-195
        XCTAssertEqual(model.messages[1].trailingCaption, ChatConversationCopy.stoppedByAthleteCaption)
    }

    /// The absence case: stopped before one token arrived, so there is no bubble for a
    /// caption to sit under and the app says what happened instead of leaving a blank.
    func testStoppingBeforeAnyTextArrivesSaysSoRatherThanShowingNothing() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("Nothing of this arrives."),
            .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 0)

        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .notice])
        XCTAssertEqual(model.messages.last?.text, ChatConversationCopy.stoppedBeforeAnyReplyArrived)
        XCTAssertEqual(threads.writes, 0)
    }

    /// D6: whatever a stop leaves behind has to round-trip. It does, by leaving the store
    /// exactly as it was — an earlier completed turn is still there and the stopped one
    /// was never written, so a reload shows a transcript with no gap in it.
    func testAStopLeavesAThreadTheLoaderReadsBackWithoutTheStoppedTurn() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("First answer."), .completed(.endTurn),
        ])
        await ask(model, "First question?")
        XCTAssertEqual(threads.writes, 1)

        client.events = [.text("Second, "), .text("interrupted."), .completed(.endTurn)]
        await askAndStop(model, client, beforeEvent: 1)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant, .user, .assistant])

        await model.load()

        XCTAssertEqual(model.loadState, .ready)
        XCTAssertEqual(model.replyPhase, .idle)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(model.messages.map(\.text), ["First question?", "First answer."])
        XCTAssertEqual(threads.writes, 1, "the stop wrote nothing, so the store never moved")
        XCTAssertEqual(model.thread?.visibleMessages.count, 2)
    }

    /// Every reader of `isStreaming` settles, and it settles the way a finished turn
    /// does: the composer is a composer again, the stop is withdrawn, and nothing offers
    /// to ask the question the athlete just ended.
    func testAStopSettlesEveryReaderOfIsStreaming() async throws {
        let (model, client, _) = try await readyModel(events: [
            .text("Half an answer"), .text(" and the rest."), .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        XCTAssertFalse(model.isStreaming)
        XCTAssertFalse(model.canStop)
        XCTAssertEqual(model.replyCancellation, .unavailable)
        XCTAssertFalse(model.canRetry, "the athlete ended this one; the app does not re-offer it")
        XCTAssertTrue(
            model.thread?.visibleMessages.isEmpty ?? false,
            "nothing to draft a plan from either: the stopped turn never reached the thread"
        )

        model.composerText = "And the cadence?"
        XCTAssertTrue(model.canSend)
        XCTAssertEqual(
            ChatComposerSendControl.resolve(
                canSend: model.canSend,
                replyPhase: model.replyPhase,
                cancellation: model.replyCancellation
            ),
            .send
        )
    }

    /// The stop is offered for exactly as long as there is something to stop, and the
    /// composer says so in the control it draws. Sampled from inside the live stream,
    /// because "what the composer showed while the reply was arriving" cannot be seen
    /// from either side of an awaited `send()`.
    func testTheStopIsOfferedForExactlyAsLongAsAReplyIsInFlight() async throws {
        let (model, client, _) = try await readyModel(events: [
            .text("A"), .heartbeat, .text("B"), .completed(.endTurn),
        ])
        XCTAssertFalse(model.canStop, "nothing in flight before anything is sent")
        XCTAssertEqual(model.replyCancellation, .unavailable)

        let probe = StreamProbe()
        client.beforeEachEvent = { [weak model] _ in
            guard let model else { return }
            probe.sample(model)
        }
        await ask(model)

        let stopThroughout: [ChatComposerSendControl] = [.stop, .stop, .stop, .stop]
        XCTAssertEqual(probe.controls, stopThroughout, "one sample per event, all four live")
        XCTAssertTrue(probe.canStop.allSatisfy({ $0 }))
        XCTAssertFalse(model.canStop, "and it is withdrawn the moment the reply lands")
        XCTAssertEqual(model.replyPhase, .complete)
    }

    /// A tap that lands after the reply has already finished is not a stop. The reply is
    /// whole, it is written, and nothing about it changes.
    func testAStopAfterTheReplyLandedChangesNothing() async throws {
        let (model, _, threads) = try await readyModel(events: [
            .text("All of it."), .completed(.endTurn),
        ])
        await ask(model)
        XCTAssertEqual(model.replyPhase, .complete)

        model.stop()

        XCTAssertEqual(model.replyPhase, .complete)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertFalse(model.messages[1].wasStoppedByAthlete)
        XCTAssertEqual(threads.writes, 1, "a late tap cannot unwrite a stored reply")
    }

    /// The other side of that boundary, and the reason the rule is "was the reply live
    /// when the tap landed" rather than "did a terminal event arrive first": a stop
    /// accepted while the reply was still live ends the turn as stopped even though the
    /// stream had a completion waiting behind it. The button means what it says.
    func testAStopAcceptedBeforeTheTerminalEventEndsTheTurnAsStopped() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("The whole answer."), .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertTrue(model.messages[1].wasStoppedByAthlete)
        XCTAssertEqual(threads.writes, 0)
    }

    /// A stop is not a stall, at the seam as well as in the ladder. The reply reaches
    /// `.stalled` first — the connection is open and quiet — and what the transcript says
    /// afterwards is that the athlete stopped it, not that anything went wrong.
    func testAStalledReplyThatIsStoppedReadsAsStoppedNotAsAFailure() async throws {
        let quietBeats = ChatReplyProgress().heartbeatsRequiredForStall
        let (model, client, threads) = try await readyModel(
            events: [.text("Half a thought")]
                + Array(repeating: ChatStreamEvent.heartbeat, count: quietBeats)
                + [.text(" finished later."), .completed(.endTurn)]
        )

        let probe = StreamProbe()
        // One past the last heartbeat: by then every beat has been folded in, so the
        // reply is genuinely on the stalled rung when the tap lands.
        await askAndStop(model, client, beforeEvent: quietBeats + 1, sampling: probe)

        XCTAssertEqual(probe.phases.last, .stalled, "the reply had stalled before it was stopped")
        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertEqual(model.messages[1].text, "Half a thought")
        XCTAssertTrue(model.messages[1].wasStoppedByAthlete)
        XCTAssertEqual(threads.writes, 0)
    }

    /// The failure the transport would have reported never reaches the transcript,
    /// because the athlete had already ended the turn. A stop must not be dressed up as a
    /// dropped connection, and a dropped connection must not be swallowed by a stop.
    func testAStopIsNeverReportedAsAnInterruption() async throws {
        let (model, client, _) = try await readyModel(events: [
            .text("Half a thought"), .failed(.interrupted),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertEqual(model.messages.map(\.kind), [.user, .assistant])
        XCTAssertFalse(
            model.messages.contains(where: { $0.kind == .notice }),
            "nothing failed, so the transcript carries no failure notice"
        )
    }

    /// A14: stopping spends no call and starts none. The one thing this app must never do
    /// is decide by itself to talk to the model again.
    func testStoppingNeverAsksAgainOnItsOwn() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("Half"), .text(" the answer."), .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        XCTAssertEqual(client.callCount, 1)
        XCTAssertFalse(model.canRetry)

        // And a view forwarding the tap anyway gets nothing, the same way it does for
        // every other rung that offers no retry.
        await model.retry()

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(model.replyPhase, .stopped)
        XCTAssertEqual(threads.writes, 0)
    }

    /// The question after a stop is asked on its own. The stopped pair was never
    /// persisted, so the thread the next instruction is built from has never heard of
    /// it — which is also what keeps a half-sentence from being replayed to the model as
    /// something it said in full.
    func testTheQuestionAfterAStopIsAskedWithoutTheStoppedTurn() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("Half"), .text(" the answer."), .completed(.endTurn),
        ])
        await askAndStop(model, client, beforeEvent: 1)

        client.beforeEachEvent = nil
        client.events = [.text("A whole answer."), .completed(.endTurn)]
        await ask(model, "Second question?")

        XCTAssertEqual(model.replyPhase, .complete)
        let second = try XCTUnwrap(client.receivedInstructions.last)
        XCTAssertEqual(second.turns.map(\.text), ["Second question?"])
        XCTAssertEqual(threads.writes, 1, "only the turn that finished is on disk")
        XCTAssertEqual(
            model.thread?.visibleMessages.map(\.content),
            ["Second question?", "A whole answer."]
        )
    }

    func testStopBeforeAnythingIsSentIsANoOp() async throws {
        let (model, client, threads) = try await readyModel(events: [
            .text("Untouched."), .completed(.endTurn),
        ])

        model.stop()

        XCTAssertEqual(model.replyPhase, .idle)
        XCTAssertFalse(model.canStop)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(threads.writes, 0)
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
/// Samples what the surface looked like from *inside* a live stream (MAX-197).
///
/// Mid-stream state is invisible from either side of an awaited `send()` — the test is
/// suspended for exactly as long as the reply is arriving — so the assertions that matter
/// most here are gathered as the stream runs and read afterwards. `@MainActor` because
/// everything it touches is, which is also what lets the fake's hook hold one.
@MainActor
private final class StreamProbe {
    private(set) var phases: [ChatReplyPhase] = []
    private(set) var controls: [ChatComposerSendControl] = []
    private(set) var canStop: [Bool] = []

    func sample(_ model: ChatModel) {
        phases.append(model.replyPhase)
        canStop.append(model.canStop)
        controls.append(
            .resolve(
                canSend: model.canSend,
                replyPhase: model.replyPhase,
                cancellation: model.replyCancellation
            )
        )
    }
}
