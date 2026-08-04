import Foundation

/// One raw heart-rate reading as the health store reports it: an absolute timestamp,
/// not yet converted to `HeartRateSample`'s workout-relative offset.
///
/// The conversion needs the workout's `start`, which only `WorkoutSampleExtractor`
/// holds — keeping the offset out of this type means an adapter never has to carry
/// that knowledge, only the reading itself.
public struct RawHeartRateSample: Hashable, Sendable {
    public let date: Date
    public let beatsPerMinute: Double

    public init(date: Date, beatsPerMinute: Double) {
        self.date = date
        self.beatsPerMinute = beatsPerMinute
    }
}

/// One page of a heart-rate sample fetch.
///
/// Bounded and re-requestable rather than "give me everything": a 90-minute run can
/// carry thousands of samples, and a background wake has an unspecified time budget
/// (tracker R8). `WorkoutSampleExtractor` drives repeated requests until a page comes
/// back shorter than `limit` — the same "short page means done" rule
/// `AnchoredWorkoutIngester` already uses for workouts themselves.
public struct HeartRateSampleFetchRequest: Hashable, Sendable {
    public let workoutID: UUID
    public let windowStart: Date
    public let windowEnd: Date

    /// Resume point: the adapter should return only samples timestamped at or after
    /// this instant. `nil` on the first page, meaning "from `windowStart`".
    ///
    /// Nudged fractionally past the previous page's last sample by the extractor,
    /// rather than left exactly equal to it — an inclusive re-query at the exact
    /// boundary instant would hand the same sample back twice. See
    /// `WorkoutSampleExtractor`.
    public let after: Date?

    /// Maximum samples this page may contain.
    public let limit: Int

    public init(workoutID: UUID, windowStart: Date, windowEnd: Date, after: Date?, limit: Int) throws {
        guard windowEnd >= windowStart else {
            throw DomainError.inconsistent(
                reason: "HeartRateSampleFetchRequest.windowEnd must not precede windowStart"
            )
        }
        guard limit >= 1 else {
            throw DomainError.outOfRange(
                field: "HeartRateSampleFetchRequest.limit",
                value: Double(limit),
                lowerBound: 1,
                upperBound: nil
            )
        }
        self.workoutID = workoutID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.after = after
        self.limit = limit
    }
}

/// What one heart-rate page fetch returned.
public struct HeartRateSampleFetchPage: Hashable, Sendable {
    /// Samples for this page, in whatever order the health store returned them.
    /// `WorkoutSampleExtractor` sorts and validates; nothing here is assumed ordered
    /// (per this ticket: "HealthKit's return order is not something to assume").
    public let samples: [RawHeartRateSample]

    public init(samples: [RawHeartRateSample]) {
        self.samples = samples
    }
}

/// One raw GPS fix, before it becomes a `RoutePoint` with a workout-relative offset.
public struct RawRoutePoint: Hashable, Sendable {
    public let date: Date
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let altitudeMeters: Double?
    public let speedMetersPerSecond: Double?

    public init(
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        altitudeMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) {
        self.date = date
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

/// One route fetch.
///
/// Unlike heart rate, this is **not** paged from the core's side. Apple's route API
/// (`HKWorkoutRouteQuery`) streams a route's locations to its caller through repeated
/// callbacks with no query-level limit — there is no per-page cursor for the core to
/// drive the way `after`/`limit` drive heart rate. `maxPoints` is instead a safety cap
/// the *adapter* enforces while draining those callbacks, so one route query still
/// cannot hand back an unbounded amount of data during a short background wake.
public struct RouteFetchRequest: Hashable, Sendable {
    public let workoutID: UUID
    public let windowStart: Date
    public let windowEnd: Date
    public let maxPoints: Int

    public init(workoutID: UUID, windowStart: Date, windowEnd: Date, maxPoints: Int) throws {
        guard windowEnd >= windowStart else {
            throw DomainError.inconsistent(reason: "RouteFetchRequest.windowEnd must not precede windowStart")
        }
        guard maxPoints >= 1 else {
            throw DomainError.outOfRange(
                field: "RouteFetchRequest.maxPoints",
                value: Double(maxPoints),
                lowerBound: 1,
                upperBound: nil
            )
        }
        self.workoutID = workoutID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.maxPoints = maxPoints
    }
}

/// What one route fetch returned.
public struct RouteFetchResult: Hashable, Sendable {
    /// `nil` when the health store has no route object for this workout — FR-0.6's
    /// *absence*, not an empty array. A route object that exists but streamed zero
    /// usable locations is reported the same way: there is nothing to draw either way,
    /// and `WorkoutSampleExtractor` does not need to tell the two apart.
    public let points: [RawRoutePoint]?

    /// True when `maxPoints` was reached before the route finished streaming, so the
    /// caller has a genuine partial route rather than the whole thing.
    public let truncated: Bool

    public init(points: [RawRoutePoint]?, truncated: Bool = false) {
        self.points = points
        self.truncated = truncated
    }
}

/// Reads full-fidelity per-workout samples out of the health store (FR-0.3).
///
/// The implementation is a HealthKit adapter in the app layer, which CI cannot execute
/// (CLAUDE.md — "What CI can and cannot prove"). As with `WorkoutFetching`, everything
/// above this line is kept free of judgement: each method runs one query — or, for
/// routes, drains one query's callbacks up to a safety cap — and returns what it found.
/// `WorkoutSampleExtractor` decides how many pages to request, when a gap is
/// recoverable, and how raw readings become domain values.
public protocol WorkoutSampleFetching: Sendable {
    /// One page of heart-rate samples for the workout's window.
    func fetchHeartRateSamples(_ request: HeartRateSampleFetchRequest) async throws -> HeartRateSampleFetchPage

    /// The workout's full route, or the absence of one.
    func fetchRoute(_ request: RouteFetchRequest) async throws -> RouteFetchResult

    /// Total steps recorded over the workout window, or `nil` if the source reported
    /// none. Cadence (§9) is derived from this total, not fetched as a sample series —
    /// it is an aggregate the same way `Workout.activeEnergyKilocalories` already is.
    func fetchTotalStepCount(workoutID: UUID, windowStart: Date, windowEnd: Date) async throws -> Double?
}
