import Foundation
import HealthKit
import MaximizeCore
import OSLog
import UIKit

/// Composition root for the zero-touch capture pipeline (PRD §7.0).
///
/// Everything the wake path needs is assembled here, once, so that the pieces
/// themselves stay ignorant of each other. MAX-031 → MAX-033 land by replacing exactly
/// one line below.
@MainActor
enum IngestionComposition {
    /// One store for the whole app. Apple: "You need only a single HealthKit store per
    /// app. These are long-lived objects; you create the store once, and keep a
    /// reference for later use."
    private static let healthStore = HKHealthStore()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Maximize",
        category: "ingestion"
    )

    /// **The MAX-031 → MAX-033 seam.**
    ///
    /// Replace `UningestedWorkoutsPlaceholder()` with the real ingester — anchored
    /// incremental fetch (MAX-031), sample extraction (MAX-032), dedupe/derive/store
    /// (MAX-033) — and the entire wake path above it is already built, tested, and
    /// unchanged.
    private static let coordinator = WorkoutObservationCoordinator(
        ingester: UningestedWorkoutsPlaceholder(),
        reportFailure: { error in
            // Pipeline state only. No workout, no sample, no identifier — CLAUDE.md
            // treats health data as PII and rules it out of logs entirely.
            log.error("Workout ingestion failed: \(String(describing: error), privacy: .public)")
        }
    )

    static let workoutObserver = HealthKitWorkoutObserver(
        healthStore: healthStore,
        responder: coordinator
    )
}

/// Exists for one reason: HealthKit observer queries must be registered from
/// `application(_:didFinishLaunchingWithOptions:)`.
///
/// Apple states this directly, and the mechanism behind it matters more than the rule.
/// When HealthKit wakes a suspended app to deliver a change, it calls the update
/// handler of every already-registered observer query — an app that registers its
/// queries later, from a scene or a view's `.task`, has no queries at the moment the
/// delivery arrives. A background launch may never build a view at all. Registering
/// here is what makes "once at launch" (FR-0.1) true on the launches that are not the
/// user opening the app, which are the only launches zero-touch capture depends on.
///
/// No authorization is requested from here: the permission sheet needs a foreground,
/// and a background-launched app has none. That affordance lives in Settings.
final class MaximizeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Idempotent, and cheap when HealthKit access has not been granted: the query
        // is registered and simply never fires.
        IngestionComposition.workoutObserver.startObservingWorkouts()
        return true
    }
}
