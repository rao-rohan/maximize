import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-044: the map-ready presentation FR-1.4's route section is built from.
///
/// Two things are the point of this file, mirroring `HeartRateChartDataTests` (MAX-042)
/// and `CadenceChartDataTests` (MAX-043):
///
/// - `resolve(hasRoute:route:)` is the whole of "which of the three states is this
///   workout in" — the branch this ticket pushes out of the view — so every combination
///   of `hasRoute` and a present/absent stored route is pinned here.
/// - The bounding region never recomputes anything about the route besides its own
///   framing: coordinates are a straight pass-through, and the padding/floor math is
///   exercised the way `CadenceChartDataTests` exercises `axisDomain`.
final class RouteMapDataTests: XCTestCase {
    // MARK: - resolve(hasRoute:route:) — the three states

    /// FR-0.6: an indoor run. No route was ever captured, so there is nothing to say
    /// "could not be loaded" about — this is `.noRoute`, not `.unavailable`.
    func testIndoorRunResolvesToNoRoute() {
        XCTAssertEqual(RouteMapData.resolve(hasRoute: false, route: nil), .noRoute)
    }

    /// A `hasRoute` flag with no matching stored route is still `.noRoute` — `hasRoute`
    /// is the only signal this decides on, never inferred from whether a route happens
    /// to be present.
    func testHasRouteFalseResolvesToNoRouteEvenIfARouteIsSomehowPassed() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0)])
        XCTAssertEqual(RouteMapData.resolve(hasRoute: false, route: route), .noRoute)
    }

    /// The state FR-1.4 asks to be distinguished from `.noRoute`: an outdoor run the
    /// capture source says had a route, but the store does not have it.
    func testOutdoorRunWithNoStoredRouteResolvesToUnavailable() {
        XCTAssertEqual(RouteMapData.resolve(hasRoute: true, route: nil), .unavailable)
    }

    func testOutdoorRunWithAStoredRouteResolvesToAvailable() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0), (60, 40.001, -74.001)])
        guard case .available(let content) = RouteMapData.resolve(hasRoute: true, route: route) else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(content.coordinates.count, 2)
    }

    // MARK: - Coordinates are a straight pass-through

    func testCoordinatesMatchTheStoredPointsInOrder() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0), (30, 40.001, -74.002), (60, 40.002, -74.004)])
        let content = RouteMapData.Content(route: route)

        XCTAssertEqual(content.coordinates.map(\.latitudeDegrees), [40.0, 40.001, 40.002])
        XCTAssertEqual(content.coordinates.map(\.longitudeDegrees), [-74.0, -74.002, -74.004])
    }

    // MARK: - Bounding region

    func testRegionIsCenteredOnTheBoundingBox() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0), (60, 40.010, -74.020)])
        let content = RouteMapData.Content(route: route)

        XCTAssertEqual(content.region.centerLatitudeDegrees, 40.005, accuracy: 1e-9)
        XCTAssertEqual(content.region.centerLongitudeDegrees, -74.010, accuracy: 1e-9)
    }

    /// The load-bearing case for framing: the span has to comfortably contain the
    /// route's own extremities, not sit flush against them.
    func testRegionSpanCoversTheFullBoundingBoxWithRoomToSpare() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0), (60, 40.010, -74.020)])
        let content = RouteMapData.Content(route: route)

        let latSpan = 40.010 - 40.0
        let lonSpan = -74.0 - (-74.020)
        XCTAssertGreaterThan(content.region.latitudeDeltaDegrees, latSpan)
        XCTAssertGreaterThan(content.region.longitudeDeltaDegrees, lonSpan)
    }

    /// A route whose bounding box collapses to (near) a point — an out-and-back GPS
    /// track near a single spot, or `Route`'s minimum of one point — still gets a
    /// nonzero, renderable span rather than a degenerate region.
    func testRegionSpanIsFlooredForASinglePointRoute() throws {
        let route = try Fixture.route(points: [(0, 40.0, -74.0)])
        let content = RouteMapData.Content(route: route)

        XCTAssertGreaterThan(content.region.latitudeDeltaDegrees, 0)
        XCTAssertGreaterThan(content.region.longitudeDeltaDegrees, 0)
    }

    func testRegionSpanIsFlooredEvenForTwoNearlyIdenticalPoints() throws {
        // Distinct enough to satisfy `Route`'s strictly-ascending-offset invariant,
        // but close enough in space that the naive padded span would be negligible.
        let route = try Fixture.route(points: [(0, 40.0, -74.0), (1, 40.0000001, -74.0000001)])
        let content = RouteMapData.Content(route: route)

        XCTAssertGreaterThanOrEqual(content.region.latitudeDeltaDegrees, 0.001)
        XCTAssertGreaterThanOrEqual(content.region.longitudeDeltaDegrees, 0.001)
    }
}

private extension Fixture {
    /// A `Route` built from `(offsetSeconds, latitude, longitude)` triples — the
    /// shorthand `RouteMapDataTests` needs, kept local to this file since no other test
    /// yet constructs routes directly.
    static func route(points: [(Double, Double, Double)]) throws -> Route {
        try Route(
            workoutID: Fixture.workoutID,
            points: try points.map { try RoutePoint(offsetSeconds: $0.0, latitudeDegrees: $0.1, longitudeDegrees: $0.2) }
        )
    }
}
