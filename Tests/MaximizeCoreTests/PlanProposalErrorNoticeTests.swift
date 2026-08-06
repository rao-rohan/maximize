import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-158: what an athlete reads on a rejected plan proposal stops speaking the wire
/// vocabulary `PlanProposalError.description` exists to hand back to the model — no
/// field names, no "JSON", no "schema" — while `description` itself keeps every case's
/// precise correction text, because that is what the retry needs to be worth attempting.
///
/// Written against the whole of `PlanProposalError`, mirroring
/// `PlanDraftingNoticeTests`'s own reasoning: "we thought about every case" is a claim
/// only an exhaustive test can make.
final class PlanProposalErrorNoticeTests: XCTestCase {

    /// One instance of every `PlanProposalError` case, each carrying a distinctive,
    /// recognisable payload so a leak is easy to spot in a failure message.
    private static let everyCase: [PlanProposalError] = [
        .malformedResponse(reason: "expected a single JSON object and nothing else"),
        .missingField(name: "heartRateCapBPM"),
        .forbiddenField(name: "effectiveFrom"),
        .unknownSessionKind(name: "sprint"),
        .unknownWeekday(name: "funday"),
        .unknownLiftKind(name: "cardio"),
        .unknownMuscleGroup(name: "neck"),
        .weekIsNotOneSessionPerWeekday(missing: [.monday], duplicated: [.tuesday]),
        .restDayIsNotEmpty(weekday: .monday),
        .liftRestDayIsNotEmpty(weekday: .tuesday),
        .malformedGoalTargetDay(value: "15 November"),
        .longRunArcIsEmpty,
        .longRunArcWeekNotPositive(week: 0),
        .longRunArcOutOfOrder(week: 2),
        .rejectedByAuthoring(.heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)),
    ]

    private func message(_ error: PlanProposalError) -> String {
        PlanProposalErrorNotice.notice(for: error).message
    }

    // MARK: - Every case is covered, and none of them is a fallback

    func testEveryCaseHasANonEmptySentence() {
        for error in Self.everyCase {
            let text = message(error)
            XCTAssertFalse(text.isEmpty, "\(error)")
            XCTAssertTrue(text.hasSuffix("."), "\(error): \(text)")
        }
    }

    /// Fifteen cases, fifteen different sentences. A `default` branch would collapse
    /// several of these onto one string and this count would drop.
    func testEveryCaseSaysSomethingDifferent() {
        let messages = Set(Self.everyCase.map(message))
        XCTAssertEqual(messages.count, Self.everyCase.count)
    }

    /// Nothing here interpolates a payload: two instances of the same case, carrying
    /// different names or indices, read identically — the same rule
    /// `PlanDraftingNotice.transportMessage` keeps for `PlanProposalModelError`.
    /// `.rejectedByAuthoring` is excluded: it is the one deliberate exception, argued in
    /// `PlanProposalErrorNotice`'s own documentation, and is pinned by its own test below.
    func testNoCaseOtherThanAuthoringInterpolatesItsPayload() {
        XCTAssertEqual(
            message(.missingField(name: "heartRateCapBPM")),
            message(.missingField(name: "week"))
        )
        XCTAssertEqual(
            message(.unknownSessionKind(name: "sprint")),
            message(.unknownSessionKind(name: "lift"))
        )
        XCTAssertEqual(
            message(.restDayIsNotEmpty(weekday: .monday)),
            message(.restDayIsNotEmpty(weekday: .sunday))
        )
        XCTAssertEqual(
            message(.longRunArcWeekNotPositive(week: 0)),
            message(.longRunArcWeekNotPositive(week: -3))
        )
    }

    // MARK: - Nothing here speaks the wire

    /// The exact defect this ticket fixes: a field name, "JSON", or "schema" reaching an
    /// athlete who has no field, no JSON, and no schema to fix.
    func testNoMessageLeaksWireVocabulary() {
        let banned = [
            "JSON", "json", "schema", "liftKind", "heartRateCapBPM", "effectiveFrom",
            "cadenceLowStepsPerMinute", "cadenceHighStepsPerMinute", "distanceMeters",
            "liftMuscleGroups", "liftDurationSeconds", "liftNote", "goalStatements",
            "goalTargetDay", "longRunArc", "minimumSessionDurationSeconds",
        ]
        for error in Self.everyCase {
            let text = message(error)
            for token in banned {
                XCTAssertFalse(text.contains(token), "\(error) leaked \(token): \(text)")
            }
        }
    }

    /// `PlanProposalError.description` quotes every field name and every value it
    /// names ("heartRateCapBPM", "monday", the model's raw text). The athlete-facing
    /// rendering never needs to, so a quotation mark surviving into it is itself a sign
    /// something from the wire slipped through.
    func testNoMessageContainsAQuotationMark() {
        for error in Self.everyCase {
            let text = message(error)
            XCTAssertFalse(text.contains("\""), "\(error): \(text)")
        }
    }

    /// The fourteen model-boundary cases read nothing like the correction text a retry
    /// needs — `.rejectedByAuthoring` is excluded, because it is the one case where the
    /// two renderings are the same sentence on purpose.
    func testEveryModelBoundaryCaseDiffersFromItsCorrectionText() {
        for error in Self.everyCase {
            guard case .rejectedByAuthoring = error else {
                XCTAssertNotEqual(message(error), error.description, "\(error)")
                continue
            }
        }
    }

    // MARK: - The one deliberate exception

    /// `.rejectedByAuthoring` is not rewritten: `PlanAuthoringError.description` is
    /// already the athlete-facing sentence everywhere else it is used (§4.5,
    /// `FailureCopy.planCouldNotBePrepared`'s own doc comment), so this is the one case
    /// that is honestly one string for both readers rather than two competing ones.
    func testRejectedByAuthoringCarriesThePlanAuthoringSentenceVerbatim() {
        let authoringError = PlanAuthoringError.thresholdsInverted
        XCTAssertEqual(
            message(.rejectedByAuthoring(authoringError)),
            authoringError.description
        )
    }

    // MARK: - The correction channel is unweakened

    /// `PlanProposalError.description` — read by the retry, never by this type — still
    /// carries the precise wire name for every case that has one. Weakening it here
    /// would trade a usability bug for a functional one: a model that cannot see which
    /// field was wrong cannot correct it.
    func testTheCorrectionTextStillNamesThePreciseField() {
        XCTAssertTrue(
            PlanProposalError.missingField(name: "heartRateCapBPM").description
                .contains("heartRateCapBPM")
        )
        XCTAssertTrue(
            PlanProposalError.forbiddenField(name: "effectiveFrom").description
                .contains("effectiveFrom")
        )
        XCTAssertTrue(
            PlanProposalError.unknownSessionKind(name: "sprint").description.contains("sprint")
        )
        XCTAssertTrue(
            PlanProposalError.unknownWeekday(name: "funday").description.contains("funday")
        )
        XCTAssertTrue(
            PlanProposalError.unknownLiftKind(name: "cardio").description.contains("cardio")
        )
        XCTAssertTrue(
            PlanProposalError.unknownMuscleGroup(name: "neck").description.contains("neck")
        )
        XCTAssertTrue(
            PlanProposalError.malformedGoalTargetDay(value: "15 November").description
                .contains("15 November")
        )
        XCTAssertTrue(
            PlanProposalError.longRunArcWeekNotPositive(week: 0).description.contains("0")
        )
        XCTAssertTrue(
            PlanProposalError.longRunArcOutOfOrder(week: 2).description.contains("2")
        )
    }
}
