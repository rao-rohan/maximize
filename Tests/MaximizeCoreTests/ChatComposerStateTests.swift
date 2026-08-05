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
