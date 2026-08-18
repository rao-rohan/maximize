import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-134 / A19 — the unit of account is the obligation, not the day.
///
/// Reasoned against `Fixture.plan(lift:)`: effective from **Thursday 2026-01-01**, run
/// slot Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday easy 8 km / Friday
/// rest / Saturday easy 6 km / Sunday long 18 km, effective threshold 70. Tests that
/// need a two-obligation day put a lift on **Tuesday**, so Tuesday 2026-01-06 asks for a
/// run *and* a lift and every other day is unchanged.
final class ObligationTalliesTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// `today` sits after everything these tests reason about, so the whole suite is
    /// "the past" unless a test says otherwise — the same convention `TalliesTests` and
    /// `ScoreCalendarTests` both use.
    private static let defaultToday = "2026-12-31"

    private func workout(
        id: UUID,
        on dayText: String,
        activityType: ActivityType = .running,
        startOffsetSeconds: Double = 0,
        durationSeconds: Double = 3_600
    ) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(startOffsetSeconds)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: activityType.isRun ? 8_000 : nil,
            activeEnergyKilocalories: 500,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 60)
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

    /// A lift's ledger. Supplied directly rather than produced by the pipeline, which
    /// keeps this suite about A19's arithmetic — MAX-168 has since opened the gate that
    /// makes such a ledger reachable, and it reaches it under exactly these conditions: a
    /// day prescribing a lift, judged by a band that names `.lift`.
    private func liftLedger(points: Int, workoutID: UUID) throws -> ScoreLedger {
        try ledger(
            points: points,
            workoutID: workoutID,
            scheduledKind: .lift,
            actualClassification: .lift
        )
    }

    private func planWithATuesdayLift() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])
    }

    private func runOnlyPlan() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan()])
    }

    private func computeTallies(
        from: String,
        through: String,
        today: String = ObligationTalliesTests.defaultToday,
        workouts: [Workout] = [],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget = .standard
    ) throws -> Tallies {
        try TalliesCalculator.compute(
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
        )
    }

    // MARK: - A day prescribing both

    /// Tuesday asks for a run and a lift; the run happened and scored well, the lift
    /// never happened. **One obligation met out of two**, and the day does not extend the
    /// streak — this is the whole of A19 in one assertion. Under the old day-level rule
    /// this same Tuesday read 1/1 and extended the streak, which is the flattering
    /// arithmetic §6.1 rejects.
    func testADayPrescribingBothCountsTwiceWhenOnlyTheRunIsMet() throws {
        let run = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06", // Tuesday
            workouts: [try workout(id: run, on: "2026-01-06")],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2, "a run and a lift are two chances")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1, "only the run was met")
        XCTAssertEqual(tallies.currentStreak, 0, "meeting one obligation is not meeting the day")
        XCTAssertEqual(tallies.workoutDays, 1, "showing up is still counted in days, not obligations")
    }

    /// Both halves done and scored. 2/2, and the day extends the streak — a day is not
    /// penalised for being asked twice when it delivered twice.
    func testADayPrescribingBothCountsTwiceWhenBothAreMet() throws {
        let run = UUID()
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: run, on: "2026-01-06"),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining,
                    startOffsetSeconds: 3_600 * 8
                ),
            ],
            scoreLedgers: [
                run: try ledger(points: 80, workoutID: run),
                lift: try liftLedger(points: 85, workoutID: lift),
            ],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 2)
        XCTAssertEqual(tallies.currentStreak, 1, "every obligation met, so the day extends it")
        XCTAssertEqual(tallies.workoutDays, 1, "two sessions, one day shown up for")
    }

    /// Nothing recorded at all, and no budget to forgive either half: two eligible
    /// chances, neither met, streak broken.
    func testADayPrescribingBothCountsTwoMissesWhenNeitherIsMet() throws {
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertEqual(tallies.currentStreak, 0)
    }

    /// The mirror of the first test, and the one that says lifting is not decorative:
    /// the *lift* was met and the run skipped. Symmetric arithmetic, no discipline
    /// weighted above the other (§6.5 rejects weighting outright).
    func testADayPrescribingBothIsEquallyUnmetWhenOnlyTheLiftIsMet() throws {
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining
                )
            ],
            scoreLedgers: [lift: try liftLedger(points: 85, workoutID: lift)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1)
        XCTAssertEqual(tallies.currentStreak, 0, "the run was still skipped")
    }

    // MARK: - The streak across such a day

    /// A week where Tuesday asks for both, the lift is skipped, and every other day is
    /// met. The streak walks back from Sunday and stops at Tuesday — it does **not**
    /// reach Monday, and the days before Tuesday are unreachable however good they were.
    ///
    /// Sun (long, met) · Sat (easy, met) · Fri (rest, neutral) · Thu (easy, met) ·
    /// Wed (hard, met) · Tue (run met, lift skipped → breaks). Four extending days.
    func testTheStreakStopsAtADayWhoseSecondObligationWasSkipped() throws {
        let wednesday = UUID()
        let thursday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let tuesdayRun = UUID()

        let workouts = [
            try workout(id: tuesdayRun, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: thursday, on: "2026-01-08"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tuesdayRun: try ledger(points: 80, workoutID: tuesdayRun),
            wednesday: try ledger(points: 80, workoutID: wednesday),
            thursday: try ledger(points: 80, workoutID: thursday),
            saturday: try ledger(points: 80, workoutID: saturday),
            sunday: try ledger(points: 80, workoutID: sunday),
        ]

        let withLift = try computeTallies(
            from: "2026-01-05", through: "2026-01-11",
            workouts: workouts, scoreLedgers: scoreLedgers,
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(withLift.currentStreak, 4, "Sun, Sat, Thu, Wed extend; Tuesday's skipped lift breaks")
        XCTAssertEqual(withLift.effectiveDays.eligibleCount, 6, "five runs plus one lift")
        XCTAssertEqual(withLift.effectiveDays.effectiveCount, 5)

        // The identical week under the identical plan minus the lift slot: the same five
        // runs now satisfy everything asked, so the streak runs the whole way back.
        let withoutLift = try computeTallies(
            from: "2026-01-05", through: "2026-01-11",
            workouts: workouts, scoreLedgers: scoreLedgers,
            planCalendar: try runOnlyPlan(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(withoutLift.currentStreak, 5)
        XCTAssertEqual(withoutLift.effectiveDays.eligibleCount, 5)
        XCTAssertEqual(withoutLift.effectiveDays.effectiveCount, 5)
    }

    /// A lift recorded but not yet scored is **neutral**, exactly as an unscored run is:
    /// the athlete did not skip anything, and there is no verdict yet to count for them.
    /// So the day neither extends nor breaks, and the lift reaches neither side of the
    /// ratio while the run still reaches both.
    func testAnUnscoredLiftLeavesTheDayUndecidedRatherThanBroken() throws {
        let run = UUID()
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: run, on: "2026-01-06"),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining,
                    startOffsetSeconds: 3_600 * 8
                ),
            ],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "the unscored lift is not yet a chance decided")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1)
        XCTAssertEqual(tallies.currentStreak, 0, "not every obligation is *met*, so the day does not extend")
    }

    // MARK: - Two attempts at one obligation (§5, deliberately unchanged)

    /// The warm-up jog. Two runs on a day asking for one run: the best one decides, and
    /// the worse one does not drag the day down. A19 changes the rule *across*
    /// obligations, not *within* one, and this is the assertion that says so.
    func testTwoAttemptsAtOneObligationStillResolveBestOf() throws {
        let warmUp = UUID()
        let real = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: warmUp, on: "2026-01-06", startOffsetSeconds: 0),
                try workout(id: real, on: "2026-01-06", startOffsetSeconds: 3_600 * 6),
            ],
            scoreLedgers: [
                warmUp: try ledger(points: 20, workoutID: warmUp),
                real: try ledger(points: 90, workoutID: real),
            ],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "one ask, however many attempts")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1, "judged by the best session")
        XCTAssertEqual(tallies.currentStreak, 1)
    }

    /// And the same generosity within each half of a two-obligation day: a bad warm-up
    /// jog alongside a good run, plus a good lift, is still 2/2. The best-of rule is per
    /// obligation, not per day, which is only visible when the day has two.
    func testBestOfAppliesWithinEachObligationOfATwoObligationDay() throws {
        let warmUp = UUID()
        let real = UUID()
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: warmUp, on: "2026-01-06", startOffsetSeconds: 0),
                try workout(id: real, on: "2026-01-06", startOffsetSeconds: 3_600 * 6),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining,
                    startOffsetSeconds: 3_600 * 10
                ),
            ],
            scoreLedgers: [
                warmUp: try ledger(points: 20, workoutID: warmUp),
                real: try ledger(points: 90, workoutID: real),
                lift: try liftLedger(points: 80, workoutID: lift),
            ],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 2)
        XCTAssertEqual(tallies.currentStreak, 1)
    }

    // MARK: - The rest-day budget under the new unit (§6.4)

    /// **N per week stays N conversions per week, and they are conversions of
    /// obligations.** Tuesday asks for a run and a lift and neither happened; the rest of
    /// the week is covered. A budget of 1 forgives exactly one of Tuesday's two halves —
    /// the run, because `.easy` (tier 1) is cheaper than `.lift` (tier 2) — and the other
    /// half stays a miss. Converting the whole day would have forgiven both, which is a
    /// budget that buys more than it was sold for.
    func testTheBudgetForgivesOneObligationNotTheWholeDay() throws {
        let wednesday = UUID()
        let thursday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let workouts = [
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: thursday, on: "2026-01-08"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            wednesday: try ledger(points: 80, workoutID: wednesday),
            thursday: try ledger(points: 80, workoutID: thursday),
            saturday: try ledger(points: 80, workoutID: saturday),
            sunday: try ledger(points: 80, workoutID: sunday),
        ]

        let tallies = try computeTallies(
            from: "2026-01-05", through: "2026-01-11",
            workouts: workouts, scoreLedgers: scoreLedgers,
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 1)
        )

        // Four met runs + Tuesday's forgiven run (excluded entirely) + Tuesday's
        // unforgiven lift (eligible, unmet) = 5 eligible, 4 effective.
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 5)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 4)
        XCTAssertEqual(tallies.currentStreak, 4, "Sun, Sat, Thu, Wed; Tuesday's unforgiven lift breaks it")
    }

    /// Spend two on the same Tuesday and the day is fully forgiven: both obligations are
    /// dropped from both sides of the ratio, and the day goes neutral for the streak
    /// rather than extending it. The budget's own arithmetic, one obligation at a time.
    func testABudgetOfTwoCanForgiveBothHalvesOfOneDay() throws {
        let wednesday = UUID()
        let thursday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let workouts = [
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: thursday, on: "2026-01-08"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            wednesday: try ledger(points: 80, workoutID: wednesday),
            thursday: try ledger(points: 80, workoutID: thursday),
            saturday: try ledger(points: 80, workoutID: saturday),
            sunday: try ledger(points: 80, workoutID: sunday),
        ]

        let tallies = try computeTallies(
            from: "2026-01-05", through: "2026-01-11",
            workouts: workouts, scoreLedgers: scoreLedgers,
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 2)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 4, "both of Tuesday's halves are excluded")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 4)
        XCTAssertEqual(
            tallies.currentStreak, 4,
            "Sun, Sat, Thu, Wed extend; Tuesday is neutral because both halves were forgiven, so "
                + "the walk passes through it to Monday's rest and reaches `from` without breaking"
        )
    }

    /// The budget ranks a missed lift between a missed easy run and a missed hard
    /// session (`costTier`, unreordered by this ticket), and the ranking is over
    /// obligations drawn from **both** slots of the same week.
    func testTheBudgetRanksAMissedLiftAgainstMissedRunsOfTheSameWeek() throws {
        // Tuesday: easy run (tier 1) + lift (tier 2). Wednesday: hard (tier 3).
        // Nothing recorded all week; a budget of 2 takes the two cheapest.
        let conversions = try RestDayBudgeting.convertingMissedObligations(
            planDays: try PlanCalendar(
                [try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])]
            ).planDays(from: try day("2026-01-05"), through: try day("2026-01-07")),
            workoutDisciplines: [:],
            budget: try RestDayBudget(daysPerWeek: 2),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            conversions.map { "\($0.date) \($0.discipline.rawValue)" },
            ["2026-01-06 run", "2026-01-06 lift"],
            "the easy run then the lift; Wednesday's hard session is dearer than both"
        )
    }

    // MARK: - The resolver's own interface (MAX-135 reads this, not its own roll-up)

    /// The shared roll-up §7.3 requires, exercised directly: the mixed day reports one
    /// met obligation carrying a band, and one unmet obligation naming its discipline and
    /// the kind that was asked for. Those are the three facts §7.2's `partiallyMet` state
    /// is built from, and MAX-135 must read them here rather than recomputing them.
    func testTheResolverExposesTheMixedDayMAX135Needs() throws {
        let run = UUID()
        let planDay = try XCTUnwrap(
            try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])
                .planDay(on: try day("2026-01-06"))
        )
        let runWorkout = try workout(id: run, on: "2026-01-06")

        let resolved = DayObligationResolver.resolve(
            date: try day("2026-01-06"),
            planDay: planDay,
            workouts: [runWorkout],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            outcomeIsKnown: true
        )

        XCTAssertEqual(resolved.resolutions.map(\.discipline), [.run, .lift], "run slot first, always")
        XCTAssertFalse(resolved.isFullyMet)
        XCTAssertEqual(resolved.streakContribution, .breaks)
        XCTAssertEqual(resolved.eligibleCount, 2)
        XCTAssertEqual(resolved.effectiveCount, 1)

        let met = try XCTUnwrap(resolved.metObligations.first)
        XCTAssertEqual(met.discipline, .run)
        XCTAssertEqual(met.band, .effective, "the calendar's colour, from the immutable auto-score")
        XCTAssertEqual(met.decidingWorkoutID, run)

        let unmet = try XCTUnwrap(resolved.unmetObligations.first)
        XCTAssertEqual(unmet.discipline, .lift)
        XCTAssertEqual(unmet.outcome, .missed)
        XCTAssertEqual(unmet.scheduledSession.kind, .lift)
        XCTAssertNil(unmet.band, "nothing of that discipline was scored, so there is no band to draw")
    }

    /// A day the plan asks nothing of has no obligations, and is neutral rather than
    /// broken — the load-bearing choice the streak has always made, restated in the unit
    /// this ticket introduced.
    func testADayWithNoObligationsIsEmptyAndNeutral() throws {
        let planDay = try XCTUnwrap(
            try runOnlyPlan().planDay(on: try day("2026-01-05")) // Monday: rest, both slots
        )
        let resolved = DayObligationResolver.resolve(
            date: try day("2026-01-05"),
            planDay: planDay,
            workouts: [],
            outcomeIsKnown: true
        )

        XCTAssertTrue(resolved.isEmpty)
        XCTAssertEqual(resolved.eligibleCount, 0)
        XCTAssertEqual(resolved.streakContribution, .neutral)
        XCTAssertFalse(resolved.isFullyMet, "nothing was asked, so nothing was met")
    }

    /// A day no plan version governs resolves to no obligations at all, rather than to a
    /// day whose asks are unknown.
    func testADayNoPlanGovernsHasNoObligations() throws {
        let resolved = DayObligationResolver.resolve(
            date: try day("2025-12-25"),
            planDay: nil,
            workouts: [],
            outcomeIsKnown: true
        )
        XCTAssertTrue(resolved.isEmpty)
        XCTAssertEqual(resolved.streakContribution, .neutral)
    }

    /// The two reads `ObligationResolution` deliberately carries side by side: an
    /// annotation raises the obligation to met (§8 — tallies use the correction) while
    /// the band still reports the immutable auto-score (D1/D4/D8 — the calendar never
    /// colours from a correction). A single "was this good" field would have had to pick
    /// one and silently break the other.
    func testAnAnnotationMovesTheOutcomeButNeverTheBand() throws {
        let run = UUID()
        let planDay = try XCTUnwrap(try runOnlyPlan().planDay(on: try day("2026-01-06")))
        let corrected = try ScoreLedger(automatic: try Fixture.score(points: 30, workoutID: run))
            .annotated(with: try Fixture.annotation(points: 90, workoutID: run))

        let resolved = DayObligationResolver.resolve(
            date: try day("2026-01-06"),
            planDay: planDay,
            workouts: [try workout(id: run, on: "2026-01-06")],
            scoreLedgers: [run: corrected],
            outcomeIsKnown: true
        )

        let resolution = try XCTUnwrap(resolved.resolution(for: .run))
        XCTAssertEqual(resolution.outcome, .met, "the correction is what the tallies count")
        XCTAssertEqual(resolution.band, .ineffective, "the auto-score is what the calendar draws")
    }

    // MARK: - The one class of historical day that moves, deliberately

    /// **A scheduled run day whose only recorded workout was a lift is now a miss.**
    ///
    /// This is the single exception to A19's no-op claim, and it is deliberate. §6.2 says
    /// each obligation is resolved "against the workouts of its own discipline" and §5
    /// confirms a lift belongs to the lift slot and never to the run's — so a lift cannot
    /// meet the run obligation, and it cannot excuse it either.
    ///
    /// The old rule tested whether *anything* was recorded that day. Under it, this
    /// Tuesday was "recorded but unscored": excluded from both sides of the ratio and
    /// neutral for the streak, so a lift silently covered a skipped run. That is A19's own
    /// argument arriving from the other side — meeting one obligation is not meeting
    /// another — and preserving it would have preserved the bug the ticket exists to name.
    ///
    /// The honest statement of the acceptance criterion is therefore: **no historical day
    /// moves whose recorded workouts all belong to the discipline that day prescribed.**
    /// `testSingleDisciplineDaysCountIdenticallyUnderBothRules` below is that property,
    /// swept over every shape of week.
    func testALiftOnAPrescribedRunDayNowMissesTheRunDeliberately() throws {
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06", // Tuesday: easy 8 km, no lift prescribed
            workouts: [
                try workout(id: lift, on: "2026-01-06", activityType: .traditionalStrengthTraining)
            ],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "the run was asked for and not delivered")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
        XCTAssertEqual(tallies.currentStreak, 0, "a lift is not an attempt at the run the plan asked for")
        XCTAssertEqual(tallies.workoutDays, 1, "the athlete did train, and that figure is unchanged")
    }

    /// The same day, with the run *also* done: the lift is simply not the run
    /// obligation's business, and the day is met. Together with the test above this pins
    /// that the attribution is by discipline and nothing else.
    func testALiftAlongsideTheRunLeavesTheRunObligationMet() throws {
        let run = UUID()
        let lift = UUID()
        let tallies = try computeTallies(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: run, on: "2026-01-06"),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining,
                    startOffsetSeconds: 3_600 * 8
                ),
            ],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )

        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1)
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1)
        XCTAssertEqual(tallies.currentStreak, 1, "an unprescribed lift neither helps nor hurts the run")
    }

    /// A ride, a walk and a hike are `.run` by *slot* (`ActivityType.discipline` makes
    /// `.run` the residual, A17), so they reach the run obligation exactly as they always
    /// did. Only a lift is attributed elsewhere — which is what keeps the historical
    /// movement above to one narrow shape rather than to every cross-training day.
    func testNonRunCardioStillCountsTowardTheRunObligation() throws {
        for activityType: ActivityType in [.cycling, .walking, .hiking, .other] {
            let id = UUID()
            let tallies = try computeTallies(
                from: "2026-01-06", through: "2026-01-06",
                workouts: [try workout(id: id, on: "2026-01-06", activityType: activityType)],
                scoreLedgers: [id: try ledger(points: 80, workoutID: id)],
                planCalendar: try runOnlyPlan(),
                restDayBudget: try RestDayBudget(daysPerWeek: 0)
            )
            XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1, "\(activityType)")
            XCTAssertEqual(tallies.currentStreak, 1, "\(activityType)")
        }
    }

    // MARK: - The regression sweep: single-discipline days do not move

    /// What one prescribed day of the swept corpus can have happened on it. Declared here
    /// rather than inside the test so `CaseIterable` is synthesised at type scope.
    private enum DayOutcome: CaseIterable {
        case nothingRecorded
        case recordedUnscored
        case scoredEffective
        case scoredIneffective
    }

    /// **A19's landable property, as a fixture suite rather than an argument.**
    ///
    /// `legacyDayCounting` below is the pre-MAX-134 rule, transcribed from the code this
    /// ticket replaced: eligible-if-the-day-had-a-run-ask, effective-if-any-ledger-was,
    /// converted days dropped from both sides, unscored days neutral, and the streak
    /// walking back over the same four cases. This sweeps **every** combination of
    /// outcomes over a run-only week — nothing recorded, recorded-and-unscored,
    /// scored-effective, scored-ineffective on each of the week's five prescribed days,
    /// against two budgets — and asserts the new obligation counting agrees with it
    /// exactly, on all three figures the ticket touches.
    ///
    /// 4⁵ × 2 = 2,048 weeks. The corpus is deliberately exhaustive rather than
    /// hand-picked, because the claim being defended is universal: *no* historical figure
    /// moves. Every day in it prescribes one session and every workout in it is of that
    /// session's discipline — the qualification
    /// `testALiftOnAPrescribedRunDayNowMissesTheRunDeliberately` explains.
    func testSingleDisciplineDaysCountIdenticallyUnderBothRules() throws {
        // The week's prescribed run days under `Fixture.plan()`; Mon and Fri are rest.
        let prescribed = ["2026-01-06", "2026-01-07", "2026-01-08", "2026-01-10", "2026-01-11"]
        let planCalendar = try runOnlyPlan()

        var combinations: [[DayOutcome]] = [[]]
        for _ in prescribed {
            combinations = combinations.flatMap { prefix in
                DayOutcome.allCases.map { prefix + [$0] }
            }
        }
        XCTAssertEqual(combinations.count, 1_024, "the sweep must actually be exhaustive")

        for budgetDays in [0, 1] {
            let budget = try RestDayBudget(daysPerWeek: budgetDays)
            for combination in combinations {
                var workouts: [Workout] = []
                var scoreLedgers: [UUID: ScoreLedger] = [:]
                for (dayText, outcome) in zip(prescribed, combination) {
                    guard outcome != .nothingRecorded else { continue }
                    let id = UUID()
                    workouts.append(try workout(id: id, on: dayText))
                    switch outcome {
                    case .scoredEffective:
                        scoreLedgers[id] = try ledger(points: 80, workoutID: id)
                    case .scoredIneffective:
                        scoreLedgers[id] = try ledger(points: 30, workoutID: id)
                    case .recordedUnscored, .nothingRecorded:
                        break
                    }
                }

                let input = try TalliesInput(
                    from: try day("2026-01-05"),
                    through: try day("2026-01-11"),
                    timeZone: .gmt,
                    today: try day(ObligationTalliesTests.defaultToday),
                    workouts: workouts,
                    scoreLedgers: scoreLedgers,
                    planCalendar: planCalendar,
                    restDayBudget: budget
                )
                let actual = try TalliesCalculator.compute(input)
                let expected = try legacyDayCounting(input)

                let scenario = "budget \(budgetDays), week \(combination)"
                XCTAssertEqual(
                    actual.effectiveDays.eligibleCount, expected.eligibleCount,
                    "eligible moved — \(scenario)"
                )
                XCTAssertEqual(
                    actual.effectiveDays.effectiveCount, expected.effectiveCount,
                    "effective moved — \(scenario)"
                )
                XCTAssertEqual(
                    actual.currentStreak, expected.streak,
                    "streak moved — \(scenario)"
                )
            }
        }
    }

    /// The rest-day budget's own no-op, at the level the budget works at: over the same
    /// exhaustive corpus, the obligation-converting budget forgives exactly the days the
    /// day-converting one did, in the same order.
    func testTheBudgetConvertsTheSameDaysItAlwaysDidOnASingleDisciplineWeek() throws {
        let planCalendar = try runOnlyPlan()
        let planDays = try planCalendar.planDays(
            from: try day("2026-01-05"), through: try day("2026-01-11")
        )
        let prescribed = planDays.filter(\.canBeMissed).map(\.date)

        // Every subset of the week's five prescribed days that saw a run.
        for mask in 0..<(1 << prescribed.count) {
            var ran: Set<CalendarDay> = []
            for (index, date) in prescribed.enumerated() where mask & (1 << index) != 0 {
                ran.insert(date)
            }
            let workoutDisciplines = Dictionary(
                uniqueKeysWithValues: ran.map { ($0, Set([Discipline.run])) }
            )

            for budgetDays in [0, 1, 2, 5] {
                let conversions = try RestDayBudgeting.convertingMissedObligations(
                    planDays: planDays,
                    workoutDisciplines: workoutDisciplines,
                    budget: try RestDayBudget(daysPerWeek: budgetDays),
                    createdAt: Date(timeIntervalSince1970: 0)
                )
                let expected = try legacyConversions(
                    planDays: planDays,
                    workoutDays: ran,
                    budgetDays: budgetDays
                )
                XCTAssertEqual(
                    conversions.map(\.date.description), expected.map(\.description),
                    "conversions moved — mask \(mask), budget \(budgetDays)"
                )
                XCTAssertTrue(
                    conversions.allSatisfy { $0.discipline == .run },
                    "a run-only plan can only ever convert run obligations"
                )
            }
        }
    }

    // MARK: - The pre-MAX-134 rules, transcribed

    /// The day-level effective tally and streak exactly as `TalliesCalculator` computed
    /// them before this ticket. Kept as a reference implementation rather than a set of
    /// hand-written numbers so the sweep above can be exhaustive: 2,048 hand-worked weeks
    /// is not a thing anyone would write, or trust if they had.
    private func legacyDayCounting(
        _ input: TalliesInput
    ) throws -> (eligibleCount: Int, effectiveCount: Int, streak: Int) {
        var workoutsByDay: [CalendarDay: [Workout]] = [:]
        for recorded in input.workouts {
            let onDay = try recorded.calendarDay(in: input.timeZone)
            workoutsByDay[onDay, default: []].append(recorded)
        }

        var planDaysInRange: [CalendarDay: PlanDay] = [:]
        var convertedDates: Set<CalendarDay> = []
        if let planCalendar = input.planCalendar {
            let expanded = try planCalendar.planDays(
                from: try input.from.startOfTrainingWeek(),
                through: try input.through.startOfTrainingWeek().adding(days: 6)
            )
            for planDay in expanded
            where planDay.date >= input.from && planDay.date <= input.through {
                planDaysInRange[planDay.date] = planDay
            }
            convertedDates = Set(
                try legacyConversions(
                    planDays: expanded,
                    workoutDays: Set(workoutsByDay.keys),
                    budgetDays: input.restDayBudget.daysPerWeek,
                    outcomesUnknownFrom: input.today
                )
            )
        }

        var eligibleCount = 0
        var effectiveCount = 0
        for day in try CalendarDay.days(from: input.from, through: input.through) {
            guard day < input.today else { continue }
            guard let planDay = planDaysInRange[day], planDay.canBeMissed else { continue }
            guard !convertedDates.contains(day) else { continue }
            let dayWorkouts = workoutsByDay[day] ?? []
            let dayLedgers = dayWorkouts.compactMap { input.scoreLedgers[$0.id] }
            if !dayWorkouts.isEmpty, dayLedgers.isEmpty { continue }
            eligibleCount += 1
            if dayLedgers.contains(where: \.isEffective) { effectiveCount += 1 }
        }

        var streak = 0
        let walkStart = min(input.through, input.today)
        if walkStart >= input.from {
            var day = walkStart
            walk: while true {
                if let planDay = planDaysInRange[day], planDay.canBeMissed {
                    let dayWorkouts = workoutsByDay[day] ?? []
                    if dayWorkouts.isEmpty {
                        if day != input.today, !convertedDates.contains(day) { break walk }
                    } else {
                        let dayLedgers = dayWorkouts.compactMap { input.scoreLedgers[$0.id] }
                        if !dayLedgers.isEmpty {
                            if dayLedgers.contains(where: \.isEffective) {
                                streak += 1
                            } else {
                                break walk
                            }
                        }
                    }
                }
                guard day != input.from else { break walk }
                day = try day.adding(days: -1)
            }
        }

        return (eligibleCount, effectiveCount, streak)
    }

    /// `RestDayBudgeting.convertingMissedDays` exactly as it was before this ticket:
    /// day-granular candidates, a single rest row, tier then adjacency then date.
    private func legacyConversions(
        planDays: [PlanDay],
        workoutDays: Set<CalendarDay>,
        budgetDays: Int,
        outcomesUnknownFrom: CalendarDay? = nil
    ) throws -> [CalendarDay] {
        guard budgetDays > 0 else { return [] }

        func costTier(_ kind: ScheduledSessionKind) -> Int {
            switch kind {
            case .other: return 0
            case .easy: return 1
            case .lift: return 2
            case .hard: return 3
            case .long: return 4
            case .rest: return 5
            }
        }
        func outcomeIsKnown(_ date: CalendarDay) -> Bool {
            guard let outcomesUnknownFrom else { return true }
            return date < outcomesUnknownFrom
        }

        var byWeek: [CalendarDay: [PlanDay]] = [:]
        for planDay in planDays {
            let week = try planDay.date.startOfTrainingWeek()
            byWeek[week, default: []].append(planDay)
        }

        var converted: [CalendarDay] = []
        for weekPlanDays in byWeek.values {
            let missed = weekPlanDays.filter {
                $0.canBeMissed && !workoutDays.contains($0.date) && outcomeIsKnown($0.date)
            }
            guard !missed.isEmpty else { continue }
            let restDates = Set(weekPlanDays.filter(\.scheduledSession.isRest).map(\.date))
            func isAdjacent(_ date: CalendarDay) -> Bool {
                let before = try? date.adding(days: -1)
                let after = try? date.adding(days: 1)
                return before.map(restDates.contains) == true || after.map(restDates.contains) == true
            }
            let ordered = missed.sorted { lhs, rhs in
                let lhsTier = costTier(lhs.scheduledSession.kind)
                let rhsTier = costTier(rhs.scheduledSession.kind)
                if lhsTier != rhsTier { return lhsTier < rhsTier }
                let lhsAdjacent = isAdjacent(lhs.date)
                let rhsAdjacent = isAdjacent(rhs.date)
                if lhsAdjacent != rhsAdjacent { return lhsAdjacent }
                return lhs.date < rhs.date
            }
            converted += ordered.prefix(budgetDays).map(\.date)
        }
        return converted.sorted()
    }
}
