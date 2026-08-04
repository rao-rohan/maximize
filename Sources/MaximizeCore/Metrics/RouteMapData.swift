import Foundation

/// Chart-ready — or rather, map-ready — presentation of one workout's route (FR-1.4):
/// everything a map view needs to draw the track and frame it, precomputed here so CI,
/// not a device, verifies the framing math. Mirrors the discipline `HeartRateChartData`
/// (MAX-042) and `CadenceChartData` (MAX-043) established: this is the module's only
/// public door onto a route for display purposes, and it decides *what to draw and how
/// to frame it*, never *how many meters were covered* — that stays `DerivedMetrics`'
/// job (D2). Nothing here sums a distance or a pace from these coordinates.
///
/// `MaximizeCore` must not import MapKit (CLAUDE.md's architecture job greps for it),
/// so `Coordinate` and `Region` are plain degree pairs — the `App` layer's map view
/// turns them into `CLLocationCoordinate2D`/`MKCoordinateRegion` and does nothing else
/// with them.
///
/// ## The three states FR-1.4 has to get right
///
/// `resolve(hasRoute:route:)` is where the *decision* of which state a workout is in
/// lives, so it is unit tested rather than left to a branch in a view:
///
/// - **`.noRoute`** — an indoor/treadmill run. `Workout.hasRoute` is false, meaning no
///   route was ever captured. FR-0.6 makes this first-class, not a degraded case: there
///   was never a route to draw, so the section omits itself cleanly rather than
///   apologizing for an absence.
/// - **`.unavailable`** — `Workout.hasRoute` is true (the capture source recorded one)
///   but `WorkoutRepository.route(forWorkout:)` returned nil. Distinct from `.noRoute`
///   on purpose: this is an outdoor run whose route could not be loaded, not a run that
///   never had one, and the view can say so honestly instead of collapsing both into
///   silence.
/// - **`.available`** — a route to draw, with its coordinates and framing resolved.
public enum RouteMapData: Hashable, Sendable {
    case noRoute
    case unavailable
    case available(Content)

    /// The stored route, prepared for drawing.
    public struct Content: Hashable, Sendable {
        /// One GPS fix, in the plain (lat, lon) a map draws — altitude and speed are
        /// not part of what FR-1.4 asks to be drawn, so they are left off rather than
        /// carried through unused.
        public struct Coordinate: Hashable, Sendable {
            public let latitudeDegrees: Double
            public let longitudeDegrees: Double

            public init(latitudeDegrees: Double, longitudeDegrees: Double) {
                self.latitudeDegrees = latitudeDegrees
                self.longitudeDegrees = longitudeDegrees
            }
        }

        /// A MapKit-agnostic bounding region: center + span, in degrees — the plain
        /// data an `MKCoordinateRegion` is built from, without this module ever naming
        /// that type.
        public struct Region: Hashable, Sendable {
            public let centerLatitudeDegrees: Double
            public let centerLongitudeDegrees: Double
            public let latitudeDeltaDegrees: Double
            public let longitudeDeltaDegrees: Double

            public init(
                centerLatitudeDegrees: Double,
                centerLongitudeDegrees: Double,
                latitudeDeltaDegrees: Double,
                longitudeDeltaDegrees: Double
            ) {
                self.centerLatitudeDegrees = centerLatitudeDegrees
                self.centerLongitudeDegrees = centerLongitudeDegrees
                self.latitudeDeltaDegrees = latitudeDeltaDegrees
                self.longitudeDeltaDegrees = longitudeDeltaDegrees
            }
        }

        /// One point per stored fix, in the route's recorded order — a straight
        /// pass-through, the same discipline `HeartRateChartData.points` follows: no
        /// simplification or resampling happens here.
        public let coordinates: [Coordinate]

        /// The region a map should frame the route in: centered on the route's
        /// bounding box, padded so the track is never drawn flush against the map's
        /// edge.
        public let region: Region

        /// - Parameter route: the stored route (`WorkoutRepository.route(forWorkout:)`).
        ///   Never recomputes distance, pace, or anything else from these coordinates
        ///   (D2) — this type exists only to turn them into something a map can draw
        ///   and a region to frame it in.
        public init(route: Route) {
            self.coordinates = route.points.map {
                Coordinate(latitudeDegrees: $0.latitudeDegrees, longitudeDegrees: $0.longitudeDegrees)
            }
            self.region = Self.boundingRegion(for: coordinates)
        }

        /// The smallest box containing every coordinate, padded by a fraction of its
        /// own span so the route's edges are not drawn flush against the map's frame,
        /// and floored to a minimum span so a short out-and-back near a single point —
        /// or `Route`'s minimum of one point — still frames at a legible zoom level
        /// rather than collapsing to a region with no usable extent.
        private static func boundingRegion(for coordinates: [Coordinate]) -> Region {
            // `Route.init` rejects an empty `points`, so this always has a first
            // element on the live path — the guard exists so this stays total rather
            // than force-unwrapping, per CLAUDE.md's no-`!` rule.
            guard let first = coordinates.first else {
                return Region(
                    centerLatitudeDegrees: 0,
                    centerLongitudeDegrees: 0,
                    latitudeDeltaDegrees: minimumSpanDegrees,
                    longitudeDeltaDegrees: minimumSpanDegrees
                )
            }

            var minLatitude = first.latitudeDegrees
            var maxLatitude = first.latitudeDegrees
            var minLongitude = first.longitudeDegrees
            var maxLongitude = first.longitudeDegrees
            for coordinate in coordinates {
                minLatitude = Swift.min(minLatitude, coordinate.latitudeDegrees)
                maxLatitude = Swift.max(maxLatitude, coordinate.latitudeDegrees)
                minLongitude = Swift.min(minLongitude, coordinate.longitudeDegrees)
                maxLongitude = Swift.max(maxLongitude, coordinate.longitudeDegrees)
            }

            let latitudeSpan = Swift.max((maxLatitude - minLatitude) * paddingFactor, minimumSpanDegrees)
            let longitudeSpan = Swift.max((maxLongitude - minLongitude) * paddingFactor, minimumSpanDegrees)

            return Region(
                centerLatitudeDegrees: (minLatitude + maxLatitude) / 2,
                centerLongitudeDegrees: (minLongitude + maxLongitude) / 2,
                latitudeDeltaDegrees: latitudeSpan,
                longitudeDeltaDegrees: longitudeSpan
            )
        }

        /// Widens the raw bounding box by a quarter on each side so the track's own
        /// extremities land inside the frame rather than on its border.
        private static let paddingFactor = 1.3

        /// Roughly 300m of latitude span at the equator — enough to show a single GPS
        /// fix, or a route so short its bounding box is a point, at a zoom level a map
        /// can actually render (`MKCoordinateRegion` misbehaves at a zero-degree span).
        private static let minimumSpanDegrees = 0.003
    }

    /// Decides which of FR-1.4's three states this workout is in — the branch this
    /// ticket exists to push out of a view and into a place CI verifies (CLAUDE.md,
    /// "thin shell, fat core").
    ///
    /// - Parameters:
    ///   - hasRoute: `Workout.hasRoute` — whether the capture source recorded a route
    ///     for this workout at all. False for every indoor run (FR-0.6) by
    ///     construction.
    ///   - route: `WorkoutRepository.route(forWorkout:)`'s result. Only consulted when
    ///     `hasRoute` is true — the read is not made otherwise.
    public static func resolve(hasRoute: Bool, route: Route?) -> RouteMapData {
        guard hasRoute else { return .noRoute }
        guard let route else { return .unavailable }
        return .available(Content(route: route))
    }
}
