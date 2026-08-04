import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-017 — the five §8 / FR-3.4 rollups, computed on read.
///
/// Every scenario below is reasoned against `Fixture.plan()` unless noted: effective
/// from **Thursday 2026-01-01**, template Monday rest / Tuesday easy 8 km / Wednesday
/// hard / Thursday easy 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km,
/// effective threshold 70. Arc weeks are Monday-anchored from **Monday 2025-12-29**
/// (the Monday on or before the plan's effective date), so **2026-01-05...11 is arc
/// week 2** — the week most of these tests use.
final class TalliesTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func workout(id: UUID, on dayText: String, durationSeconds: Double = 3_600) throws -> Workout {
        let start = try day(dayText).civilAnchor()
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: 8_000,
            activeEnergyKilocalories: 500,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 60)
        )
    }

    private func ledger(points: Int, workoutID: UUID, annotationPoints: Int? = nil) throws -> ScoreLedger {
        let base = try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: workoutID))
        guard let annotationPoints else { return base }
        return try base.annotated(with: try Fixture.annotation(points: annotationPoints, workoutID: workoutID))
    }

    private func calendar(_ plan: Plan? = nil) throws -> PlanCalendar {
        try PlanCalendar([plan ?? Fixture.plan()])
    }

    private func input(
        from: String,
        through: String,
        workouts: [Workout] = [],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget = .standard
    ) throws -> TalliesInput {
        try TalliesInput(
            from: try day(from),
            through: try day(through),
            timeZone: .gmt,
            workouts: workouts,
            scoreLedgers: scoreLedgers,
            planCalendar: planCalendar,
            restDayBudget: restDayBudget
        )
    }

    // MARK: - The combined week (rules 1, 2, 3 and unscored, all at once)

    /// Monday rest · Tuesday easy (effective) · Wednesday hard (effective) ·
    /// Thursday easy, no workout — the week's only miss, so budget 1 converts it ·
    /// Friday rest · Saturday easy, workout recorded but never scored · Sunday long
    /// (effective). Hand-worked expectations for every tally follow from just that.
    func testTheCombinedWeekExercisesAllFiveTalliesTogether() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let saturday = UUID()
        let sunday = UUID()

        let workouts = [
            try workout(id: tuesday, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tuesday: try ledger(points: 80, workoutID: tuesday),
            wednesday: try ledger(points: 75, workoutID: wednesday),
            sunday: try ledger(points: 90, workoutID: sunday),
            // Saturday deliberately has no entry: recorded, unscored.
        ]

        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-05",
                through: "2026-01-11",
                workouts: workouts,
                scoreLedgers: scoreLedgers,
                planCalendar: try calendar(),
                restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        )

        XCTAssertEqual(tallies.workoutDays, 4, "Tue, Wed, Sat, Sun each had a workout")
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 3, "Thu excluded (converted), Sat excluded (unscored)")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 3, "Tue, Wed, Sun all cleared the threshold")
        XCTAssertEqual(try XCTUnwrap(tallies.averageScore), (80.0 + 75.0 + 90.0) / 3, accuracy: 0.001)
        XCTAssertEqual(
            tallies.currentStreak, 3,
            "Sun, Sat(unscored, neutral), Fri(rest, neutral), Thu(converted, neutral), Wed, Tue all pass "
                + "through or extend; Mon(rest) is neutral too, so the walk reaches `from` with 3 extensions"
        )
        XCTAssertEqual(tallies.currentWeek.start.description, "2026-01-05")
        XCTAssertEqual(tallies.currentWeek.end.description, "2026-01-11")
        XCTAssertEqual(tallies.currentWeek.arcWeekIndex, 2)
    }

    func testResultIsIndependentOfWorkoutInputOrder() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let workouts = [
            try workout(id: tuesday, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tuesday: try ledger(points: 80, workoutID: tuesday),
            wednesday: try ledger(points: 75, workoutID: wednesday),
            sunday: try ledger(points: 90, workoutID: sunday),
        ]

        func compute(_ ordered: [Workout]) throws -> Tallies {
            try TalliesCalculator.compute(
                input(
                    from: "2026-01-05", through: "2026-01-11",
                    workouts: ordered, scoreLedgers: scoreLedgers,
                    planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 1)
                )
            )
        }

        let first = try compute(workouts)
        let shuffled = try compute(workouts.shuffled())
        XCTAssertEqual(first, shuffled)
    }

    // MARK: - Rule 1: annotations win; the auto-score stays recorded

    func testAnAnnotationRaisesAnIneffectiveAutoScoreToEffectiveForTallies() throws {
        let workoutID = UUID()
        let scoreLedger = try ledger(points: 50, workoutID: workoutID, annotationPoints: 85)
        XCTAssertEqual(scoreLedger.automatic.value.points, 50, "the auto-score is untouched")

        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-06", through: "2026-01-06",
                workouts: [try workout(id: workoutID, on: "2026-01-06")],
                scoreLedgers: [workoutID: scoreLedger],
                planCalendar: try calendar()
            )
        )

        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1, "the annotation, not the auto-score, decides")
        XCTAssertEqual(tallies.averageScore, 85, "average score reads the correction")
    }

    func testAnAnnotationLowersAnEffectiveAutoScoreToIneffectiveForTallies() throws {
        let workoutID = UUID()
        let scoreLedger = try ledger(points: 90, workoutID: workoutID, annotationPoints: 40)
        XCTAssertEqual(scoreLedger.automatic.value.points, 90, "the auto-score is untouched")

        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-06", through: "2026-01-06",
                workouts: [try workout(id: workoutID, on: "2026-01-06")],
                scoreLedgers: [workoutID: scoreLedger],
                planCalendar: try calendar()
            )
        )

        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "still counts against — the day was judged")
        XCTAssertEqual(tallies.averageScore, 40)
    }

    // MARK: - Unscored workouts

    func testAnUnscoredWorkoutCountsAsAWorkoutDayButNotAsEffectiveOrAverage() throws {
        let workoutID = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-07", through: "2026-01-07",
                workouts: [try workout(id: workoutID, on: "2026-01-07")],
                scoreLedgers: [:],
                planCalendar: try calendar()
            )
        )

        XCTAssertEqual(tallies.workoutDays, 1, "a workout happened")
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0, "not yet judged, so not counted against")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertNil(tallies.averageScore)
        XCTAssertEqual(tallies.currentStreak, 0, "neutral: neither extends nor breaks")
    }

    // MARK: - Rule 2: converted rest days are excluded, not merely spared

    func testAConvertedRestDayIsExcludedFromEffectiveDaysEntirely() throws {
        // Tue, Wed, Sat, Sun all executed and effective; Thursday (easy) is the
        // week's only miss, so a budget of 1 converts it.
        let tuesday = UUID()
        let wednesday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let workouts = [
            try workout(id: tuesday, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tuesday: try ledger(points: 80, workoutID: tuesday),
            wednesday: try ledger(points: 80, workoutID: wednesday),
            saturday: try ledger(points: 80, workoutID: saturday),
            sunday: try ledger(points: 80, workoutID: sunday),
        ]

        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-08", through: "2026-01-08", // Thursday alone
                workouts: workouts, scoreLedgers: scoreLedgers,
                planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0, "converted: dropped from the denominator too")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    // MARK: - Streak: what breaks it, what doesn't

    func testAGenuineUnconvertedMissBreaksTheStreak() throws {
        // Thursday missed, no budget to spend; Friday (rest) sits after it.
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-08", through: "2026-01-09",
                workouts: [], scoreLedgers: [:],
                planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 0)
            )
        )
        XCTAssertEqual(tallies.currentStreak, 0, "Friday is neutral, but Thursday's miss stops the walk")
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "Thursday counts against")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    func testAWorkoutScoredBelowThresholdBreaksTheStreakAndCountsAgainst() throws {
        let workoutID = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-07", through: "2026-01-07",
                workouts: [try workout(id: workoutID, on: "2026-01-07")],
                scoreLedgers: [workoutID: try ledger(points: 40, workoutID: workoutID)],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.currentStreak, 0)
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    /// The load-bearing streak decision: a plan's own prescribed rest day must not
    /// reset a streak, or the streak would be hostile to a plan that prescribes rest.
    func testAScheduledRestDayDoesNotBreakTheStreak() throws {
        let thursday = UUID()
        let saturday = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-08", through: "2026-01-10", // Thu, Fri(rest), Sat
                workouts: [
                    try workout(id: thursday, on: "2026-01-08"),
                    try workout(id: saturday, on: "2026-01-10"),
                ],
                scoreLedgers: [
                    thursday: try ledger(points: 90, workoutID: thursday),
                    saturday: try ledger(points: 90, workoutID: saturday),
                ],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.currentStreak, 2, "both effective days count; Friday's rest is skipped, not a break")
    }

    /// An unscored day is treated the same as rest for the streak: it neither extends
    /// nor breaks it, because there is no verdict yet to act on either way.
    func testAnUnscoredWorkoutDayDoesNotBreakOrExtendTheStreak() throws {
        let tuesday = UUID()
        let thursday = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-06", through: "2026-01-08", // Tue, Wed(unscored), Thu
                workouts: [
                    try workout(id: tuesday, on: "2026-01-06"),
                    try workout(id: UUID(), on: "2026-01-07"), // Wednesday: recorded, never scored
                    try workout(id: thursday, on: "2026-01-08"),
                ],
                scoreLedgers: [
                    tuesday: try ledger(points: 90, workoutID: tuesday),
                    thursday: try ledger(points: 90, workoutID: thursday),
                ],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.currentStreak, 2, "Wednesday is skipped, not counted, and does not break the walk")
    }

    /// `currentStreak` is a lower bound when the walk is stopped by `from` rather than
    /// by an actual break — it reports exactly what is visible, not more.
    func testStreakIsTruncatedAtFromRatherThanGuessingBeyondIt() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-06", through: "2026-01-07",
                workouts: [
                    try workout(id: tuesday, on: "2026-01-06"),
                    try workout(id: wednesday, on: "2026-01-07"),
                ],
                scoreLedgers: [
                    tuesday: try ledger(points: 90, workoutID: tuesday),
                    wednesday: try ledger(points: 90, workoutID: wednesday),
                ],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.currentStreak, 2, "exactly the two visible days — the walk never looks past `from`")
    }

    // MARK: - Days no plan governs

    /// Days before the plan's `effectiveFrom` are neither missed nor eligible — they
    /// pass through the streak walk exactly like a scheduled rest day.
    func testDaysNoPlanGovernsAreNeitherMissedNorEligibleAndDoNotBreakTheStreak() throws {
        let newYearsDay = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2025-12-30", through: "2026-01-02", // Dec 30, 31 (ungoverned), Jan 1 (easy), Jan 2 (rest)
                workouts: [try workout(id: newYearsDay, on: "2026-01-01")],
                scoreLedgers: [newYearsDay: try ledger(points: 90, workoutID: newYearsDay)],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.workoutDays, 1)
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "only Jan 1 was ever asked of")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1)
        XCTAssertEqual(
            tallies.currentStreak, 1,
            "Jan 2 (rest) and Jan 1 (effective) count/skip normally; Dec 31 and Dec 30 are ungoverned and neutral"
        )
    }

    // MARK: - Current week

    func testCurrentWeekArcIndexIsNilBeforeAnyPlanGovernsTheDay() throws {
        let tallies = try TalliesCalculator.compute(
            input(from: "2025-12-25", through: "2025-12-25", planCalendar: try calendar())
        )
        XCTAssertNil(tallies.currentWeek.arcWeekIndex)
        XCTAssertEqual(tallies.currentWeek.start.description, "2025-12-22", "Monday-anchored bounds still resolve")
        XCTAssertEqual(tallies.currentWeek.end.description, "2025-12-28")
    }

    func testCurrentWeekResolvesTheArcWeekOfThroughNotFrom() throws {
        let tallies = try TalliesCalculator.compute(
            input(from: "2026-01-05", through: "2026-01-11", planCalendar: try calendar())
        )
        XCTAssertEqual(tallies.currentWeek.arcWeekIndex, 2)
    }

    // MARK: - Empty range

    func testAnEmptyRangeWithNoWorkoutsAndNoPlanHasDefinedAnswersEverywhere() throws {
        let tallies = try TalliesCalculator.compute(
            input(from: "2026-06-01", through: "2026-06-01", planCalendar: nil)
        )
        XCTAssertEqual(tallies.workoutDays, 0)
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertNil(tallies.effectiveDays.rate)
        XCTAssertNil(tallies.averageScore)
        XCTAssertEqual(tallies.currentStreak, 0)
        XCTAssertNil(tallies.currentWeek.arcWeekIndex)
        XCTAssertEqual(tallies.currentWeek.start.description, "2026-06-01", "2026-06-01 is itself a Monday")
    }

    // MARK: - C1: whole-week resolution, honoured regardless of the queried slice

    /// A custom template — Mon easy / Tue hard / Wed rest / Thu long / Fri other /
    /// Sat easy / Sun rest — with **every non-rest day missed** and a budget of 1.
    /// The least-costly day is Friday (`.other`, tier 0); Monday, Tuesday, Thursday
    /// and Saturday all stay genuine misses.
    ///
    /// Querying **Monday alone** and **Friday alone** each pin one side of C1: a
    /// per-slice (rather than per-week) resolution would either convert Monday
    /// (it is the *only* candidate visible to a one-day query) or fail to convert
    /// Friday (nothing in a one-day query looks cheaper than doing nothing). Neither
    /// happens here, because `TalliesCalculator` always expands to the whole week.
    private func c1Plan() throws -> Plan {
        try Plan(
            version: PlanVersion(1),
            effectiveFrom: day("2026-01-01"),
            weeklyTemplate: WeeklyTemplate([
                .monday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .tuesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
                .wednesday: .rest,
                .thursday: ScheduledSession(kind: .long, distanceMeters: 18_000),
                .friday: ScheduledSession(kind: .other),
                .saturday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .sunday: .rest,
            ]),
            longRunArc: LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 18_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric()
        )
    }

    func testC1MondayAloneIsNotWronglyConvertedJustBecauseItIsTheOnlyVisibleCandidate() throws {
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-05", through: "2026-01-05", // Monday alone
                workouts: [], scoreLedgers: [:],
                planCalendar: try calendar(try c1Plan()), restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        )
        XCTAssertEqual(
            tallies.effectiveDays.eligibleCount, 1,
            "Monday stays a real miss — Friday is cheaper for the week as a whole"
        )
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    func testC1FridayAloneIsCorrectlyConvertedBecauseTheWholeWeekIsStillConsidered() throws {
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-09", through: "2026-01-09", // Friday alone
                workouts: [], scoreLedgers: [:],
                planCalendar: try calendar(try c1Plan()), restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        )
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0, "Friday is the week's cheapest miss and converts")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    // MARK: - TalliesInput validation

    func testTalliesInputRejectsFromAfterThrough() throws {
        assertThrows(
            .inconsistent,
            try TalliesInput(
                from: try day("2026-01-10"),
                through: try day("2026-01-05"),
                timeZone: .gmt,
                workouts: [],
                planCalendar: nil,
                restDayBudget: .standard
            )
        )
    }

    func testTalliesInputRejectsALedgerFiledUnderTheWrongWorkoutID() throws {
        let workoutID = UUID()
        let mismatchedKey = UUID()
        assertThrows(
            .inconsistent,
            try TalliesInput(
                from: try day("2026-01-05"),
                through: try day("2026-01-05"),
                timeZone: .gmt,
                workouts: [],
                scoreLedgers: [mismatchedKey: try ledger(points: 80, workoutID: workoutID)],
                planCalendar: nil,
                restDayBudget: .standard
            )
        )
    }

    // MARK: - EffectiveDayTally / TrainingWeek / Tallies invariants

    func testEffectiveDayTallyRejectsEffectiveCountExceedingEligibleCount() throws {
        assertThrows(.inconsistent, try EffectiveDayTally(effectiveCount: 2, eligibleCount: 1))
    }

    func testEffectiveDayTallyRateIsNilWhenNothingWasEligible() throws {
        let tally = try EffectiveDayTally(effectiveCount: 0, eligibleCount: 0)
        XCTAssertNil(tally.rate)
    }

    func testTrainingWeekRejectsEndBeforeStart() throws {
        assertThrows(
            .inconsistent,
            try TrainingWeek(start: try day("2026-01-05"), end: try day("2026-01-01"), arcWeekIndex: nil)
        )
    }

    func testTalliesRejectsFromAfterThrough() throws {
        assertThrows(
            .inconsistent,
            try Tallies(
                from: try day("2026-01-10"),
                through: try day("2026-01-05"),
                workoutDays: 0,
                effectiveDays: try EffectiveDayTally(effectiveCount: 0, eligibleCount: 0),
                averageScore: nil,
                currentStreak: 0,
                currentWeek: try TrainingWeek(start: try day("2026-01-05"), end: try day("2026-01-11"), arcWeekIndex: nil)
            )
        )
    }
}
