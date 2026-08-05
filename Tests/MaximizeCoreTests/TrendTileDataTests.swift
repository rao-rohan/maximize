import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-063 — the four FR-3.4 tiles built from an already-computed `Tallies` plus the
/// plan's arc. `Tallies` itself is MAX-017's territory and is not re-tested here; these
/// tests are about `TrendTileData`'s own job: formatting, and the mileage figure it
/// alone computes.
final class TrendTileDataTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func workout(on dayText: String, distanceMeters: Double?, id: UUID = UUID()) throws -> Workout {
        let start = try day(dayText).civilAnchor()
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 300,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(1_860)
        )
    }

    /// A bare `Tallies` with only `from`/`through` and the rollups a given test cares
    /// about — the rest filled with the most neutral value available, so each test
    /// states only what it is about.
    private func tallies(
        from: String,
        through: String,
        workoutDays: Int = 0,
        effectiveDays: EffectiveDayTally? = nil,
        averageScore: Double? = nil,
        currentStreak: Int = 0
    ) throws -> Tallies {
        let start = try day(from)
        return try Tallies(
            from: start,
            through: try day(through),
            workoutDays: workoutDays,
            effectiveDays: try effectiveDays ?? EffectiveDayTally(effectiveCount: 0, eligibleCount: 0),
            averageScore: averageScore,
            currentStreak: currentStreak,
            currentWeek: try TrainingWeek(
                start: start.startOfTrainingWeek(),
                end: start.startOfTrainingWeek().adding(days: 6),
                arcWeekIndex: nil
            )
        )
    }

    // MARK: - Mileage vs. arc

    func testMileageSumsActualAgainstTheArcsTargetForGovernedDays() throws {
        // Tuesday/Thursday/Saturday each ask 8/8/6 km per `Fixture.weeklyTemplate()`;
        // Sunday's long run is substituted from the arc (18 km, week 2). Monday/Friday
        // are rest (0 km ask). Total target for the week: 8+8+6+18 = 40 km.
        let plan = try Fixture.plan()
        let calendar = try PlanCalendar([plan])
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let workouts = [
            try workout(on: "2026-01-06", distanceMeters: 8_000),
            try workout(on: "2026-01-11", distanceMeters: 17_500),
        ]

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.mileage?.value, "25.50 / 40.00")
        XCTAssertEqual(data.mileage?.caption, "km vs. arc")
    }

    /// MAX-047: both the actual and the target convert — a mile is longer than a
    /// kilometre, so both figures shrink, not just one.
    func testMileageConvertsBothActualAndTargetWhenUnitIsMiles() throws {
        let plan = try Fixture.plan()
        let calendar = try PlanCalendar([plan])
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let workouts = [
            try workout(on: "2026-01-06", distanceMeters: 8_000),
            try workout(on: "2026-01-11", distanceMeters: 17_500),
        ]

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .miles
        )

        XCTAssertEqual(data.mileage?.value, "15.84 / 24.85")
        XCTAssertEqual(data.mileage?.caption, "mi vs. arc")
    }

    /// Zero workouts is a real, measured 0 km actual — not an absent tile — as long as
    /// a plan governs the interval.
    func testMileageActualIsZeroNotAbsentWhenNoWorkoutsWereRecorded() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.mileage?.value, "0.00 / 40.00")
    }

    /// No plan authored at all: the tile is absent, not "0.00 / 0.00" — a fabricated
    /// zero target would misreport an interval nothing has ever governed.
    func testMileageIsNilWhenNoPlanHasBeenAuthored() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertNil(data.mileage)
    }

    /// The whole interval precedes the plan's `effectiveFrom` — `planDays` comes back
    /// empty even though a `PlanCalendar` exists, and that must read the same as no
    /// plan at all.
    func testMileageIsNilWhenTheIntervalPredatesEveryPlanVersion() throws {
        let calendar = try PlanCalendar([try Fixture.plan()]) // effectiveFrom 2026-01-01
        let tallies = try tallies(from: "2025-12-01", through: "2025-12-07")

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        XCTAssertNil(data.mileage)
    }

    /// `TalliesInput`'s own contract widens `workouts` to whole Monday-first weeks
    /// (C1) — a workout that lands outside `tallies.from...tallies.through` must not
    /// leak into the actual-mileage sum.
    func testWorkoutsOutsideTheTalliesRangeAreExcludedFromTheActualSum() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let workouts = [
            try workout(on: "2026-01-06", distanceMeters: 8_000), // inside
            try workout(on: "2026-01-04", distanceMeters: 50_000), // Sunday before, outside
            try workout(on: "2026-01-12", distanceMeters: 50_000), // Monday after, outside
        ]

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.mileage?.value, "8.00 / 40.00")
    }

    // MARK: - Effective days (read, not recomputed)

    func testEffectiveDaysRendersTheNumeratorOverEligibleCount() throws {
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveDayTally(effectiveCount: 3, eligibleCount: 5)
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.effectiveDays?.value, "3/5")
        XCTAssertEqual(data.effectiveDays?.caption, "effective days")
    }

    func testEffectiveDaysIsNilWhenNothingWasEligible() throws {
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveDayTally(effectiveCount: 0, eligibleCount: 0)
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertNil(data.effectiveDays)
    }

    // MARK: - Streak (never absent)

    func testStreakIsRenderedEvenWhenZero() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", currentStreak: 0)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.streak.value, "0")
        XCTAssertEqual(data.streak.caption, "day streak")
    }

    func testStreakRendersAPositiveCount() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", currentStreak: 7)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.streak.value, "7")
    }

    // MARK: - Average score

    func testAverageScoreIsFormattedToOneDecimalPlace() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: 82.456)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.averageScore?.value, "82.5")
        XCTAssertEqual(data.averageScore?.caption, "avg score")
    }

    func testAverageScoreIsNilWhenNothingHasBeenScored() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: nil)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertNil(data.averageScore)
    }

    // MARK: - Tile ordering

    /// FR-3.4's own order: mileage vs. arc, effective days, streak, average score. Every
    /// figure present here so the ordering assertion is meaningful.
    func testTilesAreOrderedPerFR34AndOmitNils() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveDayTally(effectiveCount: 2, eligibleCount: 4),
            averageScore: 88,
            currentStreak: 3
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [try workout(on: "2026-01-06", distanceMeters: 8_000)],
            timeZone: .gmt,
            planCalendar: calendar,
            distanceUnit: .kilometers
        )

        XCTAssertEqual(data.tiles.map(\.caption), ["km vs. arc", "effective days", "day streak", "avg score"])
    }

    /// With mileage and effective days both absent, `tiles` drops straight to the two
    /// figures that remain — never a placeholder standing in for the missing ones.
    func testTilesOmitsAbsentFiguresEntirely() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: 70, currentStreak: 1)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.tiles.map(\.caption), ["day streak", "avg score"])
    }

    // MARK: - The tile set follows the span (MAX-083)

    /// The single table in `DashboardSpanPresentation.swift`, pinned. A view choosing a
    /// tile set for itself is exactly what this mapping exists to prevent.
    func testEachSpanMapsToItsOwnTileSet() {
        XCTAssertEqual(TrendIntervalKind.week.trendTileSet, .weekly)
        XCTAssertEqual(TrendIntervalKind.month.trendTileSet, .monthly)
        XCTAssertEqual(TrendIntervalKind.year.trendTileSet, .annual)
    }

    /// A month keeps the arc comparison and gains a consistency figure.
    func testAMonthAddsDaysTrainedAndKeepsTheArcComparison() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(
            from: "2026-01-01",
            through: "2026-01-31",
            workoutDays: 18,
            effectiveDays: try EffectiveDayTally(effectiveCount: 12, eligibleCount: 20),
            averageScore: 74,
            currentStreak: 3
        )

        let data = try tileData(
            kind: .month,
            workouts: [try workout(on: "2026-01-06", distanceMeters: 8_000)],
            tallies: tallies,
            planCalendar: calendar
        )

        XCTAssertNotNil(data.mileage)
        XCTAssertNil(data.totalDistance)
        XCTAssertEqual(data.effectiveDays?.value, "12/20")
        XCTAssertEqual(data.workoutDays?.value, "18")
        // "days trained", not "days run" (MAX-150): `Tallies.workoutDays` counts a day
        // whose only workout was a lift too, and the caption must not claim otherwise.
        XCTAssertEqual(data.workoutDays?.caption, "days trained")
        XCTAssertEqual(
            data.tiles.map(\.caption),
            ["km vs. arc", "effective days", "days trained", "day streak", "avg score"]
        )
    }

    /// A week does **not** get the days-trained tile: four days out of seven is already
    /// legible in the calendar row directly above the tiles.
    func testAWeekDoesNotCarryTheDaysTrainedTile() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", workoutDays: 4)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt,
            planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertNil(data.workoutDays)
    }

    /// The year drops the arc comparison for a bare total, and reports effectiveness as
    /// a rate with its denominator moved into the caption.
    func testAYearReportsTotalsAndRatesInsteadOfArcComparisons() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(
            from: "2026-01-01",
            through: "2026-12-31",
            workoutDays: 212,
            effectiveDays: try EffectiveDayTally(effectiveCount: 211, eligibleCount: 310),
            averageScore: 79.44,
            currentStreak: 5
        )

        let data = try tileData(
            kind: .year,
            workouts: [
                try workout(on: "2026-01-06", distanceMeters: 8_000),
                try workout(on: "2026-07-19", distanceMeters: 21_097),
            ],
            tallies: tallies,
            planCalendar: calendar
        )

        // Withheld even though a plan governs part of the year — see `TrendTileSet.annual`.
        XCTAssertNil(data.mileage)
        XCTAssertEqual(data.totalDistance?.value, "29.10")
        XCTAssertEqual(data.totalDistance?.caption, "km total")
        // 211/310 = 68.06%.
        XCTAssertEqual(data.effectiveDays?.value, "68%")
        XCTAssertEqual(data.effectiveDays?.caption, "effective, of 310 eligible days")
        XCTAssertEqual(data.workoutDays?.value, "212")
        XCTAssertEqual(
            data.tiles.map(\.caption),
            ["km total", "effective, of 310 eligible days", "days trained", "day streak", "avg score"]
        )
    }

    /// Absent is not zero at a year either: a year holding no runs has no distance to
    /// report, and "0.00 km" would state a measurement nobody took.
    func testAYearWithNoRunsHasNoTotalDistanceTile() throws {
        let tallies = try tallies(from: "2026-01-01", through: "2026-12-31")

        let data = try tileData(kind: .year, workouts: [], tallies: tallies, planCalendar: nil)

        XCTAssertNil(data.totalDistance)
        XCTAssertNil(data.mileage)
    }

    /// A year of runs that recorded no distance is a genuine zero — the distinction the
    /// test above depends on. Treadmill runs with no distance sample are the real case.
    func testAYearOfDistancelessRunsTotalsZeroRatherThanBeingAbsent() throws {
        let tallies = try tallies(from: "2026-01-01", through: "2026-12-31")

        let data = try tileData(
            kind: .year,
            workouts: [try workout(on: "2026-03-02", distanceMeters: nil)],
            tallies: tallies,
            planCalendar: nil
        )

        XCTAssertEqual(data.totalDistance?.value, "0.00")
    }

    /// The C1 widening applies at every span: a workout in the trailing partial week of
    /// December must not be counted into the year's total.
    func testAYearsTotalExcludesWorkoutsOutsideItsOwnDays() throws {
        let tallies = try tallies(from: "2026-01-01", through: "2026-12-31")

        let data = try tileData(
            kind: .year,
            workouts: [
                try workout(on: "2026-06-01", distanceMeters: 10_000), // inside
                try workout(on: "2025-12-29", distanceMeters: 50_000), // widened week before
                try workout(on: "2027-01-02", distanceMeters: 50_000), // widened week after
            ],
            tallies: tallies,
            planCalendar: nil
        )

        XCTAssertEqual(data.totalDistance?.value, "10.00")
    }

    /// A rate rounds to the nearest whole percent — no decimal, since at a year's
    /// denominator a tenth of a percent is a fraction of a day.
    func testTheAnnualEffectiveRateRoundsToAWholePercent() throws {
        let tallies = try tallies(
            from: "2026-01-01",
            through: "2026-12-31",
            effectiveDays: try EffectiveDayTally(effectiveCount: 2, eligibleCount: 3)
        )

        let data = try tileData(kind: .year, workouts: [], tallies: tallies, planCalendar: nil)

        XCTAssertEqual(data.effectiveDays?.value, "67%")
    }

    /// Nothing eligible is still an absence at a year — never "0%", which would read as
    /// "you failed every session" rather than "there was nothing to judge".
    func testTheAnnualEffectiveTileIsAbsentWhenNothingWasEligible() throws {
        let tallies = try tallies(
            from: "2026-01-01",
            through: "2026-12-31",
            effectiveDays: try EffectiveDayTally(effectiveCount: 0, eligibleCount: 0)
        )

        let data = try tileData(kind: .year, workouts: [], tallies: tallies, planCalendar: nil)

        XCTAssertNil(data.effectiveDays)
    }

    /// Convenience for the span tests: the two parameters they never vary.
    private func tileData(
        kind: TrendIntervalKind,
        workouts: [Workout],
        tallies: Tallies,
        planCalendar: PlanCalendar?
    ) throws -> TrendTileData {
        try TrendTileData(
            kind: kind,
            tallies: tallies,
            workouts: workouts,
            timeZone: .gmt,
            planCalendar: planCalendar,
            distanceUnit: .kilometers
        )
    }
}
