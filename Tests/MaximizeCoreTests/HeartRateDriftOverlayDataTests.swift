import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-062: the cross-run HR-drift overlay (FR-3.3, D5).
///
/// The tests under `MARK: - Normalisation` are the point of this file. Everything about
/// this ticket that can be got wrong quietly is a resampling decision — what a bucket
/// means, what the percentage axis is measured against, and whether the answer depends on
/// how often the sensor happened to fire. Each is pinned here with hand-computed numbers
/// rather than by reading one off the implementation.
final class HeartRateDriftOverlayDataTests: XCTestCase {

    // MARK: - Fixtures

    /// A run starting `daysBeforeEpoch` days before `Fixture.epoch`, so a stack's recency
    /// ordering is unambiguous.
    private func makeWorkout(
        id: UUID,
        daysBeforeEpoch: Double,
        durationSeconds: Double,
        activityType: ActivityType
    ) throws -> Workout {
        let start = Fixture.epoch.addingTimeInterval(-daysBeforeEpoch * 86_400)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: 10_000,
            activeEnergyKilocalories: 700,
            hasRoute: activityType != .treadmillRunning,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 120)
        )
    }

    private func makeMetrics(id: UUID, driftFraction: Double?) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: id,
            averageHeartRateBPM: 140,
            maximumHeartRateBPM: 170,
            heartRateDriftFraction: driftFraction,
            planVersion: PlanVersion(1)
        )
    }

    /// - Parameter samples: nil means the run has no stored heart-rate series at all,
    ///   which is a first-class state here (see the type's documentation), not an empty
    ///   series — `HeartRateSeries` cannot be empty.
    private func makeCandidate(
        id: UUID = UUID(),
        daysBeforeEpoch: Double = 0,
        durationSeconds: Double = 3_600,
        activityType: ActivityType = .running,
        samples: [(Double, Double)]? = [(0, 130), (1_800, 150)],
        classification: WorkoutClassification? = .easy,
        driftFraction: Double? = 0.04
    ) throws -> HeartRateDriftOverlayData.Candidate {
        HeartRateDriftOverlayData.Candidate(
            workout: try makeWorkout(
                id: id,
                daysBeforeEpoch: daysBeforeEpoch,
                durationSeconds: durationSeconds,
                activityType: activityType
            ),
            series: try samples.map { try MetricsFixture.series($0, workoutID: id) },
            classification: classification,
            metrics: try makeMetrics(id: id, driftFraction: driftFraction)
        )
    }

    /// Two buckets keeps every expected value hand-computable, and drops the covered-span
    /// floor to 10 s so short fixture curves are not excluded for being short.
    private let twoBuckets = 2

    private let thirdWorkoutID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()

    // MARK: - Normalisation: the axis, the buckets, and what a bucket means

    /// Two runs of wildly different lengths land on the same axis with the same point
    /// count — the entire premise of FR-3.3.
    func testRunsOfDifferentDurationsShareOnePercentAxis() throws {
        let short = try makeCandidate(
            daysBeforeEpoch: 1,
            durationSeconds: 28 * 60,
            samples: (0...28).map { (Double($0) * 60, 140) }
        )
        let long = try makeCandidate(
            daysBeforeEpoch: 2,
            durationSeconds: 94 * 60,
            samples: (0...94).map { (Double($0) * 60, 140) }
        )

        let overlay = HeartRateDriftOverlayData(candidates: [short, long])

        XCTAssertEqual(overlay.curves.count, 2)
        for curve in overlay.curves {
            XCTAssertEqual(curve.points.count, HeartRateDriftOverlayData.defaultBucketCount)
            let first = try XCTUnwrap(curve.points.first)
            let last = try XCTUnwrap(curve.points.last)
            XCTAssertEqual(first.percentElapsed, 0.5, accuracy: 1e-9)
            XCTAssertEqual(last.percentElapsed, 99.5, accuracy: 1e-9)
        }
        // The runs stay distinguishable *as runs*: normalising the axis does not erase how
        // long each one actually was.
        XCTAssertEqual(Set(overlay.curves.map(\.coveredSeconds)), [1_680, 5_640])
    }

    /// A bucket carries the **time-weighted mean over its slice**, plotted at the slice's
    /// midpoint — not the curve's value sampled at a grid point.
    ///
    /// The fixture is a straight ramp from 100 bpm at 0 s to 200 bpm at 100 s. Split into
    /// two buckets, the first covers [0, 50] and averages (100 + 150) / 2 = 125; the
    /// second covers [50, 100] and averages (150 + 200) / 2 = 175. Point sampling at the
    /// midpoints happens to agree for a straight ramp, which is why the two sparse-sampling
    /// tests below are the ones that actually separate the readings.
    func testEachBucketIsTheTimeWeightedMeanOverItsSlicePlottedAtTheMidpoint() throws {
        let run = try makeCandidate(samples: [(0, 100), (100, 200)])
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        let curve = try XCTUnwrap(overlay.curves.first)
        XCTAssertEqual(curve.points.count, 2)
        XCTAssertEqual(curve.points[0].percentElapsed, 25, accuracy: 1e-9)
        XCTAssertEqual(curve.points[0].beatsPerMinute, 125, accuracy: 1e-9)
        XCTAssertEqual(curve.points[1].percentElapsed, 75, accuracy: 1e-9)
        XCTAssertEqual(curve.points[1].beatsPerMinute, 175, accuracy: 1e-9)
    }

    /// **Resampling does not depend on sampling density.** The same underlying ramp,
    /// captured as two samples and as eleven, normalises to exactly the same curve.
    /// HealthKit sampling is not uniform, and a normalisation that moved when the sensor
    /// got chattier would be measuring the sensor rather than the run.
    func testANormalizedCurveIsIndependentOfHowDenselyTheRunWasSampled() throws {
        let sparse = try makeCandidate(id: Fixture.workoutID, samples: [(0, 100), (100, 200)])
        let dense = try makeCandidate(
            id: Fixture.otherWorkoutID,
            samples: (0...10).map { (Double($0) * 10, 100 + Double($0) * 10) }
        )

        let sparseOverlay = HeartRateDriftOverlayData(candidates: [sparse], bucketCount: twoBuckets)
        let denseOverlay = HeartRateDriftOverlayData(candidates: [dense], bucketCount: twoBuckets)

        let sparseCurve = try XCTUnwrap(sparseOverlay.curves.first)
        let denseCurve = try XCTUnwrap(denseOverlay.curves.first)
        XCTAssertEqual(sparseCurve.points.count, denseCurve.points.count)
        for (left, right) in zip(sparseCurve.points, denseCurve.points) {
            XCTAssertEqual(left.percentElapsed, right.percentElapsed, accuracy: 1e-9)
            XCTAssertEqual(left.beatsPerMinute, right.beatsPerMinute, accuracy: 1e-9)
        }
    }

    /// Irregular sampling — a dense burst early, one long quiet stretch after — is weighted
    /// by *time*, so the burst does not outvote the stretch.
    ///
    /// The expectation is taken from `HeartRateCurve.timeWeightedMeanBPM` over the whole
    /// span, which `HeartRateCurveTests` pins independently. That is the assertion: the
    /// bucket agrees with the curve's own averaging, because resampling routes through the
    /// one interpolation model rather than inventing a second. A sample-*counting* mean
    /// would read about 155 here (eleven samples at 160, one at 100); the time-weighted
    /// answer is near 133, because the run spent 100 of its 110 seconds falling toward 100.
    func testABucketAgreesWithTheCurvesOwnTimeWeightedMeanOverThatSpan() throws {
        var pairs: [(Double, Double)] = (0...10).map { (Double($0), 160) }
        pairs.append((110, 100))

        let run = try makeCandidate(samples: pairs)
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: 1)

        let curve = HeartRateCurve(try MetricsFixture.series(pairs))
        let expected = try XCTUnwrap(curve.timeWeightedMeanBPM(from: 0, to: 110))

        let point = try XCTUnwrap(overlay.curves.first?.points.first)
        XCTAssertEqual(point.beatsPerMinute, expected, accuracy: 1e-9)
        XCTAssertEqual(point.percentElapsed, 50, accuracy: 1e-9)
        XCTAssertLessThan(point.beatsPerMinute, 140)
    }

    /// 0% is the curve's first sample and 100% its last — **not** the workout's start and
    /// end. The stored drift figure splits the curve's covered span at its midpoint, so
    /// anchoring the axis anywhere else would put the 50% gridline somewhere other than the
    /// split the number printed beside it was computed at.
    func testThePercentAxisSpansTheCurveNotTheWorkoutDuration() throws {
        // A one-hour workout whose HR series only covers 600 s → 1200 s.
        let run = try makeCandidate(durationSeconds: 3_600, samples: [(600, 100), (1_200, 200)])
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        let curve = try XCTUnwrap(overlay.curves.first)
        XCTAssertEqual(curve.coveredSeconds, 600, accuracy: 1e-9)
        // Identical to the [(0, 100), (100, 200)] ramp above: only the shape survives.
        XCTAssertEqual(curve.points[0].beatsPerMinute, 125, accuracy: 1e-9)
        XCTAssertEqual(curve.points[1].beatsPerMinute, 175, accuracy: 1e-9)
    }

    // MARK: - The drift figure is stated, never derived (D2)

    /// The mirror of `HeartRateChartDataTests`'s pin: the stored figure survives even when
    /// it disagrees with what the curve would imply. If this initializer ever starts
    /// computing drift from `points`, this test starts failing — which is why the fixture
    /// passes a deliberately implausible value rather than a realistic one.
    func testDriftFractionIsTheStoredFigureVerbatimEvenWhenItContradictsTheCurve() throws {
        // A curve that plainly rose across the run, paired with a stored *negative* drift.
        let run = try makeCandidate(samples: [(0, 100), (600, 180)], driftFraction: -0.99)
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        XCTAssertEqual(overlay.curves.first?.driftFraction, -0.99)
    }

    func testDriftFractionStaysNilWhenNoneWasStored() throws {
        let run = try makeCandidate(driftFraction: nil)
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        XCTAssertNil(overlay.curves.first?.driftFraction)
        XCTAssertNil(overlay.curves.first?.formattedDriftPercent)
    }

    func testFormattedDriftPercentMatchesTheSummaryTilesRounding() throws {
        let run = try makeCandidate(driftFraction: 0.0312)
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        XCTAssertEqual(overlay.curves.first?.formattedDriftPercent, "+3.1")
    }

    // MARK: - A missing curve is ordinary, and is said rather than drawn

    func testARunWithNoStoredSeriesIsExcludedAndNotDrawnFlat() throws {
        let run = try makeCandidate(samples: nil)
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertNil(overlay.bpmAxisDomain)
        XCTAssertEqual(overlay.excluded.map(\.reason), [.noHeartRateSeries])
        XCTAssertEqual(overlay.candidateCount, 1)
    }

    func testAnUnscoredRunIsExcludedAsUnscoredRatherThanReclassifiedHere() throws {
        let run = try makeCandidate(classification: nil)
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertEqual(overlay.excluded.map(\.reason), [.notYetScored])
    }

    func testHardAndOtherSessionsAreExcludedBecauseDriftIsNotMeaningfulOnThem() throws {
        let hard = try makeCandidate(id: Fixture.workoutID, classification: .hard)
        let other = try makeCandidate(id: Fixture.otherWorkoutID, classification: .other)
        let overlay = HeartRateDriftOverlayData(candidates: [hard, other])

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertEqual(overlay.count(of: .driftNotMeaningfulForThisSession), 2)
    }

    func testLongRunsAreStackedAlongsideEasyOnes() throws {
        let easy = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, classification: .easy)
        let long = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, classification: .long)
        let overlay = HeartRateDriftOverlayData(candidates: [easy, long])

        XCTAssertEqual(Set(overlay.curves.map(\.classification)), [.easy, .long])
    }

    /// FR-0.6: an indoor run has no route and is not a degraded case here. Nothing in the
    /// overlay reads `Workout.hasRoute`, and this test exists to keep it that way.
    func testATreadmillRunIsStackedLikeAnyOther() throws {
        let run = try makeCandidate(activityType: .treadmillRunning)
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertEqual(overlay.curves.count, 1)
    }

    // MARK: - A run far shorter than the others

    func testACurveCoveringLessThanTheFloorIsExcludedRatherThanStretched() throws {
        // 400 s of heart-rate data, against a 100-bucket floor of 500 s.
        let run = try makeCandidate(samples: [(0, 130), (400, 150)])
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertEqual(overlay.excluded.map(\.reason), [.curveTooShortToNormalize])
    }

    func testACurveExactlyAtTheFloorIsStacked() throws {
        let run = try makeCandidate(samples: [(0, 130), (500, 150)])
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertEqual(overlay.curves.count, 1)
        XCTAssertEqual(overlay.minimumCoveredSeconds, 500, accuracy: 1e-9)
    }

    /// A single-sample series covers no span at all. It lands in the same bucket as a
    /// too-short curve rather than becoming a one-point line or a flat zero.
    func testASingleSampleSeriesHasNoShapeToNormalizeAndIsExcluded() throws {
        let run = try makeCandidate(samples: [(30, 145)])
        let overlay = HeartRateDriftOverlayData(candidates: [run])

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertEqual(overlay.excluded.map(\.reason), [.curveTooShortToNormalize])
    }

    // MARK: - Ordering, ranking, and the stack limit

    func testCurvesAreOrderedOldestFirstSoTheMostRecentDrawsOnTop() throws {
        let newest = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1)
        let oldest = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 9)
        let overlay = HeartRateDriftOverlayData(candidates: [newest, oldest])

        XCTAssertEqual(overlay.curves.map(\.workoutID), [Fixture.otherWorkoutID, Fixture.workoutID])
        XCTAssertEqual(overlay.curves.map(\.recencyRank), [1, 0])
        XCTAssertEqual(overlay.curves.last?.isMostRecent, true)
    }

    func testOnlyTheMostRecentQualifyingRunsAreStackedAndTheRestAreCounted() throws {
        let candidates = try (0..<5).map { index in
            try makeCandidate(daysBeforeEpoch: Double(index))
        }
        let overlay = HeartRateDriftOverlayData(candidates: candidates, stackLimit: 2)

        XCTAssertEqual(overlay.curves.count, 2)
        XCTAssertEqual(overlay.count(of: .beyondStackLimit), 3)
        XCTAssertEqual(overlay.candidateCount, 5)
        // The two stacked are the two most recent (fewest days before the epoch).
        XCTAssertEqual(overlay.curves.map(\.start).max(), Fixture.epoch)
    }

    /// FR-3.3's "selectable which runs are stacked": hiding a recent run promotes the
    /// next-oldest qualifying one into the stack rather than leaving a gap.
    func testHidingARecentRunPromotesAnOlderOneIntoTheStack() throws {
        let newest = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 0)
        let middle = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 1)
        let oldest = try makeCandidate(id: thirdWorkoutID, daysBeforeEpoch: 2)

        let unfiltered = HeartRateDriftOverlayData(candidates: [newest, middle, oldest], stackLimit: 2)
        XCTAssertEqual(Set(unfiltered.curves.map(\.workoutID)), [Fixture.workoutID, Fixture.otherWorkoutID])

        let filtered = HeartRateDriftOverlayData(
            candidates: [newest, middle, oldest],
            hiddenWorkoutIDs: [Fixture.workoutID],
            stackLimit: 2
        )
        XCTAssertEqual(Set(filtered.curves.map(\.workoutID)), [Fixture.otherWorkoutID, thirdWorkoutID])
        XCTAssertEqual(filtered.count(of: .hiddenByAthlete), 1)
        XCTAssertEqual(filtered.count(of: .beyondStackLimit), 0)
    }

    /// Two runs recorded at the same instant must stack in the same order every time — a
    /// chart that reshuffled itself between two reads of one interval would be its own
    /// bug. The tie-break is the identifier, so the ordering is a property of the data
    /// rather than of the order the repository happened to return.
    func testRunsSharingAStartInstantStackDeterministically() throws {
        let first = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 3)
        let second = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 3)

        let oneWay = HeartRateDriftOverlayData(candidates: [first, second])
        let otherWay = HeartRateDriftOverlayData(candidates: [second, first])

        XCTAssertEqual(oneWay.curves.map(\.workoutID), otherWay.curves.map(\.workoutID))
    }

    func testExcludedRunsAreListedMostRecentFirst() throws {
        let recent = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, samples: nil)
        let older = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 5, samples: nil)
        let overlay = HeartRateDriftOverlayData(candidates: [older, recent])

        XCTAssertEqual(overlay.excluded.map(\.workoutID), [Fixture.workoutID, Fixture.otherWorkoutID])
    }

    // MARK: - Axis domain

    func testTheAxisDomainCoversEveryStackedCurve() throws {
        let low = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, samples: [(0, 110), (600, 120)])
        let high = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, samples: [(0, 170), (600, 180)])
        let overlay = HeartRateDriftOverlayData(candidates: [low, high], bucketCount: twoBuckets)

        let domain = try XCTUnwrap(overlay.bpmAxisDomain)
        XCTAssertLessThan(domain.lowerBound, 112.5)
        XCTAssertGreaterThan(domain.upperBound, 177.5)
    }

    func testTheAxisDomainIsWellFormedWhenEveryStackedCurveIsFlat() throws {
        let run = try makeCandidate(samples: [(0, 140), (600, 140)])
        let overlay = HeartRateDriftOverlayData(candidates: [run], bucketCount: twoBuckets)

        let domain = try XCTUnwrap(overlay.bpmAxisDomain)
        XCTAssertLessThan(domain.lowerBound, domain.upperBound)
    }

    // MARK: - Legibility with N curves

    func testTheMostRecentCurveIsAlwaysFullStrengthWhateverTheStackSize() {
        for count in 1...30 {
            XCTAssertEqual(HeartRateDriftOverlayData.contextOpacity(recencyRank: 0, stackedCount: count), 1)
        }
    }

    /// With six curves the ramp spans its whole range and never reaches invisibility — the
    /// oldest run is the "before" in a before-and-after and has to stay readable.
    func testTheRampFadesMonotonicallyAndFloorsAboveInvisible() {
        let stackedCount = 6
        let opacities = (0..<stackedCount).map {
            HeartRateDriftOverlayData.contextOpacity(recencyRank: $0, stackedCount: stackedCount)
        }

        for index in 1..<opacities.count {
            XCTAssertLessThan(opacities[index], opacities[index - 1])
        }
        XCTAssertEqual(opacities[1], HeartRateDriftOverlayData.newestContextOpacity, accuracy: 1e-9)
        XCTAssertEqual(opacities[stackedCount - 1], HeartRateDriftOverlayData.oldestContextOpacity, accuracy: 1e-9)
    }

    /// The ramp's endpoints do not move with the stack size: a thirty-curve stack fades
    /// through the same range as a six-curve one, in finer steps. That is what keeps the
    /// oldest curve legible no matter how full the stack is.
    func testTheRampSpansTheSameRangeAtEveryStackSize() {
        for stackedCount in 3...30 {
            let oldest = HeartRateDriftOverlayData.contextOpacity(
                recencyRank: stackedCount - 1,
                stackedCount: stackedCount
            )
            XCTAssertEqual(oldest, HeartRateDriftOverlayData.oldestContextOpacity, accuracy: 1e-9)
            for rank in 1..<stackedCount {
                let opacity = HeartRateDriftOverlayData.contextOpacity(
                    recencyRank: rank,
                    stackedCount: stackedCount
                )
                XCTAssertGreaterThanOrEqual(opacity, HeartRateDriftOverlayData.oldestContextOpacity)
                XCTAssertLessThanOrEqual(opacity, HeartRateDriftOverlayData.newestContextOpacity)
            }
        }
    }

    func testTwoCurvesPutTheOlderOneCloseToFullStrength() {
        XCTAssertEqual(
            HeartRateDriftOverlayData.contextOpacity(recencyRank: 1, stackedCount: 2),
            HeartRateDriftOverlayData.newestContextOpacity,
            accuracy: 1e-9
        )
    }

    // MARK: - Saying what is missing

    func testExclusionNotesNameEachKindOfOmissionOnce() throws {
        let unscored = try makeCandidate(daysBeforeEpoch: 1, classification: nil)
        let hard = try makeCandidate(daysBeforeEpoch: 2, classification: .hard)
        let noSeries = try makeCandidate(daysBeforeEpoch: 3, samples: nil)
        let short = try makeCandidate(daysBeforeEpoch: 4, samples: [(0, 130), (60, 140)])
        let drawn = try makeCandidate(daysBeforeEpoch: 5)

        let overlay = HeartRateDriftOverlayData(candidates: [unscored, hard, noSeries, short, drawn])

        XCTAssertEqual(overlay.curves.count, 1)
        XCTAssertEqual(overlay.exclusionNotes.count, 4)
        XCTAssertTrue(overlay.exclusionNotes.contains { $0.contains("isn't scored yet") })
        XCTAssertTrue(overlay.exclusionNotes.contains { $0.contains("hard or other session") })
        XCTAssertTrue(overlay.exclusionNotes.contains { $0.contains("no stored heart-rate curve") })
        // The floor is stated in the note, and it is the floor this overlay's resolution
        // actually applies — 100 buckets × 5 s.
        XCTAssertTrue(overlay.exclusionNotes.contains { $0.contains("8m 20s") })
    }

    func testExclusionNotesAgreeInNumber() throws {
        let one = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, samples: nil)
        let single = HeartRateDriftOverlayData(candidates: [one])
        XCTAssertEqual(single.exclusionNotes, ["1 run has no stored heart-rate curve."])

        let two = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, samples: nil)
        let plural = HeartRateDriftOverlayData(candidates: [one, two])
        XCTAssertEqual(plural.exclusionNotes, ["2 runs have no stored heart-rate curve."])
    }

    func testTheStackSummaryCountsWhatIsDrawnAgainstWhatTheIntervalHeld() throws {
        let drawn = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1)
        let hard = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, classification: .hard)

        XCTAssertEqual(
            HeartRateDriftOverlayData(candidates: [drawn, hard]).stackSummary,
            "1 of 2 runs stacked"
        )
        XCTAssertEqual(
            HeartRateDriftOverlayData(candidates: [drawn]).stackSummary,
            "1 of 1 run stacked"
        )
    }

    /// A run the athlete un-stacked themselves is not narrated back at them.
    func testHidingARunProducesNoExplanatoryNote() throws {
        let run = try makeCandidate(id: Fixture.workoutID)
        let overlay = HeartRateDriftOverlayData(
            candidates: [run],
            hiddenWorkoutIDs: [Fixture.workoutID]
        )

        XCTAssertEqual(overlay.count(of: .hiddenByAthlete), 1)
        XCTAssertTrue(overlay.exclusionNotes.isEmpty)
    }

    func testAnIntervalWithNoRunsAtAllIsEmptyRatherThanAnEmptyChart() {
        let overlay = HeartRateDriftOverlayData(candidates: [])

        XCTAssertTrue(overlay.isEmpty)
        XCTAssertNil(overlay.bpmAxisDomain)
        XCTAssertEqual(overlay.candidateCount, 0)
        XCTAssertTrue(overlay.exclusionNotes.isEmpty)
    }

    // MARK: - MAX-150: copy moved here from `DriftOverlayView`

    /// An empty interval and an interval whose runs all failed the shape filter are two
    /// different facts, and `emptyStateText` must not collapse them into one sentence.
    func testEmptyStateTextDistinguishesAnEmptyIntervalFromNoQualifyingCurve() throws {
        let noCandidates = HeartRateDriftOverlayData(candidates: [])
        XCTAssertEqual(noCandidates.emptyStateText, "No runs in this interval.")

        let noSeries = try makeCandidate(samples: nil)
        let excluded = HeartRateDriftOverlayData(candidates: [noSeries])
        XCTAssertEqual(excluded.candidateCount, 1)
        XCTAssertTrue(excluded.isEmpty)
        XCTAssertEqual(
            excluded.emptyStateText,
            "No run in this interval has a heart-rate curve to normalise."
        )
    }

    func testChartAccessibilityLabelNamesHowManyCurvesAreStacked() throws {
        let one = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1)
        let two = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2)
        let overlay = HeartRateDriftOverlayData(candidates: [one, two])

        XCTAssertEqual(
            overlay.chartAccessibilityLabel,
            "Heart-rate curves for 2 runs, on a shared percent-elapsed axis"
        )
    }
}
