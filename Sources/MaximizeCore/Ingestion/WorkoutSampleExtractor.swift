import Foundation

/// The tunable parts of one workout's sample extraction.
///
/// Values, not constants in the algorithm, so a test can drive a many-page heart-rate
/// fetch or a truncated route through the same path a dense real workout takes.
public struct SampleExtractionPolicy: Hashable, Sendable {
    /// Maximum heart-rate samples one page may contain.
    public let heartRateBatchLimit: Int

    /// Maximum pages one heart-rate fetch may request before giving up on the rest.
    ///
    /// The product of the two heart-rate figures bounds one extraction the same way
    /// `AnchoredIngestionPolicy.batchLimit * maxBatchesPerPass` bounds one ingestion
    /// pass: a stop for pathological cases, not something a normal run's HR curve
    /// (thousands of samples at most) ever meets.
    public let heartRateMaxPages: Int

    /// Safety cap on GPS points collected from one route.
    ///
    /// Unlike heart rate, this is not "batch size times page count" — see
    /// `RouteFetchRequest` for why a route fetch is not paged from the core's side.
    /// It is simply the most points one extraction will accept before treating the
    /// rest as a truncation rather than reading indefinitely during a short background
    /// wake.
    public let maxRoutePoints: Int

    private init(uncheckedHeartRateBatchLimit: Int, heartRateMaxPages: Int, maxRoutePoints: Int) {
        self.heartRateBatchLimit = uncheckedHeartRateBatchLimit
        self.heartRateMaxPages = heartRateMaxPages
        self.maxRoutePoints = maxRoutePoints
    }

    public init(heartRateBatchLimit: Int, heartRateMaxPages: Int, maxRoutePoints: Int) throws {
        guard heartRateBatchLimit >= 1 else {
            throw DomainError.outOfRange(
                field: "SampleExtractionPolicy.heartRateBatchLimit",
                value: Double(heartRateBatchLimit),
                lowerBound: 1,
                upperBound: nil
            )
        }
        guard heartRateMaxPages >= 1 else {
            throw DomainError.outOfRange(
                field: "SampleExtractionPolicy.heartRateMaxPages",
                value: Double(heartRateMaxPages),
                lowerBound: 1,
                upperBound: nil
            )
        }
        guard maxRoutePoints >= 1 else {
            throw DomainError.outOfRange(
                field: "SampleExtractionPolicy.maxRoutePoints",
                value: Double(maxRoutePoints),
                lowerBound: 1,
                upperBound: nil
            )
        }
        self.init(
            uncheckedHeartRateBatchLimit: heartRateBatchLimit,
            heartRateMaxPages: heartRateMaxPages,
            maxRoutePoints: maxRoutePoints
        )
    }

    /// 1,000 samples per page, at most 20 pages (20,000 samples), 20,000 route points.
    ///
    /// A watch sensor recording roughly once per second puts even a 90-minute run
    /// (tracker's own example) at ~5,400 samples and ~5,400 GPS fixes — comfortably
    /// under both caps, which exist for the pathological case, not normal operation.
    public static let standard = SampleExtractionPolicy(
        uncheckedHeartRateBatchLimit: 1_000,
        heartRateMaxPages: 20,
        maxRoutePoints: 20_000
    )
}

/// Something that happened during one workout's extraction and would otherwise be
/// invisible — a gap the pipeline decided to tolerate rather than fail on.
///
/// Carries counts and reasons only, never a workout identifier, a coordinate, or a
/// timestamp (CLAUDE.md: health data is PII).
public enum SampleExtractionDiagnostic: Hashable, Sendable {
    /// The heart-rate fetch failed partway (or entirely). Whatever was collected
    /// before the failure is kept; nothing collected means the workout's heart-rate
    /// series comes back absent, same as a source that genuinely recorded none.
    case heartRateFetchFailed

    /// Raw heart-rate readings that could not become a valid `HeartRateSample` —
    /// out-of-plausible-range values, or an exact-timestamp duplicate across pages.
    case heartRateSamplesDropped(count: Int)

    /// `SampleExtractionPolicy.heartRateMaxPages` was reached while the health store
    /// still had more to give. The series returned is real but partial.
    case heartRatePagingTruncated(samplesCollected: Int)

    /// The route fetch failed. The workout is still usable; FR-1.4 already expects a
    /// route to be omitted cleanly, and this is indistinguishable from that case once
    /// it reaches the dashboard.
    case routeFetchFailed

    /// Raw GPS fixes that could not become a valid `RoutePoint`.
    case routePointsDropped(count: Int)

    /// `SampleExtractionPolicy.maxRoutePoints` was reached before the route finished
    /// streaming.
    case routeTruncated(pointsCollected: Int)

    /// The step-count fetch failed. Average cadence comes back absent, not zero.
    case stepCountFetchFailed
}

/// Assembles one workout's full-fidelity `DerivedMetricsInput` (FR-0.3) from a health
/// store, behind `WorkoutSampleFetching`.
///
/// ## Partial failure is not extraction failure
///
/// Each of the three fetches — heart rate, route, step count — degrades independently
/// to absence on failure rather than aborting the whole extraction. This function does
/// not throw for a missing or partial piece; it only throws if `DerivedMetricsInput`'s
/// own invariants would be violated, which cannot happen from data this type
/// constructs itself, or if a caller hands it a workout so malformed the requests
/// cannot even be built.
///
/// This is a deliberate reading of MAX-031's contract on `WorkoutIngestionSink`:
/// throwing there leaves the anchor in place, so the workout is refetched and rethrown
/// on every later pass, and everything recorded after it queues behind it forever
/// (tracker R11). A route that fails to fetch is exactly the kind of *recoverable* gap
/// that contract warns against wedging the pipeline over — the workout is still
/// scoreable (§9's cap-based metrics need heart rate, not GPS), and FR-1.4 already
/// renders "no route" cleanly for indoor runs, so a fetch-time absence and a
/// genuine-absence render identically. The same reasoning applies symmetrically to a
/// heart-rate or step-count fetch that fails: a `Workout` MAX-031 has already
/// validated is *always* a usable record on its own, and this function's job is to
/// enrich it as far as the health store cooperates, not to gate on full cooperation.
///
/// Every degradation is still reported through `report`, so "the pipeline tolerated a
/// gap" stays visible (mirrors `AnchoredWorkoutIngester`'s `IngestionDiagnostic`) even
/// though it is never fatal.
///
/// ## Indoor runs
///
/// The route fetch is skipped entirely when `workout.hasRoute` is `false` — not
/// attempted and found empty, simply never asked. FR-0.6 makes that the normal case
/// for a treadmill run, and skipping the query costs it nothing (mirrors
/// `HealthKitWorkoutFetcher.hasStoredRoute`, which already skips its own probe for
/// activities that cannot have a route).
public enum WorkoutSampleExtractor {
    /// A resumed heart-rate page is requested fractionally after the previous page's
    /// last sample, not at the same instant. An inclusive re-query exactly at the
    /// boundary would return that sample again; readings this close together are not
    /// physiologically meaningful to lose.
    private static let pagingEpsilonSeconds: TimeInterval = 0.0001

    /// - Parameters:
    ///   - workout: the record MAX-031 already validated. Its `start`/`end` is the
    ///     window every fetch below uses as its predicate.
    ///   - fetcher: the HealthKit adapter, or a fake in tests.
    ///   - report: called for every tolerated gap. Defaults to discarding. Must not
    ///     write health data anywhere durable — `SampleExtractionDiagnostic` carries
    ///     none, and that is only worth having if the sink for it respects it.
    public static func extract(
        for workout: Workout,
        using fetcher: WorkoutSampleFetching,
        policy: SampleExtractionPolicy = .standard,
        report: @escaping @Sendable (SampleExtractionDiagnostic) -> Void = { _ in }
    ) async throws -> DerivedMetricsInput {
        let heartRateSeries = try await extractHeartRateSeries(
            workout: workout,
            fetcher: fetcher,
            policy: policy,
            report: report
        )

        // Skipped, not attempted-and-empty: an indoor run costs this function nothing
        // extra, same as the existence probe it already costs nothing (FR-0.6).
        let route = workout.hasRoute
            ? try await extractRoute(workout: workout, fetcher: fetcher, policy: policy, report: report)
            : nil

        let totalStepCount = await extractTotalStepCount(workout: workout, fetcher: fetcher, report: report)

        return try DerivedMetricsInput(
            workout: workout,
            heartRateSeries: heartRateSeries,
            route: route,
            totalStepCount: totalStepCount
        )
    }

    // MARK: - Heart rate

    private static func extractHeartRateSeries(
        workout: Workout,
        fetcher: WorkoutSampleFetching,
        policy: SampleExtractionPolicy,
        report: @Sendable (SampleExtractionDiagnostic) -> Void
    ) async throws -> HeartRateSeries? {
        var raw: [RawHeartRateSample] = []
        var after: Date?
        var pages = 0

        while pages < policy.heartRateMaxPages {
            let request = try HeartRateSampleFetchRequest(
                workoutID: workout.id,
                windowStart: workout.start,
                windowEnd: workout.end,
                after: after,
                limit: policy.heartRateBatchLimit
            )

            let page: HeartRateSampleFetchPage
            do {
                page = try await fetcher.fetchHeartRateSamples(request)
            } catch {
                // Whatever earlier pages already collected is kept — a failure midway
                // through a long fetch degrades to "partial series", not "no series".
                report(.heartRateFetchFailed)
                return try buildHeartRateSeries(workoutID: workout.id, workoutStart: workout.start, raw: raw, report: report)
            }

            raw.append(contentsOf: page.samples)
            pages += 1

            // A page shorter than the limit means the store had nothing more to give.
            guard page.samples.count >= policy.heartRateBatchLimit else {
                return try buildHeartRateSeries(workoutID: workout.id, workoutStart: workout.start, raw: raw, report: report)
            }

            guard let latest = page.samples.map(\.date).max() else {
                return try buildHeartRateSeries(workoutID: workout.id, workoutStart: workout.start, raw: raw, report: report)
            }
            after = latest.addingTimeInterval(Self.pagingEpsilonSeconds)
        }

        // Exited because the page count ran out while the last page was still full —
        // there is real reason to believe more remained.
        report(.heartRatePagingTruncated(samplesCollected: raw.count))
        return try buildHeartRateSeries(workoutID: workout.id, workoutStart: workout.start, raw: raw, report: report)
    }

    /// Converts, sorts, and validates raw readings into a `HeartRateSeries`.
    ///
    /// Sorting is not optional here (per this ticket: "HealthKit's return order is not
    /// something to assume"), and neither pages nor the health store's own ordering
    /// within a page are trusted. A reading that cannot become a valid
    /// `HeartRateSample` — implausible BPM, or a timestamp that collides with one
    /// already kept — is dropped and counted rather than allowed to fail the whole
    /// extraction, mirroring `WorkoutFetchBatch.unrepresentableWorkoutCount`.
    private static func buildHeartRateSeries(
        workoutID: UUID,
        workoutStart: Date,
        raw: [RawHeartRateSample],
        report: (SampleExtractionDiagnostic) -> Void
    ) throws -> HeartRateSeries? {
        let sorted = raw.sorted { $0.date < $1.date }

        var samples: [HeartRateSample] = []
        samples.reserveCapacity(sorted.count)
        var lastOffset: Double?
        var dropped = 0

        for reading in sorted {
            let offset = reading.date.timeIntervalSince(workoutStart)
            if let lastOffset, offset <= lastOffset {
                dropped += 1
                continue
            }
            guard let sample = try? HeartRateSample(offsetSeconds: offset, beatsPerMinute: reading.beatsPerMinute) else {
                dropped += 1
                continue
            }
            samples.append(sample)
            lastOffset = offset
        }

        if dropped > 0 {
            report(.heartRateSamplesDropped(count: dropped))
        }

        // Absent, not empty: a workout the source recorded no heart rate for, and a
        // workout every reading of which was unusable, look the same to every metric
        // downstream (MAX-012).
        guard !samples.isEmpty else { return nil }

        // Strictly increasing by construction above, so the validating initializer
        // cannot reject this — no silent `try?` standing in for an invariant this
        // function has already enforced.
        return try HeartRateSeries(workoutID: workoutID, samples: samples)
    }

    // MARK: - Route

    private static func extractRoute(
        workout: Workout,
        fetcher: WorkoutSampleFetching,
        policy: SampleExtractionPolicy,
        report: (SampleExtractionDiagnostic) -> Void
    ) async throws -> Route? {
        let request = try RouteFetchRequest(
            workoutID: workout.id,
            windowStart: workout.start,
            windowEnd: workout.end,
            maxPoints: policy.maxRoutePoints
        )

        let result: RouteFetchResult
        do {
            result = try await fetcher.fetchRoute(request)
        } catch {
            report(.routeFetchFailed)
            return nil
        }

        guard let raw = result.points, !raw.isEmpty else { return nil }

        if result.truncated {
            report(.routeTruncated(pointsCollected: raw.count))
        }

        let sorted = raw.sorted { $0.date < $1.date }
        var points: [RoutePoint] = []
        points.reserveCapacity(sorted.count)
        var lastOffset: Double?
        var dropped = 0

        for fix in sorted {
            let offset = fix.date.timeIntervalSince(workout.start)
            if let lastOffset, offset <= lastOffset {
                dropped += 1
                continue
            }
            guard let point = try? RoutePoint(
                offsetSeconds: offset,
                latitudeDegrees: fix.latitudeDegrees,
                longitudeDegrees: fix.longitudeDegrees,
                altitudeMeters: fix.altitudeMeters,
                speedMetersPerSecond: fix.speedMetersPerSecond
            ) else {
                dropped += 1
                continue
            }
            points.append(point)
            lastOffset = offset
        }

        if dropped > 0 {
            report(.routePointsDropped(count: dropped))
        }

        guard !points.isEmpty else { return nil }
        return try Route(workoutID: workout.id, points: points)
    }

    // MARK: - Step count

    private static func extractTotalStepCount(
        workout: Workout,
        fetcher: WorkoutSampleFetching,
        report: (SampleExtractionDiagnostic) -> Void
    ) async -> Double? {
        do {
            return try await fetcher.fetchTotalStepCount(
                workoutID: workout.id,
                windowStart: workout.start,
                windowEnd: workout.end
            )
        } catch {
            report(.stepCountFetchFailed)
            return nil
        }
    }
}
