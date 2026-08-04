import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-043: the chart-ready presentation FR-1.3's cadence-vs-band comparison is built
/// from.
///
/// Mirrors `HeartRateChartDataTests` (MAX-042): the point of this file is pinning that
/// `averageStepsPerMinute` and `band` are stored verbatim, never derived from one
/// another or from anything else, and that the axis domain behaves for every
/// combination of "cadence present/absent" and "band present/absent."
final class CadenceChartDataTests: XCTestCase {
    // MARK: - Pass-through, never derived

    func testAverageStepsPerMinuteIsStoredVerbatim() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: 172, band: band)

        XCTAssertEqual(data.averageStepsPerMinute, 172)
    }

    func testBandIsStoredVerbatim() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: 168, band: band)

        XCTAssertEqual(data.band, band)
    }

    // MARK: - No cadence at all (state: this run has no step count)

    func testNilAverageStaysNilRatherThanBecomingZero() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: nil, band: band)

        XCTAssertNil(data.averageStepsPerMinute)
    }

    // MARK: - No plan governs the day (state: no band to compare against)

    func testNilBandStaysNilRatherThanFallingBackToAConstant() {
        let data = CadenceChartData(averageStepsPerMinute: 168, band: nil)

        XCTAssertNil(data.band)
        XCTAssertEqual(data.averageStepsPerMinute, 168)
    }

    // MARK: - Axis domain

    func testAxisDomainCoversTheBandWhenThereIsNoAverage() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: nil, band: band)

        XCTAssertLessThanOrEqual(data.axisDomain.lowerBound, 165)
        XCTAssertGreaterThanOrEqual(data.axisDomain.upperBound, 170)
    }

    func testAxisDomainCoversTheAverageWhenThereIsNoBand() {
        let data = CadenceChartData(averageStepsPerMinute: 180, band: nil)

        XCTAssertLessThan(data.axisDomain.lowerBound, 180)
        XCTAssertGreaterThan(data.axisDomain.upperBound, 180)
    }

    /// The load-bearing case: a run well above (or below) its band still has to fit
    /// on the same axis as the band itself, or the comparison FR-1.3 asks for is not
    /// actually drawable.
    func testAxisDomainWidensToIncludeAnAverageOutsideTheBand() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: 190, band: band)

        XCTAssertLessThanOrEqual(data.axisDomain.lowerBound, 165)
        XCTAssertGreaterThanOrEqual(data.axisDomain.upperBound, 190)
    }

    func testAxisDomainWidensToIncludeAnAverageBelowTheBand() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: 140, band: band)

        XCTAssertLessThanOrEqual(data.axisDomain.lowerBound, 140)
        XCTAssertGreaterThanOrEqual(data.axisDomain.upperBound, 170)
    }

    func testAxisDomainIsWellFormedWhenTheAverageSitsInsideTheBand() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        let data = CadenceChartData(averageStepsPerMinute: 168, band: band)

        XCTAssertLessThan(data.axisDomain.lowerBound, data.axisDomain.upperBound)
        XCTAssertLessThanOrEqual(data.axisDomain.lowerBound, 165)
        XCTAssertGreaterThanOrEqual(data.axisDomain.upperBound, 170)
    }

    func testAxisDomainIsWellFormedForAZeroWidthBand() throws {
        let band = try CadenceBand(lowStepsPerMinute: 168, highStepsPerMinute: 168)
        let data = CadenceChartData(averageStepsPerMinute: nil, band: band)

        XCTAssertLessThan(data.axisDomain.lowerBound, data.axisDomain.upperBound)
    }

    func testAxisDomainIsWellFormedWhenNeitherAverageNorBandIsPresent() {
        let data = CadenceChartData(averageStepsPerMinute: nil, band: nil)

        XCTAssertLessThan(data.axisDomain.lowerBound, data.axisDomain.upperBound)
    }
}
