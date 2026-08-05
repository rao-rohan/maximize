import Foundation

/// The athlete's training over an inclusive, **already-resolved** range of days.
///
/// ## Why this is two `CalendarDay`s and not a `TrendInterval`
///
/// A `TrendInterval` is a *rule* — "this week", "this month" — and a rule re-resolves.
/// A thread's scope must not (§3.4, A11): a conversation is about a bounded set of
/// facts, and a window that slid with the calendar would make last Tuesday's answer cite
/// runs that are no longer in context, so scrolling up your own transcript would show
/// the assistant contradicting the app.
///
/// So the freezing is done by the type rather than by a convention somebody has to
/// remember. `init(resolving:)` is the one door in from a `TrendInterval`, it converts
/// to absolute days on the way through, and there is deliberately **no way back out** —
/// nothing on this type can hand you the interval it came from, because a caller holding
/// one would be a caller that could re-resolve it.
///
/// `TrainingScope` is what makes "New chat" a real action rather than a nicety: a newer
/// window is a different conversation, and this is the value that differs.
public struct TrainingScope: Hashable, Sendable, Codable {
    /// Inclusive lower bound. Same vocabulary as `TrendInterval.from`, `TalliesInput`
    /// and `PlanCalendar.planDays(from:through:)`, so a scope drops straight into every
    /// core function a training context will need (A12's "no arithmetic in a context").
    public let from: CalendarDay

    /// Inclusive upper bound.
    public let through: CalendarDay

    public init(from: CalendarDay, through: CalendarDay) throws {
        guard from <= through else {
            throw DomainError.inconsistent(
                reason: "TrainingScope.from (\(from)) must not be later than through (\(through))"
            )
        }
        self.from = from
        self.through = through
    }

    /// Freezes the dashboard's current selection into absolute days.
    ///
    /// The scope is inherited from the app's existing interval control rather than
    /// picked in a second control inside the chat sheet — two notions of "what period
    /// are we talking about" is the same class of mistake D2 and D3 exist to prevent
    /// (§3.4).
    public init(resolving interval: TrendInterval) throws {
        try self.init(from: interval.from, through: interval.through)
    }

    /// "28 Dec 2025 – 3 Jan 2026". The window, stated — which §3.6(b) requires wherever
    /// a frozen scope could be mistaken for the dashboard's current one.
    public var label: String {
        CalendarDayLabel.range(from: from, through: through)
    }

    private enum CodingKeys: String, CodingKey {
        case from, through
    }

    // Written out rather than synthesised so a decoded scope goes through the same
    // ordering check a constructed one does. A synthesised `init(from:)` would let a
    // hand-edited or corrupted payload produce an inverted range that every consumer
    // downstream would silently read as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            from: container.decode(CalendarDay.self, forKey: .from),
            through: container.decode(CalendarDay.self, forKey: .through)
        )
    }
}

/// Which shape a `ChatSubject` is, without its payload.
///
/// Exists so the persistence layer has a stable discriminator to store as a column
/// (MAX-093) rather than reaching into the enum, and so a thread list can pick a glyph
/// (§2.3) without switching over identifiers it does not need.
public enum ChatSubjectKind: String, Hashable, Sendable, Codable, CaseIterable {
    case workout
    case training
}

/// What a chat thread is about (A11).
///
/// Thread identity is the thread's own id; this is what decides **which pile of the
/// athlete's data enters a prompt**. That is the whole reason the type exists, and it is
/// why the set is closed: A12 makes adding a third subject an amendment, not a ticket,
/// because every subject is a new answer to "what health data leaves the device", and
/// that question is not one a ticket should be able to answer on its own.
///
/// Being closed is also what lets `ContextBuilder.build(for:)` (MAX-095) stay exhaustive
/// — a new case cannot be added without the compiler demanding a context for it.
public enum ChatSubject: Hashable, Sendable, Codable {
    /// One run. The workout link is now a field of a case rather than the thread's
    /// identity — which is exactly what A11 supersedes in D6.
    case workout(UUID)

    /// The athlete's training over a resolved, frozen range of days.
    case training(TrainingScope)

    public var kind: ChatSubjectKind {
        switch self {
        case .workout: return .workout
        case .training: return .training
        }
    }

    /// The run this thread is about, or nil for a training thread.
    ///
    /// Deliberately optional and deliberately not called `workoutID` on `ChatThread`:
    /// a caller that wants "the workout" has to say what it does when there isn't one.
    public var workoutID: UUID? {
        switch self {
        case let .workout(id): return id
        case .training: return nil
        }
    }

    /// The frozen day range this thread is about, or nil for a workout thread.
    public var trainingScope: TrainingScope? {
        switch self {
        case .workout: return nil
        case let .training(scope): return scope
        }
    }

    // MARK: - Codable

    // A tagged wire form with an explicit discriminator, rather than Swift's synthesised
    // enum encoding, for the same reason `CalendarDay` pins `YYYY-MM-DD`: this shape is
    // about to be split across columns by MAX-093 (`subjectKind`, an optional workout
    // identifier, two optional day strings), and the stored record and the JSON payload
    // must not be able to disagree about what a subject is. The key names below are
    // therefore the column names.
    private enum CodingKeys: String, CodingKey {
        case kind, workoutID, from, through
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .workout(id):
            try container.encode(id, forKey: .workoutID)
        case let .training(scope):
            try container.encode(scope.from, forKey: .from)
            try container.encode(scope.through, forKey: .through)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ChatSubjectKind.self, forKey: .kind)
        switch kind {
        case .workout:
            self = .workout(try container.decode(UUID.self, forKey: .workoutID))
        case .training:
            self = .training(try TrainingScope(
                from: container.decode(CalendarDay.self, forKey: .from),
                through: container.decode(CalendarDay.self, forKey: .through)
            ))
        }
    }
}
