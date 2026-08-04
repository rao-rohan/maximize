import Foundation

/// **The MAX-031 → MAX-032/033 seam.**
///
/// MAX-031 answers "which workouts are new?" and stops there. What happens to one — the
/// full-fidelity HR series and route (MAX-032, FR-0.3), the derived metrics and the
/// score (MAX-033, FR-0.5, D2) — happens behind this protocol.
///
/// A `Workout` is the whole handoff, and it is enough: it carries the identifier the
/// downstream store dedupes on and the `start`/`end` window every sample query needs as
/// its predicate. MAX-012's `DerivedMetricsInput` additionally wants a step count, which
/// `Workout` does not carry — that is MAX-032's to fetch from the same window, and
/// nothing here needs to be reshaped for it to do so.
///
/// ## What an implementation owes the ingester
///
/// The ingester's whole safety argument rests on two of these:
///
/// - **`hasIngestedWorkout` and `ingest` are the dedupe pair (FR-0.5).** `ingest` may be
///   called with a workout that has already been ingested if the ingester's own guard is
///   bypassed, and it must be a no-op in that case rather than a second record.
/// - **`ingest` returning means the workout is durably stored.** The ingester persists
///   the anchor immediately afterwards, and the anchor moving past a workout is the one
///   irreversible step in the pipeline. An implementation that returns before the write
///   has landed converts a crash into permanent silent loss.
///
/// ## And a warning about throwing
///
/// A thrown error stops the pass and leaves the anchor where it was, so the workout is
/// re-delivered on the next pass. That is right for a *transient* failure and wrong for a
/// permanent one: a workout this sink can never accept will be refetched and rethrown on
/// every wake forever, blocking every workout behind it. An implementation that discovers
/// a permanently unacceptable workout should record it as handled — however it likes —
/// and return, rather than throwing in perpetuity.
public protocol WorkoutIngestionSink: Sendable {
    /// Whether this workout has already been durably ingested. Dedupe on
    /// `workoutUUID` (FR-0.5, A2) — the same key `Workout.id` carries.
    func hasIngestedWorkout(id: UUID) async throws -> Bool

    /// Takes ownership of a workout that has not been ingested before. Returns only once
    /// the record is durable.
    func ingest(_ workout: Workout) async throws

    /// Handles a workout the health store reports as deleted.
    ///
    /// Must be a no-op for an identifier that was never ingested — a deletion can be
    /// re-delivered, and the very first fetch after a lost anchor can report the deletion
    /// of something this app never saw.
    func discardWorkout(id: UUID) async throws
}

/// Stand-in `WorkoutIngestionSink` for the window between MAX-031 and MAX-033.
///
/// It **throws**, and that is the entire point of it. A sink that quietly accepted and
/// dropped workouts would let the anchor advance past real runs, and they would be gone —
/// no error, no retry, nothing on screen, nothing in CI. Throwing keeps the anchor
/// pinned: every wake refetches the same pending workouts, fails, and acknowledges, until
/// MAX-032/033 land and the backlog drains on the next wake.
///
/// The visible cost until then is one reported failure per background wake. That is the
/// correct symptom for "the pipeline is half-built" — loud, harmless, and self-clearing.
public struct AwaitingPipelineWorkoutSink: WorkoutIngestionSink {
    public init() {}

    public func hasIngestedWorkout(id: UUID) async throws -> Bool {
        // Nothing has been ingested, because nothing can be yet.
        false
    }

    public func ingest(_ workout: Workout) async throws {
        throw IngestionPipelineIncomplete.workoutHandlingNotImplemented
    }

    public func discardWorkout(id: UUID) async throws {
        throw IngestionPipelineIncomplete.workoutHandlingNotImplemented
    }
}

/// Raised by `AwaitingPipelineWorkoutSink`. Distinguishable from a real failure so a
/// reader of the failure report can tell "not built yet" from "broken".
public enum IngestionPipelineIncomplete: Error, Hashable, Sendable {
    case workoutHandlingNotImplemented
}
