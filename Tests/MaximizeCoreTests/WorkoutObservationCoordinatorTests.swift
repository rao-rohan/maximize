import XCTest
import Foundation
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// The consequences of a background wake, exercised without a Health store.
///
/// Every assertion here is about behaviour the real pipeline depends on and that a
/// device run would only reveal by *not happening* — a run that never appears, or
/// background delivery quietly ceasing after three wakes. That is the whole argument
/// for the protocol seam: HealthKit cannot be exercised in CI (tracker R2), so the
/// decisions were moved somewhere that can be.
final class WorkoutObservationCoordinatorTests: XCTestCase {
    func testAWakeTriggersIngestion() async {
        let ingester = FakeWorkoutIngester()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        XCTAssertEqual(ingester.ingestCallCount, 1)
    }

    func testAWakeIsAcknowledged() async {
        let ingester = FakeWorkoutIngester()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
    }

    func testAcknowledgementHappensAfterIngestionNotBefore() async {
        // Apple: "After your observer queries have finished processing the new data,
        // you must call the update's completion handler." Acknowledging first would
        // let iOS suspend the app mid-fetch while everything still looked healthy.
        let ingester = FakeWorkoutIngester()
        let acknowledgements = AcknowledgementRecorder()
        let observedMidIngest = MidIngestObservation()
        ingester.onIngest {
            observedMidIngest.record(hasAcknowledged: acknowledgements.hasAcknowledged)
        }
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        // Defaulting to `true` makes a hook that never ran fail the test rather than
        // pass it vacuously.
        XCTAssertFalse(observedMidIngest.hasAcknowledged ?? true)
        XCTAssertTrue(acknowledgements.hasAcknowledged)
    }

    func testAcknowledgementStillHappensWhenIngestionFails() async {
        // The asymmetry that drives this design: a dropped wake costs a delayed run,
        // which the anchored fetch recovers on the next wake. A missing acknowledgement
        // three times over costs background delivery entirely, permanently, silently.
        let ingester = FakeWorkoutIngester()
        ingester.failNextIngests(with: IngestionFailure.simulated)
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
    }

    func testIngestionFailureIsReportedRatherThanSwallowed() async {
        let ingester = FakeWorkoutIngester()
        ingester.failNextIngests(with: IngestionFailure.simulated)
        let reported = ReportedErrors()
        let coordinator = WorkoutObservationCoordinator(
            ingester: ingester,
            reportFailure: { reported.record($0) }
        )

        await coordinator.workoutsMayHaveChanged(acknowledge: {})

        XCTAssertEqual(reported.descriptions, [String(describing: IngestionFailure.simulated)])
    }

    func testAnErroredWakeStillIngestsAndStillAcknowledges() async {
        // An error from the observation mechanism says nothing about whether the store
        // gained a workout. Skipping the fetch would trade a cheap redundant query for
        // a missed run.
        let ingester = FakeWorkoutIngester()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await coordinator.workoutsMayHaveChanged(
            observationError: IngestionFailure.simulated,
            acknowledge: acknowledgements.handler()
        )

        XCTAssertEqual(ingester.ingestCallCount, 1)
        XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
    }

    func testAnErroredWakeIsReported() async {
        let reported = ReportedErrors()
        let coordinator = WorkoutObservationCoordinator(
            ingester: FakeWorkoutIngester(),
            reportFailure: { reported.record($0) }
        )

        await coordinator.workoutsMayHaveChanged(
            observationError: IngestionFailure.simulated,
            acknowledge: {}
        )

        XCTAssertEqual(reported.descriptions, [String(describing: IngestionFailure.simulated)])
    }

    func testEachWakeIsAcknowledgedExactlyOnce() async {
        // iOS may wake the app repeatedly. Each delivery gets its own acknowledgement:
        // never zero, never doubled.
        let ingester = FakeWorkoutIngester()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        for _ in 0..<5 {
            let acknowledgements = AcknowledgementRecorder()
            await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())
            XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
        }

        XCTAssertEqual(ingester.ingestCallCount, 5)
    }

    func testConcurrentWakesEachGetTheirOwnAcknowledgement() async {
        let ingester = FakeWorkoutIngester()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(ingester: ingester)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await coordinator.workoutsMayHaveChanged(
                        acknowledge: acknowledgements.handler()
                    )
                }
            }
        }

        XCTAssertEqual(acknowledgements.acknowledgementCount, 8)
        XCTAssertEqual(ingester.ingestCallCount, 8)
    }

    func testARealAnchoredIngesterIsDrivenByAWakeAndAcknowledged() async throws {
        // The seam, with MAX-031's actual implementation on the far side of it rather
        // than a fake: a wake performs an anchored fetch and is acknowledged exactly once.
        let fetcher = FakeWorkoutFetcher()
        let anchorStore = InMemoryWorkoutQueryAnchorStore()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(
            ingester: AnchoredWorkoutIngester(
                fetcher: fetcher,
                anchorStore: anchorStore,
                sink: RecordingWorkoutIngestionSink()
            )
        )

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        XCTAssertEqual(fetcher.fetchCount, 1)
        XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
    }

    func testAWakeIsStillAcknowledgedWhenTheAnchoredIngesterFails() async {
        // The load-bearing pairing (tracker R9): the anchored ingester leaves its anchor
        // untouched on failure, and the coordinator acknowledges anyway. Neither half is
        // safe without the other.
        let fetcher = FakeWorkoutFetcher()
        fetcher.failNextFetch(with: IngestionFailure.simulated)
        let anchorStore = InMemoryWorkoutQueryAnchorStore()
        let acknowledgements = AcknowledgementRecorder()
        let coordinator = WorkoutObservationCoordinator(
            ingester: AnchoredWorkoutIngester(
                fetcher: fetcher,
                anchorStore: anchorStore,
                sink: RecordingWorkoutIngestionSink()
            )
        )

        await coordinator.workoutsMayHaveChanged(acknowledge: acknowledgements.handler())

        XCTAssertEqual(acknowledgements.acknowledgementCount, 1)
        XCTAssertNil(anchorStore.currentAnchor)
    }
}

private enum IngestionFailure: Error {
    case simulated
}

/// Captures a single observation made from inside the ingest call.
private final class MidIngestObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: Bool?

    var hasAcknowledged: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    func record(hasAcknowledged: Bool) {
        lock.lock()
        observed = hasAcknowledged
        lock.unlock()
    }
}

/// Collects errors handed to the coordinator's failure hook.
///
/// Stores `String(describing:)` rather than the errors themselves, mirroring the rule
/// that this hook must never carry health data anywhere durable.
private final class ReportedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []

    var descriptions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    func record(_ error: Error) {
        lock.lock()
        collected.append(String(describing: error))
        lock.unlock()
    }
}
