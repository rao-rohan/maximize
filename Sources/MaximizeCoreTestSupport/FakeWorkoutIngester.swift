import Foundation
import MaximizeCore

/// In-memory stand-in for `WorkoutIngesting`.
///
/// This is what makes MAX-030's wake path testable at all. The real ingester will read
/// a HealthKit store, which CI cannot do (CLAUDE.md — "What CI can and cannot prove"),
/// so the decisions that matter — does a wake trigger ingestion, when is the platform
/// acknowledged, what happens when ingestion throws — are written against this instead.
///
/// Thread-safe because the code under test drives it across an `await` and, in
/// production, from an anonymous background queue.
public final class FakeWorkoutIngester: WorkoutIngesting, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var thrownError: Error?
    private var duringIngestHook: (@Sendable () -> Void)?

    public init() {}

    /// Number of times `ingestPendingWorkouts()` has been entered.
    public var ingestCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    /// If set, `ingestPendingWorkouts()` throws this instead of succeeding, so callers
    /// can be tested against a failing pipeline without one.
    public func failNextIngests(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        thrownError = error
    }

    /// Runs inside `ingestPendingWorkouts()`, before it returns or throws.
    ///
    /// Exists so a test can observe the world *mid-ingest* — specifically, whether the
    /// platform has already been acknowledged, which is the ordering guarantee
    /// `WorkoutObservationCoordinator` exists to provide.
    public func onIngest(_ hook: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        duringIngestHook = hook
    }

    public func ingestPendingWorkouts() async throws {
        lock.lock()
        callCount += 1
        let hook = duringIngestHook
        let error = thrownError
        lock.unlock()

        hook?()

        if let error {
            throw error
        }
    }
}

/// Records acknowledgements of a background wake.
///
/// Substitutes for HealthKit's `HKObserverQueryCompletionHandler`, which is an opaque
/// block whose only observable effect is on iOS's internal delivery bookkeeping. Here
/// the effect is a counter, so "acknowledged exactly once, after the work" becomes an
/// assertion instead of a hope.
public final class AcknowledgementRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    public init() {}

    /// How many times the acknowledgement has been invoked.
    ///
    /// Both failure modes are visible here: `0` is the one that makes HealthKit give
    /// up on the app after three strikes, and anything above `1` means a delivery was
    /// acknowledged more than once.
    public var acknowledgementCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    public var hasAcknowledged: Bool { acknowledgementCount > 0 }

    /// The handler to hand to the code under test.
    public func handler() -> @Sendable () -> Void {
        { [self] in
            lock.lock()
            count += 1
            lock.unlock()
        }
    }
}
