import CoreLocation
import Foundation
import HealthKit
import MaximizeCore

/// The HealthKit half of FR-0.3: full-fidelity per-workout sample extraction.
///
/// **Nothing in this file executes in CI**, so — as with `HealthKitWorkoutFetcher` — it
/// is written to hold as little judgement as possible. Each method runs one query (or,
/// for the route, drains one query's callbacks up to a safety cap) and returns what it
/// found. `WorkoutSampleExtractor` decides how many heart-rate pages to request, what a
/// fetch failure means, and how raw readings become domain values.
///
/// ## Heart rate and step count are date-range queries; the route is not
///
/// FR-0.3 specifies heart rate as a "time-range predicate" fetch, and that is exactly
/// what `fetchHeartRateSamples` and `fetchTotalStepCount` run — no workout lookup
/// needed, just the window `WorkoutSampleExtractor` already knows. A route is
/// different: HealthKit associates a route with a workout by *object*, not by a
/// date-range predicate (`HKQuery.predicateForObjects(from: HKWorkout)`), so
/// `fetchRoute` first re-resolves the `HKWorkout` from the UUID `WorkoutSampleFetching`
/// carries, then hands it to `HealthKitRouteLookup`. This is the one extra query this
/// file could not avoid: `WorkoutSampleFetching`'s methods intentionally know nothing
/// beyond a workout's identifier and window (per `WorkoutFetching`'s own model), so
/// only the adapter, which does have the HealthKit vocabulary, can bridge back.
final class HealthKitWorkoutSampleFetcher: WorkoutSampleFetching, @unchecked Sendable {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    // MARK: - Heart rate

    func fetchHeartRateSamples(_ request: HeartRateSampleFetchRequest) async throws -> HeartRateSampleFetchPage {
        let predicate = HKQuery.predicateForSamples(
            withStart: request.after ?? request.windowStart,
            end: request.windowEnd,
            options: .strictStartDate
        )

        let raw: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: predicate,
                limit: request.limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        return HeartRateSampleFetchPage(
            samples: raw.map { sample in
                RawHeartRateSample(date: sample.startDate, beatsPerMinute: sample.quantity.doubleValue(for: beatsPerMinute))
            }
        )
    }

    // MARK: - Route

    func fetchRoute(_ request: RouteFetchRequest) async throws -> RouteFetchResult {
        guard let workout = try await lookupWorkout(uuid: request.workoutID) else {
            return RouteFetchResult(points: nil)
        }
        guard let route = await HealthKitRouteLookup.route(for: workout, in: healthStore) else {
            return RouteFetchResult(points: nil)
        }
        return try await drainLocations(from: route, maxPoints: request.maxPoints)
    }

    private func lookupWorkout(uuid: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    /// Drains an `HKWorkoutRoute`'s locations.
    ///
    /// `HKWorkoutRouteQuery` streams a route's locations through repeated callbacks
    /// with no query-level limit, so this — not the core — is where `maxPoints` is
    /// enforced: once reached, the query is stopped and what has been collected so far
    /// is returned as a truncated result.
    private func drainLocations(from route: HKWorkoutRoute, maxPoints: Int) async throws -> RouteFetchResult {
        let accumulator = RouteLocationAccumulator(maxPoints: maxPoints)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { query, locations, done, error in
                if let error {
                    if accumulator.claimFailure() {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let outcome = accumulator.record(locations ?? [], sourceDone: done) else {
                    // Either a genuine mid-stream batch (not yet done, cap not yet
                    // reached), or a callback that arrived after this query already
                    // resumed its continuation once — `stop()` does not guarantee no
                    // further delivery, so this must be a safe no-op either way.
                    return
                }

                if outcome.truncated {
                    self.healthStore.stop(query)
                }

                continuation.resume(returning: RouteFetchResult(
                    points: outcome.points.isEmpty ? nil : outcome.points,
                    truncated: outcome.truncated
                ))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Step count

    func fetchTotalStepCount(workoutID: UUID, windowStart: Date, windowEnd: Date) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }
    }
}

/// Accumulates `HKWorkoutRouteQuery` callback batches into `RawRoutePoint`s, and
/// decides — exactly once — when the caller should resume its continuation.
///
/// Two things make this its own type rather than inline closure state: the callback
/// can fire multiple times before the route finishes, and after `stop()` is called it
/// may still fire once more (Apple does not guarantee delivery halts the instant
/// `stop()` returns). A `CheckedContinuation` resumed twice is a crash, so "have we
/// already decided" has to be a single, locked answer shared by every callback.
private final class RouteLocationAccumulator: @unchecked Sendable {
    struct Outcome {
        let points: [RawRoutePoint]
        let truncated: Bool
    }

    private let lock = NSLock()
    private let maxPoints: Int
    private var points: [RawRoutePoint] = []
    private var claimed = false

    init(maxPoints: Int) {
        self.maxPoints = maxPoints
    }

    /// Appends `locations`, and returns the outcome exactly once — on the call where
    /// the route finishes streaming or `maxPoints` is first reached. Every call after
    /// that returns `nil`.
    func record(_ locations: [CLLocation], sourceDone: Bool) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return nil }

        var reachedCap = false
        for location in locations {
            guard points.count < maxPoints else {
                reachedCap = true
                break
            }
            points.append(
                RawRoutePoint(
                    date: location.timestamp,
                    latitudeDegrees: location.coordinate.latitude,
                    longitudeDegrees: location.coordinate.longitude,
                    // A negative accuracy is Core Location's own signal that the
                    // corresponding value is not meaningful (RoutePoint.swift already
                    // documents why this stays absent rather than a fabricated number).
                    altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                    speedMetersPerSecond: location.speed >= 0 ? location.speed : nil
                )
            )
        }

        guard sourceDone || reachedCap else { return nil }
        claimed = true
        return Outcome(points: points, truncated: reachedCap)
    }

    /// Claims the failure outcome, or returns `false` if a success already claimed it
    /// first — the mirror image of `record`'s guarantee, for the error path.
    func claimFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
