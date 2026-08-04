import XCTest
import Foundation
@testable import MaximizeCore

/// The "call it exactly once" half of HealthKit's observer-query contract, checked
/// without HealthKit. See `BackgroundDeliveryAcknowledgement` for why the cost of
/// getting this wrong is a silently dead capture pipeline.
final class BackgroundDeliveryAcknowledgementTests: XCTestCase {
    func testAcknowledgeRunsTheHandler() {
        let recorder = AcknowledgementCounter()
        let acknowledgement = BackgroundDeliveryAcknowledgement { recorder.increment() }

        acknowledgement.acknowledge()

        XCTAssertEqual(recorder.value, 1)
    }

    func testHandlerDoesNotRunUntilAcknowledged() {
        let recorder = AcknowledgementCounter()
        _ = BackgroundDeliveryAcknowledgement { recorder.increment() }

        XCTAssertEqual(recorder.value, 0)
    }

    func testSecondAcknowledgementIsANoOp() {
        let recorder = AcknowledgementCounter()
        let acknowledgement = BackgroundDeliveryAcknowledgement { recorder.increment() }

        acknowledgement.acknowledge()
        acknowledgement.acknowledge()
        acknowledgement.acknowledge()

        XCTAssertEqual(recorder.value, 1)
    }

    func testAcknowledgeReportsWhetherItWasTheCallThatRanTheHandler() {
        let acknowledgement = BackgroundDeliveryAcknowledgement {}

        XCTAssertTrue(acknowledgement.acknowledge())
        XCTAssertFalse(acknowledgement.acknowledge())
    }

    func testHasAcknowledgedTracksState() {
        let acknowledgement = BackgroundDeliveryAcknowledgement {}
        XCTAssertFalse(acknowledgement.hasAcknowledged)

        acknowledgement.acknowledge()

        XCTAssertTrue(acknowledgement.hasAcknowledged)
    }

    func testConcurrentAcknowledgementsStillRunTheHandlerOnce() {
        // HealthKit invokes observer update handlers on an anonymous background queue,
        // so the wake path is not single-threaded by construction. A racing double
        // acknowledgement must not become a double-count.
        let recorder = AcknowledgementCounter()
        let acknowledgement = BackgroundDeliveryAcknowledgement { recorder.increment() }

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            acknowledgement.acknowledge()
        }

        XCTAssertEqual(recorder.value, 1)
    }
}

/// Minimal thread-safe counter. Local to this file because it exists only to observe
/// a closure that otherwise has no return value.
private final class AcknowledgementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
