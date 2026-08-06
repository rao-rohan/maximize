import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-135 / LIFTING-SPEC §7 — the calendar cell on a day that prescribed two sessions.
///
/// Reasoned against `Fixture.plan(lift:)`, the same fixture `ObligationTalliesTests` uses
/// so the two suites can be read against each other: effective from **Thursday
/// 2026-01-01**, run slot Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday easy
/// 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km, effective threshold 70.
/// A lift is put on **Tuesday**, so Tuesday 2026-01-06 asks for a run *and* a lift, and on
/// **Monday** where a lift-only day is wanted (the run slot rests there).
///
/// Most tests pass `RestDayBudget(daysPerWeek: 0)`. That is deliberate rather than
/// incidental: with a budget in play the week's cheapest miss is forgiven, and a test
/// about a *missed* obligation that quietly measured a forgiven one would pass for the
/// wrong reason. The one test that wants a conversion asks for it explicitly.
final class ScoreCalendarMixedDayTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// After everything these tests reason about, so the suite is "the past" unless a
    /// test says otherwise — the convention `ScoreCalendarTests` and
    /// `ObligationTalliesTests` both use.
    private static let defaultToday = "2026-12-31"

    private func workout(
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
        actualClassification: WorkoutClassification = .easy,
        correctedTo correction: Int? = nil
    ) throws -> ScoreLedger {
        let automatic = try Fixture.score(
            points: points,
            workoutID: workoutID,
            scheduledKind: scheduledKind,
            actualClassification: actualClassification
        )
        guard let correction else { return try ScoreLedger(automatic: automatic) }
        return try ScoreLedger(
            automatic: automatic,
            annotations: [try Fixture.annotation(points: correction, workoutID: workoutID)]
        )
    }

    /// A lift's ledger, supplied directly rather than produced by the pipeline, the same
    /// way `ObligationTalliesTests` supplies one. Written before MAX-168 opened the gate,
    /// so that the cell drew the first scored lift correctly on the day it did.
    private func liftLedger(points: Int, workoutID: UUID, correctedTo correction: Int? = nil) throws -> ScoreLedger {
        try ledger(
            points: points,
            workoutID: workoutID,
            scheduledKind: .lift,
            actualClassification: .lift,
            correctedTo: correction
        )
    }

    /// Tuesday asks for a run *and* a lift; every other day is the run-only fixture week.
    private func planWithATuesdayLift() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])
    }

    /// Monday rests the run slot, so a lift there is a day whose *only* obligation is a
    /// lift — the shape that used to draw "scheduled rest day" over an outstanding ask.
    private func planWithAMondayLift() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan(lift: [.monday: ScheduledSession(kind: .lift)])])
    }

    /// D9 switched off, so that a test about a *missed* obligation is measuring a missed
    /// one. With a budget in play the week's cheapest miss is forgiven, and a test that
    /// quietly measured the forgiveness would pass for the wrong reason.
    private var noBudget: RestDayBudget {
        get throws { try RestDayBudget(daysPerWeek: 0) }
    }

    private func resolve(
        from: String,
        through: String,
        today: String = ScoreCalendarMixedDayTests.defaultToday,
        workouts: [Workout] = [],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget = .standard
    ) throws -> [ScoreCalendarDay] {
        try ScoreCalendar.resolve(
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

    private func cell(_ days: [ScoreCalendarDay], on text: String) throws -> ScoreCalendarDay {
        let target = try day(text)
        return try XCTUnwrap(days.first { $0.date == target })
    }

    private func state(_ days: [ScoreCalendarDay], on text: String) throws -> ScoreCalendarDayState {
        try cell(days, on: text).state
    }

    // MARK: - §7.2: one of two met

    /// The headline case: the run was met and the lift never happened. §7.2 — *"A day
    /// where the run scored effective and the lift was missed is not a green day."*
    func testARunMetAndALiftMissedIsPartiallyMet() throws {
        let run = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: run, on: "2026-01-06")],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ),
            "the run's band is carried for the sentence; the lift carries no band because nothing was recorded"
        )
    }

    /// The mirror image, which only becomes reachable when something scores lifts. The
    /// state is symmetric on purpose: the missed half is named, whichever slot it is.
    func testALiftMetAndTheRunMissedIsAlsoPartiallyMet() throws {
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: lift, on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            scoreLedgers: [lift: try liftLedger(points: 85, workoutID: lift)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .lift, kind: .lift, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .run, kind: .easy, judgedBand: nil)
            )
        )
    }

    /// "Not met" is two different facts and the unmet half keeps them apart: a session
    /// performed and judged short carries the band it earned, where a skipped one carries
    /// none. The cell draws the same red either way; the sentence is where the difference
    /// survives.
    func testAnUnmetObligationThatWasJudgedShortCarriesItsBand() throws {
        let run = UUID()
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: run, on: "2026-01-06"),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining, startOffsetSeconds: 3_600 * 8
                ),
            ],
            scoreLedgers: [
                run: try ledger(points: 80, workoutID: run),
                lift: try liftLedger(points: 20, workoutID: lift),
            ],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: .ineffective)
            )
        )
    }

    /// The mixed cell spends nothing from MAX-084's or MAX-087's channels: no band pip,
    /// because the fill it draws on is not a band; not unfilled, because
    /// `.forthcoming` owns that; hollow at year density, where there is no glyph to
    /// separate it from a plain miss and hollow is the true reading of both.
    func testTheMixedCellDrawsNoBandPipAndCollapsesOntoAMissAtYearDensity() throws {
        let run = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: run, on: "2026-01-06")],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )
        let mixed = try state(days, on: "2026-01-06")

        XCTAssertNil(mixed.scoredBand, "the corner pip's vocabulary is 'which band is this fill', and this fill is not one")
        XCTAssertFalse(mixed.isDrawnUnfilledInTheDayGrid)
        XCTAssertTrue(mixed.isDrawnHollowAtHeatmapDensity)
    }

    // MARK: - The days either side of it

    /// Both halves met. The day is `.scored`, and it is coloured by the **worse** of the
    /// two bands — different obligations resolve all-of (§6.3), not the best-of that
    /// resolves two attempts at one obligation (§5).
    ///
    /// The lift here is met by a *correction* over a marginal auto-score, which pins the
    /// second rule at the same time: the cell colours from the immutable auto-score
    /// (D1/D4/D8), never from the annotation that decided the obligation was met.
    func testBothObligationsMetColourTheDayByTheWorseBand() throws {
        let run = UUID()
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: run, on: "2026-01-06"),
                try workout(
                    id: lift, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining, startOffsetSeconds: 3_600 * 8
                ),
            ],
            scoreLedgers: [
                run: try ledger(points: 90, workoutID: run),
                lift: try liftLedger(points: 60, workoutID: lift, correctedTo: 80),
            ],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .scored(band: .marginal, activityType: .traditionalStrengthTraining),
            "the lift was met, and its auto band is the worse of the two"
        )
    }

    /// Neither half met. Still a miss, not a new state — the day has nothing to be
    /// partial about — and it names the run slot, which is the order every list of a
    /// day's obligations comes out in.
    func testNeitherObligationMetIsAMissNamingTheRunSlot() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .missed(scheduledKind: .easy))
    }

    /// A forgiven half is not an unmet half (D9/A6). The day did everything still being
    /// asked of it, so it is a scored day — the same answer `DayObligations.isFullyMet`
    /// gives, which is the point of both reading one roll-up.
    ///
    /// The budget is 7 because the fixture week has five other misses; a smaller one
    /// would be spent on the cheaper of *those* and never reach the lift.
    func testAForgivenLiftLeavesTheDayScoredRatherThanPartial() throws {
        let run = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: run, on: "2026-01-06")],
            scoreLedgers: [run: try ledger(points: 80, workoutID: run)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try RestDayBudget(daysPerWeek: 7)
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .scored(band: .effective, activityType: .running))
    }

    /// A day whose only obligation is a lift used to draw *"scheduled rest day"*, because
    /// the cell read `PlanDay.canBeMissed` — the run slot alone. It is a miss, and it is
    /// ringed, because the plan asked for something there.
    func testALiftOnlyDayIsAMissRatherThanScheduledRest() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: run slot rests, lift prescribed
            planCalendar: try planWithAMondayLift(),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .missed(scheduledKind: .lift))
        XCTAssertTrue(try cell(days, on: "2026-01-05").prescribesASession, "the plan asked for something here")
    }

    /// A day that rests **both** slots is still scheduled rest, and carries no ring.
    func testADayThatRestsBothSlotsIsStillScheduledRest() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday under the run-only fixture
            planCalendar: try PlanCalendar([try Fixture.plan()]),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .scheduledRest)
        XCTAssertFalse(try cell(days, on: "2026-01-05").prescribesASession)
    }

    /// The standing rule that no future day shows red survives the rewrite: a
    /// two-obligation day ahead of `today` is forthcoming, and it names the run slot's
    /// ask; a lift-only day ahead of today names the lift.
    func testAFutureTwoObligationDayIsForthcomingAndNeverRed() throws {
        let mixed = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            today: "2026-01-05",
            planCalendar: try planWithATuesdayLift()
        )
        XCTAssertEqual(try state(mixed, on: "2026-01-06"), .forthcoming(scheduledKind: .easy))

        let liftOnly = try resolve(
            from: "2026-01-12", through: "2026-01-12", // the following Monday
            today: "2026-01-05",
            planCalendar: try planWithAMondayLift()
        )
        XCTAssertEqual(try state(liftOnly, on: "2026-01-12"), .forthcoming(scheduledKind: .lift))
    }

    // MARK: - The single-obligation day does not move

    /// Every day in the athlete's history prescribes at most one session, so nothing this
    /// ticket added may change one. The run-only fixture week is resolved end to end and
    /// asserted cell by cell, against a workout that was scored, one that was not, and
    /// days with nothing on them at all.
    func testASingleObligationWeekIsUnchangedCellByCell() throws {
        let tuesdayRun = UUID()
        let saturdayRide = UUID()
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-11",
            workouts: [
                try workout(id: tuesdayRun, on: "2026-01-06"),
                try workout(id: saturdayRide, on: "2026-01-10", activityType: .cycling),
            ],
            scoreLedgers: [tuesdayRun: try ledger(points: 90, workoutID: tuesdayRun)],
            planCalendar: try PlanCalendar([try Fixture.plan()]),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(try state(days, on: "2026-01-05"), .scheduledRest)
        XCTAssertEqual(try state(days, on: "2026-01-06"), .scored(band: .effective, activityType: .running))
        XCTAssertEqual(try state(days, on: "2026-01-07"), .missed(scheduledKind: .hard))
        XCTAssertEqual(try state(days, on: "2026-01-08"), .missed(scheduledKind: .easy))
        XCTAssertEqual(try state(days, on: "2026-01-09"), .scheduledRest)
        XCTAssertEqual(
            try state(days, on: "2026-01-10"), .noVerdict(activityType: .cycling),
            "a ride on a prescribed run day is still the day the athlete trained, unscored and unscoreable"
        )
        XCTAssertEqual(try state(days, on: "2026-01-11"), .missed(scheduledKind: .long))
    }

    /// Two attempts at one obligation still resolve **best-of** — §5's warm-up jog, which
    /// is deliberately the opposite rule to the all-of applied across obligations, and the
    /// one this ticket must not have flipped by accident.
    func testTwoAttemptsAtOneObligationStillResolveBestOf() throws {
        let warmup = UUID()
        let real = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: warmup, on: "2026-01-06"),
                try workout(id: real, on: "2026-01-06", startOffsetSeconds: 3_600 * 6),
            ],
            scoreLedgers: [
                warmup: try ledger(points: 20, workoutID: warmup),
                real: try ledger(points: 90, workoutID: real),
            ],
            planCalendar: try PlanCalendar([try Fixture.plan()]),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .scored(band: .effective, activityType: .running))
    }

    /// A run on a day the plan asked nothing of is still coloured by what was done (D4).
    /// The obligation-driven rewrite must not have swallowed the off-plan session, which
    /// has no obligation to be met or missed.
    func testAnOffPlanSessionIsStillColouredByWhatWasDone() throws {
        let run = UUID()
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: rest in both slots
            workouts: [try workout(id: run, on: "2026-01-05")],
            scoreLedgers: [run: try ledger(points: 90, workoutID: run)],
            planCalendar: try PlanCalendar([try Fixture.plan()])
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .scored(band: .effective, activityType: .running))
        XCTAssertEqual(try cell(days, on: "2026-01-05").agreement, .unprescribed(performed: .easy))
    }

    /// MAX-135's other correction to `agreement`: the ask compared against is the scored
    /// workout's **own slot's**. Before, a scored lift was compared with the day's running
    /// ask and reported as a divergence from a plan the athlete had in fact followed.
    func testAgreementComparesAScoredLiftAgainstTheLiftAsk() throws {
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: lift, on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            scoreLedgers: [lift: try liftLedger(points: 85, workoutID: lift)],
            planCalendar: try planWithATuesdayLift()
        )
        XCTAssertEqual(try cell(days, on: "2026-01-06").agreement, .asPrescribed(kind: .lift))
    }

    // MARK: - §7.3: the cell and the tile answer to the same roll-up

    /// The property §7.3 exists to protect, asserted rather than argued: the cell that
    /// draws "one of two met" and the tile that counts 1 of 2 are reading the same
    /// `DayObligations`, so they cannot disagree about the same Tuesday.
    func testTheMixedCellAndTheEffectiveObligationsTileAgree() throws {
        let run = UUID()
        let workouts = [try workout(id: run, on: "2026-01-06")]
        let scoreLedgers = [run: try ledger(points: 80, workoutID: run)]
        let budget = try RestDayBudget(daysPerWeek: 0)

        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: scoreLedgers,
            planCalendar: try planWithATuesdayLift(), restDayBudget: budget
        )
        let tallies = try TalliesCalculator.compute(
            try TalliesInput(
                from: try day("2026-01-06"),
                through: try day("2026-01-06"),
                timeZone: .gmt,
                today: try day(ScoreCalendarMixedDayTests.defaultToday),
                workouts: workouts,
                scoreLedgers: scoreLedgers,
                planCalendar: try planWithATuesdayLift(),
                restDayBudget: budget
            )
        )

        guard case .partiallyMet = try state(days, on: "2026-01-06") else {
            return XCTFail("expected the mixed state on the day the tile counts 1 of 2")
        }
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 1)
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 2)
    }
}

/// The mixed day's spoken sentence (§7.2: *"the full truth lives in the VoiceOver
/// sentence and one level down"*), which is why it is composed in the core rather than
/// beside the view.
final class ScoreCalendarCopyTests: XCTestCase {

    func testTheMixedDaySpeaksBothHalves() throws {
        XCTAssertEqual(
            ScoreCalendarCopy.partiallyMetOutcome(
                met: .init(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ),
            "one of two sessions met. Easy run, effective; lift missed."
        )
    }

    /// A dropped half that was performed and judged short says so — the distinction the
    /// cell's single mark cannot draw, and the reason the unmet half carries a band at all.
    func testAJudgedButUnmetHalfIsSpokenAsItsBandRatherThanAsAMiss() throws {
        XCTAssertEqual(
            ScoreCalendarCopy.partiallyMetOutcome(
                met: .init(discipline: .run, kind: .long, band: .marginal),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: .ineffective)
            ),
            "one of two sessions met. Long run, marginal; lift, ineffective."
        )
    }

    /// The mirror image reads as a sentence too, which is the check on a copy string
    /// assembled from two halves: it has to work whichever slot is which.
    func testTheSentenceReadsBothWaysRound() throws {
        XCTAssertEqual(
            ScoreCalendarCopy.partiallyMetOutcome(
                met: .init(discipline: .lift, kind: .lift, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .run, kind: .hard, judgedBand: nil)
            ),
            "one of two sessions met. Lift, effective; hard session missed."
        )
    }

    /// The sentence says "one of two", which is arithmetic: a day cannot hold more
    /// obligations than there are disciplines. If a third ever arrives, this fails here —
    /// at the copy that would have started lying — rather than on a device.
    func testTheCopysArithmeticDependsOnThereBeingTwoDisciplines() {
        XCTAssertEqual(
            Discipline.allCases.count, 2,
            "`one of two sessions met` counts slots; a third discipline means rewriting this sentence"
        )
    }
}
