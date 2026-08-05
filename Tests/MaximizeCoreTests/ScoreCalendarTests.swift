import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-061 — the per-day state taxonomy behind the score-colored calendar (D4, D9,
/// A6, FR-3.2).
///
/// Reasoned against `Fixture.plan()` unless noted: effective from **Thursday
/// 2026-01-01**, template Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday
/// easy 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km. `2026-01-05...11`
/// is the week most of these tests use — the same week `TalliesTests` reasons about,
/// deliberately, so the two suites can be cross-checked by eye.
final class ScoreCalendarTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func workout(
        id: UUID = UUID(),
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
            distanceMeters: 8_000,
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

    private func calendar(_ plan: Plan? = nil) throws -> PlanCalendar {
        try PlanCalendar([plan ?? Fixture.plan()])
    }

    /// `today` defaults to a day after every date these tests reason about, so the
    /// whole suite is "the past" unless a test deliberately says otherwise. Every
    /// pre-MAX-105 expectation therefore still reads as written: a scheduled day with
    /// nothing recorded is a miss, because it has been and gone.
    private static let defaultToday = "2026-12-31"

    private func resolve(
        from: String,
        through: String,
        today: String = ScoreCalendarTests.defaultToday,
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

    private func destination(
        _ days: [ScoreCalendarDay],
        on text: String
    ) throws -> ScoreCalendarDayDestination {
        try cell(days, on: text).destination
    }

    // MARK: - .scored

    func testAScoredWorkoutShowsTheStoredBandAndActivityType() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06", activityType: .treadmillRunning)],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .scored(band: .effective, activityType: .treadmillRunning)
        )
    }

    func testMarginalAndIneffectiveBandsComeThroughUnchanged() throws {
        let marginalID = UUID()
        let ineffectiveID = UUID()
        let marginalDays = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: marginalID, on: "2026-01-06")],
            scoreLedgers: [marginalID: try ledger(points: 60, workoutID: marginalID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(marginalDays, on: "2026-01-06"), .scored(band: .marginal, activityType: .running))

        let ineffectiveDays = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: ineffectiveID, on: "2026-01-06")],
            scoreLedgers: [ineffectiveID: try ledger(points: 20, workoutID: ineffectiveID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try state(ineffectiveDays, on: "2026-01-06"),
            .scored(band: .ineffective, activityType: .running)
        )
    }

    /// Two workouts, one day: the better band wins rather than the day reading as
    /// however its worse session scored.
    func testTwoWorkoutsOnOneDayResolveToTheBetterBand() throws {
        let morning = UUID()
        let evening = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(id: morning, on: "2026-01-06", activityType: .running, startOffsetSeconds: 0),
                try workout(id: evening, on: "2026-01-06", activityType: .cycling, startOffsetSeconds: 3_600 * 8),
            ],
            scoreLedgers: [
                morning: try ledger(points: 30, workoutID: morning), // ineffective
                evening: try ledger(points: 90, workoutID: evening), // effective — should win
            ],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .scored(band: .effective, activityType: .cycling))
    }

    /// Same band, two workouts: the earlier one wins, deterministically, regardless
    /// of the order they were supplied in.
    func testATieInBandBreaksOnEarliestStart() throws {
        let earlier = UUID()
        let later = UUID()
        let scoreLedgers: [UUID: ScoreLedger] = [
            earlier: try ledger(points: 80, workoutID: earlier),
            later: try ledger(points: 85, workoutID: later), // still .effective — same band as earlier
        ]
        let workouts = [
            try workout(id: earlier, on: "2026-01-06", activityType: .running, startOffsetSeconds: 0),
            try workout(id: later, on: "2026-01-06", activityType: .cycling, startOffsetSeconds: 3_600 * 4),
        ]

        let forward = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: scoreLedgers, planCalendar: try calendar()
        )
        let reversed = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts.reversed(), scoreLedgers: scoreLedgers, planCalendar: try calendar()
        )
        XCTAssertEqual(try state(forward, on: "2026-01-06"), .scored(band: .effective, activityType: .running))
        XCTAssertEqual(try state(reversed, on: "2026-01-06"), .scored(band: .effective, activityType: .running))
    }

    /// A workout on the plan's own scheduled rest day is still judged on its merits —
    /// D4 colors by what happened, not by what was asked.
    func testAWorkoutOnAScheduledRestDayStillShowsScoredNotScheduledRest() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: scheduled rest in Fixture.plan()
            workouts: [try workout(id: workoutID, on: "2026-01-05")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .scored(band: .effective, activityType: .running))
    }

    // MARK: - .awaitingScore

    func testARecordedButUnscoredRunIsAwaitingScore() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06", activityType: .running)],
            scoreLedgers: [:],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .awaitingScore(activityType: .running))
    }

    /// Both runs, deliberately: with two *kinds* of scoreless day since MAX-126, a
    /// mixed pair would leave this assertion satisfiable by either the earliest-start
    /// tiebreak or the run-before-non-run precedence, and it is the tiebreak this test
    /// is named for. The precedence has tests of its own below.
    func testMultipleUnscoredRunsPickTheEarliestDeterministically() throws {
        let earlier = UUID()
        let later = UUID()
        let workouts = [
            try workout(id: earlier, on: "2026-01-06", activityType: .running, startOffsetSeconds: 0),
            try workout(
                id: later, on: "2026-01-06",
                activityType: .treadmillRunning, startOffsetSeconds: 3_600 * 4
            ),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: [:], planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .awaitingScore(activityType: .running))
    }

    // MARK: - MAX-126: .noVerdict — recorded, and no score is coming

    /// The defect this state exists to fix. Before MAX-126 a lift resolved to
    /// `.awaitingScore`, which the calendar draws — and VoiceOver speaks — as a run the
    /// app has not got round to yet. Since MAX-111 no score is ever attempted for it, so
    /// that was a wait with nothing at the end of it.
    func testARecordedNonRunHasNoVerdictRatherThanAwaitingOne() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(
                    on: "2026-01-06",
                    activityType: .traditionalStrengthTraining
                )
            ],
            scoreLedgers: [:],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .noVerdict(activityType: .traditionalStrengthTraining)
        )
    }

    /// Every non-run, not just the lift MAX-109 is about: the split is
    /// `ActivityType.isRun`, so a ride, a hike and a walk are in exactly the same
    /// position and must not read as runs the app owes a verdict to.
    func testEveryNonRunActivityResolvesToNoVerdict() throws {
        for activityType: ActivityType in [.cycling, .hiking, .walking, .other] {
            let days = try resolve(
                from: "2026-01-06", through: "2026-01-06",
                workouts: [try workout(on: "2026-01-06", activityType: activityType)],
                scoreLedgers: [:],
                planCalendar: try calendar()
            )
            XCTAssertEqual(
                try state(days, on: "2026-01-06"),
                .noVerdict(activityType: activityType),
                "\(activityType)"
            )
        }
    }

    func testMultipleUnscoredNonRunsPickTheEarliestDeterministically() throws {
        let workouts = [
            try workout(
                on: "2026-01-06", activityType: .traditionalStrengthTraining,
                startOffsetSeconds: 3_600 * 6
            ),
            try workout(on: "2026-01-06", activityType: .cycling, startOffsetSeconds: 3_600),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: [:], planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .noVerdict(activityType: .cycling))
    }

    /// A lift on a day the plan asked for an easy run is **not** a miss. Something was
    /// recorded, and D4's "a workout that happened outranks the plan's ask" is unchanged
    /// by this ticket — whether an unmet *running* obligation should recolour such a day
    /// is §7.2's roll-up, which is MAX-116/MAX-117's and needs the lifting plan model to
    /// exist first. The prescription is still carried on the cell either way.
    func testALiftOnAPrescribedRunDayIsNeitherMissedNorScored() throws {
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06", // Tuesday: easy 8 km
            workouts: [
                try workout(on: "2026-01-06", activityType: .traditionalStrengthTraining)
            ],
            scoreLedgers: [:],
            planCalendar: try calendar()
        )
        let resolved = try cell(days, on: "2026-01-06")
        XCTAssertEqual(resolved.state, .noVerdict(activityType: .traditionalStrengthTraining))
        XCTAssertEqual(resolved.prescription?.scheduledSession.kind, .easy)
        // No stored classification exists for a lift, so there is nothing to compare
        // against the ask (D2) — and unlike an awaiting run, there never will be.
        XCTAssertNil(resolved.agreement)
        XCTAssertNil(resolved.state.scoredBand)
    }

    // MARK: - MAX-126: a day holding both a run and a lift

    /// The ordinary day once MAX-109 lands. A pending answer outranks a settled absence:
    /// this cell is about to become a band when the run is scored, so calling the day
    /// "no verdict" would be false within minutes. Asserted with the lift *first* so the
    /// earliest-start tiebreak cannot be what produces the answer.
    func testADayHoldingALiftAndAnUnscoredRunAwaitsTheRunsScore() throws {
        let workouts = [
            try workout(
                on: "2026-01-06", activityType: .traditionalStrengthTraining,
                startOffsetSeconds: 3_600
            ),
            try workout(on: "2026-01-06", activityType: .running, startOffsetSeconds: 3_600 * 10),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: [:], planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .awaitingScore(activityType: .running))
    }

    /// And once that run is scored, the band wins outright — the lift alongside it takes
    /// nothing away from a day that was judged.
    func testADayHoldingALiftAndAScoredRunShowsTheRunsBand() throws {
        let runID = UUID()
        let workouts = [
            try workout(
                on: "2026-01-06", activityType: .traditionalStrengthTraining,
                startOffsetSeconds: 3_600
            ),
            try workout(
                id: runID, on: "2026-01-06",
                activityType: .running, startOffsetSeconds: 3_600 * 10
            ),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts,
            scoreLedgers: [runID: try ledger(points: 88, workoutID: runID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .scored(band: .effective, activityType: .running)
        )
    }

    /// D8. A lift ingested before MAX-111 carries an immutable auto-score produced by
    /// the running rubric, and this ticket does not reach back and hide it: the day still
    /// shows the band that was stored. Whether those historical scores should be
    /// relabelled is A21/MAX-125, the owner's decision, and it has not been made.
    func testAnAlreadyScoredNonRunKeepsItsStoredBand() throws {
        let liftID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [
                try workout(
                    id: liftID, on: "2026-01-06",
                    activityType: .traditionalStrengthTraining
                )
            ],
            scoreLedgers: [liftID: try ledger(points: 30, workoutID: liftID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try state(days, on: "2026-01-06"),
            .scored(band: .ineffective, activityType: .traditionalStrengthTraining)
        )
    }

    /// The invariant the calendar's drawing is paid for by: the two scoreless states
    /// partition on `ActivityType.isRun`, so the activity glyph a cell already carries
    /// separates them without a new colour or a new mark. If this ever fails, a lifting
    /// day and a run awaiting its score have become the same cell.
    func testTheTwoScorelessStatesNeverCarryTheSameActivityType() throws {
        let workouts = [
            try workout(on: "2026-01-05", activityType: .running),
            try workout(on: "2026-01-06", activityType: .treadmillRunning),
            try workout(on: "2026-01-07", activityType: .traditionalStrengthTraining),
            try workout(on: "2026-01-08", activityType: .cycling),
            try workout(on: "2026-01-09", activityType: .hiking),
            try workout(on: "2026-01-10", activityType: .walking),
        ]
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-11",
            workouts: workouts, scoreLedgers: [:], planCalendar: try calendar()
        )
        for resolved in days {
            switch resolved.state {
            case .awaitingScore(let activityType):
                XCTAssertTrue(activityType.isRun, "\(resolved.date): \(activityType)")
            case .noVerdict(let activityType):
                XCTAssertFalse(activityType.isRun, "\(resolved.date): \(activityType)")
            case .scored, .missed, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
                continue
            }
        }
    }

    // MARK: - .missed / .convertedRest / .scheduledRest / .unplanned

    func testAMissedDayWithNoBudgetStaysMissed() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08", // Thursday: easy, nothing recorded
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .missed(scheduledKind: .easy))
    }

    /// Budget resolves per whole week (C1), so every other non-rest day of the week
    /// needs a recorded workout for Thursday to be the week's *only* miss — the same
    /// setup `TalliesTests`' combined-week test uses, reused here so the two suites
    /// stay comparable.
    func testAMissedDayWithBudgetConvertsToRest() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let saturday = UUID()
        let sunday = UUID()
        let otherWorkouts = [
            try workout(id: tuesday, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: saturday, on: "2026-01-10"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let otherLedgers: [UUID: ScoreLedger] = [
            tuesday: try ledger(points: 80, workoutID: tuesday),
            wednesday: try ledger(points: 80, workoutID: wednesday),
            saturday: try ledger(points: 80, workoutID: saturday),
            sunday: try ledger(points: 80, workoutID: sunday),
        ]
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08", // Thursday, the week's only miss
            workouts: otherWorkouts, scoreLedgers: otherLedgers,
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 1)
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .convertedRest(scheduledKind: .easy))
    }

    func testAScheduledRestDayWithNothingRecordedIsScheduledRest() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: scheduled rest
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .scheduledRest)
    }

    func testADayNoPlanGovernsIsUnplanned() throws {
        let days = try resolve(
            from: "2025-12-25", through: "2025-12-25", // well before Fixture.plan()'s effectiveFrom
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2025-12-25"), .unplanned)
    }

    func testEveryDayIsUnplannedWhenNoPlanHasBeenAuthored() throws {
        let days = try resolve(from: "2026-01-06", through: "2026-01-06", planCalendar: nil)
        XCTAssertEqual(try state(days, on: "2026-01-06"), .unplanned)
    }

    // MARK: - Shape of the result

    func testResolveReturnsExactlyOneEntryPerDayAscending() throws {
        let days = try resolve(from: "2026-01-05", through: "2026-01-11", planCalendar: try calendar())
        XCTAssertEqual(days.map(\.date), try CalendarDay.days(from: day("2026-01-05"), through: day("2026-01-11")))
    }

    func testResolveRejectsFromAfterThrough() throws {
        assertThrows(
            .inconsistent,
            try ScoreCalendar.resolve(
                from: try day("2026-01-10"),
                through: try day("2026-01-05"),
                timeZone: .gmt,
                today: try day("2026-12-31"),
                workouts: [],
                planCalendar: nil,
                restDayBudget: .standard
            )
        )
    }

    func testResultIsIndependentOfWorkoutInputOrder() throws {
        let tuesday = UUID()
        let wednesday = UUID()
        let sunday = UUID()
        let workouts = [
            try workout(id: tuesday, on: "2026-01-06"),
            try workout(id: wednesday, on: "2026-01-07"),
            try workout(id: sunday, on: "2026-01-11"),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            tuesday: try ledger(points: 80, workoutID: tuesday),
            wednesday: try ledger(points: 75, workoutID: wednesday),
            sunday: try ledger(points: 90, workoutID: sunday),
        ]

        func compute(_ ordered: [Workout]) throws -> [ScoreCalendarDay] {
            try resolve(
                from: "2026-01-05", through: "2026-01-11",
                workouts: ordered, scoreLedgers: scoreLedgers,
                planCalendar: try calendar(), restDayBudget: try RestDayBudget(daysPerWeek: 1)
            )
        }

        XCTAssertEqual(try compute(workouts), try compute(workouts.shuffled()))
    }

    // MARK: - C1: whole-week resolution, honoured regardless of the queried slice
    //
    // Mirrors `TalliesTests`' own C1 coverage exactly, because `ScoreCalendar` and
    // `TalliesCalculator` must reach the same conversion decision from the same
    // records — see this file's own header.

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
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday alone
            planCalendar: try calendar(try c1Plan()), restDayBudget: try RestDayBudget(daysPerWeek: 1)
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .missed(scheduledKind: .easy), "Friday is cheaper")
    }

    func testC1FridayAloneIsCorrectlyConvertedBecauseTheWholeWeekIsStillConsidered() throws {
        let days = try resolve(
            from: "2026-01-09", through: "2026-01-09", // Friday alone
            planCalendar: try calendar(try c1Plan()), restDayBudget: try RestDayBudget(daysPerWeek: 1)
        )
        XCTAssertEqual(try state(days, on: "2026-01-09"), .convertedRest(scheduledKind: .other))
    }

    // MARK: - MAX-105: a day that has not happened is not a day that was missed
    //
    // The defect this closes was visible on a real device: `resolve` had no notion of
    // today, so every scheduled day between now and the end of the selected month
    // resolved to `.missed` and rendered red. The fix is a state, not a filter — the
    // resolver reaches `.forthcoming` before it can reach `.missed` or `.convertedRest`,
    // so there is no path by which a future day acquires a miss for a view to hide.

    func testAScheduledDayInTheFutureIsForthcomingRatherThanMissed() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08", // Thursday: easy, nothing recorded
            today: "2026-01-06",                       // Tuesday — Thursday is still ahead
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .forthcoming(scheduledKind: .easy))
    }

    /// The same day, once it is behind the athlete. The two assertions differ only in
    /// `today`, which is the whole point: nothing about the records changed.
    func testTheSameScheduledDayIsMissedOnceItIsInThePast() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-09",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .missed(scheduledKind: .easy))
    }

    /// Today itself is forthcoming, not missed. A scheduled run at six in the morning
    /// has not been skipped, and a calendar that said so would be wrong for most of
    /// every day the athlete looks at it.
    func testTodayIsForthcomingNotMissed() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-08",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .forthcoming(scheduledKind: .easy))
    }

    /// A workout recorded today still wins: `.forthcoming` only ever describes a day
    /// with nothing on it.
    func testADayWithAWorkoutIsNeverForthcoming() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-08",
            workouts: [try workout(id: workoutID, on: "2026-01-08")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-08"), .scored(band: .effective, activityType: .running))
    }

    /// A scheduled rest day reads the same on either side of today. Rest was prescribed,
    /// rest is what the day is, and there is no outcome still pending on it.
    func testAFutureScheduledRestDayIsStillScheduledRest() throws {
        let days = try resolve(
            from: "2026-01-09", through: "2026-01-09", // Friday: rest in Fixture.plan()
            today: "2026-01-06",
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-09"), .scheduledRest)
    }

    /// The invariant behind the device report, asserted over a whole month rather than
    /// one day: **no day on or after today may carry a miss**, converted or not. This is
    /// the version CI can hold — a future edit that reintroduces the collapse fails here
    /// even if it never touches the two single-day tests above.
    func testNoDayOnOrAfterTodayIsEverMissedOrConverted() throws {
        let days = try resolve(
            from: "2026-01-01", through: "2026-01-31",
            today: "2026-01-14",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 2)
        )
        let today = try day("2026-01-14")
        for entry in days where entry.date >= today {
            switch entry.state {
            case .missed, .convertedRest:
                XCTFail("\(entry.date) has not happened yet and resolved to \(entry.state)")
            default:
                break
            }
        }
        // And the past half still resolves misses, so the assertion above is not passing
        // vacuously because nothing was ever missed.
        XCTAssertTrue(
            days.contains { $0.date < today && $0.state == .missed(scheduledKind: .easy) },
            "expected at least one genuine miss before today"
        )
    }

    /// The weekly rest-day budget is finite, so offering it days that have not happened
    /// spends it on non-events and leaves genuine misses unforgiven.
    ///
    /// Reasoned against `c1Plan()` — Monday easy / Tuesday hard / Wednesday rest /
    /// Thursday long / Friday other / Saturday easy / Sunday rest — because it is the
    /// template that makes the bug visible. On Wednesday, with one day of budget, the
    /// only days behind the athlete are Monday (easy, missed) and Tuesday (hard,
    /// missed), so Monday converts. Offer the future as well and Friday's `.other`
    /// wins on cost — the cheapest tier there is — so the allowance goes to a day
    /// nobody has reached and Monday's real miss stays red.
    func testTheRestDayBudgetIsNotSpentOnDaysThatHaveNotHappened() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-11",
            today: "2026-01-07",
            planCalendar: try calendar(try c1Plan()),
            restDayBudget: try RestDayBudget(daysPerWeek: 1)
        )
        XCTAssertEqual(try state(days, on: "2026-01-05"), .convertedRest(scheduledKind: .easy))
        XCTAssertEqual(try state(days, on: "2026-01-06"), .missed(scheduledKind: .hard))
        XCTAssertEqual(try state(days, on: "2026-01-07"), .scheduledRest)
        XCTAssertEqual(try state(days, on: "2026-01-09"), .forthcoming(scheduledKind: .other))
        XCTAssertEqual(try state(days, on: "2026-01-10"), .forthcoming(scheduledKind: .easy))
    }

    // MARK: - MAX-105: the plan layer

    /// Every day carries the plan version in effect *on that day* (D1), whatever became
    /// of it.
    func testEveryDayCarriesThePrescriptionInEffectOnIt() throws {
        let days = try resolve(from: "2026-01-05", through: "2026-01-11", planCalendar: try calendar())

        let monday = try cell(days, on: "2026-01-05")   // rest
        XCTAssertEqual(monday.prescription?.scheduledSession.kind, .rest)
        XCTAssertEqual(monday.prescription?.planVersion, try PlanVersion(1))
        XCTAssertFalse(monday.prescribesASession, "rest is not a session the plan can hold you to")

        let sunday = try cell(days, on: "2026-01-11")   // long
        XCTAssertEqual(sunday.prescription?.scheduledSession.kind, .long)
        XCTAssertTrue(sunday.prescribesASession)
    }

    /// A day before every plan version has no prescription at all — distinct from a
    /// prescription of rest, and the reason the plan layer is drawn on nothing there.
    func testADayNoPlanGovernsCarriesNoPrescription() throws {
        let days = try resolve(from: "2025-12-25", through: "2025-12-25", planCalendar: try calendar())
        let resolved = try cell(days, on: "2025-12-25")
        XCTAssertNil(resolved.prescription)
        XCTAssertFalse(resolved.prescribesASession)
    }

    /// The long-run distance comes from the arc for the week the day falls in, so the
    /// prescription is the plan's real ask rather than the template's placeholder — the
    /// D1 resolution, not a re-derivation.
    func testALongRunDayCarriesTheArcDistanceForItsWeek() throws {
        let days = try resolve(from: "2026-01-11", through: "2026-01-18", planCalendar: try calendar())
        // Fixture.plan()'s arc: week 1 → 16 km, week 2 → 18 km. effectiveFrom is
        // Thursday 2026-01-01, so arc week 1 opens on Monday 2025-12-29.
        XCTAssertEqual(try cell(days, on: "2026-01-11").prescription?.scheduledSession.distanceMeters, 18_000)
        XCTAssertEqual(try cell(days, on: "2026-01-18").prescription?.scheduledSession.distanceMeters, 20_000)
    }

    // MARK: - MAX-105: plan versus execution

    func testACompletedDayMatchingItsPrescriptionAgrees() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06", // Tuesday: easy 8 km
            workouts: [try workout(id: workoutID, on: "2026-01-06")],
            scoreLedgers: [
                workoutID: try ledger(
                    points: 90, workoutID: workoutID,
                    scheduledKind: .easy, actualClassification: .easy
                ),
            ],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try cell(days, on: "2026-01-06").agreement, .asPrescribed(kind: .easy))
    }

    func testACompletedDayDivergingFromItsPrescriptionSaysWhatWasAskedAndWhatWasRun() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-11", through: "2026-01-11", // Sunday: long run
            workouts: [try workout(id: workoutID, on: "2026-01-11")],
            scoreLedgers: [
                workoutID: try ledger(
                    points: 60, workoutID: workoutID,
                    scheduledKind: .long, actualClassification: .easy
                ),
            ],
            planCalendar: try calendar()
        )
        XCTAssertEqual(
            try cell(days, on: "2026-01-11").agreement,
            .divergent(prescribed: .long, performed: .easy)
        )
    }

    /// A run on the plan's own rest day. Not a failure, and not agreement either — the
    /// divergence the calendar could not show at all before this ticket.
    func testASessionOnAScheduledRestDayIsUnprescribed() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: scheduled rest
            workouts: [try workout(id: workoutID, on: "2026-01-05")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        let resolved = try cell(days, on: "2026-01-05")
        XCTAssertEqual(resolved.agreement, .unprescribed(performed: .easy))
        XCTAssertFalse(resolved.prescribesASession)
    }

    func testASessionOnADayNoPlanGovernsIsUnprescribed() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2025-12-25", through: "2025-12-25",
            workouts: [try workout(id: workoutID, on: "2025-12-25")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try cell(days, on: "2025-12-25").agreement, .unprescribed(performed: .easy))
    }

    /// The comparison waits for the score, because the classification it compares
    /// against is stored on the score (D2). The *ask* does not wait — the day still
    /// carries its prescription.
    func testARecordedButUnscoredDayHasAPrescriptionButNoAgreementYet() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06")],
            planCalendar: try calendar()
        )
        let resolved = try cell(days, on: "2026-01-06")
        XCTAssertNil(resolved.agreement)
        XCTAssertTrue(resolved.prescribesASession)
    }

    /// The agreement is read off the same workout the band is, so a two-workout day
    /// cannot report one session's band beside another session's divergence.
    func testTheAgreementDescribesTheSameWorkoutTheBandDoes() throws {
        let morning = UUID()
        let evening = UUID()
        let days = try resolve(
            from: "2026-01-11", through: "2026-01-11", // Sunday: long run
            workouts: [
                try workout(id: morning, on: "2026-01-11", startOffsetSeconds: 0),
                try workout(id: evening, on: "2026-01-11", startOffsetSeconds: 3_600 * 8),
            ],
            scoreLedgers: [
                morning: try ledger(
                    points: 30, workoutID: morning,
                    scheduledKind: .long, actualClassification: .easy
                ),
                evening: try ledger(
                    points: 90, workoutID: evening,
                    scheduledKind: .long, actualClassification: .long
                ),
            ],
            planCalendar: try calendar()
        )
        let resolved = try cell(days, on: "2026-01-11")
        XCTAssertEqual(resolved.state, .scored(band: .effective, activityType: .running))
        XCTAssertEqual(resolved.agreement, .asPrescribed(kind: .long))
    }

    // MARK: - MAX-108: the tappability decision
    //
    // "Is there anything behind this day" has to be decided here, not by a view
    // guessing from `state`'s case — the whole reason being that several states share
    // the same "nothing recorded" fact but not the same tense relative to `today`.

    func testADayWithOneWorkoutHasThatWorkoutAsItsDestination() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-06"), .workouts([workoutID]))
    }

    /// The interesting half. Both workouts are in the destination, ordered by start
    /// time regardless of the order they were supplied in — the order a swipe between
    /// them should present, and the same tiebreak the band-ranking and
    /// earliest-unscored logic elsewhere in this type already use.
    func testATwoWorkoutDayCarriesBothOrderedByStartTime() throws {
        let morning = UUID()
        let evening = UUID()
        let workouts = [
            try workout(id: evening, on: "2026-01-06", startOffsetSeconds: 3_600 * 8),
            try workout(id: morning, on: "2026-01-06", startOffsetSeconds: 0),
        ]
        let scoreLedgers: [UUID: ScoreLedger] = [
            morning: try ledger(points: 90, workoutID: morning),
            evening: try ledger(points: 60, workoutID: evening),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: scoreLedgers, planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-06"), .workouts([morning, evening]))
    }

    /// Three or more is not a special case — the door just carries every id.
    func testAThreeWorkoutDayCarriesAllThreeOrderedByStartTime() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let workouts = [
            try workout(id: third, on: "2026-01-06", startOffsetSeconds: 3_600 * 16),
            try workout(id: first, on: "2026-01-06", startOffsetSeconds: 0),
            try workout(id: second, on: "2026-01-06", startOffsetSeconds: 3_600 * 8),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-06"), .workouts([first, second, third]))
    }

    /// An unscored workout still opens — the destination does not wait on a band the
    /// way the state's own colour does.
    func testAnAwaitingScoreDayStillHasAWorkoutDestination() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06", activityType: .hiking)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-06"), .workouts([workoutID]))
    }

    /// A missed day, behind the athlete: a true dead end.
    func testAMissedDayHasNoRecordedDestination() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08", // Thursday: easy, nothing recorded
            today: "2026-01-09",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try destination(days, on: "2026-01-08"), .nothingRecorded)
    }

    /// The same day, still ahead of the athlete: not yet due, not a dead tap that
    /// happens to read the same as one that is.
    func testAForthcomingDayIsNotYetDue() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-06",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try destination(days, on: "2026-01-08"), .notYetDue)
    }

    /// Today itself follows `.forthcoming`'s own strict boundary: not yet due, not
    /// nothing-recorded, even though no workout exists yet either way.
    func testTodayWithNothingRecordedIsNotYetDue() throws {
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-08",
            planCalendar: try calendar(),
            restDayBudget: try RestDayBudget(daysPerWeek: 0)
        )
        XCTAssertEqual(try destination(days, on: "2026-01-08"), .notYetDue)
    }

    /// A scheduled rest day carries no tense of its own in `state` — this is the case
    /// the core has to get right that a view reading `state`'s case alone could not.
    /// Behind the athlete, it is a dead end.
    func testAPastScheduledRestDayHasNoRecordedDestination() throws {
        let days = try resolve(
            from: "2026-01-05", through: "2026-01-05", // Monday: scheduled rest
            today: "2026-01-06",
            planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-05"), .nothingRecorded)
    }

    /// The same scheduled-rest day, still ahead: not yet due, even though `state` is
    /// `.scheduledRest` on both sides of `today` and cannot tell the two apart itself.
    func testAFutureScheduledRestDayIsNotYetDue() throws {
        let days = try resolve(
            from: "2026-01-09", through: "2026-01-09", // Friday: rest in Fixture.plan()
            today: "2026-01-06",
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-09"), .scheduledRest, "state alone cannot see the tense")
        XCTAssertEqual(try destination(days, on: "2026-01-09"), .notYetDue)
    }

    /// `.unplanned` carries no tense either — a query reaching earlier than every plan
    /// version. Past, it is a dead end.
    func testAPastUnplannedDayHasNoRecordedDestination() throws {
        let days = try resolve(
            from: "2025-12-25", through: "2025-12-25", // before Fixture.plan()'s effectiveFrom
            today: "2025-12-26",
            planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2025-12-25"), .nothingRecorded)
    }

    /// The same unplanned state, ahead of the athlete: still not yet due. Nothing about
    /// "no plan governs this day" implies the day has already happened.
    func testAFutureUnplannedDayIsNotYetDue() throws {
        let days = try resolve(
            from: "2025-12-25", through: "2025-12-25",
            today: "2025-12-24",
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2025-12-25"), .unplanned, "state alone cannot see the tense")
        XCTAssertEqual(try destination(days, on: "2025-12-25"), .notYetDue)
    }

    /// A recorded workout always wins the destination too, mirroring `.forthcoming`'s
    /// own rule that a workout on the day beats every other reading of it.
    func testADayWithAWorkoutIsNeverNotYetDueEvenOnTheDayItself() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-08", through: "2026-01-08",
            today: "2026-01-08",
            workouts: [try workout(id: workoutID, on: "2026-01-08")],
            scoreLedgers: [workoutID: try ledger(points: 90, workoutID: workoutID)],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try destination(days, on: "2026-01-08"), .workouts([workoutID]))
    }
}
