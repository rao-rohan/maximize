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
        gradeAdjustedPaceSecondsPerKilometer: Double? = 308,
        strain: WorkoutStrain? = nil,
        distanceSplits: DistanceSplits? = nil
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
            strain: strain,
            distanceSplits: distanceSplits,
            planVersion: PlanVersion(planVersion)
        )
    }

    /// Splits written by hand rather than cut by `DistanceSplitCalculator`: these tests
    /// are about what reaches the prompt, and a calculator in the fixture would make a
    /// failure ambiguous between the two.
    private func splits(
        kilometreSeconds: [Double] = [300, 312, 347, 331],
        trailingMeters: Double? = nil,
        trailingSeconds: Double = 150,
        milePaceSeconds: Double = 500
    ) throws -> DistanceSplits {
        var kilometreSplits = try kilometreSeconds.enumerated().map { index, seconds in
            try DistanceSplit(
                ordinal: index + 1,
                distanceMeters: 1_000,
                elapsedSeconds: seconds,
                isComplete: true
            )
        }
        if let trailingMeters {
            kilometreSplits.append(
                try DistanceSplit(
                    ordinal: kilometreSplits.count + 1,
                    distanceMeters: trailingMeters,
                    elapsedSeconds: trailingSeconds,
                    isComplete: false
                )
            )
        }
        return try DistanceSplits(series: [
            DistanceSplitSeries(unit: .kilometers, splits: kilometreSplits),
            // A mile cut that is deliberately nothing like the kilometre one, so a test
            // can tell which series reached the prompt.
            DistanceSplitSeries(unit: .miles, splits: [
                DistanceSplit(
                    ordinal: 1,
                    distanceMeters: DistanceUnit.miles.metersPerUnit,
                    elapsedSeconds: milePaceSeconds,
                    isComplete: true
                ),
            ]),
        ])
    }

    private func build(
        metrics overrideMetrics: DerivedMetrics? = nil,
        classification: WorkoutClassification = .easy,
        on subject: String = "2026-01-06",
        workout: Workout? = nil,
        audience: WorkoutContext.Audience = .scoring,
        heartRateSeries: HeartRateSeries? = nil,
        existingScore: Score? = nil
    ) throws -> WorkoutContext {
        try WorkoutContextBuilder.build(
            workout: workout ?? Fixture.workout(),
            on: day(subject),
            metrics: overrideMetrics ?? metrics(),
            classification: classification,
            planCalendar: planCalendar(),
            audience: audience,
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
            "Strain:",
        ] {
            let occurrences = sheet.components(separatedBy: label).count - 1
            XCTAssertEqual(occurrences, 1, "\(label) should appear exactly once")
        }
    }

    // MARK: - MAX-177: strain

    func testAbsentStrainStatesTheAbsence() throws {
        let sheet = try build(
            metrics: metrics(
                averageHeartRateBPM: nil, maximumHeartRateBPM: nil, timeAboveCapSeconds: nil,
                heartRateDriftFraction: nil, strain: nil
            )
        ).factSheet()
        XCTAssertTrue(sheet.contains("Strain: not applicable — this workout has no heart-rate data"), sheet)
    }

    /// The common case on real data today: MAX-176 rescored nothing already stored
    /// (D8), so a workout with heart-rate data and no strain is not a contradiction —
    /// it predates the ticket, and this must read differently from "no heart-rate data
    /// at all" or Claude would be told the workout carries no heart-rate series when it
    /// plainly does (average/max HR appear two lines above).
    func testStrainNotYetComputedIsDistinguishedFromNoHeartRateData() throws {
        let sheet = try build(metrics: metrics(strain: nil)).factSheet()

        XCTAssertTrue(sheet.contains("Average heart rate: 142 bpm"), sheet)
        XCTAssertTrue(sheet.contains("Strain: not yet computed for this workout"), sheet)
        XCTAssertFalse(sheet.contains("Strain: not applicable"), "there is heart-rate data; this is a different fact")
    }

    /// Pinned as a literal, per the ticket's own requirement, so the wording — the
    /// unit, and the two things a bare number would invite Claude to assume — cannot
    /// silently drift.
    func testPresentStrainStatesTheUnitAndItsLimits() throws {
        let strain = try WorkoutStrain(points: 142)
        let sheet = try build(metrics: metrics(strain: strain)).factSheet()

        XCTAssertTrue(sheet.contains(
            "Strain: 142 zone-weighted minutes. Unbounded, not a 0–100 score: a bigger "
                + "number can mean a longer session, a harder one, or both, and it does not "
                + "distinguish them. Heart rate only — it says nothing about sets, reps, or "
                + "load, on a lift or otherwise."
        ), sheet)
    }

    /// `WorkoutStrain`'s zero-span case, built exactly as `DerivedMetricsCalculator`
    /// would: a curve that exists but covers no time (a single sample) reads as a
    /// *recorded* strain of 0 and *empty* zone splits — one fact, not two in tension —
    /// so the zone-splits line above reads "not applicable" while the strain line must
    /// not read as the same absence.
    func testAZeroSpanStrainIsDistinguishedFromNoHeartRateData() throws {
        let zeroSpanMetrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 140,
            maximumHeartRateBPM: 140,
            zoneSplits: .empty,
            strain: WorkoutStrain(points: 0),
            planVersion: PlanVersion(1)
        )
        let sheet = try build(metrics: zeroSpanMetrics).factSheet()

        XCTAssertTrue(sheet.contains("Time in zones: not applicable — no heart-rate data"), sheet)
        XCTAssertTrue(sheet.contains("Strain: 0 zone-weighted minutes"), sheet)
        XCTAssertFalse(
            sheet.contains("Strain: not applicable"),
            "a recorded zero must not read as the same absence as no heart-rate data at all"
        )
    }

    /// LIFTING-SPEC/A20: strain is heart-rate only, and a lift's line must not be
    /// readable as a verdict on the weight the athlete moved — the caveat is on every
    /// strain line, run or lift, rather than only appearing for one discipline.
    func testALiftsStrainLineDisclaimsLoad() throws {
        let strain = try WorkoutStrain(points: 88)
        let sheet = try build(
            metrics: metrics(strain: strain),
            workout: Fixture.workout(
                activityType: .traditionalStrengthTraining, distanceMeters: nil, hasRoute: false
            )
        ).factSheet()

        XCTAssertTrue(sheet.contains("Heart rate only — it says nothing about sets, reps, or load"), sheet)
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

    // MARK: - Pace breakdown (MAX-068)

    /// The decision this ticket made, asserted from both sides. The scorer's prompt is
    /// the automatic one — it is sent for every ingested run whether or not anybody asked
    /// a question — so it gets a rubric's worth of facts and no more.
    func testThePaceBreakdownIsWithheldFromTheScorer() throws {
        let withSplits = try metrics(distanceSplits: splits())

        let forScoring = try build(metrics: withSplits, audience: .scoring)
        XCTAssertNil(forScoring.paceBreakdown)
        XCTAssertFalse(forScoring.factSheet().contains("Pace by kilometre"))
        XCTAssertFalse(forScoring.factSheet().contains("5:12"), "no split pace may reach a scoring prompt")

        let forChat = try build(metrics: withSplits, audience: .chat)
        XCTAssertNotNil(forChat.paceBreakdown)
        XCTAssertTrue(forChat.factSheet().contains("## Pace by kilometre"))
    }

    /// FR-2's worked example is "why did my HR drift at mile 3", and answering it needs
    /// the *position* of each split, not a summary of the set. A fastest/slowest/variance
    /// reduction would be smaller and would answer nothing.
    func testChatIsGivenEveryKilometreInOrderRatherThanASummary() throws {
        let sheet = try build(
            metrics: metrics(distanceSplits: splits()),
            audience: .chat
        ).factSheet()

        // 300 s, 312 s, 347 s and 331 s over a kilometre each.
        XCTAssertTrue(sheet.contains("1 5:00 · 2 5:12 · 3 5:47 · 4 5:31"), sheet)
        XCTAssertFalse(sheet.lowercased().contains("fastest"), "not a reduction")
        XCTAssertFalse(sheet.lowercased().contains("variance"), "not a reduction")
    }

    /// The record stores a kilometre cut and a mile cut. Only one may reach the prompt,
    /// and which one may not depend on `AppSettings.distanceUnit` — the same stored run
    /// must render the same prompt on a day the athlete prefers miles.
    func testOnlyTheKilometreCutIsSentWhicheverUnitTheAthleteReads() throws {
        let context = try build(
            // A mile split of 500 s renders as 8:20 in its own unit; nothing like the
            // kilometre paces, so its appearance would be unmistakable.
            metrics: metrics(distanceSplits: splits(milePaceSeconds: 500)),
            audience: .chat
        )

        XCTAssertEqual(context.paceBreakdown?.unit, .kilometers)
        let sheet = context.factSheet()
        XCTAssertFalse(sheet.contains("8:20"), "the mile cut must not be sent as well")
        XCTAssertFalse(sheet.contains("/mi"), sheet)
    }

    /// An incomplete trailing split's pace is an extrapolation from a short stretch. On
    /// screen `SplitsListData` marks it "partial"; in the prompt it has to say as much in
    /// words, or Claude reads a finishing kick as the fastest kilometre of the run.
    func testTheTrailingPartialSplitIsMarkedAsExtrapolated() throws {
        let sheet = try build(
            // 420 m in 150 s — a 5:57 per-kilometre pace nobody held for a kilometre.
            metrics: metrics(distanceSplits: splits(trailingMeters: 420, trailingSeconds: 150)),
            audience: .chat
        ).factSheet()

        XCTAssertTrue(sheet.contains("final 0.42 km 5:57"), sheet)
        XCTAssertTrue(sheet.contains("extrapolated"), sheet)
    }

    /// Constraint from the ticket, and the common case today: every run already on the
    /// device predates MAX-046. "No splits are recorded" must read as a gap in what was
    /// stored, never as a run that had no per-kilometre variation.
    func testAMissingBreakdownReadsAsAGapInOurRecordsNotAnEvenRun() throws {
        let sheet = try build(audience: .chat).factSheet()

        XCTAssertTrue(sheet.contains("## Pace by kilometre"), "stated, not omitted")
        XCTAssertTrue(sheet.contains("gap in what was stored"), sheet)
        XCTAssertTrue(sheet.contains("do not read it as an even pace"), sheet)
    }

    /// A treadmill run never had a track to cut up (FR-0.6). That is a fact about the
    /// run, and it must not be worded like the missing-record case above.
    func testAnIndoorRunSaysThereWasNeverATrackToCut() throws {
        let sheet = try build(
            workout: Fixture.workout(hasRoute: false),
            audience: .chat
        ).factSheet()

        XCTAssertTrue(sheet.contains("Not applicable — indoor run"), sheet)
        XCTAssertFalse(sheet.contains("gap in what was stored"), "a different absence")
    }

    /// The bound. Not a budget for running long — a marathon is 43 entries — but the
    /// guard that stops a corrupted distance from sizing a prompt full of health data.
    func testAPathologicalSplitCountIsNotListed() throws {
        let tooMany = try (1...(WorkoutContext.maximumRenderedSplits + 1)).map { ordinal in
            try DistanceSplit(
                ordinal: ordinal,
                distanceMeters: 1_000,
                elapsedSeconds: 300,
                isComplete: true
            )
        }
        let sheet = try build(
            metrics: metrics(distanceSplits: DistanceSplits(series: [
                DistanceSplitSeries(unit: .kilometers, splits: tooMany),
            ])),
            audience: .chat
        ).factSheet()

        XCTAssertTrue(sheet.contains("\(tooMany.count) splits are on file"), sheet)
        XCTAssertFalse(sheet.contains("1 5:00 · 2 5:00"), "none of them are listed")
    }

    // MARK: - Determinism

    /// D3's actual requirement. If two builds of the same context can render differently,
    /// the scorer and the chat have started to disagree about the run and nothing on
    /// screen will say so.
    func testTheSameContextRendersIdenticallyEveryTime() throws {
        let first = try build().factSheet()
        let second = try build().factSheet()
        XCTAssertEqual(first, second)

        // And with the widest payload, which is the one worth pinning: the splits are
        // rendered from stored scalars with a fixed unit and a pinned locale, so nothing
        // about the device may move them.
        let withSplits = try metrics(distanceSplits: splits(trailingMeters: 420))
        XCTAssertEqual(
            try build(metrics: withSplits, audience: .chat).factSheet(),
            try build(metrics: withSplits, audience: .chat).factSheet()
        )
    }
}
