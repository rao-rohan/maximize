import Foundation
import MaximizeCore

/// An in-memory stand-in for the `ChatThreadRepository` half of `MaximizeStore`
/// (MAX-020, MAX-050).
///
/// `MaximizeStore` itself lives in `App/` and is never executed by CI (no simulator or
/// device in this pipeline — tracker R2). This fake exists so the one write-path rule
/// that matters for D6/FR-2.3 — **a workout has at most one thread** — is exercised
/// under `swift test` on every commit, against the real protocol, rather than trusted
/// on the strength of reading `MaximizeStore.swift` by eye.
///
/// ## The rule this enforces, mirrored from `MaximizeStore.store(_ thread:)`
///
/// `store(_:)` is an upsert **keyed on `workoutID`, not on the thread's own `id`.**
/// Calling it twice for the same workout replaces the stored thread rather than
/// creating a second one — the schema has no unique constraint CloudKit could enforce
/// (`ChatThreadRecord.workoutUUID` is a plain, non-unique attribute, same reasoning as
/// `WorkoutRecord.workoutUUID`), so "two threads for one workout" is made unrepresentable
/// here instead: there is exactly one door in, and it always writes to the same slot.
///
/// This is the seam MAX-051 builds the chat UI against. A view model can hold a
/// `ChatThreadRepository` and be driven end-to-end in a test without SwiftData, a
/// simulator, or a device.
public final class FakeChatThreadRepository: ChatThreadRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var threadsByWorkoutID: [UUID: ChatThread] = [:]
    private var writeCount = 0
    private var readError: Error?
    private var writeError: Error?

    public init() {}

    // MARK: - Inspection

    /// Every stored thread, keyed by the workout it belongs to. Exposed for assertions
    /// like "still exactly one row" rather than as a way to bypass the protocol.
    public var allThreads: [ChatThread] {
        lock.locked { Array(threadsByWorkoutID.values) }
    }

    public var threadCount: Int {
        lock.locked { threadsByWorkoutID.count }
    }

    /// Every call to `store(_:)`, counting replaces — so "an upsert, not an insert" is
    /// an assertion about this count and `threadCount` together, not about identity.
    public var writes: Int { lock.locked { writeCount } }

    // MARK: - Failure injection

    public func failReads(with error: Error) {
        lock.locked { readError = error }
    }

    public func failWrites(with error: Error) {
        lock.locked { writeError = error }
    }

    public func stopFailing() {
        lock.locked {
            readError = nil
            writeError = nil
        }
    }

    // MARK: - ChatThreadRepository

    public func thread(forWorkout id: UUID) async throws -> ChatThread? {
        try lock.locked {
            if let readError { throw readError }
            return threadsByWorkoutID[id]
        }
    }

    public func store(_ thread: ChatThread) async throws {
        try lock.locked {
            if let writeError { throw writeError }
            threadsByWorkoutID[thread.workoutID] = thread
            writeCount += 1
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
