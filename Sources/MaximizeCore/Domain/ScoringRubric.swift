import Foundation

/// A metric a rubric band can test.
///
/// Closed on purpose, unlike `ActivityType`: a rubric that names a metric the scorer
/// cannot compute is a broken rubric, and the compiler should be the thing that says
/// so when MAX-012 adds or renames one.
///
/// ## What a lift can be judged on, and what was deliberately left out
///
/// A lift's stored record is average heart rate, maximum heart rate and zone splits
/// (MAX-130) — plus `durationSeconds`, which is a `Workout` field and is already here.
/// A20 scores a lift on **adherence, not volume**: whether the session the plan asked
/// for happened, on the day, for roughly the prescribed length. `durationSeconds` is
/// the whole of the measurable half of that, so this list gains nothing for MAX-131.
///
/// **`activeEnergyKilocalories` was considered and declined**, against LIFTING-SPEC
/// §3.5's suggestion. `Workout` does store it, so it could be named here. But A20's own
/// words are *"no rubric band references a load or a volume"*, and energy burned is a
/// volume proxy — the one number in a lift's record that answers "how much work",
/// which is the question A20 says the app cannot honestly ask. It also has no
/// plan-relative anchor: the plan prescribes no energy, so a band using it would carry
/// a `.constant`, i.e. a per-athlete physiological threshold frozen into the rubric,
/// which is the shape `RubricReference` exists to avoid. Under D1 a case here is
/// permanent — it becomes part of what every plan version *means* — so the case for
/// adding it should be made by a band somebody actually wants to write, not in advance.
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
    /// A fraction of the day's scheduled **duration** — "lifted for at least 70% of the
    /// ask" (A20, MAX-131).
    ///
    /// The sibling of `.scheduledDistance`, and the half of A20's judgement the rubric
    /// could not previously express: a lift has no distance, so "roughly how long" is
    /// the only measurable part of "did the session the plan asked for happen". It is
    /// written as a fraction of the ask rather than as a literal for the reason this
    /// whole type exists — a band saying "≥ 1,800 seconds" would freeze today's
    /// prescription into the rubric and need rewriting the first time a lift day moved
    /// from 45 minutes to 60.
    ///
    /// Resolves to nil on a day whose ask carries no duration, which the evaluator reads
    /// as no-match, exactly as it already does for `.scheduledDistance`.
    case scheduledDuration(fraction: Double)
}

/// One clause of a band's match condition. A band matches when **all** of its
/// conditions hold; disjunction ("avg ≥ 159 **or** ran hard instead", §10.3) is
/// expressed as two bands sharing a score range, which keeps the data shape flat and
/// the evaluation order obvious.
///
/// ## Adding a case is additive on the wire, and permanent in meaning
///
/// Swift's synthesised enum `Codable` writes a case as a single-key object named for
/// the case, so a stored rubric that never mentions a case decodes exactly as it did
/// before that case existed — the same additivity `ScheduledSessionKind.lift` has. What
/// is *not* reversible is the meaning: a rubric lives inside a versioned plan record
/// (D1), so a condition written into a plan version is what that version permanently
/// says, and a case that turns out to be wrong cannot be fixed in place. Which is why
/// this list grows only when a band somebody wants to write cannot be said without it.
///
/// **Muscle groups are the standing example of a case not added.** A plan may prescribe
/// them (`ScheduledSession.muscleGroups`, MAX-129) and HealthKit reports nothing that
/// could check one, so there is no condition here that names them and no band can
/// require one. MAX-144 is the owner's open decision on whether that ever changes; if it
/// does, it is one more case, and by the paragraph above that costs no stored rubric
/// anything.
public enum RubricCondition: Hashable, Sendable, Codable {
    case metric(metric: RubricMetric, comparison: RubricComparison, reference: RubricReference)
    /// The workout was classified as one of these (§10.2).
    case actualClassification(oneOf: [WorkoutClassification])
    /// The workout **is** of one of these disciplines (A17, A20, MAX-131).
    ///
    /// ## Why this is not `.actualClassification(oneOf: [.lift])`
    ///
    /// Two reasons, and the second is the load-bearing one.
    ///
    /// A discipline is read off the workout's `ActivityType`, which is a fact HealthKit
    /// recorded; a classification is read off a heart-rate curve by `WorkoutClassifier`,
    /// which is a judgement. A band that wants to say "this was a lift" is stating the
    /// fact, and routing the fact through the judgement makes the band depend on the
    /// component PRD §13 names as poisoning every downstream number when it is wrong.
    ///
    /// And the classifier does not currently answer `.lift` at all — it short-circuits
    /// every non-run to `.other` — so a band conditioned on the classification would
    /// silently never fire, while this one is correct the moment a lift reaches the
    /// evaluator. `WorkoutClassification.lift` exists as vocabulary (MAX-128); nothing
    /// produces it.
    ///
    /// ## Why the rubric needs it at all
    ///
    /// `RubricBand.appliesTo` filters by what was **scheduled**; this is the *actual*
    /// side, the same split `.actualClassification` sits on. MAX-133 will match a
    /// workout to the ask of its own discipline, which makes a cross-discipline match
    /// structurally impossible — but the seed's `easy.wellOverCap` band shows why a
    /// band should also be able to say so itself: it carries one condition, "average HR
    /// above cap + 8", with nothing about what was done, and it is how a lift came to be
    /// permanently scored 20–45 as a failed easy run. A band that names its discipline
    /// cannot make that mistake regardless of what routes a workout to it. MAX-132 is
    /// the ticket that writes the seed's bands; this is only the word for it.
    case actualDiscipline(oneOf: [Discipline])
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
