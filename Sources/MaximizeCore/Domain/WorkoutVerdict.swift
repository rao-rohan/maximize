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
/// 2. **Is this workout waiting for a score, waiting on the athlete, never getting one,
///    or on a day no plan governs?** All four are real, distinct states — see
///    `Scoring.awaitingScore`, `Scoring.awaitingMuscleGroups`, `Scoring.noVerdict` and
///    `scheduledSession == nil` — and conflating any of them with "loading" or "nothing
///    to show" would misrepresent the workout on screen. The third was added by
///    MAX-126: MAX-111 stopped non-runs being scored, and until it had a case of its
///    own the header promised every lift a verdict that was never going to arrive. The
///    second was added by MAX-145 (A22), and it is the opposite correction: a lift the
///    athlete has not described yet is not permanently unscoreable — the app is waiting
///    on an answer it has asked for. **MAX-168 moved a lift out of the third and into
///    the first two**: the ingestion gate now offers a lift the scoring path, so
///    `.noVerdict` keeps only what it was always true of — a ride, a hike, a walk.
///
/// 3. **Which prescription is "what the plan asked for"?** A17 gave the plan two slots,
///    one per discipline, and a workout is only ever judged against its own (LIFTING-SPEC
///    §10.1). `discipline` and `scheduledSession` below answer this together; see
///    `scheduledSession`'s own documentation for the MAX-139 fix this made necessary.
///
/// A view observes this, renders it, and forwards nothing (there is no user intent to
/// forward yet) — CLAUDE.md's "thin shell" rule applied to a header that has more than
/// one branch worth getting right, and worth testing where CI can see it.
public struct WorkoutVerdict: Hashable, Sendable {
    /// Which of the plan's two prescriptions this workout answers to (A17). Read from
    /// `Workout.activityType.discipline`, the one place that mapping lives — the same
    /// source `WorkoutContext.discipline` and `MuscleGroupEntryData.resolve` already
    /// read, so the header cannot land on a different answer than the fact sheet or the
    /// muscle-group section give for the identical workout.
    public let discipline: Discipline

    /// What the plan asked for **this workout's own discipline** on its day, or nil
    /// when no plan version governs that day (`PlanCalendar.planDay(on:)` returned
    /// nil) — a run predating the plan, kept distinct from "the plan asked for rest."
    ///
    /// **MAX-139**: this used to be `planDay?.scheduledSession` unconditionally — the
    /// *run* slot, whatever the workout was — which is why a lift's header used to show
    /// the day's run ask instead of its own. `PlanDay.scheduledSession(for:)` is total
    /// in the discipline (rest is an answer on each slot), so reading through it costs
    /// nothing on a run: every reader before this ticket meant the run ask, and
    /// `discipline == .run` for every one of them, so nothing they saw changes.
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
        /// **A lift reaches this too, as of MAX-168**, once the athlete has said what it
        /// worked. Its wait can be longer than a run's and still honest: a lift on a day
        /// prescribing none, or under a plan version whose rubric predates the lift bands,
        /// is waiting on a new plan version — the same tense this state already carries
        /// for a run whose rubric has no band for what happened, since D1 makes a band a
        /// plan version rather than a code change.
        ///
        /// Named for the wait since MAX-126, because there is now a second scoreless
        /// state that is *not* one; `.unscored` described them both equally well, which
        /// is exactly why it had to stop being the only one.
        case awaitingScore

        /// A strength session the athlete has not said what they trained yet, so
        /// nothing can judge it — **awaiting the athlete**, not awaiting a model (A22,
        /// MAX-145).
        ///
        /// A22's load-bearing consequence, stated as a state. D2 computes derived
        /// metrics once when a workout arrives and D8 makes an auto-score immutable,
        /// but the muscle groups arrive *later*, whenever the detail screen is opened.
        /// A lift scored at ingestion would have been judged against information nobody
        /// had, and revising it afterwards is exactly what D8 forbids. So the lift
        /// waits.
        ///
        /// **The difference from `.awaitingScore` is who is being waited on**, and it
        /// changes what a surface may show. A run waiting on the scorer changes by
        /// itself, so a spinner is honest there. This one changes only when the athlete
        /// answers, so a spinner would be the app pretending to work on something it
        /// has not been given — a view rendering this asks the question instead
        /// (`MuscleGroupEntryCopy.awaitingEntryHeadline`). That prompt is also how the
        /// field is discovered at all, which is why the state is worth having rather
        /// than folding into either neighbour.
        ///
        /// **The difference from `.noVerdict` is tense.** `.noVerdict` says no verdict
        /// is coming; this says one cannot be reached *yet*, for a reason the athlete
        /// can remove.
        ///
        /// **And as of MAX-168 the sentence it shows is literally true** — *"This lift
        /// isn't scored until you set the muscle groups it worked."* When MAX-145 wrote
        /// that, nothing scored a lift under any condition, so the copy stated an
        /// amendment rather than a mechanism. The ingestion gate now honours it:
        /// `IngestionPipelineDiagnostic.UnscoredReason.liftAwaitingMuscleGroups` is this
        /// state seen from the pipeline's side, and answering is what unblocks the score.
        case awaitingMuscleGroups

        /// No automatic score has been recorded for this workout and **none ever will
        /// be**: this was a ride, a hike or a walk, and the plan's rubric has no
        /// vocabulary that describes one (MAX-111, narrowed by MAX-168 — a lift is now
        /// judged, and reaches `.awaitingScore` or `.awaitingMuscleGroups` instead).
        ///
        /// Still permanent, and by construction rather than by policy: `Discipline` is
        /// closed at two cases, a ride occupies the run slot without being a run, and
        /// there is no band editor with which an athlete could author a rule that named
        /// one. See `ActivityType.isScoreable`.
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

    /// What the athlete has said this session worked, or nil if they have not said
    /// (A22). Only ever non-nil on a lift — nothing asks a run the question.
    ///
    /// Carried here rather than looked up separately by each surface so that the
    /// header's copy and the section's copy are reading one fact, and so `scoring`
    /// above can be resolved from it in one place.
    public let muscleGroupEntry: MuscleGroupEntry?

    /// Set when the auto-score exists and was written against the wrong discipline's
    /// ask (A21/MAX-143), read straight off the ledger — never re-derived here, since
    /// `ScoreLedger.isMiscategorised` is already the one place that judgement is made
    /// and stored. Nil whenever there is no score yet and nil for an ordinary one.
    ///
    /// Carried beside `scoring` rather than folded into `.scored`'s associated values:
    /// the label is additional information about an unchanged score (MAX-143's whole
    /// point — nothing about the score's own presentation moves), not a fourth scoring
    /// outcome, so it does not belong in the enum that names outcomes.
    public let miscategorisationLabel: MiscategorisedScoreLabel?

    /// - Parameters:
    ///   - workout: the captured record. Only its `activityType` is read here (for
    ///     the unscored `.actual` case); everything else about the run belongs to the
    ///     tickets that draw it (HR curve, cadence, route, splits).
    ///   - planDay: the resolved calendar entry for the workout's day
    ///     (`PlanCalendar.planDay(on:)`), or nil if no plan governs it.
    ///   - ledger: the workout's score ledger (`ScoreRepository.ledger(forWorkout:)`),
    ///     or nil if scoring has not produced one.
    ///   - muscleGroups: this workout's muscle-group log
    ///     (`MuscleGroupEntryRepository.muscleGroupLog(forWorkout:)`), A22/MAX-145.
    ///
    ///     **Nil means "this caller did not look", not "the athlete has not said"** —
    ///     the two are different and only the second may produce
    ///     `.awaitingMuscleGroups`. An *empty* log is the athlete not having said; nil
    ///     resolves exactly as this initializer did before A22. That is what lets a
    ///     caller with no muscle-group repository to hand (the context builder, today)
    ///     keep its existing answer rather than assert a state it has not read, and it
    ///     is why the default is nil rather than an empty log.
    public init(
        workout: Workout,
        planDay: PlanDay?,
        ledger: ScoreLedger?,
        muscleGroups: MuscleGroupLog? = nil
    ) {
        let discipline = workout.activityType.discipline
        self.discipline = discipline
        self.scheduledSession = planDay?.scheduledSession(for: discipline)
        self.muscleGroupEntry = muscleGroups?.current
        self.miscategorisationLabel = ledger?.miscategorisationLabel
        if let ledger {
            self.actual = .classified(ledger.automatic.actualClassification)
            self.scoring = .scored(automatic: ledger.automatic, annotation: ledger.currentAnnotation)
        } else {
            self.actual = .unclassified(workout.activityType)
            // A22 first, and the order is the ticket (MAX-168). A lift the athlete has
            // not answered for is waiting on *them*, and it is the pipeline's first gate
            // too — so asking `isScoreable` before this would collapse the state A22
            // added into the generic wait and take the question off the screen that asks
            // it. Read through `Discipline` rather than compared to an activity type, so
            // a strength type mapped later is asked the same question, and so
            // `MuscleGroupEntryData.resolve` and this cannot disagree about which
            // workouts the app asks.
            //
            // The ledger branch above is what keeps D8 intact here: a lift that was
            // already scored as a run (A21/MAX-143) never reaches this line, so no
            // existing score changes state.
            if discipline == .lift, let muscleGroups, muscleGroups.isAwaitingEntry {
                self.scoring = .awaitingMuscleGroups
            } else if workout.activityType.isScoreable {
                // `isScoreable` rather than `isRun` since MAX-168: a lift is now offered
                // the scoring path, so telling the athlete no verdict is coming would be
                // false the moment one arrives. The same predicate the pipeline gates on
                // and the calendar splits on — one notion of "can this be judged" in the
                // core, not three that can drift.
                self.scoring = .awaitingScore
            } else {
                self.scoring = .noVerdict
            }
        }
    }
}
