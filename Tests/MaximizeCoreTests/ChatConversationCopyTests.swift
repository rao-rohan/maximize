import Foundation
import XCTest
@testable import MaximizeCore

/// The conversation surface's subject-dependent copy (MAX-097) — mirrors
/// `ChatModel.userFacingMessage(for:)`'s existing "worded from the subject" pattern for
/// the two other places a thread's subject decides what a person reads.
final class ChatConversationCopyTests: XCTestCase {

    /// The workout path's wording is pinned exactly as `WorkoutChatView` wrote it before
    /// this ticket — MAX-097 generalises the surface, not that path's copy.
    func testTheWorkoutStringsAreUnchangedFromBeforeThisTicket() {
        XCTAssertEqual(
            ChatConversationCopy.failedToLoad(for: .workout),
            "Chat could not be loaded for this workout."
        )
        XCTAssertEqual(
            ChatConversationCopy.emptyTranscriptInvitation(for: .workout),
            "Ask about this run — pacing, drift, whether it matched the plan."
        )
        XCTAssertEqual(ChatConversationCopy.composerPlaceholder(for: .workout), "Ask about this run…")
    }

    /// A training thread's copy must not say "this workout" or "this run" — there is no
    /// one run it is about.
    func testEveryTrainingStringIsWordedForAWindowNotARun() {
        for text in [
            ChatConversationCopy.failedToLoad(for: .training),
            ChatConversationCopy.emptyTranscriptInvitation(for: .training),
            ChatConversationCopy.composerPlaceholder(for: .training),
        ] {
            XCTAssertFalse(text.contains("run"), "\(text) reads as if it is about one run")
            XCTAssertFalse(text.isEmpty)
        }
    }

    func testEveryKindHasDistinctCopyForAllThreeStrings() {
        XCTAssertNotEqual(
            ChatConversationCopy.failedToLoad(for: .workout),
            ChatConversationCopy.failedToLoad(for: .training)
        )
        XCTAssertNotEqual(
            ChatConversationCopy.emptyTranscriptInvitation(for: .workout),
            ChatConversationCopy.emptyTranscriptInvitation(for: .training)
        )
        XCTAssertNotEqual(
            ChatConversationCopy.composerPlaceholder(for: .workout),
            ChatConversationCopy.composerPlaceholder(for: .training)
        )
    }

    /// MAX-097 review: a model opened by thread id has no subject until `load()`
    /// resolves one off the stored thread, so these three have to degrade rather than
    /// force a caller to unwrap a value that is genuinely absent in that window.
    func testANilKindDegradesToAGenericButNonEmptyString() {
        for text in [
            ChatConversationCopy.failedToLoad(for: nil),
            ChatConversationCopy.emptyTranscriptInvitation(for: nil),
            ChatConversationCopy.composerPlaceholder(for: nil),
        ] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("workout"))
            XCTAssertFalse(text.contains("training"))
        }
    }

    /// §2.3: what a deleted-elsewhere thread reached by id says. Not worded by subject —
    /// the lookup that would have supplied one is the lookup that failed.
    func testThreadNotFoundIsNotEmpty() {
        XCTAssertFalse(ChatConversationCopy.threadNotFound.isEmpty)
    }

    // MARK: - MAX-150: the other two `ChatModel.LoadState` cases

    /// Ordinary, not a failure — worded as "not yet" rather than "cannot", the same
    /// register `failedToLoad`/`threadNotFound` keep for their own ordinary states.
    func testNotYetScoredIsNotEmptyAndDoesNotReadAsAFailure() {
        XCTAssertFalse(ChatConversationCopy.notYetScored.isEmpty)
        XCTAssertFalse(ChatConversationCopy.notYetScored.lowercased().contains("error"))
    }

    /// The opposite tense of `notYetScored` (MAX-126): a lift will never be scored, so
    /// the sentence must not promise one is coming.
    func testNoVerdictDoesNotPromiseAScoreIsComing() {
        XCTAssertFalse(ChatConversationCopy.noVerdict.isEmpty)
        XCTAssertNotEqual(ChatConversationCopy.noVerdict, ChatConversationCopy.notYetScored)
    }

    // MARK: - MAX-150: `ChatModel.DisplayMessage`'s two flags

    func testTruncatedAndInterruptedCaptionsAreDistinctAndNonEmpty() {
        XCTAssertFalse(ChatConversationCopy.truncatedCaption.isEmpty)
        XCTAssertFalse(ChatConversationCopy.interruptedByFailureCaption.isEmpty)
        XCTAssertNotEqual(ChatConversationCopy.truncatedCaption, ChatConversationCopy.interruptedByFailureCaption)
    }

    // MARK: - MAX-191: dropped turns notice

    /// Zero dropped messages is the common case — no notice is needed, following CLAUDE.md's
    /// "absence is a designed state" rule.
    func testZeroDroppedMessagesReturnsNil() {
        XCTAssertNil(ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: 0))
    }

    /// Negative counts should also return nil — they are not meaningful.
    func testNegativeDroppedMessagesReturnsNil() {
        XCTAssertNil(ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: -1))
    }

    /// Singular: "1 earlier message".
    func testOneMessageUsesCorrectSingular() {
        let notice = ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: 1)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("1 earlier message"))
        XCTAssertFalse(notice!.contains("messages"))
    }

    /// Plural: "N earlier messages".
    func testMultipleMessagesUseCorrectPlural() {
        let notice = ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: 2)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("2 earlier messages"))
    }

    /// Large numbers also use plural.
    func testLargeCountUsesPlural() {
        let notice = ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: 40)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("40 earlier messages"))
    }

    /// The message does not leak internal details like "turn count", "tokens", or implementation details.
    func testTheMessageDoesNotLeakInternalDetails() {
        for count in [1, 2, 5, 10, 20] {
            let notice = ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: count)
            XCTAssertNotNil(notice)
            let lowercased = notice!.lowercased()
            XCTAssertFalse(lowercased.contains("turn"), "message should say 'message' not 'turn'")
            XCTAssertFalse(lowercased.contains("token"), "message should not mention tokens")
            XCTAssertFalse(lowercased.contains("exchange"), "message should be plain language")
            XCTAssertFalse(lowercased.contains("buffer"), "message should not leak implementation")
        }
    }

    /// The message speaks in the app's voice, not the model's.
    func testTheMessageIsInAppVoice() {
        let notice = ChatConversationCopy.droppedTurnsNotice(droppedMessageCount: 5)
        XCTAssertNotNil(notice)
        // The message should not impersonate the model
        XCTAssertFalse(notice!.lowercased().contains("i don't have"))
        XCTAssertFalse(notice!.lowercased().contains("i don't"))
        // It should be clear and descriptive from the app's perspective
        XCTAssertTrue(notice!.contains("aren't included"))
    }
}
