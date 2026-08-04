/// Turns "workouts may have changed" into "ingest, then acknowledge".
///
/// This is the whole decision content of MAX-030's wake path, and it is here — in a
/// pure Swift type with an injected collaborator — rather than inside the HealthKit
/// adapter, because everything in the adapter is unverifiable by this repo's CI while
/// everything here is checked on every commit.
///
/// ## When the acknowledgement happens, and why
///
/// Apple's guidance is to acknowledge *after* the work:
///
/// > After your observer queries have finished processing the new data, you must call
/// > the update's completion handler.
/// > — `enableBackgroundDelivery(for:frequency:withCompletion:)`, "Receive Background
/// >   Updates"
///
/// So the acknowledgement is not fired on entry. Acknowledging first would tell iOS
/// the delivery was handled while the fetch is still in flight, and iOS would be free
/// to suspend the app mid-ingest — the app would look healthy and lose data.
///
/// The harder question is what to do when ingestion *fails*. The two options are not
/// symmetric:
///
/// - **Acknowledge only on success.** iOS retries with backoff, which sounds like the
///   robust choice — until the third consecutive failure, at which point HealthKit
///   concludes the app cannot receive data and stops delivering background updates
///   altogether. That state is silent and does not repair itself.
/// - **Acknowledge on every path.** A failed wake is simply lost. But it is lost into
///   a pipeline built to survive exactly that: the anchored query (MAX-031, FR-0.2)
///   persists its anchor, so the next wake — from the next workout, or from the app
///   coming to the foreground — refetches everything since the anchor and the missed
///   workout is picked up with no special handling.
///
/// One option degrades to "a run shows up later"; the other degrades to "the product
/// silently stops working". This type takes the second path: **acknowledge exactly
/// once, after the ingestion attempt, whether or not it succeeded.**
///
/// The consequence to be honest about: because we always acknowledge, we never get
/// iOS's retry. That is a deliberate trade, and it is only sound while ingestion stays
/// idempotent and anchored. If MAX-031 ever lands a fetch that is *not* anchored, this
/// reasoning stops holding and this decision must be revisited.
public actor WorkoutObservationCoordinator: WorkoutChangeResponding {
    private let ingester: WorkoutIngesting
    private let reportFailure: @Sendable (Error) -> Void

    /// - Parameters:
    ///   - ingester: the work a wake triggers. `UningestedWorkoutsPlaceholder` until
    ///     MAX-031 lands.
    ///   - reportFailure: called when an ingestion attempt throws, and when the
    ///     observation mechanism itself reports an error. Defaults to discarding,
    ///     which is the honest default for a type that has no opinion about logging.
    ///
    ///     Whatever is passed here **must not write health data anywhere durable** —
    ///     CLAUDE.md treats workout data as PII and rules out logs, analytics, and
    ///     crash reports. Errors on this path describe the pipeline, not the person.
    public init(
        ingester: WorkoutIngesting,
        reportFailure: @escaping @Sendable (Error) -> Void = { _ in }
    ) {
        self.ingester = ingester
        self.reportFailure = reportFailure
    }

    public func workoutsMayHaveChanged(
        observationError: Error?,
        acknowledge: @escaping @Sendable () -> Void
    ) async {
        let acknowledgement = BackgroundDeliveryAcknowledgement(acknowledge)

        if let observationError {
            reportFailure(observationError)
        }

        // An errored wake still runs the ingest. The observation mechanism reporting a
        // problem says nothing about whether the store gained a workout, and the
        // anchored fetch is the authority on what is actually new: treating the wake as
        // "maybe something changed" costs one redundant query, while treating it as
        // "nothing changed" costs a missed run.
        do {
            try await ingester.ingestPendingWorkouts()
        } catch {
            reportFailure(error)
        }

        // Reached on every path above — success, ingestion failure, and errored wake.
        // See the type documentation for why failure acknowledges too.
        acknowledgement.acknowledge()
    }
}
