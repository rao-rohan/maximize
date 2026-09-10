import Foundation
import HealthKit
import CoreLocation

/// Seeds sample workouts for the simulator tour.
///
/// The UI test runner cannot hold the HealthKit entitlement (Xcode's test runner
/// app does not inherit the `.xctest` bundle's entitlements under ad-hoc signing),
/// so the tour seeds from the app process instead, which does hold it. This only
/// runs when the `-seedTourWorkouts` launch argument is present — never in
/// production, never on a real device, never without the tour explicitly asking.
///
/// The app is otherwise read-only for HealthKit; this is the single write path,
/// and it is gated by the launch argument.
enum TourWorkoutSeeder {
    /// The launch argument the tour passes to trigger seeding.
    static let launchArgument = "-seedTourWorkouts"

    static func seedIfRequested() async {
        guard CommandLine.arguments.contains(launchArgument) else { return }
        do {
            try await seed()
            print("TOUR: seeded sample workouts from app process")
        } catch {
            // The tour continues and documents the empty state; the failure is
            // in the log, not a crash.
            print("TOUR: seeding sample workouts failed: \(error)")
        }
    }

    private static func seed() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let routeType = HKSeriesType.workoutRoute()
        try await store.requestAuthorization(
            toShare: [workoutType, heartRateType, routeType],
            read: [workoutType, heartRateType, routeType]
        )

        let now = Date()
        // A loop in Central Park for the route, timestamps matching the run.
        let routeStart = now.addingTimeInterval(-86400 - 1800)
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: routeStart,
            duration: 1800,
            distanceMeters: 5000,
            baseBPM: 142,
            withRoute: true
        )
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: now.addingTimeInterval(-3 * 86400 - 1500),
            duration: 1500,
            distanceMeters: 5200,
            baseBPM: 158,
            withRoute: false
        )
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: now.addingTimeInterval(-6 * 86400 - 4500),
            duration: 4500,
            distanceMeters: 12000,
            baseBPM: 138,
            withRoute: false
        )
    }

    private static func seedRun(
        store: HKHealthStore,
        heartRateType: HKQuantityType,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        baseBPM: Double,
        withRoute: Bool
    ) async throws {
        let end = start.addingTimeInterval(duration)

        // HKWorkoutBuilder, not the deprecated HKWorkout(activityType:start:end:)
        // initializer — the builder is the only supported way to create a workout
        // with associated samples since iOS 17.
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        let builder = try await HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: start)

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sampleCount = Int(duration / 10)
        let samples = (0..<sampleCount).map { index -> HKQuantitySample in
            let timestamp = start.addingTimeInterval(Double(index) * 10)
            let bpm = baseBPM + 12 * sin(Double(index) / 9) + Double(index % 5)
            return HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: bpmUnit, doubleValue: bpm),
                start: timestamp,
                end: timestamp
            )
        }
        // Samples go through the builder, not a separate save + add: the builder
        // owns the in-progress workout. `add(_:completion:)` has no async
        // variant, so it is bridged with a continuation.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SeederError.samplesNotAdded)
                }
            }
        }

        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else {
            throw SeederError.workoutNotFinished
        }

        if withRoute {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            let center = CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665)
            let locations = (0..<120).map { index -> CLLocation in
                let angle = Double(index) / 120 * 2 * .pi
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: center.latitude + 0.004 * cos(angle),
                        longitude: center.longitude + 0.004 * sin(angle)
                    ),
                    altitude: 10,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    timestamp: start.addingTimeInterval(Double(index) * duration / 120)
                )
            }
            try await routeBuilder.insertRouteData(locations)
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
    }

    /// The seeder's own failures, distinct from HealthKit's — so a tour failure says
    /// which half broke.
    private enum SeederError: Error {
        case samplesNotAdded
        case workoutNotFinished
    }
}
