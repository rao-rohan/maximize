import Foundation

/// One GPS fix: `{t, lat, lon, alt, speed}` in PRD §8 terms.
///
/// Altitude and speed are optional because Core Location genuinely omits them (a fix
/// with no vertical accuracy has no meaningful altitude, and a stationary fix may
/// report no speed). Grade-adjusted pace (§9) is therefore a *conditional* metric,
/// and modelling the absence here is what lets MAX-012 say so honestly instead of
/// treating a missing altitude as sea level.
public struct RoutePoint: Hashable, Sendable, Codable, Comparable {
    /// Seconds since the workout started, matching `HeartRateSample.offsetSeconds` so
    /// the two series can be aligned without a shared clock.
    public let offsetSeconds: Double
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    /// Metres above sea level.
    public let altitudeMeters: Double?
    /// Instantaneous speed in metres per second.
    public let speedMetersPerSecond: Double?

    public init(
        offsetSeconds: Double,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        altitudeMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) throws {
        try Validate.nonNegative(offsetSeconds, "RoutePoint.offsetSeconds")
        try Validate.within(latitudeDegrees, -90...90, "RoutePoint.latitudeDegrees")
        try Validate.within(longitudeDegrees, -180...180, "RoutePoint.longitudeDegrees")
        // Below the Dead Sea shore or above the troposphere means a bad fix, not a run.
        try Validate.optionalWithin(altitudeMeters, -500...9_000, "RoutePoint.altitudeMeters")
        try Validate.optionalNonNegative(speedMetersPerSecond, "RoutePoint.speedMetersPerSecond")

        self.offsetSeconds = offsetSeconds
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }

    public static func < (lhs: RoutePoint, rhs: RoutePoint) -> Bool {
        lhs.offsetSeconds < rhs.offsetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case offsetSeconds, latitudeDegrees, longitudeDegrees, altitudeMeters, speedMetersPerSecond
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            offsetSeconds: container.decode(Double.self, forKey: .offsetSeconds),
            latitudeDegrees: container.decode(Double.self, forKey: .latitudeDegrees),
            longitudeDegrees: container.decode(Double.self, forKey: .longitudeDegrees),
            altitudeMeters: container.decodeIfPresent(Double.self, forKey: .altitudeMeters),
            speedMetersPerSecond: container.decodeIfPresent(Double.self, forKey: .speedMetersPerSecond)
        )
    }
}

/// The GPS track for one workout (PRD §8 `route`).
///
/// A route is **absent**, not empty, for indoor runs. FR-0.6 makes treadmill runs
/// first-class: the heart-rate curve is the point, and nothing in the domain should
/// read a missing route as a defect. Consumers get `Route?` and are expected to
/// render the no-route case deliberately (FR-1.4), not apologetically.
public struct Route: Hashable, Sendable, Codable {
    public let workoutID: UUID
    public let points: [RoutePoint]

    /// - Parameter points: non-empty and strictly ascending by `offsetSeconds`.
    public init(workoutID: UUID, points: [RoutePoint]) throws {
        guard !points.isEmpty else {
            throw DomainError.empty(field: "Route.points")
        }
        for index in 1..<points.count where points[index].offsetSeconds <= points[index - 1].offsetSeconds {
            if points[index].offsetSeconds == points[index - 1].offsetSeconds {
                throw DomainError.duplicate(
                    field: "Route.points",
                    key: "offsetSeconds=\(points[index].offsetSeconds)"
                )
            }
            throw DomainError.outOfOrder(field: "Route.points", index: index)
        }
        self.workoutID = workoutID
        self.points = points
    }

    public init(workoutID: UUID, sorting points: [RoutePoint]) throws {
        try self.init(workoutID: workoutID, points: points.sorted())
    }

    public var count: Int { points.count }

    /// True when at least two points carry an altitude, which is the minimum for a
    /// grade to exist at all (§9, grade-adjusted pace).
    public var hasUsableAltitude: Bool {
        points.filter { $0.altitudeMeters != nil }.count >= 2
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID, points
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            points: container.decode([RoutePoint].self, forKey: .points)
        )
    }
}
