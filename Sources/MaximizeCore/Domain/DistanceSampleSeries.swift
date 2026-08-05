import Foundation

/// One reading from HealthKit's `distanceWalkingRunning` quantity type: the ground
/// covered since the previous sample, ending at `offsetSeconds`.
///
/// This is the incremental shape HealthKit itself reports a cumulative-type quantity
/// in — a run's distance series is a sequence of short deltas, not a sequence of
/// running totals — so `meters` is that delta, and `DistanceSplitCalculator` sums
/// them into a cumulative distance-versus-time curve the same way it already sums
/// haversine distances between consecutive GPS fixes for an outdoor `Route`. One
/// arithmetic idea, two sources.
public struct DistanceSample: Hashable, Sendable, Codable, Comparable {
    /// Seconds since the workout started, matching `HeartRateSample.offsetSeconds`
    /// and `RoutePoint.offsetSeconds`.
    public let offsetSeconds: Double

    /// Metres covered since the previous sample. Never negative — a treadmill belt
    /// does not run backwards, and a distance quantity type does not report it doing
    /// so.
    public let meters: Double

    public init(offsetSeconds: Double, meters: Double) throws {
        try Validate.nonNegative(offsetSeconds, "DistanceSample.offsetSeconds")
        try Validate.nonNegative(meters, "DistanceSample.meters")
        self.offsetSeconds = offsetSeconds
        self.meters = meters
    }

    public static func < (lhs: DistanceSample, rhs: DistanceSample) -> Bool {
        lhs.offsetSeconds < rhs.offsetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case offsetSeconds, meters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            offsetSeconds: container.decode(Double.self, forKey: .offsetSeconds),
            meters: container.decode(Double.self, forKey: .meters)
        )
    }
}

/// One workout's distance-sample series (MAX-066): the time-versus-distance relation
/// an indoor run has instead of a GPS `Route`.
///
/// `distanceWalkingRunning` is already authorised for HR and step-count purposes; this
/// is the same quantity type read as a series instead of a single cumulative total, so
/// a treadmill run gets a genuine per-split breakdown (FR-1.5) rather than none at all
/// (FR-0.6).
///
/// Same ordering invariant as `Route` and `HeartRateSeries`: strictly ascending by
/// `offsetSeconds`, non-empty. Absence is `DerivedMetricsInput.distanceSamples == nil`,
/// never an empty series — a workout the source recorded no distance samples for looks
/// the same as one that was never asked.
///
/// This series is **not stored**, unlike `Route` and `HeartRateSeries`. Nothing else in
/// the app reads a treadmill's raw distance curve — D7 stores whole curves so the
/// cross-run drift overlay (D5) can read them, and that overlay is heart-rate-only.
/// `DistanceSplitCalculator` consumes this once, at ingestion, and only its output
/// (`DerivedMetrics.distanceSplits`) is durable (D2).
public struct DistanceSampleSeries: Hashable, Sendable, Codable {
    public let workoutID: UUID
    public let samples: [DistanceSample]

    /// - Parameter samples: must be non-empty and strictly ascending by
    ///   `offsetSeconds`.
    public init(workoutID: UUID, samples: [DistanceSample]) throws {
        guard !samples.isEmpty else {
            throw DomainError.empty(field: "DistanceSampleSeries.samples")
        }
        for index in 1..<samples.count where samples[index].offsetSeconds <= samples[index - 1].offsetSeconds {
            if samples[index].offsetSeconds == samples[index - 1].offsetSeconds {
                throw DomainError.duplicate(
                    field: "DistanceSampleSeries.samples",
                    key: "offsetSeconds=\(samples[index].offsetSeconds)"
                )
            }
            throw DomainError.outOfOrder(field: "DistanceSampleSeries.samples", index: index)
        }
        self.workoutID = workoutID
        self.samples = samples
    }

    /// Convenience for ingestion, where the health store returns samples in an order
    /// nobody has promised — mirrors `HeartRateSeries.init(workoutID:sorting:)`.
    public init(workoutID: UUID, sorting samples: [DistanceSample]) throws {
        try self.init(workoutID: workoutID, samples: samples.sorted())
    }

    public var count: Int { samples.count }

    private enum CodingKeys: String, CodingKey {
        case workoutID, samples
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            samples: container.decode([DistanceSample].self, forKey: .samples)
        )
    }
}
