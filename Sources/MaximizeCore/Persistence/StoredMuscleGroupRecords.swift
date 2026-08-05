import Foundation

/// `MuscleGroupEntry` as stored (A22).
///
/// Modelled on `StoredScoreAnnotation`, which is the record this one is a sibling of:
/// its own identifier rather than the workout's, because a workout accumulates entries;
/// no update path, because entries are additive; and a `createdAt`-shaped timestamp,
/// because "the latest one" is the whole resolution rule.
///
/// ## Why the groups are a blob and not a column each
///
/// `PersistencePayload`'s rule is that anything a screen filters, sorts or groups by
/// stays a real column, and everything else may be a blob. Nothing queries by muscle
/// group: the entry is read for one workout at a time, by that workout's identifier,
/// and the two consumers this ticket has (the detail section and the verdict header)
/// both want the whole set. Six boolean columns would buy a query nobody intends to
/// make and would put "chest" in the schema, where adding a seventh group later would
/// be a migration rather than a `MuscleGroup` case.
///
/// The array is canonically ordered (`Set<MuscleGroup>.ordered`) so that an unchanged
/// entry re-encodes to identical bytes — `PersistencePayload` explains why that
/// matters, and `MuscleGroupEntry.encode(to:)` is where the ordering is applied.
public struct StoredMuscleGroupEntry: Hashable, Sendable {
    public var entryUUID: UUID
    public var workoutUUID: UUID

    /// A JSON array of `MuscleGroup` raw values, canonically ordered.
    public var groupsJSON: Data

    public var recordedAt: Date

    public init(
        entryUUID: UUID,
        workoutUUID: UUID,
        groupsJSON: Data,
        recordedAt: Date
    ) {
        self.entryUUID = entryUUID
        self.workoutUUID = workoutUUID
        self.groupsJSON = groupsJSON
        self.recordedAt = recordedAt
    }

    public init(_ entry: MuscleGroupEntry) throws {
        self.init(
            entryUUID: entry.id,
            workoutUUID: entry.workoutID,
            groupsJSON: try PersistencePayload.encode(
                entry.groups.ordered,
                field: "StoredMuscleGroupEntry.groupsJSON"
            ),
            recordedAt: entry.recordedAt
        )
    }

    /// - Note: `MuscleGroup` is a closed enum (see its own documentation on why), so an
    ///   unrecognised raw value is a corrupted or downgraded record rather than a new
    ///   variant to tolerate, and decoding fails loudly — `StoredScore`'s treatment of
    ///   `ScoreBand`, for the same reason. An entry that decoded to a *subset* of what
    ///   the athlete actually said would be worse than one that fails to load: it would
    ///   silently misreport a session, and D8's neighbourhood is the last place to
    ///   invent data.
    public func toDomain() throws -> MuscleGroupEntry {
        let groups: [MuscleGroup] = try PersistencePayload.decode(
            [MuscleGroup].self,
            from: groupsJSON,
            field: "StoredMuscleGroupEntry.groupsJSON"
        )
        return try MuscleGroupEntry(
            id: entryUUID,
            workoutID: workoutUUID,
            groups: Set(groups),
            recordedAt: recordedAt
        )
    }
}
