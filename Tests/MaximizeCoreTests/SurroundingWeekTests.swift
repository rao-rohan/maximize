import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-182 / A29 — a workout conversation knows where the session sits in the athlete's
/// week, in aggregates and plan configuration only.
///
/// Everything here is reasoned against `Fixture.plan()`: effective from **Thursday
/// 2026-01-01**, template Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday easy
/// 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km, cap 150 bpm, effective
/// threshold 70. Arc weeks are Monday-anchored from **Monday 2025-12-29**, so the week
/// **2026-01-05…11 is arc week 2**, whose prescribed long run is 18 km. The subject of most
/// of these tests is a run on **Tuesday 2026-01-06**.
///
/// Two tests here matter more than the rest.
/// `testAScoringContextNeverCarriesTheSurroundingWeek` is the D8 guard: a scoring prompt
/// that grew a week block would make an immutable, permanently stored score depend on what
/// happened on days other than the one being scored, and `ContextDisciplineTests` pins that
/// prompt byte for byte as the other half of the same protection.
/// `testTheBlockDoesNotGrowWithHowMuchTheAthleteTrained` is A29's bound: the shape MAX-184's
/// audit imposed is that this block is O(1), and a test is the only thing that keeps that
/// true after the next edit.
final class SurroundingWeekTests: XCTestCase {

    // MARK: - Fixtures

    private static let heading = "## The week around this session"

    /// Well clear of the fixture week, so no test picks up the "this week is not over"
    /// branch unless it asks for it.
    private static let today = "2026-06-01"

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func calendar(_ plans: [Plan]? = nil) throws -> PlanCalendar {
        try PlanCalendar(plans ?? [Fixture.plan()])
    }

    private func workout(
        id: UUID,
        on dayText: String,
        atHour hour: Double = 8,
        activityType: ActivityType = .running,
        durationSeconds: Double = 3_600,
        distanceMeters: Double? = 10_000
    ) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(hour * 3_600)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 500,
            hasRoute: distanceMeters != nil,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 60)
        )
    }

    private func metrics(workoutID: UUID) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            planVersion: PlanVersion(1)
        )
    }

    private func ledger(points: Int, workoutID: UUID) throws -> ScoreLedger {
        try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: workoutID))
    }

    private func record(
        id: UUID,
        on dayText: String,
        atHour hour: Double = 8,
        activityType: ActivityType = .running,
        durationSeconds: Double = 3_600,
        distanceMeters: Double? = 10_000,
        scored: Int? = 82,
        withMetrics: Bool = false
    ) throws -> ContextInputs.WorkoutRecord {
        try ContextInputs.WorkoutRecord(
            workout: try workout(
                id: id,
                on: dayText,
                atHour: hour,
                activityType: activityType,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters
            ),
            metrics: withMetrics ? try metrics(workoutID: id) : nil,
            ledger: try scored.map { try ledger(points: $0, workoutID: id) }
        )
    }

    private func inputs(
        _ records: [ContextInputs.WorkoutRecord],
        planCalendar: PlanCalendar?,
        today: String = SurroundingWeekTests.today,
        timeZone: TimeZone = .gmt
    ) throws -> ContextInputs {
        try ContextInputs(
            timeZone: timeZone,
            today: try day(today),
            planCalendar: planCalendar,
            restDayBudget: .standard,
            records: records
        )
    }

    /// The subject run, on Tuesday 2026-01-06, alongside whatever else the week holds.
    private func context(
        alongside others: [ContextInputs.WorkoutRecord] = [],
        subjectID: UUID = UUID(),
        planCalendar: PlanCalendar? = nil,
        today: String = SurroundingWeekTests.today,
        timeZone: TimeZone = .gmt
    ) throws -> WorkoutContext {
        let subject = try record(id: subjectID, on: "2026-01-06", withMetrics: true)
        let built = try ContextBuilder.build(
            for: .workout(subjectID),
            from: try inputs(
                [subject] + others,
                planCalendar: try planCalendar ?? calendar(),
                today: today,
                timeZone: timeZone
            )
        )
        guard case let .workout(context) = built else {
            throw DomainError.inconsistent(reason: "expected a workout context")
        }
        return context
    }

    /// The text of the week block alone, so a test asserting something is *absent* cannot
    /// pass or fail on the run's own record above it.
    private func weekBlock(of context: WorkoutContext) throws -> String {
        let sheet = context.factSheet()
        guard let start = sheet.range(of: Self.heading) else {
            throw DomainError.inconsistent(reason: "the fact sheet carries no week block")
        }
        return String(sheet[start.lowerBound...])
    }

    // MARK: - The scorer is not shown this

    /// **The load-bearing test.** D1 fixes a workout's verdict to the plan version in effect
    /// on its date and D8 stores that verdict forever. A scorer that could read the days
    /// around the session would score two identical runs differently according to what
    /// happened beside them — permanently, and with nothing on screen to contradict it.
    ///
    /// Both gates are checked: the builder drops a week handed to a `.scoring` audience, and
    /// the renderer omits the section even if a context somehow held one.
    func testAScoringContextNeverCarriesTheSurroundingWeek() throws {
        let id = UUID()
        let built = try inputs(
            [try record(id: id, on: "2026-01-06", withMetrics: true)],
            planCalendar: try calendar()
        )
        let week = try ContextBuilder.surroundingWeek(around: try day("2026-01-06"), from: built)

        let scoring = try WorkoutContextBuilder.build(
            workout: try workout(id: id, on: "2026-01-06"),
            on: try day("2026-01-06"),
            metrics: try metrics(workoutID: id),
            classification: .easy,
            planCalendar: try calendar(),
            audience: .scoring,
            surroundingWeek: week
        )

        XCTAssertNil(scoring.surroundingWeek)
        XCTAssertFalse(scoring.factSheet().contains(Self.heading), scoring.factSheet())
    }

    /// The same run, scored with and without a week offered: the two prompts must be equal
    /// to the byte. `ContextDisciplineTests` pins the exact text; this pins that *offering* a
    /// week cannot move it.
    func testOfferingAWeekToTheScorerChangesNothingInItsPrompt() throws {
        let id = UUID()
        let built = try inputs(
            [try record(id: id, on: "2026-01-06", withMetrics: true)],
            planCalendar: try calendar()
        )
        let week = try ContextBuilder.surroundingWeek(around: try day("2026-01-06"), from: built)

        func scoringSheet(offering week: WorkoutContext.SurroundingWeek?) throws -> String {
            try WorkoutContextBuilder.build(
                workout: try workout(id: id, on: "2026-01-06"),
                on: try day("2026-01-06"),
                metrics: try metrics(workoutID: id),
                classification: .easy,
                planCalendar: try calendar(),
                audience: .scoring,
                surroundingWeek: week
            ).factSheet()
        }

        XCTAssertEqual(try scoringSheet(offering: week), try scoringSheet(offering: nil))
    }

    /// The chat half of the same rule: a workout thread does get it, through the one entry
    /// point, without the caller asking for it.
    func testAWorkoutThreadReceivesTheSurroundingWeek() throws {
        let context = try context()
        XCTAssertEqual(context.audience, .chat)
        XCTAssertNotNil(context.surroundingWeek)
        XCTAssertTrue(context.factSheet().contains(Self.heading), context.factSheet())
    }

    // MARK: - A29's bound: the block does not grow with training volume

    /// The constraint MAX-184's audit imposed, as a test rather than an intention. A week
    /// with one session and a week with fourteen must render the same lines, because a
    /// per-session term is `TrainingContext` arriving by a side door and would make a
    /// workout prompt grow with how much the athlete trains.
    ///
    /// Only two lines may legitimately differ: the session count, and the "nothing else is
    /// recorded" sentence that a one-session week states and a busy one does not.
    func testTheBlockDoesNotGrowWithHowMuchTheAthleteTrained() throws {
        let subjectID = UUID()
        let busy = try (0..<13).map { index in
            try record(
                id: UUID(),
                on: "2026-01-0\(7 + index % 3)",
                atHour: Double(index % 12),
                scored: index.isMultiple(of: 2) ? 78 : nil,
                withMetrics: true
            )
        }

        let quietLines = try weekBlock(of: try context(subjectID: subjectID))
            .components(separatedBy: "\n")
        let busyLines = try weekBlock(of: try context(alongside: busy, subjectID: subjectID))
            .components(separatedBy: "\n")

        // One line apart, and that line is the absence sentence only the quiet week states.
        // Thirteen extra sessions add no lines at all; they move figures, which is the whole
        // point of an aggregate.
        XCTAssertEqual(quietLines.count, busyLines.count + 1, "\(quietLines)\n\n\(busyLines)")
        XCTAssertTrue(
            quietLines.contains("No workout other than this one is recorded anywhere in this week.")
        )
        XCTAssertFalse(
            busyLines.contains("No workout other than this one is recorded anywhere in this week.")
        )
        XCTAssertTrue(busyLines.contains("Workouts recorded in this week: 14"), "\(busyLines)")
    }

    /// No session but the subject's own is described in any way — not its distance, its
    /// duration, its type, its classification, its heart rate, its drift or its score. This
    /// is the difference between this block and `TrainingContext`, which carries all of them
    /// per session by design.
    func testNoSiblingSessionIsDescribedInTheWeekBlock() throws {
        let block = try weekBlock(of: try context(alongside: [
            try record(
                id: UUID(),
                on: "2026-01-08",
                durationSeconds: 3_120,
                distanceMeters: 9_200,
                scored: 78,
                withMetrics: true
            ),
            try record(
                id: UUID(),
                on: "2026-01-10",
                activityType: .traditionalStrengthTraining,
                durationSeconds: 2_700,
                distanceMeters: nil,
                scored: nil
            ),
        ]))

        for leaked in [
            "9.20 km",            // the Thursday run's distance
            "52m 0s",             // its duration
            "45m 0s",             // the Saturday lift's duration
            "classified",         // any stored classification
            "78/100",             // any sibling's score
            "Average heart rate",
            "Heart-rate drift",
            "Rationale given:",
            "Held the cap",       // `Fixture.score`'s rationale text
        ] {
            XCTAssertFalse(block.contains(leaked), "\(leaked) reached the week block:\n\(block)")
        }
    }

    // MARK: - The window, and the arithmetic that resolves it

    func testTheWindowIsTheMondayFirstWeekContainingTheSession() throws {
        guard let week = try context().surroundingWeek else { return XCTFail("no week") }

        XCTAssertEqual(week.from, try day("2026-01-05"))
        XCTAssertEqual(week.through, try day("2026-01-11"))
        XCTAssertEqual(week.from.weekday, .monday)
        XCTAssertEqual(week.through.weekday, .sunday)
        XCTAssertEqual(week.days.map(\.date), try CalendarDay.days(
            from: try day("2026-01-05"),
            through: try day("2026-01-11")
        ))
    }

    /// A Sunday session is the *end* of its week, not the start of the next one — the
    /// Monday-first boundary the weekly template is written against. The naive spelling of
    /// "the week containing this day" gets Sunday wrong in both directions.
    func testASundaySessionSitsAtTheEndOfItsWeekAndAMondayAtTheStart() throws {
        for (dayText, expectedStart) in [
            ("2026-01-11", "2026-01-05"), // Sunday
            ("2026-01-12", "2026-01-12"), // the Monday after it
        ] {
            let id = UUID()
            let built = try ContextBuilder.build(
                for: .workout(id),
                from: try inputs(
                    [try ContextInputs.WorkoutRecord(
                        workout: try workout(id: id, on: dayText),
                        metrics: try metrics(workoutID: id),
                        ledger: try ledger(points: 82, workoutID: id)
                    )],
                    planCalendar: try calendar()
                )
            )
            guard case let .workout(context) = built, let week = context.surroundingWeek else {
                return XCTFail("expected a workout context with a week")
            }
            XCTAssertEqual(week.from, try day(expectedStart), dayText)
            XCTAssertEqual(try week.from.days(until: week.through), 6, dayText)
        }
    }

    /// **The same instant, two time zones, two different weeks.** 2026-01-12T01:00Z is Monday
    /// in GMT and Sunday evening in Los Angeles, so the session belongs to a different
    /// Monday-first week depending on where the athlete was standing — which is why the zone
    /// enters at `Workout.calendarDay(in:)` and why nothing downstream may guess one.
    ///
    /// A week resolved by adding 86,400-second blocks would also drift by an hour across a
    /// daylight-saving change; `CalendarDay`'s arithmetic counts days as days, and
    /// `MuscleFatigue`'s own note points at the defect that avoids.
    func testTheWeekIsResolvedInTheAthletesTimeZoneAndNotTheDevices() throws {
        let id = UUID()
        let instant = try day("2026-01-12").civilAnchor().addingTimeInterval(3_600)
        let run = try Workout(
            id: id,
            activityType: .running,
            start: instant,
            end: instant.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 10_000,
            activeEnergyKilocalories: 500,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: instant.addingTimeInterval(3_700)
        )

        func week(in timeZone: TimeZone) throws -> WorkoutContext.SurroundingWeek {
            let built = try ContextBuilder.build(
                for: .workout(id),
                from: try inputs(
                    [try ContextInputs.WorkoutRecord(
                        workout: run,
                        metrics: try metrics(workoutID: id),
                        ledger: try ledger(points: 82, workoutID: id)
                    )],
                    planCalendar: try calendar(),
                    timeZone: timeZone
                )
            )
            guard case let .workout(context) = built, let week = context.surroundingWeek else {
                throw DomainError.inconsistent(reason: "expected a workout context with a week")
            }
            return week
        }

        guard let losAngeles = TimeZone(identifier: "America/Los_Angeles") else {
            return XCTFail("America/Los_Angeles is not available")
        }
        XCTAssertEqual(try week(in: .gmt).from, try day("2026-01-12"))
        XCTAssertEqual(try week(in: losAngeles).from, try day("2026-01-05"))
        XCTAssertEqual(try week(in: losAngeles).through, try day("2026-01-11"))
    }

    /// A week the session does not fall in is not a smaller truth, it is a false heading over
    /// real figures — and the model has no way to notice.
    func testTheBuilderRefusesAWeekTheWorkoutDoesNotFallIn() throws {
        let id = UUID()
        let elsewhere = try ContextBuilder.surroundingWeek(
            around: try day("2026-01-06"),
            from: try inputs(
                [try record(id: id, on: "2026-01-06", withMetrics: true)],
                planCalendar: try calendar()
            )
        )

        XCTAssertThrowsError(
            try WorkoutContextBuilder.build(
                workout: try workout(id: id, on: "2026-01-20"),
                on: try day("2026-01-20"),
                metrics: try metrics(workoutID: id),
                classification: .easy,
                planCalendar: try calendar(),
                audience: .chat,
                surroundingWeek: elsewhere
            )
        )
    }

    // MARK: - The fields chosen

    /// The week's asks, every day of it — the reference the figures above are measured
    /// against, and the only thing in the block that makes "should I back off Thursday"
    /// answerable. Configuration, never a measurement of the athlete (§3.3 item 1).
    func testEveryDayOfTheWeekNamesWhatThePlanAskedOfIt() throws {
        let block = try weekBlock(of: try context())

        XCTAssertTrue(block.contains("Monday 2026-01-05 · rest"), block)
        XCTAssertTrue(block.contains("Tuesday 2026-01-06 · easy, 8.0 km"), block)
        XCTAssertTrue(block.contains("Wednesday 2026-01-07 · hard, (6 × 800m)"), block)
        XCTAssertTrue(block.contains("Sunday 2026-01-11 · long, 18.0 km"), block)
    }

    /// A plan that prescribes a lift names it on the day, tagged, and says nothing on the
    /// days it does not — with the convention stated once so the silence is a stated fact
    /// rather than a gap (MAX-175, and `TrainingFactSheet`'s own precedent).
    func testALiftAskIsNamedOnItsDayAndOmittedOnEveryOther() throws {
        let plan = try Fixture.plan(lift: [
            .thursday: ScheduledSession(
                kind: .lift,
                durationSeconds: 2_700,
                note: "upper body",
                muscleGroups: [.shoulders, .chest]
            ),
        ])
        let block = try weekBlock(of: try context(planCalendar: try calendar([plan])))

        XCTAssertTrue(block.contains("a day with no lift clause prescribes no lifting that day"), block)
        XCTAssertTrue(
            block.contains("Thursday 2026-01-08 · easy, 8.0 km · Lift: lift, 45m 0s, "
                + "muscle groups: chest, shoulders (upper body)"),
            block
        )
        // Once on Thursday's line and nowhere else. Counted as the field separator rather
        // than the bare word, so the preamble's own `(tagged "Lift:")` is not miscounted as
        // an eighth day prescribing one.
        XCTAssertEqual(block.components(separatedBy: " · Lift: ").count - 1, 1, block)
    }

    /// Where the week sits in the block (D1's arc), quoted from the one resolution of "what
    /// week is it" — `PlanCalendar.arcWeek`, through the tallies.
    func testTheArcWeekAndItsPrescribedLongRunAreStated() throws {
        let context = try context()
        guard let week = context.surroundingWeek else { return XCTFail("no week") }

        XCTAssertEqual(week.arcWeekIndex, 2)
        XCTAssertEqual(week.arcWeekLongRunMeters, 18_000)
        XCTAssertTrue(
            context.factSheet().contains("Arc week 2 under plan v1, long run prescribed: 18.00 km."),
            context.factSheet()
        )
    }

    /// §3.6(a) with teeth: the block's aggregates are `TalliesCalculator`'s own values for
    /// exactly this week, not a second count made here. If this ever drifts, a figure quoted
    /// in a workout thread and the same figure on the dashboard have started to disagree.
    func testTheWeeksTalliesAreTheCalculatorsOwnValuesForExactlyThatWeek() throws {
        let subjectID = UUID()
        let others = [try record(id: UUID(), on: "2026-01-08", scored: 78, withMetrics: true)]
        guard let week = try context(alongside: others, subjectID: subjectID).surroundingWeek else {
            return XCTFail("no week")
        }

        let subject = try record(id: subjectID, on: "2026-01-06", withMetrics: true)
        let all = [subject] + others
        let expected = try TalliesCalculator.compute(
            TalliesInput(
                from: try day("2026-01-05"),
                through: try day("2026-01-11"),
                timeZone: .gmt,
                today: try day(Self.today),
                workouts: all.map(\.workout),
                scoreLedgers: Dictionary(
                    uniqueKeysWithValues: all.compactMap { record in
                        record.ledger.map { (record.workout.id, $0) }
                    }
                ),
                planCalendar: try calendar(),
                restDayBudget: .standard
            )
        )

        XCTAssertEqual(week.tallies, expected)
        XCTAssertEqual(week.tallies.from, week.from)
        XCTAssertEqual(week.tallies.through, week.through)
        XCTAssertEqual(week.sessionCount, 2)
    }

    /// A tally computed over a different span cannot be printed under this week's heading:
    /// the block's first sentence promises every figure is measured over exactly these seven
    /// days, and that promise is a check rather than a comment.
    func testAWeekRefusesTalliesComputedOverADifferentSpan() throws {
        let month = try TalliesCalculator.compute(
            TalliesInput(
                from: try day("2026-01-01"),
                through: try day("2026-01-31"),
                timeZone: .gmt,
                today: try day(Self.today),
                workouts: [],
                scoreLedgers: [:],
                planCalendar: try calendar(),
                restDayBudget: .standard
            )
        )

        XCTAssertThrowsError(
            try WorkoutContext.SurroundingWeek(
                from: try day("2026-01-05"),
                through: try day("2026-01-11"),
                today: try day(Self.today),
                plan: try Fixture.plan(),
                tallies: month,
                days: try CalendarDay.days(from: try day("2026-01-05"), through: try day("2026-01-11"))
                    .map { WorkoutContext.SurroundingWeek.Day(date: $0, planDay: nil) },
                sessionCount: 0
            )
        )
    }

    /// The streak is the one tally withheld: it walks backwards out of the week, so it is not
    /// measured over the seven days the block's opening sentence promises — and over a window
    /// this short it is a truncated lower bound with no way to say so.
    func testTheStreakIsNotQuotedInTheWeekBlock() throws {
        XCTAssertFalse(try weekBlock(of: try context()).contains("Current streak"))
    }

    // MARK: - Absence is a designed state

    /// A first session on a new install, or one ninety days back with nothing around it. The
    /// record states its own absence, in words, so the model does not supply a figure
    /// (MAX-175) — and states it about *the record*, not about the athlete: what this app
    /// holds for a week and what a person did in it are different claims, and only the first
    /// is one it can make (R10's rule, at a different seam).
    func testAWeekHoldingNothingElseSaysSoRatherThanReadingAsAnEmptyWeek() throws {
        let block = try weekBlock(of: try context())

        XCTAssertTrue(
            block.contains("No workout other than this one is recorded anywhere in this week."),
            block
        )
        XCTAssertTrue(block.contains("Workouts recorded in this week: 1"), block)
        // Not a fabricated zero anywhere: the effective ratio is a ratio, and an average with
        // nothing scored under it is an absence rather than a 0.
        XCTAssertFalse(block.contains("Average score this week: 0"), block)
    }

    /// Nothing eligible is not the same statement as nothing achieved, and
    /// `EffectiveObligationTally` refuses to collapse them. The prompt must not turn that
    /// refusal back into a zero.
    func testAWeekWithNothingEligibleSaysSoRatherThanReportingZero() throws {
        // `today` is the subject's own day, so the only decided day in the week is Monday,
        // which the plan rests: nothing was eligible, and nothing was failed either.
        let block = try weekBlock(of: try context(today: "2026-01-06"))
        XCTAssertTrue(block.contains("Effective sessions: nothing in this week was eligible"), block)
        XCTAssertFalse(block.contains("Effective sessions: 0/"), block)
    }

    /// Seven repetitions of "no plan version governed this day" is the prompt spending its
    /// budget on absences. Said once, and the day lines are not emitted at all —
    /// `TrainingFactSheet` and `WorkoutFactSheet` both invert the same rule for the same
    /// reason.
    func testAWeekNoPlanGovernsSaysSoOnceRatherThanSevenTimes() throws {
        let base = try Fixture.plan()
        let later = try Plan(
            version: base.version,
            effectiveFrom: try day("2026-03-02"),
            weeklyTemplate: base.weeklyTemplate,
            longRunArc: base.longRunArc,
            heartRateCapBPM: base.heartRateCapBPM,
            cadenceTarget: base.cadenceTarget,
            rubric: base.rubric,
            goals: base.goals
        )
        let block = try weekBlock(of: try context(planCalendar: try calendar([later])))

        XCTAssertEqual(
            block.components(separatedBy: "No plan version governed any day of this week").count - 1,
            1,
            block
        )
        XCTAssertFalse(block.contains("Monday 2026-01-05 ·"), block)
        XCTAssertTrue(block.contains("no arc week"), block)
    }

    /// A week reaching past today: an ask with nothing recorded against it reads the same
    /// whether the day has been and gone or has not arrived, and only one of those is a
    /// session the athlete skipped.
    func testAWeekThatIsNotOverSaysSo() throws {
        let midweek = try context(today: "2026-01-07")
        XCTAssertTrue(
            midweek.factSheet().contains("This week is not over: today is 2026-01-07."),
            midweek.factSheet()
        )
        XCTAssertFalse(try weekBlock(of: try context()).contains("This week is not over"))
    }

    // MARK: - Determinism

    /// The same stored week must render byte-identically every time, or D3's determinism
    /// quietly stops being true at the prompt boundary.
    func testTheSameWeekRendersIdenticallyRegardlessOfInputOrder() throws {
        let subjectID = UUID()
        let others = [
            try record(id: UUID(), on: "2026-01-08", atHour: 7, scored: 78, withMetrics: true),
            try record(id: UUID(), on: "2026-01-08", atHour: 7, activityType: .traditionalStrengthTraining,
                       durationSeconds: 2_700, distanceMeters: nil, scored: nil),
            try record(id: UUID(), on: "2026-01-10", scored: 64, withMetrics: true),
        ]

        let first = try context(alongside: others, subjectID: subjectID).factSheet()
        let reversed = try context(alongside: others.reversed(), subjectID: subjectID).factSheet()

        XCTAssertEqual(first, reversed)
        XCTAssertEqual(first, try context(alongside: others, subjectID: subjectID).factSheet())
    }
}
