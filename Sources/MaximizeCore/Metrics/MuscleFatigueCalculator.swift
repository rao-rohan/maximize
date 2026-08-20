import Foundation

/// One strength session, reduced to the three things the fatigue model reads: what it
/// worked, when it finished, and how long it lasted (MAX-179).
///
/// A separate type from `Workout` on purpose. The model reads two records that meet
/// nowhere else — what HealthKit captured (`Workout`) and what the athlete said about it
/// (`MuscleGroupEntry`, A22) — and joining them at the calculator's door means the
/// arithmetic below never has to ask which half a field came from, and a test can state
/// a session in one line instead of building two records to imply one.
///
/// **Nothing here is derived.** `durationSeconds` is `Workout.durationSeconds` as
/// stored and `endedAt` is `Workout.end` as stored; the groups are the entry in force.
/// D2 forbids recomputing a metric at read time and this recomputes none — the decay is
/// a function of *now*, which is why it cannot be stored at ingestion and why
/// `TalliesCalculator`'s shape, not `DerivedMetricsCalculator`'s, is the one this
/// follows.
public struct MuscleFatigueSession: Hashable, Sendable {

    public let workoutID: UUID

    /// The groups in force for this session — `MuscleGroupLog.current`, never empty
    /// (`MuscleGroupEntry` forbids an empty set, so "not told yet" is the absence of a
    /// session here rather than a session naming nothing).
    public let groups: Set<MuscleGroup>

    /// When the session **ended**. Recovery runs from the end, not the start.
    public let endedAt: Date

    /// Active duration in seconds, as `Workout` stores it — paused time excluded, which
    /// is the number the weighting wants.
    public let durationSeconds: Double

    /// - Throws: `DomainError` if the session could not carry a figure at all — an
    ///   empty group set, or a duration of zero.
    ///
    ///   **A zero-duration session is refused rather than admitted as a zero weight.**
    ///   A zero would produce a fatigue figure of 0.0, which reads as *fully
    ///   recovered* — a claim, from a record that says nothing about the athlete's
    ///   body. That is exactly MAX-175's rule, applied at the input boundary where it
    ///   is cheapest to enforce.
    public init(
        workoutID: UUID,
        groups: Set<MuscleGroup>,
        endedAt: Date,
        durationSeconds: Double
    ) throws {
        guard !groups.isEmpty else {
            throw DomainError.empty(field: "MuscleFatigueSession.groups")
        }
        try Validate.positive(durationSeconds, "MuscleFatigueSession.durationSeconds")
        self.workoutID = workoutID
        self.groups = groups
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
    }
}

/// Everything `MuscleFatigueCalculator.compute` reads, bundled for `TalliesInput`'s
/// reason: the calling convention is stated once rather than hoped for at each call
/// site.
public struct MuscleFatigueInput: Sendable {

    /// The instant the map describes. **An input, never a clock read** (MAX-110) — a
    /// calculator that called `Date()` would be untestable by construction and would
    /// disagree with the figure drawn beside it the moment the two read the clock at
    /// different instants.
    public let now: Date

    /// The logged strength sessions, in any order. Sessions naming a group other than
    /// the six change nothing — `MuscleGroup` is closed.
    ///
    /// **How far back to fetch is the caller's decision, and it is nearly free to get
    /// right**: one session per group sets the figure, so a window that is too short can
    /// only under-report, never invent. Fetch at least the curve's own length —
    /// `MuscleFatigueModel.negligibleDecay` puts that at a fortnight for the standard
    /// model — or simply fetch the lifts you already have.
    public let sessions: [MuscleFatigueSession]

    public let model: MuscleFatigueModel

    public init(
        now: Date,
        sessions: [MuscleFatigueSession],
        model: MuscleFatigueModel = .standard
    ) {
        self.now = now
        self.sessions = sessions
        self.model = model
    }

    /// The join, done once: stored workouts plus the athlete's entries for them.
    ///
    /// **Which workouts may carry groups is not decided here.** It is read off
    /// `MuscleGroupEntryData.resolve(activityType:entry:)`, which A22 made the single
    /// place that answers it — a second `activityType == .traditionalStrengthTraining`
    /// in this file would be that rule written twice, and would fall out of step the day
    /// HealthKit's `functionalStrengthTraining` is mapped.
    ///
    /// Two kinds of workout are passed over, and they are passed over for different
    /// reasons:
    ///
    /// - **No entry in force** — the athlete has not said what the session worked. It
    ///   contributes nothing because nothing is known about it (A22: "I have not told
    ///   you yet" is not "I trained nothing").
    /// - **A non-positive duration** — a degenerate record that cannot be weighed. See
    ///   `MuscleFatigueSession.init` for why it is not admitted as a zero. It is skipped
    ///   rather than thrown on, so one malformed record cannot deny the athlete the
    ///   other five groups' figures.
    ///
    /// - Parameters:
    ///   - workouts: any workouts; non-lifts are filtered out here.
    ///   - muscleGroupLogs: keyed by `Workout.id`. A workout with no log is awaiting an
    ///     entry, which is the ordinary starting state and not a failure.
    public init(
        now: Date,
        workouts: [Workout],
        muscleGroupLogs: [UUID: MuscleGroupLog],
        model: MuscleFatigueModel = .standard
    ) throws {
        var sessions: [MuscleFatigueSession] = []
        for workout in workouts where workout.durationSeconds > 0 {
            let entry = MuscleGroupEntryData.resolve(
                activityType: workout.activityType,
                entry: muscleGroupLogs[workout.id]?.current
            )
            guard let groups = entry.groups else { continue }
            sessions.append(
                try MuscleFatigueSession(
                    workoutID: workout.id,
                    groups: groups,
                    endedAt: workout.end,
                    durationSeconds: workout.durationSeconds
                )
            )
        }
        self.init(now: now, sessions: sessions, model: model)
    }
}

/// Turns logged sessions into one figure per muscle group (MAX-179).
///
/// ## The curve
///
/// For each session naming a group:
///
/// ```text
/// weight   = min(durationSeconds / fullSessionSeconds, 1)
/// decay    = pow(0.5, elapsedSeconds / halfLifeSeconds)
/// fraction = weight * decay
/// ```
///
/// Exponential rather than linear because a linear ramp needs an arbitrary zero
/// crossing and then asserts a hard edge at it — *fatigued on Thursday, recovered on
/// Friday* — which is a sharper claim than "roughly halves every couple of days" and no
/// better supported. The floor at `negligibleDecay` is where the exponential's tail
/// stops being reported as fatigue; the figure underneath it is still carried, so
/// ordering survives.
///
/// ## Exactly one session governs, and it is the one that comes out highest
///
/// **Not simply the latest**, and the difference is the reason this is written down.
/// MAX-179 was briefed as "the last session that worked it", and taken literally that
/// makes the app punish honesty: a ninety-minute leg day on Monday evening reads about
/// 0.82 on Tuesday morning, and logging a ten-minute mobility session that also touched
/// legs on Tuesday morning drops the same athlete to about 0.22 — *more* logged data,
/// *less* reported fatigue, from a session that added work rather than removing it.
///
/// Taking the highest candidate reading fixes that without accumulating anything: still
/// exactly one session, still no sum, and now monotone — logging a session can never
/// lower a group's figure. It reduces to "the last session" whenever the sessions are
/// of comparable length, which is the ordinary case the brief was describing.
///
/// `MuscleFatigue` carries both instants, because they answer different questions:
/// `sessionEndedAt` is where the figure came from, and `mostRecentlyWorkedAt` is when
/// the athlete last worked the group at all — which is what a screen means by "last
/// worked", and would be a false sentence if it named the governing session instead.
///
/// Three leg days in four still read as one of them, never as their sum: that was
/// declined for MAX-179 because the sum's scale is anchored to nothing measured, and
/// the model's own weight is already a proxy standing in for work nobody recorded. See
/// `MuscleFatigue` for the full list of what this cannot know.
///
/// A pure function over stored records, in the shape `TalliesCalculator` already has —
/// no clock, no storage, no framework.
public enum MuscleFatigueCalculator {

    /// - Returns: a reading for every one of the six groups. A group no session named
    ///   is `.neverLogged` — **no figure**, not a zero (MAX-175).
    /// - Throws: `DomainError` only if a figure fell outside `0...1` or was not finite,
    ///   which the arithmetic above cannot produce from a valid `MuscleFatigueSession`.
    ///   It is a `throws` rather than a comment claiming so.
    public static func compute(_ input: MuscleFatigueInput) throws -> MuscleFatigueMap {
        var readings: [MuscleGroup: MuscleFatigueReading] = [:]
        for group in MuscleGroup.allCases {
            let named = input.sessions.filter { $0.groups.contains(group) }
            guard
                let governing = governingSession(among: named, now: input.now, model: input.model),
                let lastWorked = named.map({ $0.endedAt }).max()
            else { continue }
            readings[group] = try reading(
                for: group,
                session: governing,
                mostRecentlyWorkedAt: lastWorked,
                now: input.now,
                model: input.model
            )
        }
        return MuscleFatigueMap(
            computedAt: input.now,
            model: input.model,
            readings: readings
        )
    }

    /// The one session a group's figure is measured from: whichever reads highest. See
    /// the type note for why this is not simply the latest.
    ///
    /// Ties are broken deterministically — later session first, then longer, then by
    /// identifier — because equal figures are ordinary here (two identical sessions, two
    /// sessions sharing an end instant, a fixture) and a map that redrew itself
    /// differently on each launch would be a bug nobody could reproduce.
    private static func governingSession(
        among sessions: [MuscleFatigueSession],
        now: Date,
        model: MuscleFatigueModel
    ) -> MuscleFatigueSession? {
        var governing: MuscleFatigueSession?
        var governingFigure = -Double.infinity
        for session in sessions {
            let figure = fraction(of: session, now: now, model: model)
            guard let held = governing else {
                governing = session
                governingFigure = figure
                continue
            }
            if figure > governingFigure || (figure == governingFigure && isLater(session, than: held)) {
                governing = session
                governingFigure = figure
            }
        }
        return governing
    }

    private static func isLater(
        _ lhs: MuscleFatigueSession,
        than rhs: MuscleFatigueSession
    ) -> Bool {
        if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
        if lhs.durationSeconds != rhs.durationSeconds {
            return lhs.durationSeconds > rhs.durationSeconds
        }
        return lhs.workoutID.uuidString > rhs.workoutID.uuidString
    }

    /// Seconds since a session ended, clamped.
    ///
    /// Clamped rather than signed: a session whose end stamp is in the future is a clock
    /// or time-zone artefact, not evidence of work not yet done, and letting the exponent
    /// go negative would push the figure above the model's ceiling. The stamp itself is
    /// carried through to `MuscleFatigue.sessionEndedAt` uncorrected — this clamps the
    /// arithmetic, not the record.
    private static func elapsedSeconds(since session: MuscleFatigueSession, now: Date) -> Double {
        max(0, now.timeIntervalSince(session.endedAt))
    }

    private static func decay(
        since session: MuscleFatigueSession,
        now: Date,
        model: MuscleFatigueModel
    ) -> Double {
        pow(0.5, elapsedSeconds(since: session, now: now) / model.halfLifeSeconds)
    }

    private static func fraction(
        of session: MuscleFatigueSession,
        now: Date,
        model: MuscleFatigueModel
    ) -> Double {
        weight(for: session, model: model) * decay(since: session, now: now, model: model)
    }

    private static func reading(
        for group: MuscleGroup,
        session: MuscleFatigueSession,
        mostRecentlyWorkedAt: Date,
        now: Date,
        model: MuscleFatigueModel
    ) throws -> MuscleFatigueReading {
        let fatigue = try MuscleFatigue(
            group: group,
            fraction: fraction(of: session, now: now, model: model),
            sessionEndedAt: session.endedAt,
            mostRecentlyWorkedAt: mostRecentlyWorkedAt,
            elapsedSeconds: elapsedSeconds(since: session, now: now),
            sessionWeight: weight(for: session, model: model)
        )
        // Tested against the decay factor, not the finished figure: a twenty-second
        // session read a minute later is small, not old, and calling it `.fresh` would
        // say "enough time has passed" about something that just happened. See
        // `MuscleFatigueModel.negligibleDecay`.
        return decay(since: session, now: now, model: model) < model.negligibleDecay
            ? .fresh(fatigue)
            : .fatigued(fatigue)
    }

    /// What a session counts for before decay.
    ///
    /// **This is the seam MAX-176 swaps.** When per-workout strain lands, this gains a
    /// branch on `model.weighting` and nothing else in this file moves — see
    /// `MuscleFatigueModel.Weighting`.
    static func weight(for session: MuscleFatigueSession, model: MuscleFatigueModel) -> Double {
        switch model.weighting {
        case .duration:
            return min(session.durationSeconds / model.fullSessionSeconds, 1)
        }
    }
}
