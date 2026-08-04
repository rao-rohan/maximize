import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// Exercises `ChatThreadRepository` (D6, FR-2.3, MAX-050) against
/// `FakeChatThreadRepository`.
///
/// `MaximizeStore`'s real `ChatThreadRepository` conformance lives in `App/` and is
/// never executed by CI — there is no simulator or device in this pipeline (tracker
/// R2). These tests exist so the write-path rule that actually matters — one thread
/// per workout — is checked on every commit against the protocol itself, rather than
/// trusted on the strength of `MaximizeStore.swift` reading correctly by eye. The fake
/// mirrors `MaximizeStore.store(_:)`'s upsert-by-`workoutID` behaviour exactly (see its
/// doc comment), so a test that passes here is a test of the rule the real store
/// implements, not of a different one.
final class ChatThreadRepositoryTests: XCTestCase {
    private func message(_ role: ChatRole, _ content: String, at offsetSeconds: Double) throws -> ChatMessage {
        try ChatMessage(
            id: UUID(),
            role: role,
            content: content,
            timestamp: Fixture.epoch.addingTimeInterval(offsetSeconds)
        )
    }

    func testUnknownWorkoutReadsAsNil() async throws {
        let repository = FakeChatThreadRepository()
        let result = try await repository.thread(forWorkout: Fixture.workoutID)
        XCTAssertNil(result)
    }

    func testStoreThenReadRoundTrips() async throws {
        let repository = FakeChatThreadRepository()
        let thread = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "Was that on plan?", at: 0)]
        )

        try await repository.store(thread)
        let restored = try await repository.thread(forWorkout: Fixture.workoutID)

        XCTAssertEqual(restored, thread)
    }

    /// D6/FR-2.3: thread identity is the workout. Storing a second thread for the same
    /// workout must replace the first, never sit beside it — the schema has no unique
    /// constraint CloudKit could enforce (see `MaximizeSchema`'s CloudKit notes), so
    /// this is the invariant that stands in for one.
    func testStoringForTheSameWorkoutReplacesRatherThanDuplicates() async throws {
        let repository = FakeChatThreadRepository()
        let first = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "First question", at: 0)]
        )
        let second = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [
                try message(.user, "First question", at: 0),
                try message(.assistant, "First answer", at: 5),
                try message(.user, "Follow-up question", at: 10),
            ]
        )

        try await repository.store(first)
        try await repository.store(second)

        XCTAssertEqual(repository.threadCount, 1, "one thread per workout, not one per store() call")
        XCTAssertEqual(repository.writes, 2, "both writes landed; the second overwrote the first's slot")

        let restored = try await repository.thread(forWorkout: Fixture.workoutID)
        XCTAssertEqual(restored, second)
        XCTAssertEqual(restored?.messages.count, 3)
    }

    /// Two workouts never share a thread even when written interleaved.
    func testThreadsForDifferentWorkoutsAreIndependent() async throws {
        let repository = FakeChatThreadRepository()
        let threadA = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "About run A", at: 0)]
        )
        let threadB = try ChatThread(
            id: UUID(),
            workoutID: Fixture.otherWorkoutID,
            messages: [try message(.user, "About run B", at: 0)]
        )

        try await repository.store(threadA)
        try await repository.store(threadB)

        XCTAssertEqual(repository.threadCount, 2)
        let restoredA = try await repository.thread(forWorkout: Fixture.workoutID)
        let restoredB = try await repository.thread(forWorkout: Fixture.otherWorkoutID)
        XCTAssertEqual(restoredA, threadA)
        XCTAssertEqual(restoredB, threadB)
    }

    /// Ordering is durable because it is an explicit, validated property of the domain
    /// type (`ChatThread.init`, `ChatMessage.timestamp`) — not incidental row order from
    /// a store. Round-tripping through the repository must not disturb it.
    func testOrderingSurvivesStoreAndRead() async throws {
        let repository = FakeChatThreadRepository()
        var thread = try ChatThread(id: UUID(), workoutID: Fixture.workoutID)
        thread = try thread.appending(message(.user, "Why did my HR drift at mile 3?", at: 0))
        thread = try thread.appending(message(.assistant, "Your second half averaged 8 bpm higher.", at: 4))
        thread = try thread.appending(message(.user, "Was that expected?", at: 30))

        try await repository.store(thread)
        let restored = try await repository.thread(forWorkout: Fixture.workoutID)

        XCTAssertEqual(restored?.messages.map(\.content), thread.messages.map(\.content))
        let timestamps = try XCTUnwrap(restored?.messages.map(\.timestamp))
        XCTAssertEqual(timestamps, timestamps.sorted())
    }

    /// A caller cannot hand the repository anything but a fully-formed `ChatThread` —
    /// there is no signature anywhere on `ChatThreadRepository` that accepts a partial
    /// or in-flight turn. Building an out-of-order thread fails before `store(_:)` is
    /// ever reachable, which is `ChatThread.appending`'s job, not this repository's.
    func testAppendingAnOutOfOrderTurnNeverReachesTheRepository() async throws {
        let repository = FakeChatThreadRepository()
        let thread = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "Why did my HR drift?", at: 60)]
        )

        assertThrows(.outOfOrder, try thread.appending(message(.assistant, "Because…", at: 30)))
        XCTAssertEqual(repository.threadCount, 0, "nothing was ever handed to the repository")
    }

    func testReadFailureIsPropagated() async {
        let repository = FakeChatThreadRepository()
        struct Boom: Error {}
        repository.failReads(with: Boom())

        do {
            _ = try await repository.thread(forWorkout: Fixture.workoutID)
            XCTFail("expected the injected failure to propagate")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("expected Boom, got \(error)")
        }
    }

    func testWriteFailureIsPropagated() async throws {
        let repository = FakeChatThreadRepository()
        struct Boom: Error {}
        repository.failWrites(with: Boom())
        let thread = try ChatThread(
            id: UUID(),
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "Hello", at: 0)]
        )

        do {
            try await repository.store(thread)
            XCTFail("expected the injected failure to propagate")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("expected Boom, got \(error)")
        }

        repository.stopFailing()
        try await repository.store(thread)
        XCTAssertEqual(repository.threadCount, 1)
    }
}
