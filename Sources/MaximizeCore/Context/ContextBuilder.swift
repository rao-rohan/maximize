import Foundation

/// What Claude is told about a chat thread's subject, in whichever shape that subject
/// takes (CHAT-FIRST-SPEC.md §3.2, PRD-AMENDMENTS.md A12).
///
/// Two cases behind one renderer. `factSheet()` is the only rendering either case has, so
/// a consumer holds "the context" without holding a branch — which is what keeps the
/// transport and the view layer out of the business of composing prompt text.
///
/// The set is closed because `ChatSubject` is: A12 rule 2 makes a third subject an
/// amendment rather than a ticket, because every subject is a new answer to *what health
/// data leaves the device*, and that is not a question a ticket should be able to answer
/// on its own.
public enum PromptContext: Hashable, Sendable {
    case workout(WorkoutContext)
    case training(TrainingContext)

    /// The exact text that goes in front of Claude. Dispatches; neither consumer may
    /// reformat, trim or extend it. What a consumer adds is the *instruction* around it.
    public func factSheet() -> String {
        switch self {
        case let .workout(context): return context.factSheet()
        case let .training(context): return context.factSheet()
        }
    }

    /// Which shape this is, without unwrapping it — the same discriminator
    /// `ChatSubject.kind` gives, so a caller choosing an instruction (MAX-096) does not
    /// have to switch over payloads it will not read.
    public var subjectKind: ChatSubjectKind {
        switch self {
        case .workout: return .workout
        case .training: return .training
        }
    }
}

/// The stored records `ContextBuilder` assembles a context from.
///
/// Everything here is **read from storage, never derived**: a workout, the metrics
/// computed for it once at ingestion (D2), the ledger the scorer wrote (D8), the plan
/// calendar, and the athlete's settings. This type computes nothing and validates only
/// that the pieces describe the same workouts.
///
/// ## One bundle for both subjects, on purpose
///
/// A workout thread does not use `today` or `restDayBudget`, and a training thread does
/// not use `heartRateSeries`. Two input types would let a caller assemble one shape and
/// hand it to the wrong builder; one bundle behind one entry point is what A12 rule 1 asks
/// for, and the unused fields cost a caller nothing to supply because it already holds
/// them.
///
/// ## The calling convention `records` carries (this is C1, reaching one type further)
///
/// `TalliesCalculator` must never see a partial training week — ranking a missed day is
/// relative to the other misses *in its week*. It widens its own plan lookups to the whole
/// Monday-first weeks touching the interval, but it cannot widen the workouts it was
/// handed. **So for a training subject, `records` must cover every day in the Monday-first
/// weeks touching the scope, not merely the scope itself.** A caller supplying only the
/// scope's own workouts, when the scope does not already start on a Monday and end on a
/// Sunday, will misjudge misses at the edges — and the roll-up and the dashboard would
/// then disagree, which is the failure §3.6 exists to make impossible.
///
/// Supplying more than that is harmless: the session list filters to the scope itself
/// rather than trusting the caller to have narrowed it, exactly as `TrendTileData` does.
public struct ContextInputs: Sendable {

    /// One workout and everything stored alongside it.
    public struct WorkoutRecord: Hashable, Sendable, Identifiable {
        public var id: UUID { workout.id }

        public let workout: Workout

        /// `DerivedMetricsCalculator`'s output, stored at ingestion (D2). **Nil is a real
        /// state**: a workout ingested on a day no plan governed has no derived metrics
        /// at all (`IngestionPipelineDiagnostic.storedWithoutPlan`), and the lazy path
        /// fills them in later — or never, for a workout predating every plan version.
        public let metrics: DerivedMetrics?

        /// The score and any corrections (D8). Nil for an unscored workout — an ordinary,
        /// often indefinite state (no API key stored, no network) and, since MAX-111, the
        /// *permanent* state of every non-run.
        public let ledger: ScoreLedger?

        /// The stored heart-rate curve. Read only by the workout subject, which turns it
        /// into a bounded `HeartRateShape`; a training roll-up carries no curve for any
        /// session (§3.3), so a caller building one should pass nil and avoid the read.
        public let heartRateSeries: HeartRateSeries?

        /// - Throws: when the pieces do not describe the same workout. These are assembly
        ///   errors, and failing on them here means a mismatch cannot reach a prompt: a
        ///   context quietly pairing one run's metrics with another's score would produce
        ///   a confident, wrong answer with nothing on screen to contradict it.
        public init(
            workout: Workout,
            metrics: DerivedMetrics? = nil,
            ledger: ScoreLedger? = nil,
            heartRateSeries: HeartRateSeries? = nil
        ) throws {
            if let metrics, metrics.workoutID != workout.id {
                throw DomainError.inconsistent(
                    reason: "ContextInputs.WorkoutRecord: metrics belong to a different workout"
                )
            }
            if let ledger, ledger.automatic.workoutID != workout.id {
                throw DomainError.inconsistent(
                    reason: "ContextInputs.WorkoutRecord: score ledger belongs to a different workout"
                )
            }
            if let heartRateSeries, heartRateSeries.workoutID != workout.id {
                throw DomainError.inconsistent(
                    reason: "ContextInputs.WorkoutRecord: heart-rate series belongs to a different workout"
                )
            }
            self.workout = workout
            self.metrics = metrics
            self.ledger = ledger
            self.heartRateSeries = heartRateSeries
        }
    }

    /// The athlete's zone, not the device's — matching `Workout.calendarDay(in:)` and
    /// `TalliesInput`, both of which refuse to guess one.
    public let timeZone: TimeZone

    /// The athlete's current civil day, in `timeZone`. **An input, never a clock read**
    /// (MAX-110): `TalliesCalculator` withholds days whose outcome is not yet known from
    /// both sides of the effective-day ratio, and a calculator that called `Date()` would
    /// disagree with the calendar cell beside it the moment the two read the clock at
    /// different instants.
    ///
    /// Distinct from `TrainingScope.through`, and deliberately so: a frozen window can end
    /// in the past, and a window ending in the future must not have its unfinished days
    /// counted as misses.
    public let today: CalendarDay

    /// Nil before the first plan version is authored — a real state, not "no data".
    public let planCalendar: PlanCalendar?

    /// D9's weekly allowance, from `AppSettings`. Read by `TalliesCalculator` only.
    public let restDayBudget: RestDayBudget

    /// See the type's documentation for the range this must cover for a training subject.
    /// For a workout subject it need only contain that workout.
    public let records: [WorkoutRecord]

    /// - Throws: when two records claim the same workout. `records` is indexed by workout
    ///   id below, and a duplicate would make which of the two a context described depend
    ///   on array order.
    public init(
        timeZone: TimeZone,
        today: CalendarDay,
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget,
        records: [WorkoutRecord]
    ) throws {
        var seen = Set<UUID>()
        for record in records {
            guard seen.insert(record.workout.id).inserted else {
                throw DomainError.duplicate(field: "ContextInputs.records", key: "\(record.workout.id)")
            }
        }
        self.timeZone = timeZone
        self.today = today
        self.planCalendar = planCalendar
        self.restDayBudget = restDayBudget
        self.records = records
    }
}

/// **The** assembler of prompt context, over a closed set of subjects (D3, A12 rule 1).
///
/// One module, one entry point. Nothing else in the system may compose prompt text —
/// CLAUDE.md makes that a rule rather than a preference, and A12 restates it for the case
/// D3's original wording did not anticipate: a thread with no workout.
///
/// ## Why this is not a second assembler
///
/// D3's guarantee is *one assembler per subject, shared by every consumer of that
/// subject*. The workout subject has two consumers — the scorer and a workout thread —
/// and they share `WorkoutContextBuilder`, which this calls and does not wrap, reorder or
/// re-word. **The scorer keeps calling that builder directly, byte for byte**, so a
/// scoring prompt and a workout chat prompt still cannot diverge. The training subject has
/// one consumer and nothing to diverge from. Two cases behind one entry point is one
/// place; a view model or a transport composing its own text would be a second, and that
/// is what A12 forbids.
///
/// ## The audience is always chat
///
/// Everything this builds is for a conversation the athlete opened and typed into.
/// `WorkoutContext.Audience.scoring` is the *other* caller's business: the scorer's payload
/// is the strict one because it spends itself automatically on every ingested workout
/// whether or not anybody asked a question, and it reaches `WorkoutContextBuilder` without
/// passing through here.
public enum ContextBuilder {

    /// Assembles the context for one chat thread's subject.
    ///
    /// - Throws: `DomainError.inconsistent` when the inputs cannot describe the subject —
    ///   the workout is not among the records, has no derived metrics, or has not been
    ///   scored. All three are real states rather than defects, and all three are worth
    ///   failing on rather than papering over, because each would otherwise produce a
    ///   fact sheet quietly missing the thing the conversation is about.
    public static func build(for subject: ChatSubject, from inputs: ContextInputs) throws -> PromptContext {
        // Exhaustive over a closed set. Adding a subject is an amendment (A12 rule 2), and
        // when one is added the compiler demands a context for it here rather than letting
        // it default to something smaller or larger than intended.
        switch subject {
        case let .workout(workoutID):
            return .workout(try workoutContext(for: workoutID, from: inputs))
        case let .training(scope):
            return .training(try trainingContext(for: scope, from: inputs))
        }
    }

    // MARK: - The workout subject — delegated, unchanged

    private static func workoutContext(
        for workoutID: UUID,
        from inputs: ContextInputs
    ) throws -> WorkoutContext {
        guard let record = inputs.records.first(where: { $0.workout.id == workoutID }) else {
            throw DomainError.inconsistent(
                reason: "ContextBuilder: no stored record was supplied for workout \(workoutID)"
            )
        }
        guard let metrics = record.metrics else {
            throw DomainError.inconsistent(
                reason: "ContextBuilder: workout \(workoutID) has no derived metrics, so there is "
                    + "nothing measured to describe. A workout ingested on a day no plan governed "
                    + "has none until the lazy path fills them in."
            )
        }
        guard let planCalendar = inputs.planCalendar else {
            throw DomainError.inconsistent(
                reason: "ContextBuilder: no plan version has been authored, so workout \(workoutID) "
                    + "has no plan to be measured against."
            )
        }
        guard let ledger = record.ledger else {
            // FR-2.1 seeds a workout thread with the score already assigned, and
            // `WorkoutContext` needs a classification to render at all. That classification
            // is a stored decision the scorer made (`Score.actualClassification`, D2);
            // re-deriving it here would be a second classifier, free to disagree with the
            // one the score was computed under. So an unscored workout has no context yet —
            // ordinary, not a failure, and `WorkoutChatModel` already treats it as a state.
            throw DomainError.inconsistent(
                reason: "ContextBuilder: workout \(workoutID) has not been scored, so nothing has "
                    + "classified it and there is no verdict to open a conversation about."
            )
        }

        let day = try record.workout.calendarDay(in: inputs.timeZone)
        return try WorkoutContextBuilder.build(
            workout: record.workout,
            on: day,
            metrics: metrics,
            classification: ledger.automatic.actualClassification,
            planCalendar: planCalendar,
            audience: .chat,
            heartRateSeries: record.heartRateSeries,
            existingScore: ledger.automatic
        )
    }

    // MARK: - The training subject — a roll-up, assembled from core functions only

    private static func trainingContext(
        for scope: TrainingScope,
        from inputs: ContextInputs
    ) throws -> TrainingContext {
        // §3.6(a): the tallies come from the function the dashboard tiles read, over this
        // exact window, and are carried verbatim. Nothing below re-derives one of them.
        let tallies = try TalliesCalculator.compute(
            TalliesInput(
                from: scope.from,
                through: scope.through,
                timeZone: inputs.timeZone,
                today: inputs.today,
                workouts: inputs.records.map(\.workout),
                scoreLedgers: scoreLedgers(in: inputs),
                planCalendar: inputs.planCalendar,
                restDayBudget: inputs.restDayBudget
            )
        )

        var inScope: [(record: ContextInputs.WorkoutRecord, day: CalendarDay)] = []
        for record in inputs.records {
            let day = try record.workout.calendarDay(in: inputs.timeZone)
            guard day >= scope.from, day <= scope.through else { continue }
            inScope.append((record: record, day: day))
        }
        // Chronological, with the workout id breaking a tie so two sessions recorded at the
        // same instant cannot swap places between two builds of the same window. A prompt
        // that reordered itself would break D3's determinism as surely as a reformatted
        // number would.
        inScope.sort {
            ($0.record.workout.start, $0.record.workout.id.uuidString)
                < ($1.record.workout.start, $1.record.workout.id.uuidString)
        }

        let sessions: [TrainingContext.Session]
        if inScope.count > TrainingContext.maximumRenderedSessions {
            // Beyond the cap: state the count, list none. See
            // `TrainingContext.maximumRenderedSessions` for why this branch is reachable
            // by a legitimate window rather than only by a corrupt record.
            sessions = []
        } else {
            sessions = try inScope.map { try session(for: $0.record, on: $0.day, in: inputs) }
        }

        let plan = inputs.planCalendar?.plan(on: scope.through)
        return TrainingContext(
            scope: scope,
            plan: plan,
            planCoverage: planCoverage(of: scope, in: inputs.planCalendar, governing: plan),
            tallies: tallies,
            sessions: sessions,
            sessionCountInScope: inScope.count
        )
    }

    private static func session(
        for record: ContextInputs.WorkoutRecord,
        on day: CalendarDay,
        in inputs: ContextInputs
    ) throws -> TrainingContext.Session {
        var planDay: PlanDay?
        if let planCalendar = inputs.planCalendar {
            planDay = try planCalendar.planDay(on: day)
        }

        return TrainingContext.Session(
            workoutID: record.workout.id,
            day: day,
            activityType: record.workout.activityType,
            // The same resolution the workout detail header runs (§3.6(a)): what the plan
            // asked, what the classifier decided, and the verdict or its honest absence.
            verdict: WorkoutVerdict(workout: record.workout, planDay: planDay, ledger: record.ledger),
            // Stored figures, read (D2). No metric is computed here, at prompt time or
            // anywhere near it.
            distanceMeters: record.workout.distanceMeters,
            durationSeconds: record.workout.durationSeconds,
            averageHeartRateBPM: record.metrics?.averageHeartRateBPM,
            heartRateDriftFraction: record.metrics?.heartRateDriftFraction
        )
    }

    private static func scoreLedgers(in inputs: ContextInputs) -> [UUID: ScoreLedger] {
        var ledgers: [UUID: ScoreLedger] = [:]
        for record in inputs.records {
            guard let ledger = record.ledger else { continue }
            ledgers[record.workout.id] = ledger
        }
        return ledgers
    }

    /// How much of the window the plan governing its last day actually governed.
    ///
    /// Decided by comparing the two endpoints rather than by resolving every day in the
    /// window — a year would be 365 lookups to produce one answer. Comparing endpoints is
    /// exact, not an approximation: `PlanCalendar` guarantees versions are contiguous and
    /// that `version` ascends with `effectiveFrom`, so the versions governing the window
    /// are exactly those from the one at `from` to the one at `through`, and the two agree
    /// if and only if a single version covered the lot.
    private static func planCoverage(
        of scope: TrainingScope,
        in calendar: PlanCalendar?,
        governing plan: Plan?
    ) -> TrainingContext.PlanCoverage {
        // No plan governs the last day, so — resolution being monotone in the day — none
        // governs any day of the window.
        guard let calendar, let plan else { return .wholeWindow }
        guard let atStart = calendar.plan(on: scope.from) else { return .beganWithinTheWindow }
        guard atStart.version != plan.version else { return .wholeWindow }
        return .revisedWithinTheWindow(earlier: atStart.version)
    }
}
