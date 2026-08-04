import Foundation

/// A metric a rubric band can test.
///
/// Closed on purpose, unlike `ActivityType`: a rubric that names a metric the scorer
/// cannot compute is a broken rubric, and the compiler should be the thing that says
/// so when MAX-012 adds or renames one.
public enum RubricMetric: String, Hashable, Sendable, Codable, CaseIterable {
    case averageHeartRateBPM
    case maximumHeartRateBPM
    case timeAboveCapSeconds
    /// Aerobic decoupling as a **fraction** — 0.05 is 5%. See `DerivedMetrics`.
    case heartRateDriftFraction
    case averageCadenceStepsPerMinute
    case gradeAdjustedPaceSecondsPerKilometer
    case distanceMeters
    case durationSeconds
}

public enum RubricComparison: String, Hashable, Sendable, Codable, CaseIterable {
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    public func evaluate(_ lhs: Double, _ rhs: Double) -> Bool {
        switch self {
        case .lessThan: return lhs < rhs
        case .lessThanOrEqual: return lhs <= rhs
        case .greaterThan: return lhs > rhs
        case .greaterThanOrEqual: return lhs >= rhs
        }
    }
}

/// The right-hand side of a rubric comparison.
///
/// This is the piece that makes D1 work. A rubric that said "average HR ≤ 150" would
/// hardcode today's cap into the rubric and force a rubric rewrite whenever the cap
/// moves. Expressing the threshold *relative to the plan* — "≤ the cap", "≤ cap + 8"
/// — means the cap and the rubric are independent knobs on the same versioned
/// record.
public enum RubricReference: Hashable, Sendable, Codable {
    /// A literal, for metrics with no plan-relative anchor (drift fraction, duration).
    case constant(Double)
    /// The plan's HR cap, optionally offset. `heartRateCap(offsetBPM: 8)` is the
    /// "151–158" band's upper edge when the cap is 150.
    case heartRateCap(offsetBPM: Double)
    /// The low edge of the plan's cadence target band, optionally offset.
    case cadenceTargetLow(offsetStepsPerMinute: Double)
    /// The high edge of the plan's cadence target band, optionally offset.
    case cadenceTargetHigh(offsetStepsPerMinute: Double)
    /// A fraction of the day's scheduled distance — "ran at least 80% of the ask".
    case scheduledDistance(fraction: Double)
}

/// One clause of a band's match condition. A band matches when **all** of its
/// conditions hold; disjunction ("avg ≥ 159 **or** ran hard instead", §10.3) is
/// expressed as two bands sharing a score range, which keeps the data shape flat and
/// the evaluation order obvious.
public enum RubricCondition: Hashable, Sendable, Codable {
    case metric(metric: RubricMetric, comparison: RubricComparison, reference: RubricReference)
    /// The workout was classified as one of these (§10.2).
    case actualClassification(oneOf: [WorkoutClassification])
    /// The metric could not be computed — no HR series, or an indoor run with no
    /// grade. Lets a rubric say "if drift is unavailable, don't use the drift band"
    /// rather than leaving the scorer to invent a policy.
    case metricUnavailable(RubricMetric)
    /// No workout was recorded for the scheduled day at all (the "skipped → 0–15"
    /// band).
    case noWorkoutRecorded
}

/// One rubric row: "when these conditions hold, the score is in this band, and this
/// is why".
public struct RubricBand: Hashable, Sendable, Codable {
    /// Stable identifier, carried into the score's provenance so a historical score
    /// can be traced to the exact rule that produced it.
    public let identifier: String

    /// Scheduled session kinds this band applies to. Empty means "any".
    public let appliesTo: [ScheduledSessionKind]

    /// All must hold. Empty means the band always matches once `appliesTo` does —
    /// useful as a final catch-all.
    public let conditions: [RubricCondition]

    public let scoreRange: ScoreRange

    /// Template for the one-line rationale in the verdict header (FR-1.1). Plain text
    /// today; if it ever grows placeholders, the substitution belongs in the scorer,
    /// not here.
    public let rationale: String

    public init(
        identifier: String,
        appliesTo: [ScheduledSessionKind] = [],
        conditions: [RubricCondition] = [],
        scoreRange: ScoreRange,
        rationale: String
    ) throws {
        try Validate.nonEmpty(identifier, "RubricBand.identifier")
        try Validate.nonEmpty(rationale, "RubricBand.rationale")
        self.identifier = identifier
        self.appliesTo = appliesTo
        self.conditions = conditions
        self.scoreRange = scoreRange
        self.rationale = rationale
    }

    public func applies(to kind: ScheduledSessionKind) -> Bool {
        appliesTo.isEmpty || appliesTo.contains(kind)
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, appliesTo, conditions, scoreRange, rationale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            identifier: container.decode(String.self, forKey: .identifier),
            appliesTo: container.decode([ScheduledSessionKind].self, forKey: .appliesTo),
            conditions: container.decode([RubricCondition].self, forKey: .conditions),
            scoreRange: container.decode(ScoreRange.self, forKey: .scoreRange),
            rationale: container.decode(String.self, forKey: .rationale)
        )
    }
}

/// The scoring rubric — **data the scorer reads, not a `switch` the scorer is**
/// (D1, §10).
///
/// Bands are evaluated in order and the first match wins, so ordering is part of the
/// rubric's meaning and is preserved verbatim. Changing a threshold means authoring a
/// new `Plan` with a new `version`; it must never mean editing Swift, or every
/// historical score silently becomes irreproducible.
public struct ScoringRubric: Hashable, Sendable, Codable {
    /// Score at or above which a day counts as effective (§10.4; 70 in the current
    /// plan). Versioned with everything else, precisely so that moving it does not
    /// retroactively rewrite last month's calendar.
    public let effectiveThreshold: ScoreValue

    /// Score at or above which a miss is a *near* miss rather than a failure — the
    /// amber/red cut in D4's calendar, i.e. the `ScoreBand.marginal` /
    /// `.ineffective` boundary.
    ///
    /// It lives here for the same reason `effectiveThreshold` does. `ScoreBand`
    /// deliberately cannot compute itself from a number, which means *something* has
    /// to supply the cut points, and D1 says that something is versioned plan data
    /// rather than a constant in the scorer. Two thresholds, three bands.
    public let marginalThreshold: ScoreValue

    /// Ordered; first match wins.
    public let bands: [RubricBand]

    public init(
        effectiveThreshold: ScoreValue,
        marginalThreshold: ScoreValue,
        bands: [RubricBand]
    ) throws {
        guard marginalThreshold <= effectiveThreshold else {
            throw DomainError.inconsistent(
                reason: "ScoringRubric.marginalThreshold (\(marginalThreshold)) must not exceed "
                    + "effectiveThreshold (\(effectiveThreshold))"
            )
        }
        guard !bands.isEmpty else {
            throw DomainError.empty(field: "ScoringRubric.bands")
        }
        var seen = Set<String>()
        for band in bands {
            guard seen.insert(band.identifier).inserted else {
                throw DomainError.duplicate(field: "ScoringRubric.bands", key: band.identifier)
            }
        }
        self.effectiveThreshold = effectiveThreshold
        self.marginalThreshold = marginalThreshold
        self.bands = bands
    }

    /// Bands that could apply to a given scheduled session kind, in rubric order.
    public func bands(for kind: ScheduledSessionKind) -> [RubricBand] {
        bands.filter { $0.applies(to: kind) }
    }

    public func band(identifiedBy identifier: String) -> RubricBand? {
        bands.first { $0.identifier == identifier }
    }

    private enum CodingKeys: String, CodingKey {
        case effectiveThreshold, marginalThreshold, bands
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            effectiveThreshold: container.decode(ScoreValue.self, forKey: .effectiveThreshold),
            marginalThreshold: container.decode(ScoreValue.self, forKey: .marginalThreshold),
            bands: container.decode([RubricBand].self, forKey: .bands)
        )
    }
}
