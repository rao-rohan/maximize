import Foundation
import MaximizeCore

/// A scripted `WorkoutSampleFetching`.
///
/// Heart-rate pages are queued and handed out one per call — the same "script a
/// sequence, then assert what was asked for" shape as `FakeWorkoutFetcher` — which is
/// what lets a test drive multi-page extraction, a truncated fetch, and a fetch that
/// fails partway, none of which a real health store can be made to do on demand.
public final class FakeWorkoutSampleFetcher: WorkoutSampleFetching, @unchecked Sendable {
    private let lock = NSLock()

    private var queuedHeartRatePages: [HeartRateSampleFetchPage] = []
    private var heartRateRequests: [HeartRateSampleFetchRequest] = []
    private var heartRateErrorForNextFetch: Error?

    private var routeResult = RouteFetchResult(points: nil)
    private var routeRequests: [RouteFetchRequest] = []
    private var routeError: Error?

    private var stepCount: Double?
    private var stepCountError: Error?
    private var stepCountRequests = 0

    public init() {}

    /// Every heart-rate request received, in order — what a test asserts against to
    /// show that the second page resumed after the first page's last sample.
    public var receivedHeartRateRequests: [HeartRateSampleFetchRequest] {
        lock.locked { heartRateRequests }
    }

    public var receivedRouteRequests: [RouteFetchRequest] {
        lock.locked { routeRequests }
    }

    public var stepCountRequestCount: Int {
        lock.locked { stepCountRequests }
    }

    /// Queues pages to be returned by subsequent heart-rate fetches, in order.
    public func enqueueHeartRatePage(_ page: HeartRateSampleFetchPage) {
        lock.locked { queuedHeartRatePages.append(page) }
    }

    /// The next heart-rate fetch throws this, then behaves normally again.
    public func failNextHeartRateFetch(with error: Error) {
        lock.locked { heartRateErrorForNextFetch = error }
    }

    /// Every route fetch returns this until changed again.
    public func setRoute(_ result: RouteFetchResult) {
        lock.locked { routeResult = result }
    }

    /// Every route fetch throws this.
    public func failRouteFetch(with error: Error) {
        lock.locked { routeError = error }
    }

    /// Every step-count fetch returns this until changed again.
    public func setTotalStepCount(_ count: Double?) {
        lock.locked { stepCount = count }
    }

    /// Every step-count fetch throws this.
    public func failStepCountFetch(with error: Error) {
        lock.locked { stepCountError = error }
    }

    public func fetchHeartRateSamples(_ request: HeartRateSampleFetchRequest) async throws -> HeartRateSampleFetchPage {
        let (error, next) = lock.locked { () -> (Error?, HeartRateSampleFetchPage?) in
            heartRateRequests.append(request)
            let error = heartRateErrorForNextFetch
            heartRateErrorForNextFetch = nil
            let next = queuedHeartRatePages.isEmpty ? nil : queuedHeartRatePages.removeFirst()
            return (error, next)
        }
        if let error { throw error }
        return next ?? HeartRateSampleFetchPage(samples: [])
    }

    public func fetchRoute(_ request: RouteFetchRequest) async throws -> RouteFetchResult {
        let (error, result) = lock.locked { () -> (Error?, RouteFetchResult) in
            routeRequests.append(request)
            return (routeError, routeResult)
        }
        if let error { throw error }
        return result
    }

    public func fetchTotalStepCount(workoutID: UUID, windowStart: Date, windowEnd: Date) async throws -> Double? {
        let (error, count) = lock.locked { () -> (Error?, Double?) in
            stepCountRequests += 1
            return (stepCountError, stepCount)
        }
        if let error { throw error }
        return count
    }
}

/// Collects `SampleExtractionDiagnostic`s reported during an extraction.
public final class SampleExtractionDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SampleExtractionDiagnostic] = []

    public init() {}

    public var reported: [SampleExtractionDiagnostic] {
        lock.locked { events }
    }

    public func handler() -> @Sendable (SampleExtractionDiagnostic) -> Void {
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
