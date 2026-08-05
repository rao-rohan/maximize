import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-095 — the one entry point over a closed subject set (CHAT-FIRST-SPEC.md §3.2/§3.3,
/// PRD-AMENDMENTS.md A12, LIFTING-SPEC.md §10.2).
///
/// Everything here is reasoned against `Fixture.plan()`: effective from **Thursday
/// 2026-01-01**, template Monday rest / Tuesday easy 8 km / Wednesday hard / Thursday easy
/// 8 km / Friday rest / Saturday easy 6 km / Sunday long 18 km, cap 150 bpm, cadence
/// 165–170, effective threshold 70, marginal 45. Arc weeks are Monday-anchored from
/// **Monday 2025-12-29**, so **2026-01-05...11 is arc week 2** — the window most of these
/// tests use, and week 2's prescribed long run is 18 km.
///
/// §3.6(a)'s agreement property has its own file, `TrainingContextAgreementTests`.
final class ContextBuilderTests: XCTestCase {

    // MARK: - Fixtures

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

    private func metrics(
        workoutID: UUID,
        averageHeartRateBPM: Double? = 142,
        driftFraction: Double? = 0.032,
        distanceSplits: DistanceSplits? = nil
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: averageHeartRateBPM.map { $0 + 18 },
            timeAboveCapSeconds: averageHeartRateBPM == nil ? nil : 250,
            heartRateDriftFraction: driftFraction,
            distanceSplits: distanceSplits,
            planVersion: PlanVersion(1)
        )
    }

    private func ledger(points: Int, workoutID: UUID, correctedTo: Int? = nil) throws -> ScoreLedger {
        let base = try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: workoutID))
        guard let correctedTo else { return base }
        return try base.annotated(with: try Fixture.annotation(points: correctedTo, workoutID: workoutID))
    }

    private func contextInputs(
        _ records: [ContextInputs.WorkoutRecord],
        planCalendar: PlanCalendar?,
        today: String = ContextBuilderTests.today
    ) throws -> ContextInputs {
        try ContextInputs(
            timeZone: .gmt,
            today: try day(today),
            planCalendar: planCalendar,
            restDayBudget: .standard,
            records: records
        )
    }

    private func trainingContext(
        from: String = "2026-01-05",
        through: String = "2026-01-11",
        records: [ContextInputs.WorkoutRecord],
        planCalendar: PlanCalendar?,
        today: String = ContextBuilderTests.today
    ) throws -> TrainingContext {
        let scope = try TrainingScope(from: try day(from), through: try day(through))
        let context = try ContextBuilder.build(
            for: .training(scope),
            from: try contextInputs(records, planCalendar: planCalendar, today: today)
        )
        switch context {
        case let .training(training): return training
        case .workout: throw DomainError.inconsistent(reason: "expected a training context")
        }
    }

    // MARK: - The workout subject is delegated, not reimplemented

    /// A12 rule 1: `WorkoutContextBuilder` is unchanged and is called *by* the entry point,
    /// so the scorer and a workout thread still receive byte-identical context. This is the
    /// assertion that keeps that sentence true — if this entry point ever starts adding,
    /// trimming or re-wording anything, the two strings stop matching.
    func testWorkoutSubjectRendersExactlyWhatWorkoutContextBuilderProduces() throws {
        let id = UUID()
        let run = try workout(id: id, on: "2026-01-06")
        let record = try ContextInputs.WorkoutRecord(
            workout: run,
            metrics: try metrics(workoutID: id),
            ledger: try ledger(points: 82, workoutID: id)
        )

        let built = try ContextBuilder.build(
            for: .workout(id),
            from: try contextInputs([record], planCalendar: try calendar())
        )

        let directly = try WorkoutContextBuilder.build(
            workout: run,
            on: try day("2026-01-06"),
            metrics: try metrics(workoutID: id),
            classification: .easy,
            planCalendar: try calendar(),
            audience: .chat,
            heartRateSeries: nil,
            existingScore: try Fixture.score(points: 82, workoutID: id)
        )

        XCTAssertEqual(built.subjectKind, .workout)
        XCTAssertEqual(built.factSheet(), directly.factSheet())
    }

    /// The chat audience is this entry point's, not the caller's: everything it builds is
    /// for a conversation somebody opened and typed into. The scorer reaches
    /// `WorkoutContextBuilder` without passing through here and keeps the smaller payload.
    func testWorkoutSubjectAlwaysBuildsForChatAndNeverForScoring() throws {
        let id = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: try metrics(workoutID: id),
            ledger: try ledger(points: 82, workoutID: id)
        )

        let built = try ContextBuilder.build(
            for: .workout(id),
            from: try contextInputs([record], planCalendar: try calendar())
        )
        guard case let .workout(context) = built else { return XCTFail("expected a workout context") }

        XCTAssertEqual(context.audience, .chat)
        XCTAssertNotNil(context.existingScore)
    }

    func testWorkoutSubjectThrowsWhenNoRecordWasSupplied() throws {
        let empty = try contextInputs([], planCalendar: try calendar())
        XCTAssertThrowsError(try ContextBuilder.build(for: .workout(UUID()), from: empty))
    }

    /// An unscored workout has no stored classification, and re-deriving one here would be
    /// a second classifier free to disagree with the scorer's (D2).
    func testWorkoutSubjectThrowsWhenTheWorkoutHasNotBeenScored() throws {
        let id = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: try metrics(workoutID: id),
            ledger: nil
        )
        let unscored = try contextInputs([record], planCalendar: try calendar())
        XCTAssertThrowsError(try ContextBuilder.build(for: .workout(id), from: unscored))
    }

    func testWorkoutSubjectThrowsWhenTheWorkoutHasNoDerivedMetrics() throws {
        let id = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: nil,
            ledger: try ledger(points: 82, workoutID: id)
        )
        let unenriched = try contextInputs([record], planCalendar: try calendar())
        XCTAssertThrowsError(try ContextBuilder.build(for: .workout(id), from: unenriched))
    }

    /// The record cannot be assembled mismatched, so a mismatch cannot reach a prompt.
    func testARecordRejectsPiecesBelongingToADifferentWorkout() throws {
        let run = try workout(id: UUID(), on: "2026-01-06")
        let strangersMetrics = try metrics(workoutID: UUID())
        let strangersLedger = try ledger(points: 80, workoutID: UUID())

        XCTAssertThrowsError(try ContextInputs.WorkoutRecord(workout: run, metrics: strangersMetrics))
        XCTAssertThrowsError(try ContextInputs.WorkoutRecord(workout: run, ledger: strangersLedger))
    }

    func testDuplicateRecordsForOneWorkoutAreRejected() throws {
        let record = try ContextInputs.WorkoutRecord(workout: try workout(id: UUID(), on: "2026-01-06"))
        XCTAssertThrowsError(try contextInputs([record, record], planCalendar: try calendar()))
    }

    // MARK: - One line per session, not per day (LIFTING-SPEC §10.2)

    /// A Tuesday holding a run and a lift is two obligations (A19), and a roll-up that
    /// merged them would make the second one invisible in the prompt that exists to answer
    /// "did I do what the plan asked".
    func testADayHoldingTwoSessionsProducesTwoLines() throws {
        let run = UUID()
        let lift = UUID()
        let records = [
            try ContextInputs.WorkoutRecord(
                workout: try workout(id: run, on: "2026-01-06", atHour: 7),
                metrics: try metrics(workoutID: run),
                ledger: try ledger(points: 80, workoutID: run)
            ),
            try ContextInputs.WorkoutRecord(
                workout: try workout(
                    id: lift,
                    on: "2026-01-06",
                    atHour: 18,
                    activityType: .traditionalStrengthTraining,
                    durationSeconds: 2_700,
                    distanceMeters: nil
                ),
                metrics: try metrics(workoutID: lift, averageHeartRateBPM: 118, driftFraction: nil)
            ),
        ]

        let context = try trainingContext(records: records, planCalendar: try calendar())
        let tuesday = try day("2026-01-06")

        XCTAssertEqual(context.sessionCountInScope, 2)
        XCTAssertEqual(context.sessions.map(\.day), [tuesday, tuesday])
        // Chronological within the day: the morning run first.
        XCTAssertEqual(context.sessions.map(\.workoutID), [run, lift])

        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("Running, classified easy"), sheet)
        XCTAssertTrue(sheet.contains("Strength training, not yet classified"), sheet)
    }

    func testSessionsAreOrderedChronologicallyRegardlessOfInputOrder() throws {
        let ids = (0..<3).map { _ in UUID() }
        let days = ["2026-01-11", "2026-01-06", "2026-01-08"]
        let records = try zip(ids, days).map { id, dayText in
            try ContextInputs.WorkoutRecord(
                workout: try workout(id: id, on: dayText),
                metrics: try metrics(workoutID: id),
                ledger: try ledger(points: 75, workoutID: id)
            )
        }

        let context = try trainingContext(records: records, planCalendar: try calendar())
        let expected = [try day("2026-01-06"), try day("2026-01-08"), try day("2026-01-11")]

        XCTAssertEqual(context.sessions.map(\.day), expected)
    }

    func testSessionsOutsideTheWindowAreNotListed() throws {
        let inside = UUID()
        let outside = UUID()
        let records = [
            try ContextInputs.WorkoutRecord(
                workout: try workout(id: inside, on: "2026-01-06"),
                metrics: try metrics(workoutID: inside),
                ledger: try ledger(points: 80, workoutID: inside)
            ),
            // Inside the Monday-first weeks C1 obliges the caller to supply, outside the
            // window the roll-up describes.
            try ContextInputs.WorkoutRecord(
                workout: try workout(id: outside, on: "2026-01-13"),
                metrics: try metrics(workoutID: outside),
                ledger: try ledger(points: 80, workoutID: outside)
            ),
        ]

        let context = try trainingContext(records: records, planCalendar: try calendar())

        XCTAssertEqual(context.sessionCountInScope, 1)
        XCTAssertEqual(context.sessions.map(\.workoutID), [inside])
    }

    // MARK: - Absence is first-class (MAX-111, A18)

    /// MAX-111 leaves every non-run unscored **by design**, permanently. A line for one
    /// must read as a verdict that was never going to exist, not as a missing value.
    func testAnUnscoredSessionReadsAsNoVerdict() throws {
        let unscoredRun = UUID()
        let lift = UUID()
        let records = [
            try ContextInputs.WorkoutRecord(
                workout: try workout(id: unscoredRun, on: "2026-01-06"),
                metrics: try metrics(workoutID: unscoredRun)
            ),
            try ContextInputs.WorkoutRecord(
                workout: try workout(
                    id: lift,
                    on: "2026-01-08",
                    activityType: .traditionalStrengthTraining,
                    distanceMeters: nil
                ),
                metrics: try metrics(workoutID: lift, averageHeartRateBPM: 118, driftFraction: nil)
            ),
        ]

        let sheet = try trainingContext(records: records, planCalendar: try calendar()).factSheet()

        XCTAssertTrue(sheet.contains("Score: no verdict — this run has not been scored"), sheet)
        XCTAssertTrue(
            sheet.contains("Score: no verdict — the plan's rubric scores runs, so this session is not scored"),
            sheet
        )
        // Never a bare gap, and never a zero.
        XCTAssertFalse(sheet.contains("Score: 0/100"), sheet)
    }

    /// A18 at the scale of a line: a field the record does not carry is omitted, not
    /// rendered as a heading whose only content is that it does not apply.
    func testAFieldTheRecordDoesNotCarryIsOmittedRatherThanNilRendered() throws {
        let lift = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(
                id: lift,
                on: "2026-01-06",
                activityType: .traditionalStrengthTraining,
                durationSeconds: 2_700,
                distanceMeters: nil
            ),
            metrics: try metrics(workoutID: lift, averageHeartRateBPM: nil, driftFraction: nil)
        )

        let context = try trainingContext(records: [record], planCalendar: try calendar())
        let sheet = context.factSheet()
        let line = String(
            try XCTUnwrap(sheet.split(separator: "\n").first { $0.contains("Strength training") })
        )

        XCTAssertFalse(line.contains("Distance:"), line)
        XCTAssertFalse(line.contains("Average heart rate:"), line)
        XCTAssertFalse(line.contains("Heart-rate drift:"), line)
        XCTAssertTrue(line.contains("Duration: 45m 0s"), line)
        // Stated once for the whole roll-up rather than forty times.
        XCTAssertTrue(sheet.contains("A field missing from a line was not recorded for that session."), sheet)
    }

    func testAnEmptyWindowSaysSoAndStillCarriesThePlanAndTheTallies() throws {
        let context = try trainingContext(records: [], planCalendar: try calendar())

        XCTAssertEqual(context.sessionCountInScope, 0)
        XCTAssertTrue(context.sessions.isEmpty)
        XCTAssertFalse(context.sessionsWereWithheldByTheCap)

        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("No workout was recorded in this window."), sheet)
        XCTAssertTrue(sheet.contains("Plan version: v1"), sheet)
        XCTAssertTrue(sheet.contains("Days with at least one workout: 0"), sheet)
        XCTAssertTrue(sheet.contains("Average score: nothing in this window has been scored yet"), sheet)
    }

    func testNoPlanAuthoredIsStatedRatherThanLeftBlank() throws {
        let context = try trainingContext(records: [], planCalendar: nil)

        XCTAssertNil(context.plan)
        XCTAssertEqual(context.planCoverage, .wholeWindow)
        XCTAssertTrue(
            context.factSheet().contains("No plan version was in effect at the end of this window"),
            context.factSheet()
        )
    }

    // MARK: - Bounded twice over (§3.3)

    func testExactlyTheCapIsStillListed() throws {
        let context = try windowOf(sessionCount: TrainingContext.maximumRenderedSessions)

        XCTAssertEqual(context.sessionCountInScope, TrainingContext.maximumRenderedSessions)
        XCTAssertEqual(context.sessions.count, TrainingContext.maximumRenderedSessions)
        XCTAssertFalse(context.sessionsWereWithheldByTheCap)
    }

    /// Beyond the cap the context states the count and lists none — exactly what
    /// `WorkoutFactSheet` does for an implausible split series, and for the same reason:
    /// health data leaving the device must never be sized by a number nothing has
    /// validated.
    func testBeyondTheCapTheCountIsStatedAndNoSessionIsListed() throws {
        let count = TrainingContext.maximumRenderedSessions + 1
        let context = try windowOf(sessionCount: count)

        XCTAssertEqual(context.sessionCountInScope, count)
        XCTAssertTrue(context.sessions.isEmpty)
        XCTAssertTrue(context.sessionsWereWithheldByTheCap)

        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("\(count) sessions are on file for this window"), sheet)
        // The bound is on what is *listed*, not on what is measured: the plan and the
        // tallies still describe the whole window.
        XCTAssertTrue(sheet.contains("Plan version: v1"), sheet)
        XCTAssertTrue(sheet.contains("Days with at least one workout: \(count)"), sheet)
    }

    /// One workout a day on consecutive days from Monday 2026-01-05, in a window that
    /// starts and ends on those same days.
    private func windowOf(sessionCount: Int) throws -> TrainingContext {
        let start = try day("2026-01-05")
        var records: [ContextInputs.WorkoutRecord] = []
        for offset in 0..<sessionCount {
            let id = UUID()
            let dayText = try start.adding(days: offset).description
            records.append(
                try ContextInputs.WorkoutRecord(
                    workout: try workout(id: id, on: dayText),
                    metrics: try metrics(workoutID: id),
                    ledger: try ledger(points: 80, workoutID: id)
                )
            )
        }
        return try trainingContext(
            from: start.description,
            through: try start.adding(days: sessionCount - 1).description,
            records: records,
            planCalendar: try calendar(),
            today: "2027-01-01"
        )
    }

    // MARK: - What a training context must never carry (§3.3's exclusion list)

    /// The privacy boundary, asserted rather than believed. Everything §3.3 excludes is
    /// reachable from the records this builder is handed, so the only thing stopping it
    /// reaching a prompt is this type — and a test.
    func testTheRollUpCarriesNoSplitsNoCurveNoRouteAndNoRationale() throws {
        let id = UUID()
        let splits = try DistanceSplits(series: [
            DistanceSplitSeries(unit: .kilometers, splits: [
                try DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true),
                try DistanceSplit(ordinal: 2, distanceMeters: 1_000, elapsedSeconds: 306, isComplete: true),
            ]),
        ])
        let samples = try (0..<40).map { index in
            try HeartRateSample(offsetSeconds: Double(index) * 30, beatsPerMinute: 130 + Double(index) * 0.5)
        }
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: try metrics(workoutID: id, distanceSplits: splits),
            ledger: try ledger(points: 82, workoutID: id),
            heartRateSeries: try HeartRateSeries(workoutID: id, samples: samples)
        )

        let sheet = try trainingContext(records: [record], planCalendar: try calendar()).factSheet()

        // No splits: MAX-068 calls a split series the finest-grained record of one
        // person's movement in the whole prompt, and twelve of them is not marginal.
        XCTAssertFalse(sheet.contains("Pace by"), sheet)
        XCTAssertFalse(sheet.contains("5:00"), sheet)
        // No heart-rate shape: 120 numbers answering a question nobody asked.
        XCTAssertFalse(sheet.contains("Heart-rate shape"), sheet)
        // No stored rationale: it invites the model to argue with a stored verdict (D8).
        XCTAssertFalse(sheet.contains("Held the cap with minimal drift"), sheet)
        XCTAssertFalse(sheet.contains("Rationale"), sheet)
        // Identifiers and provenance are ours.
        XCTAssertFalse(sheet.contains(id.uuidString), sheet)
        // What it does carry, so the absences above are not passing for the wrong reason.
        XCTAssertTrue(sheet.contains("Heart-rate drift: +3.2%"), sheet)
        XCTAssertTrue(sheet.contains("Score: 82/100 (effective)"), sheet)
    }

    /// The correction is carried and the automatic score is not overwritten (D8) — a line
    /// quoting only the auto score beside an average built from corrections would be the
    /// disagreement §3.6 exists to prevent.
    func testACorrectedScoreShowsBothNumbersAndBandsOnlyTheAutomaticOne() throws {
        let id = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: try metrics(workoutID: id),
            ledger: try ledger(points: 62, workoutID: id, correctedTo: 85)
        )

        let sheet = try trainingContext(records: [record], planCalendar: try calendar()).factSheet()

        XCTAssertTrue(sheet.contains("Score: 62/100 (marginal), corrected by hand to 85/100"), sheet)
    }

    // MARK: - The plan block (§3.3 item 1)

    func testThePlanBlockCarriesTheTemplateBothThresholdsAndTheArcWeek() throws {
        let sheet = try trainingContext(records: [], planCalendar: try calendar()).factSheet()

        XCTAssertTrue(sheet.contains("Heart-rate cap: 150 bpm"), sheet)
        XCTAssertTrue(sheet.contains("Cadence target: 165–170 spm"), sheet)
        XCTAssertTrue(sheet.contains("Effective-day threshold: 70 / 100"), sheet)
        XCTAssertTrue(sheet.contains("Marginal threshold: 45 / 100"), sheet)
        XCTAssertTrue(sheet.contains("Goals: Run a sub-4:00 marathon"), sheet)
        XCTAssertTrue(sheet.contains("Target event: 2026-04-20"), sheet)

        // The whole template, every weekday, because rest is an explicit ask.
        XCTAssertTrue(sheet.contains("Monday: rest"), sheet)
        XCTAssertTrue(sheet.contains("Tuesday: easy, 8.0 km"), sheet)
        XCTAssertTrue(sheet.contains("Wednesday: hard, (6 × 800m)"), sheet)
        XCTAssertTrue(sheet.contains("Sunday: long, 18.0 km"), sheet)

        // 2026-01-05...11 is arc week 2; week 2's prescribed long run is 18 km.
        XCTAssertTrue(
            sheet.contains("Training week at the end of this window: 2026-01-05 to 2026-01-11, "
                + "arc week 2, long run prescribed: 18.00 km."),
            sheet
        )
    }

    /// The arc week is read off the tallies, which got it from
    /// `PlanCalendar.arcWeek(for:under:)` — the same resolution the plan screen and the
    /// scorer use (§3.6(a)).
    func testTheArcWeekIsTheOneTheTalliesResolved() throws {
        let context = try trainingContext(records: [], planCalendar: try calendar())

        XCTAssertEqual(context.currentArcWeekIndex, context.tallies.currentWeek.arcWeekIndex)
        XCTAssertEqual(context.currentArcWeekIndex, 2)
        XCTAssertEqual(context.currentArcWeekDistanceMeters, 18_000)
    }

    /// The arc is a finite progression; running past its end is expected and means the
    /// plan wants a new version (D1), not that something is broken.
    func testAWindowPastTheEndOfTheArcSaysTheArcHasNoEntry() throws {
        let context = try trainingContext(
            from: "2026-03-02",
            through: "2026-03-08",
            records: [],
            planCalendar: try calendar()
        )

        XCTAssertNil(context.currentArcWeekDistanceMeters)
        XCTAssertTrue(
            context.factSheet().contains("The arc has no entry for that week, so it prescribes no "
                + "long-run distance."),
            context.factSheet()
        )
    }

    // MARK: - How much of the window the plan governed

    func testAPlanTakingEffectInsideTheWindowIsStated() throws {
        // `Fixture.plan()` is effective from Thursday 2026-01-01; this window opens before it.
        let context = try trainingContext(
            from: "2025-12-29",
            through: "2026-01-04",
            records: [],
            planCalendar: try calendar()
        )

        XCTAssertEqual(context.planCoverage, .beganWithinTheWindow)
        XCTAssertTrue(
            context.factSheet().contains("Version v1 took effect on 2026-01-01, inside this window."),
            context.factSheet()
        )
    }

    func testARevisionInsideTheWindowNamesBothVersions() throws {
        let revised = try Plan(
            version: PlanVersion(2),
            effectiveFrom: try day("2026-01-08"),
            weeklyTemplate: try Fixture.weeklyTemplate(),
            longRunArc: try LongRunArc(weeks: [try LongRunArc.Week(index: 1, distanceMeters: 20_000)]),
            heartRateCapBPM: 148,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 168, highStepsPerMinute: 174),
            rubric: try Fixture.rubric(),
            goals: PlanGoals()
        )

        let context = try trainingContext(
            records: [],
            planCalendar: try calendar([try Fixture.plan(), revised])
        )

        XCTAssertEqual(context.planCoverage, .revisedWithinTheWindow(earlier: PlanVersion(1)))
        XCTAssertEqual(context.plan?.version, PlanVersion(2))
        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("Plan version v1 governed the opening days of this window"), sheet)
        XCTAssertTrue(sheet.contains("version v2 took effect on 2026-01-08"), sheet)
        // The settings printed are the ones in effect at the window's end.
        XCTAssertTrue(sheet.contains("Heart-rate cap: 148 bpm"), sheet)
    }

    func testOneVersionAcrossTheWholeWindowSaysNothingExtra() throws {
        let context = try trainingContext(records: [], planCalendar: try calendar())

        XCTAssertEqual(context.planCoverage, .wholeWindow)
        XCTAssertFalse(context.factSheet().contains("took effect on"), context.factSheet())
    }

    // MARK: - The window itself (§3.3 item 4, §3.6(b))

    func testTheWindowIsStatedAndDescribedAsFrozen() throws {
        let sheet = try trainingContext(records: [], planCalendar: try calendar()).factSheet()

        XCTAssertTrue(sheet.contains("5 – 11 Jan 2026 — 2026-01-05 through 2026-01-11, inclusive."), sheet)
        XCTAssertTrue(sheet.contains("This window is frozen"), sheet)
        XCTAssertTrue(sheet.contains("Name the window whenever you quote a figure from it."), sheet)
    }

    /// Determinism (D3): the same stored window must render byte-identically every time,
    /// or "one set of stored numbers" quietly stops being true at the prompt boundary.
    func testTheSameWindowRendersIdenticallyTwice() throws {
        let id = UUID()
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: "2026-01-06"),
            metrics: try metrics(workoutID: id),
            ledger: try ledger(points: 82, workoutID: id)
        )

        let first = try trainingContext(records: [record], planCalendar: try calendar())
        let second = try trainingContext(records: [record], planCalendar: try calendar())

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.factSheet(), second.factSheet())
    }
}
