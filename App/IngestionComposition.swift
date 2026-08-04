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
/// themselves stay ignorant of each other. MAX-033 landed by replacing one argument
/// below — `sink` — and MAX-023 lands by replacing one more: `model`.
@MainActor
enum IngestionComposition {
    /// One store for the whole app. Apple: "You need only a single HealthKit store per
    /// app. These are long-lived objects; you create the store once, and keep a
    /// reference for later use."
    private static let healthStore = HKHealthStore()

    /// MAX-033's pipeline (FR-0.5, D2), or a sink that pins the anchor if there is no
    /// store to write to.
    ///
    /// **This is the line that un-pins the pipeline.** Every decision inside it lives in
    /// `MaximizeCore` and is tested there; what happens here is only the joining up.
    ///
    /// `ScoringModelInvoking` is MAX-023's, and until it lands the placeholder throws.
    /// That is safe in a way `AwaitingPipelineWorkoutSink` was not: a failed scoring call
    /// leaves a stored, measured, classified workout with no score, which is a first-class
    /// state (and the app's real steady state before an API key is entered). Capture
    /// works today; scores arrive when MAX-023 replaces one argument below.
    ///
    /// The store comes from `PersistenceComposition` (MAX-020/MAX-041) rather than from a
    /// container opened here. Two `ModelContainer`s over one SQLite file is not a
    /// duplicated object, it is two SwiftData stacks writing the same store, and the
    /// background wake would be the writer nobody was watching.
    ///
    /// A store that could not be opened is the *transient* case, so the placeholder sink
    /// stays: pinning the anchor keeps the pending workouts waiting for a launch where the
    /// container opens, rather than acknowledging wakes whose data went nowhere.
    private static let pipeline: WorkoutIngestionPipeline? = {
        guard let workoutStore = PersistenceComposition.store else {
            ingestionLog.error("The workout store is unavailable; ingestion will hold the anchor until it opens.")
            return nil
        }
        return WorkoutIngestionPipeline(
            workouts: workoutStore,
            scores: workoutStore,
            plans: workoutStore,
            samples: HealthKitWorkoutSampleFetcher(healthStore: healthStore),
            model: AwaitingTransportScoringModel(),
            report: { diagnostic in
                // Reasons only — `IngestionPipelineDiagnostic` carries no health data, no
                // identifiers and no dates, and that is only worth anything if the sink
                // for it respects it.
                switch diagnostic {
                case let .sampleExtraction(event):
                    ingestionLog.info("Sample extraction gap: \(String(describing: event), privacy: .public)")
                case let .storedWithoutPlan(reason):
                    ingestionLog.notice("Workout stored without derived metrics (\(String(describing: reason), privacy: .public)); it will be completed once a plan governs it.")
                case let .enrichmentFailed(stage):
                    ingestionLog.error("Enrichment failed at \(String(describing: stage), privacy: .public); the workout is stored and can be completed later.")
                case let .leftUnscored(reason):
                    ingestionLog.notice("Workout stored but unscored (\(String(describing: reason), privacy: .public)); scoring is retried on first view.")
                case let .workoutAbandoned(step):
                    // R11's escape actually firing. Loud, because it is the one place the
                    // pipeline gives up on a workout permanently.
                    ingestionLog.error("Gave up on a workout at \(String(describing: step), privacy: .public) so the anchor could advance past it.")
                }
            }
        )
    }()

    private static let sink: WorkoutIngestionSink = { () -> WorkoutIngestionSink in
        guard let pipeline else { return AwaitingPipelineWorkoutSink() }
        return pipeline
    }()

    /// MAX-031's anchored incremental fetch (FR-0.2), assembled from three parts that know
    /// nothing about each other: a HealthKit query, a file holding the anchor, and the
    /// core's rules about when that anchor may move.
    private static let ingester = AnchoredWorkoutIngester(
        fetcher: HealthKitWorkoutFetcher(healthStore: healthStore),
        anchorStore: FileWorkoutQueryAnchorStore(),
        sink: sink,
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
            // `.private`, unlike the diagnostics above, and the difference is the point.
            // Those interpolate payload-free enums whose cases carry no measurement, date
            // or identifier, so publishing them is safe and useful. This one interpolates
            // an *arbitrary* `Error`, and MAX-033 made real store failures reachable here
            // for the first time. A Core Data validation error can carry
            // `NSValidationErrorObject` in its `userInfo`, which would print stored row
            // values — health data, in a log, which CLAUDE.md forbids without qualification.
            //
            // Reaching it is unlikely: MAX-020's schema defaults every non-optional
            // property and the values written are pre-validated domain types, so realistic
            // failures are I/O rather than validation. But "unlikely to contain PII" is not
            // the bar, and `.private` still shows the full error to a debugger attached in
            // Xcode — the only place anyone actually reads it.
            ingestionLog.error("Workout ingestion failed: \(String(describing: error), privacy: .private)")
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
                // `.private` for the same reason as `reportFailure` above: this is an
                // arbitrary `Error`, not one of the payload-free pipeline diagnostics.
                ingestionLog.error("Foreground ingestion pass failed: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Scores a workout that was captured but left unscored — R8's lazy path.
    ///
    /// The detail view (MAX-041) is the natural caller: it is the screen that renders the
    /// unscored state, and the athlete looking at a run is the moment a network call is
    /// both affordable and wanted. Idempotent and cheap when there is nothing to do, so a
    /// view may call it unconditionally on appear.
    /// Awaitable rather than fire-and-forget: the caller is a screen that wants to redraw
    /// once the score has landed, and a detached task would have it redraw before.
    static func completeIngestion(forWorkout id: UUID) async {
        guard let pipeline else { return }
        await pipeline.completeIngestion(forWorkout: id)
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
