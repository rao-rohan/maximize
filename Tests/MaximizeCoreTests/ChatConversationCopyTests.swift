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

    // MARK: - `ChatModel.DisplayMessage`'s flags (MAX-150, MAX-197)

    func testTruncatedAndInterruptedCaptionsAreDistinctAndNonEmpty() {
        XCTAssertFalse(ChatConversationCopy.truncatedCaption.isEmpty)
        XCTAssertFalse(ChatConversationCopy.interruptedByFailureCaption.isEmpty)
        XCTAssertNotEqual(ChatConversationCopy.truncatedCaption, ChatConversationCopy.interruptedByFailureCaption)
    }

    /// Three things that can happen to a reply, three sentences. A stop that read like a
    /// dropped connection would send somebody to look at their signal for something they
    /// did themselves (MAX-197).
    func testTheStoppedStringsAreTheirOwnSentencesAndNotAFailuresWords() {
        let stopped = [
            ChatConversationCopy.stoppedByAthleteCaption,
            ChatConversationCopy.stoppedBeforeAnyReplyArrived,
        ]
        for sentence in stopped {
            XCTAssertFalse(sentence.isEmpty)
            XCTAssertNotEqual(sentence, ChatConversationCopy.truncatedCaption)
            XCTAssertNotEqual(sentence, ChatConversationCopy.interruptedByFailureCaption)
            XCTAssertNotEqual(
                sentence,
                ChatFailureNotice.notice(for: .interrupted, subject: .workout).message
            )
        }
        XCTAssertNotEqual(stopped[0], stopped[1])
    }

    /// MAX-155/156's rule, applied to the two strings this ticket adds: no codes, no
    /// identifiers, no numerals of any kind. A stop is the least technical thing that
    /// happens in this app and its words should carry nothing technical at all.
    func testTheStoppedStringsCarryNoCodesOrNumerals() {
        for sentence in [
            ChatConversationCopy.stoppedByAthleteCaption,
            ChatConversationCopy.stoppedBeforeAnyReplyArrived,
        ] {
            XCTAssertNil(
                sentence.rangeOfCharacter(from: CharacterSet.decimalDigits),
                sentence
            )
            // One vocabulary: the control says "Stop generating", so the transcript says
            // stopped rather than cancelled. Two words for one act is how a surface
            // starts sounding like two apps.
            XCTAssertFalse(sentence.lowercased().contains("cancel"), sentence)
        }
    }

    /// The caption is the only place the app says a stopped reply is not being kept.
    /// Asserted by name so the sentence cannot lose that half in an edit and leave the
    /// athlete to find out by reopening the thread.
    func testTheStoppedCaptionSaysWhatBecomesOfTheText() {
        XCTAssertTrue(
            ChatConversationCopy.stoppedByAthleteCaption.lowercased().contains("until you close"),
            ChatConversationCopy.stoppedByAthleteCaption
        )
    }
}
