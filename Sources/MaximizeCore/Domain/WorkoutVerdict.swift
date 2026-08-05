import Foundation

/// What the plan-verdict header (FR-1.1) has to say about one workout: what the plan
/// asked for, what actually happened, and the scoring verdict — if one has been reached
/// yet.
///
/// ## Why this exists as a core type rather than view logic
///
/// The header has to answer two questions that are not simple optional-unwraps:
///
/// 1. **What do we call "actual"?** Once a workout is scored, the classifier
///    (MAX-013) has already turned it into `.easy` / `.long` / `.hard` / `.other`
///    against the plan in force, and that stored classification is what the header
///    should show (D2 — never recompute what was already decided). Before scoring,
///    no classification exists to show — classifying requires derived metrics and the
///    plan version (see `WorkoutClassifier`), which is the scorer's job, not this
///    type's or a view's. So "actual" is a fact this type resolves by looking at
///    whether a `ScoreLedger` exists, not something a view should infer by checking
///    optionals in the right order.
/// 2. **Is this workout waiting for a score, never getting one, or on a day no plan
///    governs?** All three are real, distinct states — see `Scoring.awaitingScore`,
///    `Scoring.noVerdict` and `scheduledSession == nil` — and conflating any of them
///    with "loading" or "nothing to show" would misrepresent the workout on screen.
///    The second was added by MAX-126: MAX-111 stopped non-runs being scored, and until
///    it had a case of its own the header promised every lift a verdict that was never
///    going to arrive.
///
/// A view observes this, renders it, and forwards nothing (there is no user intent to
/// forward yet) — CLAUDE.md's "thin shell" rule applied to a header that has more than
/// one branch worth getting right, and worth testing where CI can see it.
public struct WorkoutVerdict: Hashable, Sendable {
    /// What the plan asked for on the workout's day, or nil when no plan version
    /// governs that day (`PlanCalendar.planDay(on:)` returned nil) — a run predating
    /// the plan, kept distinct from "the plan asked for rest."
    public let scheduledSession: ScheduledSession?

    /// What actually happened.
    public enum Actual: Hashable, Sendable {
        /// No score exists yet, so no plan-aware classification exists yet either.
        /// Carries the raw capture type — what HealthKit reported — which is the
        /// truthful answer to "what did you do" before scoring has run.
        case unclassified(ActivityType)

        /// The classification the scorer resolved and stored alongside the immutable
        /// auto-score (D2) — never recomputed here.
        case classified(WorkoutClassification)
    }
    public let actual: Actual

    /// The scoring verdict, or its honest absence — of which there are two kinds, and
    /// the difference between them is a difference in tense, not in degree.
    public enum Scoring: Hashable, Sendable {
        /// No automatic score has been recorded for this run **yet**, and one is still
        /// coming.
        ///
        /// **Not a placeholder for `.scored`.** This covers the seconds-to-minutes gap
        /// between a run finishing and scoring completing, and — for a run the scorer
        /// cannot reach right now (no API key stored, no network) — an indefinite wait
        /// that the lazy path retries every time the screen is opened. Both are
        /// ordinary, expected states, not errors.
        ///
        /// Named for the wait since MAX-126, because there is now a second scoreless
        /// state that is *not* one; `.unscored` described them both equally well, which
        /// is exactly why it had to stop being the only one.
        case awaitingScore

        /// No automatic score has been recorded for this workout and **none ever will
        /// be**: the plan scores runs (D1), and this was a lift, a ride, a hike or a
        /// walk (MAX-111).
        ///
        /// The athlete did the work. What is missing is a rubric to judge it by, which
        /// is a fact about the plan rather than about the session or about the app's
        /// progress through a queue. A view rendering this must not say a score is
        /// coming, and must not present the absence as an error or an apology — see
        /// `ScoreCalendarDayState.noVerdict`, which carries the same distinction for the
        /// calendar and the full argument for why the two absences are not one state.
        case noVerdict

        /// The immutable auto-score, together with the correction in force, if the
        /// user has made one (D8). `annotation` is `ScoreLedger.currentAnnotation` —
        /// the latest one — never a summary of the whole correction history; showing
        /// every past correction is out of this header's scope.
        ///
        /// There is deliberately no band on `annotation`. `ScoreBand` cannot be
        /// computed from a raw score (D1) — only the scorer, reading the plan version
        /// in force, may do that — and a manual correction is exactly a raw number
        /// with no stored band to read. `automatic.band` is the only band this type
        /// ever hands a view.
        case scored(automatic: Score, annotation: ScoreAnnotation?)
    }
    public let scoring: Scoring

    /// - Parameters:
    ///   - workout: the captured record. Only its `activityType` is read here (for
    ///     the unscored `.actual` case); everything else about the run belongs to the
    ///     tickets that draw it (HR curve, cadence, route, splits).
    ///   - planDay: the resolved calendar entry for the workout's day
    ///     (`PlanCalendar.planDay(on:)`), or nil if no plan governs it.
    ///   - ledger: the workout's score ledger (`ScoreRepository.ledger(forWorkout:)`),
    ///     or nil if scoring has not produced one.
    public init(workout: Workout, planDay: PlanDay?, ledger: ScoreLedger?) {
        self.scheduledSession = planDay?.scheduledSession
        if let ledger {
            self.actual = .classified(ledger.automatic.actualClassification)
            self.scoring = .scored(automatic: ledger.automatic, annotation: ledger.currentAnnotation)
        } else {
            self.actual = .unclassified(workout.activityType)
            // `activityType.isRun` is the same predicate `WorkoutIngestionPipeline`
            // declines to score on and `WorkoutClassifier` short-circuits on, on
            // purpose: one notion of "is this a run" in the core, not a third that can
            // drift from the two that decide whether a score is ever attempted.
            self.scoring = workout.activityType.isRun ? .awaitingScore : .noVerdict
        }
    }
}
