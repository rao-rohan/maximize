import Foundation

/// One anchored read of the health store.
///
/// Everything the platform adapter needs to build its query, and nothing it needs to
/// decide. The three fields correspond to the three questions the core answers about a
/// fetch — where to resume from, how far back a first fetch may reach, and how much to
/// return at once — and all three are answered in `AnchoredWorkoutIngester`.
public struct WorkoutFetchRequest: Hashable, Sendable {
    /// Resume point. `nil` means "no anchor has ever been stored, read from the
    /// beginning", which is the only case in which `earliestWorkoutStart` applies.
    public let anchor: WorkoutQueryAnchor?

    /// The oldest workout start the fetch may return, or `nil` for no lower bound.
    ///
    /// Only ever set on an unanchored fetch. Once an anchor exists it is the anchor
    /// that bounds the volume, and a date bound would then be actively harmful: a
    /// workout that syncs late but started before the bound would be filtered out while
    /// the anchor still advanced past it, which is silent loss.
    public let earliestWorkoutStart: Date?

    /// Maximum number of objects the fetch may return. The adapter passes this straight
    /// to the platform query's limit; the core uses it to recognise a full batch and ask
    /// for another.
    public let batchLimit: Int

    public init(anchor: WorkoutQueryAnchor?, earliestWorkoutStart: Date?, batchLimit: Int) throws {
        guard batchLimit >= 1 else {
            throw DomainError.outOfRange(
                field: "WorkoutFetchRequest.batchLimit",
                value: Double(batchLimit),
                lowerBound: 1,
                upperBound: nil
            )
        }
        if anchor != nil, earliestWorkoutStart != nil {
            throw DomainError.inconsistent(
                reason: "WorkoutFetchRequest.earliestWorkoutStart applies only to an unanchored fetch"
            )
        }

        self.anchor = anchor
        self.earliestWorkoutStart = earliestWorkoutStart
        self.batchLimit = batchLimit
    }
}

/// What one anchored read returned.
///
/// The shape mirrors what an anchored health-store query actually hands back: things
/// that appeared, things that disappeared, and a new position. The fourth field is the
/// one the platform does not give you, and it exists so that a record the platform
/// reports but the domain cannot represent is *counted* rather than either silently
/// dropped by the adapter or thrown as an error that wedges the pipeline forever.
public struct WorkoutFetchBatch: Hashable, Sendable {
    /// Workouts added or updated since the request's anchor, oldest first where the
    /// source provides an order. Order is not relied upon.
    public let workouts: [Workout]

    /// UUIDs of workouts the health store reports as deleted since the request's
    /// anchor. Reported once and only once by the platform, which is why they travel in
    /// the same batch as the additions and under the same anchor-advancement rule.
    public let deletedWorkoutIDs: [UUID]

    /// How many objects the platform returned that could not be turned into a
    /// `Workout` — an end before its start, a duration longer than its span, and so on.
    ///
    /// A count rather than a list of identifiers on purpose: the core reports this so a
    /// silent skip is not silent, and a health-store identifier in a log is PII the
    /// diagnostic does not need (CLAUDE.md).
    public let unrepresentableWorkoutCount: Int

    /// The position to resume from next time. Valid only once everything above has been
    /// durably handled.
    public let anchor: WorkoutQueryAnchor

    /// Total objects the platform returned, however they were classified. This is what
    /// the core compares against `batchLimit` to decide whether more remains.
    public var objectCount: Int {
        workouts.count + deletedWorkoutIDs.count + unrepresentableWorkoutCount
    }

    public init(
        workouts: [Workout],
        deletedWorkoutIDs: [UUID] = [],
        unrepresentableWorkoutCount: Int = 0,
        anchor: WorkoutQueryAnchor
    ) throws {
        guard unrepresentableWorkoutCount >= 0 else {
            throw DomainError.outOfRange(
                field: "WorkoutFetchBatch.unrepresentableWorkoutCount",
                value: Double(unrepresentableWorkoutCount),
                lowerBound: 0,
                upperBound: nil
            )
        }

        self.workouts = workouts
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.unrepresentableWorkoutCount = unrepresentableWorkoutCount
        self.anchor = anchor
    }
}

/// Failures a fetch reports that the core has a *policy* for, as opposed to the
/// arbitrary platform errors it can only propagate.
public enum WorkoutFetchError: Error, Hashable, Sendable {
    /// The stored anchor could not be turned back into something the platform accepts —
    /// truncated, written by an incompatible archive format, or otherwise corrupt.
    ///
    /// Adapters must raise this rather than substituting `nil` themselves. The choice
    /// between "refuse to fetch" and "refetch from scratch" is a data-loss decision, and
    /// it belongs where CI can see it — `AnchoredWorkoutIngester` makes it.
    case unusableAnchor
}

/// Reads workouts out of the health store, incrementally.
///
/// The implementation is an `HKAnchoredObjectQuery` in the app layer, which CI cannot
/// execute (CLAUDE.md — "What CI can and cannot prove"). Everything above this line is
/// therefore kept free of judgement: the adapter decodes an anchor, runs one query,
/// classifies what comes back, and returns. It does not decide when to fetch, how far
/// back, whether to fetch again, or what a failure means.
public protocol WorkoutFetching: Sendable {
    /// Performs exactly one read. Must return at most `request.batchLimit` objects and
    /// must not install a long-running update handler — the ingester drives repetition.
    func fetchWorkouts(_ request: WorkoutFetchRequest) async throws -> WorkoutFetchBatch
}
