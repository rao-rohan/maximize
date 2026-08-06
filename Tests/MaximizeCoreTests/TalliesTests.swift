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

    /// `today` defaults to a day after every date these tests reason about, so the
    /// whole suite is "the past" unless a test deliberately says otherwise — the same
    /// convention `ScoreCalendarTests.defaultToday` uses, for the same reason: every
    /// pre-MAX-110 expectation still reads as written, because a scheduled day with
    /// nothing recorded has been and gone.
    private static let defaultToday = "2026-12-31"

    private func input(
        from: String,
        through: String,
        today: String = TalliesTests.defaultToday,
        workouts: [Workout] = [],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget = .standard
    ) throws -> TalliesInput {
        try TalliesInput(
            from: try day(from),
            through: try day(through),
            timeZone: .gmt,
            today: try day(today),
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

    // MARK: - MAX-110: today

    /// The defect this ticket exists to fix, reproduced directly. Without `today`, the
    /// walk starts at `through` (Sunday) and meets Sunday's own unrecorded long run
    /// first — a genuine break under the old rule, since `restDayBudget` here is zero
    /// and nothing folds it into rest. The streak would read 0 even though Tuesday and
    /// Wednesday were both run and both cleared the threshold.
    ///
    /// Thursday (`today`) is empty here — nobody has trained yet today — so the walk
    /// visits it, finds nothing, and steps past it neutrally rather than stopping; it
    /// never reaches Friday/Saturday/Sunday at all, since those are strictly after
    /// `today`. See `testATodayAlreadyTrainedCountsTowardTheStreakImmediately` for the
    /// case where `today` itself already has a hit to count.
    func testAStreakThatSpansTodayIgnoresScheduledDaysNotYetReached() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-05", through: "2026-01-11", // the full week; Fri-Sun are still ahead
                today: "2026-01-08", // Thursday: itself empty so far, visited but neutral
                workouts: [
                    try workout(id: tuesday, on: "2026-01-06"),
                    try workout(id: wednesday, on: "2026-01-07"),
                ],
                scoreLedgers: [
                    tuesday: try ledger(points: 90, workoutID: tuesday),
                    wednesday: try ledger(points: 90, workoutID: wednesday),
                ],
                planCalendar: try calendar(),
                restDayBudget: try RestDayBudget(daysPerWeek: 0)
            )
        )
        XCTAssertEqual(
            tallies.currentStreak, 2,
            "Thu (today, empty) is skipped rather than breaking; Wed and Tue both extend; "
                + "Fri/Sat/Sun are strictly after today and are never reached"
        )
        XCTAssertEqual(
            tallies.effectiveDays.eligibleCount, 2,
            "only Tue and Wed are decided and ask something (Mon is rest; Thu-Sun are still ahead)"
        )
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 2)
    }

    /// The regression test for the defect a review caught in this ticket's first draft:
    /// an earlier version of the walk stopped at `today - 1`, so a run already
    /// completed and scored *this morning* did not count until tomorrow — a smaller
    /// version of the exact "the app is wrong about me" complaint the ticket exists to
    /// fix. `ScoreCalendar.resolve` already treats a hit today as decided (it resolves
    /// to `.scored`, never `.forthcoming`); the streak walk must agree.
    func testATodayAlreadyTrainedCountsTowardTheStreakImmediately() throws {
        let workoutID = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-08", through: "2026-01-08",
                today: "2026-01-08", // today itself, already run and scored
                workouts: [try workout(id: workoutID, on: "2026-01-08")],
                scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.currentStreak, 1, "a hit today is a decided fact, counted the moment it happens")
    }

    /// The mirror image, and the reason the exception for `today` is narrow rather than
    /// "today is always neutral": a run already performed today and already scored
    /// below the threshold is just as decided as a hit, so it breaks the streak the
    /// same day instead of waiting for tomorrow to notice.
    func testATodayScoredBelowThresholdBreaksTheStreakImmediately() throws {
        let yesterday = UUID()
        let workoutID = UUID()
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-07", through: "2026-01-08", // Wed (effective) then Thu (today, ineffective)
                today: "2026-01-08",
                workouts: [
                    try workout(id: yesterday, on: "2026-01-07"),
                    try workout(id: workoutID, on: "2026-01-08"),
                ],
                scoreLedgers: [
                    yesterday: try ledger(points: 90, workoutID: yesterday),
                    workoutID: try ledger(points: 30, workoutID: workoutID),
                ],
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(
            tallies.currentStreak, 0,
            "today's own ineffective score breaks the walk before it ever reaches yesterday's hit"
        )
    }

    /// The invariant the ticket calls out explicitly: an interval that lies wholly in
    /// the past must produce the same streak whether `today` is the day right after it
    /// ends or is pushed arbitrarily further into the future — `today` never enters the
    /// walk once it is past `through`. Reasoned against the same week
    /// `testTheCombinedWeekExercisesAllFiveTalliesTogether` already worked out by hand.
    func testAnIntervalEntirelyInThePastAgreesWithTheDefaultFarFutureToday() throws {
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

        func compute(today: String) throws -> Tallies {
            try TalliesCalculator.compute(
                input(
                    from: "2026-01-05", through: "2026-01-11",
                    today: today,
                    workouts: workouts, scoreLedgers: scoreLedgers,
                    planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 1)
                )
            )
        }

        // The day right after the interval ends…
        let barelyPast = try compute(today: "2026-01-12")
        // …and a today pushed arbitrarily further out.
        let farFuture = try compute(today: TalliesTests.defaultToday)

        XCTAssertEqual(barelyPast, farFuture, "an interval wholly in the past must not care how far past `today` is")
        XCTAssertEqual(barelyPast.currentStreak, 3, "matches the hand-worked value from the combined-week test")
        XCTAssertEqual(barelyPast.effectiveDays.eligibleCount, 3)
        XCTAssertEqual(barelyPast.effectiveDays.effectiveCount, 3)
    }

    /// An interval that has not started yet has no decided day at all — the walk must
    /// not run, and every day is withheld from `eligibleCount`.
    func testAnIntervalEntirelyInTheFutureHasNoEligibleDaysAndZeroStreak() throws {
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-05", through: "2026-01-11",
                today: "2026-01-01", // before the interval even starts
                planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        )
        XCTAssertEqual(tallies.currentStreak, 0, "nothing in the interval has a known outcome yet")
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    /// The boundary is strict, matching `ScoreCalendar`: `today` itself has not been
    /// decided yet, so a single-day query landing exactly on `today` finds nothing
    /// eligible — not because nothing was asked, but because the day is not yet in.
    func testADayEqualToTodayDoesNotCountAsEligible() throws {
        let tallies = try TalliesCalculator.compute(
            input(
                from: "2026-01-08", through: "2026-01-08", // Thursday, easy
                today: "2026-01-08",
                planCalendar: try calendar()
            )
        )
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 0, "today itself is not yet decided")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertEqual(
            tallies.currentStreak, 0,
            "the walk does visit today, finds it empty, and skips it neutrally — but there is no day "
                + "before it in range to have extended the streak in the first place"
        )
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

    // MARK: - Calendar/tiles agreement (MAX-110)

    /// **The strongest guarantee this ticket can leave behind**, per CLAUDE.md's "the
    /// calendar and the tiles must agree": `TalliesCalculator` and `ScoreCalendar` are
    /// two independent readers of the same records, and they must reach the same
    /// verdict for every day. This reasons against `c1Plan()`, `today` Wednesday, and a
    /// budget of 1 — the exact scenario `ScoreCalendarTests
    /// .testTheRestDayBudgetIsNotSpentOnDaysThatHaveNotHappened` pins on the calendar
    /// side, so the two suites can be read side by side. Monday converts (the week's
    /// only decided candidate cheap enough); Tuesday stays a genuine miss; Wednesday is
    /// scheduled rest; Thursday through Sunday have not happened yet.
    ///
    /// Rather than hard-coding the expected counts a second time, this derives them
    /// from `ScoreCalendar.resolve`'s own output — so a future change that moves the
    /// two calculators out of step fails here even if neither suite's hand-worked
    /// numbers happen to still be right.
    func testEffectiveObligationTallyAgreesWithTheScoreCalendarOverTheSameInterval() throws {
        let plan = try c1Plan()
        let planCalendar = try calendar(plan)
        let from = try day("2026-01-05")
        let through = try day("2026-01-11")
        let today = try day("2026-01-07")
        let budget = try RestDayBudget(daysPerWeek: 1)

        let tallies = try TalliesCalculator.compute(
            TalliesInput(
                from: from, through: through, timeZone: .gmt, today: today,
                workouts: [], scoreLedgers: [:],
                planCalendar: planCalendar, restDayBudget: budget
            )
        )

        let calendarDays = try ScoreCalendar.resolve(
            from: from, through: through, timeZone: .gmt, today: today,
            workouts: [], scoreLedgers: [:],
            planCalendar: planCalendar, restDayBudget: budget
        )

        var expectedEligible = 0
        var expectedEffective = 0
        for cell in calendarDays {
            switch cell.state {
            case .missed:
                expectedEligible += 1
            case .scored(let band, _):
                expectedEligible += 1
                if band == .effective { expectedEffective += 1 }
            case .partiallyMet:
                // MAX-135. Unreachable under this run-only fixture, and mapped rather
                // than lumped in with the neutral states because the state's own
                // definition fixes the arithmetic: it takes one met obligation and one
                // unmet one, so the day it describes contributes exactly two decided
                // chances of which one was taken. If the cell and the tile ever disagree
                // about that, this is where it shows.
                expectedEligible += 2
                expectedEffective += 1
            case .awaitingScore, .noVerdict, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
                // `.noVerdict` (MAX-126) joins `.awaitingScore` here for the reason it is
                // a separate state everywhere else and the same one here: a day with no
                // stored score has no verdict to count on either side of the tally, and
                // whether one is still coming does not change that.
                break // never eligible — matches `effectiveDayTally`'s own exclusions
            }
        }

        XCTAssertEqual(expectedEligible, 1, "sanity: only Tuesday's genuine miss is decided, eligible, and unconverted")
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, expectedEligible)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, expectedEffective)
    }

    /// Independently reconstructs the streak from `ScoreCalendarDay.state` — the same
    /// states the calendar itself paints — so the test below does not simply restate
    /// `TalliesCalculator.streak`'s own branches to check them against themselves. This
    /// is the streak's counterpart to `expectedEligible`/`expectedEffective` above.
    /// `calendarDays` must be ascending and cover at least `from...through`.
    private func expectedStreak(
        calendarDays: [ScoreCalendarDay],
        from: CalendarDay,
        through: CalendarDay,
        today: CalendarDay
    ) throws -> Int {
        let walkStart = min(through, today)
        guard walkStart >= from else { return 0 }
        let byDate = Dictionary(uniqueKeysWithValues: calendarDays.map { ($0.date, $0) })
        var streak = 0
        var day = walkStart
        while true {
            if let cell = byDate[day] {
                switch cell.state {
                case .scored(let band, _):
                    if band == .effective {
                        streak += 1
                    } else {
                        return streak // breaks — matches `TalliesCalculator`'s own rule
                    }
                case .missed:
                    return streak // breaks
                case .partiallyMet:
                    // §6.3's all-of: a day that dropped one of its two asks did not do
                    // everything the plan asked, so it breaks the streak exactly as a
                    // whole miss does — which is the rule `DayObligations
                    // .streakContribution` applies and this reconstruction must mirror.
                    return streak // breaks
                case .awaitingScore, .noVerdict, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
                    // `.noVerdict` is neutral for the same reason `.awaitingScore` is: the
                    // athlete showed up, and nothing judged it. A lift neither extends a
                    // streak of effective runs nor breaks one.
                    break // neutral — steps past without extending or breaking
                }
            }
            guard day != from else { break }
            day = try day.adding(days: -1)
        }
        return streak
    }

    /// The property the coordinator asked for explicitly: **the streak tile must not
    /// contradict the calendar cell for the same day.** Reasons against `c1Plan()` with
    /// `today` Thursday, a budget of 1, and — the case the eligibility-only agreement
    /// test above did not cover — a workout already completed and scored *today*.
    /// Monday converts (cheapest known miss); Tuesday stays a genuine miss; Thursday
    /// (today) already has an effective run. `ScoreCalendar` resolves Thursday to
    /// `.scored`, not `.forthcoming`, exactly because a hit is decided the moment it
    /// happens — the assertion below is that the streak agrees, both by cross-checking
    /// against an independent reconstruction of the calendar's own states and by the
    /// hand-worked number.
    func testCurrentStreakAgreesWithTheScoreCalendarWhenTodayIsAlreadyAHit() throws {
        let plan = try c1Plan()
        let planCalendar = try calendar(plan)
        let from = try day("2026-01-05")
        let through = try day("2026-01-11")
        let today = try day("2026-01-08") // Thursday
        let budget = try RestDayBudget(daysPerWeek: 1)
        let thursdayWorkout = try workout(id: UUID(), on: "2026-01-08")
        let scoreLedgers: [UUID: ScoreLedger] = [
            thursdayWorkout.id: try ledger(points: 90, workoutID: thursdayWorkout.id),
        ]

        let tallies = try TalliesCalculator.compute(
            TalliesInput(
                from: from, through: through, timeZone: .gmt, today: today,
                workouts: [thursdayWorkout], scoreLedgers: scoreLedgers,
                planCalendar: planCalendar, restDayBudget: budget
            )
        )

        let calendarDays = try ScoreCalendar.resolve(
            from: from, through: through, timeZone: .gmt, today: today,
            workouts: [thursdayWorkout], scoreLedgers: scoreLedgers,
            planCalendar: planCalendar, restDayBudget: budget
        )

        let todayCell = try XCTUnwrap(calendarDays.first { $0.date == today })
        XCTAssertEqual(
            todayCell.state, .scored(band: .effective, activityType: .running),
            "sanity: today's hit shows on the calendar as scored, not forthcoming (MAX-105)"
        )
        XCTAssertEqual(
            tallies.currentStreak,
            try expectedStreak(calendarDays: calendarDays, from: from, through: through, today: today),
            "the streak tile must not contradict the calendar cell for the same day"
        )
        XCTAssertEqual(
            tallies.currentStreak, 1,
            "Thursday's hit counts today; Tuesday's earlier unconverted miss stops the walk before Monday"
        )
    }

    // MARK: - TalliesInput validation

    func testTalliesInputRejectsFromAfterThrough() throws {
        assertThrows(
            .inconsistent,
            try TalliesInput(
                from: try day("2026-01-10"),
                through: try day("2026-01-05"),
                timeZone: .gmt,
                today: try day(TalliesTests.defaultToday),
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
                today: try day(TalliesTests.defaultToday),
                workouts: [],
                scoreLedgers: [mismatchedKey: try ledger(points: 80, workoutID: workoutID)],
                planCalendar: nil,
                restDayBudget: .standard
            )
        )
    }

    // MARK: - EffectiveObligationTally / TrainingWeek / Tallies invariants

    func testEffectiveObligationTallyRejectsEffectiveCountExceedingEligibleCount() throws {
        assertThrows(.inconsistent, try EffectiveObligationTally(effectiveCount: 2, eligibleCount: 1))
    }

    func testEffectiveObligationTallyRateIsNilWhenNothingWasEligible() throws {
        let tally = try EffectiveObligationTally(effectiveCount: 0, eligibleCount: 0)
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
                effectiveDays: try EffectiveObligationTally(effectiveCount: 0, eligibleCount: 0),
                averageScore: nil,
                currentStreak: 0,
                currentWeek: try TrainingWeek(start: try day("2026-01-05"), end: try day("2026-01-11"), arcWeekIndex: nil)
            )
        )
    }
}
