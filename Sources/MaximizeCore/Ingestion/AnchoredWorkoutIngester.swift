import Foundation

/// The tunable parts of an anchored ingestion pass.
///
/// Values, not constants in the algorithm, so a test can drive a two-workout batch
/// through the same paging path a real backlog takes.
public struct AnchoredIngestionPolicy: Hashable, Sendable {
    /// How many objects one fetch may return.
    ///
    /// Bounded because a background wake is a short, unspecified budget (tracker R8) and
    /// the first fetch on a phone with years of Health history is the one place this
    /// pipeline could ask for thousands of records at once.
    public let batchLimit: Int

    /// How many batches one pass may process before stopping and leaving the rest for
    /// the next pass.
    ///
    /// Stopping early is safe in a way that stopping *late* is not: the anchor is already
    /// persisted for every batch that completed, so the remainder is picked up from where
    /// this pass left off. Overrunning the wake budget, by contrast, risks being suspended
    /// mid-batch.
    public let maxBatchesPerPass: Int

    /// How far back a *first* fetch — one with no stored anchor — may reach, or `nil` for
    /// no limit.
    ///
    /// The alternative is an unbounded first fetch of every workout the phone has ever
    /// held, which is both a wake-budget hazard and largely pointless: a score is only
    /// meaningful against the plan version in effect on the workout's date (D1), and
    /// there is no plan predating the app.
    public let firstRunBackfill: TimeInterval?

    private init(uncheckedBatchLimit: Int, maxBatchesPerPass: Int, firstRunBackfill: TimeInterval?) {
        self.batchLimit = uncheckedBatchLimit
        self.maxBatchesPerPass = maxBatchesPerPass
        self.firstRunBackfill = firstRunBackfill
    }

    public init(batchLimit: Int, maxBatchesPerPass: Int, firstRunBackfill: TimeInterval?) throws {
        guard batchLimit >= 1 else {
            throw DomainError.outOfRange(
                field: "AnchoredIngestionPolicy.batchLimit",
                value: Double(batchLimit),
                lowerBound: 1,
                upperBound: nil
            )
        }
        guard maxBatchesPerPass >= 1 else {
            throw DomainError.outOfRange(
                field: "AnchoredIngestionPolicy.maxBatchesPerPass",
                value: Double(maxBatchesPerPass),
                lowerBound: 1,
                upperBound: nil
            )
        }
        if let firstRunBackfill {
            try Validate.positive(firstRunBackfill, "AnchoredIngestionPolicy.firstRunBackfill")
        }

        self.init(
            uncheckedBatchLimit: batchLimit,
            maxBatchesPerPass: maxBatchesPerPass,
            firstRunBackfill: firstRunBackfill
        )
    }

    /// 50 objects per fetch, at most 20 fetches per pass, 90 days of first-run backfill.
    ///
    /// The product of the first two — 1000 workouts drainable in a single pass — is well
    /// past any realistic single-user backlog, so the cap is a stop for pathological
    /// cases rather than something normal operation meets.
    public static let standard = AnchoredIngestionPolicy(
        uncheckedBatchLimit: 50,
        maxBatchesPerPass: 20,
        firstRunBackfill: 90 * 24 * 60 * 60
    )
}

/// Something that happened during a pass and would otherwise be invisible.
///
/// Every case here describes a moment where the pipeline moved past data, or declined
/// to. Those are precisely the events that leave no other trace: nothing crashes, nothing
/// appears on screen, and CI cannot see a device. Carries counts and reasons only — never
/// a workout, a date, or an identifier (CLAUDE.md: health data is PII).
public enum IngestionDiagnostic: Hashable, Sendable {
    /// The stored anchor was thrown away and the pass restarted from scratch.
    case storedAnchorDiscarded(reason: DiscardedAnchorReason)

    /// The health store returned objects that could not be represented as `Workout`s.
    /// The anchor has advanced past them; they will not be offered again.
    case workoutsUnrepresentable(count: Int)

    /// The pass hit `maxBatchesPerPass` with more still waiting. Everything processed is
    /// durable and anchored; the remainder resumes on the next pass.
    case passTruncated(batchesProcessed: Int)

    public enum DiscardedAnchorReason: Hashable, Sendable {
        /// The store could not read back what it had written.
        case unreadable
        /// The platform rejected the anchor it was handed.
        case unusable
    }
}

/// FR-0.2: fetch new workouts via an anchored query, incrementally, with no duplicates
/// across relaunches.
///
/// ## Why this type is load-bearing
///
/// `WorkoutObservationCoordinator` (MAX-030) acknowledges *every* background wake,
/// including one whose ingestion failed, because three unacknowledged wakes make HealthKit
/// stop delivering to the app permanently and silently. The cost of that choice is that
/// **iOS never retries**, and the thing that makes it survivable is this type: a workout
/// that was not durably handled leaves the anchor where it was, so the next pass offers it
/// again. Every rule below exists to keep that true.
///
/// ## When the anchor advances
///
/// **After the batch is durably handled, never before.** The two orderings fail in
/// opposite directions and they are not equally bad:
///
/// - *Anchor first.* A crash between saving the anchor and storing the workouts loses
///   them **forever**. The next fetch resumes past them and the health store will never
///   offer them again. Nothing reports this; the runs simply never appear.
/// - *Anchor last.* A crash between storing the workouts and saving the anchor
///   re-delivers the whole batch on the next pass. `hasIngestedWorkout` recognises each
///   one and skips it (FR-0.5), so the visible cost is one redundant fetch.
///
/// A recoverable duplicate beats an unrecoverable loss, so the anchor is written last, and
/// per batch rather than per pass — a pass that stops halfway keeps the ground it took.
///
/// ## The remaining honest gap
///
/// "The next pass recovers it" requires a next pass. This type cannot summon one: it runs
/// when something calls it, which is a background wake (a new workout arriving) or the app
/// coming to the foreground. So a workout whose ingestion fails is *delayed until one of
/// those happens*, not lost — but if the failure is permanent and nothing new is ever
/// recorded and the app is never opened, "delayed" is indefinite. The guarantee is
/// at-least-once delivery, not bounded-latency delivery, and PRD §11 asks for exactly the
/// former.
///
/// ## Concurrency
///
/// Two background wakes can overlap. Two passes interleaving on one anchor would let the
/// later one persist an anchor covering workouts the earlier one had not finished storing
/// — the anchor-first failure, arrived at by accident. So passes are serialised: a call
/// that finds one in flight waits for it, then runs its own. The second pass is nearly
/// free, because by then the anchor has moved and there is nothing left to return.
///
/// Actor isolation alone is *not* enough for this. Actors are reentrant: a second call
/// would enter at the first `await` inside the pass. The explicit chain below is what
/// serialises, and the actor is what makes the chain itself race-free.
public actor AnchoredWorkoutIngester: WorkoutIngesting {
    private let fetcher: WorkoutFetching
    private let anchorStore: WorkoutQueryAnchorStore
    private let sink: WorkoutIngestionSink
    private let policy: AnchoredIngestionPolicy
    private let now: @Sendable () -> Date
    private let report: @Sendable (IngestionDiagnostic) -> Void

    /// The most recently started pass. Read and written only under actor isolation, and
    /// never across a suspension point, so "who is my predecessor" cannot race.
    ///
    /// Not cleared when a pass finishes: awaiting a completed `Task` returns immediately,
    /// so the only cost is holding one finished task, and the chain never grows beyond the
    /// single previous link.
    private var passInFlight: Task<Void, Error>?

    /// - Parameters:
    ///   - report: called with events that would otherwise leave no trace. Defaults to
    ///     discarding. Whatever is passed **must not write health data anywhere durable**
    ///     — `IngestionDiagnostic` is built to carry none, and that property is only worth
    ///     having if the sink for it respects it.
    public init(
        fetcher: WorkoutFetching,
        anchorStore: WorkoutQueryAnchorStore,
        sink: WorkoutIngestionSink,
        policy: AnchoredIngestionPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        report: @escaping @Sendable (IngestionDiagnostic) -> Void = { _ in }
    ) {
        self.fetcher = fetcher
        self.anchorStore = anchorStore
        self.sink = sink
        self.policy = policy
        self.now = now
        self.report = report
    }

    public func ingestPendingWorkouts() async throws {
        let predecessor = passInFlight

        let pass = Task { [self] in
            // The predecessor's outcome is not this caller's to report — one wake failing
            // must not fail an unrelated later wake — so only its completion is awaited.
            if let predecessor {
                _ = await predecessor.result
            }
            try await performPass()
        }
        passInFlight = pass

        // Deliberately `pass.value` and not a cancellation-aware wrapper: an unstructured
        // `Task` does not inherit cancellation, so if the caller is cancelled mid-wake the
        // pass still runs to completion and the work already fetched still lands.
        try await pass.value
    }

    // MARK: - One pass

    private func performPass() async throws {
        var anchor = await loadAnchorFailingOpen()
        var mayStillRetryWithoutAnchor = anchor != nil
        var handledInThisPass: Set<UUID> = []
        var batchesProcessed = 0

        while batchesProcessed < policy.maxBatchesPerPass {
            let request = try makeRequest(anchor: anchor)

            let batch: WorkoutFetchBatch
            do {
                batch = try await fetcher.fetchWorkouts(request)
            } catch WorkoutFetchError.unusableAnchor where mayStillRetryWithoutAnchor {
                // Failing closed here would mean never fetching again — a corrupt byte on
                // disk would end zero-touch capture for good. Failing open costs one
                // re-read of the backfill window, and every workout in it is recognised
                // and skipped by the dedupe check.
                report(.storedAnchorDiscarded(reason: .unusable))
                try? await anchorStore.clearAnchor()
                anchor = nil
                mayStillRetryWithoutAnchor = false
                continue
            }

            if batch.unrepresentableWorkoutCount > 0 {
                // Reported, and then moved past. Refusing to advance would pin the anchor
                // on a record that can never be accepted, and every workout recorded after
                // it would queue behind that forever.
                report(.workoutsUnrepresentable(count: batch.unrepresentableWorkoutCount))
            }

            // Additions before deletions, so that a batch carrying both for one workout
            // ends with it deleted — the state the health store is describing.
            for workout in batch.workouts where !handledInThisPass.contains(workout.id) {
                handledInThisPass.insert(workout.id)
                let alreadyIngested = try await sink.hasIngestedWorkout(id: workout.id)
                if alreadyIngested { continue }
                try await sink.ingest(workout)
            }
            for id in batch.deletedWorkoutIDs {
                try await sink.discardWorkout(id: id)
            }

            // Everything above is durable. Only now may the anchor move; see the type
            // documentation for the failure mode this ordering chooses.
            if batch.anchor != anchor {
                try await anchorStore.saveAnchor(batch.anchor)
            }

            batchesProcessed += 1

            // A batch smaller than the limit means the store had nothing more to give.
            guard batch.objectCount >= request.batchLimit else { return }
            // A full batch that did not move the anchor would loop forever. The store
            // cannot legitimately produce this; a fetcher that ignores the anchor can.
            guard batch.anchor != anchor else { return }
            anchor = batch.anchor
        }

        report(.passTruncated(batchesProcessed: batchesProcessed))
    }

    private func makeRequest(anchor: WorkoutQueryAnchor?) throws -> WorkoutFetchRequest {
        // The backfill bound applies only to a first fetch. Applying it to an anchored one
        // would filter out a workout that synced late while letting the anchor advance
        // past it — a silent loss dressed up as a bound.
        let earliestWorkoutStart: Date? = anchor == nil
            ? policy.firstRunBackfill.map { now().addingTimeInterval(-$0) }
            : nil

        return try WorkoutFetchRequest(
            anchor: anchor,
            earliestWorkoutStart: earliestWorkoutStart,
            batchLimit: policy.batchLimit
        )
    }

    /// Reads the stored anchor, treating an unreadable one as absent.
    ///
    /// Failing open is the whole point. "I cannot read the anchor, so I will not fetch"
    /// ends capture permanently for a single bad read; "I cannot read the anchor, so I
    /// will read the backfill window again" costs a redundant fetch whose every result is
    /// deduped away.
    private func loadAnchorFailingOpen() async -> WorkoutQueryAnchor? {
        do {
            return try await anchorStore.loadAnchor()
        } catch {
            report(.storedAnchorDiscarded(reason: .unreadable))
            return nil
        }
    }
}
