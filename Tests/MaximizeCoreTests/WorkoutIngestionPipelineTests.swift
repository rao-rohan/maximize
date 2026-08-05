import XCTest
import Foundation
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// FR-0.5, D2, D8, R8 and R11, exercised without a health store, a device or an API key.
///
/// The pipeline is the one place in this product where every piece meets, and it is also
/// the place whose failures are invisible: a run that never appears, a score that never
/// arrives, a queue that quietly stops draining. None of those has a symptom on a device
/// either — nothing crashes and nothing is logged that a person would go looking for. So
/// the orchestration was pushed into the core, and this file drives it against fakes that
/// can be made to fail in ways a real store never will on demand.
final class WorkoutIngestionPipelineTests: XCTestCase {

    // MARK: - The happy path

    func testAWorkoutIsStoredMeasuredClassifiedAndScored() async throws {
        let harness = try Harness()

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])

        let metrics = try XCTUnwrap(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertEqual(metrics.planVersion, try PlanVersion(1))
        XCTAssertEqual(metrics.averageHeartRateBPM, 140)

        let score = try XCTUnwrap(harness.store.storedScore(forWorkout: harness.workout.id))
        XCTAssertEqual(score.value.points, 92)
        XCTAssertEqual(score.actualClassification, .easy)
        XCTAssertEqual(score.rubricBandIdentifier, "easy.onCap.lowDrift")
        XCTAssertEqual(score.scoredAt, Harness.scoredAt)
        XCTAssertTrue(harness.diagnostics.reported.isEmpty)
    }

    func testTheHeartRateCurveAndRouteAreStoredWholeBesideTheMetrics() async throws {
        // D7: the curves are records in their own right, not something the detail view
        // re-derives from the metrics.
        let harness = try Harness(routePoints: 3)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.allSeries.count, 1)
        XCTAssertEqual(harness.store.allSeries.first?.samples.count, 3)
        XCTAssertEqual(harness.store.allRoutes.first?.points.count, 3)
    }

    func testMetricsAreRecomputedOnceTheClassificationIsKnown() async throws {
        // MAX-012 gates drift on classification and MAX-013 reads the metrics, so the
        // pipeline computes, classifies, and computes again. Skipping the second pass
        // would leave drift nil — which is observable here, because the §10.3 band that
        // matches this run *requires* a drift figure and the fallback band does not.
        let harness = try Harness()

        try await harness.pipeline.ingest(harness.workout)

        let metrics = try XCTUnwrap(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertNotNil(metrics.heartRateDriftFraction, "drift is only computed once the run is known to be easy")
        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id)?.rubricBandIdentifier, "easy.onCap.lowDrift")
    }

    // MARK: - R11: a poison pill must not wedge the queue

    func testAWorkoutThatCanNeverBeStoredIsAbandonedRatherThanRethrownForever() async throws {
        // The failure this is about: `ingest` throwing leaves the anchor where it was, so
        // the same workout is refetched and rethrown on every wake, forever, and capture
        // stops. A permanent failure has to end in `ingest` *returning*.
        let harness = try Harness()
        harness.store.failWorkoutStore(
            of: harness.workout.id,
            with: DomainError.inconsistent(reason: "unstorable")
        )

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertTrue(harness.store.storedWorkouts.isEmpty)
        XCTAssertEqual(harness.diagnostics.reported, [.workoutAbandoned(step: .storingTheWorkout)])
    }

    func testAPoisonWorkoutDoesNotBlockTheWorkoutsBehindIt() async throws {
        // The end-to-end version, driven through the real MAX-031 ingester: a batch whose
        // first workout can never be stored must still leave the anchor advanced and the
        // second workout captured.
        let harness = try Harness()
        let poison = try Fixture.workout(id: Fixture.otherWorkoutID)
        harness.store.failWorkoutStore(of: poison.id, with: DomainError.inconsistent(reason: "unstorable"))

        let fetcher = FakeWorkoutFetcher()
        let anchorStore = InMemoryWorkoutQueryAnchorStore()
        let batchAnchor = WorkoutQueryAnchor(opaqueData: Data([7]))
        fetcher.enqueue(try WorkoutFetchBatch(workouts: [poison, harness.workout], anchor: batchAnchor))

        let ingester = AnchoredWorkoutIngester(
            fetcher: fetcher,
            anchorStore: anchorStore,
            sink: harness.pipeline
        )

        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        XCTAssertEqual(anchorStore.savedAnchors, [batchAnchor], "the anchor must move past a workout that can never be handled")
    }

    func testAStoreThatCannotWriteAtAllPinsTheAnchorInstead() async throws {
        // The other half of the split, and the reason it is a split rather than a
        // counter. A store that cannot write is not a fact about this workout: it is a
        // full disk or an unavailable CloudKit, it is transient, and giving up on the
        // workout would turn a recoverable stall into permanent loss.
        let harness = try Harness()
        harness.store.failWorkoutStores(with: InMemoryWorkoutStore.Failure.storageUnavailable)

        let fetcher = FakeWorkoutFetcher()
        let anchorStore = InMemoryWorkoutQueryAnchorStore()
        fetcher.enqueue(try WorkoutFetchBatch(workouts: [harness.workout], anchor: WorkoutQueryAnchor(opaqueData: Data([7]))))

        let ingester = AnchoredWorkoutIngester(fetcher: fetcher, anchorStore: anchorStore, sink: harness.pipeline)

        do {
            try await ingester.ingestPendingWorkouts()
            XCTFail("a store that could not write must not be reported as a handled workout")
        } catch {
            XCTAssertEqual(error as? InMemoryWorkoutStore.Failure, .storageUnavailable)
        }
        XCTAssertTrue(anchorStore.savedAnchors.isEmpty, "the anchor must stay put so the workout comes back")
    }

    func testEveryContentFailureLeavesTheWorkoutStoredAndTheAnchorFree() async throws {
        // The structural claim, stated as a test: no amount of bad *content* can make
        // `ingest` throw. Each of these would be a permanent, deterministic failure if it
        // were allowed to propagate.
        let cases: [(String, (Harness) -> Void)] = [
            ("no plan authored", { $0.store.setPlanCalendar(nil) }),
            ("plan read fails", { $0.store.failPlanReads(with: InMemoryWorkoutStore.Failure.storageUnavailable) }),
            ("sample fetch fails", { $0.samples.failNextHeartRateFetch(with: InMemoryWorkoutStore.Failure.storageUnavailable) }),
            ("metrics cannot be stored", { $0.store.failMetricStores(with: InMemoryWorkoutStore.Failure.storageUnavailable) }),
            ("model unavailable", { $0.model.failAllCalls(with: InMemoryWorkoutStore.Failure.storageUnavailable) }),
            ("model reply is nonsense", { $0.model.setReply("I would rather not say.") }),
            ("score cannot be stored", { $0.store.failScoreStores(with: InMemoryWorkoutStore.Failure.storageUnavailable) }),
        ]

        for (name, breakIt) in cases {
            let harness = try Harness()
            breakIt(harness)

            try await harness.pipeline.ingest(harness.workout)

            XCTAssertEqual(
                harness.store.storedWorkouts.map(\.id),
                [harness.workout.id],
                "\(name): the workout must still be captured"
            )
        }
    }

    // MARK: - An already-recorded auto-score is success

    func testAReplayedWorkoutKeepsItsOriginalScoreAndDoesNotFail() async throws {
        // D8 on a workout that has come round again — which is normal here, not exotic:
        // dedupe absorbs replays by design, and a lost anchor re-delivers a whole
        // backfill window. Treating this as an error would pin the anchor forever through
        // the one path the pipeline is guaranteed to take.
        let harness = try Harness()
        try await harness.pipeline.ingest(harness.workout)
        let firstScore = try XCTUnwrap(harness.store.storedScore(forWorkout: harness.workout.id))

        harness.model.setReply(FakeScoringModel.acceptableReply(score: 99, rationale: "A second opinion."))
        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id), firstScore)
        XCTAssertEqual(harness.model.callCount, 1, "a workout that already has a score is not re-scored")
        XCTAssertTrue(harness.diagnostics.reported.isEmpty, "a replay is normal operation, not a tolerated gap")
    }

    func testARaceThatLosesToAnotherScorerIsTreatedAsSuccess() async throws {
        // The narrow window the check above cannot close: the ledger read said unscored,
        // and by the time the write happened someone else had recorded one. D8 says the
        // score already written is the permanent one, so there is nothing to repair and
        // nothing to report.
        let harness = try Harness()
        harness.model.onCall { [store = harness.store, workoutID = harness.workout.id] in
            if let planted = try? Fixture.score(points: 88, workoutID: workoutID) {
                store.seedScore(planted)
            }
        }

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id)?.value.points, 88)
        XCTAssertTrue(harness.diagnostics.reported.isEmpty)
    }

    func testAReplayedWorkoutIsNotStoredTwice() async throws {
        // FR-0.5 through the ingester's own guard: `hasIngestedWorkout` answers from the
        // same store `ingest` writes to, so the second delivery never reaches `ingest`.
        let harness = try Harness()
        let fetcher = FakeWorkoutFetcher()
        let anchorStore = InMemoryWorkoutQueryAnchorStore()
        fetcher.enqueue(
            try WorkoutFetchBatch(workouts: [harness.workout], anchor: WorkoutQueryAnchor(opaqueData: Data([1]))),
            try WorkoutFetchBatch(workouts: [harness.workout], anchor: WorkoutQueryAnchor(opaqueData: Data([2])))
        )
        let ingester = AnchoredWorkoutIngester(fetcher: fetcher, anchorStore: anchorStore, sink: harness.pipeline)

        try await ingester.ingestPendingWorkouts()
        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(harness.store.storedWorkouts.count, 1)
        XCTAssertEqual(harness.store.workoutWriteCount, 1)
        XCTAssertEqual(harness.samples.stepCountRequestCount, 1, "a deduped workout is not extracted again")
    }

    // MARK: - Scoring failure is not ingestion failure

    func testAWorkoutRecordedBeforeAnAPIKeyExistsIsStoredComplete() async throws {
        // No key is the app's state the moment it is installed. If this failed ingestion,
        // every run recorded before the athlete opens Settings would be lost.
        let harness = try Harness()
        harness.model.failAllCalls(with: InMemoryWorkoutStore.Failure.storageUnavailable)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        XCTAssertNotNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.store.allSeries.count, 1)
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.diagnostics.reported, [.leftUnscored(reason: .modelUnavailable)])
    }

    func testAnUnscoredWorkoutCanBeScoredLater() async throws {
        // The lazy path R8 asks for, and the state MAX-041 is building the screen for.
        let harness = try Harness()
        harness.model.failAllCalls(with: InMemoryWorkoutStore.Failure.storageUnavailable)
        try await harness.pipeline.ingest(harness.workout)
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))

        harness.model.stopFailing()
        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id)?.value.points, 92)
    }

    func testCompletingAnAlreadyScoredWorkoutCostsNothing() async throws {
        // A screen calls this on appear without deciding whether the run needs scoring,
        // so "already scored" has to be free — not a HealthKit round trip per view.
        let harness = try Harness()
        try await harness.pipeline.ingest(harness.workout)
        let requestsAfterIngestion = harness.samples.receivedHeartRateRequests.count

        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        XCTAssertEqual(harness.samples.receivedHeartRateRequests.count, requestsAfterIngestion)
        XCTAssertEqual(harness.model.callCount, 1)
    }

    func testAWorkoutCapturedBeforeAnyPlanExistsIsScoredOnceAPlanIsAuthored() async throws {
        // A plan cannot be resolved, so nothing can be measured — there is no cap to
        // measure against. The run is still a first-class record, and the lazy path
        // completes it when the plan arrives.
        let harness = try Harness()
        harness.store.setPlanCalendar(nil)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        // MAX-034: the curve is a fact about the run, not about the plan, so it is
        // captured and stored even though there is nothing yet to measure it against.
        XCTAssertEqual(harness.store.allSeries.map(\.workoutID), [harness.workout.id])
        XCTAssertNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.diagnostics.reported, [.storedWithoutPlan(reason: .noPlanAuthored)])

        harness.store.setPlanCalendar(try PlanCalendar([ScoringFixture.plan()]))
        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        XCTAssertNotNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertNotNil(harness.store.storedScore(forWorkout: harness.workout.id))
    }

    func testAWorkoutFromBeforeThePlanBeganIsStoredButNotScored() async throws {
        // `PlanCalendar` answers nil for a day preceding every version rather than
        // inventing an ask, and a score against no plan would be a number with no stated
        // meaning (`ScoringError.noPlanInEffect`).
        let harness = try Harness()
        let earlyPlan = try Plan(
            version: PlanVersion(1),
            effectiveFrom: CalendarDay(iso8601: "2026-06-01"),
            weeklyTemplate: Fixture.weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: ScoringFixture.workedExampleRubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
        harness.store.setPlanCalendar(try PlanCalendar([earlyPlan]))

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        // MAX-034: unlike `.noPlanAuthored` above, this reason never resolves — MAX-011
        // forbids a later plan version from opening earlier than one that already
        // exists — but the curve is not held hostage to that either.
        XCTAssertEqual(harness.store.allSeries.map(\.workoutID), [harness.workout.id])
        XCTAssertEqual(harness.diagnostics.reported, [.storedWithoutPlan(reason: .workoutPredatesEveryPlan)])
    }

    // MARK: - MAX-034: samples are captured independently of plan coverage

    func testAWorkoutOnADayNoPlanGovernsStillGetsItsHeartRateSeriesAndRouteStored() async throws {
        // The bug this ticket fixes: `enrich` used to return before
        // `WorkoutSampleExtractor.extract` ever ran when no plan governed the workout's
        // day, so the HR curve (and the route) were never fetched or stored — a loss
        // MAX-031's advancing anchor makes permanent. The curve is a fact about the run,
        // not about the plan, and must survive regardless.
        let harness = try Harness(routePoints: 3)
        harness.store.setPlanCalendar(nil)

        try await harness.pipeline.ingest(harness.workout)

        let series = try XCTUnwrap(harness.store.allSeries.first)
        XCTAssertEqual(series.workoutID, harness.workout.id)
        XCTAssertEqual(series.samples.count, 3)
        XCTAssertEqual(harness.store.allRoutes.first?.points.count, 3)
        // And, symmetrically, no derived metrics — those genuinely have nothing to be
        // measured against.
        XCTAssertNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))
    }

    func testAPartialSampleFailureIsReportedAlongsideNoPlanAndDoesNotThrow() async throws {
        // Two independent gaps in one enrichment: a route that failed to fetch, and a
        // day no plan governs. Neither may throw (R11), and the diagnostics for each
        // must stay distinguishable rather than collapsing into one.
        let harness = try Harness(routePoints: 3)
        harness.samples.failRouteFetch(with: InMemoryWorkoutStore.Failure.storageUnavailable)
        harness.store.setPlanCalendar(nil)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.allSeries.first?.samples.count, 3, "the HR series is unaffected by the route failing")
        XCTAssertNil(harness.store.allRoutes.first)
        XCTAssertEqual(
            Set(harness.diagnostics.reported),
            [.sampleExtraction(.routeFetchFailed), .storedWithoutPlan(reason: .noPlanAuthored)]
        )
    }

    func testARubricWithNoMatchingBandLeavesTheWorkoutUnscoredWithoutCallingTheModel() async throws {
        // `ScoringError.noBandMatched` is deterministic in the plan data: the repair is a
        // new plan version, not a retry, and burning a model call on it would be the
        // retry loop around an unscoreable workout that R11 warns about.
        let harness = try Harness()
        let emptyRubric = try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: "long.only",
                    appliesTo: [.long],
                    conditions: [],
                    scoreRange: ScoreRange(lowest: 0, highest: 100),
                    rationale: "Nothing here applies to an easy day."
                ),
            ]
        )
        harness.store.setPlanCalendar(try PlanCalendar([ScoringFixture.plan(rubric: emptyRubric)]))

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertNotNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.model.callCount, 0)
        XCTAssertEqual(harness.diagnostics.reported, [.leftUnscored(reason: .rubricCouldNotBeApplied)])
    }

    // MARK: - C2: durability before acknowledgement

    func testTheWorkoutIsDurableBeforeTheModelIsEverCalled() async throws {
        // C2, and the reason R8 is survivable: a wake killed mid-scoring costs a score,
        // never a run.
        let harness = try Harness()
        let workoutWasStored = Locked(false)
        harness.model.onCall { [store = harness.store, id = harness.workout.id] in
            workoutWasStored.set(store.storedWorkouts.contains { $0.id == id })
        }

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertTrue(workoutWasStored.value, "the model must not be called before the workout is durable")
    }

    func testMetricsAreDurableBeforeTheModelIsEverCalled() async throws {
        let harness = try Harness()
        let metricsWereStored = Locked(false)
        harness.model.onCall { [store = harness.store, id = harness.workout.id] in
            metricsWereStored.set(store.storedMetrics(forWorkout: id) != nil)
        }

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertTrue(metricsWereStored.value)
    }

    // MARK: - R8: the wake budget

    func testAModelCallThatOverrunsTheWakeBudgetLeavesAStoredUnscoredWorkout() async throws {
        let harness = try Harness(
            policy: try IngestionPipelinePolicy(scoringBudgetSeconds: 0.05, scoringAttempts: 1)
        )
        harness.model.setDelaySeconds(30)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        XCTAssertNotNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.diagnostics.reported, [.leftUnscored(reason: .scoringBudgetExceeded)])
    }

    func testTheLazyPathIsNotBoundedByTheWakeBudget() async throws {
        // Nothing is queued behind a user-initiated attempt, so the budget that protects
        // the rest of a wake's batch has nothing to protect.
        let harness = try Harness(
            policy: try IngestionPipelinePolicy(scoringBudgetSeconds: 0.05, scoringAttempts: 1)
        )
        harness.model.setDelaySeconds(0.2)
        try await harness.store.store(harness.workout)

        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        XCTAssertNotNil(harness.store.storedScore(forWorkout: harness.workout.id))
    }

    // MARK: - Re-asking the model

    func testAScoreOutsideTheBandIsReAskedOnce() async throws {
        // `WorkoutScorer`'s instruction says "a score outside it will be rejected and you
        // will be asked again". A promise made in a prompt that the caller does not keep
        // is a defect in the caller.
        let harness = try Harness()
        harness.model.enqueueReplies(
            FakeScoringModel.acceptableReply(score: 12),
            FakeScoringModel.acceptableReply(score: 95)
        )

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.model.callCount, 2)
        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id)?.value.points, 95)
    }

    func testTheModelIsNotAskedForeverWhenEveryReplyIsRejected() async throws {
        let harness = try Harness()
        harness.model.setReply(FakeScoringModel.acceptableReply(score: 12))

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.model.callCount, 2, "bounded by IngestionPipelinePolicy.scoringAttempts")
        XCTAssertNil(harness.store.storedScore(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.diagnostics.reported, [.leftUnscored(reason: .modelReplyRejected)])
    }

    // MARK: - Deletions

    func testADeletedWorkoutIsRemovedWithEverythingHangingOffIt() async throws {
        let harness = try Harness()
        try await harness.pipeline.ingest(harness.workout)

        try await harness.pipeline.discardWorkout(id: harness.workout.id)

        XCTAssertTrue(harness.store.storedWorkouts.isEmpty)
        XCTAssertTrue(harness.store.allMetrics.isEmpty)
        XCTAssertTrue(harness.store.allScores.isEmpty)
    }

    func testADeletionThatCanNeverSucceedIsAbandonedRatherThanRethrownForever() async throws {
        let harness = try Harness()
        harness.store.failDeletes(with: DomainError.inconsistent(reason: "undeletable"))

        try await harness.pipeline.discardWorkout(id: harness.workout.id)

        XCTAssertEqual(harness.diagnostics.reported, [.workoutAbandoned(step: .discardingTheWorkout)])
    }

    // MARK: - Diagnostics

    func testGapsInSampleExtractionAreForwardedRatherThanSwallowed() async throws {
        let harness = try Harness()
        harness.samples.failRouteFetch(with: InMemoryWorkoutStore.Failure.storageUnavailable)

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.diagnostics.reported, [.sampleExtraction(.routeFetchFailed)])
        XCTAssertNotNil(harness.store.storedScore(forWorkout: harness.workout.id), "a missing route does not stop a run being scored")
    }

    // MARK: - MAX-067: backfilling distance splits for pre-MAX-046 history

    func testABackfillPassRecomputesLegacyMetricsAndGainsSplitsWithoutTouchingTheScore() async throws {
        // Stands in for the athlete's actual device: a workout, scored, with metrics on
        // file that predate MAX-046 — `distanceSplitsComputed == false` is exactly what
        // `DerivedMetricsRecord`'s migration default produces for every existing row.
        let harness = try Harness()
        // A route exactly as long as `Fixture.workout()`'s recorded 10 km — the same
        // shape `DerivedMetricsCalculatorTests.matchingRoute()` uses — so the backfill
        // actually has something to cut up, rather than a track too short to trust.
        harness.samples.setRoute(RouteFetchResult(points: (0..<10).map { index in
            RawRoutePoint(
                date: Fixture.epoch.addingTimeInterval(Double(index) * 10),
                latitudeDegrees: Double(index) * (10_000.0 / 9) / MetricsFixture.metersPerLatitudeDegree,
                longitudeDegrees: 0,
                altitudeMeters: 50
            )
        }))
        try await harness.store.store(harness.workout)
        let legacyMetrics = try DerivedMetrics(
            workoutID: harness.workout.id,
            averageHeartRateBPM: 140,
            distanceSplitsComputed: false,
            planVersion: PlanVersion(1)
        )
        try await harness.store.store(legacyMetrics)
        let originalScore = try Fixture.score(points: 77, workoutID: harness.workout.id)
        harness.store.seedScore(originalScore)

        let outcome = await harness.pipeline.backfillDistanceSplits()

        XCTAssertEqual(outcome.workoutsProcessed, 1)
        XCTAssertEqual(outcome.workoutsRemaining, 0)
        let metrics = try XCTUnwrap(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertTrue(metrics.distanceSplitsComputed)
        XCTAssertNotNil(metrics.distanceSplits, "a routed run should gain a real breakdown")
        // D8: the auto-score is untouched, and the model is never asked again — the
        // enforcement point is `applyScore`'s existing ledger check, unmodified by this
        // ticket.
        XCTAssertEqual(harness.store.storedScore(forWorkout: harness.workout.id), originalScore)
        XCTAssertEqual(harness.model.callCount, 0)
    }

    func testABackfillPassDoesNotRetryARouteLessWorkoutForever() async throws {
        // The crux: a workout with no route (indoor, or pre-MAX-034) will produce nil
        // splits on every attempt, genuinely. One re-enrichment must be enough to stop it
        // being offered again — otherwise every launch re-fetches its HealthKit samples
        // for nothing, forever.
        let harness = try Harness() // no route
        try await harness.store.store(harness.workout)
        let legacyMetrics = try DerivedMetrics(
            workoutID: harness.workout.id,
            averageHeartRateBPM: 140,
            distanceSplitsComputed: false,
            planVersion: PlanVersion(1)
        )
        try await harness.store.store(legacyMetrics)

        let firstPass = await harness.pipeline.backfillDistanceSplits()
        XCTAssertEqual(firstPass.workoutsProcessed, 1)
        XCTAssertEqual(firstPass.workoutsRemaining, 0)
        let requestsAfterFirstPass = harness.samples.receivedHeartRateRequests.count

        let secondPass = await harness.pipeline.backfillDistanceSplits()

        XCTAssertEqual(secondPass.workoutsProcessed, 0, "already attempted, and the answer is still no splits")
        XCTAssertEqual(
            harness.samples.receivedHeartRateRequests.count,
            requestsAfterFirstPass,
            "a workout already marked distanceSplitsComputed must not be re-enriched"
        )
        let metrics = try XCTUnwrap(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertTrue(metrics.distanceSplitsComputed)
        XCTAssertNil(metrics.distanceSplits)
    }

    func testABackfillPassLeavesAlreadyBackfilledWorkoutsAlone() async throws {
        // The ordinary steady state once the backlog is drained: nothing is a candidate,
        // so nothing is touched.
        let harness = try Harness()
        try await harness.pipeline.ingest(harness.workout)
        let requestsBeforeBackfill = harness.samples.receivedHeartRateRequests.count

        let outcome = await harness.pipeline.backfillDistanceSplits()

        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertEqual(harness.samples.receivedHeartRateRequests.count, requestsBeforeBackfill)
    }

    func testABackfillPassIsBoundedByItsPolicyAndResumesOnTheNextPass() async throws {
        // Route-less on purpose: this test is about the cap and the carry-over, not about
        // what a split ends up containing.
        let harness = try Harness()
        let second = try Fixture.workout(id: Fixture.otherWorkoutID)
        try await harness.store.store(harness.workout)
        try await harness.store.store(second)
        for id in [harness.workout.id, second.id] {
            let legacy = try DerivedMetrics(workoutID: id, distanceSplitsComputed: false, planVersion: PlanVersion(1))
            try await harness.store.store(legacy)
        }
        let onePerPass = try DistanceSplitsBackfillPolicy(maxWorkoutsPerPass: 1)

        let firstPass = await harness.pipeline.backfillDistanceSplits(policy: onePerPass)
        XCTAssertEqual(firstPass.workoutsProcessed, 1)
        XCTAssertEqual(firstPass.workoutsRemaining, 1, "the wake budget must not do more than the policy allows")

        let secondPass = await harness.pipeline.backfillDistanceSplits(policy: onePerPass)
        XCTAssertEqual(secondPass.workoutsProcessed, 1, "the remainder is picked up by the next pass")
        XCTAssertEqual(secondPass.workoutsRemaining, 0)

        XCTAssertTrue(harness.store.allMetrics.allSatisfy(\.distanceSplitsComputed))
    }

    func testABackfillPassSkipsAWorkoutWithNoDerivedMetricsAtAll() async throws {
        // A workout stored without metrics (no plan governed its day, MAX-034) is not a
        // candidate: `DerivedMetricsCalculator` has nothing to compute against, backfilled
        // or not, and this is `storedWithoutPlan`'s territory, not MAX-067's.
        let harness = try Harness()
        harness.store.setPlanCalendar(nil)
        try await harness.pipeline.ingest(harness.workout)
        XCTAssertNil(harness.store.storedMetrics(forWorkout: harness.workout.id))

        let outcome = await harness.pipeline.backfillDistanceSplits()

        XCTAssertEqual(outcome, .nothingToDo)
    }

    // MARK: - Harness

    /// Everything wired the way the app wires it, with the health store, the model and
    /// the database replaced by fakes.
    private struct Harness {
        static let scoredAt = Date(timeIntervalSince1970: 1_767_312_000)

        let store: InMemoryWorkoutStore
        let samples: FakeWorkoutSampleFetcher
        let model: FakeScoringModel
        let diagnostics: IngestionPipelineDiagnosticRecorder
        let pipeline: WorkoutIngestionPipeline
        let workout: Workout

        /// `Fixture.epoch` is 2026-01-01, a Thursday, which `Fixture.weeklyTemplate()`
        /// prescribes as an easy 8 km — so the run below is an easy run on an easy day,
        /// the ordinary case §10.3's worked example is written around.
        init(
            policy: IngestionPipelinePolicy = .standard,
            beatsPerMinute: Double = 140,
            routePoints: Int = 0
        ) throws {
            let capturedWorkout = try Fixture.workout()
            let workoutStore = InMemoryWorkoutStore(planCalendar: try PlanCalendar([ScoringFixture.plan()]))
            let sampleFetcher = FakeWorkoutSampleFetcher()
            let scoringModel = FakeScoringModel()
            let recorder = IngestionPipelineDiagnosticRecorder()

            // Flat, so drift is zero and the run lands in the "held the cap" band without
            // the test having to reason about interpolation.
            //
            // Queued several times because `enqueueHeartRatePage` hands out one page per
            // call, while a real health store answers the same window with the same
            // samples however often it is asked. Re-extraction is a genuine path — the
            // lazy `completeIngestion` takes it — so the fake has to be faithful about it.
            let page = HeartRateSampleFetchPage(samples: [0.0, 1_800.0, 3_600.0].map {
                RawHeartRateSample(date: Fixture.epoch.addingTimeInterval($0), beatsPerMinute: beatsPerMinute)
            })
            for _ in 0..<4 {
                sampleFetcher.enqueueHeartRatePage(page)
            }
            sampleFetcher.setTotalStepCount(10_000)
            if routePoints > 0 {
                sampleFetcher.setRoute(RouteFetchResult(points: (0..<routePoints).map { index in
                    RawRoutePoint(
                        date: Fixture.epoch.addingTimeInterval(Double(index) * 60),
                        latitudeDegrees: 51.5 + Double(index) * 0.001,
                        longitudeDegrees: -0.12,
                        altitudeMeters: 10
                    )
                }))
            }

            workout = capturedWorkout
            store = workoutStore
            samples = sampleFetcher
            model = scoringModel
            diagnostics = recorder
            pipeline = WorkoutIngestionPipeline(
                workouts: workoutStore,
                scores: workoutStore,
                plans: workoutStore,
                samples: sampleFetcher,
                model: scoringModel,
                policy: policy,
                // UTC, so "which day was this run" is a fact of the fixture rather than of
                // the machine CI happens to run on.
                timeZone: { TimeZone(identifier: "UTC") ?? .gmt },
                now: { Harness.scoredAt },
                report: recorder.handler()
            )
        }
    }
}

/// A `Sendable` box for a value a test observes from inside a fake's callback.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        stored = newValue
    }
}
