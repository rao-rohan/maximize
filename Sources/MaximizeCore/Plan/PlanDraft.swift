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
        public private(set) var note: String?

        /// The **lift** slot's ask, carried verbatim (A17).
        ///
        /// Not decomposed into kind/distance/note the way the run slot is, and not
        /// editable here, because nothing on the authoring screen can edit it yet —
        /// MAX-137 is the ticket that gives the screen its second row set, and a
        /// decomposition with no editor is a shape chosen before its use is known.
        ///
        /// It is carried because `PlanDraft.init(_:)` is documented as lossless and
        /// this is the first field that could have made that untrue: a revision that
        /// dropped it would silently delete a lifting prescription the next time the
        /// athlete changed their HR cap. A17 leans on exactly that carry-forward when
        /// it argues one plan record rather than two.
        public private(set) var liftSession: ScheduledSession

        public init(weekday: Weekday, session: ScheduledSession, liftSession: ScheduledSession = .rest) {
            self.weekday = weekday
            self.kind = session.kind
            self.distanceMeters = session.distanceMeters
            self.note = session.note
            self.liftSession = liftSession
        }

        public mutating func setKind(_ kind: ScheduledSessionKind) {
            self.kind = kind
            if kind == .rest {
                distanceMeters = nil
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
            try ScheduledSession(kind: kind, distanceMeters: distanceMeters, note: note)
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
    ///   - liftSessions: the lift slot, carried but not edited — see `DayDraft
    ///     .liftSession`. A weekday left out is rest, matching `WeeklyTemplate`'s own
    ///     default.
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
