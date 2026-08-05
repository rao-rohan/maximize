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
///
/// **Adding a figure here means adding a `DerivedMetricKind` case**, which is where the
/// question "which disciplines does this describe?" is asked and answered (A17,
/// MAX-130). `DerivedMetricKindTests` walks these stored properties by reflection and
/// fails on one that has no case, so the pairing is not a convention anyone has to
/// remember.
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

    /// FR-1.5's per-kilometre/mile pace breakdown — cut at ingestion, at every display
    /// unit, and stored (D2). Not to be confused with `zoneSplits` above, which is time
    /// per *heart-rate zone*: a different measurement that happens to share the word.
    ///
    /// Nil means *this run has no breakdown*: an indoor run with no route, a workout with
    /// no recorded distance, a route too short or too far from the recorded distance to
    /// cut up, or a workout whose metrics were computed before MAX-046 existed and have
    /// not yet been through MAX-067's backfill. `DistanceSplitCalculator` documents each
    /// case that can produce nil once the calculator has actually run.
    /// `distanceSplitsComputed` is what tells those apart.
    public let distanceSplits: DistanceSplits?

    /// Whether `DistanceSplitCalculator` has ever run against this record, independent of
    /// whether it found a breakdown to store (MAX-067).
    ///
    /// Before this flag existed, `distanceSplits == nil` meant two different things with
    /// no way to tell them apart: "there is truly nothing to cut up" (no route, no
    /// recorded distance, a track too implausible to trust) and "this record predates
    /// MAX-046, and the split calculator has simply never been asked." That ambiguity is
    /// exactly what stopped a backfill from falling out for free — without it, a sweep
    /// cannot distinguish a workout it has already re-enriched and definitively found no
    /// splits for from one it has never touched, and would either refetch a permanently
    /// route-less workout's HealthKit samples forever or stop before ever reaching one
    /// that genuinely could gain a breakdown.
    ///
    /// Defaults `true` because every in-memory construction of `DerivedMetrics` — the
    /// calculator's own output (`DerivedMetricsCalculator.compute` always attempts the
    /// split calculation, MAX-046 onward) and every test that builds one directly by hand
    /// — is, by construction, already past the question this flag answers. `false` is
    /// reached exactly one way: `StoredDerivedMetrics.toDomain()` reading a row written
    /// before this column existed, where SwiftData's lightweight migration defaults it to
    /// `false` for precisely that reason — see `DerivedMetricsRecord.distanceSplitsComputed`.
    public let distanceSplitsComputed: Bool

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
        distanceSplits: DistanceSplits? = nil,
        distanceSplitsComputed: Bool = true,
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
        self.distanceSplits = distanceSplits
        self.distanceSplitsComputed = distanceSplitsComputed
        self.planVersion = planVersion
    }

    /// Whether a heart-rate curve existed for this workout at all.
    public var hasHeartRateData: Bool { averageHeartRateBPM != nil }

    /// Whether this record actually carries the named figure.
    ///
    /// The counterpart to `DerivedMetricKind.applies(to:)`: that says whether a figure
    /// *could* describe a workout of some activity type, this says whether this
    /// particular record ended up with one. The two differ legitimately — an indoor run
    /// is entitled to a grade-adjusted pace and has no route to compute it from — and
    /// only one direction is an invariant: a figure that does not apply is never
    /// recorded. `DerivedMetricsCalculatorTests` asserts exactly that.
    ///
    /// `zoneSplits` is the one case where absence is not a nil. Empty means "no curve to
    /// distribute", which is why it reads as not recorded rather than as five zeroes.
    public func isRecorded(_ kind: DerivedMetricKind) -> Bool {
        switch kind {
        case .averageHeartRateBPM: return averageHeartRateBPM != nil
        case .maximumHeartRateBPM: return maximumHeartRateBPM != nil
        case .timeAboveCapSeconds: return timeAboveCapSeconds != nil
        case .heartRateDriftFraction: return heartRateDriftFraction != nil
        case .averageCadenceStepsPerMinute: return averageCadenceStepsPerMinute != nil
        case .gradeAdjustedPaceSecondsPerKilometer: return gradeAdjustedPaceSecondsPerKilometer != nil
        case .zoneSplits: return !zoneSplits.splits.isEmpty
        case .distanceSplits: return distanceSplits != nil
        }
    }

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
        case gradeAdjustedPaceSecondsPerKilometer, zoneSplits, distanceSplits
        case distanceSplitsComputed, planVersion
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
            // `decodeIfPresent`: a record encoded before MAX-046 carries no key here, and
            // the honest reading of that is "no breakdown recorded", not a decode failure
            // that would lose every other metric on the run.
            distanceSplits: container.decodeIfPresent(DistanceSplits.self, forKey: .distanceSplits),
            // A value encoded through this initializer's own `encode(to:)` always carries
            // this key, so an absent key means data from outside that round trip —
            // treated the same as the throwing initializer's default (see
            // `distanceSplitsComputed`'s documentation for why `true` is the safe default
            // for a hand-assembled or freshly-encoded value).
            distanceSplitsComputed: container.decodeIfPresent(Bool.self, forKey: .distanceSplitsComputed) ?? true,
            planVersion: container.decode(PlanVersion.self, forKey: .planVersion)
        )
    }
}
