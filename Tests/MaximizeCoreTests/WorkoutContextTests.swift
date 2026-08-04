import Foundation
import XCTest
@testable import MaximizeCore

/// D3, pinned: one assembler, one rendering, and no way for the scorer and the chat to
/// end up believing different things about the same run.
final class WorkoutContextTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func planCalendar() throws -> PlanCalendar {
        try PlanCalendar([Fixture.plan()])
    }

    /// Metrics carrying the fixture plan's version, so the coherence check passes.
    private func metrics(
        workoutID: UUID = Fixture.workoutID,
        planVersion: Int = 1,
        averageHeartRateBPM: Double? = 142,
        maximumHeartRateBPM: Double? = 161,
        timeAboveCapSeconds: Double? = 250,
        heartRateDriftFraction: Double? = 0.032,
        averageCadenceStepsPerMinute: Double? = 167,
        gradeAdjustedPaceSecondsPerKilometer: Double? = 308
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: timeAboveCapSeconds,
            heartRateDriftFraction: heartRateDriftFraction,
            averageCadenceStepsPerMinute: averageCadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
            zoneSplits: ZoneSplits(splits: [
                ZoneSplits.Split(zone: .two, seconds: 3_000),
                ZoneSplits.Split(zone: .three, seconds: 900),
            ]),
            planVersion: PlanVersion(planVersion)
        )
    }

    private func build(
        metrics overrideMetrics: DerivedMetrics? = nil,
        classification: WorkoutClassification = .easy,
        on subject: String = "2026-01-06",
        heartRateSeries: HeartRateSeries? = nil,
        existingScore: Score? = nil
    ) throws -> WorkoutContext {
        try WorkoutContextBuilder.build(
            workout: Fixture.workout(),
            on: day(subject),
            metrics: overrideMetrics ?? metrics(),
            classification: classification,
            planCalendar: planCalendar(),
            heartRateSeries: heartRateSeries,
            existingScore: existingScore
        )
    }

    // MARK: - Assembly coherence

    /// The check that earns its keep. `DerivedMetrics` records the plan version its
    /// thresholds came from; if that is not the version governing the day, "time above
    /// cap" was measured against a cap the plan did not have. The number would look
    /// entirely ordinary and be wrong, and D8 would then store the resulting score
    /// forever.
    func testRejectsMetricsComputedAgainstADifferentPlanVersion() throws {
        assertThrows(
            .inconsistent,
            try build(metrics: metrics(planVersion: 2))
        )
    }

    func testRejectsPiecesBelongingToDifferentWorkouts() throws {
        assertThrows(
            .inconsistent,
            try build(metrics: metrics(workoutID: Fixture.otherWorkoutID))
        )
    }

    func testResolvesTheGoverningPlanAndTheDaysAsk() throws {
        // 2026-01-06 is a Tuesday; the fixture template's Tuesday is an 8 km easy run.
        let context = try build()
        XCTAssertEqual(context.plan?.version, try PlanVersion(1))
        XCTAssertEqual(context.planDay?.scheduledSession.kind, .easy)
        XCTAssertEqual(context.planDay?.scheduledSession.distanceMeters, 8_000)
    }

    /// A run predating every plan version is a real state, not an error.
    func testADayBeforeAnyPlanBuildsWithNoPlanRatherThanFailing() throws {
        let context = try build(on: "2025-12-15")
        XCTAssertNil(context.plan)
        XCTAssertNil(context.planDay)
        XCTAssertTrue(
            context.factSheet().contains("No plan version was in effect"),
            "the absence must be stated, not left as a missing section"
        )
    }

    // MARK: - The fact sheet states absence rather than omitting it

    /// The distinction MAX-012 was careful to model must survive into the prompt. A
    /// blank line invites Claude to treat the metric as unmeasured, or to reason about
    /// a number it was never given.
    func testAnInapplicableMetricSaysSoAndSaysWhy() throws {
        // A hard session: §9 makes drift near-meaningless, so MAX-012 withholds it.
        let sheet = try build(
            metrics: metrics(heartRateDriftFraction: nil),
            classification: .hard
        ).factSheet()

        XCTAssertTrue(sheet.contains("Heart-rate drift: not meaningful for a hard session"), sheet)
        XCTAssertFalse(sheet.contains("Heart-rate drift: 0"), "absent must never render as zero")
    }

    /// The same absence, for a different reason, must read differently — "no data" and
    /// "not meaningful here" are different facts about the run.
    func testMissingHeartRateDataIsDistinguishedFromAnInapplicableMetric() throws {
        let sheet = try build(
            metrics: metrics(
                averageHeartRateBPM: nil,
                maximumHeartRateBPM: nil,
                timeAboveCapSeconds: nil,
                heartRateDriftFraction: nil
            )
        ).factSheet()

        XCTAssertTrue(sheet.contains("Heart-rate drift: not applicable — this workout has no heart-rate data"), sheet)
        XCTAssertTrue(sheet.contains("Time above cap: not applicable"), sheet)
    }

    func testEveryMetricAppearsExactlyOnceEvenWhenAbsent() throws {
        let sheet = try build(
            metrics: metrics(
                averageHeartRateBPM: nil,
                maximumHeartRateBPM: nil,
                timeAboveCapSeconds: nil,
                heartRateDriftFraction: nil,
                averageCadenceStepsPerMinute: nil,
                gradeAdjustedPaceSecondsPerKilometer: nil
            )
        ).factSheet()

        for label in [
            "Average heart rate:", "Maximum heart rate:", "Time above cap:",
            "Heart-rate drift:", "Average cadence:", "Grade-adjusted pace:", "Time in zones:",
        ] {
            let occurrences = sheet.components(separatedBy: label).count - 1
            XCTAssertEqual(occurrences, 1, "\(label) should appear exactly once")
        }
    }

    // MARK: - What is deliberately withheld

    /// Route coordinates are the most re-identifying data in the record and the scorer
    /// does not need them — grade-adjusted pace already carries what terrain implies.
    /// This asserts the omission rather than trusting the renderer to keep omitting it.
    func testTheFactSheetCarriesNoIdentifiersOrCoordinates() throws {
        let sheet = try build().factSheet()
        XCTAssertFalse(sheet.contains(Fixture.workoutID.uuidString), "no workout identifier")
        XCTAssertFalse(sheet.lowercased().contains("latitude"))
        XCTAssertFalse(sheet.lowercased().contains("longitude"))
    }

    /// FR-2.1 seeds a chat thread with the score already assigned; a scorer must never
    /// see one, or it is being invited to agree rather than to judge — and the
    /// auto-versus-manual divergence PRD §2 measures depends on independence.
    func testTheAssignedScoreAppearsOnlyWhenItIsSupplied() throws {
        let withoutScore = try build().factSheet()
        XCTAssertFalse(withoutScore.contains("Score already assigned"))

        let withScore = try build(existingScore: Fixture.score(points: 88)).factSheet()
        XCTAssertTrue(withScore.contains("Score already assigned"))
        XCTAssertTrue(withScore.contains("88 / 100"))
    }

    // MARK: - Heart-rate shape

    func testTheShapeSummarisesTheCurveWithoutTheSamples() throws {
        // 100 samples climbing steadily from 130 to 160 over 3000 seconds.
        let samples = try (0..<100).map { index in
            try HeartRateSample(
                offsetSeconds: Double(index) * 30,
                beatsPerMinute: 130 + Double(index) * 0.3
            )
        }
        let series = try HeartRateSeries(workoutID: Fixture.workoutID, samples: samples)
        let context = try build(heartRateSeries: series)

        let shape = try XCTUnwrap(context.heartRateShape)
        XCTAssertEqual(shape.buckets.count, HeartRateShape.bucketCount)
        XCTAssertEqual(shape.buckets[0].startFraction, 0.0, accuracy: 0.0001)

        // A rising curve must render as rising — that is the whole point of keeping shape.
        let first = try XCTUnwrap(shape.buckets.first).averageBeatsPerMinute
        let last = try XCTUnwrap(shape.buckets.last).averageBeatsPerMinute
        XCTAssertLessThan(first, last)

        // And the raw sample count must not have leaked into the prompt.
        XCTAssertFalse(context.factSheet().contains("\(samples.count) samples"))
    }

    func testASingleSampleHasNoShapeBecauseItCoversNoTime() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: [HeartRateSample(offsetSeconds: 0, beatsPerMinute: 140)]
        )
        XCTAssertNil(try build(heartRateSeries: series).heartRateShape)
    }

    // MARK: - Determinism

    /// D3's actual requirement. If two builds of the same context can render differently,
    /// the scorer and the chat have started to disagree about the run and nothing on
    /// screen will say so.
    func testTheSameContextRendersIdenticallyEveryTime() throws {
        let first = try build().factSheet()
        let second = try build().factSheet()
        XCTAssertEqual(first, second)
    }
}
