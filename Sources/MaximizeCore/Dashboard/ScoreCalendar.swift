import Foundation

/// What one day on the score-colored calendar (D4, FR-3.2) actually is.
///
/// ## Why nine cases, not "good / bad / empty"
///
/// The PRD treats these as different facts, and collapsing them would throw away
/// information the athlete can act on:
///
/// - `.scored` — a workout happened and was judged. The one state color is *for*.
/// - `.partiallyMet` — the day asked for **two** sessions (A17) and exactly one of them
///   was met. Not a ninth colour and not a fourth channel: LIFTING-SPEC §7.2 is explicit
///   that the cell gains a *state*, and the contrast budget MAX-084 and MAX-087 paid for
///   is already spent. See the case's own documentation for what it draws on and why.
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

    /// The day prescribed two obligations and **exactly one of them was met** (A19,
    /// LIFTING-SPEC §7.2). A Tuesday whose run scored effective and whose lift never
    /// happened is this state, not `.scored`.
    ///
    /// ## What this reverses, precisely
    ///
    /// `dayState` used to say, in its own words, *"a workout that actually happened
    /// always outranks the plan's ask for the day"*. That reasoning was written for a day
    /// whose single ask was rest and the athlete ran anyway, where what was done genuinely
    /// is the more informative fact. It does not transfer to a day whose *other* ask went
    /// unmet: there, what was done is a half-truth, and a green cell over a skipped
    /// obligation is the calendar lying about the week. So `.scored` still outranks the
    /// ask for **the obligation it belongs to**; it no longer outranks a *different*
    /// obligation's miss.
    ///
    /// ## Why the payload is two halves rather than one verdict
    ///
    /// Both halves are drawn from the one shared roll-up (`DayObligationResolver`, §7.3):
    /// the calendar must never answer "was this day fully met" differently from the
    /// effective-obligations tile, or the two disagree about the same Tuesday with a
    /// colour attached. `met` is what the day still earned; `unmet` is what it did not,
    /// and it names the slot so the spoken sentence can say *which* half was dropped —
    /// the difference between "you skipped the lift" and "you skipped the run", which no
    /// ~42pt cell can draw but which is the whole reason the athlete asked for both.
    ///
    /// **Never reachable on a day prescribing one session**, by construction: it takes a
    /// met obligation *and* an unmet one, and a one-slot day has at most one obligation
    /// of either kind. That is what makes this state cost nothing historically.
    case partiallyMet(met: MetObligation, unmet: UnmetObligation)

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

extension ScoreCalendarDayState {

    /// The half of a mixed day that **was** met (`ObligationOutcome.met`).
    ///
    /// `band` is non-optional here because a met obligation always has one: meeting an
    /// obligation requires a workout of its discipline that was scored, and a scored
    /// workout carries `ScoreLedger.automatic.band`. Modelling it as an optional would
    /// have made an unrepresentable day representable.
    ///
    /// **The band is the auto-score's, never a correction's** (D1/D4/D8) — the same rule
    /// `.scored` obeys, and the same one `ObligationResolution.band` already encodes. So
    /// an obligation met *by annotation* over an ineffective auto-score arrives here as
    /// met, carrying the band the scorer wrote. The two readings disagree on purpose; the
    /// divergence between them is PRD §2's scorer-quality signal, and resolving it away
    /// on a calendar cell would destroy exactly the telemetry it exists to preserve.
    public struct MetObligation: Hashable, Sendable {
        public let discipline: Discipline

        /// What the plan asked of this slot — the ask, not what was performed. A day can
        /// meet a `.long` ask with an easy run; `ScoreCalendarDay.agreement` is where that
        /// divergence lives, and it is a different question from this one.
        public let kind: ScheduledSessionKind

        public let band: ScoreBand

        public init(discipline: Discipline, kind: ScheduledSessionKind, band: ScoreBand) {
            self.discipline = discipline
            self.kind = kind
            self.band = band
        }
    }

    /// The half of a mixed day that was **not** met — `.missed` (nothing of that
    /// discipline was recorded and the weekly budget did not stretch to it) or `.notMet`
    /// (something was recorded, and judged short).
    ///
    /// A converted obligation is deliberately **not** one of these: D9/A6 forgave it, so
    /// the day was not held to it, and `DayObligations.isFullyMet` excludes it from the
    /// test for exactly the same reason. A day whose lift was forgiven and whose run was
    /// met is a `.scored` day, not a partial one.
    public struct UnmetObligation: Hashable, Sendable {
        public let discipline: Discipline

        /// What the plan asked of this slot.
        public let kind: ScheduledSessionKind

        /// The band of the best-scored workout of this discipline, or **nil when nothing
        /// of it was recorded at all**. That nil is the whole difference between "you
        /// lifted and it fell short" and "you did not lift", which the spoken sentence
        /// says and the cell — one fill, one glyph — cannot.
        public let judgedBand: ScoreBand?

        public init(discipline: Discipline, kind: ScheduledSessionKind, judgedBand: ScoreBand?) {
            self.discipline = discipline
            self.kind = kind
            self.judgedBand = judgedBand
        }
    }
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
    ///
    /// **Either slot counts, as of MAX-135.** It was `PlanDay.canBeMissed` — the run ask
    /// alone — which MAX-134 deliberately left in place because widening it silently
    /// changes what a cell draws. A day prescribing a lift is a day the plan asked
    /// something of, and drawing no ring on it would say the opposite in the one channel
    /// that carries the plan at all. `PlanDay.hasObligations` is the same predicate seen
    /// from the tallies' end (A19), and the two agree on every day either has ever seen,
    /// because every plan on disk rests its lift slot.
    public var prescribesASession: Bool {
        prescription?.hasObligations == true
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

        let (planDaysInRange, convertedObligations) = try resolveRestDayConversions(
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
            // **The shared roll-up, not a second one** (§7.3, MAX-134). Every judgement
            // below about which of the day's asks were met is read off this value; the
            // effective-obligations tile counts the same value over the same interval, so
            // the cell and the tile cannot disagree about the same Tuesday.
            let obligations = DayObligationResolver.resolve(
                date: day,
                planDay: planDay,
                workouts: dayWorkouts,
                scoreLedgers: scoreLedgers,
                convertedObligations: convertedObligations,
                outcomeIsKnown: outcomeIsKnown
            )
            let state = dayState(
                dayWorkouts: dayWorkouts,
                bestScored: best,
                obligations: obligations,
                planDay: planDay
            )
            return ScoreCalendarDay(
                date: day,
                state: state,
                prescription: planDay,
                agreement: agreement(planDay: planDay, scored: best),
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
    ) throws -> (planDaysInRange: [CalendarDay: PlanDay], convertedObligations: Set<ObligationID>) {
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
        // **Both slots' conversions now** (MAX-135). MAX-134 had to filter this to the run
        // slot because a forgiven *lift* had no cell state to land in, and folding it in
        // would have painted a day's run as forgiven because its lift was. The states below
        // are per-obligation, so the whole set is handed over — the identical value
        // `TalliesCalculator` passes the same resolver, which is what stops the budget
        // being spent one way for the tile and another for the cell.
        return (planDaysInRange, Set(conversions.map(\.id)))
    }

    // MARK: - Per-day state

    /// - Parameters:
    ///   - obligations: the day's asks and what became of each, from the one shared
    ///     roll-up (§7.3). Every met/unmet/forgiven judgement below reads this rather than
    ///     re-deriving one; `planDay` is still passed because "no plan governs this day"
    ///     and "the plan governs it and asks nothing" are different facts and
    ///     `DayObligations` deliberately does not distinguish them.
    private static func dayState(
        dayWorkouts: [Workout],
        bestScored: (Workout, ScoreLedger)?,
        obligations: DayObligations,
        planDay: PlanDay?
    ) -> ScoreCalendarDayState {
        // §7.2, ahead of everything: on a day that asked for two sessions and got one,
        // the worse verdict colours the day. A workout that happened still outranks the
        // plan's ask for *its own* obligation — that is `.scored` below, unchanged — but
        // it no longer outranks a different obligation's miss.
        if let mixed = partiallyMet(obligations) {
            return mixed
        }
        // Every decided obligation was met (or forgiven), so the day is coloured by the
        // **worst** band among the met ones. On the single-obligation day that is every
        // day in the athlete's history, "worst of one" is the same band the day-wide
        // best-of below would have chosen, so no historical cell moves; on a two-session
        // day it is §7.2's rule applied to a day that met both asks, which is the same
        // all-of the streak uses (§6.3) rather than the best-of that resolves two attempts
        // at one ask.
        if let scored = scoredFromObligations(obligations, dayWorkouts: dayWorkouts) {
            return scored
        }
        // A workout that happened on a day the plan asked nothing of — a rest day the
        // athlete ran through, or a day before the first plan version. D4 colors by what
        // was done, and that is a fact worth surfacing honestly rather than hiding behind
        // "scheduled rest".
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

        guard planDay != nil else { return .unplanned }
        // The plan governs the day and asks nothing of **either** slot. Widened from
        // `PlanDay.canBeMissed` (the run slot alone) by MAX-135, which is the ticket that
        // can give a lift-only day a cell to land in: before this, a day prescribing a
        // lift and resting its run slot drew "scheduled rest day" over an obligation the
        // athlete was still being held to. No day either predicate has ever seen moves —
        // every plan on disk rests its lift slot, so the two agree everywhere.
        guard let first = obligations.resolutions.first else { return .scheduledRest }
        // Ahead of `.missed`/`.convertedRest`: a day whose outcome is not in has nothing
        // to forgive and nothing to have skipped. (The resolver settles all of a day's
        // obligations against the same `outcomeIsKnown`, so these cannot mix.)
        if let pending = obligations.resolutions.first(where: { $0.outcome == .notYetDue }) {
            return .forthcoming(scheduledKind: pending.scheduledSession.kind)
        }
        // A real miss outranks a forgiven one: on a day whose run was converted and whose
        // lift was skipped, the cell has to show the skip. Run-first within each, from
        // `resolutions`' own slot ordering, so the answer never depends on input order.
        if let missed = obligations.resolutions.first(where: { $0.outcome == .missed }) {
            return .missed(scheduledKind: missed.scheduledSession.kind)
        }
        if let converted = obligations.resolutions.first(where: { $0.outcome == .converted }) {
            return .convertedRest(scheduledKind: converted.scheduledSession.kind)
        }
        // Unreachable: `.met` and `.notMet` imply a scored workout and `.awaitingVerdict`
        // a recorded one, and all three were answered above. Falls back to the day's ask
        // rather than to rest, so that a seventh `ObligationOutcome` arriving without a
        // cell state shows the plan asking for something rather than claiming it did not.
        return .missed(scheduledKind: first.scheduledSession.kind)
    }

    /// §7.2's mixed day: exactly one of the day's two obligations was met.
    ///
    /// Nil on every day in the athlete's history, because it takes a met obligation *and*
    /// an unmet one and a one-slot day has at most one obligation of either kind. Both
    /// lists are the shared roll-up's own (`DayObligations.metObligations` /
    /// `.unmetObligations`), so "was this day fully met" is answered here by the same
    /// arithmetic the effective-obligations tile counts by.
    private static func partiallyMet(_ obligations: DayObligations) -> ScoreCalendarDayState? {
        guard let met = obligations.metObligations.first,
              // A met obligation always carries a band (see `MetObligation`); the guard is
              // how that invariant is enforced rather than assumed, and a day that somehow
              // lacked one falls through to `.scored` rather than to a force unwrap.
              let band = met.band,
              let unmet = obligations.unmetObligations.first
        else { return nil }
        return .partiallyMet(
            met: ScoreCalendarDayState.MetObligation(
                discipline: met.discipline,
                kind: met.scheduledSession.kind,
                band: band
            ),
            unmet: ScoreCalendarDayState.UnmetObligation(
                discipline: unmet.discipline,
                kind: unmet.scheduledSession.kind,
                judgedBand: unmet.band
            )
        )
    }

    /// The band and activity a day that met everything it was held to is coloured by:
    /// the **worst** band among its met obligations.
    ///
    /// Worst rather than best because these are different obligations, not two attempts at
    /// one — §5's warm-up-jog generosity already resolved each obligation's own attempts
    /// inside the resolver, and applying it a second time across obligations is the
    /// day-level OR §6.1 rejects. Ties keep the earlier slot (run before lift), so the
    /// result never depends on input order.
    ///
    /// Nil when the day met nothing it was asked for, which includes every day the plan
    /// asked nothing of; the caller falls back to the day's best-scored workout there.
    private static func scoredFromObligations(
        _ obligations: DayObligations,
        dayWorkouts: [Workout]
    ) -> ScoreCalendarDayState? {
        let worst = obligations.metObligations.reduce(nil) { current, candidate -> ObligationResolution? in
            guard let currentBand = current?.band else { return candidate }
            guard let candidateBand = candidate.band else { return current }
            return DayObligationResolver.bandRank(candidateBand) > DayObligationResolver.bandRank(currentBand)
                ? candidate
                : current
        }
        guard let worst, let band = worst.band,
              let workout = dayWorkouts.first(where: { $0.id == worst.decidingWorkoutID })
        else { return nil }
        return .scored(band: band, activityType: workout.activityType)
    }

    // MARK: - Plan vs. execution

    /// Nil unless something was performed *and* scored — the classification this
    /// compares against lives on the auto-score (`Score.actualClassification`, D2), so
    /// a recorded-but-unscored day has an ask and an outcome but no comparison yet.
    /// That is a real state, not a gap to paper over: the calendar still shows the ask.
    ///
    /// **The ask is the scored workout's own slot's** (MAX-135). It used to be
    /// `planDay.scheduledSession` — the run ask — whatever had been scored, which was
    /// correct only while nothing but a run could be. Once a lift can carry a score, that
    /// comparison reads a strength session against the day's running ask and reports the
    /// athlete diverged from a plan they in fact followed; a lift is not an attempt at the
    /// run, which is §6.2's rule arriving one surface further on. Unchanged for every
    /// score on disk: `scheduledSession(for: .run)` *is* `scheduledSession`.
    private static func agreement(
        planDay: PlanDay?,
        scored: (Workout, ScoreLedger)?
    ) -> PlanExecutionAgreement? {
        guard let scored else { return nil }
        let performed = scored.1.automatic.actualClassification
        let discipline = scored.0.activityType.discipline
        guard let planDay, !planDay.scheduledSession(for: discipline).isRest else {
            return .unprescribed(performed: performed)
        }
        let prescribed = planDay.scheduledSession(for: discipline).kind
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
