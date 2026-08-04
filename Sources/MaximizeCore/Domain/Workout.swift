import Foundation

/// The kind of activity a workout was, as reported by the capture source.
///
/// Deliberately an open string wrapper rather than a closed `enum`: HealthKit has
/// dozens of activity types and gains more each release, and an unknown one must
/// degrade to "some other activity" rather than fail to decode a run the user
/// actually did. The cases we reason about are named constants.
public struct ActivityType: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let running = ActivityType(rawValue: "running")
    /// Indoor / treadmill running. First-class, not a degraded run: it simply has no
    /// route (FR-0.6).
    public static let treadmillRunning = ActivityType(rawValue: "treadmillRunning")
    public static let walking = ActivityType(rawValue: "walking")
    public static let hiking = ActivityType(rawValue: "hiking")
    public static let cycling = ActivityType(rawValue: "cycling")
    public static let traditionalStrengthTraining = ActivityType(rawValue: "traditionalStrengthTraining")
    public static let other = ActivityType(rawValue: "other")

    /// Whether this type is one the plan scores as a run. Strength work is explicitly
    /// out of scope for HR scoring (PRD §3 non-goals).
    public var isRun: Bool {
        self == .running || self == .treadmillRunning
    }

    /// Whether the activity is expected to carry a GPS route. Indoor runs answering
    /// `false` here is the point of FR-0.6.
    public var isOutdoorByNature: Bool {
        self == .running || self == .walking || self == .hiking || self == .cycling
    }

    public var description: String { rawValue }

    // Written out rather than left to the RawRepresentable/Codable default so the
    // encoded form is unambiguously a bare string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where a workout came from. Recorded for provenance; the app never writes to
/// HealthKit (PRD §3), so every workout originates outside it.
public struct WorkoutSource: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appleWatch = WorkoutSource(rawValue: "appleWatch")
    public static let iPhone = WorkoutSource(rawValue: "iPhone")
    public static let unknown = WorkoutSource(rawValue: "unknown")

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A completed workout as captured from the health store (PRD §8 `workout`).
///
/// This is the raw record only. Everything computed from it lives in
/// `DerivedMetrics`, which is calculated once at ingestion and stored (D2) — never
/// recomputed here at display time.
public struct Workout: Hashable, Sendable, Codable, Identifiable {
    /// HealthKit's workout UUID. It is the primary key and the dedupe key for
    /// idempotent ingestion (FR-0.5, A2).
    public let id: UUID
    public let activityType: ActivityType
    public let start: Date
    public let end: Date

    /// Active duration in seconds. Stored separately from `end - start` on purpose:
    /// a paused workout has a wall-clock span longer than its duration, and the
    /// metrics care about the latter.
    public let durationSeconds: Double

    /// Total distance in **meters**. Nil for activities that do not measure distance.
    /// Meters is the storage unit everywhere in the core; miles/kilometers are a
    /// display concern (`AppSettings.distanceUnit`).
    public let distanceMeters: Double?

    /// Active energy burned in **kilocalories** (the "calories" a fitness app shows).
    public let activeEnergyKilocalories: Double?

    /// Whether the capture source recorded a GPS route for this workout. Kept as a
    /// stored flag rather than derived from a `Route` value because ingestion learns
    /// it before it fetches the route, and an indoor run legitimately has none.
    public let hasRoute: Bool

    public let source: WorkoutSource

    /// When this record entered the local store. Distinct from `end`: HealthKit sync
    /// and background-delivery throttling can put minutes or hours between them
    /// (PRD §13).
    public let ingestedAt: Date

    public init(
        id: UUID,
        activityType: ActivityType,
        start: Date,
        end: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        hasRoute: Bool,
        source: WorkoutSource,
        ingestedAt: Date
    ) throws {
        guard end >= start else {
            throw DomainError.inconsistent(reason: "Workout.end must not precede Workout.start")
        }
        try Validate.nonNegative(durationSeconds, "Workout.durationSeconds")
        // A tolerance, not a rounding fudge: HealthKit's duration and its
        // start/end stamps are recorded independently and disagree by fractions of a
        // second on real workouts. A duration meaningfully longer than the elapsed
        // span, though, means the two fields describe different workouts.
        let elapsed = end.timeIntervalSince(start)
        guard durationSeconds <= elapsed + 1 else {
            throw DomainError.inconsistent(
                reason: "Workout.durationSeconds (\(durationSeconds)) exceeds elapsed time (\(elapsed))"
            )
        }
        try Validate.optionalNonNegative(distanceMeters, "Workout.distanceMeters")
        try Validate.optionalNonNegative(activeEnergyKilocalories, "Workout.activeEnergyKilocalories")

        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.hasRoute = hasRoute
        self.source = source
        self.ingestedAt = ingestedAt
    }

    /// Wall-clock span in seconds, including any paused time.
    public var elapsedSeconds: Double {
        end.timeIntervalSince(start)
    }

    /// The calendar day this workout is scored against, in the given time zone. The
    /// *start* is what anchors it: a run beginning at 23:50 belongs to the day it was
    /// started, which is how a person describes it.
    public func calendarDay(in timeZone: TimeZone) throws -> CalendarDay {
        try CalendarDay(start, in: timeZone)
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityType, start, end, durationSeconds, distanceMeters
        case activeEnergyKilocalories, hasRoute, source, ingestedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            activityType: container.decode(ActivityType.self, forKey: .activityType),
            start: container.decode(Date.self, forKey: .start),
            end: container.decode(Date.self, forKey: .end),
            durationSeconds: container.decode(Double.self, forKey: .durationSeconds),
            distanceMeters: container.decodeIfPresent(Double.self, forKey: .distanceMeters),
            activeEnergyKilocalories: container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories),
            hasRoute: container.decode(Bool.self, forKey: .hasRoute),
            source: container.decode(WorkoutSource.self, forKey: .source),
            ingestedAt: container.decode(Date.self, forKey: .ingestedAt)
        )
    }
}
