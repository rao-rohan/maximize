import XCTest
import Foundation
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// FR-0.3 (full-fidelity extraction) and FR-0.6 (indoor runs are first-class),
/// exercised without a health store.
///
/// HealthKit cannot run in CI, so what is tested here is exactly what CLAUDE.md says
/// this ticket *can* verify: the mapping and assembly logic — sorting, unit
/// conversion, absent-versus-empty, offset computation from workout start, and the
/// partial-failure decision documented on `WorkoutSampleExtractor`.
final class WorkoutSampleExtractorTests: XCTestCase {
    // MARK: - Happy path

    func testAssemblesHeartRateRouteAndStepCountIntoOneDerivedMetricsInput() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 120),
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(20), beatsPerMinute: 125),
        ]))
        fetcher.setRoute(RouteFetchResult(points: [
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(10), latitudeDegrees: 40, longitudeDegrees: -73),
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(20), latitudeDegrees: 40.001, longitudeDegrees: -73.001),
        ]))
        fetcher.setTotalStepCount(5_400)

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        let series = try XCTUnwrap(input.heartRateSeries)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [10, 20])
        XCTAssertEqual(series.samples.map(\.beatsPerMinute), [120, 125])

        let route = try XCTUnwrap(input.route)
        XCTAssertEqual(route.points.map(\.offsetSeconds), [10, 20])

        XCTAssertEqual(input.totalStepCount, 5_400)
    }

    // MARK: - Ordering (HealthKit's return order is not assumed)

    func testSortsHeartRateSamplesRegardlessOfHealthStoreOrder() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(30), beatsPerMinute: 130),
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 110),
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(20), beatsPerMinute: 120),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        let series = try XCTUnwrap(input.heartRateSeries)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [10, 20, 30])
    }

    func testSortsRoutePointsRegardlessOfHealthStoreOrder() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.setRoute(RouteFetchResult(points: [
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(20), latitudeDegrees: 40, longitudeDegrees: -73),
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(5), latitudeDegrees: 40, longitudeDegrees: -73),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        let route = try XCTUnwrap(input.route)
        XCTAssertEqual(route.points.map(\.offsetSeconds), [5, 20])
    }

    // MARK: - Indoor runs are first-class (FR-0.6)

    func testAnIndoorWorkoutNeverQueriesForARoute() async throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 140),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        XCTAssertNil(input.route)
        XCTAssertTrue(fetcher.receivedRouteRequests.isEmpty)
        // The HR curve is the point for an indoor run — it must still come through.
        XCTAssertNotNil(input.heartRateSeries)
    }

    // MARK: - Treadmill distance samples are the mirror image (MAX-066)

    func testAnIndoorWorkoutFetchesDistanceSamplesButNotARoute() async throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(10), meters: 0),
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(20), meters: 25),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        let series = try XCTUnwrap(input.distanceSamples)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [10, 20])
        XCTAssertEqual(series.samples.map(\.meters), [0, 25])
        XCTAssertNil(input.route)
        XCTAssertTrue(fetcher.receivedRouteRequests.isEmpty)
    }

    /// The exact mirror of `testAnIndoorWorkoutNeverQueriesForARoute`: an outdoor run
    /// already has an authoritative track, so the distance-sample query is never run.
    func testAnOutdoorWorkoutNeverQueriesForDistanceSamples() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.setRoute(RouteFetchResult(points: [
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(10), latitudeDegrees: 40, longitudeDegrees: -73),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        XCTAssertNil(input.distanceSamples)
        XCTAssertTrue(fetcher.receivedDistanceSampleRequests.isEmpty)
        XCTAssertNotNil(input.route)
    }

    func testSortsDistanceSamplesRegardlessOfHealthStoreOrder() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(20), meters: 25),
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(5), meters: 0),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        let series = try XCTUnwrap(input.distanceSamples)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [5, 20])
    }

    func testNoDistanceSamplesAtAllIsAbsentNotEmpty() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        // No pages enqueued: the fake returns an empty page.

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        XCTAssertNil(input.distanceSamples)
    }

    func testADistanceSampleFetchFailureLeavesTheWorkoutUsableWithHeartRateIntact() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 140),
        ]))
        fetcher.failNextDistanceSampleFetch(with: TestFetchError.boom)
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertNotNil(input.heartRateSeries)
        XCTAssertNil(input.distanceSamples)
        XCTAssertEqual(diagnostics.reported, [.distanceSampleFetchFailed])
    }

    func testDistanceSamplePagingResumesAfterTheLastSampleOfThePreviousPage() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let policy = try SampleExtractionPolicy(
            heartRateBatchLimit: 100,
            heartRateMaxPages: 5,
            maxRoutePoints: 100,
            distanceSampleBatchLimit: 2,
            distanceSampleMaxPages: 5
        )
        let firstPageLastDate = Fixture.epoch.addingTimeInterval(20)
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(10), meters: 0),
            RawDistanceSample(date: firstPageLastDate, meters: 25),
        ]))
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(30), meters: 26),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher, policy: policy)

        XCTAssertEqual(fetcher.receivedDistanceSampleRequests.count, 2)
        XCTAssertNil(fetcher.receivedDistanceSampleRequests[0].after)
        let secondRequestAfter = try XCTUnwrap(fetcher.receivedDistanceSampleRequests[1].after)
        XCTAssertGreaterThan(secondRequestAfter, firstPageLastDate)

        let series = try XCTUnwrap(input.distanceSamples)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [10, 20, 30])
    }

    func testDistanceSamplePagingTruncatesAndReportsWhenThePolicyLimitIsReached() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let policy = try SampleExtractionPolicy(
            heartRateBatchLimit: 100,
            heartRateMaxPages: 5,
            maxRoutePoints: 100,
            distanceSampleBatchLimit: 1,
            distanceSampleMaxPages: 2
        )
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(10), meters: 0),
        ]))
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(20), meters: 25),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            policy: policy,
            report: diagnostics.handler()
        )

        XCTAssertEqual(fetcher.receivedDistanceSampleRequests.count, 2)
        XCTAssertEqual(input.distanceSamples?.count, 2)
        XCTAssertEqual(diagnostics.reported, [.distanceSamplePagingTruncated(samplesCollected: 2)])
    }

    func testAnImplausibleDistanceSampleIsDroppedAndReported() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(10), meters: 25),
            // A negative distance is not a real reading — Validate.nonNegative rejects it.
            RawDistanceSample(date: Fixture.epoch.addingTimeInterval(20), meters: -5),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.distanceSamples?.samples.map(\.offsetSeconds), [10])
        XCTAssertEqual(diagnostics.reported, [.distanceSamplesDropped(count: 1)])
    }

    func testADuplicateDistanceSampleTimestampAcrossPagesIsDroppedAndReported() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let duplicateDate = Fixture.epoch.addingTimeInterval(10)
        fetcher.enqueueDistanceSamplePage(DistanceSampleFetchPage(samples: [
            RawDistanceSample(date: duplicateDate, meters: 25),
            RawDistanceSample(date: duplicateDate, meters: 26),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.distanceSamples?.count, 1)
        XCTAssertEqual(diagnostics.reported, [.distanceSamplesDropped(count: 1)])
    }

    func testNoHeartRateAtAllIsAbsentNotEmpty() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        // No pages enqueued: the fake returns an empty page, as a workout the source
        // recorded no heart rate for would.

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        XCTAssertNil(input.heartRateSeries)
    }

    // MARK: - Partial failure does not fail the whole extraction

    func testARouteFetchFailureLeavesTheWorkoutUsableWithHeartRateIntact() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 140),
        ]))
        fetcher.failRouteFetch(with: TestFetchError.boom)
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertNotNil(input.heartRateSeries)
        XCTAssertNil(input.route)
        XCTAssertEqual(diagnostics.reported, [.routeFetchFailed])
    }

    func testAHeartRateFetchFailureLeavesTheWorkoutUsableWithRouteIntact() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.failNextHeartRateFetch(with: TestFetchError.boom)
        fetcher.setRoute(RouteFetchResult(points: [
            RawRoutePoint(date: Fixture.epoch.addingTimeInterval(10), latitudeDegrees: 40, longitudeDegrees: -73),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertNil(input.heartRateSeries)
        XCTAssertNotNil(input.route)
        XCTAssertEqual(diagnostics.reported, [.heartRateFetchFailed])
    }

    func testAStepCountFetchFailureLeavesCadenceAbsentNotZero() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.failStepCountFetch(with: TestFetchError.boom)
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertNil(input.totalStepCount)
        XCTAssertEqual(diagnostics.reported, [.stepCountFetchFailed])
    }

    func testExtractionNeverThrowsForAFailedFetchOfAnyKind() async throws {
        // The whole point of the partial-failure decision: even every fetch failing
        // at once still returns a usable (if minimal) DerivedMetricsInput, because a
        // thrown error here would, once wired behind WorkoutIngestionSink, pin the
        // anchor and wedge every later workout behind this one (tracker R11).
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.failNextHeartRateFetch(with: TestFetchError.boom)
        fetcher.failRouteFetch(with: TestFetchError.boom)
        fetcher.failStepCountFetch(with: TestFetchError.boom)

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher)

        XCTAssertNil(input.heartRateSeries)
        XCTAssertNil(input.route)
        XCTAssertNil(input.totalStepCount)
        XCTAssertEqual(input.workout.id, workout.id)
    }

    // MARK: - Paging

    func testHeartRatePagingResumesAfterTheLastSampleOfThePreviousPage() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let policy = try SampleExtractionPolicy(heartRateBatchLimit: 2, heartRateMaxPages: 5, maxRoutePoints: 100)
        let firstPageLastDate = Fixture.epoch.addingTimeInterval(20)
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 110),
            RawHeartRateSample(date: firstPageLastDate, beatsPerMinute: 120),
        ]))
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(30), beatsPerMinute: 130),
        ]))

        let input = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher, policy: policy)

        XCTAssertEqual(fetcher.receivedHeartRateRequests.count, 2)
        XCTAssertNil(fetcher.receivedHeartRateRequests[0].after)
        let secondRequestAfter = try XCTUnwrap(fetcher.receivedHeartRateRequests[1].after)
        // Strictly after the previous page's last sample, not equal to it — an
        // inclusive re-query at the exact boundary would return it twice.
        XCTAssertGreaterThan(secondRequestAfter, firstPageLastDate)

        let series = try XCTUnwrap(input.heartRateSeries)
        XCTAssertEqual(series.samples.map(\.offsetSeconds), [10, 20, 30])
    }

    func testHeartRatePagingStopsWhenAPageComesBackShortOfTheLimit() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let policy = try SampleExtractionPolicy(heartRateBatchLimit: 10, heartRateMaxPages: 5, maxRoutePoints: 100)
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 110),
        ]))

        _ = try await WorkoutSampleExtractor.extract(for: workout, using: fetcher, policy: policy)

        XCTAssertEqual(fetcher.receivedHeartRateRequests.count, 1)
    }

    func testHeartRatePagingTruncatesAndReportsWhenThePolicyLimitIsReached() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let policy = try SampleExtractionPolicy(heartRateBatchLimit: 1, heartRateMaxPages: 2, maxRoutePoints: 100)
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 110),
        ]))
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(20), beatsPerMinute: 120),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            policy: policy,
            report: diagnostics.handler()
        )

        // Both full pages were requested (hitting maxPages), and nothing beyond them —
        // everything collected so far is kept, not discarded.
        XCTAssertEqual(fetcher.receivedHeartRateRequests.count, 2)
        XCTAssertEqual(input.heartRateSeries?.count, 2)
        XCTAssertEqual(diagnostics.reported, [.heartRatePagingTruncated(samplesCollected: 2)])
    }

    func testRouteTruncationIsReportedButThePartialRouteIsKept() async throws {
        let workout = try Fixture.workout(hasRoute: true)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.setRoute(RouteFetchResult(
            points: [RawRoutePoint(date: Fixture.epoch.addingTimeInterval(10), latitudeDegrees: 40, longitudeDegrees: -73)],
            truncated: true
        ))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.route?.count, 1)
        XCTAssertEqual(diagnostics.reported, [.routeTruncated(pointsCollected: 1)])
    }

    // MARK: - Malformed readings are dropped, not fatal

    func testAnImplausibleHeartRateReadingIsDroppedAndReported() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 120),
            // Outside HeartRateSample.plausibleBPM — a sensor artefact.
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(20), beatsPerMinute: 999),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.heartRateSeries?.samples.map(\.offsetSeconds), [10])
        XCTAssertEqual(diagnostics.reported, [.heartRateSamplesDropped(count: 1)])
    }

    func testADuplicateTimestampAcrossPagesIsDroppedAndReported() async throws {
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        let duplicateDate = Fixture.epoch.addingTimeInterval(10)
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: duplicateDate, beatsPerMinute: 120),
            RawHeartRateSample(date: duplicateDate, beatsPerMinute: 121),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.heartRateSeries?.count, 1)
        XCTAssertEqual(diagnostics.reported, [.heartRateSamplesDropped(count: 1)])
    }

    func testAReadingBeforeWorkoutStartIsDroppedRatherThanThrown() async throws {
        // A negative offset would fail HeartRateSample's validation; the extractor
        // must not let one bad reading fail the entire workout's extraction.
        let workout = try Fixture.workout(hasRoute: false)
        let fetcher = FakeWorkoutSampleFetcher()
        fetcher.enqueueHeartRatePage(HeartRateSampleFetchPage(samples: [
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(-5), beatsPerMinute: 120),
            RawHeartRateSample(date: Fixture.epoch.addingTimeInterval(10), beatsPerMinute: 125),
        ]))
        let diagnostics = SampleExtractionDiagnosticRecorder()

        let input = try await WorkoutSampleExtractor.extract(
            for: workout,
            using: fetcher,
            report: diagnostics.handler()
        )

        XCTAssertEqual(input.heartRateSeries?.samples.map(\.offsetSeconds), [10])
        XCTAssertEqual(diagnostics.reported, [.heartRateSamplesDropped(count: 1)])
    }
}

private enum TestFetchError: Error {
    case boom
}
