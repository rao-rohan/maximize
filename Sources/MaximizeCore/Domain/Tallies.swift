import Foundation

/// One interval's contribution to `Tallies.effectiveDays` — a numerator/denominator
/// pair rather than a bare percentage, because a percentage with no visible
/// denominator hides exactly the question a training log exists to answer:
/// "effective out of how many chances."
///
/// ## The denominator counts **obligations**, not days (A19, LIFTING-SPEC §6.2)
///
/// A Tuesday prescribing a run and a lift is **two** chances, and meeting one of them
/// leaves the ratio at 1/2 rather than 1/1. Meeting one is not meeting the day: extending
/// the old day-level rule to two disciplines would have said a day with two obligations
/// is satisfied by meeting either one, which makes lifting free — skip every lift for
/// sixteen weeks and the rate never moves, as long as you ran.
///
/// **This type was `EffectiveDayTally` until MAX-134**, and the field names are
/// unchanged: what moved is the unit each of them counts. `Tallies.effectiveDays` still
/// spells "days" for now, and the athlete-facing caption is MAX-140's to correct — the
/// tile reads `4/5` on a run-only week today and would read `6/8` on a week with three
/// lifts, which is a visible change in a number the athlete knows and needs one line of
/// copy saying the denominator is sessions.
///
/// **Eligible** means the plan asked something of that slot on that day
/// (`PlanDay.prescribedDisciplines`) and the obligation was not folded into rest —
/// neither by the plan itself (a rested slot is never eligible; you cannot miss what was
/// not asked of you) nor by MAX-016's automatic weekly conversion (an obligation the
/// budget converted is neither a hit nor a miss — see `TalliesCalculator` for why it is
/// dropped from both sides of this ratio rather than merely spared the "ineffective"
/// label).
///
/// A day the plan does not govern at all (`PlanCalendar` returns nil before the first
/// plan version) contributes nothing to either side: no ask, nothing to be effective or
/// ineffective *at*.
public struct EffectiveObligationTally: Hashable, Sendable {
    public let effectiveCount: Int
    public let eligibleCount: Int

    public init(effectiveCount: Int, eligibleCount: Int) throws {
        try Validate.nonNegative(Double(effectiveCount), "EffectiveObligationTally.effectiveCount")
        try Validate.nonNegative(Double(eligibleCount), "EffectiveObligationTally.eligibleCount")
        guard effectiveCount <= eligibleCount else {
            throw DomainError.inconsistent(
                reason: "EffectiveObligationTally.effectiveCount (\(effectiveCount)) exceeds "
                    + "eligibleCount (\(eligibleCount))"
            )
        }
        self.effectiveCount = effectiveCount
        self.eligibleCount = eligibleCount
    }

    /// Nil rather than `0` when nothing was eligible — an interval with no plan, or one
    /// spent entirely on rest, has no rate to report, and reporting zero would read as
    /// "you failed every session" instead of the true "there was nothing to judge."
    public var rate: Double? {
        eligibleCount > 0 ? Double(effectiveCount) / Double(eligibleCount) : nil
    }
}

/// The Monday-first training week containing the day a `Tallies` was computed as of,
/// and which arc week (D1's progression) that day falls in under the plan governing
/// it.
///
/// Bounds are always defined — week arithmetic needs no plan. `arcWeekIndex` is nil
/// exactly when no plan governs the day (a fresh install, or a day before the first
/// plan version): a real state, not a defect.
public struct TrainingWeek: Hashable, Sendable {
    /// Monday.
    public let start: CalendarDay
    /// Sunday.
    public let end: CalendarDay
    public let arcWeekIndex: Int?

    public init(start: CalendarDay, end: CalendarDay, arcWeekIndex: Int?) throws {
        guard start <= end else {
            throw DomainError.inconsistent(
                reason: "TrainingWeek.start (\(start)) must not be after end (\(end))"
            )
        }
        self.start = start
        self.end = end
        self.arcWeekIndex = arcWeekIndex
    }
}

/// The five §8 / FR-3.4 rollups — workout-days, effective-days, average score,
/// streak, current week — computed on read from stored records, never from a counter
/// that could drift from them.
///
/// See `TalliesCalculator` for how each is derived and for the streak definition the
/// PRD leaves open; this type only carries the answers and the interval they cover.
public struct Tallies: Hashable, Sendable {
    public let from: CalendarDay
    public let through: CalendarDay

    /// Distinct calendar days in `from...through` with at least one recorded
    /// workout, scored or not — "did you show up," independent of how it graded.
    public let workoutDays: Int

    /// See `EffectiveObligationTally` — which, since A19, counts the plan's *obligations*
    /// rather than its days. The property keeps the name the dashboard and the fact sheet
    /// already read; correcting the athlete-facing wording is MAX-140's.
    public let effectiveDays: EffectiveObligationTally

    /// Mean of `ScoreLedger.effectiveValue` — the manual correction where one exists,
    /// else the auto-score (§8) — over every *scored* workout in the interval **that
    /// is not labelled miscategorised** (A21, MAX-160). Nil when nothing eligible in
    /// the interval has been scored yet, which is an honest "no data yet," not a
    /// zero — see `averageScoreExcludedMiscategorisedCount` for the state where that
    /// nil is instead every score having been excluded.
    ///
    /// **Why a labelled score is skipped rather than averaged in.** MAX-143 marks a
    /// score written against the wrong discipline's ask — a lift judged by the
    /// running rubric before the plan told the two apart — because the model was
    /// handed a category error, not evidence about the athlete's training. The
    /// average answers "how am I training"; a score answering the wrong question is
    /// noise from a bug, not a data point about the athlete, so it is left out here
    /// exactly as it is already left out of PRD §2's scorer-quality signal. The score
    /// itself is untouched (D8) and still visible on the workout with its rationale
    /// and `MiscategorisedScoreCopy`'s explanation — only this aggregate's read of it
    /// changes.
    public let averageScore: Double?

    /// How many scored workouts in the interval were left out of `averageScore`
    /// because their `ScoreLedger.isMiscategorised` (MAX-160). Zero whenever nothing
    /// in the interval carries a label — in particular, always zero for a
    /// single-discipline history, which is what keeps `averageScore` byte-identical
    /// to its pre-MAX-160 value there.
    ///
    /// Carried as a count, not just a bool, so a caption can say *how many* points
    /// were withheld rather than only that some were — the same reasoning
    /// `EffectiveObligationTally` gives for a numerator/denominator pair over a bare
    /// rate: a reader who can see the exclusion can also judge how much it might
    /// matter.
    public let averageScoreExcludedMiscategorisedCount: Int

    /// See `TalliesCalculator` for the exact definition and why converted rest days
    /// and unscored workouts neither extend nor break it.
    public let currentStreak: Int

    public let currentWeek: TrainingWeek

    public init(
        from: CalendarDay,
        through: CalendarDay,
        workoutDays: Int,
        effectiveDays: EffectiveObligationTally,
        averageScore: Double?,
        averageScoreExcludedMiscategorisedCount: Int = 0,
        currentStreak: Int,
        currentWeek: TrainingWeek
    ) throws {
        guard from <= through else {
            throw DomainError.inconsistent(
                reason: "Tallies.from (\(from)) must not be after through (\(through))"
            )
        }
        try Validate.nonNegative(Double(workoutDays), "Tallies.workoutDays")
        try Validate.nonNegative(Double(currentStreak), "Tallies.currentStreak")
        try Validate.nonNegative(
            Double(averageScoreExcludedMiscategorisedCount),
            "Tallies.averageScoreExcludedMiscategorisedCount"
        )
        if let averageScore {
            try Validate.finite(averageScore, "Tallies.averageScore")
        }
        self.from = from
        self.through = through
        self.workoutDays = workoutDays
        self.effectiveDays = effectiveDays
        self.averageScore = averageScore
        self.averageScoreExcludedMiscategorisedCount = averageScoreExcludedMiscategorisedCount
        self.currentStreak = currentStreak
        self.currentWeek = currentWeek
    }
}
