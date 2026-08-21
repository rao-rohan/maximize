import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-153: what the composer's trailing control is, in each state a person reaches.
///
/// The control is one 44pt box that means four different things. None of those meanings
/// is decidable by looking at a screenshot — "is that send button disabled or is it the
/// tint I chose?" — so all four are asserted here instead.
final class ChatComposerSendControlTests: XCTestCase {

    // MARK: - Resolution

    func testSomethingToSendOnAReadyThreadIsASendButton() {
        XCTAssertEqual(ChatComposerSendControl.resolve(canSend: true, isStreaming: false), .send)
    }

    func testAnEmptyOrUnreadyComposerIsDimmedRatherThanHidden() {
        XCTAssertEqual(ChatComposerSendControl.resolve(canSend: false, isStreaming: false), .unavailable)
    }

    /// The honest default while the app has no cancellation: a reply is arriving and
    /// nothing can stop it, so the control shows progress rather than a stop the athlete
    /// would tap once and never trust again.
    func testAStreamingReplyWithoutCancellationShowsProgressNotAStop() {
        let control = ChatComposerSendControl.resolve(canSend: false, isStreaming: true)
        XCTAssertEqual(control, .awaitingReply)
        XCTAssertTrue(control.showsActivity)
        XCTAssertNil(control.systemImageName)
        XCTAssertFalse(control.isEnabled)
    }

    /// The seam MAX-152 fills. One call site changes and the control becomes a stop
    /// button that is already sized, labelled and hinted.
    func testAStreamingReplyWithCancellationOffersAStop() {
        let control = ChatComposerSendControl.resolve(
            canSend: false,
            isStreaming: true,
            cancellation: .available
        )
        XCTAssertEqual(control, .stop)
        XCTAssertTrue(control.isEnabled)
        XCTAssertFalse(control.showsActivity)
        XCTAssertEqual(control.systemImageName, "stop.circle.fill")
    }

    /// Streaming outranks `canSend` unconditionally. `canSend` is already false mid-stream
    /// today; this is the guard against a future edit loosening it and putting a live send
    /// button next to an arriving reply.
    func testStreamingOutranksCanSend() {
        XCTAssertEqual(ChatComposerSendControl.resolve(canSend: true, isStreaming: true), .awaitingReply)
        XCTAssertEqual(
            ChatComposerSendControl.resolve(canSend: true, isStreaming: true, cancellation: .available),
            .stop
        )
    }

    // MARK: - Reading MAX-152's ladder rather than a flag

    /// A reply that has been stopped is not a reply in flight, so offering cancellation
    /// does not keep the stop button on screen (MAX-197). The composer goes back to being
    /// a composer the moment the turn ends, however it ended.
    func testAStoppedReplyLeavesTheControlBackOnSendEvenWithCancellationAvailable() {
        XCTAssertEqual(
            ChatComposerSendControl.resolve(
                canSend: true,
                replyPhase: .stopped,
                cancellation: .available
            ),
            .send
        )
        XCTAssertEqual(
            ChatComposerSendControl.resolve(
                canSend: false,
                replyPhase: .stopped,
                cancellation: .available
            ),
            .unavailable
        )
    }

    /// The three live rungs are one fact to the send control: a request is open. They are
    /// three different things to say in the *transcript*, and `ChatPendingReplyView` is
    /// where they are said — the composer narrating them a second time, six inches away,
    /// would be the app talking over itself.
    func testEveryLiveRungOfTheReplyLadderIsTheSameControl() {
        for phase in [ChatReplyPhase.awaitingFirstToken, .streaming, .stalled] {
            XCTAssertEqual(
                ChatComposerSendControl.resolve(canSend: false, replyPhase: phase),
                .awaitingReply,
                "\(phase)"
            )
        }
    }

    func testEveryTerminalRungLeavesTheControlBackOnSendOrDimmed() {
        let terminal: [ChatReplyPhase] = [
            .idle, .complete, .truncated, .emptyReply, .stopped, .failed(.midStreamFailure),
        ]
        for phase in terminal {
            XCTAssertEqual(ChatComposerSendControl.resolve(canSend: true, replyPhase: phase), .send, "\(phase)")
            XCTAssertEqual(
                ChatComposerSendControl.resolve(canSend: false, replyPhase: phase),
                .unavailable,
                "\(phase)"
            )
        }
    }

    /// The overload is the boolean one, taken from the ladder — asserted rather than
    /// assumed, so the two cannot answer differently if either is ever edited.
    func testThePhaseOverloadAgreesWithTheBooleanOne() {
        let phases: [ChatReplyPhase] = [
            .idle, .awaitingFirstToken, .streaming, .stalled,
            .complete, .truncated, .emptyReply, .stopped, .failed(.midStreamFailure),
        ]
        for phase in phases {
            for canSend in [true, false] {
                XCTAssertEqual(
                    ChatComposerSendControl.resolve(canSend: canSend, replyPhase: phase),
                    ChatComposerSendControl.resolve(canSend: canSend, isStreaming: phase.isLive),
                    "\(phase) / \(canSend)"
                )
            }
        }
    }

    // MARK: - The target does not move

    /// Enabled and disabled send draw the same glyph. A control that changed shape on the
    /// keystroke that made the field non-blank would flicker under ordinary typing, and
    /// a person aiming for it would be aiming at something that moved.
    func testEnabledAndDisabledSendDrawTheSameGlyph() {
        XCTAssertEqual(
            ChatComposerSendControl.send.systemImageName,
            ChatComposerSendControl.unavailable.systemImageName
        )
        XCTAssertEqual(ChatComposerSendControl.send.systemImageName, "arrow.up.circle.fill")
    }

    // MARK: - No state distinguished by tint alone

    /// CLAUDE.md's rule, applied to a control rather than a chart: `.send` and
    /// `.unavailable` are the same glyph in two tints, so the difference has to exist in
    /// words as well. Every state is spoken distinguishably.
    func testEveryStateIsSpokenDistinguishably() {
        let spoken = ChatComposerSendControl.allCases.map {
            [$0.accessibilityLabel, $0.accessibilityValue ?? ""].joined(separator: " — ")
        }
        XCTAssertEqual(Set(spoken).count, ChatComposerSendControl.allCases.count, "\(spoken)")
    }

    func testTheTwoUnpressableStatesSayWhyRatherThanRelyingOnDimming() {
        XCTAssertNotNil(ChatComposerSendControl.unavailable.accessibilityValue)
        XCTAssertNotNil(ChatComposerSendControl.awaitingReply.accessibilityValue)
    }

    /// A hint describes what a tap does, so the states where a tap does nothing must not
    /// carry one — VoiceOver would promise an action that is not there.
    func testOnlyTheActionableStatesCarryAHint() {
        for control in ChatComposerSendControl.allCases {
            XCTAssertEqual(
                control.accessibilityHint != nil,
                control.isEnabled,
                "\(control) hint should exist exactly when it is tappable"
            )
        }
    }

    func testEveryStateHasANonEmptySpokenLabel() {
        for control in ChatComposerSendControl.allCases {
            XCTAssertFalse(control.accessibilityLabel.isEmpty, "\(control)")
        }
    }

    /// Exactly one state is not a button, and it is the one MAX-152's waiting indicator
    /// occupies. If a second one ever needs an indicator, this test is where that decision
    /// gets made rather than discovered.
    func testExactlyOneStateShowsActivityAndItHasNoGlyph() {
        let showing = ChatComposerSendControl.allCases.filter(\.showsActivity)
        XCTAssertEqual(showing, [.awaitingReply])
        for control in ChatComposerSendControl.allCases {
            XCTAssertEqual(control.systemImageName == nil, control.showsActivity, "\(control)")
        }
    }
}

/// MAX-198, §6.5: the keyed store `ChatModel` reads and writes `composerText` through.
/// `ChatModel`'s own suite exercises it end to end (restoring across a fresh model,
/// staying off a different subject, clearing on send); this asserts the store's own
/// small contract in isolation.
///
/// `@MainActor` to match `ChatComposerDraftStore` itself — every test method is `async`
/// so it compiles under Linux's non-isolated test discovery (SwiftPM), the same rule
/// `ChatModelTests` follows.
@MainActor
final class ChatComposerDraftStoreTests: XCTestCase {

    private let workout = ChatSubject.workout(UUID())
    private let otherWorkout = ChatSubject.workout(UUID())

    func testANeverWrittenSubjectReadsAsEmptyRatherThanRequiringAnUnwrap() async {
        let store = ChatComposerDraftStore()
        XCTAssertEqual(store.draft(for: workout), "")
    }

    func testAWrittenDraftReadsBackExactly() async {
        let store = ChatComposerDraftStore()
        store.setDraft("Three sentences about how it felt.", for: workout)
        XCTAssertEqual(store.draft(for: workout), "Three sentences about how it felt.")
    }

    /// Decision #1: per subject. Two subjects through the same store never see each
    /// other's text.
    func testTwoSubjectsThroughTheSameStoreDoNotSeeEachOthersDraft() async {
        let store = ChatComposerDraftStore()
        store.setDraft("For the run.", for: workout)
        XCTAssertEqual(store.draft(for: otherWorkout), "")
        XCTAssertEqual(store.draft(for: workout), "For the run.")
    }

    /// Setting an empty string removes the entry rather than storing an empty one — the
    /// same outcome `clear(for:)` names, so the two converge on one state instead of a
    /// blank draft and a cleared draft being subtly different things.
    func testWritingAnEmptyStringLeavesNothingBehind() async {
        let store = ChatComposerDraftStore()
        store.setDraft("Typed, then deleted.", for: workout)
        store.setDraft("", for: workout)
        XCTAssertEqual(store.draft(for: workout), "")
    }

    func testClearIsEquivalentToWritingAnEmptyString() async {
        let store = ChatComposerDraftStore()
        store.setDraft("Ask about the long run.", for: workout)
        store.clear(for: workout)
        XCTAssertEqual(store.draft(for: workout), "")
    }
}
