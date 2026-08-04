import Foundation
import XCTest
@testable import MaximizeCore

final class HeartRateSeriesTests: XCTestCase {
    func testAcceptsAStrictlyAscendingSeries() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: Fixture.samples([(0, 120), (30, 134), (60, 141)])
        )
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series.firstSample.beatsPerMinute, 120)
        XCTAssertEqual(series.lastSample.beatsPerMinute, 141)
        XCTAssertEqual(series.coveredSeconds, 60, accuracy: 0.001)
    }

    /// The invariant every downstream metric leans on. An unsorted curve does not
    /// fail loudly in a drift calculation — it produces a plausible wrong number.
    func testRejectsAnOutOfOrderSeries() throws {
        let samples = try Fixture.samples([(0, 120), (60, 141), (30, 134)])
        assertThrows(.outOfOrder, try HeartRateSeries(workoutID: Fixture.workoutID, samples: samples))
    }

    func testRejectsTwoSamplesAtTheSameOffset() throws {
        let samples = try Fixture.samples([(0, 120), (30, 134), (30, 138)])
        assertThrows(.duplicate, try HeartRateSeries(workoutID: Fixture.workoutID, samples: samples))
    }

    /// "No heart-rate data" is the absence of a series, not an empty one.
    func testRejectsAnEmptySeries() {
        assertThrows(.empty, try HeartRateSeries(workoutID: Fixture.workoutID, samples: []))
    }

    func testSingleSampleSeriesIsValid() throws {
        let series = try HeartRateSeries(workoutID: Fixture.workoutID, samples: Fixture.samples([(12, 99)]))
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.coveredSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(series.firstSample, series.lastSample)
    }

    /// Repair is available but has to be asked for by name, so no caller drifts into
    /// depending on silent reordering.
    func testSortingInitializerRepairsIngestionOrder() throws {
        let samples = try Fixture.samples([(60, 141), (0, 120), (30, 134)])
        let series = try HeartRateSeries(workoutID: Fixture.workoutID, sorting: samples)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [0, 30, 60])
    }

    func testRejectsImplausibleSamples() {
        assertThrows(.outOfRange, try HeartRateSample(offsetSeconds: -1, beatsPerMinute: 130))
        assertThrows(.outOfRange, try HeartRateSample(offsetSeconds: 0, beatsPerMinute: 400))
        assertThrows(.outOfRange, try HeartRateSample(offsetSeconds: 0, beatsPerMinute: 0))
        assertThrows(.notFinite, try HeartRateSample(offsetSeconds: 0, beatsPerMinute: .nan))
    }

    func testRoundTripsThroughJSON() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: Fixture.samples([(0, 120), (30, 134)])
        )
        XCTAssertEqual(try roundTripped(series), series)
    }

    func testDecodingRejectsAnOutOfOrderSeries() throws {
        let json = """
        {"wrapped":{"workoutID":"11111111-1111-1111-1111-111111111111","samples":[\
        {"offsetSeconds":60,"beatsPerMinute":141},{"offsetSeconds":0,"beatsPerMinute":120}]}}
        """
        struct Box: Decodable {
            let wrapped: HeartRateSeries
        }
        let data = try XCTUnwrap(json.data(using: .utf8))
        assertThrows(.outOfOrder, try JSONDecoder().decode(Box.self, from: data))
    }
}

final class RouteTests: XCTestCase {
    private func point(
        _ offset: Double,
        _ latitude: Double = 37.77,
        _ longitude: Double = -122.42,
        altitude: Double? = 10
    ) throws -> RoutePoint {
        try RoutePoint(
            offsetSeconds: offset,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            altitudeMeters: altitude,
            speedMetersPerSecond: 3.2
        )
    }

    func testAcceptsAnAscendingTrack() throws {
        let route = try Route(workoutID: Fixture.workoutID, points: [point(0), point(5), point(10)])
        XCTAssertEqual(route.count, 3)
        XCTAssertTrue(route.hasUsableAltitude)
    }

    func testRejectsOutOfOrderAndDuplicateFixes() throws {
        assertThrows(.outOfOrder, try Route(workoutID: Fixture.workoutID, points: [point(10), point(5)]))
        assertThrows(.duplicate, try Route(workoutID: Fixture.workoutID, points: [point(5), point(5)]))
        assertThrows(.empty, try Route(workoutID: Fixture.workoutID, points: []))
    }

    func testRejectsCoordinatesOffTheGlobe() {
        assertThrows(.outOfRange, try RoutePoint(offsetSeconds: 0, latitudeDegrees: 91, longitudeDegrees: 0))
        assertThrows(.outOfRange, try RoutePoint(offsetSeconds: 0, latitudeDegrees: 0, longitudeDegrees: -181))
        assertThrows(
            .outOfRange,
            try RoutePoint(
                offsetSeconds: 0,
                latitudeDegrees: 0,
                longitudeDegrees: 0,
                speedMetersPerSecond: -1
            )
        )
    }

    /// Grade-adjusted pace needs altitude on at least two fixes; a route without it
    /// must say so rather than let the metric quietly assume sea level.
    func testAltitudeAvailabilityIsExplicit() throws {
        let flat = try Route(
            workoutID: Fixture.workoutID,
            points: [point(0, altitude: nil), point(5, altitude: nil)]
        )
        XCTAssertFalse(flat.hasUsableAltitude)

        let partial = try Route(
            workoutID: Fixture.workoutID,
            points: [point(0, altitude: 12), point(5, altitude: nil)]
        )
        XCTAssertFalse(partial.hasUsableAltitude)
    }

    func testRoundTripsThroughJSON() throws {
        let route = try Route(workoutID: Fixture.workoutID, points: [point(0), point(5)])
        XCTAssertEqual(try roundTripped(route), route)
    }
}
