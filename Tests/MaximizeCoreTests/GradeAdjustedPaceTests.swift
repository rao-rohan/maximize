import XCTest
@testable import MaximizeCore

/// Expected values are hand-derived from the Minetti polynomial and from arc length on a
/// sphere; the derivations are written out beside each assertion so a later reader can
/// check the arithmetic without running anything.
final class GradeAdjustedPaceTests: XCTestCase {
    // MARK: - Geodesy

    /// Along a meridian the haversine formula reduces to `R · Δφ`, so a 0.01° step is
    /// `6 371 008.8 × 0.01 × π/180 = 1 111.9508 m`. This is the number every grade below
    /// is divided by, so it is pinned first.
    func testMeridianDistanceMatchesTheHandComputedArcLength() throws {
        let origin = try RoutePoint(offsetSeconds: 0, latitudeDegrees: 0, longitudeDegrees: 0)
        let north = try RoutePoint(offsetSeconds: 10, latitudeDegrees: 0.01, longitudeDegrees: 0)

        XCTAssertEqual(
            GradeAdjustedPace.horizontalDistanceMeters(from: origin, to: north),
            MetricsFixture.stepMeters,
            accuracy: 0.01
        )
    }

    /// A degree of longitude *on the equator* is the same arc as a degree of latitude —
    /// a second, independent way to hit the same number.
    func testEquatorialLongitudeStepIsTheSameArc() throws {
        let origin = try RoutePoint(offsetSeconds: 0, latitudeDegrees: 0, longitudeDegrees: 0)
        let east = try RoutePoint(offsetSeconds: 10, latitudeDegrees: 0, longitudeDegrees: 0.01)

        XCTAssertEqual(
            GradeAdjustedPace.horizontalDistanceMeters(from: origin, to: east),
            MetricsFixture.stepMeters,
            accuracy: 0.01
        )
    }

    func testIdenticalFixesAreZeroApart() throws {
        let fix = try RoutePoint(offsetSeconds: 0, latitudeDegrees: 51.5, longitudeDegrees: -0.12)
        let same = try RoutePoint(offsetSeconds: 10, latitudeDegrees: 51.5, longitudeDegrees: -0.12)

        XCTAssertEqual(GradeAdjustedPace.horizontalDistanceMeters(from: fix, to: same), 0, accuracy: 1e-9)
    }

    // MARK: - Cost of running

    func testCostOfRunningAtHandComputedGradients() {
        // 155.4i⁵ − 30.4i⁴ − 43.3i³ + 46.3i² + 19.5i + 3.6
        // i = 0:    3.6
        // i = 0.1:  0.001554 − 0.00304 − 0.0433 + 0.463 + 1.95 + 3.6   = 5.968214
        // i = −0.1: −0.001554 − 0.00304 + 0.0433 + 0.463 − 1.95 + 3.6  = 2.151706
        // i = −0.2: −0.049728 − 0.04864 + 0.3464 + 1.852 − 3.9 + 3.6   = 1.800032
        XCTAssertEqual(GradeAdjustedPace.costOfRunning(gradient: 0), 3.6, accuracy: 1e-9)
        XCTAssertEqual(GradeAdjustedPace.costOfRunning(gradient: 0.1), 5.968214, accuracy: 1e-9)
        XCTAssertEqual(GradeAdjustedPace.costOfRunning(gradient: -0.1), 2.151706, accuracy: 1e-9)
        XCTAssertEqual(GradeAdjustedPace.costOfRunning(gradient: -0.2), 1.800032, accuracy: 1e-9)
    }

    /// Two properties of the curve that the pace arithmetic leans on: descending is
    /// cheapest somewhere around −20% rather than on the flat, and a steep descent costs
    /// more again.
    func testCostIsMinimisedOnAModerateDescentNotOnTheFlat() {
        XCTAssertLessThan(
            GradeAdjustedPace.costOfRunning(gradient: -0.2),
            GradeAdjustedPace.costOfRunning(gradient: 0)
        )
        XCTAssertGreaterThan(
            GradeAdjustedPace.costOfRunning(gradient: -0.45),
            GradeAdjustedPace.costOfRunning(gradient: -0.2)
        )
    }

    func testGradesBeyondTheFittedRangeAreClamped() {
        // A GPS glitch reporting a 300% grade must not be extrapolated through a quintic.
        let absurd = GradeAdjustedPace.adjustmentFactor(gradient: 3, parameters: .default)
        let clamped = GradeAdjustedPace.adjustmentFactor(gradient: 0.45, parameters: .default)
        XCTAssertEqual(absurd, clamped, accuracy: 1e-12)

        let absurdDescent = GradeAdjustedPace.adjustmentFactor(gradient: -3, parameters: .default)
        let clampedDescent = GradeAdjustedPace.adjustmentFactor(gradient: -0.45, parameters: .default)
        XCTAssertEqual(absurdDescent, clampedDescent, accuracy: 1e-12)
    }

    // MARK: - Altitude smoothing

    func testSmoothingLeavesASteadyClimbExactlyAsItWas() {
        // Symmetric truncation: the window at index i has half-width min(2, i, n−1−i), so
        // index 0 keeps 0, index 1 averages (0+10+20)/3 = 10, index 2 averages
        // (0+10+20+30+40)/5 = 20, and so on. A ramp survives untouched — smoothing a hill
        // must not flatten it.
        let ramp = [0.0, 10, 20, 30, 40]
        XCTAssertEqual(GradeAdjustedPace.smoothedAltitudes(ramp, radius: 2), ramp)
    }

    func testSmoothingAttenuatesASpike() {
        // [0, 0, 30, 0, 0] with radius 2:
        //   index 0: half-width 0            → 0
        //   index 1: (0 + 0 + 30)/3          → 10
        //   index 2: (0 + 0 + 30 + 0 + 0)/5  → 6
        //   index 3: (30 + 0 + 0)/3          → 10
        //   index 4: half-width 0            → 0
        XCTAssertEqual(
            GradeAdjustedPace.smoothedAltitudes([0, 0, 30, 0, 0], radius: 2),
            [0, 10, 6, 10, 0]
        )
    }

    func testSmoothingIsANoOpWithoutARadiusOrEnoughPoints() {
        XCTAssertEqual(GradeAdjustedPace.smoothedAltitudes([0, 30, 0], radius: 0), [0, 30, 0])
        XCTAssertEqual(GradeAdjustedPace.smoothedAltitudes([0, 30], radius: 2), [0, 30])
    }

    // MARK: - Route cost factor

    func testFlatRouteHasACostFactorOfExactlyOne() throws {
        let route = try MetricsFixture.meridianRoute(altitudes: [100, 100, 100, 100])
        let factor = try XCTUnwrap(
            GradeAdjustedPace.weightedAdjustmentFactor(route: route, parameters: .default)
        )
        XCTAssertEqual(factor, 1, accuracy: 1e-9)
    }

    func testUniformClimbCostFactorIsMinettiAtTenPercent() throws {
        // One 0.01° step (1 111.9508 m) rising 111.19508 m is a grade of exactly 0.1.
        // Factor = Cr(0.1)/Cr(0) = 5.968214/3.6.
        let route = try MetricsFixture.meridianRoute(altitudes: [0, MetricsFixture.tenPercentRiseMeters])
        let factor = try XCTUnwrap(
            GradeAdjustedPace.weightedAdjustmentFactor(route: route, parameters: .default)
        )
        XCTAssertEqual(factor, 5.968214 / 3.6, accuracy: 1e-6)
    }

    func testRouteWithFewerThanTwoAltitudesHasNoFactor() throws {
        let noAltitudes = try MetricsFixture.meridianRoute(altitudes: [nil, nil, nil])
        XCTAssertNil(GradeAdjustedPace.weightedAdjustmentFactor(route: noAltitudes, parameters: .default))

        let oneAltitude = try MetricsFixture.meridianRoute(altitudes: [100, nil, nil])
        XCTAssertNil(GradeAdjustedPace.weightedAdjustmentFactor(route: oneAltitude, parameters: .default))
    }

    // MARK: - Grade-adjusted pace

    private func tenKilometresInAnHour(hasRoute: Bool = true) throws -> Workout {
        // 10 000 m in 3 600 s → a flat pace of 360 s/km.
        try Fixture.workout(durationSeconds: 3_600, distanceMeters: 10_000, hasRoute: hasRoute)
    }

    func testFlatRouteLeavesThePaceAlone() throws {
        let pace = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: try MetricsFixture.meridianRoute(altitudes: [50, 50, 50, 50]),
                parameters: .default
            )
        )
        XCTAssertEqual(pace, 360, accuracy: 1e-9)
    }

    func testClimbingMakesTheAdjustedPaceFasterThanThePaceRun() throws {
        // 360 s/km ÷ (5.968214/3.6) = 1 296/5.968214 ≈ 217.15 s/km. Uphill effort buys a
        // faster equivalent flat pace — the sign of this correction is the easiest thing
        // in the whole metric to get backwards.
        let pace = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: try MetricsFixture.meridianRoute(
                    altitudes: [0, MetricsFixture.tenPercentRiseMeters]
                ),
                parameters: .default
            )
        )
        XCTAssertEqual(pace, 1_296.0 / 5.968214, accuracy: 1e-4)
        XCTAssertLessThan(pace, 360)
    }

    func testDescendingMakesTheAdjustedPaceSlowerThanThePaceRun() throws {
        // Factor = Cr(−0.1)/Cr(0) = 2.151706/3.6, so 360 ÷ that = 1 296/2.151706 ≈ 602.3.
        let pace = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: try MetricsFixture.meridianRoute(
                    altitudes: [MetricsFixture.tenPercentRiseMeters, 0]
                ),
                parameters: .default
            )
        )
        XCTAssertEqual(pace, 1_296.0 / 2.151706, accuracy: 1e-4)
        XCTAssertGreaterThan(pace, 360)
    }

    func testRollingTerrainWithNoNetClimbIsStillHarderThanFlat() throws {
        // Up 10% for one step, back down 10% for the next: equal horizontal distances, so
        // the weighted factor is the plain mean
        //   (5.968214 + 2.151706) / (2 × 3.6) = 8.11992/7.2 ≈ 1.1278,
        // and the adjusted pace is 360 ÷ that = 2 592/8.11992 ≈ 319.21 s/km. Zero net
        // elevation, and still not a flat run.
        let route = try MetricsFixture.meridianRoute(
            altitudes: [0, MetricsFixture.tenPercentRiseMeters, 0]
        )
        let pace = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: route,
                parameters: MetricsFixture.unfiltered
            )
        )
        XCTAssertEqual(pace, 2_592.0 / 8.11992, accuracy: 1e-4)
    }

    /// The counterpart to the smoothing test, at the level the metric is actually read
    /// at: unfiltered, GPS altitude jitter on a flat road manufactures a climb the runner
    /// never ran.
    func testAltitudeJitterOnAFlatRoadIsFilteredOut() throws {
        // Eight fixes 111.195 m apart on a road that starts and ends at 100 m and never
        // actually goes anywhere, reported with the ±6 m of vertical noise a phone
        // considers normal.
        let jittery = try MetricsFixture.meridianRoute(
            altitudes: [100, 106, 94, 106, 94, 106, 94, 100],
            latitudeStepDegrees: 0.001
        )
        let workout = try tenKilometresInAnHour()

        let unfiltered = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: workout,
                route: jittery,
                parameters: MetricsFixture.unfiltered
            )
        )
        let filtered = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: workout,
                route: jittery,
                parameters: .default
            )
        )

        // Noise is asymmetric in the cost curve — a climb costs more than the matching
        // descent gives back — so raw point-to-point grade credits the runner with
        // effort they never spent. Here that is tens of seconds per kilometre on a road
        // with no net elevation change at all: the mean cost factor comes out near 1.12
        // instead of 1.
        XCTAssertLessThan(unfiltered, 340)
        // Smoothed, the same trace lands back on the pace actually run.
        XCTAssertEqual(filtered, 360, accuracy: 3)
        XCTAssertLessThan(abs(filtered - 360), abs(unfiltered - 360))
    }

    func testMeasuringGradeOverTooLongAStretchWashesHillsOut() throws {
        // The mirror-image failure, stated so the parameter's cost is on record: demand a
        // 5 km stretch from a 2.2 km route and the up-and-down folds into one flat
        // average, giving back exactly the unadjusted pace.
        let route = try MetricsFixture.meridianRoute(
            altitudes: [0, MetricsFixture.tenPercentRiseMeters, 0]
        )
        let pace = try XCTUnwrap(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: route,
                parameters: GradeAdjustmentParameters(
                    altitudeSmoothingRadius: 0,
                    minimumSegmentMeters: 5_000
                )
            )
        )
        XCTAssertEqual(pace, 360, accuracy: 1e-9)
    }

    // MARK: - Not applicable

    func testIndoorRunHasNoAdjustedPace() throws {
        let treadmill = try Fixture.workout(
            activityType: .treadmillRunning,
            durationSeconds: 3_600,
            distanceMeters: 10_000,
            hasRoute: false
        )
        XCTAssertNil(
            GradeAdjustedPace.secondsPerKilometer(workout: treadmill, route: nil, parameters: .default)
        )
    }

    func testRouteWithoutAltitudeHasNoAdjustedPace() throws {
        let route = try MetricsFixture.meridianRoute(altitudes: [nil, nil, nil])
        XCTAssertNil(
            GradeAdjustedPace.secondsPerKilometer(
                workout: try tenKilometresInAnHour(),
                route: route,
                parameters: .default
            )
        )
    }

    func testZeroDistanceOrDurationHasNoAdjustedPace() throws {
        let route = try MetricsFixture.meridianRoute(altitudes: [0, 10, 20])

        let noDistance = try Fixture.workout(durationSeconds: 3_600, distanceMeters: 0)
        XCTAssertNil(
            GradeAdjustedPace.secondsPerKilometer(workout: noDistance, route: route, parameters: .default)
        )

        let unmeasuredDistance = try Fixture.workout(durationSeconds: 3_600, distanceMeters: nil)
        XCTAssertNil(
            GradeAdjustedPace.secondsPerKilometer(
                workout: unmeasuredDistance, route: route, parameters: .default
            )
        )

        let noDuration = try Fixture.workout(durationSeconds: 0, distanceMeters: 10_000)
        XCTAssertNil(
            GradeAdjustedPace.secondsPerKilometer(workout: noDuration, route: route, parameters: .default)
        )
    }
}
