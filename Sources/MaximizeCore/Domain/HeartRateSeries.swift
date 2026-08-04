import Foundation

/// One heart-rate sample: `{t, bpm}` in PRD §8 terms.
///
/// `t` is stored as **seconds elapsed from the workout's start**, not as an absolute
/// timestamp. The drift overlay (D5) plots curves against *% of run elapsed*, which
/// is a function of offsets; keeping offsets primary means that view never has to
/// subtract a start date it would have to fetch separately.
public struct HeartRateSample: Hashable, Sendable, Codable, Comparable {
    /// Seconds since the workout started. Non-negative.
    public let offsetSeconds: Double

    /// Instantaneous heart rate in beats per minute.
    public let beatsPerMinute: Double

    /// Physiologically plausible bounds for a wrist sensor. Values outside these are
    /// sensor artefacts, and averaging them silently is how a drift number becomes a
    /// lie.
    public static let plausibleBPM: ClosedRange<Double> = 20...250

    public init(offsetSeconds: Double, beatsPerMinute: Double) throws {
        try Validate.nonNegative(offsetSeconds, "HeartRateSample.offsetSeconds")
        try Validate.within(beatsPerMinute, HeartRateSample.plausibleBPM, "HeartRateSample.beatsPerMinute")
        self.offsetSeconds = offsetSeconds
        self.beatsPerMinute = beatsPerMinute
    }

    public static func < (lhs: HeartRateSample, rhs: HeartRateSample) -> Bool {
        lhs.offsetSeconds < rhs.offsetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case offsetSeconds, beatsPerMinute
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            offsetSeconds: container.decode(Double.self, forKey: .offsetSeconds),
            beatsPerMinute: container.decode(Double.self, forKey: .beatsPerMinute)
        )
    }
}

/// The full heart-rate curve for one workout (PRD §8 `hr_series`).
///
/// D7 keeps this a whole-curve blob rather than normalized per-sample rows, because
/// every consumer — the detail-view curve, time-above-cap, drift, the cross-run
/// overlay — reads entire curves. There is no query here to optimize for.
///
/// The invariant is strict time ordering: samples are sorted ascending by offset with
/// no two samples sharing an offset. Every metric downstream (first-half vs
/// second-half drift, time-above-cap by trapezoid) assumes it, and an unsorted series
/// produces a plausible-looking wrong number rather than an error.
public struct HeartRateSeries: Hashable, Sendable, Codable {
    public let workoutID: UUID
    public let samples: [HeartRateSample]

    /// - Parameter samples: must be non-empty and strictly ascending by
    ///   `offsetSeconds`. A workout with no heart-rate data is represented by having
    ///   no series at all, not by an empty one.
    public init(workoutID: UUID, samples: [HeartRateSample]) throws {
        guard !samples.isEmpty else {
            throw DomainError.empty(field: "HeartRateSeries.samples")
        }
        for index in 1..<samples.count where samples[index].offsetSeconds <= samples[index - 1].offsetSeconds {
            if samples[index].offsetSeconds == samples[index - 1].offsetSeconds {
                throw DomainError.duplicate(
                    field: "HeartRateSeries.samples",
                    key: "offsetSeconds=\(samples[index].offsetSeconds)"
                )
            }
            throw DomainError.outOfOrder(field: "HeartRateSeries.samples", index: index)
        }
        self.workoutID = workoutID
        self.samples = samples
    }

    /// Convenience for ingestion, where the health store returns samples in an order
    /// nobody has promised. Sorting is a deliberate, named act; the primary
    /// initializer still rejects unsorted input so a caller cannot drift into
    /// relying on silent repair.
    public init(workoutID: UUID, sorting samples: [HeartRateSample]) throws {
        try self.init(workoutID: workoutID, samples: samples.sorted())
    }

    public var count: Int { samples.count }

    /// Total accessors rather than optionals: the initializers guarantee at least one
    /// sample, so indexing is safe and callers are spared an `if let` that can never
    /// take its else branch.
    public var firstSample: HeartRateSample { samples[0] }

    public var lastSample: HeartRateSample { samples[samples.count - 1] }

    /// Span covered by the curve, in seconds.
    public var coveredSeconds: Double {
        lastSample.offsetSeconds - firstSample.offsetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID, samples
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            samples: container.decode([HeartRateSample].self, forKey: .samples)
        )
    }
}
