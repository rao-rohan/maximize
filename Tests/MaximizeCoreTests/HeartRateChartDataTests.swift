import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-042: the chart-ready presentation FR-1.2's HR curve is built from.
///
/// The tests in `MARK: - The stated figure never becomes a second number` are the
/// point of this file: they exist to catch exactly the failure the ticket calls out —
/// a shaded region and a stated duration that quietly stop agreeing.
final class HeartRateChartDataTests: XCTestCase {
    // MARK: - Points are a straight pass-through

    func testPointsAreTheStoredSamplesUnchanged() throws {
        let series = try MetricsFixture.series([(0, 120), (300, 150), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: 300)

        XCTAssertEqual(data.points.count, 3)
        XCTAssertEqual(data.points.map(\.offsetSeconds), [0, 300, 600])
        XCTAssertEqual(data.points.map(\.beatsPerMinute), [120, 150, 180])
    }

    // MARK: - The stated figure never becomes a second number

    /// The core guarantee this type exists to provide: `timeAboveCapSeconds` is exactly
    /// what was passed in, even when it disagrees with what the curve's own crossings
    /// would sum to. If `init` ever starts deriving this from `aboveCapExcursions`
    /// instead of storing the parameter, this test starts failing — which is the whole
    /// point of pinning an intentionally "wrong" value rather than a realistic one.
    func testTimeAboveCapSecondsIsStoredVerbatimEvenWhenItDisagreesWithTheCurve() throws {
        // The true crossing-implied duration for this ramp and this cap is 300 s
        // (reference ramp, see HeartRateCurveTests) — deliberately pass something else.
        let series = try MetricsFixture.series([(0, 120), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: 42)

        XCTAssertEqual(data.timeAboveCapSeconds, 42)
    }

    func testTimeAboveCapSecondsPassesThroughNilUnchanged() throws {
        let series = try MetricsFixture.series([(0, 120), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: nil)
        XCTAssertNil(data.timeAboveCapSeconds)
    }

    /// The shading is independent of the stated figure in the other direction too:
    /// `aboveCapExcursions` is populated purely from the curve and the cap, whether or
    /// not a stored duration was supplied at all.
    func testShadingIsComputedFromTheCurveRegardlessOfWhatTimeAboveCapSecondsSays() throws {
        let series = try MetricsFixture.series([(0, 120), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: nil)

        XCTAssertEqual(data.aboveCapExcursions.count, 1)
        let excursion = try XCTUnwrap(data.aboveCapExcursions.first)
        let firstPoint = try XCTUnwrap(excursion.first)
        let lastPoint = try XCTUnwrap(excursion.last)
        XCTAssertEqual(firstPoint.offsetSeconds, 300, accuracy: 1e-9)
        XCTAssertEqual(lastPoint.offsetSeconds, 600, accuracy: 1e-9)
    }

    // MARK: - No cap governs the day (state 4: a workout no plan covers)

    func testNoCapMeansNoShadingAndNoThresholdToDraw() throws {
        let series = try MetricsFixture.series([(0, 120), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: nil, timeAboveCapSeconds: nil)

        XCTAssertNil(data.capBPM)
        XCTAssertTrue(data.aboveCapExcursions.isEmpty)
    }

    // MARK: - A run entirely below the cap (state 3: perfectly executed, not absent)

    func testACurveThatNeverExceedsTheCapHasNoExcursionsButStillStatesZero() throws {
        let series = try MetricsFixture.series([(0, 120), (600, 140)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: 0)

        XCTAssertTrue(data.aboveCapExcursions.isEmpty)
        // Zero is stated, not omitted — distinguishing "held the cap" from "unmeasured"
        // is the view's job, but the data has to preserve the zero to make that possible.
        XCTAssertEqual(data.timeAboveCapSeconds, 0)
    }

    // MARK: - Axis domains

    func testBPMAxisDomainExpandsToIncludeACapAboveTheCurvesOwnPeak() throws {
        // min 120, max 140, cap 150: the axis must reach the cap, not just the curve.
        let series = try MetricsFixture.series([(0, 120), (600, 140)])
        let data = HeartRateChartData(series: series, capBPM: 150, timeAboveCapSeconds: 0)

        let domain = data.bpmAxisDomain
        XCTAssertLessThanOrEqual(domain.lowerBound, 120)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 150)
    }

    func testBPMAxisDomainUsesOnlyTheCurveWhenThereIsNoCap() throws {
        let series = try MetricsFixture.series([(0, 120), (600, 180)])
        let data = HeartRateChartData(series: series, capBPM: nil, timeAboveCapSeconds: nil)

        let domain = data.bpmAxisDomain
        XCTAssertLessThanOrEqual(domain.lowerBound, 120)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 180)
        // And it shouldn't balloon out to cover some default cap that was never there.
        XCTAssertLessThan(domain.upperBound, 200)
    }

    func testBPMAxisDomainIsWellFormedForAFlatSingleSampleCurve() throws {
        let series = try MetricsFixture.series([(30, 160)])
        let data = HeartRateChartData(series: series, capBPM: nil, timeAboveCapSeconds: nil)

        XCTAssertLessThan(data.bpmAxisDomain.lowerBound, data.bpmAxisDomain.upperBound)
    }

    func testOffsetSecondsDomainMatchesTheCurvesOwnSpan() throws {
        let series = try MetricsFixture.series([(30, 128), (900, 155)])
        let data = HeartRateChartData(series: series, capBPM: nil, timeAboveCapSeconds: nil)

        XCTAssertEqual(data.offsetSecondsDomain.lowerBound, 30, accuracy: 1e-9)
        XCTAssertEqual(data.offsetSecondsDomain.upperBound, 900, accuracy: 1e-9)
    }

    func testOffsetSecondsDomainIsPaddedForASingleSampleCurve() throws {
        let series = try MetricsFixture.series([(30, 160)])
        let data = HeartRateChartData(series: series, capBPM: nil, timeAboveCapSeconds: nil)

        XCTAssertLessThan(data.offsetSecondsDomain.lowerBound, data.offsetSecondsDomain.upperBound)
    }

    // MARK: - Duration formatting

    func testFormattedDurationUnderAMinuteIsSecondsOnly() {
        XCTAssertEqual(HeartRateChartData.formattedDuration(seconds: 45), "45s")
    }

    func testFormattedDurationUnderAnHourIsMinutesAndSeconds() {
        XCTAssertEqual(HeartRateChartData.formattedDuration(seconds: 754), "12m 34s")
    }

    func testFormattedDurationOverAnHourIncludesHours() {
        XCTAssertEqual(HeartRateChartData.formattedDuration(seconds: 3_723), "1h 02m 03s")
    }

    func testFormattedDurationOfZeroIsZeroSeconds() {
        XCTAssertEqual(HeartRateChartData.formattedDuration(seconds: 0), "0s")
    }
}
