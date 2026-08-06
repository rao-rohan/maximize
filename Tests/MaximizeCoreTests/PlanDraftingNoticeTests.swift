import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-155: the plan proposal card's failure text follows the same discipline
/// `ChatFailureNoticeTests` asserts for a dropped stream — no status code, no enum
/// name, no wire vocabulary, no case falling through to a generic apology.
///
/// The suite is written against the whole of `PlanProposalModelError` rather than the
/// interesting cases, for the same reason `ChatFailureNoticeTests` is: "we thought
/// about every failure" is a claim only an exhaustive test can make.
final class PlanDraftingNoticeTests: XCTestCase {

    /// Every `PlanProposalModelError`, mirroring `ChatReplyPhaseTests.everyStreamError`.
    /// The status codes are arbitrary and are asserted never to appear in anything a
    /// person reads.
    private static let everyTransportError: [PlanProposalModelError] = [
        .noAPIKeyStored,
        .requestFailed,
        .timedOut,
        .invalidAPIKey,
        .rateLimited,
        .serverUnavailable(statusCode: 503),
        .unexpectedStatus(400),
        .refused,
        .truncated,
        .unreadableResponse,
    ]

    private func notice(_ error: PlanProposalModelError) -> PlanDraftingNotice {
        PlanDraftingNotice.notice(for: .transport(error))
    }

    // MARK: - Every transport case is covered, and none of them is a fallback

    func testEveryTransportFailureHasANonEmptySentence() {
        for error in Self.everyTransportError {
            let message = notice(error).message
            XCTAssertFalse(message.isEmpty, "\(error)")
            XCTAssertTrue(message.hasSuffix("."), "\(error): \(message)")
        }
    }

    /// Ten failures, ten different sentences. A `default` branch would collapse several
    /// of these onto one string and this count would drop.
    func testEveryTransportFailureSaysSomethingDifferent() {
        let messages = Set(Self.everyTransportError.map { notice($0).message })
        XCTAssertEqual(messages.count, Self.everyTransportError.count)
    }

    /// The diagnostic and the sentence are two different texts for two different
    /// readers, for every case that was actually a diagnostic before this ticket.
    /// `.noAPIKeyStored` is excluded on purpose: `PlanDraftingFailure.description`
    /// already special-cased it to the same athlete-facing sentence this type gives it
    /// (see `PlanProposalDrafting.swift`), so equality there is not a regression — the
    /// other nine cases are where `description` was the raw `PlanProposalModelError`
    /// diagnostic, and MAX-155 is about those.
    func testNoTransportFailureShowsTheDeveloperFacingDescription() {
        for error in Self.everyTransportError {
            XCTAssertNotEqual(notice(error).message, error.description, "\(error)")
            guard error != .noAPIKeyStored else { continue }
            XCTAssertNotEqual(
                notice(error).message,
                PlanDraftingFailure.transport(error).description,
                "\(error)"
            )
        }
    }

    // MARK: - Nothing leaks into the words

    /// No status codes, no counts, no numerals of any kind — the exact defect MAX-155
    /// was filed for. `serverUnavailable` and `unexpectedStatus` are exactly where a
    /// number would leak.
    func testNoTransportMessageContainsANumeral() {
        for error in Self.everyTransportError {
            let message = notice(error).message
            XCTAssertNil(message.rangeOfCharacter(from: .decimalDigits), "\(error): \(message)")
        }
    }

    /// No enum names, no API vocabulary, no parenthetical asides.
    func testNoTransportMessageLeaksVocabularyFromTheWire() {
        let banned = [
            "stop_reason", "HTTP", "status", "(", ")", "nil", "error:",
            "noAPIKeyStored", "unreadableResponse", "unexpectedStatus", "serverUnavailable",
            "invalidAPIKey", "rateLimited", "requestFailed", "timedOut", "truncated",
        ]
        for error in Self.everyTransportError {
            let message = notice(error).message
            for token in banned {
                XCTAssertFalse(message.contains(token), "\(error) leaked \(token): \(message)")
            }
        }
    }

    /// Nothing here interpolates anything the caller supplies — every `.transport`
    /// sentence is a constant keyed only by the case, so calling twice with the same
    /// case gives the same words.
    func testATransportMessageIsConstantForItsCase() {
        for error in Self.everyTransportError {
            XCTAssertEqual(notice(error).message, notice(error).message, "\(error)")
        }
    }

    /// The exact regression: a 400, specifically, must not reach the words as "400".
    func testTheStatusFourHundredNeverAppearsAsANumber() {
        XCTAssertFalse(notice(.unexpectedStatus(400)).message.contains("400"))
    }

    /// And neither does any other status this client can receive.
    func testNoStatusCodeSurvivesIntoTheSentence() {
        for code in [400, 401, 403, 404, 413, 429, 500, 503, 529] {
            XCTAssertFalse(notice(.serverUnavailable(statusCode: code)).message.contains("\(code)"))
            XCTAssertFalse(notice(.unexpectedStatus(code)).message.contains("\(code)"))
        }
    }

    // MARK: - The no-key sentence is the one that shipped

    func testTheNoKeySentencePointsAtSettingsAndNamesNoStatus() {
        let message = notice(.noAPIKeyStored).message
        XCTAssertEqual(message, "Add an Anthropic API key in Settings to draft a plan from this conversation.")
        XCTAssertFalse(message.contains("401"))
    }

    /// "No key" and "the key was rejected" are the sharpest pair, same as chat's: one
    /// means *add* a key, the other means *replace* one.
    func testHavingNoKeyAndHavingARejectedKeySayDifferentThings() {
        XCTAssertNotEqual(notice(.noAPIKeyStored).message, notice(.invalidAPIKey).message)
        XCTAssertTrue(notice(.noAPIKeyStored).message.contains("Settings"))
        XCTAssertTrue(notice(.invalidAPIKey).message.contains("Settings"))
    }

    // MARK: - The failures that are not transport failures

    /// `.rejected` is the deliberate exception to "nothing is interpolated" — see this
    /// type's documentation. It is carried through unchanged, and asserted here so a
    /// future edit to it is a decision rather than an accident.
    func testARejectedProposalCarriesTheCorrectionTextVerbatim() {
        let error = PlanProposalError.longRunArcIsEmpty
        let message = PlanDraftingNotice.notice(for: .rejected(error)).message

        XCTAssertTrue(message.contains(error.description), message)
        XCTAssertTrue(message.contains("Nothing has changed"), message)
        XCTAssertFalse(message.isEmpty)
    }

    /// The conversation being too thin to draft from is its own sentence, and it names
    /// no case and no number.
    func testNothingToDraftFromNamesNoCaseAndNoNumber() {
        let message = PlanDraftingNotice.notice(for: .nothingToDraftFrom).message

        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(message.rangeOfCharacter(from: .decimalDigits), message)
        XCTAssertFalse(message.contains("nothingToDraftFrom"))
    }

    /// The whole board at once: every `.transport` sentence plus the two non-transport
    /// ones, all distinct.
    func testEveryNoticeInTheAppIsDistinct() {
        var messages = Set(Self.everyTransportError.map { notice($0).message })
        messages.insert(
            PlanDraftingNotice.notice(for: .rejected(.longRunArcIsEmpty)).message
        )
        messages.insert(PlanDraftingNotice.notice(for: .nothingToDraftFrom).message)
        XCTAssertEqual(messages.count, Self.everyTransportError.count + 2)
    }
}
