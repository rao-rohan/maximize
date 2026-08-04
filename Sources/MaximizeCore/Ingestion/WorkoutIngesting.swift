/// Fetches and stores workouts that have appeared since the last successful ingest.
///
/// **This is the seam MAX-031 → MAX-033 fill in.** MAX-030 builds only the wake-up
/// path: something notices new workouts may exist, and this protocol is where the
/// consequence is handed off. The real implementation is the anchored incremental
/// fetch (MAX-031, FR-0.2), full-fidelity sample extraction (MAX-032, FR-0.3), and
/// the dedupe/derive/store/score pipeline (MAX-033, FR-0.5, D2).
///
/// Two obligations on implementations, both inherited from how the platform behaves
/// rather than from taste:
///
/// - **Idempotent.** iOS may deliver the same change more than once, and a wake may
///   arrive with nothing actually new behind it. FR-0.5 / A2 satisfy this by deduping
///   on `workoutUUID` at write time. A caller must be able to invoke this on every
///   wake without checking first.
/// - **Bounded.** The system grants a short, unspecified window when it wakes an app
///   in the background (tracker R8). An implementation that blocks indefinitely —
///   say, on a network call to Claude for scoring — does not just fail slowly; it
///   delays the acknowledgement that keeps background delivery alive. R8's resolution
///   is that MAX-033 scores lazily on first view when the wake budget is exceeded,
///   which keeps this call short.
public protocol WorkoutIngesting: Sendable {
    /// Ingests everything not yet ingested. Safe to call repeatedly.
    func ingestPendingWorkouts() async throws
}

/// Stand-in `WorkoutIngesting` for the window between MAX-030 and MAX-031.
///
/// Deliberately not a silent no-op in disguise: the wake path is fully wired and
/// exercised end to end with this in place, so when MAX-031 swaps in the anchored
/// fetch, the only thing that changes is one line in the app's composition root. It
/// does nothing because there is nothing yet to do, not because the call was
/// forgotten.
public struct UningestedWorkoutsPlaceholder: WorkoutIngesting {
    public init() {}

    public func ingestPendingWorkouts() async throws {
        // MAX-031: anchored `HKAnchoredObjectQuery` with a persisted anchor.
    }
}
