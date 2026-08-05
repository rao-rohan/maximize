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

    /// Two quiet beats with no token between them, which is `heartbeatsBeforeStall`
    /// stated by name rather than by counting to two.
    func testConsecutiveQuietBeatsMidReplyAreAStall() {
        let beats = Array(
            repeating: ChatReplyEvent.heartbeat,
            count: ChatReplyProgress.heartbeatsBeforeStall
        )
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived] + beats), .stalled)
    }

    /// One beat is not a stall. The API is free to send a `ping` in the middle of a
    /// perfectly healthy reply, and a threshold of one would flag a working stream as
    /// stuck every time it did.
    func testASingleQuietBeatMidReplyIsStillStreaming() {
        XCTAssertEqual(ChatReplyProgress.heartbeatsBeforeStall, 2, "the test below assumes it")
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .heartbeat]), .streaming)
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
        XCTAssertEqual(
            phase(after: [.requestOpened, .textArrived, .heartbeat, .heartbeat, .textArrived]),
            .streaming
        )
    }

    /// The three live rungs are three distinct values — the property that was missing
    /// before this ticket, when all three were `isStreaming == true`.
    func testWaitingStreamingAndStalledAreThreeDistinctStates() {
        let waiting = phase(after: [.requestOpened])
        let streaming = phase(after: [.requestOpened, .textArrived])
        let stalled = phase(after: [.requestOpened, .textArrived, .heartbeat, .heartbeat])
        XCTAssertEqual(Set([waiting, streaming, stalled]).count, 3)
        for phase in [waiting, streaming, stalled] {
            XCTAssertTrue(phase.isLive)
            XCTAssertFalse(phase.isTerminal)
        }
    }

    // MARK: - Rung 4: the four ways a reply stops

    func testEndTurnCompletesTheReply() {
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .completed(.endTurn)]), .complete)
    }

    func testMaxTokensIsTruncatedNotComplete() {
        XCTAssertEqual(phase(after: [.requestOpened, .textArrived, .completed(.truncated)]), .truncated)
    }

    func testAStalledReplyCanStillCompleteNormally() {
        XCTAssertEqual(
            phase(after: [.requestOpened, .textArrived, .heartbeat, .heartbeat, .completed(.endTurn)]),
            .complete
        )
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
