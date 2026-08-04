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

    private func ledger(points: Int, workoutID: UUID) throws -> ScoreLedger {
        try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: workoutID))
    }

    private func calendar(_ plan: Plan? = nil) throws -> PlanCalendar {
        try PlanCalendar([plan ?? Fixture.plan()])
    }

    private func resolve(
        from: String,
        through: String,
        workouts: [Workout] = [],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget = .standard
    ) throws -> [ScoreCalendarDay] {
        try ScoreCalendar.resolve(
            from: try day(from),
            through: try day(through),
            timeZone: .gmt,
            workouts: workouts,
            scoreLedgers: scoreLedgers,
            planCalendar: planCalendar,
            restDayBudget: restDayBudget
        )
    }

    private func state(_ days: [ScoreCalendarDay], on text: String) throws -> ScoreCalendarDayState {
        let target = try day(text)
        return try XCTUnwrap(days.first { $0.date == target }).state
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

    func testARecordedButUnscoredWorkoutIsAwaitingScore() throws {
        let workoutID = UUID()
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: [try workout(id: workoutID, on: "2026-01-06", activityType: .hiking)],
            scoreLedgers: [:],
            planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .awaitingScore(activityType: .hiking))
    }

    func testMultipleUnscoredWorkoutsPickTheEarliestDeterministically() throws {
        let earlier = UUID()
        let later = UUID()
        let workouts = [
            try workout(id: earlier, on: "2026-01-06", activityType: .running, startOffsetSeconds: 0),
            try workout(id: later, on: "2026-01-06", activityType: .cycling, startOffsetSeconds: 3_600 * 4),
        ]
        let days = try resolve(
            from: "2026-01-06", through: "2026-01-06",
            workouts: workouts, scoreLedgers: [:], planCalendar: try calendar()
        )
        XCTAssertEqual(try state(days, on: "2026-01-06"), .awaitingScore(activityType: .running))
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
}
