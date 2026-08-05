import XCTest
@testable import MaximizeCore

/// End-to-end assembly of the §9 metrics.
///
/// The reference workout is an hour covering 10 km, with a heart-rate curve rising
/// linearly from 120 to 180 bpm across the full 3 600 s — one bpm every minute. Against
/// the fixture plan's 150 bpm cap, every metric on it is hand-computable:
///
/// - average 150 bpm (the midpoint of a straight line), max 180 bpm;
/// - the cap is crossed at t = 1 800 s, so 1 800 s above cap;
/// - halves average 135 and 165 bpm, so drift is 165/135 − 1 = 2/9;
/// - zone edges 135/150/162/174 are crossed at t = 900, 1 800, 2 520 and 3 240 s;
/// - 9 900 steps over 60 minutes is 165 spm, inside the plan's 165–170 band;
/// - a flat route leaves the 360 s/km pace unadjusted.
final class DerivedMetricsCalculatorTests: XCTestCase {
    private func referenceInput(
        activityType: ActivityType = .running,
        durationSeconds: Double = 3_600,
        distanceMeters: Double? = 10_000,
        heartRate: [(Double, Double)]? = [(0, 120), (3_600, 180)],
        altitudes: [Double?]? = [50, 50, 50, 50],
        totalStepCount: Double? = 9_900,
        classification: WorkoutClassification? = .easy
    ) throws -> DerivedMetricsInput {
        let workout = try Fixture.workout(
            activityType: activityType,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            hasRoute: altitudes != nil
        )
        var series: HeartRateSeries?
        if let heartRate {
            series = try MetricsFixture.series(heartRate)
        }
        var route: Route?
        if let altitudes {
            route = try MetricsFixture.meridianRoute(altitudes: altitudes)
        }
        return try DerivedMetricsInput(
            workout: workout,
            heartRateSeries: series,
            route: route,
            totalStepCount: totalStepCount,
            classification: classification
        )
    }

    // MARK: - Happy path

    func testEasyOutdoorRunProducesEveryMetric() throws {
        let plan = try Fixture.plan()
        let metrics = try DerivedMetricsCalculator.compute(try referenceInput(), plan: plan)

        XCTAssertEqual(metrics.workoutID, Fixture.workoutID)
        XCTAssertEqual(metrics.planVersion, plan.version)
        XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.maximumHeartRateBPM), 180, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.heartRateDriftFraction), 2.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.averageCadenceStepsPerMinute), 165, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(metrics.gradeAdjustedPaceSecondsPerKilometer), 360, accuracy: 1e-9
        )
    }

    func testZoneSplitsCoverTheWholeCurve() throws {
        let metrics = try DerivedMetricsCalculator.compute(try referenceInput(), plan: try Fixture.plan())

        XCTAssertEqual(metrics.zoneSplits.seconds(in: .one), 900, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .two), 900, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .three), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .four), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .five), 360, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
    }

    func testAverageCadenceIsComparedAgainstThePlansBand() throws {
        let plan = try Fixture.plan()
        let metrics = try DerivedMetricsCalculator.compute(try referenceInput(), plan: plan)
        let cadence = try XCTUnwrap(metrics.averageCadenceStepsPerMinute)

        // The comparison is the plan's to make, not the metric's — the stored number is
        // just steps per minute.
        XCTAssertTrue(plan.cadenceTarget.contains(cadence))
        let slow = try DerivedMetricsCalculator.compute(
            try referenceInput(totalStepCount: 9_000), plan: plan
        )
        XCTAssertEqual(try XCTUnwrap(slow.averageCadenceStepsPerMinute), 150, accuracy: 1e-9)
        XCTAssertFalse(plan.cadenceTarget.contains(150))
    }

    // MARK: - D1: thresholds come from the plan

    /// The same run, scored against two plan versions with different caps, must produce
    /// different numbers. A hardcoded 150 anywhere in the metric code fails here.
    func testTimeAboveCapAndZonesFollowThePlansCap() throws {
        let input = try referenceInput()

        let strict = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan(heartRateCapBPM: 150))
        // 150 bpm is reached at t = 1 800 s.
        XCTAssertEqual(try XCTUnwrap(strict.timeAboveCapSeconds), 1_800, accuracy: 1e-9)

        let relaxed = try DerivedMetricsCalculator.compute(
            input, plan: try Fixture.plan(version: 2, heartRateCapBPM: 160)
        )
        // 160 bpm is reached at t = (160 − 120) × 60 = 2 400 s.
        XCTAssertEqual(try XCTUnwrap(relaxed.timeAboveCapSeconds), 1_200, accuracy: 1e-9)

        // Zones move with the cap too: with a 160 cap the first edge is 0.90 × 160 = 144,
        // reached at t = 1 440 s.
        XCTAssertEqual(relaxed.zoneSplits.seconds(in: .one), 1_440, accuracy: 1e-9)
        XCTAssertEqual(relaxed.planVersion, try PlanVersion(2))
    }

    func testAnExplicitZoneModelOverridesTheCapAnchoredDefault() throws {
        // Proves the zones are a parameter, not a rule baked into the splitting code —
        // the seam a future plan version's stored boundaries will arrive through.
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(),
            plan: try Fixture.plan(),
            zoneModel: try HeartRateZoneModel(upperBoundsBPM: [126, 138, 150, 162])
        )
        // Edges reached at t = 360, 1 080, 1 800 and 2 520 s.
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .one), 360, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .two), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .three), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .four), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .five), 1_080, accuracy: 1e-9)
    }

    // MARK: - Drift is conditional (§9)

    func testDriftIsSurfacedOnEasyAndLongRuns() throws {
        for classification in [WorkoutClassification.easy, .long] {
            let metrics = try DerivedMetricsCalculator.compute(
                try referenceInput(classification: classification), plan: try Fixture.plan()
            )
            XCTAssertEqual(
                try XCTUnwrap(metrics.heartRateDriftFraction), 2.0 / 9.0, accuracy: 1e-9,
                "drift should be surfaced for \(classification)"
            )
        }
    }

    /// The not-applicable case the ticket asks for: on an interval session drift is
    /// near-meaningless (§9), so it is **absent**, not 0.0. A zero here would be averaged
    /// into the dashboard's drift trend as a perfect run.
    func testDriftIsAbsentOnHardAndOtherSessions() throws {
        for classification in [WorkoutClassification.hard, .other] {
            let metrics = try DerivedMetricsCalculator.compute(
                try referenceInput(classification: classification), plan: try Fixture.plan()
            )
            XCTAssertNil(metrics.heartRateDriftFraction, "drift should be absent for \(classification)")
            // Everything else about the run is still measured.
            XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 150, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        }
    }

    func testDriftIsAbsentUntilTheWorkoutHasBeenClassified() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(classification: nil), plan: try Fixture.plan()
        )
        XCTAssertNil(metrics.heartRateDriftFraction)
    }

    // MARK: - Not applicable, and never zero

    func testIndoorRunHasNoGradeAdjustedPaceAndKeepsEverythingElse() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(activityType: .treadmillRunning, altitudes: nil),
            plan: try Fixture.plan()
        )

        // FR-0.6: the treadmill run is not a degraded outdoor run. Its adjusted pace is
        // absent — not zero, which anything averaging these would read as instantaneous.
        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.averageCadenceStepsPerMinute), 165, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
    }

    func testOutdoorRunWithoutAltitudeHasNoGradeAdjustedPace() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(altitudes: [nil, nil, nil]), plan: try Fixture.plan()
        )
        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
    }

    func testWorkoutWithoutHeartRateHasNoHeartRateMetrics() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(heartRate: nil), plan: try Fixture.plan()
        )

        XCTAssertNil(metrics.averageHeartRateBPM)
        XCTAssertNil(metrics.maximumHeartRateBPM)
        // Absent, not "zero seconds above the cap" — the latter would read as a
        // flawlessly disciplined run.
        XCTAssertNil(metrics.timeAboveCapSeconds)
        XCTAssertNil(metrics.heartRateDriftFraction)
        XCTAssertFalse(metrics.hasHeartRateData)
        XCTAssertTrue(metrics.zoneSplits.splits.isEmpty)
        // The rest of the run is unaffected.
        XCTAssertEqual(try XCTUnwrap(metrics.averageCadenceStepsPerMinute), 165, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(metrics.gradeAdjustedPaceSecondsPerKilometer), 360, accuracy: 1e-9
        )
    }

    /// Zero and absent side by side: a disciplined run really did spend **0 s** above the
    /// cap, and that is a different fact from having no heart-rate data.
    func testAnEasyRunUnderTheCapRecordsZeroSecondsAboveIt() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(heartRate: [(0, 128), (1_800, 134), (3_600, 130)]),
            plan: try Fixture.plan()
        )

        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 0, accuracy: 1e-9)
        XCTAssertTrue(metrics.hasHeartRateData)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .one), 3_600, accuracy: 1e-9)
    }

    func testSingleSampleSeriesMeasuresNoTimeAndNoDrift() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(heartRate: [(120, 165)]), plan: try Fixture.plan()
        )

        XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 165, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.maximumHeartRateBPM), 165, accuracy: 1e-9)
        // One sample above the cap is still zero *seconds* above it: a lone reading has
        // no duration.
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 0, accuracy: 1e-9)
        XCTAssertNil(metrics.heartRateDriftFraction)
        XCTAssertTrue(metrics.zoneSplits.splits.isEmpty)
    }

    func testCadenceIsAbsentWithoutSteps() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(totalStepCount: nil), plan: try Fixture.plan()
        )
        XCTAssertNil(metrics.averageCadenceStepsPerMinute)
    }

    func testZeroDurationWorkoutHasNoCadenceAndNoPace() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(durationSeconds: 0, heartRate: nil), plan: try Fixture.plan()
        )

        // Division by zero is a real path here: a mis-started session has a duration of
        // zero and an unknowable cadence, which is not the same as standing still.
        XCTAssertNil(metrics.averageCadenceStepsPerMinute)
        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
    }

    func testZeroDistanceWorkoutHasNoPaceButKeepsItsHeartRateMetrics() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(distanceMeters: 0), plan: try Fixture.plan()
        )

        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.averageCadenceStepsPerMinute), 165, accuracy: 1e-9)
    }

    // MARK: - FR-1.5: the pace breakdown (MAX-046)
    //
    // The breakdown's own arithmetic is pinned in `DistanceSplitsTests`. What is checked
    // here is that it is computed *at ingestion*, on the metrics record, which is D2's
    // requirement and the whole reason MAX-046 was not a display ticket.

    /// A route exactly as long as the recorded 10 km, so the track describes the run and
    /// the breakdown is producible.
    private func matchingRoute() throws -> Route {
        try MetricsFixture.meridianRoute(
            altitudes: Array<Double?>(repeating: 50, count: 10),
            latitudeStepDegrees: (10_000 / 9) / MetricsFixture.metersPerLatitudeDegree
        )
    }

    func testDistanceSplitsAreComputedOnTheMetricsRecord() throws {
        let input = try DerivedMetricsInput(
            workout: try Fixture.workout(),
            route: try matchingRoute()
        )
        let metrics = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan())

        let splits = try XCTUnwrap(metrics.distanceSplits)
        XCTAssertEqual(try XCTUnwrap(splits.series(in: .kilometers)).splits.count, 10)
        XCTAssertNotNil(splits.series(in: .miles))
    }

    /// FR-0.6 again: a treadmill run's breakdown is *absent*, never a set of identical
    /// fabricated splits derived by dividing its distance by its duration.
    func testIndoorRunHasNoDistanceSplits() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try referenceInput(activityType: .treadmillRunning, altitudes: nil),
            plan: try Fixture.plan()
        )
        XCTAssertNil(metrics.distanceSplits)
    }

    /// MAX-066: a treadmill run with a distance-sample series gets a real breakdown,
    /// computed on the metrics record exactly like the GPS path above — the arithmetic
    /// is pinned in `DistanceSplitsTests`, this only checks the ingestion-time wiring.
    func testTreadmillDistanceSplitsAreComputedOnTheMetricsRecordFromDistanceSamples() throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        var samples: [DistanceSample] = [try DistanceSample(offsetSeconds: 0, meters: 0)]
        for index in 1...9 {
            samples.append(try DistanceSample(offsetSeconds: Double(index) * 100, meters: 10_000.0 / 9))
        }
        let input = try DerivedMetricsInput(
            workout: workout,
            distanceSamples: try DistanceSampleSeries(workoutID: workout.id, samples: samples)
        )
        let metrics = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan())

        let splits = try XCTUnwrap(metrics.distanceSplits)
        XCTAssertEqual(try XCTUnwrap(splits.series(in: .kilometers)).splits.count, 10)
        XCTAssertNotNil(splits.series(in: .miles))
    }

    /// The reference route is 3 336 m of track against a 10 km run — a truncated or
    /// dropped-out track, which cannot be stretched into a breakdown (see
    /// `DistanceSplitCalculator`). Every other metric on the run is unaffected.
    func testTrackThatCannotDescribeTheRunLeavesTheRestOfTheMetricsIntact() throws {
        let metrics = try DerivedMetricsCalculator.compute(try referenceInput(), plan: try Fixture.plan())

        XCTAssertNil(metrics.distanceSplits)
        XCTAssertEqual(try XCTUnwrap(metrics.gradeAdjustedPaceSecondsPerKilometer), 360, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
    }

    // MARK: - MAX-111/MAX-130: what each discipline's metrics are
    //
    // MAX-111 gated three metrics on `isRun` at their call sites. MAX-130 moves the
    // decision into `DerivedMetricKind` and settles what a lift's record actually
    // contains. The rules themselves are pinned in `DerivedMetricKindTests`; what is
    // checked here is that the calculator honours them end to end, on inputs rich
    // enough that every withheld figure would otherwise have been produced.

    /// A run's stored record, in full, against hand-computed values (see the header).
    /// The regression promise of the refactor: not one number moves.
    func testEveryFigureOfARunIsUnchangedByDisciplineGating() throws {
        let plan = try Fixture.plan()
        let input = try DerivedMetricsInput(
            workout: try Fixture.workout(),
            heartRateSeries: try MetricsFixture.series([(0, 120), (3_600, 180)]),
            route: try matchingRoute(),
            totalStepCount: 9_900,
            classification: .easy
        )

        let metrics = try DerivedMetricsCalculator.compute(input, plan: plan)

        XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.maximumHeartRateBPM), 180, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.heartRateDriftFraction), 2.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.averageCadenceStepsPerMinute), 165, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(metrics.gradeAdjustedPaceSecondsPerKilometer), 360, accuracy: 1e-9
        )
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.distanceSplits?.series(in: .kilometers)).splits.count, 10)
        XCTAssertTrue(metrics.distanceSplitsComputed)
        XCTAssertEqual(metrics.planVersion, plan.version)

        // Stated as a totality rather than eight assertions: a run is entitled to
        // everything, and this fails if a future metric quietly stops applying to one.
        for kind in DerivedMetricKind.allCases {
            XCTAssertTrue(metrics.isRecorded(kind), "a run should record \(kind.rawValue)")
        }
    }

    /// The lift is handed a heart-rate series, a step count, a recorded distance, a route
    /// long enough to cut into splits, **and** an `.easy` classification — none of which a
    /// real lift would carry together. That is the point: every figure absent below is
    /// absent because the discipline says so, not because the input was missing.
    private func liftWithEveryRunningIngredient() throws -> DerivedMetricsInput {
        try DerivedMetricsInput(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            heartRateSeries: try MetricsFixture.series([(0, 120), (3_600, 180)]),
            route: try matchingRoute(),
            totalStepCount: 9_900,
            classification: .easy
        )
    }

    /// The whole of §3.2 in one assertion: a lift records exactly the figures that apply
    /// to a lift, and nothing else — absent, never zero.
    func testALiftRecordsExactlyTheFiguresThatApplyToALift() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try liftWithEveryRunningIngredient(), plan: try Fixture.plan()
        )

        for kind in DerivedMetricKind.allCases {
            XCTAssertEqual(
                metrics.isRecorded(kind),
                kind.applies(to: .traditionalStrengthTraining),
                kind.rawValue
            )
        }
    }

    /// The confirmed defect MAX-111 found: a strength session was storing a "cadence" —
    /// its incidental between-sets step count divided by the session's duration — and
    /// `WorkoutFactSheet` was sending that number to Claude as a measured fact.
    ///
    /// A zero would be averaged into the dashboard's cadence trend and drawn on the
    /// cadence band as a session with no turnover at all. Absent is the only honest
    /// answer, and it stays absent under the new gate.
    func testALiftGetsNoCadenceNoRunningPaceAndNoSplits() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try liftWithEveryRunningIngredient(), plan: try Fixture.plan()
        )

        XCTAssertNil(metrics.averageCadenceStepsPerMinute)
        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertNil(metrics.distanceSplits)
        // MAX-067's backfill selects on this flag; leaving it false would have the sweep
        // re-fetch a lift's samples on every launch, forever, hunting splits it will never
        // be allowed to compute.
        XCTAssertTrue(metrics.distanceSplitsComputed)
    }

    /// A lift's heart rate is a real measurement of a thing the athlete really did, and it
    /// is the one rich signal this discipline gives us for free (§3.2). Zone splits stay
    /// with it — §3.3(b) — as the only figure in the record that could tell a lifting
    /// session apart from a walk.
    func testALiftKeepsTheHeartRateItActuallyProduced() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try liftWithEveryRunningIngredient(), plan: try Fixture.plan()
        )

        XCTAssertEqual(try XCTUnwrap(metrics.averageHeartRateBPM), 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.maximumHeartRateBPM), 180, accuracy: 1e-9)
        XCTAssertTrue(metrics.hasHeartRateData)
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .five), 360, accuracy: 1e-9)
    }

    /// §3.3(a), and the one figure this ticket takes away from a lift that MAX-111 left.
    ///
    /// `Plan.heartRateCapBPM` is the **easy-run** ceiling and `timeAboveCapSeconds` is
    /// documented as the primary easy-run discipline metric. A heavy set puts most people
    /// over that cap, so on a lift the figure silently changes meaning — from "how well
    /// did you hold the plan's discipline" to "how hard did you work" — while keeping its
    /// name, its column and its heading. It is withheld rather than restated.
    ///
    /// Note what this is *not*: it is not "no heart-rate data". The reading is there; the
    /// cap it would be read against is a run field, and whether a lift should ever have a
    /// ceiling of its own is a plan-model question this ticket does not open.
    func testALiftHasNoTimeAboveCapEvenThoughItHasAHeartRate() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try liftWithEveryRunningIngredient(), plan: try Fixture.plan()
        )

        XCTAssertNil(metrics.timeAboveCapSeconds)
        XCTAssertTrue(metrics.hasHeartRateData)
    }

    /// Drift is aerobic decoupling — cardiac cost creeping up at a *held* effort — and a
    /// lift holds no effort. `driftIsMeaningful` already withholds it for every
    /// classification a lift can currently carry, so this passes twice over. The
    /// redundancy is deliberate: the classification arriving here is an input, and the
    /// gate must not depend on `WorkoutClassifier` never answering `.easy` for a lift.
    func testALiftHasNoDriftEvenWhenHandedAClassificationThatWouldSurfaceIt() throws {
        let metrics = try DerivedMetricsCalculator.compute(
            try liftWithEveryRunningIngredient(), plan: try Fixture.plan()
        )
        XCTAssertNil(metrics.heartRateDriftFraction)
    }

    /// The gap between the run *slot* and a run: a hike is `Discipline.run` — A17 is
    /// explicit that it is not a discipline of its own — and it still has no running
    /// form. Before MAX-111 it got a pace off Minetti's cost-of-**running** curve and a
    /// set of running pace splits. A gate written as `discipline == .run` would hand them
    /// straight back.
    func testARunSlotWorkoutThatIsNotARunStillGetsNoRunningPaceOrSplits() throws {
        let input = try DerivedMetricsInput(
            workout: try Fixture.workout(activityType: .hiking),
            heartRateSeries: try MetricsFixture.series([(0, 120), (3_600, 180)]),
            route: try matchingRoute(),
            totalStepCount: 9_900
        )

        let metrics = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan())

        XCTAssertEqual(metrics.workoutID, Fixture.workoutID)
        XCTAssertNil(metrics.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertNil(metrics.distanceSplits)
        XCTAssertNil(metrics.averageCadenceStepsPerMinute)
        XCTAssertTrue(metrics.distanceSplitsComputed)

        // Unchanged: a hike is in the run slot, so the run prescription's cap is the ask
        // it is measured against. Only the lift slot loses the cap figure.
        XCTAssertEqual(try XCTUnwrap(metrics.timeAboveCapSeconds), 1_800, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 3_600, accuracy: 1e-9)
    }

    // The other half of the gate — that the treadmill is still a run, so an indoor run is
    // not quietly demoted — is already pinned above by
    // `testIndoorRunHasNoGradeAdjustedPaceAndKeepsEverythingElse` (cadence 165) and
    // `testTreadmillDistanceSplitsAreComputedOnTheMetricsRecordFromDistanceSamples`
    // (a real breakdown). Both fail if the discipline check ever narrows to outdoor runs.

    // MARK: - Input invariants

    func testSeriesFromAnotherWorkoutIsRejected() throws {
        let workout = try Fixture.workout()
        assertThrows(
            .inconsistent,
            try DerivedMetricsInput(
                workout: workout,
                heartRateSeries: try MetricsFixture.series(
                    [(0, 140)], workoutID: Fixture.otherWorkoutID
                )
            )
        )
    }

    func testRouteFromAnotherWorkoutIsRejected() throws {
        let workout = try Fixture.workout()
        assertThrows(
            .inconsistent,
            try DerivedMetricsInput(
                workout: workout,
                route: try MetricsFixture.meridianRoute(
                    altitudes: [10, 20], workoutID: Fixture.otherWorkoutID
                )
            )
        )
    }

    func testDistanceSamplesFromAnotherWorkoutIsRejected() throws {
        let workout = try Fixture.workout()
        assertThrows(
            .inconsistent,
            try DerivedMetricsInput(
                workout: workout,
                distanceSamples: try DistanceSampleSeries(
                    workoutID: Fixture.otherWorkoutID,
                    samples: [try DistanceSample(offsetSeconds: 0, meters: 0)]
                )
            )
        )
    }

    func testRouteSuppliedForAWorkoutRecordedWithoutOneIsRejected() throws {
        let indoor = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        assertThrows(
            .inconsistent,
            try DerivedMetricsInput(workout: indoor, route: try MetricsFixture.meridianRoute(altitudes: [10, 20]))
        )
    }

    func testNegativeStepCountIsRejected() throws {
        assertThrows(
            .outOfRange,
            try DerivedMetricsInput(workout: try Fixture.workout(), totalStepCount: -1)
        )
    }

    // MARK: - Determinism (D2)

    func testTheSameInputsAlwaysProduceTheSameMetrics() throws {
        let input = try referenceInput()
        let plan = try Fixture.plan()

        let first = try DerivedMetricsCalculator.compute(input, plan: plan)
        let second = try DerivedMetricsCalculator.compute(input, plan: plan)

        // Stored once and read forever (D2): a second run must not disagree with the
        // first, including in the ordering of the zone splits.
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.zoneSplits.splits.map(\.zone), second.zoneSplits.splits.map(\.zone))
        XCTAssertEqual(try roundTripped(first), first)
    }
}
