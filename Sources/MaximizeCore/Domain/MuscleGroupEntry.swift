import Foundation

/// What the athlete says a strength session actually worked (A22).
///
/// ## Why this is a record beside the workout, not a field on it
///
/// `Workout` mirrors what HealthKit reported and nothing else writes to it. This is
/// athlete-supplied truth *about* a session, which is the shape `ScoreAnnotation`
/// already has — a separate, timestamped record keyed by its own identifier, additive,
/// never overwriting what was captured. Putting it on `Workout` would make that record
/// two things at once: a mirror of the health store and a place the app edits.
///
/// The discipline is `ScoreAnnotation`'s applied to an *input* rather than to a verdict.
/// A22 spends PRD §3's manual-entry non-goal for exactly one field on exactly one kind
/// of workout; keeping it out of `Workout` is what stops that permission leaking into
/// "the app can edit a captured session."
///
/// ## Changing what you said is a new entry
///
/// There is no mutating API and no `updating(_:)`. Correcting Tuesday from *chest* to
/// *chest and shoulders* appends a second entry; `MuscleGroupLog` resolves the latest
/// one as the answer in force and keeps the earlier one on record. That costs nothing
/// and it means the history of what the athlete said is never destroyed by the athlete
/// saying something else — the same reasoning D8 gives for corrections to a score.
///
/// ## `groups` is never empty
///
/// **"I have not told you yet" is not "I trained nothing"** (A22), and only the first
/// prompts. The first is the *absence of an entry* — a `MuscleGroupLog` with nothing in
/// it. If an empty set were also representable here, the two would be one state wearing
/// two spellings, and the prompt that makes the whole feature discoverable would fire on
/// a session the athlete had already answered for. So an empty set is rejected at the
/// initializer and the distinction is carried by the type rather than by a convention.
public struct MuscleGroupEntry: Hashable, Sendable, Codable, Identifiable {
    /// The record's own identity, not the workout's — a workout accumulates entries
    /// over time, exactly as it accumulates `ScoreAnnotation`s.
    public let id: UUID

    public let workoutID: UUID

    /// Never empty — see the type note. A set rather than one group because a real
    /// session is rarely one, which is the same reason `ScheduledSession.muscleGroups`
    /// is a set.
    public let groups: Set<MuscleGroup>

    /// When the athlete said it. What makes "the latest answer" a question with an
    /// answer, and what keeps the superseded ones ordered behind it.
    public let recordedAt: Date

    public init(
        id: UUID,
        workoutID: UUID,
        groups: Set<MuscleGroup>,
        recordedAt: Date
    ) throws {
        guard !groups.isEmpty else {
            throw DomainError.empty(field: "MuscleGroupEntry.groups")
        }
        self.id = id
        self.workoutID = workoutID
        self.groups = groups
        self.recordedAt = recordedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, workoutID, groups, recordedAt
    }

    /// Written as a **canonically ordered array**, for `ScheduledSession`'s reason: a
    /// `Set`'s iteration order is not stable, and `PersistencePayload` leans on an
    /// unchanged value re-encoding to identical bytes.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workoutID, forKey: .workoutID)
        try container.encode(groups.ordered, forKey: .groups)
        try container.encode(recordedAt, forKey: .recordedAt)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            groups: Set(container.decode([MuscleGroup].self, forKey: .groups)),
            recordedAt: container.decode(Date.self, forKey: .recordedAt)
        )
    }
}

/// Everything the athlete has said about one workout's muscle groups, newest last —
/// the shape `ScoreLedger` already has, made explicit so no consumer can read half of
/// it.
///
/// An **empty log is the ordinary starting state**, not a failure and not a missing
/// value: it is a session the athlete has not answered for yet, which is precisely the
/// state that prompts (A22). That is why this type is returned whole rather than as an
/// optional entry — the absence has a name here (`isAwaitingEntry`) instead of being a
/// nil every caller has to interpret for itself.
public struct MuscleGroupLog: Hashable, Sendable {
    public let workoutID: UUID

    /// Ascending by `recordedAt`; the last one is the answer in force.
    public let entries: [MuscleGroupEntry]

    public init(workoutID: UUID, entries: [MuscleGroupEntry] = []) throws {
        for (index, entry) in entries.enumerated() {
            guard entry.workoutID == workoutID else {
                throw DomainError.inconsistent(
                    reason: "MuscleGroupLog entry \(entry.id) belongs to a different workout"
                )
            }
            if index > 0, entry.recordedAt < entries[index - 1].recordedAt {
                throw DomainError.outOfOrder(field: "MuscleGroupLog.entries", index: index)
            }
        }
        self.workoutID = workoutID
        self.entries = entries
    }

    /// The answer in force, or nil if the athlete has not given one.
    public var current: MuscleGroupEntry? { entries.last }

    /// The groups in force. Never an empty set: `MuscleGroupEntry` forbids one, so nil
    /// here means "not told yet" and nothing else.
    public var currentGroups: Set<MuscleGroup>? { current?.groups }

    /// Whether this workout is still waiting on the athlete.
    public var isAwaitingEntry: Bool { entries.isEmpty }

    /// Additive by construction: the returned log carries every earlier entry, and
    /// there is no path in this type that replaces one.
    public func recording(_ entry: MuscleGroupEntry) throws -> MuscleGroupLog {
        try MuscleGroupLog(workoutID: workoutID, entries: entries + [entry])
    }
}
