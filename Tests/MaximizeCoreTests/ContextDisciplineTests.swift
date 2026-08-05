import Foundation
import XCTest
@testable import MaximizeCore

/// LIFTING-SPEC §10.1, pinned: a lift is not described in running vocabulary, the
/// prescription a workout is shown is its *own* slot's, and a run's prompt did not move
/// a byte while that was arranged.
///
/// The last of those three is the one worth the most. Every change in this ticket is on
/// the code path that produces the scoring prompt for every ingested workout, and D8
/// stores whatever verdict comes back forever. A regression here would not look like a
/// failure; it would look like slightly different scores.
final class ContextDisciplineTests: XCTestCase {
    // MARK: - Fixtures

    /// A Tuesday that prescribes both: the fixture template's 8 km easy run, plus a
    /// 45-minute upper-body lift. The day §5 of the spec is about, and the only shape
    /// that can tell "picked the right slot" apart from "picked the only slot".
    private func planPrescribingBothOnTuesday() throws -> Plan {
        try Plan(
            version: PlanVersion(1),
            effectiveFrom: Fixture.day(2026, 1, 1),
            weeklyTemplate: Fixture.weeklyTemplate(lift: [
                .tuesday: ScheduledSession(
                    kind: .lift,
                    durationSeconds: 2_700,
                    note: "upper body",
                    muscleGroups: [.shoulders, .chest]
                ),
            ]),
            longRunArc: LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(
                statements: ["Run a sub-4:00 marathon"],
                targetDay: Fixture.day(2026, 4, 20)
            )
        )
    }

    private func liftWorkout() throws -> Workout {
        try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            durationSeconds: 2_700,
            distanceMeters: nil,
            hasRoute: false
        )
    }

    /// What `DerivedMetricsCalculator` stores for a lift after MAX-130: the heart-rate
    /// figures and the zone distribution, and nothing anchored to a running model.
    private func liftMetrics() throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 118,
            maximumHeartRateBPM: 152,
            zoneSplits: ZoneSplits(splits: [
                ZoneSplits.Split(zone: .one, seconds: 1_500),
                ZoneSplits.Split(zone: .two, seconds: 1_200),
            ]),
            planVersion: PlanVersion(1)
        )
    }

    private func build(
        workout: Workout,
        metrics: DerivedMetrics,
        classification: WorkoutClassification = .other,
        plan: Plan? = nil,
        audience: WorkoutContext.Audience = .scoring,
        heartRateSeries: HeartRateSeries? = nil
    ) throws -> WorkoutContext {
        let governing = try plan ?? planPrescribingBothOnTuesday()
        return try WorkoutContextBuilder.build(
            workout: workout,
            // 2026-01-06 is the Tuesday the fixture template prescribes both on.
            on: Fixture.day(2026, 1, 6),
            metrics: metrics,
            classification: classification,
            planCalendar: PlanCalendar([governing]),
            audience: audience,
            heartRateSeries: heartRateSeries
        )
    }

    /// The vocabulary a lift's prompt may not contain, in any casing and in any position
    /// — not merely as a heading. Substrings rather than whole words on purpose: the
    /// failure this guards against is a *line* being reintroduced, and "Grade-adjusted
    /// pace", "Average cadence", "Time above cap" and "## Pace by kilometre" all fall to
    /// one of these.
    private static let runningVocabulary = ["pace", "cadence", " cap", "split", " km", "spm"]

    // MARK: - §10.1: a lift is not described as a run

    func testALiftsFactSheetCarriesNoRunningVocabulary() throws {
        let sheet = try build(workout: liftWorkout(), metrics: liftMetrics()).factSheet()

        for token in Self.runningVocabulary {
            XCTAssertFalse(
                sheet.lowercased().contains(token),
                "a lift's fact sheet must not contain \"\(token)\":\n\(sheet)"
            )
        }
    }

    /// The same requirement stated as the lines §10.1 names, so a failure says which one
    /// came back rather than only that some forbidden word did.
    func testALiftsFactSheetOmitsEveryRunOnlyHeading() throws {
        let sheet = try build(workout: liftWorkout(), metrics: liftMetrics()).factSheet()

        for label in [
            "Setting:", "Distance:", "Heart-rate cap:", "Cadence target:",
            "Time above cap:", "Heart-rate drift:", "Average cadence:",
            "Grade-adjusted pace:", "## Pace by",
        ] {
            XCTAssertFalse(sheet.contains(label), "\(label) must not appear on a lift:\n\(sheet)")
        }
        // Omitted, never rendered as an empty placeholder — the failure mode §10.1 calls
        // out by name ("not as '—', but absent").
        XCTAssertFalse(sheet.contains(": —"), "a field that does not apply is omitted, not dashed")
    }

    /// The other half of §10.1: what a lift's sheet *does* carry. An omission test alone
    /// would pass on an empty string.
    func testALiftsFactSheetCarriesWhatDescribesALift() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: (0..<40).map { index in
                try HeartRateSample(offsetSeconds: Double(index) * 60, beatsPerMinute: 110 + Double(index))
            }
        )
        let sheet = try build(
            workout: liftWorkout(),
            metrics: liftMetrics(),
            heartRateSeries: series
        ).factSheet()

        XCTAssertTrue(sheet.contains("Date: 2026-01-06 (Tuesday)"), sheet)
        XCTAssertTrue(sheet.contains("Type: traditionalStrengthTraining"), sheet)
        XCTAssertTrue(sheet.contains("Duration: 45m 0s"), sheet)
        XCTAssertTrue(sheet.contains("Active energy: 700 kcal"), sheet)
        XCTAssertTrue(sheet.contains("Plan version: v1"), sheet)
        XCTAssertTrue(sheet.contains("Goals: Run a sub-4:00 marathon"), sheet)
        XCTAssertTrue(sheet.contains("Average heart rate: 118 bpm"), sheet)
        XCTAssertTrue(sheet.contains("Maximum heart rate: 152 bpm"), sheet)
        XCTAssertTrue(sheet.contains("Time in zones: zone 1 25m 0s, zone 2 20m 0s"), sheet)
        XCTAssertTrue(sheet.contains("## Heart-rate shape"), sheet)
    }

    /// The absence rule inverted rather than dropped. Nine disclaiming headings would be
    /// prompt tokens spent on nothing; saying nothing at all would leave Claude to reason
    /// from a gap, which is the hazard the rule exists for.
    func testALiftsFactSheetSaysWhyItIsShort() throws {
        let sheet = try build(workout: liftWorkout(), metrics: liftMetrics()).factSheet()

        XCTAssertTrue(sheet.contains("This was a lift, not a run."), sheet)
        XCTAssertTrue(sheet.contains("read nothing into their absence"), sheet)
    }

    // MARK: - §10.1: the lift session prescribed for that day, not the run one

    func testTheLiftIsShownTheLiftSlotOnADayThatPrescribesBoth() throws {
        let context = try build(workout: liftWorkout(), metrics: liftMetrics())

        XCTAssertEqual(context.discipline, .lift)
        XCTAssertEqual(context.scheduledSession?.kind, .lift)
        XCTAssertEqual(context.scheduledSession?.durationSeconds, 2_700)
        XCTAssertEqual(context.scheduledSession?.muscleGroups, Set<MuscleGroup>([.chest, .shoulders]))
        // The run slot is still on the day and is still reachable — this ticket selects
        // between them, it does not hide one.
        XCTAssertEqual(context.planDay?.scheduledSession.kind, .easy)

        let sheet = context.factSheet()
        XCTAssertTrue(
            sheet.contains(
                "Scheduled for this day: lift, 45m 0s, muscle groups: chest, shoulders (upper body)"
            ),
            sheet
        )
        XCTAssertFalse(sheet.contains("Scheduled for this day: easy"), "the run slot is not the lift's ask")
        XCTAssertFalse(sheet.contains("8.0"), "nor is the run slot's prescribed distance")
    }

    /// The same day from the other side. If the discipline branch were wired backwards
    /// this is the test that would say so; the one above would pass on a builder that
    /// always chose the lift slot.
    func testTheRunOnTheSameDayIsStillShownTheRunSlot() throws {
        let context = try build(
            workout: Fixture.workout(),
            metrics: try runMetrics(),
            classification: .easy
        )

        XCTAssertEqual(context.discipline, .run)
        XCTAssertEqual(context.scheduledSession?.kind, .easy)
        XCTAssertEqual(context.scheduledSession?.distanceMeters, 8_000)
        XCTAssertTrue(context.factSheet().contains("Scheduled for this day: easy, 8.0 km"))
    }

    /// The muscle groups are a `Set`, and a set has no order. Two builds of one context
    /// that spelled them differently would be D3's determinism failing on a word.
    func testTheMuscleGroupsRenderInOneCanonicalOrder() throws {
        let context = try build(workout: liftWorkout(), metrics: liftMetrics())
        XCTAssertEqual(context.factSheet(), context.factSheet())
        XCTAssertTrue(context.factSheet().contains("muscle groups: chest, shoulders"))
        XCTAssertFalse(context.factSheet().contains("shoulders, chest"))
    }

    /// A lift the plan did not ask for is a real, interesting state — "you lifted on a
    /// day with no lift prescribed" is exactly what a scorer needs to know — so the slot
    /// is rendered even when it is rest, rather than dropped as an absent field.
    func testALiftOnADayWithNoLiftPrescribedIsToldSo() throws {
        let sheet = try build(
            workout: liftWorkout(),
            metrics: liftMetrics(),
            plan: try Fixture.plan()
        ).factSheet()

        XCTAssertTrue(sheet.contains("Scheduled for this day: rest"), sheet)
    }

    // MARK: - Records written before MAX-130 gated the calculator

    /// The guard that is not a formality. A lift ingested before MAX-130 has a cadence, a
    /// grade-adjusted pace and a split series on file — all computed from real samples,
    /// all describing nothing (§1.2). None of them may reach a prompt.
    func testALiftsPreMAX130MetricsDoNotReachThePrompt() throws {
        let fabricated = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 118,
            maximumHeartRateBPM: 152,
            timeAboveCapSeconds: 900,
            averageCadenceStepsPerMinute: 41,
            gradeAdjustedPaceSecondsPerKilometer: 640,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 2_700)]),
            distanceSplits: DistanceSplits(series: [
                DistanceSplitSeries(unit: .kilometers, splits: [
                    DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 640, isComplete: true),
                ]),
            ]),
            planVersion: PlanVersion(1)
        )

        // Chat is the wider payload, so it is the one worth asserting against.
        let context = try build(
            workout: liftWorkout(),
            metrics: fabricated,
            audience: .chat
        )

        // Selected out by the builder, so the answer to "did this leave the device" is
        // given once, by the single assembler D3 names (CLAUDE.md).
        XCTAssertNil(context.paceBreakdown)

        let sheet = context.factSheet()
        for token in Self.runningVocabulary {
            XCTAssertFalse(sheet.lowercased().contains(token), "\(token) reached a lift's prompt:\n\(sheet)")
        }
        XCTAssertFalse(sheet.contains("41"), "a fabricated cadence must not be rendered")
        XCTAssertFalse(sheet.contains("10:40"), "nor a fabricated pace")
    }

    /// A hike sits in the run slot by A17 and is not a lift. This ticket branches on the
    /// discipline, so a hike's prompt must be exactly what it was — including the split
    /// series it really does have on file, which a narrower `isRun` gate would have
    /// replaced with a sentence claiming the record has none.
    func testARunSlotWorkoutThatIsNotARunIsUnaffected() throws {
        let hike = try Fixture.workout(activityType: .hiking, distanceMeters: 12_000)
        let context = try build(
            workout: hike,
            metrics: try runMetrics(distanceSplits: DistanceSplits(series: [
                DistanceSplitSeries(unit: .kilometers, splits: [
                    DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 600, isComplete: true),
                ]),
            ])),
            audience: .chat
        )

        XCTAssertEqual(context.discipline, .run)
        XCTAssertNotNil(context.paceBreakdown)

        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("Average cadence:"), sheet)
        XCTAssertTrue(sheet.contains("## Pace by kilometre"), sheet)
        XCTAssertFalse(sheet.contains("This was a lift"), sheet)
    }

    // MARK: - The regression guard

    /// **A run's fact sheet, byte for byte.** Written out in full rather than probed with
    /// `contains`, because the property this ticket has to preserve is not "the lines are
    /// still there" — it is that the scoring prompt is character-identical, in the same
    /// order, with the same wording and the same rounding. Anything less would let a
    /// stray blank line or a reordered field through, and the effect of that is not a
    /// test failure, it is subtly different scores that D8 then stores forever.
    ///
    /// If a later ticket deliberately changes this text, it changes the literal here and
    /// says in its PR that every future scoring call's input moved.
    func testARunsFactSheetIsUnchanged() throws {
        let context = try WorkoutContextBuilder.build(
            workout: Fixture.workout(),
            on: try Fixture.day(2026, 1, 6),
            metrics: try runMetrics(),
            classification: .easy,
            planCalendar: PlanCalendar([Fixture.plan()])
        )

        XCTAssertEqual(context.factSheet(), """
        ## Workout
        Date: 2026-01-06 (Tuesday)
        Type: running
        Setting: outdoor (GPS route recorded)
        Duration: 1h 0m 0s
        Distance: 10.00 km
        Active energy: 700 kcal
        Classified as: easy

        ## The plan
        Plan version: v1
        Heart-rate cap: 150 bpm
        Cadence target: 165–170 spm
        Scheduled for this day: easy, 8.0 km
        Goals: Run a sub-4:00 marathon
        Target event: 2026-04-20

        ## Measured
        Average heart rate: 142 bpm
        Maximum heart rate: 161 bpm
        Time above cap: 4m 10s
        Heart-rate drift: +3.2%
        Average cadence: 167 spm (within the target band)
        Grade-adjusted pace: 5:08 per km
        Time in zones: zone 2 50m 0s, zone 3 15m 0s
        """)
    }

    /// The same metrics `WorkoutContextTests` builds its run cases from, restated here so
    /// this file's expected text does not silently depend on another file's fixture.
    private func runMetrics(distanceSplits: DistanceSplits? = nil) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            averageCadenceStepsPerMinute: 167,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplits: ZoneSplits(splits: [
                ZoneSplits.Split(zone: .two, seconds: 3_000),
                ZoneSplits.Split(zone: .three, seconds: 900),
            ]),
            distanceSplits: distanceSplits,
            planVersion: PlanVersion(1)
        )
    }
}
