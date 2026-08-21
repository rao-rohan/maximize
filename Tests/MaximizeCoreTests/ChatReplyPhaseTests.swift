import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-152: the ladder between "the athlete sent a message" and "the reply is complete".
///
/// Every test here is a pure value in, pure value out — no clock, no task, no stream.
/// That is the whole argument for detecting a stall from the transport's own heartbeat
/// rather than from a wall-clock watchdog: the rule is checkable to the beat, on every
/// commit, on a Linux container with no simulator anywhere near it.
final class ChatReplyPhaseTests: XCTestCase {

    private func progress(after events: [ChatReplyEvent]) -> ChatReplyProgress {
        var progress = ChatReplyProgress()
        for event in events {
            progress.apply(event)
        }
        return progress
    }

    private func phase(after events: [ChatReplyEvent]) -> ChatReplyPhase {
        progress(after: events).phase
    }

    private func beats(_ count: Int) -> [ChatReplyEvent] {
        Array(repeating: ChatReplyEvent.heartbeat, count: count)
    }

    /// Beats enough to stall a reply that has shown nothing unusual — the floor, since a
    /// stream with no proven quiet runs has calibrated nothing (MAX-170).
    ///
    /// Read from the type rather than written out, so a change to the policy moves every
    /// test that needs "enough beats" rather than leaving them asserting a stale number.
    private var beatsToStallAnUncalibratedReply: Int {
        ChatReplyProgress().heartbeatsRequiredForStall
    }

    // MARK: - Rung 1: the request is open and nothing has come back

    func testARequestWithNothingBackYetIsTheWaitingState() {
        XCTAssertEqual(phase(after: [.requestOpened]), .awaitingFirstToken)
    }

    func testNothingIsPendingBeforeAnythingIsSent() {
        XCTAssertEqual(ChatReplyProgress().phase, .idle)
    }

    /// A heartbeat before the first token leaves the ladder where it is, however many
    /// arrive. "The model has not started speaking" is what waiting already says
    /// truthfully; calling it a stall would invent a fault out of a model that is
    /// thinking, which is the state the indicator exists for.
    func testHeartbeatsBeforeTheFirstTokenAreStillWaitingNotStalling() {
        let beats = Array(repeating: ChatReplyEvent.heartbeat, count: 6)
        XCTAssertEqual(phase(after: [.requestOpened] + beats), .awaitingFirstToken)
    }

    // MARK: - Rung 2: waiting ends on the first token

    func testTheFirstTokenEndsWaiting() {
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived]), .streaming)
    }

    /// The constraint stated as a property rather than as a case: there is no phase that
    /// means "waiting and streaming at once", so an indicator cannot sit beside the
    /// words it was standing in for.
    func testNoPhaseIsBothWaitingAndStreaming() {
        for phase in Self.everyPhase {
            let isWaiting = phase == .awaitingFirstToken
            let isShowingText = phase == .streaming || phase == .stalled
            XCTAssertFalse(isWaiting && isShowingText, "\(phase)")
        }
    }

    // MARK: - Rung 3: a stall is distinguishable from both

    /// Enough consecutive quiet beats with no token between them, stated by reading the
    /// policy rather than by counting.
    ///
    /// **MAX-170 changed the number this reaches for.** It was `heartbeatsBeforeStall`
    /// used directly as the threshold; it is now that constant acting as the *floor*
    /// under a bar the stream itself can raise. On a reply that has proven nothing the
    /// two are the same, which is the case this test builds.
    func testConsecutiveQuietBeatsMidReplyAreAStall() {
        let quiet = beats(beatsToStallAnUncalibratedReply)
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived] + quiet), .stalled)
    }

    /// One beat is not a stall. The API is documented as free to send a `ping` in the
    /// middle of a perfectly healthy reply — its own streaming examples show one between
    /// two consecutive text deltas — and a threshold of one would flag a working stream
    /// as stuck every time it did.
    ///
    /// Asserted as a bound rather than as equality (MAX-170): the floor's exact value is
    /// a judgement call this test has no business pinning, but "more than one" is the
    /// property that makes the case below meaningful.
    func testASingleQuietBeatMidReplyIsStillStreaming() {
        XCTAssertGreaterThan(ChatReplyProgress.heartbeatsBeforeStall, 1)
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .heartbeat]), .streaming)
    }

    /// The floor is a floor, not the whole rule: nothing a stream does can make it easier
    /// to be called stalled than this (MAX-170).
    func testNoStreamCanLowerTheBarBelowTheFloor() {
        for provenRun in 0...4 {
            let subject = progress(after: [.requestOpened] + beats(provenRun) + [.textArrived])
            XCTAssertGreaterThanOrEqual(
                subject.heartbeatsRequiredForStall,
                ChatReplyProgress.heartbeatsBeforeStall,
                "a proven quiet run of \(provenRun)"
            )
        }
    }

    /// "Consecutive", not "cumulative": beats spread across a long reply that keeps
    /// producing text never add up to a stall.
    func testBeatsSeparatedByTokensDoNotAccumulateIntoAStall() {
        XCTAssertEqual(
            phase(after: [
                .requestOpened, .textArrived,
                .heartbeat, .textArrived,
                .heartbeat, .textArrived,
                .heartbeat, .textArrived,
            ]),
            .streaming
        )
    }

    func testAStalledReplyGoesBackToStreamingWhenTextResumes() {
        let stalling = [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply)
        XCTAssertEqual(phase(after: stalling), .stalled, "the premise")
        XCTAssertEqual(phase(after: stalling + [.textArrived]), .streaming)
    }

    /// The three live rungs are three distinct values — the property that was missing
    /// before this ticket, when all three were `isStreaming == true`.
    func testWaitingStreamingAndStalledAreThreeDistinctStates() {
        let waiting = phase(after: [.requestOpened])
        let streaming = phase(after: [.requestOpened, .textArrived])
        let stalled = phase(
            after: [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply)
        )
        XCTAssertEqual(Set([waiting, streaming, stalled]).count, 3)
        for phase in [waiting, streaming, stalled] {
            XCTAssertTrue(phase.isLive)
            XCTAssertFalse(phase.isTerminal)
        }
    }

    // MARK: - MAX-170: the rule tolerates not knowing the ping cadence

    /// A burst of heartbeats before the first token does not leave a reply primed to
    /// stall the moment it starts speaking.
    ///
    /// This is the shape MAX-152's threshold was most likely to get wrong: a model
    /// thinking for a long time pings its way through the pause, and a rule that counted
    /// those beats toward a stall — or that ignored them and then applied a small fixed
    /// threshold afterwards — would call a reply that is working perfectly well stuck.
    /// Here the pause is *evidence*: the token that ends it proves this connection goes
    /// that quiet while healthy, and the bar moves above it.
    func testABurstOfHeartbeatsBeforeTheFirstTokenDoesNotTripAStallLater() {
        let thinkingPause = ChatReplyProgress.heartbeatsBeforeStall + 3
        let opening: [ChatReplyEvent] = [.requestOpened] + beats(thinkingPause) + [.textArrived]

        // The premise: this run is longer than the floor, so an uncalibrated rule would
        // already be over its threshold on the very next quiet stretch.
        XCTAssertGreaterThan(thinkingPause, ChatReplyProgress.heartbeatsBeforeStall)

        let subject = progress(after: opening)
        XCTAssertEqual(subject.phase, .streaming)
        XCTAssertGreaterThan(subject.heartbeatsRequiredForStall, thinkingPause)
        XCTAssertEqual(phase(after: opening + beats(thinkingPause)), .streaming)
    }

    /// A reply that keeps pausing for as long as it has already paused successfully is
    /// never called stalled, however many beats that is.
    func testAReplyThatKeepsPausingAsLongAsItAlreadyHasNeverStalls() {
        var events: [ChatReplyEvent] = [.requestOpened]
        for run in 1...6 {
            events += beats(run) + [.textArrived]
            XCTAssertEqual(phase(after: events), .streaming, "after a proven run of \(run)")
        }
    }

    /// The bar rises with the stream and the floor never falls — the two halves of "this
    /// tolerates being wrong about the cadence" stated as arithmetic.
    func testTheBarRisesWithWhatTheStreamHasProvenAndNeverFalls() {
        var previous = ChatReplyProgress().heartbeatsRequiredForStall
        for run in 0...8 {
            let subject = progress(after: [.requestOpened] + beats(run) + [.textArrived])
            let bar = subject.heartbeatsRequiredForStall
            XCTAssertGreaterThanOrEqual(bar, previous, "a proven run of \(run)")
            XCTAssertGreaterThan(bar, run, "a proven run must never itself be a stall")
            previous = bar
        }
    }

    /// **The property that keeps the rule honest.** However quiet this stream proved it
    /// gets while healthy, a stream that stops producing text still reaches `.stalled`.
    ///
    /// It holds because calibration only ever moves on a token: once text genuinely
    /// stops, the bar is frozen and the quiet run grows past it. A rule that could be
    /// talked out of ever declaring a stall would be worse than the one it replaced,
    /// because a connection that hangs while still sending pings never trips the client's
    /// byte-level idle timeout either — this rung is the only thing left.
    func testADeadStreamStillReachesStalledWhateverItProved() {
        for provenRun in 0...8 {
            let opening: [ChatReplyEvent] = [.requestOpened] + beats(provenRun) + [.textArrived]
            let bar = progress(after: opening).heartbeatsRequiredForStall
            XCTAssertEqual(
                phase(after: opening + beats(bar)),
                .stalled,
                "a stream that proved a run of \(provenRun) and then died"
            )
        }
    }

    /// A reply that goes quiet long enough to be called stalled, then resumes, then
    /// finishes, ends up complete — and the stall it passed through leaves no trace in
    /// the outcome.
    func testAReplyThatResumesAfterAStallStillCompletes() {
        let stalled = [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply)
        XCTAssertEqual(phase(after: stalled), .stalled, "the premise")

        let resumed = stalled + [.textArrived, .heartbeat, .textArrived]
        XCTAssertEqual(phase(after: resumed), .streaming)
        XCTAssertEqual(phase(after: resumed + [.completed(.endTurn)]), .complete)
    }

    /// Surviving a stall teaches the machine that this connection goes that quiet, so the
    /// same reply is not called stalled again at the same length.
    ///
    /// The withdrawal in `testAStalledReplyGoesBackToStreamingWhenTextResumes` is what
    /// keeps a wrong guess cheap; this is what keeps it from being made twice.
    func testSurvivingAStallRaisesTheBarForTheRestOfTheReply() {
        let survived = [.requestOpened, .textArrived]
            + beats(beatsToStallAnUncalibratedReply)
            + [.textArrived]

        let subject = progress(after: survived)
        XCTAssertEqual(subject.phase, .streaming)
        XCTAssertGreaterThan(subject.heartbeatsRequiredForStall, beatsToStallAnUncalibratedReply)
        XCTAssertEqual(phase(after: survived + beats(beatsToStallAnUncalibratedReply)), .streaming)
    }

    /// Calibration describes one connection, not the API, so a retry starts from the
    /// floor again rather than inheriting what the abandoned attempt happened to show.
    func testARetryForgetsWhatThePreviousStreamProved() {
        let firstAttempt: [ChatReplyEvent] = [.requestOpened]
            + beats(ChatReplyProgress.heartbeatsBeforeStall + 4)
            + [.textArrived, .failed(.interrupted)]

        let retried = progress(after: firstAttempt + [.requestOpened, .textArrived])
        XCTAssertEqual(
            retried.heartbeatsRequiredForStall,
            ChatReplyProgress().heartbeatsRequiredForStall
        )
    }

    func testResetForgetsWhatTheStreamProved() {
        var subject = progress(
            after: [.requestOpened] + beats(ChatReplyProgress.heartbeatsBeforeStall + 4) + [.textArrived]
        )
        subject.reset()
        XCTAssertEqual(
            subject.heartbeatsRequiredForStall,
            ChatReplyProgress().heartbeatsRequiredForStall
        )
    }

    // MARK: - Rung 4: the four ways a reply stops

    func testEndTurnCompletesTheReply() {
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .completed(.endTurn)]), .complete)
    }

    func testMaxTokensIsTruncatedNotComplete() {
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .completed(.truncated)]), .truncated)
    }

    func testAStalledReplyCanStillCompleteNormally() {
        let stalling = [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply)
        XCTAssertEqual(phase(after: stalling), .stalled, "the premise")
        XCTAssertEqual(phase(after: stalling + [.completed(.endTurn)]), .complete)
    }

    func testAFailureCarriesWhichFailureItWas() {
        XCTAssertEqual(
            phase(after: [.requestOpened, .failed(.rateLimited)]),
            .failed(.rateLimited)
        )
    }

    /// `ChatStreamEvent`'s contract forbids a stream ending without a terminal event.
    /// Handled anyway, and named as the failure it actually is rather than left as a
    /// rung the surface has no words for.
    func testAStreamThatJustStopsIsAnInterruption() {
        XCTAssertEqual(
            phase(after: [.requestOpened, .textArrived, .endedWithoutTerminalEvent]),
            .failed(.interrupted)
        )
    }

    func testAReplyWithNoUsableTextIsItsOwnState() {
        XCTAssertEqual(phase(after: [.requestOpened, .producedNoUsableText]), .emptyReply)
    }

    /// The safety net: a stream that reports a clean completion having never delivered a
    /// token cannot be a complete reply, whatever its stop reason claimed. `ChatModel`
    /// reaches the same conclusion from the text it holds, so the two cannot disagree.
    func testCompletingWithoutEverDeliveringATokenIsAnEmptyReply() {
        XCTAssertEqual(phase(after: [.requestOpened, .completed(.endTurn)]), .emptyReply)
    }

    // MARK: - Restarting, and events out of turn

    func testARetryRestartsTheLadderFromTheBottom() {
        XCTAssertEqual(
            phase(after: [.requestOpened, .textArrived, .failed(.interrupted), .requestOpened]),
            .awaitingFirstToken
        )
    }

    /// A restart clears the quiet-beat count too, or the first beat of a retry would
    /// inherit the stall of the attempt before it.
    func testARestartForgetsTheQuietBeatsOfThePreviousAttempt() {
        XCTAssertEqual(
            phase(after: [
                .requestOpened, .textArrived, .heartbeat,
                .failed(.interrupted),
                .requestOpened, .textArrived, .heartbeat,
            ]),
            .streaming
        )
    }

    /// Nothing moves the ladder once a reply has stopped. The transport is not supposed
    /// to say anything after its terminal event, and if it does, the surface does not
    /// start claiming a finished reply is arriving again.
    func testEventsAfterATerminalRungAreIgnored() {
        let after: [ChatReplyEvent] = [.textArrived, .heartbeat, .completed(.endTurn), .failed(.refused)]
        for event in after {
            XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .completed(.endTurn), event]), .complete)
        }
    }

    func testNothingMovesTheLadderBeforeARequestIsOpened() {
        for event in [ChatReplyEvent.textArrived, .heartbeat, .completed(.endTurn), .failed(.refused)] {
            XCTAssertEqual(phase(after: [event]), .idle)
        }
    }

    func testResetPutsTheLadderBackToIdle() {
        var subject = progress(after: [.requestOpened, .textArrived])
        subject.reset()
        XCTAssertEqual(subject.phase, .idle)
    }

    // MARK: - Rung 5: the athlete stopped it (MAX-197)

    /// From every rung a reply can actually be live on. The one that matters most is the
    /// first: a reply that has said nothing yet is exactly the one somebody wants out of.
    func testAStopFromAnyLiveRungLandsOnTheStoppedRung() {
        let live: [(String, [ChatReplyEvent])] = [
            ("waiting", [.requestOpened]),
            ("streaming", [.requestOpened, .textArrived]),
            (
                "stalled",
                [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply)
            ),
        ]
        for (name, opening) in live {
            XCTAssertTrue(phase(after: opening).isLive, name)
            XCTAssertEqual(phase(after: opening + [.stoppedByAthlete]), .stopped, name)
        }
    }

    /// A stop is a tap, and a tap that lands after the reply has already ended changes
    /// nothing. `ChatModel.stop()` refuses at the same boundary; this is the ladder
    /// holding the line whatever a caller does.
    func testAStopAfterAnEndingChangesNothing() {
        let endings: [(String, [ChatReplyEvent])] = [
            ("complete", [.requestOpened, .textArrived, .completed(.endTurn)]),
            ("truncated", [.requestOpened, .textArrived, .completed(.truncated)]),
            ("empty", [.requestOpened, .producedNoUsableText]),
            ("failed", [.requestOpened, .failed(.midStreamFailure)]),
            ("stopped", [.requestOpened, .textArrived, .stoppedByAthlete]),
        ]
        for (name, events) in endings {
            XCTAssertEqual(phase(after: events + [.stoppedByAthlete]), phase(after: events), name)
        }
    }

    /// Nothing that happens on the wire can be reported as a stop. A stream can fall
    /// quiet for as long as it likes — past the stall bar, past any bar — and the rung it
    /// reaches is still `.stalled`, because the only event that produces `.stopped` comes
    /// from a person.
    func testNoAmountOfSilenceIsEverReportedAsAStop() {
        let quiet = phase(after: [.requestOpened, .textArrived] + beats(beatsToStallAnUncalibratedReply * 4))
        XCTAssertEqual(quiet, .stalled)
        XCTAssertNotEqual(quiet, .stopped)
        // And the other endings a quiet stream can reach are still themselves.
        XCTAssertEqual(
            phase(after: [.requestOpened, .textArrived, .endedWithoutTerminalEvent]),
            .failed(.interrupted)
        )
    }

    /// The mirror of the case above: a stall that recovers is a reply again, not a
    /// casualty. MAX-170's calibration is what makes the stall bar move, and a stop must
    /// not be able to ride in on either half of that.
    func testAStallThatRecoversIsStreamingAgainAndNotStopped() {
        let recovered = phase(
            after: [.requestOpened, .textArrived]
                + beats(beatsToStallAnUncalibratedReply)
                + [.textArrived]
        )
        XCTAssertEqual(recovered, .streaming)

        // And the recovery genuinely raised the bar rather than leaving it where it was,
        // so the next quiet run of the same length is not a stall either (MAX-170).
        let afterRecovery = progress(
            after: [.requestOpened, .textArrived]
                + beats(beatsToStallAnUncalibratedReply)
                + [.textArrived]
        )
        XCTAssertGreaterThan(afterRecovery.heartbeatsRequiredForStall, beatsToStallAnUncalibratedReply)
    }

    /// A stop before the request was even opened is not a state this machine invents.
    func testAStopWithNothingInFlightIsIgnored() {
        XCTAssertEqual(phase(after: [.stoppedByAthlete]), .idle)
    }

    /// The rung's own answers, stated rather than inferred from the sweeps below.
    func testTheStoppedRungIsTerminalAndOffersNoRetry() {
        XCTAssertFalse(ChatReplyPhase.stopped.isLive)
        XCTAssertTrue(ChatReplyPhase.stopped.isTerminal)
        XCTAssertFalse(
            ChatReplyPhase.stopped.offersRetry,
            "the athlete ended this one; asking the same question back is the app arguing"
        )
    }

    /// A new request from the stopped rung starts at the bottom like every other, and
    /// takes MAX-170's calibration with it — what the abandoned connection did is not
    /// evidence about this one.
    func testAskingAgainAfterAStopStartsAFreshRequest() {
        let restarted = progress(after: [
            .requestOpened, .textArrived, .stoppedByAthlete, .requestOpened,
        ])
        XCTAssertEqual(restarted.phase, .awaitingFirstToken)
        XCTAssertEqual(restarted.heartbeatsRequiredForStall, beatsToStallAnUncalibratedReply)
    }

    // MARK: - What each rung offers

    func testOnlyTheThreeLiveRungsCountAsInFlight() {
        let live: [ChatReplyPhase] = [.awaitingFirstToken, .streaming, .stalled]
        for phase in Self.everyPhase {
            XCTAssertEqual(phase.isLive, live.contains(phase), "\(phase)")
            // Live and terminal partition the ladder, with `.idle` outside both: a rung
            // that was neither would be one the surface has no rule for.
            XCTAssertNotEqual(phase.isLive, phase.isTerminal || phase == .idle, "\(phase)")
        }
    }

    /// Retry follows `ChatStreamError.isWorthRetrying` rather than re-deciding it, so
    /// there is one answer to "could asking again help" in this app.
    func testRetryIsOfferedForExactlyTheFailuresWorthRetrying() {
        for error in Self.everyStreamError {
            XCTAssertEqual(
                ChatReplyPhase.failed(error).offersRetry,
                error.isWorthRetrying,
                "\(error)"
            )
        }
    }

    func testAnEmptyReplyIsWorthAskingAgainAndACompletedOneIsNot() {
        XCTAssertTrue(ChatReplyPhase.emptyReply.offersRetry)
        XCTAssertFalse(ChatReplyPhase.complete.offersRetry)
        XCTAssertFalse(ChatReplyPhase.truncated.offersRetry)
        XCTAssertFalse(ChatReplyPhase.idle.offersRetry)
    }

    /// Nothing in flight offers a retry: there is nothing to retry yet, and a button
    /// that cancelled and re-asked mid-reply would spend a call to lose an answer that
    /// was arriving.
    func testNoLiveRungOffersARetry() {
        for phase in Self.everyPhase where phase.isLive {
            XCTAssertFalse(phase.offersRetry, "\(phase)")
        }
    }

    // MARK: - Every rung has words

    /// The waiting state's visible sentence exists, and it is the thing the animation is
    /// drawn over rather than a caption beside it. A shimmer with no words underneath is
    /// a state that disappears the moment somebody turns animation off.
    func testWaitingAndStalledEachHaveTheirOwnVisibleSentence() {
        let waiting = ChatConversationCopy.pendingStatus(for: .awaitingFirstToken)
        let stalled = ChatConversationCopy.pendingStatus(for: .stalled)
        XCTAssertEqual(waiting, ChatConversationCopy.awaitingFirstReply)
        XCTAssertEqual(stalled, ChatConversationCopy.replyStalled)
        XCTAssertNotEqual(waiting, stalled)
        for text in [waiting, stalled] {
            XCTAssertFalse(text?.isEmpty ?? true)
        }
    }

    /// Rung 2 has no visible status on purpose: once the first token lands, the words on
    /// screen say everything a status line could, and an indicator beside them is the app
    /// talking over its own answer.
    func testStreamingHasNoVisibleStatusBecauseTheReplyIsTheStatus() {
        XCTAssertNil(ChatConversationCopy.pendingStatus(for: .streaming))
    }

    func testNoTerminalRungCarriesAPendingStatus() {
        for phase in Self.everyPhase where !phase.isLive {
            XCTAssertNil(ChatConversationCopy.pendingStatus(for: phase), "\(phase)")
        }
    }

    /// Every live rung is spoken, including the one with no visible status: somebody who
    /// cannot see text arriving still needs to be told that it is.
    func testEveryLiveRungIsSpokenAndNoTerminalRungIs() {
        var spoken: Set<String> = []
        for phase in Self.everyPhase {
            let announcement = ChatConversationCopy.pendingAccessibilityLabel(for: phase)
            if phase.isLive {
                XCTAssertNotNil(announcement, "\(phase)")
                XCTAssertFalse(announcement?.isEmpty ?? true, "\(phase)")
                if let announcement { spoken.insert(announcement) }
            } else {
                XCTAssertNil(announcement, "\(phase)")
            }
        }
        XCTAssertEqual(spoken.count, 3, "the three live rungs are three different sentences")
    }

    func testTheRetryActionAndItsHintAreWorded() {
        XCTAssertFalse(ChatConversationCopy.retryAction.isEmpty)
        XCTAssertFalse(ChatConversationCopy.retryActionHint.isEmpty)
        XCTAssertNotEqual(ChatConversationCopy.retryAction, ChatConversationCopy.retryActionHint)
    }

    // MARK: - Fixtures

    /// Every rung, written out rather than derived, so adding one to `ChatReplyPhase`
    /// without deciding what it looks like, says and offers is a failing test rather
    /// than a silent gap.
    static let everyPhase: [ChatReplyPhase] = [
        .idle,
        .awaitingFirstToken,
        .streaming,
        .stalled,
        .complete,
        .truncated,
        .emptyReply,
        .stopped,
        .failed(.interrupted),
    ]

    /// Every `ChatStreamError`, for the same reason. `serverUnavailable` and
    /// `unexpectedStatus` carry a status code; the numbers below are arbitrary and are
    /// never expected to appear in anything a person reads.
    static let everyStreamError: [ChatStreamError] = [
        .noAPIKeyStored,
        .keyStoreUnavailable,
        .requestFailed,
        .timedOut,
        .invalidAPIKey,
        .rateLimited,
        .serverUnavailable(statusCode: 503),
        .unexpectedStatus(400),
        .refused,
        .interrupted,
        .midStreamFailure,
        .unreadableResponse,
    ]
}
