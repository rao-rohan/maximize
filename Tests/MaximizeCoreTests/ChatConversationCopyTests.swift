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
}
