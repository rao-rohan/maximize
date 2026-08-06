import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-156: `ScoringError.description` never carries a workout identifier or a date,
/// for any case — CLAUDE.md's "Health and privacy" rules that out of an error string
/// unconditionally, and does not carry a "today's one caller happens to log it
/// `.private`" exception. `noPlanInEffect` and `contextAlreadyScored` are the two cases
/// that used to interpolate one; every case is checked anyway, so "no case leaks a
/// workout or a date" stays a claim this suite can make rather than one that quietly
/// stops being true when a case is added.
final class ScoringErrorPrivacyTests: XCTestCase {

    /// Chosen distinctive enough that a leak is unmistakable rather than something that
    /// could plausibly be ordinary English inside a sentence.
    private let workoutID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()

    private func day() throws -> CalendarDay {
        try CalendarDay(iso8601: "2026-03-17")
    }

    /// One instance of every `ScoringError` case.
    private func everyCase() throws -> [ScoringError] {
        [
            .noPlanInEffect(day: try day()),
            .contextAlreadyScored(workoutID: workoutID),
            .noBandMatched(scheduled: .easy, actual: .hard),
            .malformedResponse(reason: "the reply was not JSON"),
            .scoreOutOfPermittedRange(proposed: 137),
            .scoreOutsideBand(
                identifier: "easy.onCap.lowDrift",
                proposed: 60,
                permitted: try ScoreRange(lowest: 90, highest: 100)
            ),
            .rationaleRejected(reason: "it was empty"),
        ]
    }

    // MARK: - The two things a description must never carry

    func testNoDescriptionContainsTheWorkoutIdentifierForAnyCase() throws {
        for error in try everyCase() {
            XCTAssertFalse(
                error.description.contains(workoutID.uuidString),
                "\(error.kind): \(error.description)"
            )
        }
    }

    func testNoDescriptionContainsTheDateForAnyCase() throws {
        let today = try day()
        for error in try everyCase() {
            XCTAssertFalse(
                error.description.contains(today.description),
                "\(error.kind): \(error.description)"
            )
            // Belt and braces: the bare year, in case a future rewording keeps only
            // part of the date rather than the full `YYYY-MM-DD` string.
            XCTAssertFalse(
                error.description.contains(String(today.year)),
                "\(error.kind): \(error.description)"
            )
        }
    }

    // MARK: - Deleting the identifier did not delete the sentence

    /// This is "remove the payload from the string", not "remove the string" — the two
    /// affected cases still say something a developer reading a debugger can act on.
    func testTheTwoAffectedCasesStillSaySomethingMeaningful() throws {
        let noPlan = ScoringError.noPlanInEffect(day: try day()).description
        XCTAssertFalse(noPlan.isEmpty)
        XCTAssertTrue(noPlan.contains("plan"))

        let alreadyScored = ScoringError.contextAlreadyScored(workoutID: workoutID).description
        XCTAssertFalse(alreadyScored.isEmpty)
        XCTAssertTrue(alreadyScored.contains("score"))
    }

    /// Every case keeps saying something different from every other case — a `default`
    /// arm collapsing two of these onto one sentence would be caught here too.
    func testEveryDescriptionIsDistinct() throws {
        let descriptions = Set(try everyCase().map(\.description))
        XCTAssertEqual(descriptions.count, try everyCase().count)
    }

    // MARK: - The value is still reachable — deliberately

    /// The identifier and the day are not gone from the type, only from `description`.
    /// A caller that genuinely needs one reaches for it by matching the specific case —
    /// which is the "separate channel" `ScoringError`'s documentation describes, rather
    /// than a second stored property duplicating the same payload.
    func testTheIdentifierAndDayAreStillReachableByMatchingTheCase() throws {
        let expectedDay = try day()
        guard case let .noPlanInEffect(matchedDay) = ScoringError.noPlanInEffect(day: expectedDay) else {
            return XCTFail("expected .noPlanInEffect")
        }
        XCTAssertEqual(matchedDay, expectedDay)

        guard case let .contextAlreadyScored(matchedID) =
            ScoringError.contextAlreadyScored(workoutID: workoutID)
        else {
            return XCTFail("expected .contextAlreadyScored")
        }
        XCTAssertEqual(matchedID, workoutID)
    }
}
