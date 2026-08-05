import Foundation

/// One stretch of a run, one display unit long — FR-1.5's per-kilometre/mile pace
/// breakdown.
///
/// ## Unit-free on purpose
///
/// A split carries **metres and seconds**, never "pace per kilometre". The unit it was
/// cut at lives on the enclosing `DistanceSplitSeries`, and pace is derived from the two
/// scalars on demand. That is what lets one stored record answer both "5:12 /km" and
/// "8:22 /mi" without anything re-deriving a number at display time (D2): a split whose
/// stored form said `paceSecondsPerKilometer` would have baked a display preference into
/// the athlete's history, and switching `AppSettings.distanceUnit` later could not have
/// honoured it.
public struct DistanceSplit: Hashable, Sendable, Codable {
    /// 1-based position in the run. The tenth kilometre is `ordinal == 10`, whether or
    /// not earlier splits were complete.
    public let ordinal: Int

    /// How far this stretch covered. Exactly `DistanceUnit.metersPerUnit` for a complete
    /// split; the run's remainder for the final incomplete one.
    public let distanceMeters: Double

    /// How long it took, measured between the GPS fixes that bound it (see
    /// `DistanceSplitCalculator` for what that excludes).
    public let elapsedSeconds: Double

    /// False only for the trailing remainder of a run that did not end on a unit
    /// boundary. A 7.4 km run cut at kilometres has seven complete splits and one
    /// incomplete one.
    ///
    /// Load-bearing for display: an incomplete split's pace is a real number but not a
    /// like-for-like one — 400 m of a finishing kick extrapolates to a per-kilometre pace
    /// the athlete never held for a kilometre. The flag is what lets a view mark it
    /// instead of letting it read as the fastest split of the run.
    public let isComplete: Bool

    public init(ordinal: Int, distanceMeters: Double, elapsedSeconds: Double, isComplete: Bool) throws {
        guard ordinal >= 1 else {
            throw DomainError.outOfRange(
                field: "DistanceSplit.ordinal",
                value: Double(ordinal),
                lowerBound: 1,
                upperBound: nil
            )
        }
        // Positive rather than non-negative for both: a split covering no ground, or
        // taking no time, has a pace of zero or infinity respectively, and either would
        // poison anything that averages or ranks these.
        try Validate.positive(distanceMeters, "DistanceSplit.distanceMeters")
        try Validate.positive(elapsedSeconds, "DistanceSplit.elapsedSeconds")

        self.ordinal = ordinal
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.isComplete = isComplete
    }

    /// Pace in its unit-free form. Multiply by `DistanceUnit.metersPerUnit` for the
    /// per-unit figure a reader recognises.
    public var paceSecondsPerMeter: Double {
        elapsedSeconds / distanceMeters
    }

    /// Pace in seconds per kilometre, per mile, or per whatever unit is asked for.
    ///
    /// For an incomplete split this is an *extrapolation* from a partial sample — see
    /// `isComplete`.
    public func paceSeconds(per unit: DistanceUnit) -> Double {
        paceSecondsPerMeter * unit.metersPerUnit
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal, distanceMeters, elapsedSeconds, isComplete
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ordinal: container.decode(Int.self, forKey: .ordinal),
            distanceMeters: container.decode(Double.self, forKey: .distanceMeters),
            elapsedSeconds: container.decode(Double.self, forKey: .elapsedSeconds),
            isComplete: container.decode(Bool.self, forKey: .isComplete)
        )
    }
}

/// One run cut into splits at one unit.
///
/// The splits are contiguous and in order: `ordinal` runs 1…n with no gaps, and at most
/// the last one is incomplete. Those are invariants the initializer enforces rather than
/// hopes for, because a view that has to check them is a view doing arithmetic.
public struct DistanceSplitSeries: Hashable, Sendable, Codable {
    public let unit: DistanceUnit
    public let splits: [DistanceSplit]

    public init(unit: DistanceUnit, splits: [DistanceSplit]) throws {
        guard !splits.isEmpty else {
            throw DomainError.empty(field: "DistanceSplitSeries.splits")
        }
        for (index, split) in splits.enumerated() {
            guard split.ordinal == index + 1 else {
                throw DomainError.outOfOrder(field: "DistanceSplitSeries.splits", index: index)
            }
            guard split.isComplete || index == splits.count - 1 else {
                throw DomainError.inconsistent(
                    reason: "DistanceSplitSeries.splits: only the final split may be incomplete"
                )
            }
        }
        self.unit = unit
        self.splits = splits
    }

    /// Total ground covered by the splits. Equal to the workout's recorded distance up to
    /// a dropped sub-`DistanceSplitCalculator.minimumRemainderMeters` tail.
    public var totalDistanceMeters: Double {
        splits.reduce(0) { $0 + $1.distanceMeters }
    }

    /// Total time the splits account for. Not the workout's duration — see
    /// `DistanceSplitCalculator`, which measures between GPS fixes and therefore excludes
    /// any lead-in before the first fix.
    public var totalElapsedSeconds: Double {
        splits.reduce(0) { $0 + $1.elapsedSeconds }
    }

    private enum CodingKeys: String, CodingKey {
        case unit, splits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unit: container.decode(DistanceUnit.self, forKey: .unit),
            splits: container.decode([DistanceSplit].self, forKey: .splits)
        )
    }
}

/// One workout's pace breakdown, cut at every unit the app can display (FR-1.5).
///
/// ## Why every unit, and not the user's current one
///
/// Splits are computed once, at ingestion, and stored (D2). `AppSettings.distanceUnit` is
/// a *display* preference the athlete may change at any point after that — so storing the
/// breakdown in whichever unit was selected on ingestion day would mean a run captured in
/// kilometres could never be read in miles, and the setting would be a switch that only
/// works on future runs. Kilometre and mile boundaries do not align (1 mi = 1 609.344 m),
/// so one series genuinely cannot be re-cut into the other without going back to the GPS
/// track, which is exactly the display-time recomputation D2 forbids.
///
/// Both series are therefore computed in the same pass at ingestion, and display picks
/// one. The cost is small — a 10 km run is ten kilometre splits and seven mile splits,
/// under 2 KB of JSON — and it is paid once per workout rather than once per screen.
///
/// The absence of a breakdown is `DerivedMetrics.distanceSplits == nil`, never an empty
/// `DistanceSplits`: this type always carries at least one series.
public struct DistanceSplits: Hashable, Sendable, Codable {
    /// One series per unit, at most one per unit, ordered by `DistanceUnit.allCases` so
    /// the encoded bytes are a deterministic function of the value.
    public let series: [DistanceSplitSeries]

    public init(series: [DistanceSplitSeries]) throws {
        guard !series.isEmpty else {
            throw DomainError.empty(field: "DistanceSplits.series")
        }
        var seen = Set<DistanceUnit>()
        for entry in series {
            guard seen.insert(entry.unit).inserted else {
                throw DomainError.duplicate(field: "DistanceSplits.series", key: "unit=\(entry.unit.rawValue)")
            }
        }
        let order = DistanceUnit.allCases
        self.series = series.sorted {
            (order.firstIndex(of: $0.unit) ?? 0) < (order.firstIndex(of: $1.unit) ?? 0)
        }
    }

    /// The breakdown in one unit, or nil if this record does not carry that unit.
    ///
    /// Optional rather than total, deliberately. A record written by an older build will
    /// not carry a unit added later, and the honest answer for it is "no breakdown in
    /// miles" — degrading one section of one screen — rather than failing to decode the
    /// whole metrics record and losing every number on it.
    public func series(in unit: DistanceUnit) -> DistanceSplitSeries? {
        series.first { $0.unit == unit }
    }

    private enum CodingKeys: String, CodingKey {
        case series
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(series: container.decode([DistanceSplitSeries].self, forKey: .series))
    }
}
