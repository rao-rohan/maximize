import Foundation

/// The tunable parts of one workout's trip through the ingestion pipeline.
///
/// Values, not constants in the algorithm, so a test can drive a wake that runs out of
/// scoring time or a model that has to be asked twice — neither of which can be arranged
/// on a device on demand.
public struct IngestionPipelinePolicy: Hashable, Sendable {
    /// Passed straight through to `WorkoutSampleExtractor` (MAX-032).
    public let sampleExtraction: SampleExtractionPolicy

    /// Passed straight through to `WorkoutClassifier` (MAX-013).
    public let classification: WorkoutClassificationPolicy

    /// Wall-clock seconds the model call may take before the pipeline stops waiting for
    /// it, or `nil` for no bound.
    ///
    /// This exists for tracker R8. A background wake is short and *unspecified*, and
    /// scoring is the only step in the pipeline that touches the network. The bound is
    /// not there to protect the workout — the ordering in `WorkoutIngestionPipeline`
    /// already does that, and the workout and its metrics are durable before the model
    /// is called at all. It is there to protect the *rest of the batch*: a wake draining
    /// several workouts must not spend its whole budget waiting on the first one's
    /// score, because the workouts behind it have not been captured yet.
    ///
    /// `nil` is right for the lazy path, where the athlete is looking at the screen and
    /// nothing is queued behind the call.
    public let scoringBudgetSeconds: TimeInterval?

    /// How many times the model may be asked for one workout's score.
    ///
    /// More than one because the instruction promises it: `WorkoutScorer`'s task text
    /// says "a score outside it will be rejected and you will be asked again", and a
    /// promise made in a prompt that the caller does not keep is a defect in the caller.
    /// Only failures `ScoringError.isWorthRetrying` admits are re-asked — the structural
    /// ones are deterministic in the plan data, and retrying them is the retry loop
    /// around an unscoreable workout that R11 warns about.
    public let scoringAttempts: Int

    private init(
        uncheckedSampleExtraction: SampleExtractionPolicy,
        classification: WorkoutClassificationPolicy,
        scoringBudgetSeconds: TimeInterval?,
        scoringAttempts: Int
    ) {
        self.sampleExtraction = uncheckedSampleExtraction
        self.classification = classification
        self.scoringBudgetSeconds = scoringBudgetSeconds
        self.scoringAttempts = scoringAttempts
    }

    public init(
        sampleExtraction: SampleExtractionPolicy = .standard,
        classification: WorkoutClassificationPolicy = .default,
        scoringBudgetSeconds: TimeInterval?,
        scoringAttempts: Int
    ) throws {
        if let scoringBudgetSeconds {
            try Validate.positive(scoringBudgetSeconds, "IngestionPipelinePolicy.scoringBudgetSeconds")
            // An upper bound as well as a lower one, because the budget is converted to
            // nanoseconds and a wildly large value would overflow that conversion rather
            // than behave like "no budget" — which is what `nil` is for.
            try Validate.within(
                scoringBudgetSeconds,
                0...Self.maximumScoringBudgetSeconds,
                "IngestionPipelinePolicy.scoringBudgetSeconds"
            )
        }
        guard scoringAttempts >= 1 else {
            throw DomainError.outOfRange(
                field: "IngestionPipelinePolicy.scoringAttempts",
                value: Double(scoringAttempts),
                lowerBound: 1,
                upperBound: nil
            )
        }
        self.init(
            uncheckedSampleExtraction: sampleExtraction,
            classification: classification,
            scoringBudgetSeconds: scoringBudgetSeconds,
            scoringAttempts: scoringAttempts
        )
    }

    /// An hour. Far past anything a wake could survive; present only so the budget cannot
    /// be a number that breaks the conversion to a sleep duration.
    public static let maximumScoringBudgetSeconds: TimeInterval = 3_600

    /// What production runs with: 20 seconds for the model call, asked at most twice.
    ///
    /// Twenty seconds is chosen against the shape of the wake rather than against a
    /// documented figure, because Apple documents none: `HKObserverQuery`'s completion
    /// handler is described only as needing to be called "as soon as you are done", and
    /// MAX-030 already notes that `.immediate` delivery frequency is a *request* iOS may
    /// clamp. So the budget is set where a normal scoring call comfortably fits and a
    /// stalled one does not consume a wake that still has workouts to capture.
    ///
    /// The budget applies to the wake path only. `WorkoutIngestionPipeline.completeIngestion(forWorkout:)`
    /// scores unbounded whatever this says, because nothing is queued behind it.
    public static let standard = IngestionPipelinePolicy(
        uncheckedSampleExtraction: .standard,
        classification: .default,
        scoringBudgetSeconds: 20,
        scoringAttempts: 2
    )
}

/// Something the ingestion pipeline decided to tolerate, or to give up on, for one
/// workout.
///
/// Every case marks a place the pipeline stored *less* than the full picture and carried
/// on. Those are exactly the events with no other trace: nothing crashes, the run still
/// appears in the app, and CI cannot see a device. Follows the rule
/// `IngestionDiagnostic` and `SampleExtractionDiagnostic` already set — reasons and
/// counts only, never a workout, a date, or an identifier (CLAUDE.md: health data is
/// PII).
///
/// **There is deliberately no success case.** A per-workout "captured" event would put a
/// timestamp in the log for every run the athlete does, and the time a run was ingested
/// is a fact about the athlete's day that the log has no need to hold.
public enum IngestionPipelineDiagnostic: Hashable, Sendable {
    /// Forwarded verbatim from `WorkoutSampleExtractor` (MAX-032).
    case sampleExtraction(SampleExtractionDiagnostic)

    /// The workout was stored, and its samples — heart rate, route, step count — were
    /// captured and stored right along with it (MAX-034), but no *derived metrics* exist
    /// because no plan governs it. Not a failure: every §9 metric is measured against a
    /// plan's cap, so scoring against no plan would be a number with no stated meaning
    /// (`ScoringError.noPlanInEffect`). The lazy path fills in metrics once a plan exists
    /// — see `MissingPlanReason.workoutPredatesEveryPlan` for the one case where it
    /// cannot.
    ///
    /// This case does **not** mean the workout has no samples. A missing sample is its
    /// own diagnostic (`sampleExtraction`, or `enrichmentFailed(stage: .sampleExtraction)`
    /// for a total extraction failure) and can fire independently of this one, including
    /// on the very same workout.
    case storedWithoutPlan(reason: MissingPlanReason)

    /// A stage of enrichment failed. The workout itself is already durable; what is
    /// missing is a derived record, and the lazy path can compute it again.
    case enrichmentFailed(stage: EnrichmentStage)

    /// The workout is stored and complete but carries no score. A first-class state, not
    /// an error — see `WorkoutIngestionPipeline`.
    case leftUnscored(reason: UnscoredReason)

    /// **R11's escape.** The pipeline gave up on this workout permanently so that the
    /// anchor could advance past it. See `WorkoutIngestionPipeline` for when this fires
    /// and why it is narrow.
    case workoutAbandoned(step: AbandonedStep)

    /// MAX-067: a `backfillDistanceSplits(policy:)` pass could not even enumerate
    /// candidates — the initial `WorkoutRepository.workouts(startingIn:)` read failed.
    /// No workout identifier to report, because none was reached; the next pass, on the
    /// next launch, tries again from scratch.
    case distanceSplitsBackfillEnumerationFailed

    public enum MissingPlanReason: Hashable, Sendable {
        /// No plan version has been authored yet — the state of a fresh install.
        ///
        /// Recoverable: `completeIngestion(forWorkout:)` re-resolves the plan calendar
        /// on every call, so the first plan the athlete ever authors can cover this
        /// workout's day retroactively (MAX-011 does not restrict where a *first*
        /// version's `effectiveFrom` may fall) and the lazy path fills in metrics then.
        case noPlanAuthored
        /// Plans exist, but the workout's day precedes every one of them.
        ///
        /// Not recoverable. `PlanCalendar` requires `version` to ascend with
        /// `effectiveFrom` (MAX-011), so no later plan version can ever open with an
        /// `effectiveFrom` earlier than one that already exists — that is what "no
        /// back-dating" means. Once any plan version exists, a workout on a day before
        /// all of them is stuck in this state permanently: `completeIngestion` will keep
        /// re-reporting it rather than ever finding a plan that governs the day.
        case workoutPredatesEveryPlan
    }

    public enum EnrichmentStage: Hashable, Sendable {
        case planResolution
        case sampleExtraction
        case metrics
        /// Storing a derived record — the curve, the route, or the metrics.
        case storage
    }

    public enum UnscoredReason: Hashable, Sendable {
        /// The workout is a ride, a hike, a walk or an activity type nobody has mapped —
        /// something the plan has no vocabulary for (MAX-111, narrowed by MAX-168).
        ///
        /// Not a failure and not a gap in the capture — the workout is stored, its
        /// heart-rate series is stored, and it shows up in the app. What it does not have
        /// is a verdict, because every band in `StandardPlanSeed`'s rubric measures either
        /// a run — against the plan's heart-rate cap, or against a prescribed running
        /// distance — or a lift, and the last one matches unconditionally. A ride judged
        /// against those gets a confident number that means nothing, and D8 would then
        /// make that number permanent.
        ///
        /// **This case stopped covering lifts in MAX-168** and now means what its name
        /// says. A lift is a discipline the plan can prescribe (A17) and the rubric can
        /// judge (MAX-131/132), so it is offered the scoring path; the two ways it can
        /// still come back unscored have their own reasons below. Nothing else moved:
        /// `ActivityType.isScoreable` is what splits them, and a ride is `false` there
        /// permanently, since `Discipline` is closed at two cases and no band naming a
        /// ride can be authored.
        ///
        /// Distinct from `rubricCouldNotBeApplied`, which says the rubric was applied and
        /// nothing matched. Here the rubric is never consulted at all, so nothing about
        /// the workout is assembled into a prompt either.
        case workoutIsNeitherARunNorALift

        /// A22/MAX-145: the lift is scoreable, and the athlete has not yet said what it
        /// worked (MAX-168).
        ///
        /// The amendment's own words — *"a lift cannot be scored at ingestion any more …
        /// a lift waits: not awaiting a model, not permanently unscoreable, but awaiting
        /// the athlete"*. HealthKit records that a session happened and never what it
        /// worked, so the one input a lift's judgement could grow beyond its clock is one
        /// only the athlete can supply. D2 computes metrics once and D8 makes an
        /// auto-score permanent, so a lift scored before the answer arrives is a lift
        /// judged without it, forever — and no later ticket that teaches the prompt or the
        /// rubric to read the groups can go back and re-judge it.
        ///
        /// Resolved by the athlete answering, on the screen that asks
        /// (`MuscleGroupEntryCopy.awaitingEntryHeadline`); `completeIngestion(forWorkout:)`
        /// is what scores it afterwards. Nothing about the workout reaches a prompt while
        /// this is the state — the check sits before the context is built.
        case liftAwaitingMuscleGroups

        /// The rubric was applied to a lift and the band it matched is not a band about
        /// lifting (MAX-168) — see `RubricBand.names(_:)`.
        ///
        /// Two shapes reach here, and both are the plan's answer rather than a defect:
        ///
        /// - **The day prescribed no lift.** `PlanDay.scheduledSession(for:)` answers
        ///   `.rest`, the day's lift bands are not in scope, and what matches is the
        ///   rubric's unconditional catch-all. A20 judges a lift on adherence to an ask,
        ///   and there was no ask — so scoring it would be inventing an opinion about
        ///   unscheduled lifting that MAX-146 explicitly declined to write.
        /// - **The plan version predates the lift bands.** D1 makes a rubric versioned
        ///   data, so a plan saved before MAX-132/MAX-146 carries neither the `lift.*`
        ///   rows nor the discipline condition that stops `rest.ranAnyway` stamping a lift
        ///   *"Ran on a scheduled rest day."* Merging those fixes changed no stored plan
        ///   and never could; adopting them is authoring a revision (MAX-173).
        ///
        /// Both are resolved by a **new plan version** — prescribe the lift day, adopt the
        /// current rubric, or both — which is D1's own mechanism, and the lazy path scores
        /// the workout the next time its screen is opened under a version that answers.
        case noLiftBandMatched
        /// The rubric could not be applied: no band matched what happened, or the
        /// context and the evaluation did not describe the same run. Deterministic in
        /// the plan data, so the lazy path will fail the same way until a new plan
        /// version adds a band (`ScoringError.noBandMatched`).
        case rubricCouldNotBeApplied
        /// `IngestionPipelinePolicy.scoringBudgetSeconds` elapsed first.
        case scoringBudgetExceeded
        /// The model could not be reached or refused the call — no API key, no network,
        /// a rate limit. The overwhelmingly common case, and the one the whole
        /// unscored-is-first-class design exists for.
        case modelUnavailable
        /// The model answered, and every attempt's answer was rejected by
        /// `WorkoutScorer`.
        case modelReplyRejected
        /// The score was produced but could not be written.
        case scoreCouldNotBeStored
    }

    public enum AbandonedStep: Hashable, Sendable {
        case storingTheWorkout
        case discardingTheWorkout
    }
}
