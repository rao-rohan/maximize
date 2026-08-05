import Foundation

/// Everything `TalliesCalculator.compute` needs, bundled so the one calling
/// convention it depends on is stated once instead of hoped for at every call site.
///
/// ## The obligation `workouts` carries (this extends C1 to `Tallies`)
///
/// MAX-016's `RestDayBudgeting` must never see a partial training week (C1, tracked in
/// `PROJECT_TRACKER.md`) — ranking a missed day is relative to the other misses *in
/// its week*, so a slice sees a different answer than the whole week would.
/// `TalliesCalculator` honours that internally: it always asks `planCalendar` for the
/// whole Monday-first weeks touching `from...through`, even when the caller's own
/// interval starts or ends mid-week. But `planCalendar` only supplies the plan's
/// *ask* — whether those extra edge days were actually missed depends on `workouts`,
/// which this type has no way to widen on its own.
///
/// **So `workouts` must cover every day in the Monday-first weeks touching
/// `from...through`, not merely `from...through` itself.** A caller that supplies only
/// the queried interval's workouts, when that interval does not already start on a
/// Monday and end on a Sunday, will silently misjudge misses at the edges — an edge
/// day whose workout fell outside the supplied slice looks identical to one that was
/// never recorded. `WorkoutRepository.workouts(startingIn:)` makes satisfying this a
/// matter of widening the query, not writing new code: fetch from
/// `from.startOfTrainingWeek()` through `through.startOfTrainingWeek().adding(days: 6)`.
///
/// `workoutDays` and `averageScore` are unaffected by this — they only ever look
/// inside `from...through`. The obligation is purely about feeding `RestDayBudgeting`
/// a whole week every time it runs.
public struct TalliesInput: Sendable {
    public let from: CalendarDay
    public let through: CalendarDay
    public let timeZone: TimeZone

    /// The athlete's current day, in `timeZone`. **An input, never a clock read**
    /// (MAX-110) — the same discipline `ScoreCalendar.resolve`'s own `today` parameter
    /// is held to, and for the same reason: a calculator that called `Date()` would be
    /// untestable by construction, and would silently disagree with the calendar cell
    /// beside it the moment the two read the clock at different instants.
    ///
    /// Three things depend on it:
    ///
    /// - `EffectiveObligationTally` never counts a day on or after `today` — see
    ///   `TalliesCalculator.effectiveObligationTally`. A day whose outcome is not yet in
    ///   cannot be judged, so **none of its obligations** reach either side of the ratio,
    ///   strictly: today itself counts as not yet decided, and a session scheduled for
    ///   this evening has not been skipped.
    /// - `RestDayBudgeting`'s weekly allowance is never spent on a day on or after
    ///   `today` — see `TalliesCalculator.resolveRestDayConversions`, which threads
    ///   this through as `outcomesUnknownFrom` (C3). Same strict boundary, same reason.
    /// - `Tallies.currentStreak`'s walk may reach `today` itself, unlike the two rules
    ///   above — a **miss** cannot be judged before the day ends, but a **hit** already
    ///   performed today is a decided fact the moment it happens. See
    ///   `TalliesCalculator`'s "Where the walk starts" documentation for the asymmetry
    ///   this requires and why it deliberately does not match the strict boundary the
    ///   other two rules use.
    public let today: CalendarDay

    /// See the type's documentation for the range this must cover — it is wider than
    /// `from...through` whenever the interval does not already align to week
    /// boundaries.
    public let workouts: [Workout]

    /// Keyed by `Workout.id`. A workout with no entry here is unscored — a first-class,
    /// often-indefinite state (no API key stored, no network reachable), never treated
    /// as a miss and never treated as a zero.
    public let scoreLedgers: [UUID: ScoreLedger]

    /// Nil before the first plan version is authored — a real state, not "no data."
    public let planCalendar: PlanCalendar?

    public let restDayBudget: RestDayBudget

    public init(
        from: CalendarDay,
        through: CalendarDay,
        timeZone: TimeZone,
        today: CalendarDay,
        workouts: [Workout],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        planCalendar: PlanCalendar?,
        restDayBudget: RestDayBudget
    ) throws {
        guard from <= through else {
            throw DomainError.inconsistent(
                reason: "TalliesInput.from (\(from)) must not be after through (\(through))"
            )
        }
        for (workoutID, ledger) in scoreLedgers {
            guard ledger.automatic.workoutID == workoutID else {
                throw DomainError.inconsistent(
                    reason: "TalliesInput.scoreLedgers[\(workoutID)] carries a ledger for a "
                        + "different workout (\(ledger.automatic.workoutID))"
                )
            }
        }
        self.from = from
        self.through = through
        self.timeZone = timeZone
        self.today = today
        self.workouts = workouts
        self.scoreLedgers = scoreLedgers
        self.planCalendar = planCalendar
        self.restDayBudget = restDayBudget
    }
}

/// Computes `Tallies` (FR-3.4, §8) from stored records — never from a counter that
/// could drift from them.
///
/// ## The unit of account is the obligation, not the day (A19, LIFTING-SPEC §6)
///
/// A Tuesday prescribing a run **and** a lift is two obligations, and meeting one is not
/// meeting the day. Every figure below that counts the plan's asks — the effective ratio
/// and the streak — resolves each obligation independently through `DayObligationResolver`,
/// against the workouts of its own discipline, and rolls the day up from those.
///
/// **Two attempts at *one* obligation still resolve generously**, and that is a different
/// question with a different answer: a warm-up jog plus a real run is one ask attempted
/// twice, judged best-of, exactly as before. See `DayObligations.streakContribution` for
/// why the two rules point in opposite directions on purpose.
///
/// `workoutDays` and `averageScore` are untouched by this: one asks whether the athlete
/// showed up, the other averages the scores that exist. Neither counts the plan's asks,
/// so neither has a unit to change.
///
/// ## The streak definition (the PRD leaves this open; this is the decision, and why)
///
/// Walking backward day by day from the walk's **start day** (defined below, not
/// always `through`), each day is rolled up from its obligations (§6.3: any obligation
/// missed-or-below-threshold breaks it; every obligation met extends it) into one of
/// four things:
///
/// 1. **Neutral — no ask.** No plan governs the day, or the plan's ask *was* rest on
///    both slots (scheduled, or converted from a miss by MAX-016's weekly budget). The
///    streak neither grows nor breaks; the walk simply steps to the day before. **This is
///    the load-bearing choice**: a streak that reset on a plan's own prescribed rest
///    day would punish the athlete for following the plan, which is worse than
///    useless — it is hostile to the thing the plan is for.
/// 2. **Neutral — not yet judged.** A workout happened but nothing has scored it yet
///    (no API key stored, or scoring hasn't caught up). Treated the same as a rest
///    day: the athlete did not skip anything, so nothing here should cost them a
///    streak they may well still be building — but there is also no verdict yet to
///    count *for* them. The walk continues without extending the streak.
/// 3. **Extends the streak.** A day with at least one obligation, **every** one of which
///    was met — a workout of that obligation's own discipline whose ledger
///    (`ScoreLedger.isEffective` — the manual correction where one exists, else the
///    auto-score, per §8) clears the plan's threshold.
/// 4. **Breaks the streak.** **Any** obligation of the day either had nothing of its
///    discipline recorded and was not folded into rest by the budget (a genuine,
///    unconverted miss), or was scored *below* the threshold. Both are real verdicts
///    against the plan's ask, and a streak that skipped past them would stop meaning
///    anything. A streak that survived skipping every lift would not be a streak of
///    following the plan.
///
/// The walk stops at whichever comes first: a break, or `from`. **A caller wanting an
/// accurate streak must supply enough lookback for it not to be truncated** — the same
/// shape of obligation `RestDayBudgeting` places on whole weeks (C1), applied here to
/// whole streaks. `Tallies.currentStreak` is a *lower bound* on the true streak when
/// it is truncated by `from` rather than by an actual break, and there is no way for
/// this type to tell its caller which of the two happened from the number alone.
///
/// ## Where the walk starts, and the asymmetry `today` requires (MAX-110)
///
/// Walking back from `through` is the rule above, and it silently assumed `through`
/// itself was decided. It is not, whenever `through` reaches into the future: a day
/// nothing has happened on yet cannot honestly be called a miss. But "nothing has
/// happened *yet*" is not the same claim as "nothing is known yet" — **a miss is
/// unknowable until the day ends, but a hit is knowable the instant it happens.** A
/// run finished this morning is a fact by lunchtime; treating it as absent until
/// midnight is a second, smaller version of the same defect this ticket exists to fix
/// (an earlier draft of this fix did exactly that, stopping the walk at `today - 1`,
/// and undercounted every streak that included a day already trained on). This asymmetry
/// is not invented here — `ScoreCalendar.resolve` already embodies it: a workout on
/// `today` resolves to `.scored` (checked *before* the forthcoming guard), never to
/// `.forthcoming`. The walk below matches that ordering rather than inventing a second
/// rule, because the calendar and this tile describe the same day and must agree.
///
/// **The walk starts at the earlier of `through` and `today` itself — `today` is
/// visited, never skipped — and `today` is judged by one extra rule layered onto the
/// four above:**
///
/// - **A hit today extends the streak**, exactly as case 3 says for any other day: an
///   effective score is a decided fact, not a guess about how the day will end.
/// - **A scored miss today breaks the streak**, exactly as case 4 says: a workout that
///   already happened and already scored below the threshold is equally decided.
/// - **An empty `today` neither extends nor breaks it.** This is the one exception to
///   case 4 — nothing recorded *yet* is not evidence of nothing coming; the walk steps
///   to yesterday instead of stopping. Yesterday, and every day before it, still applies
///   case 4 without exception: an empty day that has actually ended is a genuine miss.
///
/// Consequences for where the walk can end up starting:
///
/// - `through` is before `today`: the whole interval is in the past, `today` never
///   enters the walk, and the answer is unchanged from the pre-MAX-110 rule. This is
///   the invariant the "entirely in the past" test pins.
/// - `today` falls inside or after the interval (`from...through` reaches `today` or
///   beyond): the walk starts at `today` (not before it, per the rule above) and never
///   looks at any day after it, so a future scheduled day can no longer be reached, let
///   alone break the walk.
/// - `today` is before `from`: nothing in the interval has a known outcome yet, and the
///   streak is `0` without the walk running at all — there is no decided day to start
///   from.
///
/// ## Effective obligations (rule 2: converted rest is excluded, not merely spared)
///
/// An obligation MAX-016 converted is dropped from **both**
/// `EffectiveObligationTally.effectiveCount` and `.eligibleCount` — not counted as
/// effective, not counted as a miss either. The alternative (counting it toward
/// `eligibleCount` but not `effectiveCount`) would still drag the rate down, which is
/// exactly the "penalty" rule 2 forbids. The same exclusion applies to the streak: see
/// case 1 above.
///
/// ## What "effective" reads (rule 1: annotations win, the auto-score stays recorded)
///
/// Every read below goes through `ScoreLedger.effectiveValue` / `.isEffective`, never
/// `Score.value` / `Score.isEffective` directly. The ledger already resolves "the
/// manual correction where one exists, else the auto-score" (§8) without touching
/// `automatic` — this type adds no second copy of that rule. Reading the ledger's own
/// answer is what keeps the auto-score visibly on record (`ledger.automatic` is
/// untouched by every tally here) while the tallies themselves use the correction.
public enum TalliesCalculator {
    /// Discarded by every reader here — `RestDayBudgeting` only stamps this on the
    /// `ConvertedObligation` values it returns, and this type reads nothing off them but
    /// their identity. A fixed constant (never `Date()`) keeps the call deterministic
    /// without asking every caller to thread through a timestamp that cannot affect
    /// the answer.
    private static let restDayBudgetingStamp = Date(timeIntervalSince1970: 0)

    public static func compute(_ input: TalliesInput) throws -> Tallies {
        var workoutsByDay: [CalendarDay: [Workout]] = [:]
        for workout in input.workouts {
            let day = try workout.calendarDay(in: input.timeZone)
            workoutsByDay[day, default: []].append(workout)
        }

        let queriedDays = try CalendarDay.days(from: input.from, through: input.through)
        // Still **days**, and deliberately: "did you show up" is a question about the
        // athlete's week, not about the plan's asks, so a day with a run and a lift is
        // one day here even though it is two obligations below. A19 moved the unit of
        // account for *adherence*; it did not make this figure mean something else.
        let workoutDays = queriedDays.filter { workoutsByDay[$0] != nil }.count
        let averageScore = try computeAverageScore(queriedDays: queriedDays, workoutsByDay: workoutsByDay, input: input)

        // C1: resolve rest-day budgeting over the whole Monday-first weeks touching
        // the interval, never a slice of one. See `TalliesInput`'s documentation for
        // the matching obligation this places on its `workouts`.
        let (planDaysInRange, convertedObligations) = try resolveRestDayConversions(
            workoutsByDay: workoutsByDay,
            input: input
        )

        let effectiveDays = try effectiveObligationTally(
            queriedDays: queriedDays,
            workoutsByDay: workoutsByDay,
            planDaysInRange: planDaysInRange,
            convertedObligations: convertedObligations,
            input: input
        )

        let currentStreak = try streak(
            workoutsByDay: workoutsByDay,
            planDaysInRange: planDaysInRange,
            convertedObligations: convertedObligations,
            input: input
        )

        let currentWeek = try resolveCurrentWeek(input: input)

        return try Tallies(
            from: input.from,
            through: input.through,
            workoutDays: workoutDays,
            effectiveDays: effectiveDays,
            averageScore: averageScore,
            currentStreak: currentStreak,
            currentWeek: currentWeek
        )
    }

    // MARK: - Average score

    private static func computeAverageScore(
        queriedDays: [CalendarDay],
        workoutsByDay: [CalendarDay: [Workout]],
        input: TalliesInput
    ) throws -> Double? {
        var total = 0
        var count = 0
        for day in queriedDays {
            for workout in workoutsByDay[day] ?? [] {
                guard let ledger = input.scoreLedgers[workout.id] else { continue }
                total += ledger.effectiveValue.points
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) : nil
    }

    // MARK: - Rest-day conversion (C1)

    private static func resolveRestDayConversions(
        workoutsByDay: [CalendarDay: [Workout]],
        input: TalliesInput
    ) throws -> (planDaysInRange: [CalendarDay: PlanDay], convertedObligations: Set<ObligationID>) {
        guard let planCalendar = input.planCalendar else { return ([:], []) }

        let expandedStart = try input.from.startOfTrainingWeek()
        let expandedEnd = try input.through.startOfTrainingWeek().adding(days: 6)
        let expandedPlanDays = try planCalendar.planDays(from: expandedStart, through: expandedEnd)

        var planDaysInRange: [CalendarDay: PlanDay] = [:]
        for planDay in expandedPlanDays where planDay.date >= input.from && planDay.date <= input.through {
            planDaysInRange[planDay.date] = planDay
        }

        let conversions = try RestDayBudgeting.convertingMissedObligations(
            planDays: expandedPlanDays,
            workoutDisciplines: workoutDisciplines(workoutsByDay),
            budget: input.restDayBudget,
            createdAt: restDayBudgetingStamp,
            // C3: a day on or after `today` has not happened yet, so it is never a
            // candidate for forgiveness — the whole expanded week is still handed
            // over, so the week's shape (and so which misses sit next to a scheduled
            // rest day) is unaffected. Mirrors `ScoreCalendar.resolveRestDayConversions`.
            outcomesUnknownFrom: input.today
        )
        return (planDaysInRange, Set(conversions.map(\.id)))
    }

    /// Which disciplines each day actually saw a workout in (A19/§6.2).
    ///
    /// The one place the day-level "was anything recorded" test becomes a per-slot one.
    /// `ScoreCalendar` derives the identical mapping for the identical call, so the two
    /// cannot disagree about which obligations the budget was offered.
    static func workoutDisciplines(
        _ workoutsByDay: [CalendarDay: [Workout]]
    ) -> [CalendarDay: Set<Discipline>] {
        workoutsByDay.mapValues { workouts in
            Set(workouts.map { $0.activityType.discipline })
        }
    }

    // MARK: - Effective days

    private static func effectiveObligationTally(
        queriedDays: [CalendarDay],
        workoutsByDay: [CalendarDay: [Workout]],
        planDaysInRange: [CalendarDay: PlanDay],
        convertedObligations: Set<ObligationID>,
        input: TalliesInput
    ) throws -> EffectiveObligationTally {
        var effectiveCount = 0
        var eligibleCount = 0
        for day in queriedDays {
            // MAX-110: a day on or after `today` has no outcome yet, so nothing it asked
            // for is either effective or a miss — counting it toward `eligibleCount`
            // would measure the rate against chances that have not happened. Strict,
            // matching `ScoreCalendar`: today itself is not yet decided. Kept as a
            // day-level guard rather than left to `.notYetDue` because it must also
            // withhold a session *already performed* today, whose obligation the
            // resolver would otherwise decide.
            guard day < input.today else { continue }

            // A19: each obligation contributes independently, so a Tuesday asking for a
            // run and a lift adds two to the denominator and one to the numerator when
            // only the run was met. Every exclusion the day-level rule made — converted
            // rest, recorded-but-unscored, a day the plan does not govern — survives as
            // an `ObligationOutcome` that `isEligible` answers false for.
            let obligations = resolveObligations(
                on: day,
                workoutsByDay: workoutsByDay,
                planDaysInRange: planDaysInRange,
                convertedObligations: convertedObligations,
                input: input
            )
            eligibleCount += obligations.eligibleCount
            effectiveCount += obligations.effectiveCount
        }
        return try EffectiveObligationTally(
            effectiveCount: effectiveCount,
            eligibleCount: eligibleCount
        )
    }

    /// One day's obligations, resolved through the shared roll-up (§7.3). The streak and
    /// the ratio above both read this, and so does the calendar's mixed-day cell
    /// (MAX-135) — which is the whole point of there being one function.
    private static func resolveObligations(
        on day: CalendarDay,
        workoutsByDay: [CalendarDay: [Workout]],
        planDaysInRange: [CalendarDay: PlanDay],
        convertedObligations: Set<ObligationID>,
        input: TalliesInput
    ) -> DayObligations {
        DayObligationResolver.resolve(
            date: day,
            planDay: planDaysInRange[day],
            workouts: workoutsByDay[day] ?? [],
            scoreLedgers: input.scoreLedgers,
            convertedObligations: convertedObligations,
            outcomeIsKnown: day < input.today
        )
    }

    // MARK: - Streak

    private static func streak(
        workoutsByDay: [CalendarDay: [Workout]],
        planDaysInRange: [CalendarDay: PlanDay],
        convertedObligations: Set<ObligationID>,
        input: TalliesInput
    ) throws -> Int {
        // MAX-110: see the type's "Where the walk starts, and the asymmetry `today`
        // requires" documentation. `today` is visited, not skipped — a day strictly
        // after it never is — and does not run at all when even `from` has not
        // happened yet.
        let walkStart = min(input.through, input.today)
        guard walkStart >= input.from else { return 0 }
        var streak = 0
        var day = walkStart
        while true {
            // A19/§6.3: the four cases the walk used to spell out are now the day's
            // roll-up over its obligations — AND at the day level, so a day that met its
            // run and skipped its lift breaks the streak rather than extending it. The
            // streak still counts **days**, not obligations: a fully-met Tuesday asking
            // for both is one day of following the plan, not two.
            let obligations = resolveObligations(
                on: day,
                workoutsByDay: workoutsByDay,
                planDaysInRange: planDaysInRange,
                convertedObligations: convertedObligations,
                input: input
            )
            switch obligations.streakContribution {
            case .extends:
                streak += 1
            case .breaks:
                return streak
            case .neutral:
                // No plan governs the day, or it asked only for rest, or the budget
                // converted what it asked for, or a workout is recorded and unscored, or
                // — on `today` alone — nothing is recorded yet and the day has not ended.
                break
            }
            guard day != input.from else { break }
            day = try day.adding(days: -1)
        }
        return streak
    }

    // MARK: - Current week

    private static func resolveCurrentWeek(input: TalliesInput) throws -> TrainingWeek {
        let start = try input.through.startOfTrainingWeek()
        let end = try start.adding(days: 6)
        var arcWeekIndex: Int?
        if let planCalendar = input.planCalendar, let plan = planCalendar.plan(on: input.through) {
            arcWeekIndex = try planCalendar.arcWeek(for: input.through, under: plan)
        }
        return try TrainingWeek(start: start, end: end, arcWeekIndex: arcWeekIndex)
    }
}
