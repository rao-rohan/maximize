import Foundation
import XCTest
@testable import MaximizeCore

/// Fixtures for the §9 metric tests.
///
/// The geodesy constants here are *derived by hand*, not read off the implementation,
/// because the metric expectations are built on them. See `metersPerLatitudeDegree`.
enum MetricsFixture {
    /// Metres per degree of latitude on the sphere the distance function uses.
    ///
    /// Along a meridian the haversine formula collapses to `R · Δφ`, so this is simply
    /// `6_371_008.8 × π / 180 = 111_195.08`. Every route below moves along a meridian
    /// precisely so its segment lengths are hand-checkable, and
    /// `GradeAdjustedPaceTests.testMeridianDistanceMatchesTheHandComputedArcLength`
    /// pins the implementation to this number independently.
    static let metersPerLatitudeDegree = 111_195.08

    /// Horizontal distance covered by a 0.01° step along a meridian.
    static let stepMeters = metersPerLatitudeDegree / 100

    /// The rise that makes a `stepMeters` step exactly a 10% grade.
    static let tenPercentRiseMeters = stepMeters / 10

    static func series(
        _ pairs: [(Double, Double)],
        workoutID: UUID = Fixture.workoutID
    ) throws -> HeartRateSeries {
        try HeartRateSeries(workoutID: workoutID, samples: Fixture.samples(pairs))
    }

    static func curve(_ pairs: [(Double, Double)]) throws -> HeartRateCurve {
        HeartRateCurve(try series(pairs))
    }

    /// A route walking due north, one `latitudeStepDegrees` step per fix, with the given
    /// altitudes. Consecutive fixes are therefore exactly `R · Δφ` apart, which keeps the
    /// grades — and everything computed from them — hand-computable.
    static func meridianRoute(
        altitudes: [Double?],
        latitudeStepDegrees: Double = 0.01,
        workoutID: UUID = Fixture.workoutID
    ) throws -> Route {
        var points: [RoutePoint] = []
        for (index, altitude) in altitudes.enumerated() {
            points.append(
                try RoutePoint(
                    offsetSeconds: Double(index) * 10,
                    latitudeDegrees: Double(index) * latitudeStepDegrees,
                    longitudeDegrees: 0,
                    altitudeMeters: altitude
                )
            )
        }
        return try Route(workoutID: workoutID, points: points)
    }

    /// No altitude smoothing, no minimum stretch length — for tests that pin the raw
    /// arithmetic rather than the filter.
    static let unfiltered = GradeAdjustmentParameters(
        altitudeSmoothingRadius: 0,
        minimumSegmentMeters: 0
    )
}
