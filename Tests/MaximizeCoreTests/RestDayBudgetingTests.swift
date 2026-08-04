import Foundation
import XCTest
@testable import MaximizeCore

/// D9 + A6, pinned by hand-worked weeks.
///
/// The fixture week is **Monday 2026-01-05 through Sunday 2026-01-11**, chosen because
/// it lines up with `PlanCalendarTests`' anchor date (2026-01-01 is a Thursday, so the
/// Monday on or before it — and the first full Monday-first week after — is 2026-01-05).
///
/// The week's asks, by weekday:
///
/// | Mon 05 | Tue 06 | Wed 07 | Thu 08 | Fri 09 | Sat 10 | Sun 11 |
/// |---|---|---|---|---|---|---|
/// | easy   | hard   | rest   | long   | other  | easy   | rest   |
///
/// Wednesday and Sunday are scheduled rest, so Tuesday and Thursday are each adjacent
/// to a scheduled rest day; Saturday is adjacent to Sunday's rest. Monday and Friday
/// are not adjacent to any scheduled rest in this week.
final class RestDayBudgetingTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_767_312_000) // 2026-01-02T00:00:00Z

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func planDay(_ dateText: String, _ kind: ScheduledSessionKind, distanceMeters: Double? = nil) throws -> PlanDay {
        PlanDay(
            date: try day(dateText),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: kind, distanceMeters: distanceMeters)
        )
    }

    /// The full fixture week described above.
    private func fixtureWeek() throws -> [PlanDay] {
        [
            try planDay("2026-01-05", .easy),  // Mon
            try planDay("2026-01-06", .hard),  // Tue — adjacent to Wed rest
            try planDay("2026-01-07", .rest),  // Wed
            try planDay("2026-01-08", .long),  // Thu — adjacent to Wed rest
            try planDay("2026-01-09", .other), // Fri
            try planDay("2026-01-10", .easy),  // Sat — adjacent to Sun rest
            try planDay("2026-01-11", .rest),  // Sun
        ]
    }

    private func budget(_ n: Int) throws -> RestDayBudget {
        try RestDayBudget(daysPerWeek: n)
    }

    // MARK: - Ordering: kind tier, then adjacency, then date

    /// Every non-rest day in the fixture week is missed (no workouts at all). With a
    /// budget of 3, the least-costly-first order is:
    ///
    /// 1. Fri (`.other`, tier 0)
    /// 2. Sat (`.easy`, tier 1, adjacent to Sunday's rest)
    /// 3. Mon (`.easy`, tier 1, not adjacent) — loses the adjacency tie-break to Sat
    ///
    /// leaving Tue (`.hard`) and Thu (`.long`) — the two most expensive days — red.
    func testLeastCostlyOrderingSpendsTierThenAdjacencyThenDate() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: fixtureWeek(),
            workoutDays: [],
            budget: budget(3),
            createdAt: createdAt
        )

        XCTAssertEqual(
            overrides.map(\.date.description),
            ["2026-01-05", "2026-01-09", "2026-01-10"],
            "sorted ascending by date: Fri (other), Sat (easy, rest-adjacent), Mon (easy)"
        )
        let converted = Set(overrides.map(\.date.description))
        XCTAssertFalse(converted.contains("2026-01-06"), "Tuesday's hard session stays red")
        XCTAssertFalse(converted.contains("2026-01-08"), "Thursday's long run stays red")
        XCTAssertTrue(overrides.allSatisfy(\.convertedFromMissed))
    }

    /// Two missed days of the same kind and the same adjacency can only be broken by
    /// date. Both Tuesday-analogues here are `.hard` and both sit next to a scheduled
    /// rest day, so only the date decides.
    func testDateIsTheTieBreakFloorWhenKindAndAdjacencyMatch() throws {
        let days = [
            try planDay("2026-01-05", .rest),
            try planDay("2026-01-06", .hard), // adjacent to Mon rest
            try planDay("2026-01-07", .rest),
            try planDay("2026-01-08", .hard), // adjacent to Wed rest
            try planDay("2026-01-09", .rest),
        ]

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: days,
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )

        XCTAssertEqual(overrides.map(\.date.description), ["2026-01-06"], "earlier date wins the tie")
    }

    // MARK: - Budget boundaries

    func testBudgetZeroConvertsNothingEvenWithMisses() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: fixtureWeek(),
            workoutDays: [],
            budget: budget(0),
            createdAt: createdAt
        )
        XCTAssertEqual(overrides, [])
    }

    func testAWeekWithNoMissesConvertsNothing() throws {
        let week = try fixtureWeek()
        let workoutDays = Set(week.filter(\.canBeMissed).map(\.date))

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: week,
            workoutDays: workoutDays,
            budget: budget(5),
            createdAt: createdAt
        )
        XCTAssertEqual(overrides, [])
    }

    /// A scheduled rest day is never "missed" (`PlanDay.canBeMissed`), so it never
    /// consumes budget and never receives an override, whether or not it happens to
    /// coincide with a logged workout.
    func testAScheduledRestDayIsNeverConverted() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: fixtureWeek(),
            workoutDays: [],
            budget: budget(7),
            createdAt: createdAt
        )
        XCTAssertFalse(overrides.map(\.date.description).contains("2026-01-07"))
        XCTAssertFalse(overrides.map(\.date.description).contains("2026-01-11"))
    }

    /// Budget larger than the number of missed days converts every missed day and
    /// stops — it does not manufacture overrides for days that were not missed.
    func testBudgetLargerThanMissCountConvertsExactlyTheMisses() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: fixtureWeek(),
            workoutDays: [],
            budget: budget(7),
            createdAt: createdAt
        )
        // Mon, Tue, Thu, Fri, Sat are missed; Wed and Sun are scheduled rest.
        XCTAssertEqual(overrides.count, 5)
    }

    // MARK: - Week boundaries

    /// A range spanning two training weeks must not let either week borrow the other's
    /// budget: with N = 1, each week converts at most one day, for two total — never
    /// zero (double-charged to one week) and never more than two (carried forward).
    func testARangeSpanningAWeekBoundarySpendsEachWeeksBudgetSeparately() throws {
        let weekOne = try fixtureWeek() // 2026-01-05...11, budget spent on Fri (other, cheapest)
        let weekTwo = [
            try planDay("2026-01-12", .easy),  // Mon
            try planDay("2026-01-13", .hard),  // Tue
            try planDay("2026-01-14", .rest),  // Wed
            try planDay("2026-01-15", .long),  // Thu
            try planDay("2026-01-16", .rest),  // Fri
            try planDay("2026-01-17", .easy),  // Sat — adjacent to Fri rest
            try planDay("2026-01-18", .rest),  // Sun
        ]

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: weekOne + weekTwo,
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )

        XCTAssertEqual(overrides.count, 2, "one conversion per week, not zero and not carried forward")
        XCTAssertEqual(overrides.map(\.date.description).sorted(), ["2026-01-09", "2026-01-17"])
    }

    /// Same as above, but the boundary is fed in scrambled order and with the weeks'
    /// days interleaved, to confirm grouping is by calendar week, not by input order.
    func testWeekGroupingDoesNotDependOnInputOrder() throws {
        let weekOne = try fixtureWeek()
        let weekTwo = [
            try planDay("2026-01-12", .easy),
            try planDay("2026-01-13", .hard),
        ]
        let interleaved = [weekTwo, weekOne].flatMap { $0 }.shuffled()

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: interleaved,
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )

        // Week two here has only two missed candidates (Mon easy, Tue hard); the
        // cheaper one converts.
        XCTAssertEqual(overrides.map(\.date.description).sorted(), ["2026-01-09", "2026-01-12"])
    }

    // MARK: - Partial weeks

    /// A 3-day slice at the edge of a range still gets the **full** weekly budget, not
    /// a prorated share — see the type's documentation. Here the slice is Fri–Sun of
    /// the fixture week (`.other`, `.easy`, `.rest`); with N = 1 the single cheapest
    /// candidate in what's visible (`.other`) converts, exactly as it would if the
    /// full week were present.
    func testAPartialWeekAtTheEdgeOfARangeStillGetsTheFullBudget() throws {
        let week = try fixtureWeek()
        let cutoff = try day("2026-01-09")
        let partial = week.filter { $0.date >= cutoff } // Fri, Sat, Sun

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: partial,
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )

        XCTAssertEqual(overrides.map(\.date.description), ["2026-01-09"])
    }

    /// A single day is the extreme case of a partial week: it still gets the full
    /// budget, not `budget * (1/7)`.
    func testASingleDayPartialWeekStillGetsTheFullBudget() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: [try planDay("2026-01-09", .other)],
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )
        XCTAssertEqual(overrides.map(\.date.description), ["2026-01-09"])
    }

    // MARK: - Determinism

    func testResultIsIndependentOfInputOrderAndStable() throws {
        let week = try fixtureWeek()
        let shuffled = week.shuffled()

        let first = try RestDayBudgeting.convertingMissedDays(
            planDays: week, workoutDays: [], budget: budget(2), createdAt: createdAt
        )
        let second = try RestDayBudgeting.convertingMissedDays(
            planDays: shuffled, workoutDays: [], budget: budget(2), createdAt: createdAt
        )
        let third = try RestDayBudgeting.convertingMissedDays(
            planDays: week, workoutDays: [], budget: budget(2), createdAt: createdAt
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, third)
    }

    // MARK: - Days no plan governs

    /// A day the plan does not govern has no `PlanDay` entry at all (per
    /// `PlanCalendar.planDays(from:through:)`), so it never enters this function and is
    /// never a candidate — proven here by simply never including it, and budget still
    /// only spends on the days that are present.
    func testDaysNotPresentAreNeitherMissedNorCounted() throws {
        // Only Friday (other) and Saturday (easy) are visible — Monday through
        // Thursday are simply absent, standing in for "no plan governs them".
        let sparse = [
            try planDay("2026-01-09", .other),
            try planDay("2026-01-10", .easy),
        ]

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: sparse,
            workoutDays: [],
            budget: budget(5),
            createdAt: createdAt
        )

        // Both convert (budget exceeds candidates); nothing for the unseen days exists
        // to convert or to stay red.
        XCTAssertEqual(overrides.map(\.date.description).sorted(), ["2026-01-09", "2026-01-10"])
    }

    // MARK: - createdAt

    func testCreatedAtIsStampedFromTheParameterNotTheClock() throws {
        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: [try planDay("2026-01-09", .other)],
            workoutDays: [],
            budget: budget(1),
            createdAt: createdAt
        )
        XCTAssertEqual(overrides.first?.createdAt, createdAt)
    }
}
