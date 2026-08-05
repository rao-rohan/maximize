import Foundation
import MaximizeCore

/// An in-memory stand-in for the `ChatThreadRepository` half of `MaximizeStore`
/// (MAX-020, MAX-050, MAX-092).
///
/// `MaximizeStore` itself lives in `App/` and is never executed by CI (no simulator or
/// device in this pipeline — tracker R2). This fake exists so the write-path and
/// ordering rules that matter are exercised under `swift test` on every commit, against
/// the real protocol, rather than trusted on the strength of reading
/// `MaximizeStore.swift` by eye.
///
/// ## The two rules this mirrors
///
/// **Keyed on the thread's own `id` (A11).** `store(_:)` upserts on `id`, so a thread
/// that grows by returning a new value replaces itself rather than accumulating rows.
///
/// **One thread per workout subject, and it is a policy rather than a shape.**
/// `store(_:)` of a workout-subject thread evicts any *other* thread for the same
/// workout, which is what `MaximizeStore` achieves by upserting on `workoutUUID` — the
/// schema has no unique constraint CloudKit could enforce (`ChatThreadRecord.workoutUUID`
/// is a plain, non-unique attribute, same reasoning as `WorkoutRecord.workoutUUID`), so
/// "two threads for one workout" is prevented at the one door in. Training subjects are
/// deliberately *not* deduplicated: "New chat" over a newer window is the product
/// (§3.4), and §12's question 3 is about workouts only.
///
/// **`mostRecentThread(for:)` is total.** Newest `lastActivityAt`, `id` breaking a tie —
/// the successor to MAX-048's `(createdAt, threadUUID)` sort, and the reason this fake
/// exists at all: MAX-048's version of the rule lives in App code CI compiles and never
/// runs.
///
/// This is the seam MAX-096 and MAX-097 build against. A view model can hold a
/// `ChatThreadRepository` and be driven end-to-end in a test without SwiftData, a
/// simulator, or a device.
public final class FakeChatThreadRepository: ChatThreadRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var threadsByID: [UUID: ChatThread] = [:]
    private var facts: [UUID: WorkoutThreadFacts] = [:]
    private var writeCount = 0
    private var readError: Error?
    private var writeError: Error?

    public init() {}

    // MARK: - Inspection

    /// Every stored thread. Exposed for assertions like "still exactly one row" rather
    /// than as a way to bypass the protocol.
    public var allThreads: [ChatThread] {
        lock.locked { Array(threadsByID.values) }
    }

    public var threadCount: Int {
        lock.locked { threadsByID.count }
    }

    /// Every call to `store(_:)`, counting replaces — so "an upsert, not an insert" is
    /// an assertion about this count and `threadCount` together, not about identity.
    public var writes: Int { lock.locked { writeCount } }

    // MARK: - Test fixtures

    /// Supplies the run facts a workout thread's title is derived from (§2.4).
    ///
    /// The real store resolves these from its own workout records; a fake has none, so
    /// a test that cares about titles states them. A thread whose workout has no facts
    /// registered titles as if the run were missing, which is the same path
    /// `ChatThreadTitle.workout(_:)` documents.
    public func register(_ facts: WorkoutThreadFacts, forWorkout id: UUID) {
        lock.locked { self.facts[id] = facts }
    }

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

    public func threadSummaries() async throws -> [ChatThreadSummary] {
        try lock.locked {
            if let readError { throw readError }
            let summaries = threadsByID.values.map { thread in
                ChatThreadSummary(thread, workoutFacts: thread.subject.workoutID.flatMap { facts[$0] })
            }
            return ChatThreadSummary.sortedByActivity(summaries)
        }
    }

    public func thread(id: UUID) async throws -> ChatThread? {
        try lock.locked {
            if let readError { throw readError }
            return threadsByID[id]
        }
    }

    public func mostRecentThread(for subject: ChatSubject) async throws -> ChatThread? {
        try lock.locked {
            if let readError { throw readError }
            return threadsByID.values
                .filter { $0.subject == subject }
                // Total, per the protocol: `max(by:)` over a strict weak ordering with
                // `id` as the tiebreak, so a dictionary's arbitrary iteration order can
                // never decide which thread the athlete lands in. Compared as
                // `uuidString` for the reason `ChatThreadSummary.sortedByActivity(_:)`
                // gives.
                .max { left, right in
                    if left.lastActivityAt != right.lastActivityAt {
                        return left.lastActivityAt < right.lastActivityAt
                    }
                    return left.id.uuidString < right.id.uuidString
                }
        }
    }

    public func store(_ thread: ChatThread) async throws {
        try lock.locked {
            if let writeError { throw writeError }
            if let workoutID = thread.subject.workoutID {
                // The "one thread per workout" policy, at the one door in. Collected
                // before removing rather than removed mid-iteration, so the loop is
                // reading a set of keys and not a collection it is editing.
                let superseded = threadsByID
                    .filter { $0.key != thread.id && $0.value.subject.workoutID == workoutID }
                    .map(\.key)
                for id in superseded {
                    threadsByID[id] = nil
                }
            }
            threadsByID[thread.id] = thread
            writeCount += 1
        }
    }

    public func deleteThread(id: UUID) async throws {
        try lock.locked {
            if let writeError { throw writeError }
            threadsByID[id] = nil
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
