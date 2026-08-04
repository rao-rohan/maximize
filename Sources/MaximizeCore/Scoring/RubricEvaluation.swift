import Foundation

/// The rubric band a workout matched, together with everything needed to turn a score
/// into a stored `Score` (§10, D1).
///
/// This is the deterministic half of scoring. Given the same context and the same plan
/// version, the same band matches — every time, forever, with no model in the loop.
/// That property is what makes MAX-071's fixture suite ("known-good runs → expected
/// score bands") a meaningful test rather than a coin flip, and it is what keeps the
/// calendar's colours reproducible after the plan moves on (D1).
public struct RubricEvaluation: Hashable, Sendable {
    /// The plan version in effect on the workout's day — the version whose rubric,
    /// cap and cadence band were used, and the one recorded on the resulting `Score`.
    public let plan: Plan

    /// The day's resolved ask.
    public let planDay: PlanDay

    /// What the classifier decided actually happened (§10.2).
    public let classification: WorkoutClassification

    /// The first band whose conditions all held. First-match-wins is the rubric's own
    /// semantics, so band order is part of the plan's meaning.
    public let band: RubricBand

    init(plan: Plan, planDay: PlanDay, classification: WorkoutClassification, band: RubricBand) {
        self.plan = plan
        self.planDay = planDay
        self.classification = classification
        self.band = band
    }

    public var scheduledSession: ScheduledSession { planDay.scheduledSession }
    public var rubric: ScoringRubric { plan.rubric }

    /// The score range the matched band permits. A model proposal outside it is
    /// rejected, not clamped.
    public var permittedScores: ScoreRange { band.scoreRange }

    /// The `ScoreBand` this rubric band implies **when it implies one at all**.
    ///
    /// Nil when the band's score range straddles one of the rubric's two cut points, in
    /// which case the exact number decides. §10.3's worked example does exactly this:
    /// "avg 151–158 → 55–74" straddles an effective threshold of 70, so a run in that
    /// band is effective or not depending on where inside 55–74 it lands.
    ///
    /// This is exposed rather than hidden because it is the honest boundary of what the
    /// rubric alone settles, and a rubric author who wants the verdict fully determined
    /// can have it by writing ranges that do not cross a threshold. Making the property
    /// visible is what lets them notice the choice; see `verdictIsSettledByRubric`.
    public var settledScoreBand: ScoreBand? {
        let lowest = band.scoreRange.lowest
        let highest = band.scoreRange.highest
        if lowest >= rubric.effectiveThreshold { return .effective }
        if highest < rubric.effectiveThreshold {
            if lowest >= rubric.marginalThreshold { return .marginal }
            if highest < rubric.marginalThreshold { return .ineffective }
        }
        return nil
    }

    /// Whether matching this band already settles the effective/not verdict (§10.4),
    /// independent of where in the range the score lands.
    public var verdictIsSettledByRubric: Bool {
        band.scoreRange.lowest >= rubric.effectiveThreshold
            || band.scoreRange.highest < rubric.effectiveThreshold
    }
}

/// Applies a plan's rubric to a workout context and decides which band it falls in
/// (§10.3).
///
/// **No thresholds live here.** Every number this consults — the HR cap, the cadence
/// band, the score ranges, the drift cut, the effective threshold — arrives from the
/// `Plan` record the day resolved to. The evaluator knows only how to compare, which is
/// what makes "changing a threshold is a new plan version, never a code change" (D1)
/// actually true rather than aspirational.
public enum RubricEvaluator {

    /// Selects the first rubric band whose conditions all hold.
    ///
    /// Bands are filtered by the **scheduled** session kind (`RubricBand.appliesTo`)
    /// and then tested against what **actually** happened. That split is deliberate and
    /// it is how §10.3's "hard-instead" row works: the band applies to easy days, and
    /// its condition is that the run was classified hard.
    ///
    /// - Throws: `ScoringError.noPlanInEffect` when the day predates every plan
    ///   version, and `ScoringError.noBandMatched` when the rubric has no row for what
    ///   happened.
    public static func evaluate(_ context: WorkoutContext) throws -> RubricEvaluation {
        guard let plan = context.plan, let planDay = context.planDay else {
            throw ScoringError.noPlanInEffect(day: context.day)
        }

        let scheduledKind = planDay.scheduledSession.kind
        for band in plan.rubric.bands(for: scheduledKind) {
            let matched = band.conditions.allSatisfy { condition in
                holds(condition, in: context, under: plan, on: planDay)
            }
            if matched {
                return RubricEvaluation(
                    plan: plan,
                    planDay: planDay,
                    classification: context.classification,
                    band: band
                )
            }
        }

        throw ScoringError.noBandMatched(
            scheduled: scheduledKind,
            actual: context.classification
        )
    }

    /// Evaluates one clause. A band matches when **all** of its clauses hold
    /// (`RubricBand.conditions`); disjunction is expressed as two bands.
    private static func holds(
        _ condition: RubricCondition,
        in context: WorkoutContext,
        under plan: Plan,
        on planDay: PlanDay
    ) -> Bool {
        switch condition {
        case let .metric(metric, comparison, reference):
            // Both halves can legitimately be absent, and absence is *not* a match.
            //
            // A missing metric — an indoor run has no grade-adjusted pace, a watch that
            // dropped its HR strap has no average — means the band has not been *shown*
            // to apply, and a rubric row must not fire on evidence nobody collected.
            // Treating nil as "condition met" would score a run on a metric it does not
            // have; treating it as an error would make a legitimately incomplete
            // workout unscoreable. Falling through to the next band is the third option
            // and the right one, because the rubric can then say what it wants
            // explicitly with `.metricUnavailable`.
            //
            // A missing *reference* means the plan could not resolve the right-hand
            // side — in practice `.scheduledDistance` on a day with no prescribed
            // distance. Same reasoning: unresolvable comparison, no match.
            guard let measured = context.metrics.value(for: metric, workout: context.workout),
                  let threshold = plan.resolve(
                      reference,
                      scheduledDistanceMeters: planDay.scheduledSession.distanceMeters
                  )
            else {
                return false
            }
            return comparison.evaluate(measured, threshold)

        case let .actualClassification(kinds):
            // An empty list matches nothing, not everything. "One of []" is not a
            // statement any classification satisfies, and a band meant to apply
            // unconditionally says so by carrying no conditions at all.
            return kinds.contains(context.classification)

        case let .metricUnavailable(metric):
            return context.metrics.value(for: metric, workout: context.workout) == nil

        case .noWorkoutRecorded:
            // Always false here: a `WorkoutContext` exists because a workout was
            // recorded. §10.3's "skipped → 0–15" band is therefore unreachable through
            // this path — see the note on `RubricEvaluator` in the PR and the plan-model
            // gap it exposes: `Score` is keyed by `workoutID`, so a day with no workout
            // cannot carry a score record at all. Missed days surface through the
            // calendar (D9/MAX-016), not through the scorer.
            return false
        }
    }
}

extension ScoringRubric {
    /// Turns a score into a `ScoreBand` against **this** rubric's two cut points.
    ///
    /// This is the only place in the system entitled to make that decision.
    /// `ScoreBand` deliberately has no `init(score:)` — D1 makes the thresholds
    /// versioned plan data, so the mapping is a property of a specific plan version and
    /// not of the number. Putting it here, on the rubric that carries both thresholds,
    /// means the question "which band is a 62?" cannot even be asked without naming the
    /// plan version that answers it.
    public func scoreBand(for value: ScoreValue) -> ScoreBand {
        if value >= effectiveThreshold { return .effective }
        if value >= marginalThreshold { return .marginal }
        return .ineffective
    }
}
