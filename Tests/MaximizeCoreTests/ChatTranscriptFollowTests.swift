import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-153: whether arriving tokens are allowed to move the viewport.
///
/// This is the ticket's least visible decision and its most annoying failure. Nobody
/// notices a transcript that follows correctly; everybody notices the one that drags them
/// away from the sentence they were reading. There is no way to check that on a device
/// except by scrolling up during a live reply and watching, which is exactly why the rule
/// is a state machine here rather than three `onChange` handlers in a view.
final class ChatTranscriptFollowTests: XCTestCase {

    // MARK: - Opening a thread

    func testAFreshTranscriptFollowsAndOffersNothing() {
        let follow = ChatTranscriptFollow()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertFalse(follow.hasUnseenActivity)
        XCTAssertFalse(follow.showsJumpToLatest)
    }

    // MARK: - Rule 1 — your own message always scrolls

    func testSendingScrollsEvenFromHalfwayUpTheTranscript() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()

        let directive = follow.transcriptChanged(.ownMessage)
        XCTAssertEqual(directive, .scrollToLatest)
        XCTAssertTrue(follow.isFollowing, "sending is also how a reader says they are done re-reading")
        XCTAssertFalse(follow.hasUnseenActivity)
        XCTAssertFalse(follow.showsJumpToLatest)
    }

    // MARK: - Rule 2 — incoming content only moves a reader who is already at the bottom

    func testAReplyFollowsWhileTheReaderIsAtTheBottom() {
        var follow = ChatTranscriptFollow()
        let directive = follow.transcriptChanged(.incoming)
        XCTAssertEqual(directive, .scrollToLatest)
        XCTAssertTrue(follow.isFollowing)
    }

    /// The defect this whole type exists for. An athlete scrolls up to re-read a split;
    /// two hundred tokens arrive; nothing moves.
    func testAReplyArrivingWhileTheReaderIsScrolledUpDoesNotMoveThem() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()

        for _ in 0..<200 {
            let directive = follow.transcriptChanged(.incoming)
            XCTAssertEqual(directive, .stay)
        }
        XCTAssertFalse(follow.isFollowing)
        XCTAssertTrue(follow.hasUnseenActivity)
        XCTAssertTrue(follow.showsJumpToLatest)
    }

    /// The badge is a flag rather than a counter precisely because the unit of arrival is
    /// a token. Two hundred `.incoming` calls are one piece of news.
    func testUnseenActivityIsAFlagRatherThanACountOfTokens() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)
        let afterOne = follow
        _ = follow.transcriptChanged(.incoming)
        XCTAssertEqual(follow, afterOne)
    }

    // MARK: - Rule 2, second half — a reflow follows but is never news (MAX-152)

    /// A reader at the bottom stays at the bottom when the waiting shimmer appears, when a
    /// stall caption grows under a partial reply, or when a failure notice replaces the
    /// indicator. All of those move the content; none is something either party said.
    func testAReflowKeepsAFollowingReaderAtTheBottom() {
        var follow = ChatTranscriptFollow()
        let directive = follow.transcriptChanged(.reflow)
        XCTAssertEqual(directive, .scrollToLatest)
        XCTAssertTrue(follow.isFollowing)
    }

    /// The failure MAX-152's shimmer would otherwise cause: an athlete who scrolled up to
    /// re-read is told "New reply" because a placeholder resized. It is not a reply, so it
    /// does not badge and it does not move them.
    func testAReflowNeitherMovesNorBadgesAReaderWhoScrolledAway() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()

        let directive = follow.transcriptChanged(.reflow)
        XCTAssertEqual(directive, .stay)
        XCTAssertFalse(follow.hasUnseenActivity, "a placeholder resizing is not a reply")
        XCTAssertEqual(follow.jumpToLatestTitle, "Jump to latest")
    }

    /// And a reflow does not clear a badge an actual reply already earned: the phase
    /// settling to `.complete` right after the last token must not erase the news.
    func testAReflowDoesNotClearABadgeARealReplyEarned() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)

        _ = follow.transcriptChanged(.reflow)
        XCTAssertTrue(follow.hasUnseenActivity)
        XCTAssertEqual(follow.jumpToLatestTitle, "New reply")
    }

    // MARK: - Rule 3 — focusing the composer does not move a reader who scrolled away

    /// The deliberate departure from this app's pre-MAX-153 behaviour, which scrolled to
    /// the bottom whenever the composer took focus. Tapping the field to type a follow-up
    /// *about the thing you scrolled up to look at* must not take it off screen.
    func testFocusingTheComposerLeavesAScrolledUpReaderWhereTheyAre() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        let directive = follow.composerFocusChanged(isFocused: true)
        XCTAssertEqual(directive, .stay)
        XCTAssertFalse(follow.isFollowing)
    }

    /// The case the old behaviour was written for, still handled: a reader at the bottom
    /// stays at the bottom when the keyboard rises.
    func testFocusingTheComposerKeepsAFollowingReaderAtTheBottom() {
        var follow = ChatTranscriptFollow()
        let directive = follow.composerFocusChanged(isFocused: true)
        XCTAssertEqual(directive, .scrollToLatest)
    }

    func testLosingFocusNeverScrolls() {
        var follow = ChatTranscriptFollow()
        let whileFollowing = follow.composerFocusChanged(isFocused: false)
        XCTAssertEqual(whileFollowing, .stay)
        follow.readerScrolledAway()
        let whileAway = follow.composerFocusChanged(isFocused: false)
        XCTAssertEqual(whileAway, .stay)
    }

    // MARK: - The way back

    func testTakingTheOfferScrollsAndClearsIt() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)

        let directive = follow.jumpToLatestRequested()
        XCTAssertEqual(directive, .scrollToLatest)
        XCTAssertTrue(follow.isFollowing)
        XCTAssertFalse(follow.showsJumpToLatest)
        XCTAssertFalse(follow.hasUnseenActivity)
    }

    func testScrollingBackDownByHandResumesFollowing() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)

        follow.readerReachedLatest()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertFalse(follow.hasUnseenActivity)
        let directive = follow.transcriptChanged(.incoming)
        XCTAssertEqual(directive, .scrollToLatest)
    }

    /// A scroll view reports its position continuously, so this is called on every frame
    /// of a drag. Only the first call is a state change — otherwise an arriving token
    /// would set the flag and the next scroll event would clear it, giving a badge that
    /// blinks rather than one that means something.
    func testLeavingTheBottomIsIdempotentSoTheBadgeDoesNotFlicker() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)
        XCTAssertTrue(follow.hasUnseenActivity)

        for _ in 0..<10 { follow.readerScrolledAway() }
        XCTAssertTrue(follow.hasUnseenActivity, "a continuing drag is not new information")
    }

    /// Scrolling away *starts* a fresh watch: whatever was unseen has now been seen, or
    /// deliberately left.
    func testLeavingTheBottomAfterCatchingUpStartsCleanRatherThanCarryingAStaleBadge() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        _ = follow.transcriptChanged(.incoming)
        follow.readerReachedLatest()

        follow.readerScrolledAway()
        XCTAssertFalse(follow.hasUnseenActivity)
        XCTAssertTrue(follow.showsJumpToLatest, "the offer stands whenever you are away, badge or not")
    }

    // MARK: - What the control says

    /// The two states differ in words, not in tint or glyph — CLAUDE.md's hue rule
    /// applies to a badge exactly as it does to a score band.
    func testTheOfferNamesWhetherSomethingArrivedRatherThanColouringIt() {
        var follow = ChatTranscriptFollow()
        follow.readerScrolledAway()
        XCTAssertEqual(follow.jumpToLatestTitle, "Jump to latest")

        _ = follow.transcriptChanged(.incoming)
        XCTAssertEqual(follow.jumpToLatestTitle, "New reply")
    }
}
