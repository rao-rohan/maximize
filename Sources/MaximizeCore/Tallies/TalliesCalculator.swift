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
    /// Two things depend on it, both because a day whose outcome is not yet in cannot
    /// be judged:
    ///
    /// - `EffectiveDayTally` never counts a day on or after `today` — see
    ///   `TalliesCalculator.effectiveDayTally`.
    /// - `RestDayBudgeting`'s weekly allowance is never spent on a day on or after
    ///   `today` — see `TalliesCalculator.resolveRestDayConversions`, which threads
    ///   this through as `outcomesUnknownFrom` (C3).
    ///
    /// The boundary is **strict**, matching `ScoreCalendar`: today itself counts as not
    /// yet decided. A session scheduled for this evening has not been skipped.
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
/// ## The streak definition (the PRD leaves this open; this is the decision, and why)
///
/// Walking backward day by day from the walk's **start day** (defined below, not
/// always `through`), each day is one of four things:
///
/// 1. **Neutral — no ask.** No plan governs the day, or the plan's ask *was* rest
///    (scheduled, or converted from a miss by MAX-016's weekly budget). The streak
///    neither grows nor breaks; the walk simply steps to the day before. **This is
///    the load-bearing choice**: a streak that reset on a plan's own prescribed rest
///    day would punish the athlete for following the plan, which is worse than
///    useless — it is hostile to the thing the plan is for.
/// 2. **Neutral — not yet judged.** A workout happened but nothing has scored it yet
///    (no API key stored, or scoring hasn't caught up). Treated the same as a rest
///    day: the athlete did not skip anything, so nothing here should cost them a
///    streak they may well still be building — but there is also no verdict yet to
///    count *for* them. The walk continues without extending the streak.
/// 3. **Extends the streak.** A scheduled, non-rest day with a workout whose ledger
///    (`ScoreLedger.isEffective` — the manual correction where one exists, else the
///    auto-score, per §8) clears the plan's threshold.
/// 4. **Breaks the streak.** Either nothing was recorded and the day was not folded
///    into rest by the budget (a genuine, unconverted miss), or a workout happened
///    and was scored *below* the threshold. Both are real verdicts against the
///    plan's ask, and a streak that skipped past them would stop meaning anything.
///
/// The walk stops at whichever comes first: a break, or `from`. **A caller wanting an
/// accurate streak must supply enough lookback for it not to be truncated** — the same
/// shape of obligation `RestDayBudgeting` places on whole weeks (C1), applied here to
/// whole streaks. `Tallies.currentStreak` is a *lower bound* on the true streak when
/// it is truncated by `from` rather than by an actual break, and there is no way for
/// this type to tell its caller which of the two happened from the number alone.
///
/// ## Where the walk starts (MAX-110)
///
/// Walking back from `through` is the rule above, and it silently assumed `through`
/// itself was decided. It is not, whenever `through` reaches into the future: a day on
/// or after `today` has no outcome yet (the same strict boundary `ScoreCalendar` uses
/// — today itself is not yet decided), so starting the walk there and calling its
/// emptiness a "break" reads a scheduled-but-not-yet-run day as a miss. On the "this
/// month" interval that is most days of most months, which is why the streak tile
/// could read 0 for the first three weeks of a month before this fix.
///
/// **The walk instead starts at the later of never, and the most recent day whose
/// outcome is known** — the day before `today`, clamped to `through`:
///
/// - `through` is before `today`: the whole interval is in the past, `today` never
///   enters the walk, and the answer is unchanged from the pre-MAX-110 rule. This is
///   the invariant the "entirely in the past" test pins.
/// - `today` falls inside or after the interval (`from...through` reaches `today` or
///   beyond): the walk starts the day before `today` and never looks at `today` or any
///   day after it, so a future scheduled day can no longer be reached, let alone break
///   the walk.
/// - `today` is on or before `from`: nothing in the interval has a known outcome yet,
///   and the streak is `0` without the walk running at all — there is no "most recent
///   decided day" to start from.
///
/// ## Effective days (rule 2: converted rest is excluded, not merely spared)
///
/// A day MAX-016 converted is dropped from **both** `EffectiveDayTally.effectiveCount`
/// and `.eligibleCount` — not counted as effective, not counted as a miss either. The
/// alternative (counting it toward `eligibleCount` but not `effectiveCount`) would
/// still drag the rate down, which is exactly the "penalty" rule 2 forbids. The same
/// exclusion applies to the streak: see case 1 above.
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
    /// `RestDayOverride` values it returns, and this type reads nothing off them but
    /// their dates. A fixed constant (never `Date()`) keeps the call deterministic
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
        let workoutDays = queriedDays.filter { workoutsByDay[$0] != nil }.count
        let averageScore = try computeAverageScore(queriedDays: queriedDays, workoutsByDay: workoutsByDay, input: input)

        // C1: resolve rest-day budgeting over the whole Monday-first weeks touching
        // the interval, never a slice of one. See `TalliesInput`'s documentation for
        // the matching obligation this places on its `workouts`.
        let (planDaysInRange, convertedDates) = try resolveRestDayConversions(
            workoutsByDay: workoutsByDay,
            input: input
        )

        let effectiveDays = try effectiveDayTally(
            queriedDays: queriedDays,
            workoutsByDay: workoutsByDay,
            planDaysInRange: planDaysInRange,
            convertedDates: convertedDates,
            input: input
        )

        let currentStreak = try streak(
            workoutsByDay: workoutsByDay,
            planDaysInRange: planDaysInRange,
            convertedDates: convertedDates,
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
    ) throws -> (planDaysInRange: [CalendarDay: PlanDay], convertedDates: Set<CalendarDay>) {
        guard let planCalendar = input.planCalendar else { return ([:], []) }

        let expandedStart = try input.from.startOfTrainingWeek()
        let expandedEnd = try input.through.startOfTrainingWeek().adding(days: 6)
        let expandedPlanDays = try planCalendar.planDays(from: expandedStart, through: expandedEnd)

        var planDaysInRange: [CalendarDay: PlanDay] = [:]
        for planDay in expandedPlanDays where planDay.date >= input.from && planDay.date <= input.through {
            planDaysInRange[planDay.date] = planDay
        }

        let overrides = try RestDayBudgeting.convertingMissedDays(
            planDays: expandedPlanDays,
            workoutDays: Set(workoutsByDay.keys),
            budget: input.restDayBudget,
            createdAt: restDayBudgetingStamp,
            // C3: a day on or after `today` has not happened yet, so it is never a
            // candidate for forgiveness — the whole expanded week is still handed
            // over, so the week's shape (and so which misses sit next to a scheduled
            // rest day) is unaffected. Mirrors `ScoreCalendar.resolveRestDayConversions`.
            outcomesUnknownFrom: input.today
        )
        return (planDaysInRange, Set(overrides.map(\.date)))
    }

    // MARK: - Effective days

    private static func effectiveDayTally(
        queriedDays: [CalendarDay],
        workoutsByDay: [CalendarDay: [Workout]],
        planDaysInRange: [CalendarDay: PlanDay],
        convertedDates: Set<CalendarDay>,
        input: TalliesInput
    ) throws -> EffectiveDayTally {
        var effectiveCount = 0
        var eligibleCount = 0
        for day in queriedDays {
            // MAX-110: a day on or after `today` has no outcome yet, so it is neither
            // effective nor a miss — counting it toward `eligibleCount` would measure
            // the rate against chances that have not happened. Strict, matching
            // `ScoreCalendar`: today itself is not yet decided.
            guard day < input.today else { continue }
            guard let planDay = planDaysInRange[day], planDay.canBeMissed else { continue }
            guard !convertedDates.contains(day) else { continue }

            let dayWorkouts = workoutsByDay[day] ?? []
            let dayLedgers = dayWorkouts.compactMap { input.scoreLedgers[$0.id] }
            if !dayWorkouts.isEmpty, dayLedgers.isEmpty {
                continue // recorded but unscored: no verdict either way yet
            }

            eligibleCount += 1
            if dayLedgers.contains(where: \.isEffective) {
                effectiveCount += 1
            }
        }
        return try EffectiveDayTally(effectiveCount: effectiveCount, eligibleCount: eligibleCount)
    }

    // MARK: - Streak

    private static func streak(
        workoutsByDay: [CalendarDay: [Workout]],
        planDaysInRange: [CalendarDay: PlanDay],
        convertedDates: Set<CalendarDay>,
        input: TalliesInput
    ) throws -> Int {
        // MAX-110: see the type's "Where the walk starts" documentation. The walk may
        // only visit days whose outcome is known — strictly before `today` — so it
        // starts at the earlier of `through` and the day before `today`, and does not
        // run at all when even `from` has not happened yet.
        let latestDecidedDay = try input.today.adding(days: -1)
        guard latestDecidedDay >= input.from else { return 0 }
        var streak = 0
        var day = min(input.through, latestDecidedDay)
        while true {
            if let planDay = planDaysInRange[day], planDay.canBeMissed {
                let dayWorkouts = workoutsByDay[day] ?? []
                if dayWorkouts.isEmpty {
                    if !convertedDates.contains(day) {
                        break // genuine, unconverted miss
                    }
                } else {
                    let dayLedgers = dayWorkouts.compactMap { input.scoreLedgers[$0.id] }
                    if !dayLedgers.isEmpty {
                        if dayLedgers.contains(where: \.isEffective) {
                            streak += 1
                        } else {
                            break // scored below the plan's threshold
                        }
                    }
                    // else: recorded but unscored — neutral, fall through
                }
            }
            // else: no plan governs the day, or it was scheduled rest — neutral
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
