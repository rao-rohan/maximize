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
        effectiveDays: EffectiveObligationTally? = nil,
        averageScore: Double? = nil,
        averageScoreExcludedMiscategorisedCount: Int = 0,
        currentStreak: Int = 0
    ) throws -> Tallies {
        let start = try day(from)
        return try Tallies(
            from: start,
            through: try day(through),
            workoutDays: workoutDays,
            effectiveDays: try effectiveDays ?? EffectiveObligationTally(effectiveCount: 0, eligibleCount: 0),
            averageScore: averageScore,
            averageScoreExcludedMiscategorisedCount: averageScoreExcludedMiscategorisedCount,
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
            effectiveDays: try EffectiveObligationTally(effectiveCount: 3, eligibleCount: 5)
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.effectiveDays?.value, "3/5")
        // MAX-140: "sessions", not "days" — since MAX-134 the denominator counts
        // prescribed obligations, and a caption still saying "days" would be wrong the
        // moment a week carries a lift.
        XCTAssertEqual(data.effectiveDays?.caption, "effective sessions")
    }

    func testEffectiveDaysIsNilWhenNothingWasEligible() throws {
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveObligationTally(effectiveCount: 0, eligibleCount: 0)
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

    // MARK: - MAX-160: the average score's caption says when scores were excluded

    /// The value is untouched — `Tallies.averageScore` already reflects the exclusion
    /// (D2) — but the caption now says one was left out and how many, so the athlete can
    /// tell this figure apart from an ordinary mean without opening the workout.
    func testAverageScoreCaptionNamesOneExcludedScore() throws {
        let tallies = try tallies(
            from: "2026-01-05", through: "2026-01-11",
            averageScore: 82.456, averageScoreExcludedMiscategorisedCount: 1
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.averageScore?.value, "82.5", "the value itself is unaffected by the caption")
        XCTAssertEqual(
            data.averageScore?.caption,
            "avg score (excludes 1 score from before the plan distinguished lifting)"
        )
    }

    /// The plural, so "1 score" never reads as "1 scores."
    func testAverageScoreCaptionPluralisesMoreThanOneExcludedScore() throws {
        let tallies = try tallies(
            from: "2026-01-05", through: "2026-01-11",
            averageScore: 70, averageScoreExcludedMiscategorisedCount: 3
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(
            data.averageScore?.caption,
            "avg score (excludes 3 scores from before the plan distinguished lifting)"
        )
    }

    /// The ordinary caption, unchanged, when nothing was excluded — the property that
    /// keeps a single-discipline history's tile byte-identical to its pre-MAX-160 self.
    func testAverageScoreCaptionIsUnchangedWhenNothingWasExcluded() throws {
        let tallies = try tallies(
            from: "2026-01-05", through: "2026-01-11",
            averageScore: 70, averageScoreExcludedMiscategorisedCount: 0
        )

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.averageScore?.caption, "avg score")
    }

    // MARK: - Tile ordering

    /// FR-3.4's own order: mileage vs. arc, effective days, streak, average score. Every
    /// figure present here so the ordering assertion is meaningful.
    func testTilesAreOrderedPerFR34AndOmitNils() throws {
        let calendar = try PlanCalendar([try Fixture.plan()])
        let tallies = try tallies(
            from: "2026-01-05",
            through: "2026-01-11",
            effectiveDays: try EffectiveObligationTally(effectiveCount: 2, eligibleCount: 4),
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

        XCTAssertEqual(
            data.tiles.map(\.caption),
            ["km vs. arc", "effective sessions", "day streak", "building load history", "avg score"]
        )
    }

    /// With mileage and effective days both absent, `tiles` drops straight to the two
    /// figures that remain — never a placeholder standing in for the missing ones.
    func testTilesOmitsAbsentFiguresEntirely() throws {
        let tallies = try tallies(from: "2026-01-05", through: "2026-01-11", averageScore: 70, currentStreak: 1)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers
        )

        XCTAssertEqual(data.tiles.map(\.caption), ["day streak", "building load history", "avg score"])
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
            effectiveDays: try EffectiveObligationTally(effectiveCount: 12, eligibleCount: 20),
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
            [
                "km vs. arc", "effective sessions", "days trained",
                "day streak", "building load history", "avg score",
            ]
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
            effectiveDays: try EffectiveObligationTally(effectiveCount: 211, eligibleCount: 310),
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
        XCTAssertEqual(data.effectiveDays?.caption, "effective, of 310 eligible sessions")
        XCTAssertEqual(data.workoutDays?.value, "212")
        XCTAssertEqual(
            data.tiles.map(\.caption),
            [
                "km total", "effective, of 310 eligible sessions", "days trained",
                "day streak", "building load history", "avg score",
            ]
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
            effectiveDays: try EffectiveObligationTally(effectiveCount: 2, eligibleCount: 3)
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
            effectiveDays: try EffectiveObligationTally(effectiveCount: 0, eligibleCount: 0)
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

    // MARK: - MAX-140: the effective-sessions caption end to end, through the real
    // obligation arithmetic (not a hand-built `Tallies`) — the same integration the tests
    // above deliberately avoid, per this file's own header comment that `Tallies` is not
    // re-tested here. These two prove the *caption* stays honest against `TalliesCalculator`
    // itself rather than against a synthetic tally this file made up.

    private func scoredWorkout(
        id: UUID,
        on dayText: String,
        activityType: ActivityType = .running,
        startOffsetSeconds: Double = 0
    ) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(startOffsetSeconds)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: activityType.isRun ? 8_000 : nil,
            activeEnergyKilocalories: 500,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(3_660)
        )
    }

    private func ledger(
        points: Int,
        workoutID: UUID,
        scheduledKind: ScheduledSessionKind = .easy,
        actualClassification: WorkoutClassification = .easy
    ) throws -> ScoreLedger {
        try ScoreLedger(
            automatic: try Fixture.score(
                points: points,
                workoutID: workoutID,
                scheduledKind: scheduledKind,
                actualClassification: actualClassification
            )
        )
    }

    /// `Fixture.plan()`'s run slot, unmodified: Monday/Friday rest; Tuesday/Thursday easy
    /// 8 km; Wednesday hard; Saturday easy 6 km; Sunday long 18 km. Five eligible days —
    /// the same figure `ObligationTalliesTests`' header comment reasons against.
    ///
    /// **This is a single-discipline history** — the lift slot is never prescribed — so
    /// per LIFTING-SPEC §6.2's own acceptance criterion, obligation-counting and
    /// day-counting must land on the identical number. This test is that criterion,
    /// exercised at the tile layer rather than only at `Tallies`'.
    func testASingleDisciplineWeekReachesTheTileWithNumbersMAX134LeftUnchanged() throws {
        // Monday and Friday are rest — no obligation, no workout, nothing to assert
        // against them.
        let tue = UUID(), wed = UUID(), thu = UUID(), sat = UUID(), sun = UUID()
        let calendar = try PlanCalendar([try Fixture.plan()]) // no lift ever prescribed

        // Every eligible day (Tue/Wed/Thu/Sat/Sun) scores effective except Wednesday,
        // which is scored below threshold — four of five met, the same shape
        // `ObligationTalliesTests` reasons against for a run-only week.
        let workouts = [
            try scoredWorkout(id: tue, on: "2026-01-06"),
            try scoredWorkout(id: wed, on: "2026-01-07"),
            try scoredWorkout(id: thu, on: "2026-01-08"),
            try scoredWorkout(id: sat, on: "2026-01-10"),
            try scoredWorkout(id: sun, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tue: try ledger(points: 80, workoutID: tue),
            wed: try ledger(points: 30, workoutID: wed, scheduledKind: .hard, actualClassification: .hard),
            thu: try ledger(points: 80, workoutID: thu),
            sat: try ledger(points: 80, workoutID: sat),
            sun: try ledger(points: 80, workoutID: sun, scheduledKind: .long, actualClassification: .long),
        ]

        let input = try TalliesInput(
            from: try day("2026-01-05"),
            through: try day("2026-01-11"),
            timeZone: .gmt,
            today: try day("2026-01-12"),
            workouts: workouts,
            scoreLedgers: scoreLedgers,
            planCalendar: calendar,
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        let tallies = try TalliesCalculator.compute(input)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        // The number a day-counting reader already expects: 4 of 5 days met, exactly as
        // it would have read before MAX-134 — proving the arithmetic this tile displays
        // is unmoved, only its caption changed.
        XCTAssertEqual(data.effectiveDays?.value, "4/5")
        XCTAssertEqual(data.effectiveDays?.caption, "effective sessions")
    }

    /// A day prescribing both a run and a lift is **two** obligations, and the tile's
    /// denominator must show it — the exact case the old "effective days" caption could
    /// not describe honestly (it counted days; the number now counts chances).
    func testEffectiveSessionsCountsAMixedDisciplineDayAsTwoObligations() throws {
        let run = UUID()
        let calendar = try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])

        // Tuesday only: the run happened and scored well; the lift never happened and the
        // week's rest-day budget is zero, so nothing forgives it.
        let workouts = [try scoredWorkout(id: run, on: "2026-01-06")]
        let scoreLedgers: [UUID: ScoreLedger] = [run: try ledger(points: 80, workoutID: run)]

        let input = try TalliesInput(
            from: try day("2026-01-06"),
            through: try day("2026-01-06"),
            timeZone: .gmt,
            today: try day("2026-01-07"),
            workouts: workouts,
            scoreLedgers: scoreLedgers,
            planCalendar: calendar,
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        let tallies = try TalliesCalculator.compute(input)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        // Two chances (run + lift), one met — the flattering old day-level "1/1" is gone.
        XCTAssertEqual(data.effectiveDays?.value, "1/2")
        XCTAssertEqual(data.effectiveDays?.caption, "effective sessions")
    }

    // MARK: - MAX-140: average score is per scored workout

    /// A day prescribing and completing both a run and a lift contributes **two** terms
    /// to the average — the per-workout decision this ticket makes deliberately (see
    /// `TrendTileData.averageScore`'s own documentation), not a by-product of anything
    /// this ticket changed in `Tallies`.
    func testAverageScoreCountsBothDisciplinesOnAMixedDay() throws {
        let run = UUID()
        let lift = UUID()
        let calendar = try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])

        let workouts = [
            try scoredWorkout(id: run, on: "2026-01-06"),
            try scoredWorkout(
                id: lift, on: "2026-01-06",
                activityType: .traditionalStrengthTraining, startOffsetSeconds: 3_600 * 8
            ),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            run: try ledger(points: 80, workoutID: run),
            lift: try ledger(points: 60, workoutID: lift, scheduledKind: .lift, actualClassification: .lift),
        ]

        let input = try TalliesInput(
            from: try day("2026-01-06"),
            through: try day("2026-01-06"),
            timeZone: .gmt,
            today: try day("2026-01-07"),
            workouts: workouts,
            scoreLedgers: scoreLedgers,
            planCalendar: calendar,
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        let tallies = try TalliesCalculator.compute(input)

        let data = try TrendTileData(
            kind: .week, tallies: tallies,
            workouts: workouts, timeZone: .gmt, planCalendar: calendar, distanceUnit: .kilometers
        )

        // (80 + 60) / 2 = 70.0 — both scored efforts counted, neither collapsed to a
        // single best-of-the-day figure the way `effectiveDays` would.
        XCTAssertEqual(data.averageScore?.value, "70.0")
    }

    // MARK: - MAX-178: load balance is a formatted, already-computed reading

    /// `.buildingHistory` renders as a real tile — the designed absence state, not a
    /// blank and not the tile simply missing from `tiles`.
    func testLoadBalanceRendersTheBuildingHistoryStateAsARealTile() throws {
        let data = try TrendTileData(
            kind: .week,
            tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
            loadBalance: .buildingHistory(daysRecorded: 6, daysNeeded: 28)
        )

        XCTAssertEqual(data.loadBalance.value, "6/28 days")
        XCTAssertEqual(data.loadBalance.caption, "building load history")
        XCTAssertTrue(data.tiles.map(\.caption).contains("building load history"))
    }

    /// The ordinary case: a ratio, formatted to two decimal places, with a plain caption
    /// that names no verdict.
    func testLoadBalanceRendersTheRatioToTwoDecimalPlaces() throws {
        let balance = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 120,
            chronicStrainPoints: 160,
            chronicWeeklyAveragePoints: 40,
            ratio: 3.0,
            acuteWorkoutsWithoutStrain: 0,
            chronicWorkoutsWithoutStrain: 0
        )

        let data = try TrendTileData(
            kind: .week,
            tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
            loadBalance: .available(balance)
        )

        XCTAssertEqual(data.loadBalance.value, "3.00")
        XCTAssertEqual(data.loadBalance.caption, "acute:chronic load")
    }

    /// MAX-176's own instruction for this tile: the caption names how many of the acute
    /// window's sessions carried no strain, so a sum quietly missing coverage does not
    /// read the same as a sum of everything that happened.
    func testLoadBalanceCaptionNamesStrainlessSessionsInTheAcuteWindow() throws {
        let balance = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 80,
            chronicStrainPoints: 300,
            chronicWeeklyAveragePoints: 75,
            ratio: 80.0 / 75.0,
            acuteWorkoutsWithoutStrain: 2,
            chronicWorkoutsWithoutStrain: 2
        )

        let data = try TrendTileData(
            kind: .week,
            tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
            loadBalance: .available(balance)
        )

        XCTAssertEqual(data.loadBalance.caption, "acute:chronic load (2 sessions this week without strain)")
    }

    /// The singular, so "1 session" never reads as "1 sessions."
    func testLoadBalanceCaptionSingularisesOneStrainlessSession() throws {
        let balance = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 80,
            chronicStrainPoints: 300,
            chronicWeeklyAveragePoints: 75,
            ratio: 80.0 / 75.0,
            acuteWorkoutsWithoutStrain: 1,
            chronicWorkoutsWithoutStrain: 1
        )

        let data = try TrendTileData(
            kind: .week,
            tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
            loadBalance: .available(balance)
        )

        XCTAssertEqual(data.loadBalance.caption, "acute:chronic load (1 session this week without strain)")
    }

    /// No chronic baseline: the ratio is withheld, but the acute figure — genuinely
    /// known — is still shown rather than the tile going blank.
    func testLoadBalanceShowsTheAcuteFigureAloneWhenThereIsNoChronicBaseline() throws {
        // No strain anywhere in the window (`LoadBalance.init` ties `ratio == nil` to
        // `chronicWeeklyAveragePoints == 0`): the acute figure, genuinely 0 here, is
        // still shown — the same "measured, and containing nothing" reading
        // `WorkoutStrain` gives a zero-span curve.
        let balance = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 0,
            chronicStrainPoints: 0,
            chronicWeeklyAveragePoints: 0,
            ratio: nil,
            acuteWorkoutsWithoutStrain: 0,
            chronicWorkoutsWithoutStrain: 3
        )

        let data = try TrendTileData(
            kind: .week,
            tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
            workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
            loadBalance: .available(balance)
        )

        XCTAssertEqual(data.loadBalance.value, "0 pts")
        XCTAssertEqual(data.loadBalance.caption, "7-day strain — no 4-week baseline yet")
    }

    /// The tile carries no colour, verdict word or threshold language — only a number
    /// and a plain description of what it is. Every state this type can render one
    /// through actual `TrendTileData` output, not a hand-typed copy of the strings
    /// above, so a caption drifting toward "high"/"low"/"risk" wording later would
    /// actually fail this test rather than only failing to be re-pinned by it.
    func testLoadBalanceTilesNeverEditorialise() throws {
        func renderedTile(_ reading: LoadBalanceReading) throws -> TrendTileData.Tile {
            try TrendTileData(
                kind: .week,
                tallies: try tallies(from: "2026-01-05", through: "2026-01-11"),
                workouts: [], timeZone: .gmt, planCalendar: nil, distanceUnit: .kilometers,
                loadBalance: reading
            ).loadBalance
        }

        let available = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 120, chronicStrainPoints: 160, chronicWeeklyAveragePoints: 40,
            ratio: 3.0, acuteWorkoutsWithoutStrain: 1, chronicWorkoutsWithoutStrain: 1
        )
        let noBaseline = try LoadBalance(
            anchor: try day("2026-01-28"),
            acuteStrainPoints: 0, chronicStrainPoints: 0, chronicWeeklyAveragePoints: 0,
            ratio: nil, acuteWorkoutsWithoutStrain: 0, chronicWorkoutsWithoutStrain: 3
        )

        let renderedTiles = [
            try renderedTile(.buildingHistory(daysRecorded: 6, daysNeeded: 28)),
            try renderedTile(.available(available)),
            try renderedTile(.available(noBaseline)),
        ]

        let bannedWords = ["risk", "overtrain", "danger", "high", "low", "warning", "caution", "alert"]
        for renderedTile in renderedTiles {
            let combined = (renderedTile.value + " " + renderedTile.caption).lowercased()
            for word in bannedWords {
                XCTAssertFalse(
                    combined.contains(word),
                    "\"\(renderedTile.value)\" / \"\(renderedTile.caption)\" must not carry coaching "
                        + "language — MAX-178 forbids editorialising the ratio"
                )
            }
        }
    }
}
