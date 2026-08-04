import Foundation
import HealthKit
import OSLog
import MaximizeCore

/// The HealthKit half of FR-0.1: read-only authorization, one workout observer query,
/// and background delivery.
///
/// **Nothing in this file executes in CI.** There is no simulator run, and Apple is
/// explicit that background delivery does not work on the Simulator anyway ("Background
/// server queries aren't supported on the Simulator. Be sure to test your background
/// queries on a device."). So the file is written to hold as little as possible: it
/// maps a core vocabulary onto HealthKit types, starts a query, and forwards the wake
/// to `WorkoutChangeResponding`. Every judgement — whether to fetch, when to
/// acknowledge, what a failure means — lives in `MaximizeCore`, where CI checks it.
///
/// The one thing this file *must* get right on its own is the shape of the
/// observer-query callback, and the comments below say why each line is where it is.
///
/// `@MainActor` because `observerQuery` is mutable state reached from both the launch
/// path and the Settings affordance; isolating it makes "only one observer query ever
/// runs" a property of the type rather than a convention. The observer's own callback
/// deliberately touches none of that state — it captures the responder and nothing
/// else, so it is free to run on HealthKit's background queue.
@MainActor
final class HealthKitWorkoutObserver {
    private let healthStore: HKHealthStore
    private let responder: WorkoutChangeResponding

    /// Retained so the long-running query can be stopped, and so a second `start()`
    /// cannot leave two observers running against the same type.
    private var observerQuery: HKObserverQuery?

    init(healthStore: HKHealthStore, responder: WorkoutChangeResponding) {
        self.healthStore = healthStore
        self.responder = responder
    }

    // MARK: - Authorization

    /// Requests **read-only** access to the types in `WorkoutIngestionAuthorization`.
    ///
    /// The share set is derived from the core's `writeTypes` rather than written as a
    /// literal `[]`, so the unit test asserting that set is empty is the thing actually
    /// preventing a write scope from reaching the permission sheet. PRD §3 lists
    /// writing to HealthKit as an explicit non-goal.
    ///
    /// Must be called with the app in the foreground: the system presents a sheet.
    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitObserverError.healthDataUnavailable
        }

        let typesToRead = Set(WorkoutIngestionAuthorization.readTypes.map(\.healthKitObjectType))
        let typesToShare = Set(
            WorkoutIngestionAuthorization.writeTypes.compactMap { $0.healthKitObjectType as? HKSampleType }
        )

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)

        // Deliberately no success/denial check here. `authorizationStatus(for:)`
        // reports *share* status only — Apple does not expose whether read access was
        // granted, by design, so that an app cannot infer the absence of data from the
        // absence of permission. "The user answered the sheet" is the strongest fact
        // available, and the pipeline finds out the rest by getting zero workouts.
        ingestionLog.info("HealthKit read authorization request completed.")
    }

    // MARK: - Observation

    /// Registers the workout observer query and turns on background delivery.
    ///
    /// FR-0.1 says "once at launch", and Apple is specific about where: "If you plan on
    /// supporting background delivery, set up all your observer queries in your app
    /// delegate's `application(_:didFinishLaunchingWithOptions:)` method. By setting up
    /// the queries in `application(_:didFinishLaunchingWithOptions:)`, you ensure that
    /// you've instantiated your queries, and they're ready to use before HealthKit
    /// delivers the updates."
    ///
    /// That is not a style preference. When iOS wakes a suspended app for a HealthKit
    /// delivery there may be no window, no scene, and no view; a query registered from
    /// a SwiftUI `.task` or `.onAppear` would not exist yet at the moment the delivery
    /// arrives. See `MaximizeAppDelegate` for the call site.
    ///
    /// Safe to call more than once — a repeat is ignored rather than starting a second
    /// query against the same type.
    func startObservingWorkouts() {
        guard HKHealthStore.isHealthDataAvailable() else {
            ingestionLog.notice("HealthKit unavailable on this device; workout observation not started.")
            return
        }
        guard observerQuery == nil else { return }

        let workoutType = HKObjectType.workoutType()

        let query = HKObserverQuery(
            sampleType: workoutType,
            predicate: nil
        ) { [responder] _, completionHandler, error in
            // Handed straight across the boundary. Note what is *not* here: no check
            // on `error` deciding whether to proceed, no early `completionHandler()`,
            // no bookkeeping. Those are decisions and they live in
            // WorkoutObservationCoordinator.
            //
            // The completion handler travels *into* the core rather than being called
            // when this closure returns. It has to: this closure returns the instant
            // the Task is created, long before ingestion has finished, and Apple
            // requires the acknowledgement to follow the work, not the callback. The
            // core is what guarantees it is then called exactly once, on every path —
            // three unacknowledged wakes and HealthKit stops delivering to this app.
            Task {
                await responder.workoutsMayHaveChanged(
                    observationError: error,
                    acknowledge: { completionHandler() }
                )
            }
        }

        healthStore.execute(query)
        observerQuery = query

        // Paired with the observer query, on the same type, as Apple's "Configuring
        // HealthKit access" requires: "You pair each executed observer query with a
        // call to enableBackgroundDelivery(for:frequency:withCompletion:) and specify
        // the same sample type."
        //
        // `.immediate` is a request, not a promise — the system enforces a per-type
        // maximum frequency transparently, and PRD §2 already treats the p95 target as
        // soft for exactly this reason. Asking for less would only make it worse.
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { enabled, error in
            if enabled {
                ingestionLog.info("HealthKit background delivery enabled for workouts.")
                return
            }

            // The single most important log line in the app. Without the
            // com.apple.developer.healthkit.background-delivery entitlement this call
            // fails with HKError.Code.errorAuthorizationDenied and the app is never
            // woken again — no crash, no user-visible symptom, just a capture pipeline
            // that captures nothing (PRD §13, tracker R5).
            let reason = error.map { String(describing: $0) } ?? "no error reported"
            ingestionLog.error("HealthKit background delivery NOT enabled: \(reason, privacy: .public)")
            ingestionLog.error("Zero-touch capture is inert. Verify the com.apple.developer.healthkit.background-delivery entitlement is present in the signed build, and that Health access was granted.")
        }
    }

    /// Stops the observer query. Not used in the launch path; present so the query's
    /// lifetime is explicit rather than implicitly forever.
    func stopObservingWorkouts() {
        guard let observerQuery else { return }
        healthStore.stop(observerQuery)
        self.observerQuery = nil
    }
}

enum HealthKitObserverError: Error {
    /// HealthKit is not present on this device (iPad before iPadOS 17, macOS, and so
    /// on). Distinct from "the user said no", which HealthKit does not disclose.
    case healthDataUnavailable
}

// MARK: - Core vocabulary → HealthKit types

private extension HealthDataType {
    /// The HealthKit type this core case names.
    ///
    /// A total mapping with no optionals and no force unwraps: the identifier-based
    /// initialisers (`HKQuantityType(_:)`, iOS 15+) are non-failable, unlike the older
    /// `HKObjectType.quantityType(forIdentifier:)`, which returns an optional and
    /// invites exactly the `!` that CLAUDE.md forbids.
    ///
    /// Exhaustive by design — a new case in `MaximizeCore` should fail to compile here
    /// rather than fall into a `default` that silently drops it from the request.
    var healthKitObjectType: HKObjectType {
        switch self {
        case .workout:
            return HKObjectType.workoutType()
        case .heartRate:
            return HKQuantityType(.heartRate)
        case .distanceWalkingRunning:
            return HKQuantityType(.distanceWalkingRunning)
        case .activeEnergyBurned:
            return HKQuantityType(.activeEnergyBurned)
        case .stepCount:
            return HKQuantityType(.stepCount)
        case .workoutRoute:
            return HKSeriesType.workoutRoute()
        }
    }
}
