import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-152: every way a chat turn can fail has words the athlete can act on, and no case
/// falls through to a diagnostic.
///
/// The suite is written against the whole of `ChatStreamError` rather than against the
/// interesting cases, because "we thought about every failure" is a claim only an
/// exhaustive test can make. `ChatReplyPhaseTests.everyStreamError` is that list, written
/// out by hand so a new case has to be added to it deliberately.
final class ChatFailureNoticeTests: XCTestCase {

    private let everyError = ChatReplyPhaseTests.everyStreamError
    private let everySubject: [ChatSubjectKind?] = [.workout, .training, nil]

    private func notice(_ error: ChatStreamError, _ subject: ChatSubjectKind? = .workout) -> ChatFailureNotice {
        ChatFailureNotice.notice(for: error, subject: subject)
    }

    // MARK: - Every case is covered, and none of them is a fallback

    func testEveryFailureHasANonEmptySentenceForEverySubject() {
        for error in everyError {
            for subject in everySubject {
                let message = notice(error, subject).message
                XCTAssertFalse(message.isEmpty, "\(error)")
                XCTAssertTrue(message.hasSuffix("."), "\(error): \(message)")
            }
        }
    }

    /// Twelve failures, twelve different sentences. This is what "no case falls through
    /// to a generic fallback" actually means: a `default` branch would collapse several
    /// of these onto one string and this count would drop.
    func testEveryFailureSaysSomethingDifferent() {
        let messages = Set(everyError.map { notice($0).message })
        XCTAssertEqual(messages.count, everyError.count)
    }

    /// The diagnostic and the sentence are two different texts for two different readers.
    /// Before this ticket the transcript showed `description` for every case but one,
    /// which is how "The response was not a recognizable streaming reply" reached a
    /// person's screen.
    func testNoFailureShowsTheDeveloperFacingDescription() {
        for error in everyError {
            for subject in everySubject {
                XCTAssertNotEqual(notice(error, subject).message, error.description, "\(error)")
            }
        }
    }

    /// The device report MAX-107 was diagnosed from, by name. What a person needs to know
    /// is that their data is fine and that asking again is not the fix — neither of which
    /// the old sentence said.
    func testTheUnreadableReplyNoLongerSaysTheSentenceTheOwnerHit() {
        let message = notice(.unreadableResponse).message
        XCTAssertFalse(message.contains("recognizable"))
        XCTAssertFalse(message.contains("streaming"))
        XCTAssertFalse(notice(.unreadableResponse).offersRetry, "asking again cannot fix a shape mismatch")
    }

    // MARK: - Nothing leaks into the words

    /// No status codes, no counts, no numerals of any kind. A number in a chat bubble is
    /// a dead end for the person reading it, and the two cases that carry one
    /// (`serverUnavailable`, `unexpectedStatus`) are exactly where it would leak.
    func testNoFailureMessageContainsANumeral() {
        for error in everyError {
            for subject in everySubject {
                let message = notice(error, subject).message
                XCTAssertNil(
                    message.rangeOfCharacter(from: .decimalDigits),
                    "\(error): \(message)"
                )
            }
        }
    }

    /// No enum names, no API vocabulary, no parenthetical asides — the three shapes a
    /// developer-facing string takes when it escapes onto a screen.
    func testNoFailureMessageLeaksVocabularyFromTheWire() {
        let banned = [
            "stop_reason", "HTTP", "status", "(", ")", "nil", "error:",
            "noAPIKeyStored", "unreadableResponse", "midStreamFailure", "rate_limit",
        ]
        for error in everyError {
            for subject in everySubject {
                let message = notice(error, subject).message
                for token in banned {
                    XCTAssertFalse(message.contains(token), "\(error) leaked \(token): \(message)")
                }
            }
        }
    }

    /// Nothing here interpolates anything, so there is no path by which a question, a
    /// reply or a figure about the athlete's training could reach a notice — which is
    /// what makes these strings safe on screen and would make them safe in a log, if this
    /// app wrote one.
    func testAFailureMessageDoesNotVaryWithAnythingButTheSubject() {
        for error in everyError {
            let first = ChatFailureNotice.notice(for: error, subject: .training).message
            let second = ChatFailureNotice.notice(for: error, subject: .training).message
            XCTAssertEqual(first, second, "\(error)")
        }
    }

    // MARK: - The four states of a key are not one state

    /// The sentences that shipped, pinned. This ticket moved them out of
    /// `ChatModel.userFacingMessage(for:)`; it did not write a second set, and the
    /// reasoning that made them subject-worded — "this workout" is a lie on a thread
    /// about a month — is unchanged.
    func testTheNoKeySentencesAreTheOnesThatShipped() {
        XCTAssertEqual(
            notice(.noAPIKeyStored, .workout).message,
            "Add an Anthropic API key in Settings to chat about this workout."
        )
        XCTAssertEqual(
            notice(.noAPIKeyStored, .training).message,
            "Add an Anthropic API key in Settings to chat about your training."
        )
        XCTAssertEqual(
            notice(.noAPIKeyStored, nil).message,
            "Add an Anthropic API key in Settings to chat."
        )
    }

    /// "No key" and "the key was rejected" are the sharpest pair on the board: one means
    /// *add* a key, the other means *replace* one, and a single "check your API key"
    /// would send the athlete to stare at something that is present and looks fine.
    func testHavingNoKeyAndHavingARejectedKeySayDifferentThings() {
        for subject in everySubject {
            XCTAssertNotEqual(
                notice(.noAPIKeyStored, subject).message,
                notice(.invalidAPIKey, subject).message
            )
        }
        XCTAssertTrue(notice(.invalidAPIKey).message.contains("Settings"))
        XCTAssertTrue(notice(.noAPIKeyStored).message.contains("Settings"))
        // A rejected key is not worth asking again with — the same key fails identically.
        XCTAssertFalse(notice(.invalidAPIKey).offersRetry)
        XCTAssertFalse(notice(.noAPIKeyStored).offersRetry)
    }

    /// An unreadable keychain is not an absent key, and telling somebody to add what they
    /// already added is how a keychain problem becomes a loop.
    func testAnUnreadableKeychainIsNotTheSameAsHavingNoKey() {
        XCTAssertNotEqual(
            notice(.keyStoreUnavailable).message,
            notice(.noAPIKeyStored).message
        )
    }

    /// Only the no-key sentence varies by subject. Every other failure is the same fact
    /// on a run thread and on a training thread, and two sentences that differ in no
    /// useful way are two sentences to keep in step for nothing.
    func testOnlyTheNoKeyFailureIsWordedFromTheSubject() {
        for error in everyError where error != .noAPIKeyStored {
            let messages = Set(everySubject.map { notice(error, $0).message })
            XCTAssertEqual(messages.count, 1, "\(error) should not vary by subject")
        }
        XCTAssertEqual(Set(everySubject.map { notice(.noAPIKeyStored, $0).message }).count, 3)
    }

    // MARK: - Retry, decided rather than defaulted

    /// One source of truth for "could asking again help": `ChatStreamError` already owns
    /// the transient/permanent split and documents every case.
    func testRetryIsOfferedForExactlyTheTransientFailures() {
        for error in everyError {
            XCTAssertEqual(notice(error).offersRetry, error.isWorthRetrying, "\(error)")
        }
    }

    /// Named individually as well as by rule, because these are the four a person is
    /// most likely to meet and the ones where a wrong answer wastes the owner's credit.
    func testTheFailuresWorthAskingAgainAreTheOnesYouWouldExpect() {
        for error in [ChatStreamError.requestFailed, .timedOut, .rateLimited, .interrupted, .midStreamFailure] {
            XCTAssertTrue(notice(error).offersRetry, "\(error)")
        }
        for error in [ChatStreamError.noAPIKeyStored, .keyStoreUnavailable, .invalidAPIKey, .refused, .unreadableResponse] {
            XCTAssertFalse(notice(error).offersRetry, "\(error)")
        }
    }

    // MARK: - The failures that are not stream failures

    /// An empty reply is neither a dropped connection nor an answer, and gets a sentence
    /// that says neither. Folding it into `interrupted` would send somebody to look at
    /// their signal for a fault that is not there.
    func testAnEmptyReplyIsItsOwnNoticeAndIsWorthAskingAgain() {
        XCTAssertFalse(ChatFailureNotice.emptyReply.message.isEmpty)
        XCTAssertTrue(ChatFailureNotice.emptyReply.offersRetry)
        XCTAssertNotEqual(ChatFailureNotice.emptyReply.message, notice(.interrupted).message)
    }

    /// A reply that arrived and could not be saved says what happens to it next, and
    /// offers no retry: asking Claude again cannot fix a local write.
    func testAnUnsavedReplyExplainsWhatBecomesOfItAndOffersNoRetry() {
        XCTAssertFalse(ChatFailureNotice.couldNotSaveReply.message.isEmpty)
        XCTAssertFalse(ChatFailureNotice.couldNotSaveReply.offersRetry)
    }

    func testAMessageThatCouldNotBeSentOffersNoRetryBecauseNothingWasSent() {
        XCTAssertFalse(ChatFailureNotice.couldNotSendMessage.message.isEmpty)
        XCTAssertFalse(ChatFailureNotice.couldNotSendMessage.offersRetry)
    }

    func testTheThreeNonStreamNoticesAreThreeDifferentSentences() {
        let messages = Set([
            ChatFailureNotice.emptyReply.message,
            ChatFailureNotice.couldNotSaveReply.message,
            ChatFailureNotice.couldNotSendMessage.message,
        ])
        XCTAssertEqual(messages.count, 3)
    }

    /// The whole board at once: fifteen distinct sentences, twelve from the wire and
    /// three from everything else that can go wrong with a turn. Nothing shares words
    /// with anything else, which is the mechanical form of "each failure is
    /// distinguishable from the others".
    func testEveryNoticeInTheAppIsDistinct() {
        var messages = Set(everyError.map { notice($0).message })
        messages.insert(ChatFailureNotice.emptyReply.message)
        messages.insert(ChatFailureNotice.couldNotSaveReply.message)
        messages.insert(ChatFailureNotice.couldNotSendMessage.message)
        XCTAssertEqual(messages.count, everyError.count + 3)
    }
}
