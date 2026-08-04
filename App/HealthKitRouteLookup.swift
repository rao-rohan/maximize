import HealthKit

/// The single implementation of "does this workout have a route object, and if so
/// which one" — shared by `HealthKitWorkoutFetcher` (which only needs the yes/no for
/// `Workout.hasRoute`) and `HealthKitWorkoutSampleFetcher` (which needs the object
/// itself, to then read its locations).
///
/// MAX-031 left a note that MAX-032 should "subsume" the route-existence probe rather
/// than leave two independent implementations of the same query. This is that: one
/// query shape, defined once. The two call sites still run at different points in the
/// pipeline — `hasRoute` is learned when a `Workout` is constructed, full extraction
/// happens afterwards against the workout's window — so this does not collapse them
/// into a single *runtime* query; it collapses them into a single *implementation* of
/// it, which is what "leaving two queries where one will do" was actually about: two
/// copies of this lookup drifting apart over time.
enum HealthKitRouteLookup {
    /// The workout's route object, if the health store has one. `nil` for a workout
    /// that never had GPS enabled, and for every indoor run by construction (FR-0.6) —
    /// callers are expected not to ask for those in the first place.
    static func route(for workout: HKWorkout, in healthStore: HKHealthStore) async -> HKWorkoutRoute? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                // An error and "no route" are the same answer here: nothing to draw.
                continuation.resume(returning: samples?.first as? HKWorkoutRoute)
            }
            healthStore.execute(query)
        }
    }
}
