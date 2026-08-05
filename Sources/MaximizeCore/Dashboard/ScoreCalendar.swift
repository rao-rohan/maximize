import Foundation

/// What one day on the score-colored calendar (D4, FR-3.2) actually is.
///
/// ## Why eight cases, not "good / bad / empty"
///
/// The PRD treats these as different facts, and collapsing them would throw away
/// information the athlete can act on:
///
/// - `.scored` — a workout happened and was judged. The one state color is *for*.
/// - `.awaitingScore` — a workout happened but nothing has judged it yet (§7.0's
///   capture-to-score gap, or no API key stored). Not a verdict either way — showing
///   it as ineffective would be lying about a score that has not been reached, and
///   showing it as effective would be a promise nobody made.
/// - `.noVerdict` — a workout happened and none ever will be reached for it, because
///   the plan scores runs and this was not one (MAX-111). The same absence of a score
///   as `.awaitingScore`, and the opposite tense: one is a wait, the other is a
///   settled fact. See the case's own documentation for why they are not one state.
/// - `.missed` — the plan asked for something and nothing happened, and the weekly
///   rest-day budget did not stretch to cover it (D9). A real failure to execute.
/// - `.forthcoming` — the plan asks for something on a day that **has not happened
///   yet**. Same absence of a score as `.missed`, opposite meaning, and until MAX-105
///   this type could not tell them apart: `resolve` had no notion of "today", so every
///   scheduled day between now and the end of the selected month resolved to `.missed`
///   and the forward half of the grid read as a wall of failure. A day the athlete has
///   not reached is not a day the athlete has skipped.
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

    /// A workout was recorded but has no score yet. **A score is still coming**: the
    /// lazy path (`WorkoutIngestionPipeline.completeIngestion(forWorkout:)`) re-attempts
    /// it every time the workout is opened, and every reason it has not arrived —
    /// no key stored, no network, a rubric with no band for what happened — is one a
    /// later launch or a later plan version resolves.
    ///
    /// Only ever carries a *run*'s activity type, by construction: see `.noVerdict`.
    case awaitingScore(activityType: ActivityType)

    /// A workout was recorded and **no score will ever be reached for it**: the plan
    /// scores runs (D1 — every band in the rubric measures a run), and this was a lift,
    /// a ride, a hike or a walk.
    ///
    /// ## Why this is not `.awaitingScore`
    ///
    /// Until MAX-111, every recorded workout was scored, so "recorded and unscored"
    /// could only ever mean "not yet". MAX-111 stopped non-runs being judged against a
    /// running rubric — correctly, because `easy.wellOverCap` matches a strength session
    /// on heart rate alone and D8 would then make that number permanent — and left
    /// this state with no case of its own. A lift rendered as `.awaitingScore` tells the
    /// athlete a verdict is on its way, forever, which is a promise the app cannot keep.
    ///
    /// **Not a failure, and not an omission.** The athlete trained; the plan simply has
    /// no rubric to judge that training by. Everything else about the workout is
    /// captured and stored exactly as a run's is — duration, energy, the heart-rate
    /// series, the samples. What is absent is one number.
    ///
    /// ## Why one state and not two
    ///
    /// "Not a run, so no rubric" and "a run whose rubric could not be applied" are two
    /// different facts (`IngestionPipelineDiagnostic.UnscoredReason` names both), but
    /// only the first is decidable here and only the first is permanent. The reason a
    /// score is missing is a *diagnostic* — deliberately never stored, and carrying no
    /// workout identifier — so the only durable input this decision has is the
    /// workout's own activity type. And a run left unscored by `noBandMatched` is
    /// genuinely still waiting: D1 makes a new band a new plan version, not a code
    /// change, so the day that version lands the score arrives. `.awaitingScore` is the
    /// truthful state for it.
    ///
    /// ## The invariant that pays for the calendar's drawing
    ///
    /// `.awaitingScore` and this case can never carry the same activity type — one holds
    /// runs, the other holds everything else, split on `ActivityType.isRun`, the same
    /// predicate `WorkoutIngestionPipeline` and `WorkoutClassifier` both branch on. So
    /// the glyph channel the cell already spends on the activity separates the two for
    /// free, and this state needs no colour of its own (MAX-084/MAX-087 spent that
    /// budget; MAX-105 spent the ring). It draws on the same neutral fill every
    /// no-verdict day draws on, and the whole distinction is carried by the glyph and
    /// the VoiceOver sentence — the way `.scheduledRest` and `.convertedRest` are
    /// already told apart.
    case noVerdict(activityType: ActivityType)

    /// The plan asked for `scheduledKind` (never `.rest` — see `PlanDay.canBeMissed`)
    /// and nothing was recorded; the weekly budget did not cover it.
    case missed(scheduledKind: ScheduledSessionKind)

    /// The plan asked for `scheduledKind` and nothing was recorded, but MAX-016's
    /// automatic conversion (D9/A6) spent the weekly budget on this day.
    case convertedRest(scheduledKind: ScheduledSessionKind)

    /// The plan's own ask for the day was rest.
    case scheduledRest

    /// The plan asks for `scheduledKind` on a day that has not happened yet.
    ///
    /// **Never `.rest`**, for the same reason `.missed` never is: a scheduled rest day
    /// is `.scheduledRest` whether it is behind or ahead of today. Rest was prescribed,
    /// rest is what the day is, and there is no outcome still pending on it.
    case forthcoming(scheduledKind: ScheduledSessionKind)

    /// No plan version governs this day.
    case unplanned
}

/// How what the athlete did on a day compares with what the plan asked of it
/// (MAX-105).
///
/// ## Why this reads the stored score rather than re-deciding anything
///
/// Both halves of the comparison are already recorded on the immutable auto-score
/// (D2/D8): `Score.scheduledSession` is the prescription the scorer judged against, and
/// `Score.actualClassification` is MAX-013's answer for what the run actually was.
/// Nothing here re-classifies a workout or re-resolves a threshold — it compares two
/// values that were decided once, at ingestion, and stored.
///
/// The *prescribed* side is taken from the day's resolved `PlanDay` rather than from
/// `Score.scheduledSession`, so that every day in the range — scored or not — describes
/// its prescription from one source. `PlanCalendar`'s ordering invariants make the two
/// identical by construction: a later plan version may never take effect before an
/// earlier one, so the plan in force on a day cannot change after that day has been
/// scored (D1).
public enum PlanExecutionAgreement: Hashable, Sendable {
    /// A session was prescribed and what was performed is that kind.
    case asPrescribed(kind: ScheduledSessionKind)

    /// A session was prescribed and something else was performed — an easy run on a
    /// long-run day. Not a failure and deliberately not coloured as one: the athlete
    /// trained, and the score already judges *how* they trained. It is a divergence
    /// between plan and execution, which is the thing this calendar exists to show.
    case divergent(prescribed: ScheduledSessionKind, performed: WorkoutClassification)

    /// Something was performed on a day the plan asked nothing of — a run on a
    /// scheduled rest day, or on a day no plan version governs.
    case unprescribed(performed: WorkoutClassification)
}

/// What tapping a calendar day should do (MAX-108) — "is there anything behind this
/// day" is a core decision, not a view's opinion, the same way `state` and
/// `agreement` are.
///
/// ## Why this cannot be read off `state` alone
///
/// A day with nothing recorded reaches this type's empty cases from five different
/// `ScoreCalendarDayState` cases — `.missed`, `.convertedRest`, `.scheduledRest`,
/// `.forthcoming`, `.unplanned` — and only one of those, `.forthcoming`, names its own
/// tense. `.scheduledRest` and `.unplanned` carry none: a rest day can be scheduled
/// for tomorrow exactly as it can for yesterday, and a query reaching earlier than
/// every plan version is `.unplanned` whether the day itself is behind the athlete or
/// still ahead. Matching on `state`'s case would get a future scheduled-rest day or a
/// future unplanned day wrong — both would read as an inert dead end rather than as
/// "this hasn't happened yet." So `resolve` decides this the same way it decides
/// `.forthcoming` itself: against `today`, independent of which of the five empty
/// states the day landed in.
public enum ScoreCalendarDayDestination: Hashable, Sendable {
    /// One or more workouts were recorded on the day, ordered by start time — the
    /// order a swipe between two same-day workouts should present. A single element
    /// is the ordinary case; two or more is the day this ticket exists to serve.
    case workouts([UUID])

    /// Nothing was recorded, and the day has not happened yet (on or after `today`,
    /// the same strict boundary `.forthcoming` uses — a scheduled run at six in the
    /// morning has not been skipped, so today itself lands here, not below). Opening
    /// a workout that does not exist would be a broken tap; a door here should say
    /// what the calendar's glyph and VoiceOver label already say, not pretend to be
    /// one.
    case notYetDue

    /// Nothing was recorded, and the day is behind the athlete. A true dead end —
    /// there is nothing to navigate to — but not a silent one; see
    /// `ScoreCalendarFormatting` for what a tap on it should say.
    case nothingRecorded
}

/// One resolved calendar cell: a day, the state it is in, and the plan underneath it.
///
/// ## Two layers, deliberately not merged (MAX-105)
///
/// `state` is what *happened*. `prescription` is what was *asked*. They are separate
/// properties rather than one fatter enum because they are separate facts with
/// different lifetimes: the ask is fixed the moment a plan version takes effect, and
/// the outcome arrives days later, or never. Folding the ask into `state` would mean
/// `.scored` carried a plan payload that most of its readers do not want, and would put
/// the same `ScheduledSessionKind` in two places for `.missed` to disagree with itself
/// about.
///
/// It is also what makes the rendering rule expressible in one sentence: the
/// prescription is the ground, the state is the figure drawn on it.
public struct ScoreCalendarDay: Hashable, Sendable, Identifiable {
    public var id: CalendarDay { date }

    public let date: CalendarDay
    public let state: ScoreCalendarDayState

    /// The plan's entry for this day, resolved through `PlanCalendar` (D1) — the plan
    /// version in effect *on this day*, never today's. Nil where no version governs it.
    ///
    /// Carried even where `state` already names the ask (`.missed`, `.scheduledRest`,
    /// `.forthcoming`) so that "what does the plan say about this day" has exactly one
    /// answer regardless of how the day turned out, and so a reader never has to
    /// reconstruct it from a state's associated value.
    public let prescription: PlanDay?

    /// How the day's execution compares with `prescription` — nil when nothing was
    /// performed, and nil whenever a performed workout carries no score, since the
    /// classification this compares against is stored on the score (D2). That covers
    /// both `.awaitingScore` and `.noVerdict`: a lift has no `WorkoutClassification`
    /// to compare against a prescription and, unlike an awaiting run, never will.
    public let agreement: PlanExecutionAgreement?

    /// What a tap on this day should do (MAX-108). See
    /// `ScoreCalendarDayDestination`'s own documentation for why this is not derived
    /// from `state` at the view layer.
    public let destination: ScoreCalendarDayDestination

    public init(
        date: CalendarDay,
        state: ScoreCalendarDayState,
        prescription: PlanDay? = nil,
        agreement: PlanExecutionAgreement? = nil,
        destination: ScoreCalendarDayDestination = .nothingRecorded
    ) {
        self.date = date
        self.state = state
        self.prescription = prescription
        self.agreement = agreement
        self.destination = destination
    }

    /// Whether the plan asks for a *session* on this day, as opposed to rest or
    /// nothing at all.
    ///
    /// This is the whole condition the plan layer is drawn on — one bit, so a cell
    /// that carries it needs no legend beyond "the plan asked for something here".
    /// `PlanDay.canBeMissed` is the same predicate seen from the other end (D9), and
    /// reusing it is deliberate: a day the plan can hold you to is exactly a day the
    /// plan asked something of.
    public var prescribesASession: Bool {
        prescription?.canBeMissed == true
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
/// calls `RestDayBudgeting.convertingMissedObligations` itself, over the same widened,
/// whole-week range, and both types are pure functions of the same records. A caller
/// already assembling a `TalliesInput` for the same interval already has everything
/// `resolve` below needs.
///
/// **The two no longer differ (MAX-105 found the gap; MAX-110 closed it).** Both this
/// type and `TalliesCalculator` are told what day it is now, and both withhold days on
/// or after `today` from the budget's candidate pool (`RestDayBudgeting`'s
/// `outcomesUnknownFrom`). The rule for *which* miss is forgiven still lives in exactly
/// one place; what both callers agree on is which days are eligible to be forgiven at
/// all. Forgiving a day that has not happened is not a judgement call — it spends a
/// finite weekly budget on a non-event, and leaves a genuine miss earlier in the same
/// week showing red because the allowance was already gone.
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
    ///   - today: the athlete's current day, in `timeZone`. **An input, never a clock
    ///     read.** Two answers depend on it and both are wrong if it is guessed: a
    ///     scheduled day with nothing recorded is `.forthcoming` on or after this day
    ///     and `.missed` before it, and only days before it are candidates for D9's
    ///     rest-day conversion. Threading it in is what keeps `resolve` a pure function
    ///     — the same discipline `timeZone` above is held to, and the reason both the
    ///     future/missed split and the budget boundary are testable at all.
    ///
    ///     Note the boundary is *strict*: today itself is `.forthcoming`, not
    ///     `.missed`. A scheduled run at six in the morning has not been skipped.
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
        today: CalendarDay,
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
            today: today,
            workoutsByDay: workoutsByDay,
            planCalendar: planCalendar,
            restDayBudget: restDayBudget
        )

        return try CalendarDay.days(from: from, through: through).map { day in
            let planDay = planDaysInRange[day]
            let dayWorkouts = workoutsByDay[day] ?? []
            let outcomeIsKnown = day < today
            let best = bestScoredPair(
                dayWorkouts.compactMap { workout in
                    scoreLedgers[workout.id].map { (workout, $0) }
                }
            )
            let state = dayState(
                dayWorkouts: dayWorkouts,
                bestScored: best,
                planDay: planDay,
                isConverted: convertedDates.contains(day),
                outcomeIsKnown: outcomeIsKnown
            )
            return ScoreCalendarDay(
                date: day,
                state: state,
                prescription: planDay,
                agreement: agreement(planDay: planDay, score: best?.1.automatic),
                destination: destination(dayWorkouts: dayWorkouts, outcomeIsKnown: outcomeIsKnown)
            )
        }
    }

    // MARK: - MAX-108: is there anything behind this day

    /// `dayWorkouts` empty is exactly the condition every empty `ScoreCalendarDayState`
    /// case above is reached under (see `dayState`) — this does not re-derive that,
    /// it reads the same input. `outcomeIsKnown` is `dayState`'s own `today` boundary,
    /// threaded through unchanged rather than recomputed, so the two decisions can
    /// never disagree about which side of today a day falls on.
    private static func destination(
        dayWorkouts: [Workout],
        outcomeIsKnown: Bool
    ) -> ScoreCalendarDayDestination {
        guard !dayWorkouts.isEmpty else {
            return outcomeIsKnown ? .nothingRecorded : .notYetDue
        }
        // Ascending by start — the order a swipe between them should present, and the
        // same tiebreak `bestScoredPair` and the unscored picker above both use, so
        // three different reads of "which workout is first" never disagree.
        return .workouts(dayWorkouts.sorted { $0.start < $1.start }.map(\.id))
    }

    // MARK: - C1: rest-day conversion over whole weeks (mirrors TalliesCalculator)

    private static func resolveRestDayConversions(
        from: CalendarDay,
        through: CalendarDay,
        today: CalendarDay,
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

        let conversions = try RestDayBudgeting.convertingMissedObligations(
            planDays: expandedPlanDays,
            // The identical mapping `TalliesCalculator` builds for the identical call, so
            // the two cannot disagree about which obligations the budget was offered —
            // the same D2 argument that had both types recompute the budget rather than
            // read a stored override.
            workoutDisciplines: TalliesCalculator.workoutDisciplines(workoutsByDay),
            budget: restDayBudget,
            createdAt: restDayBudgetingStamp,
            // The whole week is still handed over (C1), so the week's *shape* — which
            // days it rests on, and therefore which misses are adjacent to rest — is
            // unchanged. Only candidacy is bounded: a day whose outcome is not in
            // cannot be a miss, so it cannot be forgiven.
            outcomesUnknownFrom: today
        )
        // **The run slot's conversions only**, because every state this set feeds —
        // `.convertedRest` against `.missed` — describes `planDay.scheduledSession`, the
        // run ask. A forgiven *lift* has no cell state to land in until MAX-135 gives the
        // mixed day one, and folding it in here would silently paint a day's run as
        // forgiven because its lift was. The budget itself is shared and spent over both
        // slots (§6.4); it is only the rendering that is still one-slot.
        return (planDaysInRange, Set(conversions.filter { $0.discipline == .run }.map(\.date)))
    }

    // MARK: - Per-day state

    private static func dayState(
        dayWorkouts: [Workout],
        bestScored: (Workout, ScoreLedger)?,
        planDay: PlanDay?,
        isConverted: Bool,
        outcomeIsKnown: Bool
    ) -> ScoreCalendarDayState {
        // A workout that actually happened always outranks the plan's ask for the
        // day — D4 colors by what was done, not by what was scheduled. This applies
        // even on a day the plan scheduled as rest: an extra session still gets
        // judged on its own merits, and a rest day the athlete ran through is a fact
        // worth surfacing honestly rather than hiding behind "scheduled rest".
        if let best = bestScored {
            return .scored(band: best.1.automatic.band, activityType: best.0.activityType)
        }
        // Nothing on this day carries a score, so every workout below is unscored.
        //
        // **A pending answer outranks a settled absence.** A day holding a run and a
        // lift — the ordinary day once MAX-109 lands — is a day whose cell is about to
        // change: the run's score arrives and the fill becomes a band. Calling that day
        // "no verdict" would be false the moment scoring completes, while calling it
        // "awaiting" is true of the obligation that is actually outstanding. The reverse
        // ordering has no such reading.
        //
        // Within each group the earliest start wins, the same tiebreak `bestScoredPair`
        // and `destination` both use, so three reads of "which workout is first" cannot
        // disagree.
        let earliestFirst = dayWorkouts.sorted { $0.start < $1.start }
        if let earliestRun = earliestFirst.first(where: { $0.activityType.isRun }) {
            return .awaitingScore(activityType: earliestRun.activityType)
        }
        if let earliest = earliestFirst.first {
            return .noVerdict(activityType: earliest.activityType)
        }

        guard let planDay else { return .unplanned }
        guard planDay.canBeMissed else { return .scheduledRest }
        // Ahead of `missed`/`convertedRest`, and deliberately ahead of `isConverted`
        // too: a day whose outcome is not in has nothing to forgive, so a stray
        // conversion could never present itself as one.
        guard outcomeIsKnown else {
            return .forthcoming(scheduledKind: planDay.scheduledSession.kind)
        }
        return isConverted
            ? .convertedRest(scheduledKind: planDay.scheduledSession.kind)
            : .missed(scheduledKind: planDay.scheduledSession.kind)
    }

    // MARK: - Plan vs. execution

    /// Nil unless something was performed *and* scored — the classification this
    /// compares against lives on the auto-score (`Score.actualClassification`, D2), so
    /// a recorded-but-unscored day has an ask and an outcome but no comparison yet.
    /// That is a real state, not a gap to paper over: the calendar still shows the ask.
    private static func agreement(planDay: PlanDay?, score: Score?) -> PlanExecutionAgreement? {
        guard let score else { return nil }
        let performed = score.actualClassification
        guard let planDay, planDay.canBeMissed else {
            return .unprescribed(performed: performed)
        }
        let prescribed = planDay.scheduledSession.kind
        return prescribed == ScheduledSessionKind(performed)
            ? .asPrescribed(kind: prescribed)
            : .divergent(prescribed: prescribed, performed: performed)
    }

    /// The best-banded workout of the day, deterministically.
    ///
    /// **`DayObligationResolver.bestScored` is now the one implementation** (MAX-134):
    /// the resolver has to pick the same workout per obligation that this picks per day,
    /// and §7.3 is explicit that the calendar and the tallies must not each compute their
    /// own answer to the same question. "Best" still mirrors the effective tally's own
    /// "contains effective" generosity — a day with two workouts is judged by its best
    /// session, not dragged down by a warmup or a second, worse effort — and ties (same
    /// band) still break on earliest start, so the result never depends on
    /// `dayWorkouts`' input order.
    private static func bestScoredPair(_ pairs: [(Workout, ScoreLedger)]) -> (Workout, ScoreLedger)? {
        DayObligationResolver.bestScored(pairs)
    }
}
