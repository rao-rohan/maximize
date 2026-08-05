import Foundation

/// The dimensionless knobs that turn plan data into a classification (§10.2).
///
/// ## Why this type exists at all
///
/// D1 says thresholds are plan data. Every *quantity* this classifier compares against
/// is exactly that: the HR cap and the zones anchored to it, the week's long-run
/// distance from the arc, the distances the weekly template prescribes. What is left
/// over is the shape of the rule — "how much of the week's long run still counts as
/// the long run", "how much time at threshold makes a session hard" — and `Plan`
/// (MAX-010) has no field for any of it.
///
/// **Known gap, stated plainly:** these fractions are a modelling choice living in
/// code, exactly as `HeartRateZoneModel.capAnchoredMultipliers` is. They are ratios,
/// never absolutes — there is no bpm, no metre and no minute in this type, so a plan
/// that moves its cap or its arc moves every threshold with it. The honest fix is a
/// `classification` block on a future plan version, at which point this value is
/// decoded from that record instead of read from `.default`. Every entry point takes
/// the policy as a parameter, so that change is additive.
public struct WorkoutClassificationPolicy: Hashable, Sendable, Codable {
    /// Fraction of the week's prescribed long-run distance at or above which a run *is*
    /// the long run.
    ///
    /// Below 1.0 on purpose: a long run cut a kilometre short is still the long run,
    /// and judging the shortfall is the scorer's job, not the classifier's. Calling it
    /// "easy" instead would hand the scorer the wrong rubric branch entirely.
    public let longRunDistanceFraction: Double

    /// Fraction of the shortest run the plan prescribes below which a recorded run is a
    /// fragment — a mis-started or accidentally-split session — rather than a workout.
    ///
    /// Zero disables the test.
    public let fragmentDistanceFraction: Double

    /// The lowest zone counted as high-intensity work. With cap-anchored zones, zone 4
    /// begins ~8% above the cap: comfortably past "an easy run that got away from you"
    /// and into tempo/threshold/interval territory.
    public let hardZoneFloor: HeartRateZone

    /// Fraction of the heart-rate curve's covered time spent at or above
    /// `hardZoneFloor` that makes the session hard.
    ///
    /// Deliberately well under half. A structured session is mostly warm-up, recovery
    /// jogs and cool-down; the hard part of 6 × 800m is a fifth of the elapsed time.
    /// Requiring a majority would classify every interval session as easy, which is the
    /// single most damaging mistake available here — drift is suppressed on hard runs
    /// (§9) and would be published for a session it is meaningless on.
    public let hardZoneTimeFraction: Double

    public init(
        longRunDistanceFraction: Double,
        fragmentDistanceFraction: Double,
        hardZoneFloor: HeartRateZone,
        hardZoneTimeFraction: Double
    ) throws {
        // Every knob is a fraction of something the plan states, so 0...1 is the whole
        // legal domain: a rule asking for more than all of a run, or more than the whole
        // prescribed distance, could never be satisfied.
        let field = "WorkoutClassificationPolicy."
        try Validate.within(longRunDistanceFraction, 0...1, field + "longRunDistanceFraction")
        try Validate.positive(longRunDistanceFraction, field + "longRunDistanceFraction")
        try Validate.within(fragmentDistanceFraction, 0...1, field + "fragmentDistanceFraction")
        try Validate.within(hardZoneTimeFraction, 0...1, field + "hardZoneTimeFraction")
        try Validate.positive(hardZoneTimeFraction, field + "hardZoneTimeFraction")

        self.longRunDistanceFraction = longRunDistanceFraction
        self.fragmentDistanceFraction = fragmentDistanceFraction
        self.hardZoneFloor = hardZoneFloor
        self.hardZoneTimeFraction = hardZoneTimeFraction
    }

    private init(
        uncheckedLongRunDistanceFraction longRunDistanceFraction: Double,
        fragmentDistanceFraction: Double,
        hardZoneFloor: HeartRateZone,
        hardZoneTimeFraction: Double
    ) {
        self.longRunDistanceFraction = longRunDistanceFraction
        self.fragmentDistanceFraction = fragmentDistanceFraction
        self.hardZoneFloor = hardZoneFloor
        self.hardZoneTimeFraction = hardZoneTimeFraction
    }

    /// What production classifies with until the plan record can express it.
    public static let `default` = WorkoutClassificationPolicy(
        uncheckedLongRunDistanceFraction: 0.85,
        fragmentDistanceFraction: 0.25,
        hardZoneFloor: .four,
        hardZoneTimeFraction: 0.15
    )

    private enum CodingKeys: String, CodingKey {
        case longRunDistanceFraction, fragmentDistanceFraction, hardZoneFloor, hardZoneTimeFraction
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            longRunDistanceFraction: container.decode(Double.self, forKey: .longRunDistanceFraction),
            fragmentDistanceFraction: container.decode(Double.self, forKey: .fragmentDistanceFraction),
            hardZoneFloor: container.decode(HeartRateZone.self, forKey: .hardZoneFloor),
            hardZoneTimeFraction: container.decode(Double.self, forKey: .hardZoneTimeFraction)
        )
    }
}

/// Classifies what the athlete **actually did** — easy / long / hard / other — from the
/// activity type and the heart-rate profile, against the plan in force (§10.2).
///
/// ## The classifier does not look at the day's prescription
///
/// It sees the `Plan`, and therefore the cap and the long-run arc; it does **not** see
/// the `ScheduledSession` for the date, and this is the central design decision here.
///
/// §10 has the scorer resolve the scheduled session (step 1) and classify the actual
/// (step 2) so that step 3 can compare them — the rubric's "ran hard on an easy day"
/// band exists precisely to fire when they disagree. A classifier that could see the
/// prescription would resolve every ambiguous run toward it, because agreeing with the
/// plan is always the locally plausible answer. It would then be right about the easy
/// Tuesdays that went to plan and wrong about exactly the Thursdays §13 names as the
/// risk — and the disagreement signal the score is built on would quietly go to zero.
///
/// The calendar still earns its "load-bearing" description in §13, just in a narrower
/// role: it selects the plan version and the arc week, so the classifier is measuring
/// against *this* week's yardstick. It supplies the yardstick, not the answer.
///
/// ## What this deliberately does not read
///
/// **Heart-rate drift.** `DerivedMetricsCalculator` computes drift only when the
/// classification says it is meaningful, so a classifier consuming drift would close a
/// cycle with no correct resolution. Ingestion's flow is: compute metrics, classify from
/// them, recompute with the classification supplied. Passing either the first or the
/// second `DerivedMetrics` to this function yields the same classification, which is
/// what makes that flow well-defined rather than order-dependent, and
/// `WorkoutClassifierTests` pins it.
///
/// **Cadence, pace and energy.** Cadence is a form metric compared against a band, not
/// an intensity signal; grade-adjusted pace is absent indoors and on routeless runs, so
/// a rule reading it would classify the same effort differently depending on whether GPS
/// was available.
public enum WorkoutClassifier {
    /// - Parameters:
    ///   - workout: the captured record.
    ///   - metrics: the §9 metrics for *this* workout, computed against *this* plan.
    ///   - plan: the version in force on the workout's date (MAX-011 resolves it).
    ///   - timeZone: the zone the run happened in — required, never inferred, because
    ///     the arc week a late-evening run belongs to genuinely differs across zones.
    ///   - policy: see `WorkoutClassificationPolicy`; production uses `.default`.
    public static func classify(
        _ workout: Workout,
        metrics: DerivedMetrics,
        plan: Plan,
        timeZone: TimeZone,
        policy: WorkoutClassificationPolicy = .default
    ) throws -> WorkoutClassification {
        guard metrics.workoutID == workout.id else {
            throw DomainError.inconsistent(
                reason: "WorkoutClassifier: metrics belong to a different workout"
            )
        }
        // Time-above-cap and the zone splits are only interpretable against the cap they
        // were measured with. Classifying with another version's numbers would read a
        // different plan's discipline into this run.
        guard metrics.planVersion == plan.version else {
            throw DomainError.inconsistent(
                reason: "WorkoutClassifier: metrics were computed against plan version "
                    + "\(metrics.planVersion), not \(plan.version)"
            )
        }

        // The plan scores runs. Strength work and cross-training are out of scope for HR
        // scoring (§3), and `other` is the truthful label for them rather than a failure.
        //
        // `WorkoutClassification.lift` now exists and this line still does not use it,
        // deliberately. Answering `.lift` here would change what the classifier reports
        // for a session already in the store, and it would only half-fix the collapse
        // MAX-126 reported: a ride and a run whose heart-rate curve could not be read
        // would still share `.other` below. Separating those is a rework of what this
        // function's residual means, not a case added to its vocabulary.
        guard workout.activityType.isRun else { return .other }

        // Not a threshold — a degenerate value. There is no effort profile of an
        // interval of zero length.
        guard workout.durationSeconds > 0 else { return .other }

        if isFragment(workout, plan: plan, policy: policy) { return .other }

        let effort = EffortProfile(metrics: metrics)

        // Hardness first: a long run taken to threshold is a hard session, and treating
        // it as the week's long run would publish a drift number §9 calls meaningless.
        if let effort, effort.isHard(policy) { return .hard }

        if try isLongRun(workout, plan: plan, timeZone: timeZone, policy: policy) { return .long }

        // Easy is the residual *among runs with a readable heart-rate profile*: a run
        // that was not structured hard work and not the week's long run. It is
        // deliberately wide. §10.3's rubric scores an easy run held at 155 bpm in the
        // 55–74 band — that is an easy run performed badly, and it keeps its
        // classification so the rubric can say so. Promoting it to `hard` would fire the
        // "ran hard on an easy day" band instead and punish a discipline lapse as if it
        // were a different session altogether.
        if effort != nil { return .easy }

        // A run with no usable heart-rate curve, and no long-run claim to stand on.
        // Easy and hard are distinguished only by the HR profile, so there is nothing
        // here to distinguish them with; guessing "easy" would fabricate the discipline
        // the rubric is about to reward.
        return .other
    }

    /// The share of the heart-rate curve spent working, as fractions of the span the
    /// curve actually covers.
    ///
    /// Nil whenever there is no span to take fractions of: no series at all, or a
    /// single sample, which `HeartRateCurve` covers zero seconds of. Both are honest
    /// "no effort signal" cases, and neither is an effort of zero.
    private struct EffortProfile {
        private let zoneSplits: ZoneSplits
        private let coveredSeconds: Double

        init?(metrics: DerivedMetrics) {
            // `ZoneSplits` sums to the curve's covered span, which is also the span
            // time-above-cap was measured over — one denominator, so no two fractions
            // taken here can disagree about how long the run was.
            let covered = metrics.zoneSplits.totalSeconds
            guard metrics.hasHeartRateData, covered > 0 else { return nil }
            self.zoneSplits = metrics.zoneSplits
            self.coveredSeconds = covered
        }

        /// Fraction of covered time spent at or above `zone`.
        func timeFraction(atOrAbove zone: HeartRateZone) -> Double {
            zoneSplits.splits
                .filter { $0.zone >= zone }
                .reduce(0) { $0 + $1.seconds } / coveredSeconds
        }

        func isHard(_ policy: WorkoutClassificationPolicy) -> Bool {
            timeFraction(atOrAbove: policy.hardZoneFloor) >= policy.hardZoneTimeFraction
        }
    }

    /// Whether the distance covered reaches the plan's ask for the week's long run.
    ///
    /// Distance, not duration: the arc (§8 `longrun_arc`) is expressed in distance, and
    /// a slow long run and a quick one are the same session. A run the plan has no arc
    /// entry for — before the plan took effect, or past the end of the block — is not
    /// long by default; the plan has no opinion there and inventing one would put a
    /// hard-coded "long is 90 minutes" back into the code.
    private static func isLongRun(
        _ workout: Workout,
        plan: Plan,
        timeZone: TimeZone,
        policy: WorkoutClassificationPolicy
    ) throws -> Bool {
        guard let distanceMeters = workout.distanceMeters else { return false }
        let day = try workout.calendarDay(in: timeZone)
        guard let week = arcWeekIndex(for: day, effectiveFrom: plan.effectiveFrom),
              let prescribed = plan.longRunArc.distanceMeters(forWeek: week)
        else { return false }
        return distanceMeters >= prescribed * policy.longRunDistanceFraction
    }

    /// Whether the record is too short to be the session it would otherwise be read as.
    ///
    /// The yardstick is the shortest run the plan ever prescribes: a quarter of that is
    /// not a bad workout, it is a workout that did not happen — a mis-started session,
    /// or one HealthKit split in two. Scoring it against a scheduled 8 km would produce
    /// a confident, immutable, wrong number (D8).
    ///
    /// The test needs a distance on both sides. A workout with none, or a plan whose
    /// template prescribes none, gets no fragment test rather than a guessed one.
    private static func isFragment(
        _ workout: Workout,
        plan: Plan,
        policy: WorkoutClassificationPolicy
    ) -> Bool {
        guard policy.fragmentDistanceFraction > 0,
              let distanceMeters = workout.distanceMeters,
              let shortest = shortestPrescribedRunMeters(in: plan)
        else { return false }
        return distanceMeters < shortest * policy.fragmentDistanceFraction
    }

    /// The shortest distance the weekly template asks a run to be.
    ///
    /// Only run sessions count — rest carries no distance, and `other` days are
    /// cross-training the rubric does not reason about. The long-run arc is left out
    /// deliberately: it describes the longest run of each week, so folding it in could
    /// only raise the floor, and a floor derived from long runs would call a legitimate
    /// short recovery run a fragment.
    private static func shortestPrescribedRunMeters(in plan: Plan) -> Double? {
        plan.weeklyTemplate.entries
            .filter { $0.session.kind != .rest && $0.session.kind != .other }
            .compactMap { $0.session.distanceMeters }
            .min()
    }

    /// 1-based week index from the plan's effective date, matching `LongRunArc`'s
    /// documented indexing ("relative to the plan's `effectiveFrom`"). Nil for a day
    /// before the plan took effect — such a workout belongs to an earlier version, and
    /// pretending it is week 1 of this one would measure it against the wrong arc.
    static func arcWeekIndex(for day: CalendarDay, effectiveFrom: CalendarDay) -> Int? {
        let elapsedDays = serialDayNumber(day) - serialDayNumber(effectiveFrom)
        guard elapsedDays >= 0 else { return nil }
        return elapsedDays / 7 + 1
    }

    /// Days since a fixed epoch on the proleptic Gregorian calendar (Howard Hinnant's
    /// `days_from_civil`), so day differences are pure integer arithmetic.
    ///
    /// `Calendar` is avoided for the same reason `CalendarDay.weekday` avoids it: a
    /// locale- and zone-free function keeps classification deterministic. Only the
    /// *difference* between two of these is meaningful; the epoch itself is arbitrary.
    private static func serialDayNumber(_ day: CalendarDay) -> Int {
        // March-based years put the leap day at the end, which is what makes the
        // day-of-year formula below a single expression.
        let year = day.year - (day.month <= 2 ? 1 : 0)
        let era = year / 400 // CalendarDay.year is ≥ 1, so this never rounds toward zero wrongly.
        let yearOfEra = year - era * 400
        let shiftedMonth = (day.month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day.day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra
    }
}
