import Foundation
import XCTest
@testable import MaximizeCore

/// D1's guarantee, pinned: the plan version in effect on a workout's date must be the
/// same answer today as it was when the score was written.
///
/// The fixture plan takes effect on **Thursday 2026-01-01** and carries a three-week
/// arc (16 km, 18 km, 20 km) over a template whose Sunday is a long run of 18 km. Every
/// expectation below is computed by hand from those two facts.
final class PlanCalendarTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// A plan identical to the fixture except for its version and effective date, so
    /// resolution tests vary only what they are about.
    private func plan(version: Int, from effectiveFrom: String) throws -> Plan {
        try Plan(
            version: PlanVersion(version),
            effectiveFrom: day(effectiveFrom),
            weeklyTemplate: Fixture.weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric()
        )
    }

    // MARK: - Version resolution

    /// The boundary that is wrong exactly once per plan version if it is wrong at all,
    /// which is rarely enough to survive casual testing.
    func testTheEffectiveFromDayIsGovernedByThatVersionNotItsPredecessor() throws {
        let calendar = try PlanCalendar([
            plan(version: 1, from: "2026-01-01"),
            plan(version: 2, from: "2026-03-01"),
        ])

        XCTAssertEqual(calendar.plan(on: try day("2026-02-28"))?.version, try PlanVersion(1))
        XCTAssertEqual(calendar.plan(on: try day("2026-03-01"))?.version, try PlanVersion(2))
        XCTAssertEqual(calendar.plan(on: try day("2026-03-02"))?.version, try PlanVersion(2))
    }

    func testADayBeforeEveryVersionHasNoGoverningPlan() throws {
        let calendar = try PlanCalendar([plan(version: 1, from: "2026-01-01")])
        XCTAssertNil(calendar.plan(on: try day("2025-12-31")))
        XCTAssertNil(try calendar.planDay(on: try day("2025-12-31")))
    }

    func testTheLatestApplicableVersionWinsAcrossManyVersions() throws {
        let calendar = try PlanCalendar([
            plan(version: 3, from: "2026-05-01"),
            plan(version: 1, from: "2026-01-01"),
            plan(version: 2, from: "2026-03-01"),
        ])

        // Constructed out of order on purpose — ordering is the calendar's job.
        XCTAssertEqual(calendar.versions.map(\.version), [try PlanVersion(1), try PlanVersion(2), try PlanVersion(3)])
        XCTAssertEqual(calendar.plan(on: try day("2026-01-01"))?.version, try PlanVersion(1))
        XCTAssertEqual(calendar.plan(on: try day("2026-04-30"))?.version, try PlanVersion(2))
        XCTAssertEqual(calendar.plan(on: try day("2027-01-01"))?.version, try PlanVersion(3))
    }

    func testRejectsTwoVersionsTakingEffectOnTheSameDay() throws {
        assertThrows(
            .duplicate,
            try PlanCalendar([
                plan(version: 1, from: "2026-01-01"),
                plan(version: 2, from: "2026-01-01"),
            ])
        )
    }

    /// The rule that protects already-scored history. Authoring a higher version that
    /// begins *earlier* would re-govern days whose scores D8 makes immutable, so the
    /// stored score and a recomputation would disagree with no way to tell which is right.
    func testRejectsALaterVersionThatWouldRegovernEarlierDays() throws {
        assertThrows(
            .inconsistent,
            try PlanCalendar([
                plan(version: 2, from: "2026-01-01"),
                plan(version: 1, from: "2026-03-01"),
            ])
        )
    }

    func testRejectsAnEmptyCalendar() throws {
        assertThrows(.empty, try PlanCalendar([]))
    }

    // MARK: - Session resolution

    func testEachWeekdayResolvesToTheTemplatesAsk() throws {
        let calendar = try PlanCalendar([plan(version: 1, from: "2026-01-01")])

        // 2026-01-01 is a Thursday; the template's Thursday is an 8 km easy run.
        let thursday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-01")))
        XCTAssertEqual(thursday.scheduledSession.kind, .easy)
        XCTAssertEqual(thursday.scheduledSession.distanceMeters, 8_000)

        let friday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-02")))
        XCTAssertTrue(friday.scheduledSession.isRest)

        // Wednesday is a hard session with a note and deliberately no distance.
        let wednesday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-07")))
        XCTAssertEqual(wednesday.scheduledSession.kind, .hard)
        XCTAssertNil(wednesday.scheduledSession.distanceMeters)
        XCTAssertEqual(wednesday.scheduledSession.note, "6 × 800m")
    }

    func testTheResolvedDayRecordsTheGoverningPlanVersion() throws {
        let calendar = try PlanCalendar([
            plan(version: 1, from: "2026-01-01"),
            plan(version: 2, from: "2026-03-01"),
        ])
        let before = try XCTUnwrap(try calendar.planDay(on: try day("2026-02-28")))
        let after = try XCTUnwrap(try calendar.planDay(on: try day("2026-03-01")))
        XCTAssertEqual(before.planVersion, try PlanVersion(1))
        XCTAssertEqual(after.planVersion, try PlanVersion(2))
    }

    // MARK: - The arc, and Monday anchoring

    /// The plan takes effect on Thursday 2026-01-01, so arc week 1 is anchored to
    /// **Monday 2025-12-29** — the Monday on or before it. Sunday 2026-01-04 therefore
    /// still falls in week 1, and takes the arc's 16 km rather than the template's 18 km.
    ///
    /// Anchoring to the effective date instead would put that Sunday in week 1 too, but
    /// would then break at the *next* boundary — which the following test pins.
    func testTheLongRunTakesItsDistanceFromTheArcNotTheTemplate() throws {
        let calendar = try PlanCalendar([plan(version: 1, from: "2026-01-01")])

        let firstSunday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-04")))
        XCTAssertEqual(firstSunday.scheduledSession.kind, .long)
        XCTAssertEqual(firstSunday.scheduledSession.distanceMeters, 16_000)
    }

    /// Monday anchoring, stated as a boundary. 2026-01-05 is the Monday that starts arc
    /// week 2, so the Sunday closing that week takes the arc's week-2 distance.
    func testArcWeeksAdvanceOnMondayNotOnThePlansStartWeekday() throws {
        let onePlan = try plan(version: 1, from: "2026-01-01")
        let calendar = try PlanCalendar([onePlan])

        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-01-04"), under: onePlan), 1)
        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-01-05"), under: onePlan), 2)
        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-01-11"), under: onePlan), 2)
        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-01-12"), under: onePlan), 3)

        let secondSunday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-11")))
        XCTAssertEqual(secondSunday.scheduledSession.distanceMeters, 18_000)
        let thirdSunday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-18")))
        XCTAssertEqual(thirdSunday.scheduledSession.distanceMeters, 20_000)
    }

    /// Past the end of a finite arc the template's own distance stands. The rejected
    /// alternative — clamping to the final week — would have the code prescribe a peak
    /// long run indefinitely, which is a training decision it has no standing to make.
    func testPastTheEndOfTheArcTheTemplateDistanceStands() throws {
        let onePlan = try plan(version: 1, from: "2026-01-01")
        let calendar = try PlanCalendar([onePlan])

        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-01-25"), under: onePlan), 4)
        XCTAssertNil(onePlan.longRunArc.distanceMeters(forWeek: 4))

        let fourthSunday = try XCTUnwrap(try calendar.planDay(on: try day("2026-01-25")))
        XCTAssertEqual(fourthSunday.scheduledSession.kind, .long)
        XCTAssertEqual(fourthSunday.scheduledSession.distanceMeters, 18_000, "the template's own ask")
    }

    /// A new plan version restarts the arc, because week indices are relative to that
    /// version's own effective date. This is D1 working as intended: a new training
    /// block begins at week 1.
    func testANewVersionRestartsTheArc() throws {
        // 2026-03-01 is a Sunday, so it is both the first day of version 2 and a long-run
        // day — and its Monday anchor is 2026-02-23, making it week 1 of the new arc.
        let second = try plan(version: 2, from: "2026-03-01")
        let calendar = try PlanCalendar([plan(version: 1, from: "2026-01-01"), second])

        XCTAssertEqual(try calendar.arcWeek(for: try day("2026-03-01"), under: second), 1)
        let restart = try XCTUnwrap(try calendar.planDay(on: try day("2026-03-01")))
        XCTAssertEqual(restart.planVersion, try PlanVersion(2))
        XCTAssertEqual(restart.scheduledSession.distanceMeters, 16_000, "back to week 1 of the arc")
    }

    // MARK: - Ranges

    func testARangeOmitsDaysNoPlanGoverns() throws {
        let calendar = try PlanCalendar([plan(version: 1, from: "2026-01-01")])
        let days = try calendar.planDays(from: try day("2025-12-30"), through: try day("2026-01-03"))

        // 2025-12-30 and -31 precede the plan and are absent rather than empty entries.
        XCTAssertEqual(days.map(\.date.description), ["2026-01-01", "2026-01-02", "2026-01-03"])
    }

    func testARangeSpansAVersionChange() throws {
        let calendar = try PlanCalendar([
            plan(version: 1, from: "2026-01-01"),
            plan(version: 2, from: "2026-03-01"),
        ])
        let days = try calendar.planDays(from: try day("2026-02-27"), through: try day("2026-03-02"))

        XCTAssertEqual(
            days.map { "\($0.date) \($0.planVersion)" },
            ["2026-02-27 v1", "2026-02-28 v1", "2026-03-01 v2", "2026-03-02 v2"]
        )
    }

    // MARK: - Determinism

    /// The whole point (D1). Resolving the same day twice, from separately constructed
    /// calendars, must give the same answer — no hidden dependence on today's date, the
    /// device's time zone, or construction order.
    func testResolutionIsDeterministicAcrossSeparatelyBuiltCalendars() throws {
        let first = try PlanCalendar([
            plan(version: 2, from: "2026-03-01"),
            plan(version: 1, from: "2026-01-01"),
        ])
        let second = try PlanCalendar([
            plan(version: 1, from: "2026-01-01"),
            plan(version: 2, from: "2026-03-01"),
        ])

        for offset in stride(from: 0, through: 120, by: 13) {
            let subject = try day("2026-01-01").adding(days: offset)
            let a = try XCTUnwrap(try first.planDay(on: subject))
            let b = try XCTUnwrap(try second.planDay(on: subject))
            XCTAssertEqual(a, b, "\(subject)")
        }
    }
}
