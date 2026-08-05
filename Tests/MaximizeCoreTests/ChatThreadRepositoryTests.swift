import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// Exercises `ChatThreadRepository` (A11, FR-2.3, MAX-050, MAX-092) against
/// `FakeChatThreadRepository`.
///
/// `MaximizeStore`'s real conformance lives in `App/` and is never executed by CI —
/// there is no simulator or device in this pipeline (tracker R2). These tests exist so
/// the rules that actually matter are checked on every commit against the protocol
/// itself, rather than trusted on the strength of `MaximizeStore.swift` reading
/// correctly by eye. The fake mirrors that store's behaviour deliberately (see its doc
/// comment), so a test that passes here is a test of the rule the real store implements.
///
/// Every `await` is hoisted out of the assertion macros on purpose: XCTest's assertions
/// take non-async autoclosures, so `XCTAssertEqual(try await …)` does not compile.
final class ChatThreadRepositoryTests: XCTestCase {
    private func message(_ role: ChatRole, _ content: String, at offsetSeconds: Double) throws -> ChatMessage {
        try Fixture.message(role, content, at: offsetSeconds)
    }

    private var workoutSubject: ChatSubject { .workout(Fixture.workoutID) }
    private var otherWorkoutSubject: ChatSubject { .workout(Fixture.otherWorkoutID) }

    private func trainingSubject(
        from start: (Int, Int, Int) = (2026, 8, 1),
        through end: (Int, Int, Int) = (2026, 8, 31)
    ) throws -> ChatSubject {
        .training(try Fixture.scope(from: start, through: end))
    }

    // MARK: - Reading

    func testUnknownSubjectAndUnknownIdentifierBothReadAsNil() async throws {
        let repository = FakeChatThreadRepository()

        let bySubject = try await repository.mostRecentThread(for: workoutSubject)
        let byID = try await repository.thread(id: UUID())
        let summaries = try await repository.threadSummaries()

        XCTAssertNil(bySubject)
        XCTAssertNil(byID)
        XCTAssertEqual(summaries, [])
    }

    func testStoreThenReadRoundTripsByIdentifierAndBySubject() async throws {
        let repository = FakeChatThreadRepository()
        let thread = try Fixture.thread(
            subject: workoutSubject,
            messages: [try message(.user, "Was that on plan?", at: 0)]
        )

        try await repository.store(thread)
        let byID = try await repository.thread(id: thread.id)
        let bySubject = try await repository.mostRecentThread(for: workoutSubject)

        XCTAssertEqual(byID, thread)
        XCTAssertEqual(bySubject, thread)
    }

    // MARK: - Identity (A11)

    /// The whole point of MAX-092: the key is the thread, not the workout. A thread that
    /// grows by returning a new value replaces itself.
    func testStoringIsKeyedOnTheThreadsOwnIdentifier() async throws {
        let repository = FakeChatThreadRepository()
        let threadID = UUID()
        let first = try Fixture.thread(
            id: threadID,
            subject: workoutSubject,
            messages: [try message(.user, "First question", at: 0)]
        )
        let grown = try first
            .appending(message(.assistant, "First answer", at: 5))
            .appending(message(.user, "Follow-up question", at: 10))

        try await repository.store(first)
        try await repository.store(grown)
        let restored = try await repository.thread(id: threadID)

        XCTAssertEqual(repository.threadCount, 1, "one row per thread, not one per store() call")
        XCTAssertEqual(repository.writes, 2, "both writes landed; the second overwrote the first's slot")
        XCTAssertEqual(restored?.messages.count, 3)
    }

    /// §12 question 3: one thread per workout, and it is a repository policy rather than
    /// a shape `ChatThread` forbids — so it is asserted here, where the policy lives.
    func testASecondThreadForTheSameWorkoutSupersedesTheFirst() async throws {
        let repository = FakeChatThreadRepository()
        let original = try Fixture.thread(
            subject: workoutSubject,
            messages: [try message(.user, "First question", at: 0)]
        )
        let replacement = try Fixture.thread(
            subject: workoutSubject,
            messages: [try message(.user, "Started over", at: 100)]
        )

        try await repository.store(original)
        try await repository.store(replacement)
        let originalNow = try await repository.thread(id: original.id)
        let resolved = try await repository.mostRecentThread(for: workoutSubject)

        XCTAssertEqual(repository.threadCount, 1)
        XCTAssertNil(originalNow)
        XCTAssertEqual(resolved, replacement)
    }

    /// Training threads are deliberately *not* deduplicated: "New chat" over a newer
    /// window is the product (§3.4), so two threads with different scopes coexist.
    func testTrainingThreadsWithDifferentScopesCoexist() async throws {
        let repository = FakeChatThreadRepository()
        let august = try Fixture.thread(
            subject: try trainingSubject(from: (2026, 8, 1), through: (2026, 8, 31)),
            messages: [try message(.user, "How was August?", at: 0)]
        )
        let september = try Fixture.thread(
            subject: try trainingSubject(from: (2026, 9, 1), through: (2026, 9, 30)),
            messages: [try message(.user, "And September?", at: 100)]
        )

        try await repository.store(august)
        try await repository.store(september)
        let resolvedAugust = try await repository.mostRecentThread(for: august.subject)

        XCTAssertEqual(repository.threadCount, 2)
        XCTAssertEqual(
            resolvedAugust,
            august,
            "a scope is part of the subject, so September's thread is not August's"
        )
    }

    func testThreadsForDifferentWorkoutsAreIndependent() async throws {
        let repository = FakeChatThreadRepository()
        let threadA = try Fixture.thread(
            subject: workoutSubject,
            messages: [try message(.user, "About run A", at: 0)]
        )
        let threadB = try Fixture.thread(
            subject: otherWorkoutSubject,
            messages: [try message(.user, "About run B", at: 0)]
        )

        try await repository.store(threadA)
        try await repository.store(threadB)
        let resolvedA = try await repository.mostRecentThread(for: workoutSubject)
        let resolvedB = try await repository.mostRecentThread(for: otherWorkoutSubject)

        XCTAssertEqual(repository.threadCount, 2)
        XCTAssertEqual(resolvedA, threadA)
        XCTAssertEqual(resolvedB, threadB)
    }

    // MARK: - Determinism (the successor to MAX-048)

    /// MAX-048's bug in its new form: with identity on the thread, "which thread does a
    /// subject resolve to" is a query over several candidates, and an unordered answer
    /// would land the athlete in a different conversation on each read.
    func testMostRecentThreadPicksTheNewestActivityDeterministically() async throws {
        let repository = FakeChatThreadRepository()
        let scope = try trainingSubject()
        let older = try Fixture.thread(subject: scope, lastActivityAt: Fixture.at(0))
        let newer = try Fixture.thread(subject: scope, lastActivityAt: Fixture.at(1_000))

        try await repository.store(older)
        try await repository.store(newer)

        for _ in 0..<20 {
            let resolved = try await repository.mostRecentThread(for: scope)
            XCTAssertEqual(resolved, newer)
        }
    }

    /// Two threads sharing a timestamp is not exotic — it is what a store whose rows all
    /// carry the same default looks like, which is the situation MAX-048 was filed for.
    /// The identifier is the total order underneath.
    func testASharedTimestampIsBrokenByIdentifier() async throws {
        let repository = FakeChatThreadRepository()
        let scope = try trainingSubject()
        let low = try Fixture.thread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            subject: scope,
            lastActivityAt: Fixture.epoch
        )
        let high = try Fixture.thread(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID(),
            subject: scope,
            lastActivityAt: Fixture.epoch
        )

        try await repository.store(low)
        try await repository.store(high)

        for _ in 0..<20 {
            let resolved = try await repository.mostRecentThread(for: scope)
            XCTAssertEqual(resolved, high)
        }
    }

    /// The two orderings must agree, or the list's top row for a subject is not the
    /// thread tapping Ask opens — a small, durable lie that would only ever appear on
    /// the tie nobody tests by hand. Asserted against the tie specifically, because
    /// that is the only case where the two rules could differ.
    func testTheListsTopRowIsTheThreadTheAskButtonOpens() async throws {
        let repository = FakeChatThreadRepository()
        let scope = try trainingSubject()
        let low = try Fixture.thread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            subject: scope,
            lastActivityAt: Fixture.epoch
        )
        let high = try Fixture.thread(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID(),
            subject: scope,
            lastActivityAt: Fixture.epoch
        )

        try await repository.store(low)
        try await repository.store(high)
        let opened = try await repository.mostRecentThread(for: scope)
        let summaries = try await repository.threadSummaries()

        XCTAssertEqual(summaries.first?.id, opened?.id)
    }

    // MARK: - The list (§2.3)

    func testSummariesComeBackNewestActivityFirst() async throws {
        let repository = FakeChatThreadRepository()
        let oldest = try Fixture.thread(subject: workoutSubject, lastActivityAt: Fixture.at(0))
        let middle = try Fixture.thread(
            subject: try trainingSubject(from: (2026, 8, 1), through: (2026, 8, 31)),
            lastActivityAt: Fixture.at(500)
        )
        let newest = try Fixture.thread(
            subject: try trainingSubject(from: (2026, 9, 1), through: (2026, 9, 30)),
            lastActivityAt: Fixture.at(1_000)
        )

        for thread in [middle, newest, oldest] {
            try await repository.store(thread)
        }
        let summaries = try await repository.threadSummaries()

        XCTAssertEqual(summaries.map(\.id), [newest.id, middle.id, oldest.id])
    }

    /// A summary is what a row draws, so it has to carry the row's whole content —
    /// including a title derived without a model call (§2.4).
    func testSummariesCarryTheDerivedTitleAndPreview() async throws {
        let repository = FakeChatThreadRepository()
        repository.register(
            WorkoutThreadFacts(day: try Fixture.day(2026, 8, 3), activityType: .running),
            forWorkout: Fixture.workoutID
        )
        let thread = try Fixture.thread(
            subject: workoutSubject,
            messages: [
                try message(.user, "Was that on plan?", at: 0),
                try message(.assistant, "Yes — Tuesday is an 8 km easy run.", at: 10),
            ]
        )

        try await repository.store(thread)
        let summaries = try await repository.threadSummaries()
        let summary = try XCTUnwrap(summaries.first)

        XCTAssertEqual(summary.id, thread.id)
        XCTAssertEqual(summary.subject, workoutSubject)
        XCTAssertEqual(summary.title, "3 Aug 2026 · Running")
        XCTAssertEqual(summary.preview, "Yes — Tuesday is an 8 km easy run.")
        XCTAssertEqual(summary.lastActivityAt, Fixture.at(10))
    }

    // MARK: - Create-or-fetch (§2.2)

    /// "Create" means minted, not written: a stray tap of a button that is now on every
    /// screen must not leave an empty thread in §2.3's list.
    func testCreateOrFetchMintsAThreadWithoutStoringIt() async throws {
        let repository = FakeChatThreadRepository()
        let newID = UUID()

        let thread = try await repository.thread(
            for: workoutSubject,
            newThreadID: newID,
            at: Fixture.at(42)
        )

        XCTAssertEqual(thread.id, newID)
        XCTAssertEqual(thread.subject, workoutSubject)
        XCTAssertEqual(thread.lastActivityAt, Fixture.at(42))
        XCTAssertTrue(thread.isEmpty)
        XCTAssertEqual(repository.threadCount, 0, "nothing reached storage")
        XCTAssertEqual(repository.writes, 0)
    }

    func testCreateOrFetchReturnsTheExistingThreadRatherThanAFreshOne() async throws {
        let repository = FakeChatThreadRepository()
        let existing = try Fixture.thread(
            subject: workoutSubject,
            messages: [try message(.user, "Was that on plan?", at: 0)]
        )
        try await repository.store(existing)

        let resolved = try await repository.thread(
            for: workoutSubject,
            newThreadID: UUID(),
            at: Fixture.at(9_999)
        )

        XCTAssertEqual(resolved, existing)
        XCTAssertEqual(repository.threadCount, 1)
    }

    // MARK: - Deleting (§2.3's swipe)

    func testDeletingRemovesOnlyThatThread() async throws {
        let repository = FakeChatThreadRepository()
        let doomed = try Fixture.thread(subject: workoutSubject, lastActivityAt: Fixture.at(0))
        let survivor = try Fixture.thread(subject: otherWorkoutSubject, lastActivityAt: Fixture.at(10))
        try await repository.store(doomed)
        try await repository.store(survivor)

        try await repository.deleteThread(id: doomed.id)
        let deleted = try await repository.thread(id: doomed.id)
        let bySubject = try await repository.mostRecentThread(for: workoutSubject)
        let summaries = try await repository.threadSummaries()

        XCTAssertNil(deleted)
        XCTAssertNil(bySubject)
        XCTAssertEqual(summaries.map(\.id), [survivor.id])
    }

    /// A row deleted on another device and again here is an ordinary race, not a failure
    /// — the same contract `deleteWorkout(id:)` carries.
    func testDeletingAnUnknownThreadIsANoOp() async throws {
        let repository = FakeChatThreadRepository()
        try await repository.deleteThread(id: UUID())
        XCTAssertEqual(repository.threadCount, 0)
    }

    // MARK: - Ordering and failure

    /// Ordering is durable because it is an explicit, validated property of the domain
    /// type (`ChatThread.init`, `ChatMessage.timestamp`) — not incidental row order from
    /// a store. Round-tripping through the repository must not disturb it.
    func testOrderingSurvivesStoreAndRead() async throws {
        let repository = FakeChatThreadRepository()
        var thread = try Fixture.thread(subject: workoutSubject)
        thread = try thread.appending(message(.user, "Why did my HR drift at mile 3?", at: 0))
        thread = try thread.appending(message(.assistant, "Your second half averaged 8 bpm higher.", at: 4))
        thread = try thread.appending(message(.user, "Was that expected?", at: 30))

        try await repository.store(thread)
        let restored = try await repository.thread(id: thread.id)

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
        let thread = try Fixture.thread(
            subject: workoutSubject,
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
            _ = try await repository.mostRecentThread(for: workoutSubject)
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
        let thread = try Fixture.thread(
            subject: workoutSubject,
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
