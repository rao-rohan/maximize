import Foundation

/// Everything Claude is told about one workout — assembled once, consumed by both the
/// scorer and the per-workout chat (D3).
///
/// ## Why one type and one renderer
///
/// D3 exists because two notions of "what Claude knows about this run" will diverge,
/// and the divergence is invisible until a number on screen disagrees with a sentence
/// in the chat. The scorer and the chat therefore do not each assemble facts: they
/// consume this, and they render it with the *same* `factSheet()`. What differs
/// between them is only the instruction wrapped around it — a rubric in one case, a
/// conversation in the other.
///
/// ## What is deliberately absent
///
/// CLAUDE.md: *"Only what the scorer or chat actually needs goes into a Claude prompt.
/// The context builder (D3) is the single place that decides this."* So this is that
/// decision, and the omissions are the interesting half:
///
/// - **No route coordinates.** Latitude and longitude are the most re-identifying data
///   in the record — a month of them is a home address, a workplace and a routine. The
///   scorer needs to know the terrain was hilly, and grade-adjusted pace (§9) already
///   says so in one number. Sending the polyline would leak a great deal to buy
///   nothing.
/// - **No raw heart-rate samples.** A run is thousands of them. `heartRateShape`
///   carries the *shape* at a fixed, bounded resolution, which is what a question like
///   "why did my HR climb after mile 3" actually needs.
/// - **No workout UUID, source device, or ingestion timestamp.** Identifiers and
///   provenance are ours; Claude has no use for them and they cannot help an answer.
///
/// ## Who is being told (MAX-068)
///
/// Two things are sent to chat and withheld from the scorer: `existingScore`, and the
/// `paceBreakdown` this ticket added. The asymmetry is the point — the two consumers
/// need genuinely different things, and the scoring call is the one that happens
/// *automatically, for every ingested run, whether or not anybody asked a question*.
/// That is the payload worth being strictest about. See `Audience`.
///
/// ## Why the pace breakdown is sent at all, and in this form
///
/// FR-2's own worked example is *"why did my HR drift at mile 3."* Before MAX-068 the
/// fact sheet could not answer it: `heartRateShape` is indexed by **elapsed time** and
/// the only distance in the prompt was the run's total, so "mile 3" named a place on
/// the curve that nothing in the context could locate. The splits are the index that
/// makes the heart-rate data already being sent addressable by distance. That is a
/// narrow, spec-named job, and it is the whole justification.
///
/// Three choices inside that, each of which had a cheaper-looking alternative:
///
/// - **Every split, not a summary.** A first/last/fastest/slowest reduction would be
///   smaller and would answer nothing: it discards the *position* that "mile 3" is
///   asking about. `HeartRateShape`'s 10-bucket downsample is the obvious precedent to
///   copy and it does not transfer, for a reason specific to this data. Raw heart-rate
///   samples are never shown to the athlete as individual numbers, so reducing them
///   cannot contradict anything on screen. Splits *are* shown, one row per split
///   (`SplitsListData`), so a bucketed reduction would have Claude reasoning about
///   4-kilometre averages while the athlete reads per-kilometre rows — a number in the
///   chat disagreeing with a number on the screen, which is the exact failure D2/D3
///   exist to prevent.
/// - **Kilometres, never the athlete's display unit.** The record stores both cuts, and
///   the mile cut is not sent. The fact sheet is already entirely kilometre-denominated
///   — distance, grade-adjusted pace — because prompt content must not vary with a
///   display preference, or the same stored run yields two different prompts on two
///   different days. Sending the mile series as well would double the exposure to save
///   Claude a unit conversion it can state in words.
/// - **Bounded by construction.** `maximumRenderedSplits` caps what is listed. The cap
///   is not aimed at real runs — a marathon is 43 entries — but at a pathological
///   record, where a corrupted distance could otherwise turn one run into thousands of
///   rows of prompt.
///
/// What this costs, stated plainly: a split series is a finer-grained record of one
/// person's movement than anything else in the prompt. It is still bounded, still
/// unit-fixed, still carries no coordinates and no timestamps, and it is sent only when
/// the athlete has opened a thread and typed a question.
public struct WorkoutContext: Hashable, Sendable {
    /// Which consumer this context was assembled for.
    ///
    /// Not a rendering style — a **minimisation switch**. CLAUDE.md's rule is that only
    /// what the scorer or chat actually needs enters a prompt, and the two do not need
    /// the same things. The scorer applies a rubric whose conditions are fixed,
    /// versioned plan data (D1) and which says nothing about splits; chat answers
    /// questions nobody enumerated in advance. Anything chat needs and the rubric never
    /// reads is therefore sent to one and not to the other.
    ///
    /// `.scoring` is the default wherever this appears, so a caller that says nothing
    /// gets the smaller payload. Exposure is opt-in, not opt-out.
    public enum Audience: String, Hashable, Sendable, CaseIterable {
        /// One automatic call per ingested workout, unattended (§10). The strictest
        /// budget in the app, because it spends itself whether or not anyone asked.
        case scoring

        /// One call per question the athlete actually typed (FR-2).
        case chat
    }

    /// Who this context was assembled to be shown to, and therefore what it carries.
    public let audience: Audience

    /// The calendar day the workout belongs to, in the athlete's zone. Resolved by the
    /// caller — `Workout.calendarDay(in:)` needs a time zone and this type refuses to
    /// guess one.
    public let day: CalendarDay

    public let workout: Workout
    public let metrics: DerivedMetrics
    public let classification: WorkoutClassification

    /// The plan governing `day`, and the ask it made. Both nil together when the day
    /// precedes every plan version — a real state, and one the scorer must be told
    /// about rather than left to infer from a missing section.
    public let plan: Plan?
    public let planDay: PlanDay?

    /// A bounded summary of the heart-rate curve. Nil when the workout has no HR data.
    public let heartRateShape: HeartRateShape?

    /// The score already assigned, when there is one.
    ///
    /// Present for chat — FR-2.1 seeds the thread with "the score already assigned" —
    /// and **absent when scoring**, because a scorer shown a previous verdict is being
    /// invited to agree with it, and the auto-versus-manual divergence that measures
    /// scorer quality (PRD §2) depends on the score being formed independently.
    public let existingScore: Score?

    /// The run cut into `paceBreakdownUnit` splits — **present for chat, absent for
    /// scoring** (MAX-068).
    ///
    /// Read from `DerivedMetrics.distanceSplits`, which `DistanceSplitCalculator` cut
    /// once at ingestion (D2); nothing here derives a pace. Nil for three different
    /// reasons and the fact sheet distinguishes them, because "the scorer is not shown
    /// this", "there was never a track to cut" and "we have no breakdown on file for a
    /// run that certainly had splits" are three different facts and only the last is a
    /// gap in our records.
    public let paceBreakdown: DistanceSplitSeries?

    /// The unit the pace breakdown is always rendered in.
    ///
    /// Fixed, not read from `AppSettings.distanceUnit`, and it matches the unit every
    /// other distance in the fact sheet already uses. Prompt content that moved with a
    /// display preference would make the same stored run produce two different prompts
    /// on two different days, which is D3's determinism requirement failing quietly.
    public static let paceBreakdownUnit = DistanceUnit.kilometers

    /// The most splits the fact sheet will list before saying so and listing none.
    ///
    /// Deliberately far above any real run — a marathon is 43 entries in kilometres —
    /// because this is not a budget for running long. It is the guard that keeps the
    /// prompt bounded when the record is *wrong*: a corrupted `Workout.distanceMeters`
    /// would otherwise cut one run into thousands of splits, and health data leaving
    /// the device should never be sized by a number nothing has validated.
    public static let maximumRenderedSplits = 200

    init(
        audience: Audience,
        day: CalendarDay,
        workout: Workout,
        metrics: DerivedMetrics,
        classification: WorkoutClassification,
        plan: Plan?,
        planDay: PlanDay?,
        heartRateShape: HeartRateShape?,
        paceBreakdown: DistanceSplitSeries?,
        existingScore: Score?
    ) {
        self.audience = audience
        self.paceBreakdown = paceBreakdown
        self.day = day
        self.workout = workout
        self.metrics = metrics
        self.classification = classification
        self.plan = plan
        self.planDay = planDay
        self.heartRateShape = heartRateShape
        self.existingScore = existingScore
    }
}

/// The heart-rate curve reduced to a fixed number of equal-time buckets.
///
/// Drift is a statement about the *shape* of a run (§9), and shape survives
/// downsampling while a token budget does not survive four thousand samples. Buckets
/// are equal spans of elapsed time rather than equal counts of samples, so an
/// irregularly sampled stretch does not silently stretch or compress the picture.
public struct HeartRateShape: Hashable, Sendable {
    public struct Bucket: Hashable, Sendable {
        /// Where this bucket starts, as a fraction of elapsed time (0…1). The same
        /// %-elapsed axis the cross-run drift overlay uses (D5/FR-3.3), so a number
        /// quoted in chat lines up with what the dashboard draws.
        public let startFraction: Double
        public let averageBeatsPerMinute: Double
    }

    public let buckets: [Bucket]

    init(buckets: [Bucket]) {
        self.buckets = buckets
    }

    /// Ten buckets: fine enough to show a mid-run climb, coarse enough that the fact
    /// sheet stays a page.
    public static let bucketCount = 10
}
