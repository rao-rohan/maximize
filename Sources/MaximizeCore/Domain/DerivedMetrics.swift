import Foundation

/// A heart-rate zone, anchored to the plan's cap (§9, "zones relative to the plan's
/// cap-anchored zones"). Five zones is the conventional split; the boundaries are a
/// plan concern, not an identity concern, so only the label lives here.
public enum HeartRateZone: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    public static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Time spent in each heart-rate zone.
///
/// Absent zones mean zero seconds, not unknown — a run that never reached zone 5
/// simply has no zone-5 entry.
public struct ZoneSplits: Hashable, Sendable, Codable {
    public struct Split: Hashable, Sendable, Codable {
        public let zone: HeartRateZone
        public let seconds: Double

        public init(zone: HeartRateZone, seconds: Double) throws {
            try Validate.nonNegative(seconds, "ZoneSplits.Split.seconds")
            self.zone = zone
            self.seconds = seconds
        }

        private enum CodingKeys: String, CodingKey {
            case zone, seconds
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                zone: container.decode(HeartRateZone.self, forKey: .zone),
                seconds: container.decode(Double.self, forKey: .seconds)
            )
        }
    }

    /// Ordered by zone, at most one entry per zone.
    public let splits: [Split]

    public init(splits: [Split]) throws {
        var seen = Set<HeartRateZone>()
        for split in splits {
            guard seen.insert(split.zone).inserted else {
                throw DomainError.duplicate(field: "ZoneSplits.splits", key: "zone=\(split.zone.rawValue)")
            }
        }
        self.splits = splits.sorted { $0.zone < $1.zone }
    }

    public static let empty = ZoneSplits(alreadySortedAndUnique: [])

    private init(alreadySortedAndUnique splits: [Split]) {
        self.splits = splits
    }

    public func seconds(in zone: HeartRateZone) -> Double {
        splits.first { $0.zone == zone }?.seconds ?? 0
    }

    public var totalSeconds: Double {
        splits.reduce(0) { $0 + $1.seconds }
    }

    private enum CodingKeys: String, CodingKey {
        case splits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(splits: container.decode([Split].self, forKey: .splits))
    }
}

/// Metrics computed once, at ingestion, and stored (D2, §9).
///
/// Nothing here is recomputed at display time. The detail view, the chat context and
/// the dashboard all read these same numbers, which is the whole point: a metric
/// recomputed in a view drifts from the one Claude was shown, and the disagreement is
/// invisible until two screens print different values for the same run.
///
/// Optionality is meaningful throughout. An indoor run has no grade-adjusted pace; a
/// workout with no heart-rate series has no average HR; drift on an interval session
/// is "near-meaningless" (§9) and is therefore left nil rather than computed and
/// quietly ignored.
public struct DerivedMetrics: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID { workoutID }

    public let workoutID: UUID

    /// Mean heart rate over the workout, in beats per minute.
    public let averageHeartRateBPM: Double?
    public let maximumHeartRateBPM: Double?

    /// Seconds spent above the plan's HR cap — the primary easy-run discipline metric
    /// (§9). Zero is a real, good answer; nil means there was no HR series to measure
    /// against.
    public let timeAboveCapSeconds: Double?

    /// Aerobic decoupling as a **fraction**: `(avg HR 2nd half / avg HR 1st half) - 1`
    /// (§9). 0.05 means 5% drift. Stored as a fraction rather than a percentage so
    /// nobody has to guess which one a bare `0.05` meant; the UI multiplies.
    public let heartRateDriftFraction: Double?

    /// Steps per minute over the run, compared against `Plan.cadenceTarget`.
    public let averageCadenceStepsPerMinute: Double?

    /// Grade-adjusted pace in **seconds per kilometre** — outdoor only, and only when
    /// the route carries usable altitude.
    public let gradeAdjustedPaceSecondsPerKilometer: Double?

    public let zoneSplits: ZoneSplits

    /// The plan version whose cap and zones these numbers were computed against.
    /// Without it, "time above cap" is a number with no stated cap, and a later plan
    /// version would silently reinterpret it.
    public let planVersion: PlanVersion

    public init(
        workoutID: UUID,
        averageHeartRateBPM: Double? = nil,
        maximumHeartRateBPM: Double? = nil,
        timeAboveCapSeconds: Double? = nil,
        heartRateDriftFraction: Double? = nil,
        averageCadenceStepsPerMinute: Double? = nil,
        gradeAdjustedPaceSecondsPerKilometer: Double? = nil,
        zoneSplits: ZoneSplits = .empty,
        planVersion: PlanVersion
    ) throws {
        try Validate.optionalWithin(averageHeartRateBPM, HeartRateSample.plausibleBPM, "DerivedMetrics.averageHeartRateBPM")
        try Validate.optionalWithin(maximumHeartRateBPM, HeartRateSample.plausibleBPM, "DerivedMetrics.maximumHeartRateBPM")
        try Validate.optionalNonNegative(timeAboveCapSeconds, "DerivedMetrics.timeAboveCapSeconds")
        try Validate.optionalNonNegative(averageCadenceStepsPerMinute, "DerivedMetrics.averageCadenceStepsPerMinute")
        try Validate.optionalPositive(
            gradeAdjustedPaceSecondsPerKilometer,
            "DerivedMetrics.gradeAdjustedPaceSecondsPerKilometer"
        )
        if let heartRateDriftFraction {
            try Validate.finite(heartRateDriftFraction, "DerivedMetrics.heartRateDriftFraction")
        }
        if let average = averageHeartRateBPM, let maximum = maximumHeartRateBPM, maximum < average {
            throw DomainError.inconsistent(
                reason: "DerivedMetrics.maximumHeartRateBPM (\(maximum)) is below averageHeartRateBPM (\(average))"
            )
        }
        if averageHeartRateBPM == nil, timeAboveCapSeconds != nil {
            throw DomainError.inconsistent(
                reason: "DerivedMetrics.timeAboveCapSeconds requires a heart-rate series"
            )
        }

        self.workoutID = workoutID
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maximumHeartRateBPM = maximumHeartRateBPM
        self.timeAboveCapSeconds = timeAboveCapSeconds
        self.heartRateDriftFraction = heartRateDriftFraction
        self.averageCadenceStepsPerMinute = averageCadenceStepsPerMinute
        self.gradeAdjustedPaceSecondsPerKilometer = gradeAdjustedPaceSecondsPerKilometer
        self.zoneSplits = zoneSplits
        self.planVersion = planVersion
    }

    /// Whether a heart-rate curve existed for this workout at all.
    public var hasHeartRateData: Bool { averageHeartRateBPM != nil }

    /// Looks a metric up by the name a rubric uses. This is the bridge that lets the
    /// rubric stay data (D1): the scorer asks for `.averageHeartRateBPM` rather than
    /// reaching for a property by hand.
    public func value(for metric: RubricMetric, workout: Workout) -> Double? {
        switch metric {
        case .averageHeartRateBPM: return averageHeartRateBPM
        case .maximumHeartRateBPM: return maximumHeartRateBPM
        case .timeAboveCapSeconds: return timeAboveCapSeconds
        case .heartRateDriftFraction: return heartRateDriftFraction
        case .averageCadenceStepsPerMinute: return averageCadenceStepsPerMinute
        case .gradeAdjustedPaceSecondsPerKilometer: return gradeAdjustedPaceSecondsPerKilometer
        case .distanceMeters: return workout.distanceMeters
        case .durationSeconds: return workout.durationSeconds
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID, averageHeartRateBPM, maximumHeartRateBPM, timeAboveCapSeconds
        case heartRateDriftFraction, averageCadenceStepsPerMinute
        case gradeAdjustedPaceSecondsPerKilometer, zoneSplits, planVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            averageHeartRateBPM: container.decodeIfPresent(Double.self, forKey: .averageHeartRateBPM),
            maximumHeartRateBPM: container.decodeIfPresent(Double.self, forKey: .maximumHeartRateBPM),
            timeAboveCapSeconds: container.decodeIfPresent(Double.self, forKey: .timeAboveCapSeconds),
            heartRateDriftFraction: container.decodeIfPresent(Double.self, forKey: .heartRateDriftFraction),
            averageCadenceStepsPerMinute: container.decodeIfPresent(
                Double.self, forKey: .averageCadenceStepsPerMinute
            ),
            gradeAdjustedPaceSecondsPerKilometer: container.decodeIfPresent(
                Double.self, forKey: .gradeAdjustedPaceSecondsPerKilometer
            ),
            zoneSplits: container.decode(ZoneSplits.self, forKey: .zoneSplits),
            planVersion: container.decode(PlanVersion.self, forKey: .planVersion)
        )
    }
}
