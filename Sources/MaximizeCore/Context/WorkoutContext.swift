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
public struct WorkoutContext: Hashable, Sendable {
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

    init(
        day: CalendarDay,
        workout: Workout,
        metrics: DerivedMetrics,
        classification: WorkoutClassification,
        plan: Plan?,
        planDay: PlanDay?,
        heartRateShape: HeartRateShape?,
        existingScore: Score?
    ) {
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
