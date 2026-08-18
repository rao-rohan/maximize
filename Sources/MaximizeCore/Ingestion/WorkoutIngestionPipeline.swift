import Foundation

/// FR-0.5, D2, A2: the step that turns a workout MAX-031 found into a stored, measured,
/// classified and — when it can be — scored record, with no server and nobody touching
/// the phone.
///
/// This is the `WorkoutIngestionSink` the pipeline has been pinned on since MAX-031.
/// Everything it does is a call into a piece that already exists: MAX-032 extracts the
/// samples, MAX-011 resolves the plan, MAX-012 measures, MAX-013 classifies, MAX-014
/// assembles the context, MAX-015 applies the rubric, MAX-020 stores. What is decided
/// *here* is the order those happen in, and what happens when one of them fails — which
/// turns out to be the whole ticket.
///
/// ## The shape, and why it is this shape
///
/// ```
/// ingest(workout)
///   ├─ capture   — one durable write. The only step that may throw.
///   └─ enrich    — everything else. Cannot throw, by construction.
/// ```
///
/// Three obligations fall out of that split, and each of them was going to need its own
/// mechanism if the split were made anywhere else.
///
/// ### R11 — the poison pill cannot form
///
/// MAX-030 acknowledges every wake, so iOS never retries; recovery depends entirely on
/// the anchor not advancing past unhandled work. The cost is that a workout which throws
/// *deterministically* is refetched and rethrown forever, and every workout recorded
/// after it queues behind it. Capture stops, and the symptom is silence.
///
/// The escape here is structural rather than a counter. Every failure that depends on
/// the *content* of a workout — an unreadable heart-rate series, a plan that does not
/// reach the day, a rubric with no matching band, a model that rejects the run, a reply
/// that will not parse — happens inside `enrich`, which returns normally no matter what
/// goes wrong. A deterministic content failure therefore cannot pin the anchor, because
/// there is no path from it to a thrown error. That is the entire class of realistic
/// poison pills, and it is closed by arrangement, not by giving up on anything.
///
/// What is left is `capture`: a single upsert of a `Workout` value MAX-031 has already
/// validated. It can still fail, and the two ways it can fail want opposite answers:
///
/// - **`DomainError` — the value cannot be represented.** Permanent by nature: the same
///   bytes will fail identically on every future pass. Abandoned, reported, and the
///   anchor is allowed past it. Losing one unstorable record beats losing every workout
///   recorded after it.
/// - **Anything else — the store could not write.** A full disk, a locked file, CloudKit
///   unavailable. These are *global and transient*: they are not about this workout, and
///   the next pass is very likely to succeed. Rethrown, so the anchor stays put and the
///   workout comes back.
///
/// A blind consecutive-failure counter was considered for the second class and rejected.
/// A storage failure that is genuinely permanent *and* specific to one workout is not
/// constructible against an upsert of an already-validated value; the failures that
/// actually occur are global, so a counter would abandon every workout in the batch
/// during a transient disk-full episode. That trades a recoverable stall for permanent
/// silent loss, which is the exact direction MAX-031's whole design refuses to move in.
/// The mechanism is left out rather than added as insurance whose failure mode is worse
/// than the thing it insures against.
///
/// ### An already-recorded auto-score is success
///
/// Replays are normal here — dedupe absorbs them by design (FR-0.5), and a lost anchor
/// re-delivers a whole backfill window. So `PersistenceError.automaticScoreAlreadyRecorded`
/// is not a failure: it is what D8 immutability looks like on a workout that has come
/// round again. It is caught and treated as done. Treating it as an error would pin the
/// anchor forever through the one path this pipeline is guaranteed to take.
///
/// ### C2 — durability before acknowledgement
///
/// `WorkoutIngestionSink` requires that `ingest` not return before its write is durable,
/// because the ingester persists the anchor immediately afterwards. `capture` awaits
/// `WorkoutRepository.store`, which saves before it returns, and nothing after that point
/// can undo it. Enrichment writes are durable on the same terms; a failure to make one of
/// them durable costs a derived record that can be recomputed, never the workout.
///
/// ### R8 — the wake budget
///
/// Scoring makes a network call inside a wake window that is short and unspecified. Two
/// things make that safe. First, the ordering: the workout and its metrics are durable
/// *before* the model is called, so a wake killed mid-scoring costs a score, not a run.
/// Second, `IngestionPipelinePolicy.scoringBudgetSeconds` bounds the call, so a stalled
/// model cannot consume a wake that still has workouts left to capture.
///
/// Scoring is attempted in the wake rather than deferred wholesale, because PRD §2 asks
/// for "end workout → scored and visible" under two minutes at p50 and deferring every
/// score to first view would make that number "whenever the athlete next opens the app".
/// When the attempt does not land, `completeIngestion(forWorkout:)` is the lazy path, and
/// MAX-041 is building the screen that calls it.
///
/// ## An unscored workout is a complete record
///
/// Follow the alternative through: if scoring failure failed ingestion, then every
/// workout recorded before the athlete enters an API key would be lost — and no-key is
/// the app's state the moment it is installed. So an unscored workout is stored,
/// measured, classified and first-class. It is a run the app knows everything about
/// except what Claude thinks of it.
///
/// ## Concurrency
///
/// An actor, because `AnchoredWorkoutIngester` serialises passes but the lazy path does
/// not go through the ingester at all: a background wake enriching a new workout and a
/// detail view scoring an old one can genuinely overlap. Isolation here means the two
/// cannot interleave inside one workout's enrichment. It does not — and need not —
/// prevent two *different* workouts being worked on in sequence; every write below is an
/// upsert or a D8-guarded insert, so the worst a true overlap could produce is a
/// redundant recomputation of a value that is a pure function of its inputs.
public actor WorkoutIngestionPipeline: WorkoutIngestionSink {
    private let workouts: WorkoutRepository
    private let scores: ScoreRepository
    private let plans: PlanRepository
    private let muscleGroups: (any MuscleGroupEntryRepository)?
    private let samples: WorkoutSampleFetching
    private let model: ScoringModelInvoking
    private let policy: IngestionPipelinePolicy
    private let timeZone: @Sendable () -> TimeZone
    private let now: @Sendable () -> Date
    private let report: @Sendable (IngestionPipelineDiagnostic) -> Void

    /// - Parameters:
    ///   - muscleGroups: A22's log, read to decide whether a lift may be scored yet
    ///     (MAX-168). **Nil means "this caller cannot look", and a lift is then never
    ///     scored** — the same reading `WorkoutVerdict` gives its own nil log, resolved in
    ///     the safe direction: D8 makes an auto-score permanent, so a pipeline that cannot
    ///     tell whether the athlete has answered must not answer for them. Defaulted so
    ///     every existing construction keeps its exact behaviour for runs.
    ///   - timeZone: the zone a workout's calendar day is resolved in.
    ///     `Workout.calendarDay(in:)` demands one and will not guess. `Workout` carries
    ///     none of its own, so the honest best available answer is the device's current
    ///     zone — which is right for the case that matters (the athlete runs where they
    ///     live) and can be wrong for a late-evening run recorded in a zone the athlete
    ///     has since left. Read once per enrichment and used for both the plan lookup and
    ///     the classifier, so those two can never disagree about which day a run was.
    ///   - now: injected rather than read from the clock so a score is a pure function of
    ///     its inputs and a test can assert on the whole record.
    ///   - report: called for every gap the pipeline tolerated. Defaults to discarding.
    ///     Whatever is passed **must not write health data anywhere durable** —
    ///     `IngestionPipelineDiagnostic` is built to carry none, and that property is
    ///     only worth having if the sink for it respects it.
    public init(
        workouts: WorkoutRepository,
        scores: ScoreRepository,
        plans: PlanRepository,
        muscleGroups: (any MuscleGroupEntryRepository)? = nil,
        samples: WorkoutSampleFetching,
        model: ScoringModelInvoking,
        policy: IngestionPipelinePolicy = .standard,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        now: @escaping @Sendable () -> Date = { Date() },
        report: @escaping @Sendable (IngestionPipelineDiagnostic) -> Void = { _ in }
    ) {
        self.workouts = workouts
        self.scores = scores
        self.plans = plans
        self.muscleGroups = muscleGroups
        self.samples = samples
        self.model = model
        self.policy = policy
        self.timeZone = timeZone
        self.now = now
        self.report = report
    }

    // MARK: - WorkoutIngestionSink

    /// FR-0.5's dedupe half. A workout the store already holds is not offered to
    /// `ingest` again.
    public func hasIngestedWorkout(id: UUID) async throws -> Bool {
        try await workouts.containsWorkout(id: id)
    }

    /// Captures the workout durably, then derives everything it can from it.
    ///
    /// Returns once the workout is stored. Whether it also ended up with metrics or a
    /// score is deliberately not signalled to the caller: the ingester's only question is
    /// "may the anchor move past this?", and once the workout is durable the answer is
    /// yes regardless of how much of the rest succeeded.
    public func ingest(_ workout: Workout) async throws {
        guard try await capture(workout) else { return }
        await enrich(workout, scoringBudgetSeconds: policy.scoringBudgetSeconds)
    }

    /// Handles a workout the health store reports as deleted.
    ///
    /// A no-op for an identifier that was never ingested — `WorkoutRepository.deleteWorkout`
    /// is specified that way, because a deletion can be re-delivered and the first fetch
    /// after a lost anchor can report the deletion of something this app never saw.
    public func discardWorkout(id: UUID) async throws {
        do {
            try await workouts.deleteWorkout(id: id)
        } catch is DomainError {
            // Same reasoning as `capture`: a delete that fails on the value itself will
            // fail identically forever, and refusing to move past it stops capture
            // altogether. Everything else is rethrown so the pass is retried.
            report(.workoutAbandoned(step: .discardingTheWorkout))
        }
    }

    // MARK: - Capture

    /// The one durable write, and the only step in the pipeline that may throw.
    ///
    /// - Returns: whether enrichment should follow. `false` means the workout was
    ///   abandoned and there is nothing to derive anything from.
    private func capture(_ workout: Workout) async throws -> Bool {
        do {
            try await workouts.store(workout)
        } catch is DomainError {
            // Permanent by nature — see the type documentation. Reported and stepped
            // over so the anchor advances and the workouts behind it are not lost too.
            report(.workoutAbandoned(step: .storingTheWorkout))
            return false
        }
        // Every other error propagates from the `do` above: the store could not write,
        // which is a condition of the store rather than of this workout, and the next
        // pass should try again.
        return true
    }

    // MARK: - Enrichment

    /// Runs the lazy path for a workout that is already stored (R8, and MAX-041's
    /// unscored state).
    ///
    /// Re-runs the whole of enrichment rather than only the missing part, which repairs
    /// a gap at any stage instead of just the last one. That is safe because every step
    /// is idempotent: `DerivedMetricsCalculator` is a pure function, `PlanCalendar`
    /// cannot gain a version that re-governs a day already past, and every write below
    /// is an upsert — except the auto-score, which D8 makes insert-once and which is
    /// checked for before the model is called at all.
    ///
    /// Does not throw. A caller here is a view or a foreground sweep, and there is
    /// nothing useful for either to do with a failure that the diagnostics do not
    /// already say better.
    ///
    /// **Returns immediately for a workout that already has a score**, before any query
    /// is run. That is what lets a screen call this unconditionally on appear rather than
    /// deciding for itself whether the run needs scoring — the check belongs here, where
    /// CI can see it, not in a view. A scored workout is necessarily a fully enriched one
    /// (metrics are stored before the model is asked, and scoring is abandoned if that
    /// write fails), so there is nothing an early return can leave unrepaired.
    public func completeIngestion(forWorkout id: UUID) async {
        let existingLedger = try? await scores.ledger(forWorkout: id)
        if existingLedger != nil { return }

        let stored: Workout?
        do {
            stored = try await workouts.workout(id: id)
        } catch {
            report(.enrichmentFailed(stage: .storage))
            return
        }
        guard let workout = stored else { return }
        // Unbounded, whatever the policy says: the wake budget exists to stop a stalled
        // model from starving workouts queued behind it, and on this path there are none.
        await enrich(workout, scoringBudgetSeconds: nil)
    }

    // MARK: - MAX-067: backfilling distance splits for pre-MAX-046 history

    /// Advances the distance-splits backfill by one bounded pass.
    ///
    /// ## Why this cannot be `completeIngestion(forWorkout:)`
    ///
    /// `completeIngestion` returns immediately for any workout that already has a score
    /// — by design (see its documentation) — and every workout on the athlete's device
    /// predates MAX-046, so every one of them already has a score. That early return is
    /// exactly what stopped a backfill falling out for free, and it must not be weakened:
    /// it is what lets a detail screen call `completeIngestion` unconditionally on appear
    /// without re-deriving metrics (and re-fetching HealthKit samples) on every view of
    /// every already-scored run. So this is a sibling, not a modification — a second,
    /// deliberately rarer door into the same `enrich` that `completeIngestion` already
    /// uses, opened only by a launch-triggered sweep rather than by a screen appearing.
    ///
    /// ## D8 is enforced exactly where it always was
    ///
    /// `enrich` recomputes the *whole* of `DerivedMetrics` — through
    /// `DerivedMetricsCalculator`, the one calculator D2 allows — and stores it, which is
    /// what makes a backfilled run's metrics identical to a freshly ingested one's. It
    /// then calls `applyScore`, which is untouched by this ticket: its very first line
    /// reads the existing ledger and returns *before the model is ever asked* when one is
    /// already on file. That check is D8's enforcement point, and it fires exactly the
    /// same way for a workout reached from here as for a replayed `ingest` or a repeated
    /// `completeIngestion` call. Nothing in this method — or in `enrich` — reads or writes
    /// a score directly; the auto-score is never in scope here at all.
    ///
    /// ## Distinguishing "not yet computed" from "computed, and the answer is none"
    ///
    /// `DerivedMetrics.distanceSplitsComputed` is what makes this safe to call on every
    /// launch forever. A route-less workout (indoor, or pre-MAX-034) will re-enrich to a
    /// `distanceSplits` of nil on every attempt — genuinely, permanently — but after the
    /// *first* attempt its `distanceSplitsComputed` is `true`, and this method's own
    /// candidate filter (`distanceSplitsComputed == false`) never selects it again. A
    /// workout is offered here exactly once per pass and, ordinarily, exactly once ever.
    ///
    /// ## Idempotent and interruptible
    ///
    /// Idempotent because `enrich` already is (see its documentation): running it twice
    /// on the same stored inputs produces the same stored metrics. Interruptible because
    /// every workout this method touches is re-enriched and its
    /// `distanceSplitsComputed = true` made durable — via the same store write `enrich`
    /// already performs — before the next one is even read; a phone locked mid-pass loses
    /// no ground; the next pass's candidate read simply excludes everything already done.
    ///
    /// ## Cost, and why enumeration and re-enrichment are bounded differently
    ///
    /// Candidates are found by reading every stored workout and, for each, its metrics —
    /// scalar fields and the small `zoneSplits`/`distanceSplits` blob, not the heart-rate
    /// or route curves. That read is proportional to the whole history, on every pass,
    /// forever, including once nothing is left to do — an accepted, stated cost, and cheap
    /// by the same reasoning the trends dashboard already reads full history for. What
    /// *cannot* run unbounded is re-enrichment itself: each candidate costs a HealthKit
    /// sample re-fetch and a store write, so only `policy.maxWorkoutsPerPass` of them are
    /// actually processed per call — see `DistanceSplitsBackfillPolicy` for the number and
    /// the reasoning behind it.
    ///
    /// - Returns: how many workouts were re-enriched and how many remain, so the caller
    ///   can log a count (never an identifier — CLAUDE.md) and so a test can assert
    ///   progress without reaching into the store.
    public func backfillDistanceSplits(
        policy: DistanceSplitsBackfillPolicy = .standard
    ) async -> DistanceSplitsBackfillOutcome {
        let candidates: [Workout]
        do {
            candidates = try await workouts.workouts(
                startingIn: DateInterval(start: .distantPast, end: now())
            )
        } catch {
            report(.distanceSplitsBackfillEnumerationFailed)
            return .nothingToDo
        }

        var pending: [Workout] = []
        pending.reserveCapacity(candidates.count)
        for workout in candidates {
            // `try?`: a metrics read that fails is not evidence the workout needs
            // backfilling, only that this attempt to check could not tell. Skipping it
            // costs nothing durable — it is read again, fresh, on the next pass.
            guard let metrics = try? await workouts.derivedMetrics(forWorkout: workout.id),
                  metrics.distanceSplitsComputed == false
            else { continue }
            pending.append(workout)
        }

        let toProcess = pending.prefix(policy.maxWorkoutsPerPass)
        for workout in toProcess {
            await enrich(workout, scoringBudgetSeconds: nil)
        }

        return DistanceSplitsBackfillOutcome(
            workoutsProcessed: toProcess.count,
            workoutsRemaining: pending.count - toProcess.count
        )
    }

    /// Everything derived from a workout that is already durable.
    ///
    /// **Cannot throw**, and that is the R11 escape rather than a convenience: a thrown
    /// error from here would reach `WorkoutIngestionSink.ingest`, pin the anchor, and
    /// re-offer this workout on every wake forever. Each stage therefore reports what it
    /// could not do and returns.
    ///
    /// ## Samples first, plan second (MAX-034)
    ///
    /// The heart-rate series, route and step count are facts about the run, not about
    /// the plan — a plan only supplies the cap and rubric that *derived metrics* are
    /// measured against. So sample extraction and storage happen unconditionally, before
    /// the plan is even looked up. Only the second half — metrics, classification,
    /// scoring, all of which are meaningless without a governing plan (§9) — is gated on
    /// `PlanCalendar.plan(on:)` returning non-nil.
    ///
    /// Getting this order backwards is exactly the bug this fixed: the old code checked
    /// for a plan first and returned before `WorkoutSampleExtractor.extract` ever ran,
    /// so a workout on a day no plan governs — every run present before the athlete
    /// authors their first plan version — kept no curve. D7 stores curves so MAX-062's
    /// drift overlay can read them; a run that never gets a curve is permanently outside
    /// that dataset, because MAX-031's anchor has already moved past it by the time
    /// anyone would notice.
    private func enrich(_ workout: Workout, scoringBudgetSeconds: TimeInterval?) async {
        let zone = timeZone()

        let input: DerivedMetricsInput
        do {
            input = try await WorkoutSampleExtractor.extract(
                for: workout,
                using: samples,
                policy: policy.sampleExtraction,
                report: forwardedSampleDiagnostics()
            )
        } catch {
            // MAX-032 degrades a failed heart-rate, route or step fetch to absence on its
            // own, so reaching here means the input could not be assembled at all.
            report(.enrichmentFailed(stage: .sampleExtraction))
            return
        }

        // D7: the curves are stored whole, and separately from the metrics derived from
        // them — and, as of MAX-034, separately from whether a plan governs this day at
        // all. A failure here is reported and stepped over rather than returned on: the
        // metrics (when a plan exists to compute them against) are derived from the
        // values already in hand, and losing the curve to a storage hiccup is no reason
        // to lose the numbers too.
        do {
            if let series = input.heartRateSeries {
                try await workouts.store(series)
            }
            if let route = input.route {
                try await workouts.store(route)
            }
        } catch {
            report(.enrichmentFailed(stage: .storage))
        }

        let calendar: PlanCalendar
        do {
            guard let resolved = try await plans.planCalendar() else {
                report(.storedWithoutPlan(reason: .noPlanAuthored))
                return
            }
            calendar = resolved
        } catch {
            report(.enrichmentFailed(stage: .planResolution))
            return
        }

        let day: CalendarDay
        do {
            day = try workout.calendarDay(in: zone)
        } catch {
            report(.enrichmentFailed(stage: .planResolution))
            return
        }

        // Nil is a real state, not a defect: the athlete existed before the app did, and
        // `PlanCalendar` answers nil rather than inventing an ask. Every §9 metric is
        // measured against the plan's cap, so there is nothing to compute either — but
        // the samples above are already durable regardless of this answer.
        guard let plan = calendar.plan(on: day) else {
            report(.storedWithoutPlan(reason: .workoutPredatesEveryPlan))
            return
        }

        // MAX-012's purity is what makes this two-pass shape well-defined: drift is gated
        // on classification, classification reads the metrics, and running `compute`
        // twice cannot produce a different answer. Only the second result is stored.
        let metrics: DerivedMetrics
        let classification: WorkoutClassification
        do {
            let provisional = try DerivedMetricsCalculator.compute(input, plan: plan)
            classification = try WorkoutClassifier.classify(
                workout,
                metrics: provisional,
                plan: plan,
                timeZone: zone,
                policy: policy.classification
            )
            metrics = try DerivedMetricsCalculator.compute(
                try input.classified(as: classification),
                plan: plan
            )
        } catch {
            report(.enrichmentFailed(stage: .metrics))
            return
        }

        do {
            // D2: computed once, at ingestion, and stored. Nothing downstream recomputes
            // this at display time.
            try await workouts.store(metrics)
        } catch {
            // Without stored metrics there is nothing coherent to score against, and the
            // score would outlive the numbers that justify it.
            report(.enrichmentFailed(stage: .storage))
            return
        }

        await applyScore(
            to: workout,
            on: day,
            metrics: metrics,
            classification: classification,
            planCalendar: calendar,
            heartRateSeries: input.heartRateSeries,
            budgetSeconds: scoringBudgetSeconds
        )
    }

    // MARK: - Scoring

    /// Asks the model for a score and records it, or leaves the workout unscored.
    ///
    /// Does not throw, for the reason `enrich` does not: a run the model cannot be asked
    /// about is a run that is stored and unscored, never a run that failed to ingest.
    private func applyScore(
        to workout: Workout,
        on day: CalendarDay,
        metrics: DerivedMetrics,
        classification: WorkoutClassification,
        planCalendar: PlanCalendar,
        heartRateSeries: HeartRateSeries?,
        budgetSeconds: TimeInterval?
    ) async {
        // D8 on a replay. Silent rather than reported: a workout coming round again is
        // normal operation here, not a gap, and the score it already has is the correct
        // and permanent one. A read that *throws* falls through and lets
        // `recordAutomaticScore` be the guard, which is where D8 is actually enforced.
        let existingLedger = try? await scores.ledger(forWorkout: workout.id)
        if existingLedger != nil { return }

        // MAX-111's gate, opened for a lift and left shut for everything else (MAX-168).
        //
        // The plan can now judge two disciplines. `RubricEvaluator` resolves the ask for
        // the workout's own slot (MAX-133), the rubric has the words to describe a lift
        // (MAX-131) and `StandardPlanSeed` writes three adherence bands with them
        // (MAX-132) — so refusing every non-run has stopped being the honest reading of
        // "the plan only knows how to score runs". What is left outside is the set the
        // rubric genuinely has no vocabulary for: a ride, a hike, a walk. See
        // `ActivityType.isScoreable`, which is where that line is drawn and why.
        //
        // Returning — rather than throwing — is what keeps every branch below inside
        // R11's guarantee: the workout is already durable, its samples are stored,
        // `enrich` completes normally, and the anchor moves on. The workout is captured;
        // it simply carries no score.
        let discipline = workout.activityType.discipline
        guard workout.activityType.isScoreable else {
            report(.leftUnscored(reason: .workoutIsNeitherARunNorALift))
            return
        }

        // A22: a lift waits for the athlete, not for a model. Asked here, before the
        // context is built, so a lift nobody has described still assembles nothing into a
        // prompt — the property MAX-111's gate had, kept for the state that replaces it.
        if discipline == .lift {
            let theAthleteHasAnswered = await athleteHasSaidWhatTheLiftWorked(workout.id)
            guard theAthleteHasAnswered else {
                report(.leftUnscored(reason: .liftAwaitingMuscleGroups))
                return
            }
        }

        let context: WorkoutContext
        let evaluation: RubricEvaluation
        do {
            context = try WorkoutContextBuilder.build(
                workout: workout,
                on: day,
                metrics: metrics,
                classification: classification,
                planCalendar: planCalendar,
                heartRateSeries: heartRateSeries,
                // Nil, deliberately: `WorkoutContext.existingScore` is for chat. A scorer
                // shown a previous verdict is being invited to agree with it.
                existingScore: nil
            )
            evaluation = try RubricEvaluator.evaluate(context)
        } catch {
            // Deterministic in the plan data and the context — most often a rubric with
            // no band for what happened, which `ScoringError.noBandMatched` documents as
            // wanting a new plan version rather than a retry.
            report(.leftUnscored(reason: .rubricCouldNotBeApplied))
            return
        }

        // **The rubric matched, and the question is what it matched with** (MAX-168).
        //
        // D1 makes the rubric versioned *data*, so what the seed says today is not what a
        // stored plan says: a plan saved before MAX-132/MAX-146 carries an unconditional
        // `rest.ranAnyway`, and an unprescribed lift lands on it and is stamped "Ran on a
        // scheduled rest day." — permanently, under D8. Merging that fix reached no
        // device; adopting it is a revision the athlete authors (MAX-173). So the gate
        // cannot assume the corrected bands are in force, and asking the *evaluation*
        // whether the band names this discipline is how it checks rather than assumes.
        //
        // The same guard covers the case where the rubric is current and the day simply
        // asked for no lift: the match is then the unconditional catch-all, which is the
        // plan's "no rule for this session", not an opinion about unscheduled lifting —
        // and MAX-146 declined to write that opinion precisely because choosing its score
        // range is a product decision. Both are answered by a new plan version, and both
        // leave the workout exactly as captured in the meantime.
        //
        // A run is not asked (see `RubricEvaluation.bandNamesItsDiscipline`), so nothing
        // on the run path changes: the same context, the same evaluation, the same
        // instruction, in the same order.
        if discipline == .lift, !evaluation.bandNamesItsDiscipline {
            report(.leftUnscored(reason: .noLiftBandMatched))
            return
        }

        let instruction: ScoringInstruction
        do {
            instruction = try WorkoutScorer.instruction(for: context, evaluation: evaluation)
        } catch {
            report(.leftUnscored(reason: .rubricCouldNotBeApplied))
            return
        }

        var attemptsRemaining = policy.scoringAttempts
        while attemptsRemaining > 0 {
            attemptsRemaining -= 1

            let reply: String
            do {
                reply = try await requestReply(to: instruction, budgetSeconds: budgetSeconds)
            } catch is ScoringBudgetExceeded {
                report(.leftUnscored(reason: .scoringBudgetExceeded))
                return
            } catch {
                // No key, no network, a rate limit. The ordinary case, and the reason
                // this whole function refuses to fail ingestion.
                report(.leftUnscored(reason: .modelUnavailable))
                return
            }

            let score: Score
            do {
                score = try WorkoutScorer.score(
                    context: context,
                    evaluation: evaluation,
                    modelResponse: reply,
                    scoredAt: now()
                )
            } catch let error as ScoringError where error.isWorthRetrying && attemptsRemaining > 0 {
                // The model's own fault, and the instruction told it it would be asked
                // again. Structural failures never reach here: `isWorthRetrying` is false
                // for them precisely so a retry loop cannot form around a run that will
                // never score.
                continue
            } catch {
                report(.leftUnscored(reason: .modelReplyRejected))
                return
            }

            do {
                try await scores.recordAutomaticScore(score)
            } catch PersistenceError.automaticScoreAlreadyRecorded {
                // Success, not failure. Another pass got there first; D8 says the score
                // already written is the permanent one, and there is nothing to repair.
                return
            } catch {
                report(.leftUnscored(reason: .scoreCouldNotBeStored))
                return
            }
            return
        }
    }

    /// Whether A22's answer is on file for this lift (MAX-168).
    ///
    /// Three ways to answer "no", and all three mean the same thing to the caller: no
    /// repository was supplied, the read failed, or the log is empty. The last is the
    /// ordinary state of a lift nobody has opened yet; the first two are the app being
    /// unable to tell — and under D8 "cannot tell" has to resolve the same way as "not
    /// yet", because the alternative writes a permanent score on a guess. A failed read is
    /// also not durable: the next pass, or the next time the screen is opened, asks again.
    private func athleteHasSaidWhatTheLiftWorked(_ workoutID: UUID) async -> Bool {
        guard let muscleGroups,
              let log = try? await muscleGroups.muscleGroupLog(forWorkout: workoutID)
        else {
            return false
        }
        return !log.isAwaitingEntry
    }

    /// One model call, optionally bounded by the wake budget (R8).
    ///
    /// The bound is a race rather than a request timeout because the transport's timeout
    /// is MAX-023's to set and answers a different question — how long one HTTP request
    /// may take, versus how long this wake is willing to wait in total.
    private func requestReply(
        to instruction: ScoringInstruction,
        budgetSeconds: TimeInterval?
    ) async throws -> String {
        // Bound locally so the child tasks below capture the value and not the actor.
        let model = self.model

        guard let budgetSeconds else {
            return try await model.reply(to: instruction)
        }

        return try await withThrowingTaskGroup(of: ScoringRaceOutcome.self) { group in
            group.addTask {
                let text = try await model.reply(to: instruction)
                return .replied(text)
            }
            group.addTask {
                // `try?`: a cancelled sleep means the model already answered, and the
                // value returned here is discarded when the group unwinds.
                try? await Task.sleep(nanoseconds: UInt64(budgetSeconds * 1_000_000_000))
                return .budgetExpired
            }

            guard let first = try await group.next() else {
                throw ScoringBudgetExceeded()
            }
            group.cancelAll()

            switch first {
            case let .replied(text):
                return text
            case .budgetExpired:
                throw ScoringBudgetExceeded()
            }
        }
    }

    private func forwardedSampleDiagnostics() -> @Sendable (SampleExtractionDiagnostic) -> Void {
        let report = self.report
        return { report(.sampleExtraction($0)) }
    }
}

/// Which half of the scoring race finished first.
private enum ScoringRaceOutcome: Sendable {
    case replied(String)
    case budgetExpired
}

/// Raised when `IngestionPipelinePolicy.scoringBudgetSeconds` elapsed before the model
/// answered. Internal: it never leaves the pipeline, which converts it to a diagnostic.
struct ScoringBudgetExceeded: Error {}

private extension DerivedMetricsInput {
    /// The same input with the classification supplied, for MAX-012's second pass.
    ///
    /// Cannot fail in practice — every cross-field invariant `DerivedMetricsInput`
    /// checks was already satisfied by the value this is derived from — but it is
    /// written through the validating initializer anyway rather than around it, because
    /// a `try!` here would be a force unwrap wearing a different hat.
    func classified(as classification: WorkoutClassification) throws -> DerivedMetricsInput {
        try DerivedMetricsInput(
            workout: workout,
            heartRateSeries: heartRateSeries,
            route: route,
            distanceSamples: distanceSamples,
            totalStepCount: totalStepCount,
            classification: classification
        )
    }
}
