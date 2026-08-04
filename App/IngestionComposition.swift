import Foundation
import HealthKit
import MaximizeCore
import OSLog
import UIKit

/// Logger for the ingestion pipeline's *plumbing*.
///
/// Deliberately at file scope and not inside `IngestionComposition`: it is read from
/// HealthKit's background callbacks, and a member of a `@MainActor` type would be
/// isolated to the main actor and therefore wrong to touch from there. `Logger` is
/// itself `Sendable`, so a non-isolated global is the honest shape.
///
/// **No health data ever goes through this.** CLAUDE.md treats workout data as PII and
/// rules it out of logs entirely; every call site below records pipeline state only —
/// never a sample, a date, or an identifier.
let ingestionLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Maximize",
    category: "ingestion"
)

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

    /// MAX-031's anchored incremental fetch (FR-0.2), assembled from three parts that know
    /// nothing about each other: a HealthKit query, a file holding the anchor, and the
    /// core's rules about when that anchor may move.
    ///
    /// **The MAX-032/033 seam is now `sink`.** `AwaitingPipelineWorkoutSink` throws, which
    /// is deliberate and safe: a sink that silently accepted workouts would let the anchor
    /// advance past real runs and lose them. Throwing pins the anchor, so every pending
    /// workout is still waiting — and is picked up on the first wake after MAX-032/033
    /// land. Until then this logs one failure per wake, which is the correct symptom for a
    /// half-built pipeline.
    private static let ingester = AnchoredWorkoutIngester(
        fetcher: HealthKitWorkoutFetcher(healthStore: healthStore),
        anchorStore: FileWorkoutQueryAnchorStore(),
        sink: AwaitingPipelineWorkoutSink(),
        report: { diagnostic in
            // Counts and reasons only — `IngestionDiagnostic` carries no health data, and
            // that is only worth anything if the sink for it respects it.
            switch diagnostic {
            case let .storedAnchorDiscarded(reason):
                ingestionLog.notice("Stored workout anchor discarded (\(String(describing: reason), privacy: .public)); refetching the backfill window.")
            case let .workoutsUnrepresentable(count):
                ingestionLog.error("\(count, privacy: .public) health-store object(s) could not be represented as workouts; the anchor has moved past them.")
            case let .passTruncated(batchesProcessed):
                ingestionLog.info("Ingestion pass stopped after \(batchesProcessed, privacy: .public) batches; the remainder resumes on the next pass.")
            }
        }
    )

    private static let coordinator = WorkoutObservationCoordinator(
        ingester: ingester,
        reportFailure: { error in
            // Pipeline state only, per `ingestionLog`'s contract above.
            ingestionLog.error("Workout ingestion failed: \(String(describing: error), privacy: .public)")
        }
    )

    static let workoutObserver = HealthKitWorkoutObserver(
        healthStore: healthStore,
        responder: coordinator
    )

    /// Runs an ingestion pass outside the wake path.
    ///
    /// The anchored fetch recovers a failed or missed wake on the *next* pass, and a wake
    /// only happens when new data arrives. Without this, a workout whose ingestion failed
    /// would wait for the next workout to be recorded. Opening the app is the other
    /// natural trigger, and it costs one query when there is nothing to do.
    static func ingestPendingWorkouts() {
        Task {
            do {
                try await ingester.ingestPendingWorkouts()
            } catch {
                ingestionLog.error("Foreground ingestion pass failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
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

    /// A second, non-wake trigger for the anchored fetch.
    ///
    /// Recovery from a failed wake is "the next pass picks it up", and a wake only happens
    /// when HealthKit has something new. Opening the app is the other moment a pass can
    /// run, and it is what keeps "delayed" from meaning "delayed until the next workout".
    /// Cheap when there is nothing pending: one anchored query returning nothing.
    func applicationDidBecomeActive(_ application: UIApplication) {
        IngestionComposition.ingestPendingWorkouts()
    }
}
