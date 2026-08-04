import Foundation
import HealthKit
import MaximizeCore

/// The HealthKit half of FR-0.2: one `HKAnchoredObjectQuery` per request, translated into
/// core vocabulary.
///
/// **Nothing in this file executes in CI**, so it is written to hold as little as
/// possible. It decodes an anchor, runs one query, classifies what comes back, and
/// returns. Every judgement the pipeline makes — whether to fetch, from where, how far
/// back, whether to fetch again, when the anchor may move, what a corrupt anchor means —
/// lives in `AnchoredWorkoutIngester`, where CI checks it on every commit.
///
/// Two constraints on this file are load-bearing rather than stylistic:
///
/// - **No `updateHandler` is set.** Setting one turns an anchored query into a
///   long-running one whose handler fires repeatedly, which would resume a checked
///   continuation more than once — a crash — and would also duplicate the observer query
///   MAX-030 already runs. The core drives repetition; this runs exactly one query.
/// - **A workout that cannot be represented is counted, not thrown.** Throwing would pin
///   the anchor on a record that can never be accepted and block every workout behind it
///   forever. The count travels back so the core can decide, and it does.
final class HealthKitWorkoutFetcher: WorkoutFetching, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let now: @Sendable () -> Date

    init(healthStore: HKHealthStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.healthStore = healthStore
        self.now = now
    }

    func fetchWorkouts(_ request: WorkoutFetchRequest) async throws -> WorkoutFetchBatch {
        let raw = try await runAnchoredQuery(
            anchor: try Self.decodeAnchor(request.anchor),
            predicate: Self.predicate(earliestWorkoutStart: request.earliestWorkoutStart),
            limit: request.batchLimit
        )

        guard let newAnchor = raw.anchor else {
            // An anchored query that returns no anchor leaves nowhere to resume from.
            // Failing the fetch leaves the stored anchor untouched, so the next wake
            // retries the same ground rather than skipping it.
            throw HealthKitFetchError.missingAnchor
        }

        let ingestedAt = now()
        var workouts: [Workout] = []
        var unrepresentable = 0
        for sample in raw.samples {
            if let workout = await workout(from: sample, ingestedAt: ingestedAt) {
                workouts.append(workout)
            } else {
                unrepresentable += 1
            }
        }

        return try WorkoutFetchBatch(
            workouts: workouts,
            deletedWorkoutIDs: raw.deletedUUIDs,
            unrepresentableWorkoutCount: unrepresentable,
            anchor: WorkoutQueryAnchor(
                opaqueData: try NSKeyedArchiver.archivedData(
                    withRootObject: newAnchor,
                    requiringSecureCoding: true
                )
            )
        )
    }

    // MARK: - The query

    /// Immutable HealthKit results on their way out of a callback.
    ///
    /// `@unchecked Sendable` because the samples are read-only value carriers that nothing
    /// here mutates, and the alternative — converting inside the callback — is impossible
    /// while the route check is asynchronous.
    private struct RawBatch: @unchecked Sendable {
        let samples: [HKSample]
        let deletedUUIDs: [UUID]
        let anchor: HKQueryAnchor?
    }

    private func runAnchoredQuery(
        anchor: HKQueryAnchor?,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> RawBatch {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    returning: RawBatch(
                        samples: samples ?? [],
                        deletedUUIDs: (deletedObjects ?? []).map(\.uuid),
                        anchor: newAnchor
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private static func decodeAnchor(_ stored: WorkoutQueryAnchor?) throws -> HKQueryAnchor? {
        guard let stored else { return nil }

        let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: stored.opaqueData
        )
        guard let decoded else {
            // Reported, never substituted with `nil` here. "Refetch from scratch" is a
            // data decision and the core owns it.
            throw WorkoutFetchError.unusableAnchor
        }
        return decoded
    }

    private static func predicate(earliestWorkoutStart: Date?) -> NSPredicate? {
        guard let earliestWorkoutStart else { return nil }
        return HKQuery.predicateForSamples(
            withStart: earliestWorkoutStart,
            end: nil,
            options: .strictStartDate
        )
    }

    // MARK: - HealthKit → core

    private func workout(from sample: HKSample, ingestedAt: Date) async -> Workout? {
        guard let captured = sample as? HKWorkout else { return nil }

        let isIndoor = (captured.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false
        let activityType = ActivityType.captured(
            activityName: captured.workoutActivityType.coreActivityName,
            isIndoor: isIndoor
        )

        return try? Workout(
            id: captured.uuid,
            activityType: activityType,
            start: captured.startDate,
            end: captured.endDate,
            durationSeconds: captured.duration,
            distanceMeters: captured.sum(of: HKQuantityType(.distanceWalkingRunning), in: .meter()),
            activeEnergyKilocalories: captured.sum(of: HKQuantityType(.activeEnergyBurned), in: .kilocalorie()),
            hasRoute: await hasStoredRoute(for: captured, activityType: activityType, isIndoor: isIndoor),
            source: WorkoutSource.captured(productType: captured.sourceRevision.productType),
            ingestedAt: ingestedAt
        )
    }

    /// Whether the source actually stored a GPS route for this workout.
    ///
    /// Asked rather than inferred, because `Workout.hasRoute` describes what was recorded
    /// and an outdoor run with location services denied has none. The probe is skipped
    /// entirely for activities that cannot have a route, so a treadmill run costs nothing
    /// (FR-0.6) — and it is a one-sample existence check, not a fetch. MAX-032 fetches the
    /// route itself and subsumes this.
    private func hasStoredRoute(
        for workout: HKWorkout,
        activityType: ActivityType,
        isIndoor: Bool
    ) async -> Bool {
        guard activityType.isOutdoorByNature, !isIndoor else { return false }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                // An error and an empty result are the same answer here: nothing to draw.
                continuation.resume(returning: samples?.isEmpty == false)
            }

            healthStore.execute(query)
        }
    }
}

enum HealthKitFetchError: Error {
    /// The anchored query completed without returning a new anchor.
    case missingAnchor
}

// MARK: - Lookup tables

private extension HKWorkout {
    /// Summed quantity for a type recorded during this workout, or nil if none was.
    func sum(of quantityType: HKQuantityType, in unit: HKUnit) -> Double? {
        statistics(for: quantityType)?.sumQuantity()?.doubleValue(for: unit)
    }
}

private extension HKWorkoutActivityType {
    /// The `ActivityType` raw value naming this HealthKit activity.
    ///
    /// A lookup, deliberately: `ActivityType` is an open string wrapper precisely so that
    /// the dozens of HealthKit activities this app does not reason about can arrive as
    /// "some other activity" rather than fail to record a workout the user did. The named
    /// cases are the ones the plan and the scorer distinguish.
    ///
    /// Note the absence of a treadmill case. HealthKit has no separate treadmill activity;
    /// indoor running is `.running` plus `HKMetadataKeyIndoorWorkout`, and combining the
    /// two is `ActivityType.captured(activityName:isIndoor:)`'s job, in the core, under test.
    var coreActivityName: String {
        switch self {
        case .running: return ActivityType.running.rawValue
        case .walking: return ActivityType.walking.rawValue
        case .hiking: return ActivityType.hiking.rawValue
        case .cycling: return ActivityType.cycling.rawValue
        case .traditionalStrengthTraining: return ActivityType.traditionalStrengthTraining.rawValue
        default: return ActivityType.other.rawValue
        }
    }
}
