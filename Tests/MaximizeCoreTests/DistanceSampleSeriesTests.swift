import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-066. Mirrors `HeartRateSeriesTests` — same ordering invariant, same
/// absent-not-empty rule, same Codable contract.
final class DistanceSampleSeriesTests: XCTestCase {
    private func samples(_ pairs: [(Double, Double)]) throws -> [DistanceSample] {
        try pairs.map { try DistanceSample(offsetSeconds: $0.0, meters: $0.1) }
    }

    func testAcceptsAStrictlyAscendingSeries() throws {
        let series = try DistanceSampleSeries(
            workoutID: Fixture.workoutID,
            samples: samples([(0, 0), (10, 25), (20, 27)])
        )
        XCTAssertEqual(series.count, 3)
    }

    /// The invariant `DistanceSplitCalculator.Track` leans on: an unsorted series does
    /// not fail loudly downstream, it produces a plausible wrong cumulative curve.
    func testRejectsAnOutOfOrderSeries() throws {
        let unordered = try samples([(0, 0), (20, 27), (10, 25)])
        assertThrows(.outOfOrder, try DistanceSampleSeries(workoutID: Fixture.workoutID, samples: unordered))
    }

    func testRejectsTwoSamplesAtTheSameOffset() throws {
        let duplicated = try samples([(0, 0), (10, 25), (10, 26)])
        assertThrows(.duplicate, try DistanceSampleSeries(workoutID: Fixture.workoutID, samples: duplicated))
    }

    /// "No distance samples" is the absence of a series, not an empty one — the same
    /// rule `HeartRateSeries` and `Route` already follow.
    func testRejectsAnEmptySeries() {
        assertThrows(.empty, try DistanceSampleSeries(workoutID: Fixture.workoutID, samples: []))
    }

    func testSortingInitializerRepairsIngestionOrder() throws {
        let unordered = try samples([(20, 27), (0, 0), (10, 25)])
        let series = try DistanceSampleSeries(workoutID: Fixture.workoutID, sorting: unordered)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [0, 10, 20])
    }

    func testRejectsANegativeOffsetOrMeters() {
        assertThrows(.outOfRange, try DistanceSample(offsetSeconds: -1, meters: 10))
        assertThrows(.outOfRange, try DistanceSample(offsetSeconds: 0, meters: -1))
    }

    /// A stationary reading — zero ground covered — is not a sensor artefact for a
    /// distance series the way a colliding heart-rate timestamp is; it is what a
    /// paused treadmill genuinely reports.
    func testZeroMetersIsAValidReading() throws {
        let sample = try DistanceSample(offsetSeconds: 10, meters: 0)
        XCTAssertEqual(sample.meters, 0)
    }

    func testRoundTripsThroughJSON() throws {
        let series = try DistanceSampleSeries(
            workoutID: Fixture.workoutID,
            samples: samples([(0, 0), (10, 25)])
        )
        XCTAssertEqual(try roundTripped(series), series)
    }

    func testDecodingRejectsAnOutOfOrderSeries() throws {
        let json = """
        {"wrapped":{"workoutID":"11111111-1111-1111-1111-111111111111","samples":[\
        {"offsetSeconds":20,"meters":27},{"offsetSeconds":0,"meters":0}]}}
        """
        struct Box: Decodable {
            let wrapped: DistanceSampleSeries
        }
        let data = try XCTUnwrap(json.data(using: .utf8))
        assertThrows(.outOfOrder, try JSONDecoder().decode(Box.self, from: data))
    }
}
