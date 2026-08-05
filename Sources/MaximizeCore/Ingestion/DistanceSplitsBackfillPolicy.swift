import Foundation

/// The tunable parts of one pass of MAX-067's distance-splits backfill.
///
/// A value, not a constant in the algorithm, for the same reason
/// `AnchoredIngestionPolicy` and `IngestionPipelinePolicy` are: a test can drive a
/// two-workout backlog through the same capped path a real one of hundreds takes,
/// without waiting on hundreds of fake HealthKit round trips.
public struct DistanceSplitsBackfillPolicy: Hashable, Sendable {
    /// How many workouts one pass may re-enrich.
    ///
    /// This is the bound the ticket calls for: enumerating candidates reads only
    /// scalar workout rows and the small `zoneSplits`/`distanceSplits` blob already on
    /// each one's metrics — the same class of read the trends dashboard already does
    /// over a run's history, and cheap by the same argument. What is expensive is
    /// re-enrichment itself: re-fetching the heart-rate and route samples from
    /// HealthKit and writing metrics back out. Capping *that* per pass is what keeps a
    /// launch on a phone with years of history from doing an unbounded amount of real
    /// work on the main actor's store, the cost `WorkoutIngestionPipeline.backfillDistanceSplits(policy:)`
    /// exists to bound. The remainder is picked up by the next pass — every workout a
    /// pass actually re-enriches is durable, with `DerivedMetrics.distanceSplitsComputed`
    /// set, before the pass returns, so stopping early loses no ground (interruptible by
    /// construction, not by a checkpoint that could itself be missed).
    public let maxWorkoutsPerPass: Int

    private init(uncheckedMaxWorkoutsPerPass: Int) {
        self.maxWorkoutsPerPass = uncheckedMaxWorkoutsPerPass
    }

    public init(maxWorkoutsPerPass: Int) throws {
        guard maxWorkoutsPerPass >= 1 else {
            throw DomainError.outOfRange(
                field: "DistanceSplitsBackfillPolicy.maxWorkoutsPerPass",
                value: Double(maxWorkoutsPerPass),
                lowerBound: 1,
                upperBound: nil
            )
        }
        self.init(uncheckedMaxWorkoutsPerPass: maxWorkoutsPerPass)
    }

    /// 25 workouts per pass, run once per launch (`applicationDidBecomeActive`,
    /// alongside `ingestPendingWorkouts`). A years-long running history is realistically
    /// a few hundred runs, not thousands, so this drains a full backlog over single-digit
    /// launches of ordinary daily use, and every launch after that is a query that finds
    /// nothing left to do.
    public static let standard = DistanceSplitsBackfillPolicy(uncheckedMaxWorkoutsPerPass: 25)
}

/// What one backfill pass actually did — MAX-067, and CLAUDE.md's rule that a progress
/// count is safe to surface even though a workout identifier or date is not.
public struct DistanceSplitsBackfillOutcome: Hashable, Sendable {
    /// How many workouts this pass re-enriched. Bounded by
    /// `DistanceSplitsBackfillPolicy.maxWorkoutsPerPass`.
    public let workoutsProcessed: Int

    /// How many workouts still had `distanceSplitsComputed == false` after this pass —
    /// zero once the backlog is drained, at which point every future pass is a store
    /// query that finds nothing to do.
    public let workoutsRemaining: Int

    public init(workoutsProcessed: Int, workoutsRemaining: Int) {
        self.workoutsProcessed = workoutsProcessed
        self.workoutsRemaining = workoutsRemaining
    }

    /// Nothing needed doing, or the enumeration read itself failed. The two are
    /// indistinguishable from the outcome alone by design — the caller has
    /// `IngestionPipelineDiagnostic` for the second case, and treating both as
    /// "try again next launch" is the correct response to either.
    public static let nothingToDo = DistanceSplitsBackfillOutcome(workoutsProcessed: 0, workoutsRemaining: 0)
}
