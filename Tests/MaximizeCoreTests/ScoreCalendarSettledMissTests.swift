import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-159 / LIFTING-SPEC §7.2 — the day that missed one obligation and trained at
/// something nothing has judged.
///
/// ## The precedence this suite fixes, in one sentence
///
/// A **settled** outcome on one obligation outranks a **pending** one on another. Before
/// this ticket a recorded-but-unjudged workout outranked everything, so a Tuesday whose
/// lift was recorded and unscored and whose run was skipped drew `.noVerdict` — a neutral
/// cell, on a sentence naming the lift and never the miss. The score that cell was waiting
/// for would not have said anything about the skipped run when it arrived; a miss is a
/// fact and a missing score is not yet anything.
///
/// ## Which cells move, and which deliberately do not
///
/// Only two shapes reach the new state, and exactly one of them exists in the athlete's
/// history:
///
/// - **A prescribed run day whose only recorded workout is a lift** — historical, and the
///   one this ticket is expected to move on the owner's device. Every plan on disk rests
///   its lift slot, so this is a one-obligation day.
/// - **A two-obligation day where one slot was skipped and the other's session is
///   unjudged** — reachable only since MAX-129 gave the template a lift slot, so it costs
///   nothing historically.
///
/// A **ride** on a prescribed run day does *not* move, which is worth stating because
/// MAX-135's report named it as the shape that would: `Discipline` makes a ride `.run` by
/// slot (it is an `.other` session in the run row, A17), so the run obligation on such a
/// day is `.awaitingVerdict` and never `.missed`. There is no settled miss on it to
/// outrank. `testARideOnAPrescribedRunDayDoesNotMove` pins that.
///
/// Reasoned against `Fixture.plan()` and `Fixture.plan(lift:)` — effective Thursday
/// 2026-01-01, run slot Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday easy
/// 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km — the same fixture
/// `ScoreCalendarTests`, `ScoreCalendarMixedDayTests` and `ObligationTalliesTests` all
/// reason against, so the four suites can be read side by side.
///
/// Most tests pass `RestDayBudget(daysPerWeek: 0)`, and here that is load-bearing rather
/// than tidy: with the standard budget of one day a week, the fixture's Tuesday easy run
/// is the week's cheapest miss and D9 forgives it — and a **forgiven** obligation is not a
/// settled miss, so the day stays neutral. Both sides of that boundary are asserted
/// below rather than left to the reader.
final class ScoreCalendarSettledMissTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// After everything these tests reason about, so the suite is "the past" unless a test
    /// says otherwise.
    private static let defaultToday = "2026-12-31"

    private func workout(
        id: UUID = UUID(),
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

    private func runOnlyPlan() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan()])
    }

    /// Tuesday asks for a run *and* a lift.
    private func planWithATuesdayLift() throws -> PlanCalendar {
        try PlanCalendar([try Fixture.plan(lift: [.tuesday: ScheduledSession(kind: .lift)])])
    }

    private var noBudget: RestDayBudget {
        get throws { try RestDayBudget(daysPerWeek: 0) }
    }

    private func resolve(
        from: String,
        through: String,
        today: String = ScoreCalendarSettledMissTests.defaultToday,
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

    // MARK: - The shape that moves, and why the new answer is the true one

    /// **The historical cell this ticket moves.** A Tuesday the plan asked an easy run of,
    /// on which the athlete lifted instead and nothing scored the lift.
    ///
    /// The old answer was `.noVerdict` — a neutral cell reading *"Strength training,
    /// recorded. Not scored — the plan scores runs. Planned: easy run."* Every clause of
    /// that is true and the day it describes is not: the run was skipped, unforgiven, and
    /// the tallies were already counting it as a decided-and-unmet obligation while the
    /// cell showed a day with nothing to report. The new answer names both facts, and the
    /// fill is the miss's because §7.2 colours a day by its worse verdict.
    func testALiftRecordedOnAnUnforgivenMissedRunDayNamesBothFacts() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06", // Tuesday: easy 8 km
            workouts: [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .missedWithUnjudgedSession(scheduledKind: .easy, recorded: .traditionalStrengthTraining)
        )
    }

    /// The other side of that boundary, and the reason the test above turns the budget off:
    /// a **forgiven** obligation is not a settled miss. D9/A6 spent the week's allowance on
    /// this Tuesday, so the athlete is no longer being held to the run, and a red cell
    /// would be the calendar taking back forgiveness the tallies have already granted.
    ///
    /// This is the same day, the same workout and the same plan as the test above — only
    /// the budget differs — which is what makes the pair a statement about *what settles an
    /// obligation* rather than about a fixture.
    func testTheSameDayStaysNeutralWhenTheBudgetForgivesTheRun() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: .standard // one day a week; Tuesday's easy run is the week's cheapest miss
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            // `.awaitingScore` rather than `.noVerdict` since MAX-168 — the lift's score
            // is outstanding, not settled. What this test is about is unchanged: a
            // forgiven obligation produces no red cell either way.
            .awaitingScore(activityType: .traditionalStrengthTraining)
        )
    }

    /// MAX-135's reported defect, verbatim: a two-obligation Tuesday whose lift was
    /// recorded but unscored and whose run was missed. It drew `.noVerdict`, and the
    /// sentence named neither the miss nor the second ask.
    func testTheTwoObligationDayMAX135ReportedNowNamesTheMiss() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .missedWithUnjudgedSession(scheduledKind: .easy, recorded: .traditionalStrengthTraining),
            "the lift is recorded and pending; the run is skipped and settled, and the settled half leads"
        )
    }

    /// The mirror image, which the state is symmetric for: the lift slot was skipped and
    /// the run is the session still waiting on a score. The missed *lift* is named, and the
    /// recorded half keeps its own tense — a run's verdict really is still coming, which is
    /// the difference `ActivityType.isScoreable` carries here exactly as it does between
    /// `.awaitingScore` and `.noVerdict`.
    func testAMissedLiftBesideARunAwaitingItsScoreNamesTheLift() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .running)],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .missedWithUnjudgedSession(scheduledKind: .lift, recorded: .running)
        )
    }

    /// The precedence *within* the day's own workouts is unchanged and still applies inside
    /// the new state: where more than one session is recorded, the one a verdict is still
    /// coming for speaks for the day. A ride and a run on a day the lift was skipped is the
    /// only shape that can hold both — the run's pending score is the more informative half
    /// of what was recorded, and picking the earlier-starting ride would have told the
    /// athlete no verdict was coming when one is.
    func testARunOutranksARideInsideTheNewStateJustAsItDoesOutsideIt() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(on: "2026-01-06", activityType: .cycling, startOffsetSeconds: 3_600),
                try workout(on: "2026-01-06", activityType: .running, startOffsetSeconds: 3_600 * 10),
            ],
            planCalendar: try planWithATuesdayLift(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .missedWithUnjudgedSession(scheduledKind: .lift, recorded: .running)
        )
    }

    // MARK: - What the cell draws

    /// The new state spends nothing from MAX-084's or MAX-087's channels — no band pip,
    /// because nothing on the day was scored and the fill is not a band — and it is filled
    /// in the day grid, because `.forthcoming` owns unfilled and this day has been and
    /// gone. At year density it collapses onto a plain miss, deliberately: there is no
    /// glyph at ~6pt, and hollow is the true half of it.
    func testTheCellDrawsNoBandPipAndCollapsesOntoAMissAtYearDensity() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )
        let settled = try state(days, on: "2026-01-06")

        XCTAssertNil(settled.scoredBand, "nothing on this day was scored, so there is no band to mark")
        XCTAssertFalse(settled.isDrawnUnfilledInTheDayGrid)
        XCTAssertTrue(settled.isDrawnHollowAtHeatmapDensity)
    }

    /// The glyph is the whole non-hue channel this state gets, so it has to be its own —
    /// stated here as well as in `WCAGContrastTests` because a failure of *this* assertion
    /// reads as "the new state lost its mark", not as a contrast regression.
    func testTheStateCarriesItsOwnGlyphWhicheverSessionWasRecorded() {
        let lifted = ScoreCalendarDayState.missedWithUnjudgedSession(
            scheduledKind: .easy, recorded: .traditionalStrengthTraining
        )
        let ran = ScoreCalendarDayState.missedWithUnjudgedSession(scheduledKind: .lift, recorded: .running)

        XCTAssertEqual(ScoreCalendarGlyph.symbolName(for: lifted), "xmark.circle")
        XCTAssertEqual(
            ScoreCalendarGlyph.symbolName(for: ran), "xmark.circle",
            "the mark is the state's, not the recorded activity's — otherwise a badly scored run and a "
                + "missed ask with a run beside it draw the same cell on the same red"
        )
        XCTAssertNotEqual(
            ScoreCalendarGlyph.symbolName(for: lifted),
            ScoreCalendarGlyph.symbolName(for: .missed(scheduledKind: .easy))
        )
    }

    /// The day is still a day with something behind it: the tap opens the session that was
    /// recorded, and the plan ring is still drawn because the plan asked something of it.
    /// A red cell that dead-ends would be worse than the neutral one it replaces.
    func testTheDayStillOpensTheSessionThatWasRecorded() throws {
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: lift, on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )
        let resolved = try cell(days, on: "2026-01-06")

        XCTAssertEqual(resolved.destination, .workouts([lift]))
        XCTAssertTrue(resolved.prescribesASession)
        XCTAssertEqual(resolved.prescription?.scheduledSession.kind, .easy)
        XCTAssertNil(resolved.agreement, "nothing was scored, so there is no classification to compare (D2)")
    }

    // MARK: - The standing rule: no future day shows red

    /// `today` itself, with a lift already recorded and the run not yet due. The run's
    /// outcome is not in, so it is `.notYetDue` rather than `.missed` and there is nothing
    /// settled for the new state to report — which is how the owner's standing "no red on
    /// a future day" rule survives a state whose fill is D9's red.
    func testADayWhoseRunIsNotYetDueIsNeverRed() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-07",
            today: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .awaitingScore(activityType: .traditionalStrengthTraining),
            "a scheduled run at six in the morning has not been skipped"
        )
        XCTAssertEqual(try state(days, on: "2026-01-07"), .forthcoming(scheduledKind: .hard))
    }

    // MARK: - §7.3: the cell and the effective-obligations tile answer to one roll-up

    /// The gap this ticket closes, asserted as the agreement it is. On this Tuesday the
    /// tile counts one decided obligation and none met — the run was skipped and
    /// unforgiven — while the cell used to draw a neutral "recorded, not scored". Two
    /// answers to the same question about the same day is D2's drift with a colour
    /// attached, and both now read the same `DayObligations`.
    func testTheCellAndTheEffectiveObligationsTileAgreeAboutTheDay() throws {
        let workouts = [try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)]
        let budget = try noBudget

        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, planCalendar: try planWithATuesdayLift(), restDayBudget: budget
        )
        let tallies = try TalliesCalculator.compute(
            try TalliesInput(
                from: try day("2026-01-06"),
                through: try day("2026-01-06"),
                timeZone: .gmt,
                today: try day(ScoreCalendarSettledMissTests.defaultToday),
                workouts: workouts,
                scoreLedgers: [:],
                planCalendar: try planWithATuesdayLift(),
                restDayBudget: budget
            )
        )

        guard case .missedWithUnjudgedSession = try state(days, on: "2026-01-06") else {
            return XCTFail("expected the settled-miss state on a day the tile counts 0 of 1")
        }
        XCTAssertEqual(tallies.effectiveDays.eligibleCount, 1, "the skipped run; the unjudged lift decides nothing")
        XCTAssertEqual(tallies.effectiveDays.effectiveCount, 0)
    }

    // MARK: - Everything else stays where it was

    /// **The shape MAX-135's report named, and it does not move.** A ride is `.run` by slot
    /// (A17: cycling is an `.other` session in the run row, not a third discipline), so the
    /// run obligation on this Tuesday is `.awaitingVerdict` — something *was* recorded
    /// against it — and never `.missed`. There is no settled outcome on the day, so the
    /// precedence this ticket changed never comes into play.
    func testARideOnAPrescribedRunDayDoesNotMove() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(on: "2026-01-06", activityType: .cycling)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .noVerdict(activityType: .cycling))
    }

    /// A **scored** session on a day another obligation was missed is deliberately left
    /// where it was, and this pins the boundary so it reads as a decision rather than an
    /// oversight. The real instance is a pre-MAX-111 lift carrying a running-rubric score
    /// (A21/MAX-143) on a day the run was skipped: moving it would recolour the cells of
    /// stored scores, which is wider than the precedence this ticket was scoped to and cuts
    /// against MAX-143's stance that those scores keep being reported. Filed on the board.
    func testAScoredSessionStillOutranksAMissedObligationOnTheSameDay() throws {
        let lift = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: lift, on: "2026-01-06", activityType: .traditionalStrengthTraining)],
            scoreLedgers: [lift: try ledger(points: 30, workoutID: lift)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .scored(band: .ineffective, activityType: .traditionalStrengthTraining)
        )
    }

    /// A day the plan asks nothing of has no obligation to be missed, so a session recorded
    /// on it is untouched by this ticket whichever kind it is — the Monday rest day the
    /// athlete lifted through is not a red day.
    func testASessionOnADayThePlanAsksNothingOfIsUnchanged() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: rest in both slots
            workouts: [try workout(on: "2026-01-05", activityType: .traditionalStrengthTraining)],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-05"),
            .awaitingScore(activityType: .traditionalStrengthTraining)
        )
        XCTAssertFalse(try cell(days, on: "2026-01-05").prescribesASession)
    }

    /// The whole week, cell by cell, with D9 switched off so every miss is a settled one —
    /// the regression fixture this ticket owes the board. Exactly one cell in it is new,
    /// and the other six say what they said before:
    ///
    /// - Monday, rest, lift recorded → `.awaitingScore` (`.noVerdict` before MAX-168 —
    ///   the lift's score is outstanding, not settled). No obligation, nothing missed.
    /// - Tuesday, easy run asked, **ride** recorded → `.noVerdict`. The ride is `.run` by
    ///   slot, so the obligation is awaiting a verdict, not missed.
    /// - Wednesday, hard session asked, **lift** recorded → **`.missedWithUnjudgedSession`**.
    ///   The one that moves.
    /// - Thursday, easy run asked, run recorded and unscored → `.awaitingScore`.
    /// - Friday, rest → `.scheduledRest`.
    /// - Saturday, easy run asked, nothing recorded → `.missed`. A miss with nothing beside
    ///   it is still a plain miss, and it keeps the "×" it always had.
    /// - Sunday, long run asked, run recorded and scored → `.scored`.
    func testTheWeekMovesInExactlyOnePlace() throws {
        let sunday = UUID()
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-11",
            workouts: [
                try workout(on: "2026-01-05", activityType: .traditionalStrengthTraining),
                try workout(on: "2026-01-06", activityType: .cycling),
                try workout(on: "2026-01-07", activityType: .traditionalStrengthTraining),
                try workout(on: "2026-01-08", activityType: .running),
                try workout(id: sunday, on: "2026-01-11", activityType: .running),
            ],
            scoreLedgers: [
                sunday: try ledger(
                    points: 90, workoutID: sunday, scheduledKind: .long, actualClassification: .long
                )
            ],
            planCalendar: try runOnlyPlan(),
            restDayBudget: try noBudget
        )

        XCTAssertEqual(
            try state(days, on: "2026-01-05"), .awaitingScore(activityType: .traditionalStrengthTraining)
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .noVerdict(activityType: .cycling))
        XCTAssertEqual(
            try state(days, on: "2026-01-07"),
            .missedWithUnjudgedSession(scheduledKind: .hard, recorded: .traditionalStrengthTraining),
            "the only cell in this week that reads differently than it did before MAX-159"
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .awaitingScore(activityType: .running))
        XCTAssertEqual(try state(days, on: "2026-01-09"), .scheduledRest)
        XCTAssertEqual(try state(days, on: "2026-01-10"), .missed(scheduledKind: .easy))
        XCTAssertEqual(try state(days, on: "2026-01-11"), .scored(band: .effective, activityType: .running))
    }
}

/// The sentence the settled-miss cell speaks. §7.2 puts the whole truth of a cell that
/// cannot draw it into the spoken label, which is what makes this copy part of the state
/// rather than decoration on it — and what puts it where CI can read it.
final class ScoreCalendarSettledMissCopyTests: XCTestCase {

    /// The headline is the miss, because it is the settled half and the reason the cell is
    /// red; the recorded session follows, with the tense its activity earns.
    ///
    /// The lift's clause changed in MAX-168 — its score is outstanding now, not absent —
    /// so the settled wording is asserted below on the activity that still earns it.
    func testTheSentenceNamesTheMissedAskThenTheRecordedSession() {
        XCTAssertEqual(
            ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .easy,
                recorded: .traditionalStrengthTraining,
                describedAs: "Strength training"
            ),
            "missed easy run. Strength training recorded, awaiting score."
        )
        XCTAssertEqual(
            ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .easy,
                recorded: .cycling,
                describedAs: "Cycling"
            ),
            "missed easy run. Cycling recorded, not scored — the plan has no rule for it."
        )
    }

    /// A recorded **run** is still waiting on a model, so the clause is a wait rather than
    /// a settled absence — the same distinction `.awaitingScore` and `.noVerdict` carry,
    /// arriving in the sentence because this state has one fill and one mark for both.
    func testARecordedRunIsSpokenAsAWaitAndARideAsASettledAbsence() {
        XCTAssertEqual(
            ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .lift, recorded: .running, describedAs: "Running"
            ),
            "missed lift. Running recorded, awaiting score."
        )
        XCTAssertEqual(
            ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .hard, recorded: .treadmillRunning, describedAs: "Treadmill running"
            ),
            "missed hard session. Treadmill running recorded, awaiting score."
        )
        XCTAssertEqual(
            ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .long, recorded: .cycling, describedAs: "Cycling"
            ),
            "missed long run. Cycling recorded, not scored — the plan has no rule for it.",
            "a ride is never judged either, so promising it a verdict would be the MAX-126 defect again"
        )
    }

    /// The tense is `ActivityType.isScoreable` and nothing else — asserted over every
    /// activity the app names, so a type added later cannot quietly acquire the wrong
    /// promise. It was `isRun` until MAX-168 opened the gate for a lift.
    func testTheTenseFollowsIsScoreableForEveryNamedActivity() {
        let activities: [ActivityType] = [
            .running, .treadmillRunning, .walking, .hiking, .cycling, .traditionalStrengthTraining, .other,
        ]
        for activity in activities {
            let sentence = ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: .easy, recorded: activity, describedAs: "Session"
            )
            let expected = activity.isScoreable
                ? "a session whose score may still arrive"
                : "a session nothing will ever judge"
            XCTAssertEqual(
                sentence.contains("awaiting score"), activity.isScoreable,
                "\(activity) is \(expected), and the sentence says the opposite: \(sentence)"
            )
        }
    }
}
