import Foundation

/// Spends the weekly rest-day budget on missed scheduled sessions (D9, A6).
///
/// PRD §14.1 left "manual or automatic" open; **A6 resolves it as automatic** — the
/// system converts the *least-costly* missed days each week into neutral rest days,
/// up to the settings-defined budget, with no user action. This type is the one place
/// that decides what "least-costly" means; nowhere else should reimplement it.
///
/// ## The ordering: least-costly missed day first
///
/// A missed day is ranked by two properties, in this order, with the date itself as
/// the deterministic floor:
///
/// 1. **What was missed.** The scheduled session's *kind* stands in for how much the
///    week's training plan actually loses when the day goes unexecuted, ranked from
///    least to most costly:
///
///    - `.other` — cross-training / mobility. Outside the run rubric entirely (§10.2);
///      skipping it doesn't touch the HR cap, cadence target, or the long-run arc.
///    - `.easy` — the lowest-stimulus run kind. One missed easy day barely dents
///      aerobic volume for the week.
///    - `.hard` — a quality session (intervals/threshold). Missing it forfeits a
///      specific, non-fungible stimulus, so it outranks `.easy` in cost.
///    - `.long` — the week's primary stimulus and the one the arc (D1) is built
///      around. The most costly day to lose, and the PRD's own example ("an easy day
///      missed costs less than a long run missed").
///
///    `.rest` never appears here — `PlanDay.canBeMissed` excludes it before this type
///    ever sees the day, because you cannot miss a day nothing was asked of.
///
/// 2. **Adjacency to a scheduled rest day.** Within the kind tier, a missed day that
///    sits immediately before or after a day the plan already scheduled as rest is
///    ranked less costly than one that doesn't. The athlete's week already framed that
///    day with recovery on one side, so folding it into rest changes the shape of the
///    week less than converting an isolated day would.
///
/// 3. **Date, ascending — the tie-break floor.** If two missed days are still tied
///    after (1) and (2), the earlier date converts first. This has no training
///    rationale; it exists only so the same week always produces the same answer, per
///    the ticket's determinism requirement. Any total order would do; date is the
///    obvious one, since it requires no further judgment about the week's shape.
///
/// **Rejected:** weighting by scheduled *distance* instead of kind. Distance is
/// optional data, `.other` sessions frequently carry none at all, and "18 km beats
/// 6 km" already falls out of the kind ranking (long > easy) without needing the
/// number. Kind is the coarser, more predictable signal — and per the ticket's own
/// steer, a rule the user can predict beats one that is marginally more optimal.
///
/// ## Weeks and partial weeks
///
/// The budget is spent **per Monday-first training week** (`CalendarDay
/// .startOfTrainingWeek()`), computed independently for every week represented in
/// `planDays`. A range that spans a week boundary therefore cannot double-spend: each
/// side of the boundary is its own group with its own budget.
///
/// **A partial week — at the edge of the queried range, or because the plan's
/// `effectiveFrom` starts mid-week — still gets the full weekly budget, not a
/// prorated share.** The budget is a rate ("up to N discretionary days *per week*"),
/// not a pool spread evenly across seven days; a user who queries a three-day slice,
/// or whose plan started on a Thursday, has not been granted a smaller allowance for
/// it. The alternative — scaling `N` by the fraction of the week present — would make
/// the same day convert or not depending on what range happened to be requested,
/// which is the opposite of reproducible.
///
/// One consequence follows from that, and is the caller's responsibility rather than
/// this type's: because only the days actually present in `planDays` are visible
/// here, the same missed day can be evaluated against a different candidate pool (and
/// so a different outcome) if it is queried inside two different partial ranges. The
/// fix is a calling convention, not a rule this pure function could enforce — the
/// dashboard should always resolve full weeks, never split one across two calls.
///
/// ## Days that have not happened yet (MAX-105)
///
/// A missed day is a day the plan asked something of and the athlete did not deliver.
/// **A day still ahead of the athlete is neither** — and until `outcomesUnknownFrom`
/// existed, every one of them was a candidate for forgiveness. In the current week that
/// is not a cosmetic problem: the budget is a small integer, so converting Friday and
/// Saturday before they have arrived leaves Tuesday's genuine miss with no allowance
/// left and showing red, and the same week silently rearranges which day it forgave as
/// the week goes on. Callers that know what day it is should say so; the parameter
/// defaults to nil only for a caller reasoning purely about the past, which genuinely
/// has no "today" to supply. `ScoreCalendar` and `TalliesCalculator` (MAX-105,
/// MAX-110) both pass it now — the seam this note used to describe as open is closed.
public enum RestDayBudgeting {
    /// Converts up to `budget.daysPerWeek` missed days per training week in `planDays`
    /// into `RestDayOverride`s, least-costly first (see the type's documentation for
    /// the ordering).
    ///
    /// - Parameters:
    ///   - planDays: the resolved calendar entries under consideration, in any order.
    ///     A day the plan does not govern simply has no entry here (`PlanCalendar
    ///     .planDays(from:through:)` already omits those) and so is never a
    ///     candidate — the plan made no ask, so there is nothing to forgive.
    ///   - workoutDays: every calendar day that had at least one workout recorded.
    ///     Membership alone is what makes a day "not missed"; whether that workout
    ///     scored well is the scorer's concern, not this one's.
    ///   - budget: N discretionary rest days per week, from `AppSettings
    ///     .restDayBudget` (PRD §8 `settings.rest_days_per_week`). `N = 0` converts
    ///     nothing.
    ///   - createdAt: stamped on every produced override. Supplied by the caller,
    ///     never read from the clock, so the result depends only on its inputs.
    ///   - outcomesUnknownFrom: the first day whose outcome is not yet known —
    ///     typically the athlete's today. Days on or after it are **never candidates**:
    ///     nothing has been missed there yet, so there is nothing to forgive. They stay
    ///     in `planDays` and still shape the week (a scheduled rest day ahead of today
    ///     still makes the day beside it cheaper to convert); they are only excluded
    ///     from the pool being spent on. Nil means every day in `planDays` is a
    ///     candidate — the behaviour before MAX-105, and correct for a caller reasoning
    ///     purely about the past.
    /// - Returns: one `RestDayOverride` per converted day, ascending by date. Missed
    ///   days beyond the budget are simply absent — they stay red by omission.
    public static func convertingMissedDays(
        planDays: [PlanDay],
        workoutDays: Set<CalendarDay>,
        budget: RestDayBudget,
        createdAt: Date,
        outcomesUnknownFrom: CalendarDay? = nil
    ) throws -> [RestDayOverride] {
        guard budget.daysPerWeek > 0 else { return [] }

        var byWeek: [CalendarDay: [PlanDay]] = [:]
        for planDay in planDays {
            let week = try planDay.date.startOfTrainingWeek()
            byWeek[week, default: []].append(planDay)
        }

        var overrides: [RestDayOverride] = []
        for weekPlanDays in byWeek.values {
            overrides += try convertingMissedDays(
                inOneWeek: weekPlanDays,
                workoutDays: workoutDays,
                budget: budget,
                createdAt: createdAt,
                outcomesUnknownFrom: outcomesUnknownFrom
            )
        }
        return overrides.sorted { $0.date < $1.date }
    }

    /// The per-week worker `convertingMissedDays(planDays:workoutDays:budget:createdAt:)`
    /// groups into. `planDays` here is assumed to already be one training week's worth
    /// (or a slice of one) — grouping happens one level up.
    private static func convertingMissedDays(
        inOneWeek planDays: [PlanDay],
        workoutDays: Set<CalendarDay>,
        budget: RestDayBudget,
        createdAt: Date,
        outcomesUnknownFrom: CalendarDay?
    ) throws -> [RestDayOverride] {
        func outcomeIsKnown(_ date: CalendarDay) -> Bool {
            guard let outcomesUnknownFrom else { return true }
            return date < outcomesUnknownFrom
        }

        let missed = planDays.filter {
            $0.canBeMissed && !workoutDays.contains($0.date) && outcomeIsKnown($0.date)
        }
        guard !missed.isEmpty else { return [] }

        // Deliberately over the *whole* week handed in, including days ahead of
        // `outcomesUnknownFrom`: the week's shape is known in advance, so a Thursday
        // miss really is framed by Friday's scheduled rest whether or not Friday has
        // arrived. Only candidacy is bounded above; adjacency is not.
        let scheduledRestDates = Set(planDays.filter(\.scheduledSession.isRest).map(\.date))

        func isAdjacentToScheduledRest(_ date: CalendarDay) -> Bool {
            let before = try? date.adding(days: -1)
            let after = try? date.adding(days: 1)
            return before.map(scheduledRestDates.contains) == true
                || after.map(scheduledRestDates.contains) == true
        }

        let leastCostlyFirst = missed.sorted { lhs, rhs in
            let lhsTier = costTier(lhs.scheduledSession.kind)
            let rhsTier = costTier(rhs.scheduledSession.kind)
            if lhsTier != rhsTier { return lhsTier < rhsTier }

            let lhsAdjacent = isAdjacentToScheduledRest(lhs.date)
            let rhsAdjacent = isAdjacentToScheduledRest(rhs.date)
            if lhsAdjacent != rhsAdjacent { return lhsAdjacent }

            return lhs.date < rhs.date
        }

        return leastCostlyFirst.prefix(budget.daysPerWeek).map {
            RestDayOverride(date: $0.date, convertedFromMissed: true, createdAt: createdAt)
        }
    }

    /// Ascending cost of forgiving a missed session of this kind — index 0 is the
    /// least costly to convert. `.rest` is unreachable in practice (`PlanDay
    /// .canBeMissed` excludes it before a day ever reaches this function); it is
    /// ranked last only so the switch stays exhaustive without a `default`, which
    /// would silently swallow a future `ScheduledSessionKind` case.
    private static func costTier(_ kind: ScheduledSessionKind) -> Int {
        switch kind {
        case .other: return 0
        case .easy: return 1
        case .hard: return 2
        case .long: return 3
        case .rest: return 4
        }
    }
}
