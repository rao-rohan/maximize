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
    /// right**: only the most recent session per group is read, so a window that is too
    /// short can only make a group read as *never logged* when it was logged before the
    /// window. Fetch at least `MuscleFatigueModel.negligibleFraction`'s worth of curve —
    /// a fortnight covers the standard model — or simply fetch the lifts you already
    /// have.
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
/// For each group, the **most recent** session that named it:
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
/// better supported. The floor at `negligibleFraction` is where the exponential's tail
/// stops being reported as fatigue; the figure underneath it is still carried, so
/// ordering survives.
///
/// **Only the last session counts.** Three leg days in four read as the last of them.
/// Accumulating them was declined for MAX-179: the sum's scale is anchored to nothing
/// measured, and the model's own weight is already a proxy standing in for work nobody
/// recorded. See `MuscleFatigue` for the full list of what this cannot know.
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
        for (group, session) in lastSessionByGroup(input.sessions) {
            readings[group] = try reading(
                for: group,
                session: session,
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

    /// The session each group is measured from: the latest one naming it.
    ///
    /// Ties are broken deterministically — longer session first, then by identifier —
    /// because two sessions can share an end instant (a re-recorded workout, a fixture)
    /// and a map that redrew itself differently on each launch would be a bug nobody
    /// could reproduce.
    private static func lastSessionByGroup(
        _ sessions: [MuscleFatigueSession]
    ) -> [MuscleGroup: MuscleFatigueSession] {
        var latest: [MuscleGroup: MuscleFatigueSession] = [:]
        for session in sessions {
            for group in session.groups {
                guard let held = latest[group] else {
                    latest[group] = session
                    continue
                }
                if isLater(session, than: held) {
                    latest[group] = session
                }
            }
        }
        return latest
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

    private static func reading(
        for group: MuscleGroup,
        session: MuscleFatigueSession,
        now: Date,
        model: MuscleFatigueModel
    ) throws -> MuscleFatigueReading {
        // Clamped rather than signed: a session whose end stamp is in the future is a
        // clock or time-zone artefact, not evidence of work not yet done, and letting
        // the exponent go negative would push the figure above the model's ceiling.
        let elapsedSeconds = max(0, now.timeIntervalSince(session.endedAt))
        let sessionWeight = weight(for: session, model: model)
        let decay = pow(0.5, elapsedSeconds / model.halfLifeSeconds)
        let fatigue = try MuscleFatigue(
            group: group,
            fraction: sessionWeight * decay,
            lastWorkedAt: session.endedAt,
            elapsedSeconds: elapsedSeconds,
            sessionWeight: sessionWeight
        )
        return fatigue.fraction < model.negligibleFraction
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
