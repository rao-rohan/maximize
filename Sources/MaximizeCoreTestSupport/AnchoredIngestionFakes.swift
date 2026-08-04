import Foundation
import MaximizeCore

/// A `WorkoutQueryAnchorStore` that keeps the anchor in memory, and can be made to fail.
///
/// "Survives relaunch" cannot be tested by relaunching anything in CI, so it is tested as
/// the property it actually reduces to: a second ingester, constructed fresh against the
/// same store, resumes from the anchor the first one left. That is what a relaunch does.
public final class InMemoryWorkoutQueryAnchorStore: WorkoutQueryAnchorStore, @unchecked Sendable {
    public enum Failure: Error, Hashable, Sendable {
        case loadFailed
        case saveFailed
    }

    private let lock = NSLock()
    private var anchor: WorkoutQueryAnchor?
    private var loadError: Failure?
    private var saveError: Failure?
    private var saves: [WorkoutQueryAnchor] = []
    private var clears = 0

    public init(anchor: WorkoutQueryAnchor? = nil) {
        self.anchor = anchor
    }

    /// Every anchor written, in order. The ingester's ordering guarantee is about *when*
    /// a write happens relative to the sink, so the history matters, not just the latest.
    public var savedAnchors: [WorkoutQueryAnchor] {
        lock.locked { saves }
    }

    public var clearCount: Int {
        lock.locked { clears }
    }

    public var currentAnchor: WorkoutQueryAnchor? {
        lock.locked { anchor }
    }

    /// Simulates a store that has bytes on disk it cannot read back.
    public func failLoads() {
        lock.locked { loadError = .loadFailed }
    }

    /// Simulates the durability failure the anchor-last ordering is designed around: the
    /// workouts landed, the anchor did not.
    public func failSaves() {
        lock.locked { saveError = .saveFailed }
    }

    public func stopFailing() {
        lock.locked {
            loadError = nil
            saveError = nil
        }
    }

    public func loadAnchor() async throws -> WorkoutQueryAnchor? {
        let (error, value) = lock.locked { (loadError, anchor) }
        if let error { throw error }
        return value
    }

    public func saveAnchor(_ newAnchor: WorkoutQueryAnchor) async throws {
        let error = lock.locked { saveError }
        if let error { throw error }
        lock.locked {
            anchor = newAnchor
            saves.append(newAnchor)
        }
    }

    public func clearAnchor() async throws {
        lock.locked {
            anchor = nil
            clears += 1
        }
    }
}

/// A scripted `WorkoutFetching`.
///
/// Batches are queued and handed out one per call, which is what lets a test drive paging,
/// re-delivery after a lost anchor, and a platform that rejects the anchor it was given —
/// none of which a real health store can be made to do on demand.
public final class FakeWorkoutFetcher: WorkoutFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [WorkoutFetchBatch] = []
    private var requests: [WorkoutFetchRequest] = []
    private var errorForNextFetch: Error?
    private var rejectsAnchoredRequests = false
    private var emptyBatchAnchor = WorkoutQueryAnchor(opaqueData: Data([0]))

    public init() {}

    /// Every request received, in order — the record a test asserts against to show that
    /// the second pass resumed from the anchor the first one stored.
    public var receivedRequests: [WorkoutFetchRequest] {
        lock.locked { requests }
    }

    public var fetchCount: Int { receivedRequests.count }

    /// Queues batches to be returned by subsequent calls, in order.
    public func enqueue(_ batches: WorkoutFetchBatch...) {
        lock.locked { queued.append(contentsOf: batches) }
    }

    /// The next fetch throws this, then behaves normally again.
    public func failNextFetch(with error: Error) {
        lock.locked { errorForNextFetch = error }
    }

    /// Makes every *anchored* request fail with `.unusableAnchor`, as a platform that
    /// cannot decode a stored anchor would. Unanchored requests still succeed, so a test
    /// can watch the ingester recover rather than merely fail.
    public func rejectAnchoredRequests() {
        lock.locked { rejectsAnchoredRequests = true }
    }

    /// The anchor returned when the queue is empty. Stable, so an idle pass does not look
    /// like forward progress.
    public func setEmptyBatchAnchor(_ anchor: WorkoutQueryAnchor) {
        lock.locked { emptyBatchAnchor = anchor }
    }

    public func fetchWorkouts(_ request: WorkoutFetchRequest) async throws -> WorkoutFetchBatch {
        let (error, rejects) = lock.locked {
            let error = errorForNextFetch
            errorForNextFetch = nil
            requests.append(request)
            return (error, rejectsAnchoredRequests)
        }

        if let error { throw error }
        if rejects, request.anchor != nil { throw WorkoutFetchError.unusableAnchor }

        let next = lock.locked { queued.isEmpty ? nil : queued.removeFirst() }
        if let next { return next }

        return try WorkoutFetchBatch(workouts: [], anchor: lock.locked { emptyBatchAnchor })
    }
}

/// A `WorkoutIngestionSink` that records what it was given and dedupes as MAX-033 will.
///
/// The dedupe is real, not a counter: `hasIngestedWorkout` answers from the same set
/// `ingest` writes to, so "re-delivery is a no-op" is demonstrated by the ingester and the
/// sink together, the way it will hold in production.
public final class RecordingWorkoutIngestionSink: WorkoutIngestionSink, @unchecked Sendable {
    private let lock = NSLock()
    private var ingestedInOrder: [Workout] = []
    private var ingestedIDs: Set<UUID> = []
    private var discarded: [UUID] = []
    private var ingestError: Error?
    private var failingWorkoutIDs: Set<UUID> = []
    private var duringIngestHook: (@Sendable (Workout) -> Void)?
    private var duringIngestAsyncHook: (@Sendable (Workout) async -> Void)?

    public init() {}

    /// Workouts accepted, in the order they were accepted. A duplicate would show up here
    /// twice, which is the assertion FR-0.5 comes down to.
    public var ingestedWorkouts: [Workout] {
        lock.locked { ingestedInOrder }
    }

    public var discardedWorkoutIDs: [UUID] {
        lock.locked { discarded }
    }

    /// Every `ingest` call throws this.
    public func failAllIngests(with error: Error) {
        lock.locked { ingestError = error }
    }

    /// Only this workout fails, so a test can leave a specific record unhandled and watch
    /// where the anchor ends up.
    public func failIngest(of id: UUID, with error: Error) {
        lock.locked {
            failingWorkoutIDs.insert(id)
            ingestError = error
        }
    }

    public func stopFailing() {
        lock.locked {
            ingestError = nil
            failingWorkoutIDs = []
        }
    }

    /// Runs inside `ingest`, before the workout is recorded — the vantage point from which
    /// a test can check that the anchor has *not* moved yet.
    public func onIngest(_ hook: @escaping @Sendable (Workout) -> Void) {
        lock.locked { duringIngestHook = hook }
    }

    /// As `onIngest`, but able to suspend. Exists so a test can hold a pass open and
    /// observe what a *concurrent* pass is doing while this one is mid-flight.
    public func onIngestAsync(_ hook: @escaping @Sendable (Workout) async -> Void) {
        lock.locked { duringIngestAsyncHook = hook }
    }

    public func hasIngestedWorkout(id: UUID) async throws -> Bool {
        lock.locked { ingestedIDs.contains(id) }
    }

    public func ingest(_ workout: Workout) async throws {
        typealias Hooks = ((@Sendable (Workout) -> Void)?, (@Sendable (Workout) async -> Void)?, Error?)
        let (hook, asyncHook, error) = lock.locked { () -> Hooks in
            let shouldFail = failingWorkoutIDs.isEmpty || failingWorkoutIDs.contains(workout.id)
            return (duringIngestHook, duringIngestAsyncHook, shouldFail ? ingestError : nil)
        }

        hook?(workout)
        await asyncHook?(workout)
        if let error { throw error }

        lock.locked {
            ingestedInOrder.append(workout)
            ingestedIDs.insert(workout.id)
        }
    }

    public func discardWorkout(id: UUID) async throws {
        lock.locked {
            discarded.append(id)
            ingestedIDs.remove(id)
            ingestedInOrder.removeAll { $0.id == id }
        }
    }
}

/// Collects `IngestionDiagnostic`s reported during a pass.
public final class DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [IngestionDiagnostic] = []

    public init() {}

    public var reported: [IngestionDiagnostic] {
        lock.locked { events }
    }

    public func handler() -> @Sendable (IngestionDiagnostic) -> Void {
        { [self] event in
            lock.locked { events.append(event) }
        }
    }
}

private extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
