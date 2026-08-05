import Foundation

/// What one day on the score-colored calendar (D4, FR-3.2) actually is.
///
/// ## Why six cases, not "good / bad / empty"
///
/// The PRD treats these as different facts, and collapsing them would throw away
/// information the athlete can act on:
///
/// - `.scored` — a workout happened and was judged. The one state color is *for*.
/// - `.awaitingScore` — a workout happened but nothing has judged it yet (§7.0's
///   capture-to-score gap, or no API key stored). Not a verdict either way — showing
///   it as ineffective would be lying about a score that has not been reached, and
///   showing it as effective would be a promise nobody made.
/// - `.missed` — the plan asked for something and nothing happened, and the weekly
///   rest-day budget did not stretch to cover it (D9). A real failure to execute.
/// - `.convertedRest` — the same missed ask, but MAX-016's automatic weekly-budget
///   conversion (A6) folded it into rest. Distinct from a scheduled rest day: this
///   one is a forgiven miss, and A6's own trade-off note ("the calendar may read as
///   too generous") is exactly why the distinction has to survive to the view rather
///   than collapsing into a fourth color.
/// - `.scheduledRest` — the plan's own ask for the day *was* rest. Nothing was
///   forgiven because nothing was owed.
/// - `.unplanned` — no plan version governs the day at all: before the athlete's
///   first plan, or a queried range that reaches earlier than every version.
///
/// ## Why color only ever comes from `.scored`
///
/// `ScoreBand` has no `init(score:)` (D1) — only the scorer, reading the plan version
/// in force when a workout was judged, may turn a number into a band. That rule holds
/// here too: this type carries `ScoreBand` **only** on `.scored`, and only the value
/// already stored on the workout's `Score` (`ScoreLedger.automatic.band`), never a
/// band recomputed from a manual correction. `WorkoutVerdict` (FR-1.1) draws the same
/// line for the same reason — see its own documentation. A manual annotation changes
/// what tallies count (D8), not what the calendar colors; the auto-score is the
/// permanent record and the divergence between the two is the scorer-quality signal
/// PRD §2 wants preserved, not resolved away on a calendar cell.
public enum ScoreCalendarDayState: Hashable, Sendable {
    /// At least one workout happened on this day and has an auto-score. When more
    /// than one workout landed on the same day, the *best* band wins and its
    /// activity type is what is shown — see `ScoreCalendar.resolve` for the ranking
    /// and why a double-workout day is not penalized for its worse session.
    case scored(band: ScoreBand, activityType: ActivityType)

    /// A workout was recorded but has no score yet.
    case awaitingScore(activityType: ActivityType)

    /// The plan asked for `scheduledKind` (never `.rest` — see `PlanDay.canBeMissed`)
    /// and nothing was recorded; the weekly budget did not cover it.
    case missed(scheduledKind: ScheduledSessionKind)

    /// The plan asked for `scheduledKind` and nothing was recorded, but MAX-016's
    /// automatic conversion (D9/A6) spent the weekly budget on this day.
    case convertedRest(scheduledKind: ScheduledSessionKind)

    /// The plan's own ask for the day was rest.
    case scheduledRest

    /// No plan version governs this day.
    case unplanned
}

/// One resolved calendar cell: a day, and the state it is in.
public struct ScoreCalendarDay: Hashable, Sendable, Identifiable {
    public var id: CalendarDay { date }

    public let date: CalendarDay
    public let state: ScoreCalendarDayState

    public init(date: CalendarDay, state: ScoreCalendarDayState) {
        self.date = date
        self.state = state
    }
}

/// Resolves `ScoreCalendarDay`s for a range (FR-3.2, D4, D9, A6).
///
/// ## Why this reads the same inputs `TalliesCalculator` does, the same way
///
/// The calendar and the summary tiles (MAX-063) must never disagree about which days
/// converted to rest — two notions of the same weekly budget is exactly the D2 drift
/// CLAUDE.md warns about, just wearing a calendar's clothes instead of a chart's. So
/// this type does not read a stored `RestDayOverride`; like `TalliesCalculator`, it
/// calls `RestDayBudgeting.convertingMissedDays` itself, over the same widened,
/// whole-week range, and both types are pure functions of the same records. A caller
/// already assembling a `TalliesInput` for the same interval already has everything
/// `resolve` below needs.
///
/// ## The C1 obligation this carries forward
///
/// `RestDayBudgeting` must never see a partial training week (C1, `PROJECT_TRACKER
/// .md`): ranking a missed day is relative to the other misses *in its week*, so a
/// slice sees a different answer than the whole week would. `TalliesInput` documents
/// the resulting requirement on `workouts`, and it applies unchanged here: `workouts`
/// must cover every day in the Monday-first weeks touching `from...through`, not
/// merely `from...through` itself, or an edge day's miss can be misjudged. See
/// `TalliesInput`'s own documentation for the full reasoning; `resolve` below widens
/// its *plan-day* query internally the same way `TalliesCalculator` does, but it has
/// no way to widen `workouts` for a caller that supplied too narrow a set.
public enum ScoreCalendar {
    /// Discarded by every reader — `RestDayBudgeting` only stamps this on the
    /// `RestDayOverride` values it returns, and nothing here reads it back. A fixed
    /// constant, never `Date()`, keeps `resolve` a pure function of its arguments,
    /// mirroring `TalliesCalculator.restDayBudgetingStamp`.
    private static let restDayBudgetingStamp = Date(timeIntervalSince1970: 0)

    /// - Parameters:
    ///   - from: inclusive lower bound — typically `TrendInterval.from`.
    ///   - through: inclusive upper bound — typically `TrendInterval.through`.
    ///   - timeZone: the athlete's zone, used only to bucket `workouts` by the day
    ///     they started on (`Workout.calendarDay(in:)`). Never read as `.current`
    ///     here — the caller supplies it, the same way `TrendInterval
    ///     .dateInterval(in:)` and `TalliesInput` both demand it rather than assume
    ///     one.
    ///   - workouts: see the type's documentation for the range this must cover —
    ///     wider than `from...through` whenever the interval does not already align
    ///     to Monday-first week boundaries.
    ///   - scoreLedgers: keyed by workout id, as `TalliesInput.scoreLedgers`. A
    ///     workout with no entry is unscored, not a zero.
    ///   - planCalendar: nil before any plan has been authored — every day resolves
    ///     to `.unplanned`.
    ///   - restDayBudget: D9's N discretionary rest days per week.
    /// - Returns: one `ScoreCalendarDay` per day in `from...through`, ascending.
    public static func resolve(
        from: CalendarDay,
        through: CalendarDay,
        timeZone: TimeZone,
        workouts: [Workout],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget
    ) throws -> [ScoreCalendarDay] {
        guard from <= through else {
            throw DomainError.inconsistent(
                reason: "ScoreCalendar.resolve: from (\(from)) must not be after through (\(through))"
            )
        }

        var workoutsByDay: [CalendarDay: [Workout]] = [:]
        for workout in workouts {
            let day = try workout.calendarDay(in: timeZone)
            workoutsByDay[day, default: []].append(workout)
        }

        let (planDaysInRange, convertedDates) = try resolveRestDayConversions(
            from: from,
            through: through,
            workoutsByDay: workoutsByDay,
            planCalendar: planCalendar,
            restDayBudget: restDayBudget
        )

        return try CalendarDay.days(from: from, through: through).map { day in
            let state = dayState(
                dayWorkouts: workoutsByDay[day] ?? [],
                planDay: planDaysInRange[day],
                isConverted: convertedDates.contains(day),
                scoreLedgers: scoreLedgers
            )
            return ScoreCalendarDay(date: day, state: state)
        }
    }

    // MARK: - C1: rest-day conversion over whole weeks (mirrors TalliesCalculator)

    private static func resolveRestDayConversions(
        from: CalendarDay,
        through: CalendarDay,
        workoutsByDay: [CalendarDay: [Workout]],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget
    ) throws -> (planDaysInRange: [CalendarDay: PlanDay], convertedDates: Set<CalendarDay>) {
        guard let planCalendar else { return ([:], []) }

        let expandedStart = try from.startOfTrainingWeek()
        let expandedEnd = try through.startOfTrainingWeek().adding(days: 6)
        let expandedPlanDays = try planCalendar.planDays(from: expandedStart, through: expandedEnd)

        var planDaysInRange: [CalendarDay: PlanDay] = [:]
        for planDay in expandedPlanDays where planDay.date >= from && planDay.date <= through {
            planDaysInRange[planDay.date] = planDay
        }

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: expandedPlanDays,
            workoutDays: Set(workoutsByDay.keys),
            budget: restDayBudget,
            createdAt: restDayBudgetingStamp
        )
        return (planDaysInRange, Set(overrides.map(\.date)))
    }

    // MARK: - Per-day state

    private static func dayState(
        dayWorkouts: [Workout],
        planDay: PlanDay?,
        isConverted: Bool,
        scoreLedgers: [UUID: ScoreLedger]
    ) -> ScoreCalendarDayState {
        let scoredPairs = dayWorkouts.compactMap { workout in
            scoreLedgers[workout.id].map { (workout, $0) }
        }

        // A workout that actually happened always outranks the plan's ask for the
        // day — D4 colors by what was done, not by what was scheduled. This applies
        // even on a day the plan scheduled as rest: an extra session still gets
        // judged on its own merits, and a rest day the athlete ran through is a fact
        // worth surfacing honestly rather than hiding behind "scheduled rest".
        if let best = bestScoredPair(scoredPairs) {
            return .scored(band: best.1.automatic.band, activityType: best.0.activityType)
        }
        if let earliestUnscored = dayWorkouts.min(by: { $0.start < $1.start }) {
            return .awaitingScore(activityType: earliestUnscored.activityType)
        }

        guard let planDay else { return .unplanned }
        guard planDay.canBeMissed else { return .scheduledRest }
        return isConverted
            ? .convertedRest(scheduledKind: planDay.scheduledSession.kind)
            : .missed(scheduledKind: planDay.scheduledSession.kind)
    }

    /// The best-banded workout of the day, deterministically. "Best" mirrors
    /// `TalliesCalculator.effectiveDayTally`'s own "contains effective" generosity: a
    /// day with two workouts is judged by its best session, not dragged down by a
    /// warmup or a second, worse effort. Ties (same band) break on earliest start, so
    /// the result never depends on `dayWorkouts`' input order.
    private static func bestScoredPair(_ pairs: [(Workout, ScoreLedger)]) -> (Workout, ScoreLedger)? {
        pairs.min { lhs, rhs in
            let lhsRank = bandRank(lhs.1.automatic.band)
            let rhsRank = bandRank(rhs.1.automatic.band)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.0.start < rhs.0.start
        }
    }

    /// Ascending cost — index 0 is the best band. Local to this type: nothing else
    /// needs an ordering over `ScoreBand`, and adding `Comparable` to the type itself
    /// would suggest a general-purpose ordering that PRD D4 never asked for.
    private static func bandRank(_ band: ScoreBand) -> Int {
        switch band {
        case .effective: return 0
        case .marginal: return 1
        case .ineffective: return 2
        }
    }
}
