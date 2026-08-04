import XCTest
@testable import MaximizeCore

/// §10.2 — classifying what the athlete actually did.
///
/// Every expectation below is reasoned from the *fixture plan*, never from a number
/// this suite invented (D1). That plan says: cap 150 bpm, so cap-anchored zones break at
/// 135 / 150 / 162 / 174; a long-run arc of 16 km, 18 km and 20 km for weeks 1–3 from
/// 2026-01-01; and a weekly template whose shortest prescribed run is 6 km. With the
/// default policy that makes the thresholds under test:
///
/// - **long** at ≥ 85% of the week's arc — 13 600 m in week 1, 17 000 m in week 3;
/// - **hard** at ≥ 15% of the heart-rate curve in zone 4 or 5, i.e. above 162 bpm;
/// - **fragment** below 25% of 6 km, i.e. 1 500 m.
///
/// Workouts start at `Fixture.epoch`, which is 2026-01-01 — the plan's first day, and
/// therefore arc week 1 — with `dayOffset` moving them into later weeks.
final class WorkoutClassifierTests: XCTestCase {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    private func runWorkout(
        activityType: ActivityType = .running,
        dayOffset: Int = 0,
        durationSeconds: Double = 3_600,
        distanceMeters: Double? = 9_000
    ) throws -> Workout {
        let start = Fixture.epoch.addingTimeInterval(Double(dayOffset) * 86_400)
        return try Workout(
            id: Fixture.workoutID,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 600,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 60)
        )
    }

    /// Metrics carrying a hand-built zone profile.
    ///
    /// `zones` nil means the workout had no heart-rate series at all — which is
    /// different from an empty one, and `DerivedMetrics` enforces the difference by
    /// refusing a time-above-cap without an average.
    private func metrics(
        zones: [(HeartRateZone, Double)]?,
        averageBPM: Double = 140,
        maximumBPM: Double = 168,
        drift: Double? = nil,
        workoutID: UUID = Fixture.workoutID,
        planVersion: Int = 1
    ) throws -> DerivedMetrics {
        guard let zones else {
            return try DerivedMetrics(workoutID: workoutID, planVersion: PlanVersion(planVersion))
        }
        var splits: [ZoneSplits.Split] = []
        for (zone, seconds) in zones {
            splits.append(try ZoneSplits.Split(zone: zone, seconds: seconds))
        }
        // Zones 3 and up begin at the cap, so time-above-cap is the same span read at a
        // lower boundary — kept consistent so no test leans on an impossible record.
        let aboveCap = zones.filter { $0.0 >= .three }.reduce(0) { $0 + $1.1 }
        return try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: averageBPM,
            maximumHeartRateBPM: maximumBPM,
            timeAboveCapSeconds: aboveCap,
            heartRateDriftFraction: drift,
            zoneSplits: ZoneSplits(splits: splits),
            planVersion: PlanVersion(planVersion)
        )
    }

    private func classify(
        _ workout: Workout,
        _ metrics: DerivedMetrics,
        plan: Plan? = nil,
        policy: WorkoutClassificationPolicy = .default
    ) throws -> WorkoutClassification {
        let resolvedPlan: Plan
        if let plan {
            resolvedPlan = plan
        } else {
            resolvedPlan = try Fixture.plan()
        }
        return try WorkoutClassifier.classify(
            workout,
            metrics: metrics,
            plan: resolvedPlan,
            timeZone: WorkoutClassifierTests.utc,
            policy: policy
        )
    }

    /// A disciplined hour: the whole curve in the recovery and aerobic zones.
    private static let underTheCap: [(HeartRateZone, Double)] = [(.one, 600), (.two, 3_000)]

    // MARK: - Activities the plan does not score as runs

    func testStrengthTrainingIsNotAnyKindOfRun() throws {
        let workout = try runWorkout(activityType: .traditionalStrengthTraining, distanceMeters: nil)
        // Even with a heart-rate profile that would read as hard on a run: §3 puts
        // strength work outside HR scoring, so the truthful answer is `other`.
        let classification = try classify(workout, metrics(zones: [(.four, 1_800), (.two, 1_800)]))
        XCTAssertEqual(classification, .other)
    }

    func testAWalkIsNotClassifiedAsAnEasyRun() throws {
        let workout = try runWorkout(activityType: .walking, distanceMeters: 5_000)
        XCTAssertEqual(try classify(workout, metrics(zones: [(.one, 3_600)])), .other)
    }

    func testATreadmillRunIsClassifiedLikeAnyOtherRun() throws {
        // FR-0.6: indoor running is first-class, not a degraded run.
        let workout = try runWorkout(activityType: .treadmillRunning, distanceMeters: 9_000)
        XCTAssertEqual(try classify(workout, metrics(zones: WorkoutClassifierTests.underTheCap)), .easy)
    }

    // MARK: - Effort

    func testARunHeldUnderTheCapIsEasy() throws {
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: WorkoutClassifierTests.underTheCap)), .easy)
    }

    func testARunSpentMostlyAboveTheCapButBelowThresholdIsAnEasyRunRunBadly() throws {
        // 80% of the hour between the cap and 162 bpm — an easy run that got away from
        // the athlete, not a session they set out to make hard. §10.3 scores exactly this
        // in the 55–74 band *as an easy run*; promoting it to `hard` would instead fire
        // the "ran hard on an easy day" band and punish a discipline lapse as though it
        // were a different session.
        let hot: [(HeartRateZone, Double)] = [(.two, 720), (.three, 2_880)]
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: hot, averageBPM: 156)), .easy)
    }

    func testAShortRunSpentAlmostEntirelyAtThresholdIsHard() throws {
        // Twenty minutes, nearly all of it above 162 bpm. Short, but unambiguously a
        // hard session rather than a shortened easy one.
        let workout = try runWorkout(durationSeconds: 1_200, distanceMeters: 5_000)
        let profile: [(HeartRateZone, Double)] = [(.two, 120), (.four, 900), (.five, 180)]
        XCTAssertEqual(try classify(workout, metrics(zones: profile, averageBPM: 168, maximumBPM: 182)), .hard)
    }

    func testAnIntervalSessionIsHardEvenThoughEasyRunningDominatesItsClock() throws {
        // 6 × 800 m inside an hour: 12 minutes above 162 bpm, 48 minutes of warm-up,
        // recovery jogs and cool-down. A majority-of-the-run rule would call this easy
        // and then publish a drift number §9 says is meaningless on it.
        let session: [(HeartRateZone, Double)] = [(.one, 600), (.two, 2_280), (.four, 480), (.five, 240)]
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: session, maximumBPM: 184)), .hard)
    }

    func testBriefHillSurgesDoNotMakeAnEasyRunHard() throws {
        // 5% of the hour above 162 bpm — two or three climbs. Still an easy run.
        let hilly: [(HeartRateZone, Double)] = [(.two, 3_420), (.four, 180)]
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: hilly, maximumBPM: 170)), .easy)
    }

    // MARK: - Long

    func testALongRunHeldUnderTheCapIsLongRatherThanEasy() throws {
        // 16 km in week 1, which is the arc's ask exactly. Both labels describe it
        // truthfully; `long` is the one the scorer needs, because the rubric's easy bands
        // would judge it against the wrong distance.
        let workout = try runWorkout(durationSeconds: 6_000, distanceMeters: 16_000)
        let profile: [(HeartRateZone, Double)] = [(.one, 900), (.two, 5_100)]
        XCTAssertEqual(try classify(workout, metrics(zones: profile)), .long)
    }

    func testALongRunCutSlightlyShortIsStillTheLongRun() throws {
        // 14 km against week 1's 16 km ask: past the 13 600 m line. Judging the shortfall
        // is the scorer's job; a classifier that demanded the full distance would send
        // every imperfect long run down the easy-run rubric.
        let workout = try runWorkout(durationSeconds: 5_400, distanceMeters: 14_000)
        XCTAssertEqual(try classify(workout, metrics(zones: WorkoutClassifierTests.underTheCap)), .long)
    }

    func testARunWellShortOfTheWeeksLongRunIsNotLong() throws {
        // 13 km, just under the 13 600 m line.
        let workout = try runWorkout(durationSeconds: 5_400, distanceMeters: 13_000)
        XCTAssertEqual(try classify(workout, metrics(zones: WorkoutClassifierTests.underTheCap)), .easy)
    }

    func testWhatCountsAsLongFollowsTheWeeksArcRatherThanAFixedDistance() throws {
        // The same 16.5 km run: the long run of week 1 (ask 16 km), and merely a big
        // midweek run in week 3 (ask 20 km, so the line is 17 km).
        let profile = try metrics(zones: WorkoutClassifierTests.underTheCap)
        let weekOne = try runWorkout(dayOffset: 0, durationSeconds: 6_000, distanceMeters: 16_500)
        let weekThree = try runWorkout(dayOffset: 14, durationSeconds: 6_000, distanceMeters: 16_500)

        XCTAssertEqual(try classify(weekOne, profile), .long)
        XCTAssertEqual(try classify(weekThree, profile), .easy)
    }

    func testALongRunTakenToThresholdIsHardRatherThanLong() throws {
        // 18 km — past week 1's line — but a third of it above 162 bpm. Calling it the
        // long run would surface drift on a session that was raced, and §9 says drift is
        // near-meaningless there.
        let workout = try runWorkout(durationSeconds: 6_000, distanceMeters: 18_000)
        let profile: [(HeartRateZone, Double)] = [(.two, 3_000), (.three, 1_000), (.four, 1_500), (.five, 500)]
        XCTAssertEqual(try classify(workout, metrics(zones: profile, averageBPM: 160, maximumBPM: 180)), .hard)
    }

    func testARunInAWeekTheArcSaysNothingAboutIsNotLongByDefault() throws {
        // Week 5 of a three-week arc: the plan has no opinion on long for that week, and
        // the classifier does not invent one.
        let workout = try runWorkout(dayOffset: 28, durationSeconds: 7_200, distanceMeters: 22_000)
        XCTAssertEqual(try classify(workout, metrics(zones: WorkoutClassifierTests.underTheCap)), .easy)
    }

    func testARunBeforeThePlanTookEffectIsNotMeasuredAgainstItsArc() throws {
        // A workout predating `effectiveFrom` belongs to an earlier plan version; week 1
        // of *this* one is the wrong yardstick, so it gets no long-run claim.
        let workout = try runWorkout(dayOffset: -3, durationSeconds: 6_000, distanceMeters: 16_000)
        XCTAssertEqual(try classify(workout, metrics(zones: WorkoutClassifierTests.underTheCap)), .easy)
    }

    // MARK: - Honest `other`

    func testARunWithNoHeartRateDataIsNotGuessedAsEasy() throws {
        // Easy and hard are separated only by the HR profile. With no curve there is
        // nothing to separate them with, and "easy" would fabricate the very discipline
        // the rubric is about to reward.
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: nil)), .other)
    }

    func testALongRunWithNoHeartRateDataIsStillTheLongRun() throws {
        // Length is a distance fact. The arc answers it without help from the sensor.
        let workout = try runWorkout(durationSeconds: 6_000, distanceMeters: 16_000)
        XCTAssertEqual(try classify(workout, metrics(zones: nil)), .long)
    }

    func testASingleHeartRateSampleCoversNoTimeAndSoDecidesNothing() throws {
        // A one-sample series has an average but spans zero seconds, so no fraction of it
        // can be taken. That is a missing effort signal, not an effort of zero.
        let sparse = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 145,
            maximumHeartRateBPM: 145,
            timeAboveCapSeconds: 0,
            planVersion: PlanVersion(1)
        )
        XCTAssertEqual(try classify(runWorkout(), sparse), .other)
    }

    func testAMisStartedFragmentIsNotClassifiedAsASession() throws {
        // Four minutes and 900 m, under the 1 500 m fragment line. Scoring it against a
        // scheduled 8 km would write a confident, immutable, wrong number (D8).
        let workout = try runWorkout(durationSeconds: 240, distanceMeters: 900)
        XCTAssertEqual(try classify(workout, metrics(zones: [(.one, 120), (.two, 120)])), .other)
    }

    func testAShortRunAboveTheFragmentLineIsStillARun() throws {
        let workout = try runWorkout(durationSeconds: 900, distanceMeters: 2_500)
        XCTAssertEqual(try classify(workout, metrics(zones: [(.two, 900)])), .easy)
    }

    func testAWorkoutWithNoDurationCannotBeClassified() throws {
        let workout = try runWorkout(durationSeconds: 0, distanceMeters: nil)
        XCTAssertEqual(try classify(workout, metrics(zones: nil)), .other)
    }

    func testARunWithNeitherDistanceNorHeartRateIsUnclassifiable() throws {
        let workout = try runWorkout(distanceMeters: nil)
        XCTAssertEqual(try classify(workout, metrics(zones: nil)), .other)
    }

    // MARK: - Thresholds are the plan's, not the code's (D1)

    func testTheSameEffortIsHardUnderOneCapAndEasyUnderAHigherOne() throws {
        // A steady hour at 168 bpm. Under a 150 bpm cap that is zone 4 throughout and a
        // hard session; under a 175 bpm cap the identical run is aerobic. Nothing about
        // the workout changed — only the plan's opinion of it.
        let workout = try runWorkout()
        let input = try DerivedMetricsInput(
            workout: workout,
            heartRateSeries: MetricsFixture.series([(0, 168), (3_600, 168)])
        )

        let strictPlan = try Fixture.plan(version: 1, heartRateCapBPM: 150)
        let relaxedPlan = try Fixture.plan(version: 2, heartRateCapBPM: 175)

        let underStrictCap = try DerivedMetricsCalculator.compute(input, plan: strictPlan)
        let underRelaxedCap = try DerivedMetricsCalculator.compute(input, plan: relaxedPlan)

        XCTAssertEqual(try classify(workout, underStrictCap, plan: strictPlan), .hard)
        XCTAssertEqual(try classify(workout, underRelaxedCap, plan: relaxedPlan), .easy)
    }

    func testAStricterPolicyCanBeAskedForWithoutTouchingTheClassifier() throws {
        // The 5%-in-zone-4 hilly easy run, read by a policy that calls 4% hard.
        let hilly: [(HeartRateZone, Double)] = [(.two, 3_420), (.four, 180)]
        let strict = try WorkoutClassificationPolicy(
            longRunDistanceFraction: 0.85,
            fragmentDistanceFraction: 0.25,
            hardZoneFloor: .four,
            hardZoneTimeFraction: 0.04
        )
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: hilly), policy: strict), .hard)
    }

    // MARK: - The ordering constraint with drift

    func testClassificationDoesNotChangeWhenDriftIsPresent() throws {
        // Drift is computed *from* the classification (`DerivedMetricsCalculator`), so a
        // classifier reading it would close a cycle. Same profile, wildly different
        // drift, same answer — for an easy run and for a hard one.
        let easy = WorkoutClassifierTests.underTheCap
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: easy)), .easy)
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: easy, drift: 0.01)), .easy)
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: easy, drift: 0.40)), .easy)

        let hard: [(HeartRateZone, Double)] = [(.two, 1_800), (.five, 1_800)]
        XCTAssertEqual(try classify(runWorkout(), metrics(zones: hard, averageBPM: 165, maximumBPM: 185)), .hard)
        let drifting = try metrics(zones: hard, averageBPM: 165, maximumBPM: 185, drift: 0.40)
        XCTAssertEqual(try classify(runWorkout(), drifting), .hard)
    }

    func testTheIngestionRoundTripReachesAFixedPoint() throws {
        // Ingestion's intended flow: compute metrics unclassified, classify from them,
        // recompute with the classification supplied. The second pass adds drift; the
        // classification it produces must be the same one that unlocked it, or the
        // sequence would depend on how many times it was run.
        let plan = try Fixture.plan()
        let workout = try runWorkout(durationSeconds: 3_600, distanceMeters: 9_000)
        let firstPass = try DerivedMetricsCalculator.compute(
            DerivedMetricsInput(workout: workout, heartRateSeries: MetricsFixture.series([(0, 130), (3_600, 148)])),
            plan: plan
        )
        XCTAssertNil(firstPass.heartRateDriftFraction)

        let classification = try classify(workout, firstPass, plan: plan)
        XCTAssertEqual(classification, .easy)

        let secondPass = try DerivedMetricsCalculator.compute(
            DerivedMetricsInput(
                workout: workout,
                heartRateSeries: MetricsFixture.series([(0, 130), (3_600, 148)]),
                classification: classification
            ),
            plan: plan
        )
        XCTAssertNotNil(secondPass.heartRateDriftFraction)
        XCTAssertEqual(try classify(workout, secondPass, plan: plan), classification)
    }

    // MARK: - Guards against classifying the wrong thing

    func testMetricsBelongingToAnotherWorkoutAreRejected() throws {
        assertThrows(.inconsistent, try self.classify(self.runWorkout(), self.metrics(
            zones: WorkoutClassifierTests.underTheCap,
            workoutID: Fixture.otherWorkoutID
        )))
    }

    func testMetricsComputedAgainstAnotherPlanVersionAreRejected() throws {
        // Time-above-cap and the zone splits only mean anything against the cap they were
        // measured with; reading v2's numbers against v1's plan would be reading a
        // different plan's discipline into this run.
        assertThrows(.inconsistent, try self.classify(self.runWorkout(), self.metrics(
            zones: WorkoutClassifierTests.underTheCap,
            planVersion: 2
        )))
    }

    // MARK: - Arc week arithmetic

    private func week(_ year: Int, _ month: Int, _ day: Int, from start: CalendarDay) throws -> Int? {
        WorkoutClassifier.arcWeekIndex(for: try Fixture.day(year, month, day), effectiveFrom: start)
    }

    func testTheArcWeekAdvancesInSevenDayBlocksFromThePlansEffectiveDate() throws {
        let start = try Fixture.day(2026, 1, 1)
        XCTAssertEqual(WorkoutClassifier.arcWeekIndex(for: start, effectiveFrom: start), 1)
        XCTAssertEqual(try week(2026, 1, 7, from: start), 1)
        XCTAssertEqual(try week(2026, 1, 8, from: start), 2)
        // 2026-04-20 is the fixture plan's goal day: 109 days out, so week 16 — the
        // "16-week arc" of D1 lands where the plan says it should.
        XCTAssertEqual(try week(2026, 4, 20, from: start), 16)
        XCTAssertNil(try week(2025, 12, 31, from: start))
    }

    func testTheArcWeekCountsTheLeapDay() throws {
        // 2028 is a leap year, so 2028-02-28 to 2028-03-05 is six days, not five: still
        // week 1. Getting this wrong would shift a whole training block's long-run asks
        // by a week, every fourth year.
        let start = try Fixture.day(2028, 2, 28)
        XCTAssertEqual(try week(2028, 3, 5, from: start), 1)
        XCTAssertEqual(try week(2028, 3, 6, from: start), 2)
    }

    // MARK: - Policy

    func testAPolicyCannotAskForMoreThanAllOfTheRun() throws {
        assertThrows(.outOfRange, try WorkoutClassificationPolicy(
            longRunDistanceFraction: 0.85,
            fragmentDistanceFraction: 0.25,
            hardZoneFloor: .four,
            hardZoneTimeFraction: 1.5
        ))
    }

    func testAPolicySurvivesASerializationRoundTrip() throws {
        // It is Codable so that a future plan version can carry it as data rather than
        // this file carrying it as constants.
        let encoded = try JSONEncoder().encode(CodableBox(wrapped: WorkoutClassificationPolicy.default))
        let decoded = try JSONDecoder().decode(CodableBox<WorkoutClassificationPolicy>.self, from: encoded)
        XCTAssertEqual(decoded.wrapped, .default)
    }
}
