import XCTest
@testable import MaximizeCore

/// Every expectation here is derived on paper from the sample values, then written down.
/// None of it was obtained by running the code — a test that asserts the implementation
/// agrees with itself would pass just as happily with the arithmetic inverted.
final class HeartRateCurveTests: XCTestCase {
    // MARK: - The reference ramp
    //
    // Samples (0 s, 120 bpm) → (600 s, 180 bpm): a straight line rising 0.1 bpm per
    // second. Nearly every §9 heart-rate metric is hand-computable on it, so it is used
    // as the single reference case.

    private func referenceRamp() throws -> HeartRateCurve {
        try MetricsFixture.curve([(0, 120), (600, 180)])
    }

    func testAverageOfALinearRampIsTheMidpointOfItsEnds() throws {
        // ∫ = (120 + 180)/2 × 600 = 90 000 bpm·s; ÷ 600 s = 150 bpm.
        XCTAssertEqual(try referenceRamp().averageBPM, 150, accuracy: 1e-9)
    }

    func testMaximumIsThePeakSampleValue() throws {
        XCTAssertEqual(try referenceRamp().maximumBPM, 180, accuracy: 1e-9)
    }

    func testSecondsAboveCapIsTheSpanAfterTheModelledCrossing() throws {
        // The ramp reaches 150 bpm at t = (150 − 120)/0.1 = 300 s, so 300 of the 600
        // seconds are above a 150 bpm cap.
        XCTAssertEqual(try referenceRamp().secondsAbove(150), 300, accuracy: 1e-9)
    }

    func testSecondsAboveCapMovesWithTheCap() throws {
        // 160 bpm is reached at t = (160 − 120)/0.1 = 400 s → 200 s above.
        XCTAssertEqual(try referenceRamp().secondsAbove(160), 200, accuracy: 1e-9)
        // 120 bpm is the opening value; every later instant is strictly above it.
        XCTAssertEqual(try referenceRamp().secondsAbove(120), 600, accuracy: 1e-9)
        XCTAssertEqual(try referenceRamp().secondsAbove(180), 0, accuracy: 1e-9)
    }

    func testDriftOfTheReferenceRamp() throws {
        // First half [0, 300]: 120 → 150, mean 135. Second half [300, 600]: 150 → 180,
        // mean 165. Drift = 165/135 − 1 = 2/9.
        let drift = try XCTUnwrap(try referenceRamp().driftFraction)
        XCTAssertEqual(drift, 2.0 / 9.0, accuracy: 1e-9)
    }

    func testZoneSplitsOfTheReferenceRamp() throws {
        // Cap-anchored zones for a 150 bpm cap: ≤135, ≤150, ≤162, ≤174, then above.
        // The ramp crosses them at t = 150, 300, 420 and 540 s.
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)
        let splits = try referenceRamp().zoneSplits(model: model)

        XCTAssertEqual(splits.seconds(in: .one), 150, accuracy: 1e-9)
        XCTAssertEqual(splits.seconds(in: .two), 150, accuracy: 1e-9)
        XCTAssertEqual(splits.seconds(in: .three), 120, accuracy: 1e-9)
        XCTAssertEqual(splits.seconds(in: .four), 120, accuracy: 1e-9)
        XCTAssertEqual(splits.seconds(in: .five), 60, accuracy: 1e-9)
        XCTAssertEqual(splits.totalSeconds, 600, accuracy: 1e-9)
    }

    // MARK: - Interpolation across a gap

    /// The case the ticket names: what does a gap between a 148 bpm sample and a 155 bpm
    /// sample contribute to time above a 150 bpm cap?
    ///
    /// The modelled curve crosses 150 at (150 − 148)/(155 − 148) = 2/7 of the way
    /// through a 70 s gap, i.e. at t = 20 s — so 50 s are above the cap. Not 70 (both
    /// samples counted), not 0 (neither), and not 35 (split the difference).
    func testAGapCrossingTheCapContributesItsAboveCapPortion() throws {
        let curve = try MetricsFixture.curve([(0, 148), (70, 155)])
        XCTAssertEqual(curve.secondsAbove(150), 50, accuracy: 1e-9)
    }

    func testADescendingGapCrossingTheCapIsMeasuredTheSameWay() throws {
        // Mirror image: 155 → 148 over 70 s falls through 150 at
        // (155 − 150)/(155 − 148) = 5/7 of the way, t = 50 s — and it is the *first*
        // 50 s that are above the cap.
        let curve = try MetricsFixture.curve([(0, 155), (70, 148)])
        XCTAssertEqual(curve.secondsAbove(150), 50, accuracy: 1e-9)
    }

    func testTimeAtExactlyTheCapIsNotTimeAboveIt() throws {
        // §9 defines the metric as HR > cap, strictly.
        let curve = try MetricsFixture.curve([(0, 150), (100, 150)])
        XCTAssertEqual(curve.secondsAbove(150), 0, accuracy: 1e-9)
    }

    func testTimeAboveCapIgnoresSamplingDensity() throws {
        // The same 600 s ramp, sampled once in the middle. Time above cap is a property
        // of the run, so it must not change.
        let sparse = try MetricsFixture.curve([(0, 120), (600, 180)])
        let dense = try MetricsFixture.curve([
            (0, 120), (60, 126), (120, 132), (300, 150), (301, 150.1), (599, 179.9), (600, 180),
        ])
        XCTAssertEqual(sparse.secondsAbove(150), dense.secondsAbove(150), accuracy: 1e-6)
    }

    // MARK: - Irregular sampling

    func testAverageIsWeightedByTimeNotBySample() throws {
        // (0, 150), (10, 150), (1000, 100).
        //   ∫[0,10]    = 150 × 10                  =   1 500
        //   ∫[10,1000] = (150 + 100)/2 × 990       = 123 750
        //   total 125 250 bpm·s ÷ 1 000 s          = 125.25 bpm
        // The plain mean of the three samples is 133.33 — the sensor's chattiness at the
        // start, not the athlete's heart.
        let curve = try MetricsFixture.curve([(0, 150), (10, 150), (1_000, 100)])
        XCTAssertEqual(curve.averageBPM, 125.25, accuracy: 1e-9)
    }

    /// Halves are split by elapsed time, not by sample count, and the two genuinely
    /// disagree — this is the test that pins the decision.
    func testDriftSplitsHalvesByElapsedTimeNotBySampleCount() throws {
        // Six samples: five in the first four minutes at 140 bpm, then one at 1 200 s of
        // 170 bpm. A count split (3 + 3) would compare 140 against a mostly-140 tail.
        //
        // The time split falls at t = 600 s, where the curve reads
        //   140 + 30 × (360/960) = 151.25 bpm.
        // First half:  ∫[0,240]   = 140 × 240                = 33 600
        //              ∫[240,600] = (140 + 151.25)/2 × 360   = 52 425
        //              total 86 025 ÷ 600                    = 143.375 bpm
        // Second half: (151.25 + 170)/2                      = 160.625 bpm
        // Drift = 160.625/143.375 − 1 ≈ 0.1203.
        let curve = try MetricsFixture.curve([
            (0, 140), (60, 140), (120, 140), (180, 140), (240, 140), (1_200, 170),
        ])
        let drift = try XCTUnwrap(curve.driftFraction)

        XCTAssertEqual(drift, 160.625 / 143.375 - 1, accuracy: 1e-9)
        // Splitting three samples against three would have compared 140 bpm (over
        // [0, 120]) against (140 × 60 + (140 + 170)/2 × 960)/1 020 = 154.12 bpm (over
        // [180, 1 200]) — a drift of ≈ 0.1008. The choice is visible in the output,
        // which is why it is pinned rather than left to whoever reads the code next.
        XCTAssertGreaterThan(abs(drift - 0.1008), 0.01)
    }

    /// An odd sample count needs no tie-break: the midpoint is a time, and the value
    /// there is interpolated.
    func testDriftWithAnOddSampleCountSplitsAtTheMidpointTime() throws {
        // (0, 140), (10, 160), (100, 160). Midpoint t = 50 s, where the curve reads 160.
        // First half:  ∫[0,10] = (140 + 160)/2 × 10 = 1 500
        //              ∫[10,50] = 160 × 40          = 6 400
        //              7 900 ÷ 50                   = 158 bpm
        // Second half: 160 bpm throughout.
        // Drift = 160/158 − 1.
        let curve = try MetricsFixture.curve([(0, 140), (10, 160), (100, 160)])
        let drift = try XCTUnwrap(curve.driftFraction)

        XCTAssertEqual(drift, 160.0 / 158.0 - 1, accuracy: 1e-9)
        // Splitting at the middle *sample* would have compared 150 bpm against 160 bpm.
        XCTAssertGreaterThan(abs(drift - (160.0 / 150.0 - 1)), 0.01)
    }

    func testZoneSplitsSumToTheCoveredSpanWhenSamplingIsIrregular() throws {
        let curve = try MetricsFixture.curve([
            (30, 128), (31, 141), (95, 139), (400, 168), (401, 171), (402, 120), (900, 155),
        ])
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)
        let splits = try curve.zoneSplits(model: model)

        // Covered span is 900 − 30: the curve is not extrapolated to the workout's start.
        XCTAssertEqual(splits.totalSeconds, 870, accuracy: 1e-9)
        XCTAssertEqual(curve.coveredSeconds, 870, accuracy: 1e-9)
    }

    func testZoneSplitsOmitZonesWithNoTime() throws {
        let curve = try MetricsFixture.curve([(0, 130), (100, 130)])
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)
        let splits = try curve.zoneSplits(model: model)

        XCTAssertEqual(splits.splits.count, 1)
        XCTAssertEqual(splits.seconds(in: .one), 100, accuracy: 1e-9)
        // Absent reads as zero, which is what `ZoneSplits` documents.
        XCTAssertEqual(splits.seconds(in: .five), 0, accuracy: 1e-9)
    }

    // MARK: - Degenerate series

    func testSingleSampleSeriesHasAnAverageButNoSpanToMeasure() throws {
        let curve = try MetricsFixture.curve([(30, 160)])

        XCTAssertEqual(curve.coveredSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(curve.averageBPM, 160, accuracy: 1e-9)
        XCTAssertEqual(curve.maximumBPM, 160, accuracy: 1e-9)
        // Zero seconds above the cap is the true answer over a zero-length span, even
        // though the one sample sits above it: there is no *duration* above the cap.
        XCTAssertEqual(curve.secondsAbove(150), 0, accuracy: 1e-9)
        // Drift is unavailable, not zero — there is no second half to compare.
        XCTAssertNil(curve.driftFraction)

        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)
        XCTAssertTrue(try curve.zoneSplits(model: model).splits.isEmpty)
    }

    func testAnEmptySeriesCannotExist() {
        // "No heart-rate data" is modelled by having no series at all, so the metric code
        // never has to invent a policy for an empty one.
        assertThrows(.empty, try HeartRateSeries(workoutID: Fixture.workoutID, samples: []))
    }

    func testTwoSamplesAtTheSameInstantAreRejectedUpstream() {
        assertThrows(
            .duplicate,
            try MetricsFixture.series([(10, 140), (10, 150)])
        )
    }

    func testMeanOverAWindowWithNoDurationIsUnavailable() throws {
        let curve = try referenceRamp()
        XCTAssertNil(curve.timeWeightedMeanBPM(from: 300, to: 300))
        XCTAssertNil(curve.timeWeightedMeanBPM(from: 900, to: 1_200))
    }

    func testMeanOverAWindowIsClippedToTheCoveredSpan() throws {
        // Asking for [−1 000, +1 000] on a curve covering [0, 600] answers for [0, 600].
        let curve = try referenceRamp()
        let mean = try XCTUnwrap(curve.timeWeightedMeanBPM(from: -1_000, to: 1_000))
        XCTAssertEqual(mean, 150, accuracy: 1e-9)
    }

    // MARK: - excursionsAbove (MAX-042: the shape a chart shades)

    /// The reference ramp crosses 150 bpm at t = 300 s (same crossing `secondsAbove(150)`
    /// pins) and stays above it to the end of the curve — one excursion, closed at the
    /// crossing and at the curve's own endpoint.
    func testExcursionAboveCapOnTheReferenceRampClosesAtTheSameCrossingSecondsAboveUses() throws {
        let excursions = try referenceRamp().excursionsAbove(150)

        XCTAssertEqual(excursions.count, 1)
        let excursion = try XCTUnwrap(excursions.first)
        XCTAssertEqual(excursion.count, 2)
        XCTAssertEqual(excursion[0].offsetSeconds, 300, accuracy: 1e-9)
        XCTAssertEqual(excursion[0].beatsPerMinute, 150, accuracy: 1e-9)
        XCTAssertEqual(excursion[1].offsetSeconds, 600, accuracy: 1e-9)
        XCTAssertEqual(excursion[1].beatsPerMinute, 180, accuracy: 1e-9)
    }

    /// A curve that rises above the cap, falls back under it, then rises again produces
    /// two separate, independently closed excursions rather than one that bridges the
    /// dip.
    func testACurveThatDipsBelowTheCapAndBackProducesTwoExcursions() throws {
        // (0,160) → (100,140): descending crossing at 0 + (150−160)/(140−160)×100 = 50 s.
        // (100,140) → (200,160): ascending crossing at 100 + (150−140)/(160−140)×100 = 150 s.
        let curve = try MetricsFixture.curve([(0, 160), (100, 140), (200, 160)])
        let excursions = curve.excursionsAbove(150)

        XCTAssertEqual(excursions.count, 2)

        XCTAssertEqual(excursions[0].count, 2)
        XCTAssertEqual(excursions[0][0].offsetSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(excursions[0][0].beatsPerMinute, 160, accuracy: 1e-9)
        XCTAssertEqual(excursions[0][1].offsetSeconds, 50, accuracy: 1e-9)
        XCTAssertEqual(excursions[0][1].beatsPerMinute, 150, accuracy: 1e-9)

        XCTAssertEqual(excursions[1].count, 2)
        XCTAssertEqual(excursions[1][0].offsetSeconds, 150, accuracy: 1e-9)
        XCTAssertEqual(excursions[1][0].beatsPerMinute, 150, accuracy: 1e-9)
        XCTAssertEqual(excursions[1][1].offsetSeconds, 200, accuracy: 1e-9)
        XCTAssertEqual(excursions[1][1].beatsPerMinute, 160, accuracy: 1e-9)
    }

    func testExcursionsAboveCapAreEmptyWhenTheCurveNeverExceedsIt() throws {
        // A perfectly held easy run: the whole ramp stays at or below the cap.
        let curve = try MetricsFixture.curve([(0, 120), (600, 140)])
        XCTAssertTrue(curve.excursionsAbove(150).isEmpty)
    }

    func testExcursionsAboveCapAreEmptyWhenTheCurveTouchesButNeverExceedsTheCap() throws {
        // §9's "strictly above" boundary applies to the shading too: sitting exactly on
        // the cap is not an excursion.
        let curve = try MetricsFixture.curve([(0, 150), (100, 150)])
        XCTAssertTrue(curve.excursionsAbove(150).isEmpty)
    }
}
