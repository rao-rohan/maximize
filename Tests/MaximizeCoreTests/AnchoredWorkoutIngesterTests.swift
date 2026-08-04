import XCTest
import Foundation
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// FR-0.2, exercised without a health store.
///
/// These tests are the only verification this ticket gets. HealthKit cannot run in CI and
/// the failure this code exists to prevent — a workout that silently never appears — has no
/// symptom on a device either: nothing crashes, nothing is logged, a run is simply absent
/// and nobody knows to look. So the anchor rules, the dedupe and the ordering were put
/// somewhere a fake can drive them, and this file drives them hard.
final class AnchoredWorkoutIngesterTests: XCTestCase {
    // MARK: - First run

    func testAFirstPassFetchesWithoutAnAnchor() async throws {
        let fetcher = FakeWorkoutFetcher()
        let ingester = makeIngester(fetcher: fetcher, anchorStore: InMemoryWorkoutQueryAnchorStore())

        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(fetcher.receivedRequests.count, 1)
        XCTAssertNil(fetcher.receivedRequests.first?.anchor)
    }

    func testAFirstPassBoundsHowFarBackItReaches() async throws {
        // An unbounded first fetch would ask a phone with years of Health history for
        // every workout it has ever held, in a background wake with an unspecified budget.
        let fetcher = FakeWorkoutFetcher()
        let ingester = makeIngester(
            fetcher: fetcher,
            anchorStore: InMemoryWorkoutQueryAnchorStore(),
            policy: try AnchoredIngestionPolicy(batchLimit: 50, maxBatchesPerPass: 5, firstRunBackfill: 86_400)
        )

        try await ingester.ingestPendingWorkouts()

        let earliest = try XCTUnwrap(fetcher.receivedRequests.first?.earliestWorkoutStart)
        XCTAssertEqual(earliest, Self.testNow.addingTimeInterval(-86_400))
    }

    func testAnAnchoredPassCarriesNoDateBound() async throws {
        // The bound exists to make the *first* fetch finite. Applying it to an anchored
        // fetch would drop a workout that synced late while the anchor advanced past it,
        // which is exactly the silent loss the anchor is supposed to prevent.
        let fetcher = FakeWorkoutFetcher()
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(1))
        let ingester = makeIngester(fetcher: fetcher, anchorStore: store)

        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(fetcher.receivedRequests.first?.anchor, Self.anchor(1))
        XCTAssertNil(fetcher.receivedRequests.first?.earliestWorkoutStart)
    }

    // MARK: - The anchor persists, and resumes

    func testTheAnchorFromASuccessfulBatchIsPersisted() async throws {
        let fetcher = FakeWorkoutFetcher()
        let store = InMemoryWorkoutQueryAnchorStore()
        fetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(7)))

        try await makeIngester(fetcher: fetcher, anchorStore: store).ingestPendingWorkouts()

        XCTAssertEqual(store.currentAnchor, Self.anchor(7))
    }

    func testAFreshIngesterResumesFromThePersistedAnchor() async throws {
        // This is FR-0.2's "across relaunches". A relaunch cannot be staged in CI, but what
        // a relaunch actually does is discard every in-memory ingester and build a new one
        // against the same durable store — which is precisely what happens below.
        let store = InMemoryWorkoutQueryAnchorStore()
        let firstFetcher = FakeWorkoutFetcher()
        firstFetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(3)))
        try await makeIngester(fetcher: firstFetcher, anchorStore: store).ingestPendingWorkouts()

        let secondFetcher = FakeWorkoutFetcher()
        try await makeIngester(fetcher: secondFetcher, anchorStore: store).ingestPendingWorkouts()

        XCTAssertEqual(secondFetcher.receivedRequests.first?.anchor, Self.anchor(3))
        XCTAssertNil(secondFetcher.receivedRequests.first?.earliestWorkoutStart)
    }

    // MARK: - Idempotency (FR-0.5)

    func testARedeliveredWorkoutIsIngestedOnlyOnce() async throws {
        // The platform delivers at least once, not exactly once (PRD §11), and the
        // anchor-last ordering below deliberately trades duplicates for durability. Both
        // land here.
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [workout], anchor: Self.anchor(1)),
            try Self.batch(workouts: [workout], anchor: Self.anchor(2))
        )
        let sink = RecordingWorkoutIngestionSink()
        let ingester = makeIngester(fetcher: fetcher, sink: sink)

        try await ingester.ingestPendingWorkouts()
        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.count, 1)
        XCTAssertEqual(sink.ingestedWorkouts.first?.id, workout.id)
    }

    func testADuplicateInsideOneBatchIsIngestedOnce() async throws {
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [workout, workout], anchor: Self.anchor(1)))
        let sink = RecordingWorkoutIngestionSink()

        try await makeIngester(fetcher: fetcher, sink: sink).ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.count, 1)
    }

    // MARK: - Anchor advancement discipline

    func testTheAnchorIsNotWrittenBeforeTheWorkoutIsIngested() async throws {
        // The ordering the whole ticket turns on. If the anchor moved first, a crash here
        // would lose this workout permanently — the store would never offer it again.
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(1)))
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()
        let observed = ObservedCount()
        sink.onIngest { _ in observed.record(store.savedAnchors.count) }

        try await makeIngester(fetcher: fetcher, anchorStore: store, sink: sink).ingestPendingWorkouts()

        // Defaulting to a non-zero value makes a hook that never ran fail rather than pass.
        XCTAssertEqual(observed.value ?? -1, 0)
        XCTAssertEqual(store.savedAnchors.count, 1)
    }

    func testAFailedIngestLeavesTheAnchorWhereItWas() async throws {
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(9)))
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(1))
        let sink = RecordingWorkoutIngestionSink()
        sink.failAllIngests(with: SinkFailure.simulated)

        await XCTAssertThrowsErrorAsync(
            try await makeIngester(fetcher: fetcher, anchorStore: store, sink: sink).ingestPendingWorkouts()
        )

        XCTAssertEqual(store.currentAnchor, Self.anchor(1))
        XCTAssertTrue(store.savedAnchors.isEmpty)
    }

    func testAWorkoutMissedByAFailedPassIsPickedUpByTheNextOne() async throws {
        // MAX-030 acknowledges failed wakes, so iOS never retries. This test is the
        // reason that is survivable: recovery comes from the anchor, not from the platform.
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [workout], anchor: Self.anchor(1)),
            try Self.batch(workouts: [workout], anchor: Self.anchor(1))
        )
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()
        sink.failAllIngests(with: SinkFailure.simulated)
        let ingester = makeIngester(fetcher: fetcher, anchorStore: store, sink: sink)

        await XCTAssertThrowsErrorAsync(try await ingester.ingestPendingWorkouts())
        XCTAssertTrue(sink.ingestedWorkouts.isEmpty)

        sink.stopFailing()
        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.map(\.id), [workout.id])
        XCTAssertEqual(store.currentAnchor, Self.anchor(1))
    }

    func testACrashBetweenIngestAndAnchorSaveReplaysWithoutDuplicating() async throws {
        // The failure mode the anchor-last ordering accepts, played out: the workout is
        // durable, the anchor write is lost, the batch comes back. Idempotency absorbs it.
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [workout], anchor: Self.anchor(4)),
            try Self.batch(workouts: [workout], anchor: Self.anchor(4))
        )
        let store = InMemoryWorkoutQueryAnchorStore()
        store.failSaves()
        let sink = RecordingWorkoutIngestionSink()
        let ingester = makeIngester(fetcher: fetcher, anchorStore: store, sink: sink)

        await XCTAssertThrowsErrorAsync(try await ingester.ingestPendingWorkouts())
        XCTAssertEqual(sink.ingestedWorkouts.count, 1, "the workout was stored before the anchor write failed")
        XCTAssertNil(store.currentAnchor)

        store.stopFailing()
        try await ingester.ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.count, 1, "re-delivery must be a no-op, not a second record")
        XCTAssertEqual(store.currentAnchor, Self.anchor(4))
    }

    // MARK: - Deletions

    func testDeletionsAreForwardedAndTheAnchorAdvancesPastThem() async throws {
        // A deletion is reported exactly once by the platform, so it lives under the same
        // rule as an addition: hand it off first, move the anchor second.
        let deletedID = UUID()
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [], deletedWorkoutIDs: [deletedID], anchor: Self.anchor(2)))
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()

        try await makeIngester(fetcher: fetcher, anchorStore: store, sink: sink).ingestPendingWorkouts()

        XCTAssertEqual(sink.discardedWorkoutIDs, [deletedID])
        XCTAssertEqual(store.currentAnchor, Self.anchor(2))
    }

    func testAFailedDeletionLeavesTheAnchorWhereItWas() async throws {
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [], deletedWorkoutIDs: [UUID()], anchor: Self.anchor(2)))
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = ThrowingDiscardSink()

        await XCTAssertThrowsErrorAsync(
            try await makeIngester(fetcher: fetcher, anchorStore: store, sink: sink).ingestPendingWorkouts()
        )

        XCTAssertNil(store.currentAnchor)
    }

    func testADeletionInTheSameBatchWinsOverTheAddition() async throws {
        // Additions are applied before deletions so the end state matches what the health
        // store is describing: a workout added and then removed is removed.
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [workout], deletedWorkoutIDs: [workout.id], anchor: Self.anchor(1))
        )
        let sink = RecordingWorkoutIngestionSink()

        try await makeIngester(fetcher: fetcher, sink: sink).ingestPendingWorkouts()

        XCTAssertTrue(sink.ingestedWorkouts.isEmpty)
        XCTAssertEqual(sink.discardedWorkoutIDs, [workout.id])
    }

    // MARK: - A stored anchor the platform will not accept

    func testAnUnusableStoredAnchorIsDiscardedAndTheFetchStartsOver() async throws {
        // Failing closed here would end zero-touch capture permanently over one corrupt
        // byte, with no symptom. Failing open costs a redundant read of the backfill window.
        let fetcher = FakeWorkoutFetcher()
        fetcher.rejectAnchoredRequests()
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(5))
        let diagnostics = DiagnosticRecorder()

        try await makeIngester(
            fetcher: fetcher,
            anchorStore: store,
            diagnostics: diagnostics
        ).ingestPendingWorkouts()

        XCTAssertEqual(fetcher.receivedRequests.count, 2)
        XCTAssertEqual(fetcher.receivedRequests.first?.anchor, Self.anchor(5))
        XCTAssertNil(fetcher.receivedRequests.last?.anchor)
        XCTAssertNotNil(fetcher.receivedRequests.last?.earliestWorkoutStart)
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertEqual(diagnostics.reported, [.storedAnchorDiscarded(reason: .unusable)])
    }

    func testWorkoutsAreStillIngestedAfterAnUnusableAnchorIsDiscarded() async throws {
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.rejectAnchoredRequests()
        fetcher.enqueue(try Self.batch(workouts: [workout], anchor: Self.anchor(6)))
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(5))
        let sink = RecordingWorkoutIngestionSink()

        try await makeIngester(fetcher: fetcher, anchorStore: store, sink: sink).ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.map(\.id), [workout.id])
        XCTAssertEqual(store.currentAnchor, Self.anchor(6))
    }

    func testTheUnusableAnchorRecoveryIsAttemptedOnlyOnce() async throws {
        // An unanchored request that still comes back `.unusableAnchor` is a fetcher bug,
        // not a corrupt anchor. Retrying it forever would spin; the error propagates.
        let fetcher = AlwaysUnusableAnchorFetcher()
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(5))

        await XCTAssertThrowsErrorAsync(
            try await makeIngester(fetcher: fetcher, anchorStore: store).ingestPendingWorkouts()
        )

        XCTAssertEqual(fetcher.fetchCount, 2)
    }

    func testAnUnreadableAnchorStoreFallsBackToAFirstRunFetch() async throws {
        let fetcher = FakeWorkoutFetcher()
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(5))
        store.failLoads()
        let diagnostics = DiagnosticRecorder()

        try await makeIngester(
            fetcher: fetcher,
            anchorStore: store,
            diagnostics: diagnostics
        ).ingestPendingWorkouts()

        XCTAssertEqual(fetcher.receivedRequests.count, 1)
        XCTAssertNil(fetcher.receivedRequests.first?.anchor)
        XCTAssertEqual(diagnostics.reported, [.storedAnchorDiscarded(reason: .unreadable)])
    }

    // MARK: - Paging

    func testFullBatchesArePagedUntilTheStoreIsDrained() async throws {
        let first = [try Fixture.workout(id: UUID()), try Fixture.workout(id: UUID())]
        let second = [try Fixture.workout(id: UUID())]
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: first, anchor: Self.anchor(1)),
            try Self.batch(workouts: second, anchor: Self.anchor(2))
        )
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()
        let policy = try AnchoredIngestionPolicy(batchLimit: 2, maxBatchesPerPass: 10, firstRunBackfill: nil)

        try await makeIngester(
            fetcher: fetcher,
            anchorStore: store,
            sink: sink,
            policy: policy
        ).ingestPendingWorkouts()

        XCTAssertEqual(sink.ingestedWorkouts.count, 3)
        // One anchor write per batch, not one per pass: a pass that stops halfway keeps
        // the ground it took.
        XCTAssertEqual(store.savedAnchors, [Self.anchor(1), Self.anchor(2)])
    }

    func testAPassStopsAtItsBatchCapAndTheNextPassResumes() async throws {
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(1)),
            try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(2))
        )
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()
        let diagnostics = DiagnosticRecorder()
        let policy = try AnchoredIngestionPolicy(batchLimit: 1, maxBatchesPerPass: 1, firstRunBackfill: nil)
        let ingester = makeIngester(
            fetcher: fetcher,
            anchorStore: store,
            sink: sink,
            policy: policy,
            diagnostics: diagnostics
        )

        try await ingester.ingestPendingWorkouts()
        XCTAssertEqual(sink.ingestedWorkouts.count, 1)
        XCTAssertEqual(diagnostics.reported, [.passTruncated(batchesProcessed: 1)])

        try await ingester.ingestPendingWorkouts()
        XCTAssertEqual(sink.ingestedWorkouts.count, 2)
        XCTAssertEqual(fetcher.receivedRequests.last?.anchor, Self.anchor(1))
    }

    func testAFullBatchThatDoesNotMoveTheAnchorStopsThePass() async throws {
        // Defensive: a fetcher that ignored the anchor would otherwise loop until the
        // batch cap, refetching the same objects.
        let workout = try Fixture.workout(id: UUID())
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(
            try Self.batch(workouts: [workout], anchor: Self.anchor(1)),
            try Self.batch(workouts: [workout], anchor: Self.anchor(1))
        )
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(1))
        let policy = try AnchoredIngestionPolicy(batchLimit: 1, maxBatchesPerPass: 10, firstRunBackfill: nil)

        try await makeIngester(fetcher: fetcher, anchorStore: store, policy: policy).ingestPendingWorkouts()

        XCTAssertEqual(fetcher.receivedRequests.count, 1)
    }

    func testAnIdlePassDoesNotRewriteAnUnchangedAnchor() async throws {
        let fetcher = FakeWorkoutFetcher()
        fetcher.setEmptyBatchAnchor(Self.anchor(1))
        let store = InMemoryWorkoutQueryAnchorStore(anchor: Self.anchor(1))

        try await makeIngester(fetcher: fetcher, anchorStore: store).ingestPendingWorkouts()

        XCTAssertTrue(store.savedAnchors.isEmpty)
    }

    // MARK: - Records the domain cannot represent

    func testUnrepresentableObjectsAreReportedAndTheAnchorAdvancesPastThem() async throws {
        // Pinning the anchor on a record that can never be accepted would queue every
        // later workout behind it forever. Losing one unrepresentable record is the
        // smaller loss, and it is reported rather than silent.
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [], unrepresentableWorkoutCount: 2, anchor: Self.anchor(3)))
        let store = InMemoryWorkoutQueryAnchorStore()
        let diagnostics = DiagnosticRecorder()

        try await makeIngester(
            fetcher: fetcher,
            anchorStore: store,
            diagnostics: diagnostics
        ).ingestPendingWorkouts()

        XCTAssertEqual(diagnostics.reported, [.workoutsUnrepresentable(count: 2)])
        XCTAssertEqual(store.currentAnchor, Self.anchor(3))
    }

    // MARK: - Overlapping wakes

    func testOverlappingPassesAreSerialisedRatherThanInterleaved() async throws {
        // Two background wakes can overlap. Two passes sharing one anchor could let the
        // later one persist an anchor covering workouts the earlier one had not stored —
        // the anchor-first failure, reached by accident instead of by choice.
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(1)))
        let store = InMemoryWorkoutQueryAnchorStore()
        let sink = RecordingWorkoutIngestionSink()
        let observed = ObservedCount()
        sink.onIngestAsync { _ in
            // Hold the first pass open long enough for a concurrent one to overtake it,
            // if it could.
            try? await Task.sleep(nanoseconds: 150_000_000)
            observed.record(fetcher.fetchCount)
        }
        let ingester = makeIngester(fetcher: fetcher, anchorStore: store, sink: sink)

        async let first: Void = ingester.ingestPendingWorkouts()
        async let second: Void = ingester.ingestPendingWorkouts()
        _ = try await (first, second)

        XCTAssertEqual(observed.value ?? -1, 1, "a second fetch started while the first pass was mid-ingest")
        XCTAssertEqual(sink.ingestedWorkouts.count, 1)
        // The decisive assertion: the second pass saw the anchor the first pass wrote.
        XCTAssertEqual(fetcher.receivedRequests.count, 2)
        XCTAssertEqual(fetcher.receivedRequests.last?.anchor, Self.anchor(1))
    }

    func testAPassIsNotFailedByItsPredecessorsFailure() async throws {
        // Passes are chained, so each one awaits the previous. It must await its
        // *completion* and not adopt its outcome — one wake failing is not the next
        // wake's problem, and a chain that propagated failures would fail forever.
        let fetcher = FakeWorkoutFetcher()
        fetcher.failNextFetch(with: SinkFailure.simulated)
        let ingester = makeIngester(fetcher: fetcher)

        await XCTAssertThrowsErrorAsync(try await ingester.ingestPendingWorkouts())

        try await ingester.ingestPendingWorkouts()
        XCTAssertEqual(fetcher.receivedRequests.count, 2)
    }

    // MARK: - The placeholder sink

    func testTheAwaitingPipelineSinkPinsTheAnchorRatherThanLosingWorkouts() async throws {
        // Until MAX-032/033 land, a sink that quietly accepted workouts would let the
        // anchor advance past real runs and they would be gone. Throwing keeps them.
        let fetcher = FakeWorkoutFetcher()
        fetcher.enqueue(try Self.batch(workouts: [try Fixture.workout(id: UUID())], anchor: Self.anchor(1)))
        let store = InMemoryWorkoutQueryAnchorStore()

        await XCTAssertThrowsErrorAsync(
            try await makeIngester(
                fetcher: fetcher,
                anchorStore: store,
                sink: AwaitingPipelineWorkoutSink()
            ).ingestPendingWorkouts()
        )

        XCTAssertNil(store.currentAnchor)
    }

    // MARK: - Value validation

    func testAFetchRequestRejectsANonPositiveBatchLimit() {
        assertThrows(.outOfRange, try WorkoutFetchRequest(anchor: nil, earliestWorkoutStart: nil, batchLimit: 0))
    }

    func testAFetchRequestRejectsADateBoundOnAnAnchoredFetch() {
        assertThrows(
            .inconsistent,
            try WorkoutFetchRequest(
                anchor: Self.anchor(1),
                earliestWorkoutStart: Fixture.epoch,
                batchLimit: 10
            )
        )
    }

    func testAPolicyRejectsNonPositiveBounds() {
        assertThrows(.outOfRange, try AnchoredIngestionPolicy(batchLimit: 0, maxBatchesPerPass: 1, firstRunBackfill: nil))
        assertThrows(.outOfRange, try AnchoredIngestionPolicy(batchLimit: 1, maxBatchesPerPass: 0, firstRunBackfill: nil))
        assertThrows(.outOfRange, try AnchoredIngestionPolicy(batchLimit: 1, maxBatchesPerPass: 1, firstRunBackfill: 0))
    }

    func testAFetchBatchRejectsANegativeUnrepresentableCount() {
        assertThrows(
            .outOfRange,
            try WorkoutFetchBatch(workouts: [], unrepresentableWorkoutCount: -1, anchor: Self.anchor(1))
        )
    }

    // MARK: - Helpers

    private static let testNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static func anchor(_ byte: UInt8) -> WorkoutQueryAnchor {
        WorkoutQueryAnchor(opaqueData: Data([byte]))
    }

    private static func batch(
        workouts: [Workout],
        deletedWorkoutIDs: [UUID] = [],
        unrepresentableWorkoutCount: Int = 0,
        anchor: WorkoutQueryAnchor
    ) throws -> WorkoutFetchBatch {
        try WorkoutFetchBatch(
            workouts: workouts,
            deletedWorkoutIDs: deletedWorkoutIDs,
            unrepresentableWorkoutCount: unrepresentableWorkoutCount,
            anchor: anchor
        )
    }

    private func makeIngester(
        fetcher: WorkoutFetching,
        anchorStore: WorkoutQueryAnchorStore = InMemoryWorkoutQueryAnchorStore(),
        sink: WorkoutIngestionSink = RecordingWorkoutIngestionSink(),
        policy: AnchoredIngestionPolicy = .standard,
        diagnostics: DiagnosticRecorder? = nil
    ) -> AnchoredWorkoutIngester {
        AnchoredWorkoutIngester(
            fetcher: fetcher,
            anchorStore: anchorStore,
            sink: sink,
            policy: policy,
            now: { Self.testNow },
            report: diagnostics?.handler() ?? { _ in }
        )
    }
}

private enum SinkFailure: Error {
    case simulated
}

/// A sink that accepts workouts but refuses deletions, so the anchor rule can be checked
/// on the deletion path independently.
private final class ThrowingDiscardSink: WorkoutIngestionSink {
    func hasIngestedWorkout(id: UUID) async throws -> Bool { false }
    func ingest(_ workout: Workout) async throws {}
    func discardWorkout(id: UUID) async throws { throw SinkFailure.simulated }
}

/// A fetcher that rejects every request, anchored or not — a broken adapter rather than a
/// corrupt anchor.
private final class AlwaysUnusableAnchorFetcher: WorkoutFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func fetchWorkouts(_ request: WorkoutFetchRequest) async throws -> WorkoutFetchBatch {
        lock.lock()
        calls += 1
        lock.unlock()
        throw WorkoutFetchError.unusableAnchor
    }
}

/// A single observation made from inside a hook, recorded across concurrency domains.
private final class ObservedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: Int?

    var value: Int? {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    func record(_ count: Int) {
        lock.lock()
        if observed == nil { observed = count }
        lock.unlock()
    }
}

/// `XCTAssertThrowsError` does not accept an `async` expression.
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}
