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
    case strain
    case distanceSplits

    /// What a workout must be before this figure describes anything about it.
    ///
    /// Three answers, and the gap between the second and the third is the whole reason
    /// the type has three rather than two — see `Discipline` and `ActivityType.isRun`,
    /// which are already documented as the wider and narrower predicate.
    public enum Requirement: Hashable, Sendable {
        /// A reading taken off a sensor the athlete was wearing. True of both
        /// disciplines, because a heart rate measured during a lift is a heart rate.
        case anyDiscipline

        /// Meaningful only against the run prescription: the figure is defined by a
        /// field of the plan that is a *run* field, so reading it on a session in the
        /// lift slot produces a number anchored to an ask nobody made of it.
        case runDiscipline

        /// A model of running — gait, or the metabolic cost of running a grade. The run
        /// *slot* is not enough here: a ride and a hike sit in the run slot by A17 and
        /// have no running form, and MAX-111 found the app inventing one for both.
        case runningActivity
    }

    public var requirement: Requirement {
        switch self {
        // Measurements. `zoneSplits` is a description of how a heart-rate curve was
        // distributed, and §3.3 keeps it for a lift on the grounds that it is the only
        // thing in the record that could ever tell a lifting session apart from a walk.
        // Its boundaries come from the cap, which is a run field — that is tracker gap
        // P2 (a modelling choice living in code), and it is made no worse by this.
        case .averageHeartRateBPM, .maximumHeartRateBPM, .zoneSplits:
            return .anyDiscipline

        // `timeAboveCapSeconds` is documented on `DerivedMetrics` as "the primary
        // easy-run discipline metric", and `Plan.heartRateCapBPM` is the easy-run
        // ceiling. A heavy set puts most people over it, so on a lift the figure
        // measures how hard the athlete worked — the opposite of what the same number
        // means on a run, in the same column, under the same heading. §3.3 answers (a):
        // do not compute it. §15 records that as the owner's to overrule.
        //
        // Drift is aerobic decoupling: cardiac cost creeping up at a *held* effort, and
        // a lift holds no effort. It is already absent for one — `driftIsMeaningful` is
        // false for `.lift` and for the `.other` a lift classifies as today — and the
        // calculator still asks both questions. Redundant by inspection, in the same
        // way and for the same reason as the `discipline` guard inside `isRun`: the
        // classifier is free to start answering `.lift`, and this must not depend on it
        // never doing so.
        case .timeAboveCapSeconds, .heartRateDriftFraction:
            return .runDiscipline

        // MAX-176. Strain is a reading of `zoneSplits` — the same distribution, weighted
        // by zone and summed — so it can only ever be as applicable as the figure it is
        // read from, and `zoneSplits` is `.anyDiscipline` by §3.3 above. Giving it a
        // narrower requirement would leave the record carrying a distribution nobody is
        // allowed to total, and a wider one does not exist.
        //
        // A lift therefore has a strain, and `WorkoutStrain` states in its own
        // documentation exactly what that figure is and is not: the cardiovascular cost
        // of the session and nothing else, because HealthKit carries no load for a
        // strength workout (A20). It inherits the zone boundaries' anchoring to the run
        // cap along with everything else read off `zoneSplits` — tracker gap P2, made no
        // worse by summing what is already there.
        case .strain:
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
        case .runDiscipline: return activityType.discipline == .run
        case .runningActivity: return activityType.isRun
        }
    }

    /// The figures that describe a workout of this activity type, in declaration order.
    public static func applicable(to activityType: ActivityType) -> [DerivedMetricKind] {
        allCases.filter { $0.applies(to: activityType) }
    }
}
