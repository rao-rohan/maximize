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
        effectiveDays: EffectiveDayTally? = nil,
        averageScore: Double? = nil,
        currentStreak: Int = 0
    ) throws -> Tallies {
        let start = try day(from)
        return try Tallies(
            from: start,
            through: try day(through),
            workoutDays: 0,
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

        let data = try TrendTileData(tallies: tallies, workouts: workouts, timeZone: .gmt, planCalendar: calendar)

        XCTAssertEqual(data.mileage?.value, "25.50 / 40.00")
        XCTAssertEqual(data.mileage?.caption, "km vs. arc")
    }

    /// Zero workouts is a real, measured 0 km actual — not an absent tile — as long as
    /// a plan governs the interval.
    func testMileageActualIsZeroNotAbsentWhenNoWorkoutsWereRecorded() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: calendar)

        XCTAssertEqual(data.mileage?.value, "0.00 / 40.00")
    }

    /// No plan authored at all: the tile is absent, not "0.00 / 0.00" — a fabricated
    /// zero target would misreport an interval nothing has ever governed.
    func testMileageIsNilWhenNoPlanHasBeenAuthored() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11")

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertNil(data.mileage)
    }

    /// The whole interval precedes the plan's `effectiveFrom` — `planDays` comes back
    /// empty even though a `PlanCalendar` exists, and that must read the same as no
    /// plan at all.
    func testMileageIsNilWhenTheIntervalPredatesEveryPlanVersion() throws {
        let calendar = try PlanCalendar([try Fixture.plan()]) // effectiveFrom 2026-01-01
        let tallies = try tallies(from: "2025-12-01", through: "2025-12-07")

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: calendar)

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

        let data = try TrendTileData(tallies: tallies, workouts: workouts, timeZone: .gmt, planCalendar: calendar)

        XCTAssertEqual(data.mileage?.value, "8.00 / 40.00")
    }

    // MARK: - Effective days (read, not recomputed)

    func testEffectiveDaysRendersTheNumeratorOverEligibleCount() throws {
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveDayTally(effectiveCount: 3, eligibleCount: 5)
        )

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertEqual(data.effectiveDays?.value, "3/5")
        XCTAssertEqual(data.effectiveDays?.caption, "effective days")
    }

    func testEffectiveDaysIsNilWhenNothingWasEligible() throws {
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveDayTally(effectiveCount: 0, eligibleCount: 0)
        )

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertNil(data.effectiveDays)
    }

    // MARK: - Streak (never absent)

    func testStreakIsRenderedEvenWhenZero() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", currentStreak: 0)

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertEqual(data.streak.value, "0")
        XCTAssertEqual(data.streak.caption, "day streak")
    }

    func testStreakRendersAPositiveCount() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", currentStreak: 7)

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertEqual(data.streak.value, "7")
    }

    // MARK: - Average score

    func testAverageScoreIsFormattedToOneDecimalPlace() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: 82.456)

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertEqual(data.averageScore?.value, "82.5")
        XCTAssertEqual(data.averageScore?.caption, "avg score")
    }

    func testAverageScoreIsNilWhenNothingHasBeenScored() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: nil)

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

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
            tallies: tallies,
            workouts: [try workout(on: "2026-01-06", distanceMeters: 8_000)],
            timeZone: .gmt,
            planCalendar: calendar
        )

        XCTAssertEqual(data.tiles.map(\.caption), ["km vs. arc", "effective days", "day streak", "avg score"])
    }

    /// With mileage and effective days both absent, `tiles` drops straight to the two
    /// figures that remain — never a placeholder standing in for the missing ones.
    func testTilesOmitsAbsentFiguresEntirely() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: 70, currentStreak: 1)

        let data = try TrendTileData(tallies: tallies, workouts: [], timeZone: .gmt, planCalendar: nil)

        XCTAssertEqual(data.tiles.map(\.caption), ["day streak", "avg score"])
    }
}
