import Foundation

/// Everything Claude is told about the athlete's training over a frozen window
/// (CHAT-FIRST-SPEC.md §3.3, PRD-AMENDMENTS.md A12, LIFTING-SPEC.md §10.2).
///
/// ## A roll-up, not a stack of fact sheets
///
/// The obvious way to answer "has my drift flattened this month" is to build a
/// `WorkoutContext` per run and concatenate. §3.1 rejects that, and the reason is not
/// prompt size: a month at fact-sheet fidelity is *the athlete's entire recent movement
/// record, at the finest resolution the app stores*, leaving the device because they
/// asked a one-sentence question. So this type carries exactly four things, and the
/// omissions are the load-bearing half.
///
/// 1. **The plan in effect** (`plan`) — version, heart-rate cap, cadence band, weekly
///    template, both rubric thresholds, goals, and the arc week the window ends in with
///    its prescribed long run. This is the athlete's own configuration, not a
///    measurement of their body, and "am I on plan" is unanswerable without it.
/// 2. **The tallies** (`tallies`) — `TalliesCalculator`'s output for this exact window,
///    verbatim. See "No arithmetic here" below.
/// 3. **One line per session** (`sessions`) — day, weekday, discipline, classification,
///    the plan's ask for that day, distance, duration, average heart rate, drift, and
///    the verdict. That is all.
/// 4. **The scope itself** (`scope`), stated in prose by the renderer, together with how
///    many sessions were dropped by the cap and why.
///
/// ## What is deliberately absent, and why each one
///
/// - **No heart-rate shape.** `WorkoutContext.heartRateShape`'s ten buckets are what let
///   one run's fact sheet answer "why did it climb after mile 3". Across twelve runs that
///   is 120 numbers answering a question nobody asked in a training thread.
/// - **No splits.** MAX-068 sent them once, for one run, and its own documentation calls
///   a split series *"a finer-grained record of one person's movement than anything else
///   in the prompt"*. Twelve of them is not a marginal increase.
/// - **No route, no coordinates.** `WorkoutContext` already gives the reasoning; a month
///   of them is a home address and a routine.
/// - **No score rationales.** `Session.verdict` carries the whole `Score`, because that is
///   the value `WorkoutVerdict` produces and re-deriving a narrower one here would be a
///   second resolution of "what is this workout's verdict". The **renderer never prints
///   `Score.rationale`**: the prose the scorer wrote per run is not needed to see a trend,
///   and it invites the model to argue with a stored verdict (D8).
/// - **No workout identifiers.** `Session.workoutID` exists so a view can push to a run's
///   own screen (§6.2); like `Workout.id` in `WorkoutContext`, it is never rendered.
///
/// ## No arithmetic here — §3.6(a), and it has teeth
///
/// Every aggregate this type quotes is produced by *the same core function the
/// corresponding screen reads*. `tallies` is `TalliesCalculator.compute`'s own value, the
/// one `TrendTileData` presents on the dashboard; `currentArcWeekIndex` is the arc week
/// that calculator resolved, through `PlanCalendar.arcWeek(for:under:)`; every per-session
/// figure is a stored `Workout` or `DerivedMetrics` field read verbatim (D2).
///
/// **This type contains no arithmetic over more than one workout.** The single number it
/// derives is `sessionCountInScope`, which counts lines in a prompt rather than measuring
/// an athlete. Averaging a few drift figures here to save a call into the tallies would be
/// D2's drift arriving in a prompt, where nothing on screen contradicts it and nobody
/// notices — and because chat and a tile now describe the same number to the same person,
/// that divergence is a **visible product defect**, not an internal untidiness.
///
/// ## Bounded twice over
///
/// The scope bounds this in the ordinary case. `maximumRenderedSessions` bounds it again,
/// exactly as `WorkoutContext.maximumRenderedSplits` does, because **health data leaving
/// the device must never be sized by a number nothing has validated.**
///
/// ## What this costs, plainly
///
/// This widens what leaves the device. Before it, one run's facts left when the athlete
/// opened a thread and typed. After it, a summary of up to `maximumRenderedSessions`
/// sessions leaves per training turn — and LIFTING-SPEC §10.2 notes the count roughly
/// doubles for an athlete who also lifts three times a week, because the unit is the
/// session and not the day. The mitigations are the four bounds above and A14's invariant
/// that no chat call is ever unattended. Every ticket touching this file gets a
/// `/security-review`.
public struct TrainingContext: Hashable, Sendable {

    /// One session in the window — one workout, not one day.
    ///
    /// **Per session, not per day** (LIFTING-SPEC §10.2): a Tuesday can hold a run and a
    /// lift, and they are separate obligations (A19). Rolling them into one line would
    /// make the second one invisible in exactly the prompt that is supposed to answer
    /// "did I do what the plan asked".
    ///
    /// Fields that do not apply are **nil and omitted by the renderer**, not printed as
    /// "—". A lift has no distance and an indoor session may have no heart-rate series;
    /// a heading whose only content is that it does not apply is prompt tokens spent on
    /// nothing (A18's rule, applied to a line instead of a section). The renderer states
    /// that convention once, for the whole roll-up, rather than per line.
    public struct Session: Hashable, Sendable, Identifiable {
        /// One session per workout, so the workout's id identifies it.
        public var id: UUID { workoutID }

        /// Carried for the app — §6.2's chip strip pushes from a line to that run's own
        /// screen, and MAX-103 needs something to push with. **Never rendered.**
        public let workoutID: UUID

        /// The calendar day the session belongs to, in the athlete's zone. Resolved by
        /// the builder from `Workout.calendarDay(in:)`, never guessed here.
        public let day: CalendarDay

        /// What the capture source called it — the discipline tag LIFTING-SPEC §10.2
        /// asks every line to carry, so a lift does not read as an unusually short run.
        public let activityType: ActivityType

        /// What the plan asked for on `day`, what the classifier decided happened, and
        /// the verdict or its honest absence.
        ///
        /// This is `WorkoutVerdict` — **the same core value the workout detail header
        /// renders** (FR-1.1). Three of the ten fields §3.3 names are exactly what that
        /// type resolves, and resolving them a second way here is how a bubble and a
        /// header start disagreeing about the same run (§3.6(a)).
        public let verdict: WorkoutVerdict

        /// `Workout.distanceMeters`, verbatim. Nil for a session that measures none.
        public let distanceMeters: Double?

        /// `Workout.durationSeconds`, verbatim. Never nil: every captured session has one.
        public let durationSeconds: Double

        /// `DerivedMetrics.averageHeartRateBPM`, verbatim (D2). Nil when the session has
        /// no heart-rate series, or when no metrics were ever derived for it — a workout
        /// ingested on a day no plan governed has none.
        public let averageHeartRateBPM: Double?

        /// `DerivedMetrics.heartRateDriftFraction`, verbatim (D2). Nil for a hard or
        /// other session, where §9 calls drift near-meaningless and MAX-012 declines to
        /// compute it, as well as when there was no series to measure.
        public let heartRateDriftFraction: Double?

        init(
            workoutID: UUID,
            day: CalendarDay,
            activityType: ActivityType,
            verdict: WorkoutVerdict,
            distanceMeters: Double?,
            durationSeconds: Double,
            averageHeartRateBPM: Double?,
            heartRateDriftFraction: Double?
        ) {
            self.workoutID = workoutID
            self.day = day
            self.activityType = activityType
            self.verdict = verdict
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.averageHeartRateBPM = averageHeartRateBPM
            self.heartRateDriftFraction = heartRateDriftFraction
        }
    }

    /// The frozen window this context describes (§3.4). Every figure here is measured
    /// over exactly these days.
    public let scope: TrainingScope

    /// The plan version governing the **last** day of the window, or nil when no version
    /// governs it — a real state (the athlete existed before the app did), not "no data".
    ///
    /// The last day rather than the first, matching `TalliesCalculator.resolveCurrentWeek`,
    /// which resolves the current training week and arc week from `through` for the same
    /// reason: a question asked about a window is asked from its end.
    public let plan: Plan?

    /// How much of the window `plan` actually governed.
    ///
    /// Stated rather than silently dropped. `plan` describes the window's *last* day, and
    /// a window straddling a revision — or one opening before the athlete had authored any
    /// plan at all — was partly measured against a cap and thresholds that are not the ones
    /// printed. An unflagged answer would quote one plan's numbers over another plan's
    /// days, which is the same class of quiet wrongness D1 makes plan versioning exist to
    /// prevent.
    public enum PlanCoverage: Hashable, Sendable {
        /// One plan version governed every day of the window — or, when `plan` is nil,
        /// none did. Overwhelmingly the ordinary case.
        case wholeWindow

        /// `plan` took effect *inside* the window. The days before its `effectiveFrom`
        /// had no plan at all, so the plan made no ask for them and they cannot be missed.
        case beganWithinTheWindow

        /// An earlier version governed the window's opening days.
        case revisedWithinTheWindow(earlier: PlanVersion)
    }

    /// See `PlanCoverage`.
    public let planCoverage: PlanCoverage

    /// `TalliesCalculator.compute`'s value for exactly this window — workout-days,
    /// effective-days, average score, streak, current training week.
    ///
    /// Read, never re-derived: this is the same `Tallies` the dashboard's own
    /// `TrendTileData` presents, from the same function over the same stored records.
    /// `TrainingContextAgreementTests` asserts the two agree, which is the difference
    /// between claiming §3.6(a)'s property and having it.
    public let tallies: Tallies

    /// One line per session in the window, ascending by start.
    ///
    /// **Empty when `sessionCountInScope` exceeds `maximumRenderedSessions`** — beyond
    /// the cap the context states the count and lists none, exactly as
    /// `WorkoutFactSheet` does for an implausible split series. Also empty, of course,
    /// when the window holds no sessions at all; `sessionCountInScope` tells those apart
    /// and the renderer words them differently.
    public let sessions: [Session]

    /// How many sessions the window actually holds, whether or not they are listed.
    ///
    /// The one number this type derives, and it measures the prompt rather than the
    /// athlete — see "No arithmetic here".
    public let sessionCountInScope: Int

    /// The most sessions the roll-up will list before saying so and listing none.
    ///
    /// **200, matching `WorkoutContext.maximumRenderedSplits`,** and chosen against the
    /// windows the app can actually produce rather than against a token budget:
    ///
    /// - A week is at most ~14 sessions and a month at most ~62, even for an athlete
    ///   training twice a day. Neither can reach this.
    /// - A year can, and does: five runs and three lifts a week is ~400. That is the one
    ///   window where "list every session" is the shape §3.1 rejects — the athlete's whole
    ///   year of movement leaving the device per turn — so a year-scale thread answers
    ///   from the plan and the tallies, which is what a year-scale question needs anyway.
    /// - A count beyond either means the stored record is wrong, and the honest response
    ///   to a record we do not believe is to say what is on file and send none of it.
    ///
    /// Unlike the splits cap, then, this bound is **reachable by a legitimate window**,
    /// and its "state the count, list none" branch is a real product state rather than a
    /// guard against corruption. That is deliberate: a bound nothing ever reaches has
    /// never been tested by use.
    public static let maximumRenderedSessions = 200

    init(
        scope: TrainingScope,
        plan: Plan?,
        planCoverage: PlanCoverage,
        tallies: Tallies,
        sessions: [Session],
        sessionCountInScope: Int
    ) {
        self.scope = scope
        self.plan = plan
        self.planCoverage = planCoverage
        self.tallies = tallies
        self.sessions = sessions
        self.sessionCountInScope = sessionCountInScope
    }

    /// Whether the window's sessions were withheld by `maximumRenderedSessions` rather
    /// than simply not existing. Two different facts, and the renderer says which.
    public var sessionsWereWithheldByTheCap: Bool {
        sessions.isEmpty && sessionCountInScope > 0
    }

    /// The 1-based arc week the window's last day falls in, or nil when no plan governs
    /// it.
    ///
    /// Read off `tallies`, which got it from `PlanCalendar.arcWeek(for:under:)` — the one
    /// interpretation of "what week is it", shared with the plan screen (`PlanDisplayData`)
    /// and with the calendar resolution the scorer uses.
    public var currentArcWeekIndex: Int? {
        tallies.currentWeek.arcWeekIndex
    }

    /// The long run the plan prescribes for `currentArcWeekIndex`, in metres.
    ///
    /// A lookup in `LongRunArc`, not a calculation: nil when the arc has run out, which
    /// `PlanCalendar` documents as an expected state meaning the plan wants a new version.
    public var currentArcWeekDistanceMeters: Double? {
        guard let plan, let week = currentArcWeekIndex else { return nil }
        return plan.longRunArc.distanceMeters(forWeek: week)
    }
}
