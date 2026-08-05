import Foundation

/// The working copy of a plan an athlete edits while authoring or revising one
/// (MAX-080).
///
/// ## A draft is not a plan, and that is the point
///
/// D1 says changing a threshold is *a new plan version, never an edit*. The cheapest
/// way to violate that is a screen that binds its controls straight to a stored `Plan`
/// and writes the mutated value back. `Plan`'s properties are all `let`, so that
/// particular spelling does not compile — but a `var` copy assembled inside a view
/// would, and nothing in the type system would notice.
///
/// So the mutable thing is a separate type that **cannot become a plan by itself**.
/// The only door out is `PlanAuthoringSession.plan(from:effectiveFrom:)`, which stamps
/// the next version number and the effective date the session already worked out. There
/// is deliberately no `PlanDraft.plan()`, no `Plan.applying(_ draft:)`, and no way to
/// address an existing version — editing version 2 in place is not an operation this
/// file can express.
///
/// ## What it does not carry
///
/// **The rubric's bands.** A draft holds the two rubric *thresholds* (effective and
/// marginal) because those are single numbers an athlete has an opinion about. The
/// bands themselves — the ordered `metric ≤ cap + 8`-shaped conditions of PRD §10.3 —
/// are carried forward verbatim by `PlanAuthoringSession` from the version being
/// revised, or seeded on a first plan. Editing them needs a structured rule editor,
/// which is its own ticket; carrying them forward means a revision never silently
/// re-seeds a rubric the athlete had already tuned.
///
/// **The version and the effective date.** Both are derived, not chosen: see
/// `PlanAuthoringSession`. A draft that carried them would let a screen offer a version
/// number, and a version number an athlete can type is a back-dated version waiting to
/// happen.
public struct PlanDraft: Hashable, Sendable {

    /// One weekday of the recurring week.
    ///
    /// `kind` and `distanceMeters` are `private(set)` behind `setKind(_:)` because
    /// `ScheduledSession` rejects a rest day carrying a distance — so a screen that set
    /// the two independently could park the draft in a state that only fails at save
    /// time, several controls later, with nothing on screen explaining which tap caused
    /// it. Clearing the distance as part of choosing rest keeps the draft always
    /// convertible.
    public struct DayDraft: Hashable, Sendable, Identifiable {
        public var id: Weekday { weekday }

        public let weekday: Weekday
        public private(set) var kind: ScheduledSessionKind
        /// Prescribed distance in **metres**, or nil where the plan prescribes a
        /// session without one (a hard session described only by its `note`).
        public private(set) var distanceMeters: Double?

        /// Prescribed duration in **seconds** (MAX-131), carried but not editable.
        ///
        /// Carried for the reason `liftSession` is: `PlanDraft.init(_:)` is documented as
        /// lossless, and the run slot is the half that gets decomposed into parts and
        /// reassembled, so any field left out of the decomposition is a field a revision
        /// silently deletes. Nothing authors a duration on a run today, which makes this
        /// carry-forward cheap now and correct later. **MAX-137 gives the screen its
        /// editor**, and with it the setter and the loose-input validation.
        public private(set) var durationSeconds: Double?

        public private(set) var note: String?

        /// The **lift** slot's kind — `.rest` or `.lift`. Nothing else is offered; see
        /// `ScheduledSessionKind.liftPrescribable`.
        public private(set) var liftKind: ScheduledSessionKind
        /// Free text describing the lift — "lower body, 45 minutes" territory, though the
        /// duration itself has its own field below. Editable via `setLiftNote` (MAX-148);
        /// before that it was carried from the stored plan with no way to author one.
        public private(set) var liftNote: String?

        /// The lift's prescribed duration in **seconds**. Editable via
        /// `setLiftDurationSeconds` (MAX-148) — the lift slot's counterpart to the run
        /// slot's `durationSeconds`, which stays carried-but-uneditable (nothing prescribes
        /// a run's length today; LIFTING-SPEC §3.5 gave the lift slot the reason to need
        /// one first: A20 scores a lift on whether the session happened, and duration is
        /// the only part of that judgement the record can measure).
        public private(set) var liftDurationSeconds: Double?
        /// What the lift is for. Empty while `.lift` is a real, distinct state — "a
        /// lift with no groups named" — from `liftKind == .rest`, "no lift". See
        /// `liftSummary`.
        public private(set) var liftMuscleGroups: Set<MuscleGroup>

        public init(weekday: Weekday, session: ScheduledSession, liftSession: ScheduledSession = .rest) {
            self.weekday = weekday
            self.kind = session.kind
            self.distanceMeters = session.distanceMeters
            self.durationSeconds = session.durationSeconds
            self.note = session.note
            self.liftKind = liftSession.kind
            self.liftNote = liftSession.note
            self.liftDurationSeconds = liftSession.durationSeconds
            self.liftMuscleGroups = liftSession.muscleGroups
        }

        /// Ignored for `.lift` (MAX-148): the run slot's vocabulary is
        /// `ScheduledSessionKind.prescribable`, which excludes it, for the reason that
        /// type's own doc gives — a lift prescribed where the run ask goes would be
        /// judged against a lift ask, the exact cross-discipline mistake A17 exists to
        /// rule out. `setLiftKind` is the run slot's way to reach the lift ask. Before
        /// this ticket the rule lived only in the screen's picker, which offered nothing
        /// else; enforcing it here means `PlanDraft` itself cannot express the mistake,
        /// independent of what a future picker offers.
        public mutating func setKind(_ kind: ScheduledSessionKind) {
            guard ScheduledSessionKind.prescribable.contains(kind) else { return }
            self.kind = kind
            if kind == .rest {
                distanceMeters = nil
                durationSeconds = nil
                note = nil
            }
        }

        /// Ignored on a rest day — see the type's note on why the two move together.
        public mutating func setDistanceMeters(_ meters: Double?) {
            guard kind != .rest else { return }
            distanceMeters = meters
        }

        /// Ignored on a rest day, for the same reason: `ScheduledSession.rest` is the
        /// canonical empty rest day and a note attached to one would be dropped anyway.
        public mutating func setNote(_ note: String?) {
            guard kind != .rest else { return }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }

        /// - Throws: `DomainError` when the pair the athlete assembled is not a legal
        ///   session — a non-positive distance, essentially, since `setKind` already
        ///   rules out rest-with-distance.
        public func session() throws -> ScheduledSession {
            try ScheduledSession(
                kind: kind,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                note: note
            )
        }

        /// Sets the lift slot's kind. Choosing anything but `.lift` clears the groups
        /// the same way choosing rest on the run slot clears its distance and note —
        /// `ScheduledSession` rejects muscle groups on a non-lift kind, and clearing
        /// here keeps the draft always convertible instead of parking an illegal
        /// combination until save time.
        public mutating func setLiftKind(_ kind: ScheduledSessionKind) {
            liftKind = kind
            if kind != .lift {
                liftMuscleGroups = []
                // Cleared for the same reason the groups are, and it is not optional:
                // `ScheduledSession` rejects a rest day carrying a duration outright, so
                // a value left behind here would make `liftSession()` throw on a draft
                // the athlete reached through this type's own setters.
                liftDurationSeconds = nil
                // Cleared for a softer reason (MAX-148): `ScheduledSession` does not
                // reject a rest day carrying a note, but "no lift" saying something
                // about a lift makes no sense to read, and the run slot's own `setKind`
                // clears its note on the same transition for the same reason.
                liftNote = nil
            }
        }

        /// Sets the lift's prescribed duration in seconds (MAX-148). Ignored while the
        /// slot is not `.lift`, for the same reason `setLiftMuscleGroups` is ignored on a
        /// rest lift: there is nowhere legal for the value to go, and `ScheduledSession`
        /// rejects a rest day carrying a duration outright.
        public mutating func setLiftDurationSeconds(_ seconds: Double?) {
            guard liftKind == .lift else { return }
            liftDurationSeconds = seconds
        }

        /// Sets the lift's free-text note (MAX-148) — the lift slot's `setNote`. Ignored
        /// while the slot is not `.lift`, and blank text collapses to `nil` the same way
        /// `setNote` does for the run slot.
        public mutating func setLiftNote(_ note: String?) {
            guard liftKind == .lift else { return }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            liftNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }

        /// Replaces the lift's muscle groups outright. Ignored while the slot is not
        /// `.lift`, for the same reason `setDistanceMeters` is ignored on a rest day:
        /// there is nowhere legal for the value to go.
        public mutating func setLiftMuscleGroups(_ groups: Set<MuscleGroup>) {
            guard liftKind == .lift else { return }
            liftMuscleGroups = groups
        }

        /// Adds or removes one group — what a checklist-style control actually calls.
        public mutating func toggleLiftMuscleGroup(_ group: MuscleGroup) {
            guard liftKind == .lift else { return }
            if liftMuscleGroups.contains(group) {
                liftMuscleGroups.remove(group)
            } else {
                liftMuscleGroups.insert(group)
            }
        }

        /// The lift ask this draft would save.
        ///
        /// Never expected to throw in practice: `setLiftKind` already clears the groups
        /// the moment the kind leaves `.lift`, so the one combination `ScheduledSession`
        /// rejects — groups on a non-lift kind — cannot be reached through this type's
        /// own setters. `throws` anyway, the same belt-and-braces reasoning
        /// `PlanAuthoringError.wouldRewriteHistory` documents: the alternative to a
        /// defensive case is a `try!`, which non-test code may not write.
        public func liftSession() throws -> ScheduledSession {
            try ScheduledSession(
                kind: liftKind,
                durationSeconds: liftDurationSeconds,
                note: liftNote,
                muscleGroups: liftMuscleGroups
            )
        }

        /// The lift slot's ask, in the vocabulary that keeps "no lift" and "a lift with
        /// no groups named" distinct (A17). What a screen reads to decide what the
        /// empty state says, rather than switching on `liftKind`/`liftMuscleGroups`
        /// itself — see `LiftPrescriptionSummary`'s note on why this exists.
        public var liftSummary: LiftPrescriptionSummary {
            LiftPrescriptionSummary(kind: liftKind, muscleGroups: liftMuscleGroups)
        }

        /// Whether the weekday carries a run ask, a lift ask, both, or neither — the
        /// fact a scannable week view leads with, before either slot's own detail
        /// (MAX-137: "a person checking seven days of two slots wants to see the week
        /// at once").
        ///
        /// The shared `ObligationSummary`, not a nested twin: a week mid-edit and a
        /// stored governing week answer the same question, and MAX-138 unified the two
        /// so they cannot drift.
        public var obligationSummary: ObligationSummary {
            ObligationSummary(runKind: kind, liftKind: liftKind)
        }
    }

    /// One week of the long-run arc.
    ///
    /// `index` is fixed at construction: the arc's weeks must stay strictly ascending
    /// and unique (`LongRunArc`), and an editable index is the one field that can break
    /// both. Weeks are added and removed at the end instead.
    public struct ArcWeekDraft: Hashable, Sendable, Identifiable {
        public var id: Int { index }

        public let index: Int
        public var distanceMeters: Double

        public init(index: Int, distanceMeters: Double) {
            self.index = index
            self.distanceMeters = distanceMeters
        }
    }

    /// Easy-run heart-rate ceiling in **beats per minute** (FR-1.2).
    public var heartRateCapBPM: Double
    public var cadenceLowStepsPerMinute: Double
    public var cadenceHighStepsPerMinute: Double
    /// Score at or above which a day counts as effective (§10.4).
    public var effectiveThresholdPoints: Int
    /// Score at or above which a day is marginal rather than ineffective.
    public var marginalThresholdPoints: Int
    /// The athlete's goals, one per line, as narrative context for the scorer and chat
    /// (`PlanGoals`). Blank lines are dropped when the plan is built.
    public var goalStatements: String
    public var goalTargetDay: CalendarDay?

    /// Exactly seven entries, Monday-first, matching `WeeklyTemplate`'s own ordering.
    public private(set) var week: [DayDraft]

    /// At least one week, ascending by index.
    public private(set) var longRunArc: [ArcWeekDraft]

    /// - Parameters:
    ///   - weeklySessions: any weekday left out defaults to rest, so a caller cannot
    ///     accidentally produce a partial week — `WeeklyTemplate` rejects one, and the
    ///     rejection would surface at save time rather than here.
    ///   - liftSessions: the lift slot's starting ask, decomposed per weekday into
    ///     `DayDraft.liftKind` / `.liftMuscleGroups` (and a carried, unedited
    ///     `.liftNote` — see that property). A weekday left out is rest, matching
    ///     `WeeklyTemplate`'s own default.
    ///   - longRunArcWeeks: must be non-empty and strictly ascending by index, the same
    ///     rule `LongRunArc` enforces. Checked here so a draft is always convertible.
    public init(
        heartRateCapBPM: Double,
        cadenceLowStepsPerMinute: Double,
        cadenceHighStepsPerMinute: Double,
        effectiveThresholdPoints: Int,
        marginalThresholdPoints: Int,
        weeklySessions: [Weekday: ScheduledSession],
        longRunArcWeeks: [ArcWeekDraft],
        liftSessions: [Weekday: ScheduledSession] = [:],
        goalStatements: String = "",
        goalTargetDay: CalendarDay? = nil
    ) throws {
        guard !longRunArcWeeks.isEmpty else {
            throw DomainError.empty(field: "PlanDraft.longRunArc")
        }
        for position in longRunArcWeeks.indices.dropFirst()
        where longRunArcWeeks[position].index <= longRunArcWeeks[position - 1].index {
            throw DomainError.outOfOrder(field: "PlanDraft.longRunArc", index: position)
        }

        self.heartRateCapBPM = heartRateCapBPM
        self.cadenceLowStepsPerMinute = cadenceLowStepsPerMinute
        self.cadenceHighStepsPerMinute = cadenceHighStepsPerMinute
        self.effectiveThresholdPoints = effectiveThresholdPoints
        self.marginalThresholdPoints = marginalThresholdPoints
        self.goalStatements = goalStatements
        self.goalTargetDay = goalTargetDay
        self.week = Weekday.allCases.sorted().map {
            DayDraft(
                weekday: $0,
                session: weeklySessions[$0] ?? .rest,
                liftSession: liftSessions[$0] ?? .rest
            )
        }
        self.longRunArc = longRunArcWeeks
    }

    /// The draft that reproduces `plan` exactly.
    ///
    /// Lossless for everything a draft carries, which matters more than it sounds:
    /// revising a plan starts from this, so any field this initializer dropped would be
    /// silently reset to a default the next time the athlete changed the HR cap.
    public init(_ plan: Plan) throws {
        var sessions: [Weekday: ScheduledSession] = [:]
        var liftSessions: [Weekday: ScheduledSession] = [:]
        for entry in plan.weeklyTemplate.entries {
            sessions[entry.weekday] = entry.session
            liftSessions[entry.weekday] = entry.liftSession
        }
        try self.init(
            heartRateCapBPM: plan.heartRateCapBPM,
            cadenceLowStepsPerMinute: plan.cadenceTarget.lowStepsPerMinute,
            cadenceHighStepsPerMinute: plan.cadenceTarget.highStepsPerMinute,
            effectiveThresholdPoints: plan.rubric.effectiveThreshold.points,
            marginalThresholdPoints: plan.rubric.marginalThreshold.points,
            weeklySessions: sessions,
            longRunArcWeeks: plan.longRunArc.weeks.map {
                ArcWeekDraft(index: $0.index, distanceMeters: $0.distanceMeters)
            },
            liftSessions: liftSessions,
            goalStatements: plan.goals.statements.joined(separator: "\n"),
            goalTargetDay: plan.goals.targetDay
        )
    }

    // MARK: - Applying a model's proposal (MAX-101)

    /// The draft this one becomes once a model's proposal is applied to it
    /// (CHAT-FIRST-SPEC.md §4.1, A13).
    ///
    /// ## It applies. It does not store. That is the whole of A13.
    ///
    /// A13 names the near-miss in this exact place: *"a helper that applies a proposal
    /// to a draft **and also stores it**. Applying is fine. Storing is D1's door, and it
    /// opens by hand."* So this returns a value and nothing else. It touches no
    /// repository, produces no `Plan`, and cannot: a `PlanDraft` still has no
    /// `plan()` of its own, and `PlanAuthoringSession.plan(from:effectiveFrom:)` is
    /// still the only door — reached only after the athlete has reviewed the card and
    /// tapped through the authoring screen.
    ///
    /// ## Why it is an instance method rather than an initializer
    ///
    /// Because of the one field a proposal still cannot touch. The run slot's
    /// `durationSeconds` stays carried-but-uneditable (`durationSeconds` since MAX-131 —
    /// nothing prescribes a run's length yet), so `PlanProposal` has no wire field for it
    /// and this mapping has to carry it forward from *somewhere*. An initializer taking
    /// only a proposal would have nothing to carry it forward *from*. Applying *onto* the
    /// draft the athlete is revising is what gives this method something to carry it
    /// from — see `carriedDurationSeconds(from:proposing:)` below.
    ///
    /// **The lift slot has no such exception as of MAX-148.** `PlanProposal`'s lift slot
    /// now carries a kind, muscle groups, a duration and a note — matching exactly what
    /// `PlanDraft.DayDraft`'s own setters expose (`setLiftKind`, `setLiftMuscleGroups`,
    /// `setLiftDurationSeconds`, `setLiftNote`) — so every one of its fields is replaced
    /// outright from the proposal, the same as the run slot's kind, distance and note
    /// always have been.
    ///
    /// Everything else is replaced outright rather than merged: the proposal is a whole
    /// plan, not a patch, and `PlanProposalInstruction` tells the model exactly that —
    /// "prescribe the whole week, every time", both slots. A weekday the proposal does
    /// not restate a lift for reverts to rest, the same totality rule `WeeklyTemplate`
    /// itself applies. A field-by-field merge here would be a second opinion about what
    /// the model meant to change.
    ///
    /// - Throws: `DomainError` only for the shapes `PlanDraft.init` itself refuses; a
    ///   parsed `PlanProposal` cannot express one (its arc is non-empty and strictly
    ///   ascending by construction), so this is belt-and-braces rather than a case a
    ///   caller has to design around — see `PlanProposalTests`' "a proposal that parses
    ///   is one the storage door accepts."
    public func applying(_ proposal: PlanProposal) throws -> PlanDraft {
        var sessions: [Weekday: ScheduledSession] = [:]
        var liftSessions: [Weekday: ScheduledSession] = [:]
        for day in week {
            let proposed = proposal[day.weekday]
            sessions[day.weekday] = try ScheduledSession(
                kind: proposed.kind,
                distanceMeters: proposed.distanceMeters,
                durationSeconds: carriedDurationSeconds(from: day, proposing: proposed),
                note: proposed.note
            )
            let proposedLift = proposal.liftSession(for: day.weekday)
            liftSessions[day.weekday] = try ScheduledSession(
                kind: proposedLift.kind,
                durationSeconds: proposedLift.durationSeconds,
                note: proposedLift.note,
                muscleGroups: proposedLift.muscleGroups
            )
        }
        return try PlanDraft(
            heartRateCapBPM: proposal.heartRateCapBPM,
            cadenceLowStepsPerMinute: proposal.cadenceLowStepsPerMinute,
            cadenceHighStepsPerMinute: proposal.cadenceHighStepsPerMinute,
            effectiveThresholdPoints: proposal.effectiveThresholdPoints,
            marginalThresholdPoints: proposal.marginalThresholdPoints,
            weeklySessions: sessions,
            longRunArcWeeks: proposal.longRunArc.map {
                ArcWeekDraft(index: $0.index, distanceMeters: $0.distanceMeters)
            },
            liftSessions: liftSessions,
            // `PlanProposal` has already applied the same normalisation
            // `PlanAuthoringSession.goals(from:)` performs, so joining and re-splitting
            // is a round trip through the draft's own newline-joined shape rather than a
            // second opinion about what a goal statement is.
            goalStatements: proposal.goalStatements.joined(separator: "\n"),
            goalTargetDay: proposal.goalTargetDay
        )
    }

    /// A prescribed run duration the proposal could not have expressed, kept when it is
    /// still about the same session and dropped when it is not (MAX-131, MAX-101).
    ///
    /// `ScheduledSession.durationSeconds` is carried-but-uneditable on the run slot, and
    /// `PlanProposal` has no field for it — so applying a proposal naively would silently
    /// delete a "45 minutes easy" the athlete never had the chance to keep, which is the
    /// exact failure `durationSeconds`' own documentation warns a revision must not
    /// commit.
    ///
    /// **Only while the kind is unchanged.** A duration is a property of the ask, so it
    /// survives the proposal editing that day's distance or note. It does not survive the
    /// proposal *replacing* the session: carrying 45 minutes from a deleted easy run onto
    /// a newly proposed hard session would be this mapping asserting something no one
    /// said. A rest day cannot carry one at all, and a rest-to-rest day never has one to
    /// carry (`setKind` clears it), so the illegal combination `ScheduledSession` refuses
    /// is unreachable here.
    private func carriedDurationSeconds(
        from day: DayDraft,
        proposing proposed: ScheduledSession
    ) -> Double? {
        guard proposed.kind == day.kind else { return nil }
        return day.durationSeconds
    }

    // MARK: - Editing the week

    /// Total by construction: the initializer fills every weekday.
    public subscript(weekday: Weekday) -> DayDraft {
        for day in week where day.weekday == weekday {
            return day
        }
        // Unreachable: `init` writes all seven days.
        return DayDraft(weekday: weekday, session: .rest)
    }

    public mutating func setKind(_ kind: ScheduledSessionKind, on weekday: Weekday) {
        mutateDay(weekday) { $0.setKind(kind) }
    }

    public mutating func setDistanceMeters(_ meters: Double?, on weekday: Weekday) {
        mutateDay(weekday) { $0.setDistanceMeters(meters) }
    }

    public mutating func setNote(_ note: String?, on weekday: Weekday) {
        mutateDay(weekday) { $0.setNote(note) }
    }

    // MARK: - Editing the lift slot (MAX-137)

    public mutating func setLiftKind(_ kind: ScheduledSessionKind, on weekday: Weekday) {
        mutateDay(weekday) { $0.setLiftKind(kind) }
    }

    public mutating func setLiftMuscleGroups(_ groups: Set<MuscleGroup>, on weekday: Weekday) {
        mutateDay(weekday) { $0.setLiftMuscleGroups(groups) }
    }

    public mutating func toggleLiftMuscleGroup(_ group: MuscleGroup, on weekday: Weekday) {
        mutateDay(weekday) { $0.toggleLiftMuscleGroup(group) }
    }

    public mutating func setLiftDurationSeconds(_ seconds: Double?, on weekday: Weekday) {
        mutateDay(weekday) { $0.setLiftDurationSeconds(seconds) }
    }

    public mutating func setLiftNote(_ note: String?, on weekday: Weekday) {
        mutateDay(weekday) { $0.setLiftNote(note) }
    }

    private mutating func mutateDay(_ weekday: Weekday, _ transform: (inout DayDraft) -> Void) {
        for position in week.indices where week[position].weekday == weekday {
            transform(&week[position])
        }
    }

    // MARK: - Editing the arc

    public mutating func setLongRunDistanceMeters(_ meters: Double, forWeek index: Int) {
        for position in longRunArc.indices where longRunArc[position].index == index {
            longRunArc[position].distanceMeters = meters
        }
    }

    /// Appends the next week, repeating the final week's distance.
    ///
    /// This is how a plan whose arc has run out gets extended — `PlanCalendar` documents
    /// that case as "a plan that wants a new version", and this is the edit that makes
    /// the new version worth authoring.
    public mutating func appendLongRunWeek() {
        guard let last = longRunArc.last else { return }
        longRunArc.append(ArcWeekDraft(index: last.index + 1, distanceMeters: last.distanceMeters))
    }

    /// Removes the final week, never the last remaining one: `LongRunArc` rejects an
    /// empty arc, so allowing it here would make the draft unconvertible with no
    /// obvious way back.
    public mutating func removeLastLongRunWeek() {
        guard longRunArc.count > 1 else { return }
        longRunArc.removeLast()
    }

    /// A straight ramp from `firstWeekDistanceMeters` to `peakWeekDistanceMeters` over
    /// `weekCount` weeks, rounded to the nearest 100 m.
    ///
    /// Deliberately the simplest progression that exists rather than a periodised one
    /// with cutback weeks. Which weeks to cut back, and by how much, is a *training*
    /// decision this package has no standing to make on the athlete's behalf; a
    /// straight ramp is legible enough that an athlete can see it is a starting point
    /// and edit the weeks that are wrong. Per-week distances stay editable precisely so
    /// the ramp never has to be right.
    public static func rampedArc(
        firstWeekDistanceMeters: Double,
        peakWeekDistanceMeters: Double,
        weekCount: Int
    ) throws -> [ArcWeekDraft] {
        try Validate.positive(firstWeekDistanceMeters, "PlanDraft.rampedArc.firstWeekDistanceMeters")
        try Validate.positive(peakWeekDistanceMeters, "PlanDraft.rampedArc.peakWeekDistanceMeters")
        guard weekCount >= 1 else {
            throw DomainError.outOfRange(
                field: "PlanDraft.rampedArc.weekCount",
                value: Double(weekCount),
                lowerBound: 1,
                upperBound: nil
            )
        }
        guard weekCount > 1 else {
            return [ArcWeekDraft(index: 1, distanceMeters: peakWeekDistanceMeters)]
        }
        let span = peakWeekDistanceMeters - firstWeekDistanceMeters
        return (1...weekCount).map { index in
            let fraction = Double(index - 1) / Double(weekCount - 1)
            let raw = firstWeekDistanceMeters + span * fraction
            return ArcWeekDraft(index: index, distanceMeters: (raw / 100).rounded() * 100)
        }
    }
}
