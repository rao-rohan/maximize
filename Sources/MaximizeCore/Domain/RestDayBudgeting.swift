import Foundation

/// Spends the weekly rest-day budget on missed scheduled sessions (D9, A6, A19).
///
/// PRD §14.1 left "manual or automatic" open; **A6 resolves it as automatic** — the
/// system converts the *least-costly* missed sessions each week into neutral rest, up to
/// the settings-defined budget, with no user action. This type is the one place that
/// decides what "least-costly" means; nowhere else should reimplement it.
///
/// ## What the budget is spent on: obligations, not days (A19, §6.4)
///
/// > *"The budget converts missed **obligations**, not missed days. N per week stays N
/// > conversions per week."*
///
/// A Tuesday prescribing a run and a lift offers the budget two things to forgive, and
/// forgiving one leaves the other still missed — because converting the whole day would
/// forgive the run the athlete also skipped, which is a budget that buys more than it was
/// sold for.
///
/// **On a week whose days each prescribe at most one session, obligations and days are
/// the same thing**, so the setting's meaning is unchanged for every week in the
/// athlete's history. That is the same no-op property §6.2 claims for the tallies, with
/// the same one exception: a day whose only recorded workout belongs to the *other*
/// discipline now leaves its obligation missed, where the old day-level "was anything
/// recorded" test counted it covered. See `PROJECT_TRACKER.md`'s MAX-134 note.
///
/// One thing this does change going forward: a week prescribing three runs and three
/// lifts has six obligations against the same budget of N. If the athlete chose their
/// `restDayBudget` against a five-run week it is now proportionally stingier. That is a
/// settings value and the fix is that the athlete changes it (§6.4 files the copy work).
///
/// ## The ordering: least-costly missed obligation first
///
/// A missed obligation is ranked by two properties, in this order, with the date and then
/// the slot as the deterministic floor:
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
///    `.rest` never appears here — `PlanDay.prescribedDisciplines` excludes a rested
///    slot before this type ever sees it, because you cannot miss what was not asked of
///    you. `.lift` sits between `.easy` and `.hard`; see `costTier`.
///
/// 2. **Adjacency to a scheduled rest day, in the same discipline's row** (§6.4). Within
///    the kind tier, a missed obligation that sits immediately before or after a day the
///    plan already rested *that same slot* is ranked less costly than one that doesn't.
///    The athlete's week already framed that session with recovery on one side, so
///    folding it into rest changes the shape of the week less than converting an isolated
///    one would. Read per row rather than per day because a lift on Thursday is framed by
///    Wednesday's and Friday's *lifting*, not by whether a run was scheduled around it.
///
/// 3. **Date, then slot, ascending — the tie-break floor.** If two missed obligations are
///    still tied after (1) and (2), the earlier date converts first, and the run slot
///    before the lift slot. This has no training rationale; it exists only so the same
///    week always produces the same answer, per the ticket's determinism requirement. Any
///    total order would do. The slot tie-break is unreachable in practice — the run slot
///    can only hold tiers 0, 1, 3, 4 and the lift slot only tier 2, so two obligations on
///    one date can never tie on kind — and it is written anyway so that the ordering is
///    total by construction rather than by a coincidence of the tier table.
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
/// One obligation the weekly budget forgave (D9/A6/A19) — which day, and which of that
/// day's two asks was folded into rest.
///
/// ## Why this is not a `RestDayOverride`
///
/// `RestDayOverride` is the **stored** record of PRD §8 `rest_day_override`, keyed by
/// day (`id: CalendarDay`), and it carries `convertedFromMissed` precisely so that a
/// rest day the athlete marked by hand can be told apart from one the budget converted.
/// This type is neither stored nor hand-authored: it is the return value of a pure
/// function, everything in it was converted from a miss by definition, and A19 makes its
/// key a (day, slot) pair rather than a day. Widening the stored record to match would
/// be a schema change bought for a value nothing persists — `TalliesCalculator` and
/// `ScoreCalendar` both recompute the budget rather than reading a stored override, and
/// nothing in the app writes one.
public struct ConvertedObligation: Hashable, Sendable {
    public let id: ObligationID

    /// Stamped from the caller's parameter, never the clock, so the same week always
    /// produces the same answer. No reader consults it today; it exists so that a caller
    /// which does persist a conversion has the provenance to hand.
    public let createdAt: Date

    public init(id: ObligationID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }

    public var date: CalendarDay { id.date }
    public var discipline: Discipline { id.discipline }
}

public enum RestDayBudgeting {
    /// Converts up to `budget.daysPerWeek` missed **obligations** per training week in
    /// `planDays`, least-costly first (see the type's documentation for the ordering).
    ///
    /// - Parameters:
    ///   - planDays: the resolved calendar entries under consideration, in any order.
    ///     A day the plan does not govern simply has no entry here (`PlanCalendar
    ///     .planDays(from:through:)` already omits those) and so is never a
    ///     candidate — the plan made no ask, so there is nothing to forgive.
    ///   - workoutDisciplines: for each calendar day, the disciplines that day actually
    ///     had a workout in (`ActivityType.discipline`). **Membership is per discipline,
    ///     not per day** (A19/§6.2): a lift is not an attempt at the run the plan asked
    ///     for, so it cannot make the run "not missed". Whether the workout scored well
    ///     is the scorer's concern, not this one's — showing up is the whole test.
    ///   - budget: N discretionary rest days per week, from `AppSettings
    ///     .restDayBudget` (PRD §8 `settings.rest_days_per_week`). `N = 0` converts
    ///     nothing. N stays a count of *conversions*, so a two-obligation day can consume
    ///     the whole of a budget of 1 and leave its other half missed.
    ///   - createdAt: stamped on every produced conversion. Supplied by the caller,
    ///     never read from the clock, so the result depends only on its inputs.
    ///   - outcomesUnknownFrom: the first day whose outcome is not yet known —
    ///     typically the athlete's today. Days on or after it are **never candidates**:
    ///     nothing has been missed there yet, so there is nothing to forgive. They stay
    ///     in `planDays` and still shape the week (a scheduled rest day ahead of today
    ///     still makes the session beside it cheaper to convert); they are only excluded
    ///     from the pool being spent on. Nil means every day in `planDays` is a
    ///     candidate — the behaviour before MAX-105, and correct for a caller reasoning
    ///     purely about the past.
    /// - Returns: one `ConvertedObligation` per forgiven obligation, ascending by date
    ///   then slot. Missed obligations beyond the budget are simply absent — they stay
    ///   red by omission.
    public static func convertingMissedObligations(
        planDays: [PlanDay],
        workoutDisciplines: [CalendarDay: Set<Discipline>],
        budget: RestDayBudget,
        createdAt: Date,
        outcomesUnknownFrom: CalendarDay? = nil
    ) throws -> [ConvertedObligation] {
        guard budget.daysPerWeek > 0 else { return [] }

        var byWeek: [CalendarDay: [PlanDay]] = [:]
        for planDay in planDays {
            let week = try planDay.date.startOfTrainingWeek()
            byWeek[week, default: []].append(planDay)
        }

        var conversions: [ConvertedObligation] = []
        for weekPlanDays in byWeek.values {
            conversions += try convertingMissedObligations(
                inOneWeek: weekPlanDays,
                workoutDisciplines: workoutDisciplines,
                budget: budget,
                createdAt: createdAt,
                outcomesUnknownFrom: outcomesUnknownFrom
            )
        }
        return conversions.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.discipline.slotOrder < rhs.discipline.slotOrder
        }
    }

    /// The per-week worker the entry point above groups into. `planDays` here is assumed
    /// to already be one training week's worth (or a slice of one) — grouping happens one
    /// level up.
    private static func convertingMissedObligations(
        inOneWeek planDays: [PlanDay],
        workoutDisciplines: [CalendarDay: Set<Discipline>],
        budget: RestDayBudget,
        createdAt: Date,
        outcomesUnknownFrom: CalendarDay?
    ) throws -> [ConvertedObligation] {
        func outcomeIsKnown(_ date: CalendarDay) -> Bool {
            guard let outcomesUnknownFrom else { return true }
            return date < outcomesUnknownFrom
        }

        var missed: [(id: ObligationID, kind: ScheduledSessionKind)] = []
        for planDay in planDays where outcomeIsKnown(planDay.date) {
            let performed = workoutDisciplines[planDay.date] ?? []
            for discipline in planDay.prescribedDisciplines where !performed.contains(discipline) {
                missed.append(
                    (
                        id: ObligationID(date: planDay.date, discipline: discipline),
                        kind: planDay.scheduledSession(for: discipline).kind
                    )
                )
            }
        }
        guard !missed.isEmpty else { return [] }

        // One rest row per discipline (§6.4): a missed lift is framed by the lift slot's
        // neighbours, not the run slot's. Built deliberately over the *whole* week handed
        // in, including days ahead of `outcomesUnknownFrom` — the week's shape is known
        // in advance, so a Thursday miss really is framed by Friday's scheduled rest
        // whether or not Friday has arrived. Only candidacy is bounded above; adjacency
        // is not.
        var scheduledRestDates: [Discipline: Set<CalendarDay>] = [:]
        for planDay in planDays {
            for discipline in Discipline.slotOrdered
            where planDay.scheduledSession(for: discipline).isRest {
                scheduledRestDates[discipline, default: []].insert(planDay.date)
            }
        }

        func isAdjacentToScheduledRest(_ id: ObligationID) -> Bool {
            let row = scheduledRestDates[id.discipline] ?? []
            let before = try? id.date.adding(days: -1)
            let after = try? id.date.adding(days: 1)
            return before.map(row.contains) == true || after.map(row.contains) == true
        }

        let leastCostlyFirst = missed.sorted { lhs, rhs in
            let lhsTier = costTier(lhs.kind)
            let rhsTier = costTier(rhs.kind)
            if lhsTier != rhsTier { return lhsTier < rhsTier }

            let lhsAdjacent = isAdjacentToScheduledRest(lhs.id)
            let rhsAdjacent = isAdjacentToScheduledRest(rhs.id)
            if lhsAdjacent != rhsAdjacent { return lhsAdjacent }

            if lhs.id.date != rhs.id.date { return lhs.id.date < rhs.id.date }
            return lhs.id.discipline.slotOrder < rhs.id.discipline.slotOrder
        }

        return leastCostlyFirst.prefix(budget.daysPerWeek).map {
            ConvertedObligation(id: $0.id, createdAt: createdAt)
        }
    }

    /// Ascending cost of forgiving a missed session of this kind — index 0 is the
    /// least costly to convert. `.rest` is unreachable in practice (`PlanDay
    /// .prescribedDisciplines` omits a rested slot before it can become a candidate); it
    /// is ranked last only so the switch stays exhaustive without a `default`, which
    /// would silently swallow a future `ScheduledSessionKind` case.
    ///
    /// **Only the order matters, never the numbers.** The tiers are compared, never
    /// summed or thresholded, so inserting a case renumbers the ones after it without
    /// changing a single conversion. What would rewrite the calendar's past is
    /// *reordering* the existing cases — A19 names that trap explicitly, and **MAX-134
    /// did not reorder them**: this function is byte-for-byte what MAX-128 left, and the
    /// obligation change above happens entirely in what is *offered* to the ranking.
    ///
    /// `.lift` sits between `.easy` and `.hard`: a missed lift costs the week more than
    /// a missed easy run, because it is a non-fungible stimulus rather than one of
    /// several interchangeable aerobic hours — the same argument the ranking already
    /// makes for `.hard` — and less than a missed quality session or long run. It is a
    /// training judgement, and LIFTING-SPEC §15 files it as the owner's to overrule.
    /// **It is reachable as of MAX-134**: the template grew its second slot in MAX-129
    /// and MAX-137 gave the lift slot a picker, so a plan that prescribes lifting now
    /// puts `.lift` obligations in front of this ranking. No *existing* week's
    /// conversions move, because every plan already on disk rests every lift slot.
    private static func costTier(_ kind: ScheduledSessionKind) -> Int {
        switch kind {
        case .other: return 0
        case .easy: return 1
        case .lift: return 2
        case .hard: return 3
        case .long: return 4
        case .rest: return 5
        }
    }
}
