import Foundation

/// One case per figure `DerivedMetrics` carries — and the single place that decides
/// which of them describe a workout of a given discipline (A17, MAX-130).
///
/// ## Why this exists rather than a gate at each call site
///
/// MAX-111 stopped the app fabricating a lift's cadence by putting `if isRun` in front
/// of three expressions in `DerivedMetricsCalculator`. That fixed the three metrics that
/// existed; it did nothing about the fourth. A metric added next year gets computed for
/// every discipline unless whoever adds it happens to read the comment above those
/// three, and the failure mode is silent — a number that looks measured, on a session it
/// does not describe, which is exactly what §1.2 of `docs/LIFTING-SPEC.md` found.
///
/// So the decision moves into a closed enum with one exhaustive `switch`. A new metric
/// is a new case; a new case does not compile until someone has answered "which
/// disciplines is this true of". `DerivedMetricKindTests` closes the other half of the
/// loop by walking `DerivedMetrics`' own stored properties and failing if one of them is
/// not named here — so a field added without a case is caught too.
///
/// ## Not a display vocabulary
///
/// This says nothing about labels, ordering or units; `SummaryTileData` and the fact
/// sheet own that. It is only the applicability question. `RubricMetric` is a different
/// list for a different purpose — what a *plan* may write a band about (D1) — and the
/// two deliberately do not share cases: `RubricMetric` names `distanceMeters`, which is
/// a `Workout` field rather than a derived one, and this names `zoneSplits`, which no
/// band can test.
public enum DerivedMetricKind: String, Hashable, Sendable, CaseIterable {
    /// Raw values match `DerivedMetrics`' property names exactly. That is what lets the
    /// coverage test pair the two by reflection, and it is worth keeping.
    case averageHeartRateBPM
    case maximumHeartRateBPM
    case timeAboveCapSeconds
    case heartRateDriftFraction
    case averageCadenceStepsPerMinute
    case gradeAdjustedPaceSecondsPerKilometer
    case zoneSplits
    case distanceSplits

    /// What a workout must be before this figure describes anything about it.
    public enum Requirement: Hashable, Sendable {
        /// A reading taken off a sensor the athlete was wearing, or a description of
        /// one. True of both disciplines, because a heart rate measured during a lift is
        /// a heart rate.
        case anyDiscipline

        /// A model of running — gait, or the metabolic cost of running a grade. Note
        /// what this is *not*: the run **slot**. A ride and a hike sit in the run slot
        /// by A17 and have no running form, and MAX-111 found the app inventing one for
        /// both, so `ActivityType.isRun` — the narrower of the two predicates, and
        /// defined in terms of `Discipline` so they cannot disagree — is the question.
        case runningActivity
    }

    public var requirement: Requirement {
        switch self {
        // Measurements, and descriptions of a measurement. `zoneSplits` boundaries come
        // from the plan's cap, which is a run field — that is tracker gap P2 (a
        // modelling choice living in code), and it is made no worse by this.
        case .averageHeartRateBPM, .maximumHeartRateBPM, .timeAboveCapSeconds,
             .heartRateDriftFraction, .zoneSplits:
            return .anyDiscipline

        // MAX-111's three, restated. Cadence is steps per minute against a running
        // band, and a lift's steps are the walk to the water fountain. Grade-adjusted
        // pace applies Minetti's cost-of-*running* polynomial. Distance splits are
        // FR-1.5's per-kilometre pace breakdown, read everywhere in the app as a run's
        // splits.
        case .averageCadenceStepsPerMinute, .gradeAdjustedPaceSecondsPerKilometer, .distanceSplits:
            return .runningActivity
        }
    }

    /// Whether this figure describes anything about a workout of this activity type.
    ///
    /// False means **absent, never zero**. A nil is left out of a trend and omitted from
    /// the fact sheet; a zero is averaged in and drawn as a measurement.
    public func applies(to activityType: ActivityType) -> Bool {
        switch requirement {
        case .anyDiscipline: return true
        case .runningActivity: return activityType.isRun
        }
    }

    /// The figures that describe a workout of this activity type, in declaration order.
    public static func applicable(to activityType: ActivityType) -> [DerivedMetricKind] {
        allCases.filter { $0.applies(to: activityType) }
    }
}
