import Foundation

/// Which obligation, independent of what it asked for: the day it falls on, and the
/// slot that asked for it (A19).
///
/// Separate from `ObligationResolution` because it is the part that is a *key* — the
/// rest-day budget hands back a set of forgiven obligations, and the resolver looks each
/// day's obligations up in it. Keying on the prescription itself would make the lookup
/// depend on the session's distance and note, which have nothing to do with identity.
public struct ObligationID: Hashable, Sendable {
    public let date: CalendarDay
    public let discipline: Discipline

    public init(date: CalendarDay, discipline: Discipline) {
        self.date = date
        self.discipline = discipline
    }
}

/// What became of one obligation (A19, LIFTING-SPEC §6.2).
///
/// Six cases rather than "met / not met", for the reason `ScoreCalendarDayState` has
/// nine rather than three: the absences are not interchangeable. A day nothing was
/// recorded on and a day whose workout has not been scored are both "not met", and
/// treating them alike would either invent a miss the athlete did not commit or forgive
/// one they did.
public enum ObligationOutcome: Hashable, Sendable {
    /// A workout of this obligation's discipline was recorded and its ledger clears the
    /// plan's threshold. **Best-of across the day's attempts at this one obligation** —
    /// see `DayObligationResolver.resolve`, where §5's warm-up-jog generosity lives
    /// unchanged.
    case met

    /// A workout of this discipline was recorded and scored, and nothing cleared the
    /// threshold. A verdict, not an absence.
    case notMet

    /// Nothing of this discipline was recorded, the day has been and gone, and the
    /// weekly budget did not stretch to cover it (D9). A genuine miss.
    case missed

    /// The same absence as `.missed`, forgiven by MAX-016's automatic weekly conversion
    /// (D9/A6). Excluded from **both** sides of the effective ratio and neutral for the
    /// streak — see `EffectiveObligationTally` for why it is dropped rather than merely
    /// spared the "ineffective" label.
    case converted

    /// A workout of this discipline was recorded and nothing has scored it yet. Not a
    /// verdict either way: the athlete did not skip anything, and there is no judgement
    /// yet to count for them.
    case awaitingVerdict

    /// The day has not happened yet, so its outcome is not in. Distinct from `.missed`
    /// for exactly the reason `ScoreCalendarDayState.forthcoming` is: a day the athlete
    /// has not reached is not a day the athlete has skipped.
    case notYetDue

    /// Whether this obligation counts toward `EffectiveObligationTally.eligibleCount` —
    /// i.e. whether it was a chance that has actually been decided.
    ///
    /// The three excluded cases are excluded for three different reasons and it is worth
    /// keeping them straight: `.converted` was forgiven (rule 2), `.awaitingVerdict` has
    /// no verdict yet, and `.notYetDue` has not arrived. Only the first is a policy
    /// decision; the other two are statements about time.
    public var isEligible: Bool {
        switch self {
        case .met, .notMet, .missed: return true
        case .converted, .awaitingVerdict, .notYetDue: return false
        }
    }

    /// Whether this obligation counts toward `EffectiveObligationTally.effectiveCount`.
    public var isEffective: Bool { self == .met }

    /// Whether this obligation, on its own, ends the streak (§6.3's all-of).
    ///
    /// A `switch` rather than a two-case `==` chain so that a seventh outcome cannot be
    /// added without someone being asked what it does to the streak.
    public var breaksTheStreak: Bool {
        switch self {
        case .notMet, .missed: return true
        case .met, .converted, .awaitingVerdict, .notYetDue: return false
        }
    }
}

/// What one day does to the streak. Three states rather than a `Bool` because "does not
/// extend it" and "ends it" are the distinction the whole streak definition turns on.
public enum StreakContribution: Hashable, Sendable {
    case extends
    case breaks
    case neutral
}

/// One obligation, and what became of it.
public struct ObligationResolution: Hashable, Sendable {
    public let id: ObligationID

    /// The plan's ask for this slot. **Never `.rest`** — a rest slot is not an
    /// obligation, and `DayObligationResolver` never builds a resolution for one.
    public let scheduledSession: ScheduledSession

    public let outcome: ObligationOutcome

    /// The band of the day's **best-scored** workout of this discipline, taken from
    /// `ScoreLedger.automatic.band`, or nil when nothing of this discipline carries an
    /// auto-score.
    ///
    /// ## Why this is a second read rather than a restatement of `outcome`
    ///
    /// `outcome` asks "was this obligation met", which §8 answers through
    /// `ScoreLedger.isEffective` — the manual correction where one exists. This asks
    /// "what colour is this obligation", which D1/D4 answer through the immutable
    /// auto-score only, because `ScoreBand` has no `init(score:)` and a manual annotation
    /// changes what tallies count, not what the calendar draws (D8: the divergence
    /// between the two is the scorer-quality signal, and resolving it away on a cell
    /// would destroy it).
    ///
    /// So the two can legitimately disagree — an ineffective auto-score raised by an
    /// annotation is `.met` with a `.ineffective` band — and they are carried side by
    /// side here rather than collapsed, so that the tile and the cell can each read the
    /// one they are entitled to *from the same resolution* instead of from two.
    public let band: ScoreBand?

    /// The workout `band` came from — the best-banded scored workout of this
    /// obligation's discipline, earliest start breaking a tie.
    ///
    /// An identifier rather than the workout, so that a caller that wants the activity
    /// type (`ScoreCalendarDayState.scored` carries one) looks it up in the day's own
    /// workouts rather than having this type copy health data around.
    public let decidingWorkoutID: UUID?

    public init(
        id: ObligationID,
        scheduledSession: ScheduledSession,
        outcome: ObligationOutcome,
        band: ScoreBand? = nil,
        decidingWorkoutID: UUID? = nil
    ) {
        self.id = id
        self.scheduledSession = scheduledSession
        self.outcome = outcome
        self.band = band
        self.decidingWorkoutID = decidingWorkoutID
    }

    public var date: CalendarDay { id.date }
    public var discipline: Discipline { id.discipline }
}

/// One day's obligations and their outcomes — **the shared roll-up LIFTING-SPEC §7.3
/// requires**, and the single answer to "what did this day come to".
///
/// ## Why this type exists at all (§7.3)
///
/// > *"The day roll-up and the obligation tally must come from one core function. If
/// > `ScoreCalendar` computes 'was this day fully met' one way and `TalliesCalculator`
/// > computes it another, the calendar and the effective-days tile will disagree about
/// > the same Tuesday — which is D2's drift with a colour attached."*
///
/// So `TalliesCalculator` counts `eligibleCount`/`effectiveCount` off this type and walks
/// the streak off `streakContribution`; the calendar's mixed-day state (MAX-135) reads
/// `resolutions` and `unmetObligations` off the same value, and computes no roll-up of
/// its own. A caller that finds it needs a fact this type does not carry should add it
/// here rather than derive it beside.
///
/// ## What is deliberately *not* here
///
/// No verdict enum, and no severity ordering over the day's obligations. §7.2 specifies
/// the cell gains a state and then says, in terms, *"I am deliberately not specifying the
/// visual"* — so this type carries the facts that decision needs (which obligations were
/// met, which were not, what each was asked to be, and what band the met ones scored) and
/// leaves the mapping to a `ScoreCalendarDayState` to the ticket that can see a pixel.
/// What it does fix, because §7.3 says it must be fixed once, is the *arithmetic*:
/// `isFullyMet` and `streakContribution` are the roll-up, and there is one of each.
public struct DayObligations: Hashable, Sendable {
    public let date: CalendarDay

    /// Ascending by slot (run, then lift). Empty when the plan asked nothing of the day
    /// — a scheduled rest day on both slots, or a day no plan version governs at all.
    /// Those two are different facts, and this type deliberately does not distinguish
    /// them: neither carries an obligation, so neither has anything to be effective *at*.
    /// `ScoreCalendarDay.prescription` is where that distinction survives.
    public let resolutions: [ObligationResolution]

    public init(date: CalendarDay, resolutions: [ObligationResolution]) {
        self.date = date
        self.resolutions = resolutions
    }

    /// The plan asked nothing of this day.
    public var isEmpty: Bool { resolutions.isEmpty }

    public func resolution(for discipline: Discipline) -> ObligationResolution? {
        resolutions.first { $0.discipline == discipline }
    }

    /// This day's contribution to `EffectiveObligationTally.eligibleCount` — **the number
    /// of obligations decided, not one for the day** (A19). A Tuesday asking for a run
    /// and a lift contributes two.
    public var eligibleCount: Int {
        resolutions.filter { $0.outcome.isEligible }.count
    }

    /// This day's contribution to `EffectiveObligationTally.effectiveCount`.
    public var effectiveCount: Int {
        resolutions.filter { $0.outcome.isEffective }.count
    }

    /// Obligations that were decided and not met — `.missed` or `.notMet`.
    ///
    /// This is where §7.2's *"the worse verdict colours the day"* reads its subject: the
    /// discipline and the prescribed kind of the half that went unmet. Empty on a day
    /// that met everything it was held to.
    public var unmetObligations: [ObligationResolution] {
        resolutions.filter { $0.outcome.isEligible && !$0.outcome.isEffective }
    }

    /// Obligations that were met.
    public var metObligations: [ObligationResolution] {
        resolutions.filter { $0.outcome.isEffective }
    }

    /// Every obligation the plan actually held this day to was met (§6.3's all-of).
    ///
    /// **Converted obligations are excluded from the test rather than counted as met.** A
    /// day whose run was forgiven by the budget and whose lift was performed did
    /// everything still being asked of it; counting the forgiven half as a met half would
    /// be generous in a different direction, and counting it as unmet would make the
    /// forgiveness worthless. Either way the athlete cannot tell the difference from the
    /// number, which is the argument for excluding it in both places (see
    /// `EffectiveObligationTally`).
    ///
    /// False on a day with no obligations at all: nothing was asked, so nothing was met.
    /// The streak reads that as neutral, not as a break — see `streakContribution`.
    public var isFullyMet: Bool {
        let judged = resolutions.filter { $0.outcome != .converted }
        return !judged.isEmpty && judged.allSatisfy { $0.outcome.isEffective }
    }

    /// What this day does to the streak (§6.3).
    ///
    /// > *"A day breaks the streak if **any** of its prescribed obligations was
    /// > missed-and-unconverted or scored below threshold. A day extends the streak if it
    /// > had at least one obligation and **every** obligation was met. A day with no
    /// > obligations is neutral."*
    ///
    /// **This is AND at the day level, and it is deliberately the opposite of the
    /// best-of generosity inside a single obligation.** They answer different questions.
    /// "Was every attempt at my run good" is answered best-of, and lives in
    /// `DayObligationResolver.resolve`. "Did I do everything the plan asked today" is
    /// answered all-of, and lives here. A streak that survived skipping every lift would
    /// not be a streak of following the plan.
    public var streakContribution: StreakContribution {
        if resolutions.contains(where: { $0.outcome.breaksTheStreak }) { return .breaks }
        return isFullyMet ? .extends : .neutral
    }
}

/// Resolves one day's obligations against what was actually recorded (A19, §6.2/§7.3).
///
/// The one place that decides, for the whole app, what a day came to. See
/// `DayObligations` for why it is one place.
public enum DayObligationResolver {
    /// - Parameters:
    ///   - date: the day being resolved. Passed rather than read off `planDay` so that a
    ///     day no plan governs still has an answer.
    ///   - planDay: the plan's entry for the day, or nil where no version governs it.
    ///     Its `date` is expected to equal `date`; callers resolve both from the same
    ///     `PlanCalendar` query, so there is no path here that could disagree.
    ///   - workouts: **every** workout recorded on the day, of either discipline. This
    ///     function splits them by `ActivityType.discipline`; a caller that pre-filtered
    ///     would be making the attribution decision twice.
    ///   - scoreLedgers: keyed by `Workout.id`. A workout with no entry is unscored — a
    ///     first-class, often-indefinite state, never a miss and never a zero.
    ///   - convertedObligations: what D9's weekly budget forgave, from
    ///     `RestDayBudgeting.convertingMissedObligations`. Obligations, not days (§6.4):
    ///     forgiving a whole day would forgive the run the athlete also skipped, which is
    ///     a budget that buys more than it was sold for.
    ///   - outcomeIsKnown: whether the day has been and gone (`date < today`). False for
    ///     today itself and for every day after it. Only the *absence* of a workout
    ///     consults this: a miss cannot be judged before the day ends, but a session
    ///     already performed and already scored is decided the instant it happens — the
    ///     same asymmetry `ScoreCalendar.resolve` and `TalliesCalculator`'s streak walk
    ///     both embody, expressed once here instead of a third time.
    public static func resolve(
        date: CalendarDay,
        planDay: PlanDay?,
        workouts: [Workout],
        scoreLedgers: [UUID: ScoreLedger] = [:],
        convertedObligations: Set<ObligationID> = [],
        outcomeIsKnown: Bool
    ) -> DayObligations {
        guard let planDay else { return DayObligations(date: date, resolutions: []) }

        let resolutions = planDay.prescribedDisciplines.map { discipline -> ObligationResolution in
            let id = ObligationID(date: date, discipline: discipline)

            // §6.2: "against the workouts of its own discipline". A lift is not an
            // attempt at the run the plan asked for, so it can neither meet that
            // obligation nor excuse it — which is A19's argument arriving from the side
            // §6.2 does not spell out. See `PROJECT_TRACKER.md`'s MAX-134 note.
            let performed = workouts.filter { $0.activityType.discipline == discipline }
            let scored = performed.compactMap { workout in
                scoreLedgers[workout.id].map { (workout, $0) }
            }
            let best = bestScored(scored)

            let outcome: ObligationOutcome
            if performed.isEmpty {
                if !outcomeIsKnown {
                    outcome = .notYetDue
                } else if convertedObligations.contains(id) {
                    outcome = .converted
                } else {
                    outcome = .missed
                }
            } else if scored.isEmpty {
                outcome = .awaitingVerdict
            } else {
                // §5, unchanged: two attempts at *one* obligation resolve generously. A
                // warm-up jog and a real run is one ask attempted twice, and the day is
                // judged by its best session rather than dragged down by the worse one.
                // §6 turns on keeping this distinct from the all-of rule across
                // obligations — see `DayObligations.streakContribution`.
                outcome = scored.contains { $0.1.isEffective } ? .met : .notMet
            }

            return ObligationResolution(
                id: id,
                scheduledSession: planDay.scheduledSession(for: discipline),
                outcome: outcome,
                band: best?.1.automatic.band,
                decidingWorkoutID: best?.0.id
            )
        }

        return DayObligations(date: date, resolutions: resolutions)
    }

    /// The best-banded of a set of scored workouts, deterministically. Ties (same band)
    /// break on earliest start, so the result never depends on input order.
    ///
    /// Internal and shared: `ScoreCalendar` picks the workout that colours a cell with
    /// this same function, so "the day's best session" is one notion in the module rather
    /// than two that agree today.
    static func bestScored(_ pairs: [(Workout, ScoreLedger)]) -> (Workout, ScoreLedger)? {
        pairs.min { lhs, rhs in
            let lhsRank = bandRank(lhs.1.automatic.band)
            let rhsRank = bandRank(rhs.1.automatic.band)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.0.start < rhs.0.start
        }
    }

    /// Ascending cost — index 0 is the best band. Deliberately not `Comparable` on
    /// `ScoreBand` itself, which would suggest a general-purpose ordering PRD D4 never
    /// asked for.
    static func bandRank(_ band: ScoreBand) -> Int {
        switch band {
        case .effective: return 0
        case .marginal: return 1
        case .ineffective: return 2
        }
    }
}

extension Discipline {
    /// A total order over the two slots.
    ///
    /// Used only as a deterministic tie-break — the last one in
    /// `RestDayBudgeting`'s ranking, and the order a day's obligations are listed in. It
    /// carries **no training judgement**: LIFTING-SPEC §6.5 rejects weighting the
    /// disciplines against each other outright ("invents a training judgement the app has
    /// no standing to make"), and a rank that decided which obligation matters more would
    /// be exactly that. Cost is `RestDayBudgeting.costTier`'s business, and it ranks the
    /// *session kind*, never the slot.
    var slotOrder: Int {
        switch self {
        case .run: return 0
        case .lift: return 1
        }
    }

    /// The two slots in `slotOrder`, so every list of obligations in the app comes out in
    /// the same order without each site sorting for itself.
    static let slotOrdered: [Discipline] = Discipline.allCases.sorted { $0.slotOrder < $1.slotOrder }
}
