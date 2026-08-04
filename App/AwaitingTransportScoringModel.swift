import Foundation
import MaximizeCore

/// Stand-in `ScoringModelInvoking` for the window between MAX-033 and MAX-023.
///
/// Unlike `AwaitingPipelineWorkoutSink` — the placeholder this ticket removes — throwing
/// here is *harmless*, and the difference is the whole point of MAX-033's design. A sink
/// that threw held the anchor and stopped capture. A model that throws leaves a workout
/// stored, measured and classified, with no score; `WorkoutIngestionPipeline` treats that
/// as a complete record and `completeIngestion(forWorkout:)` scores it later.
///
/// So with this in place the pipeline is already doing its job: every run is captured,
/// nothing is pinned, and the backlog drains. What is missing is the last field of each
/// record, and MAX-023 fills it in by replacing exactly one line in
/// `IngestionComposition`.
///
/// This is also, exactly, the shape of the app's real steady state before the athlete has
/// entered an API key — so it is not a special case being simulated, it is the ordinary
/// no-key path arriving early.
struct AwaitingTransportScoringModel: ScoringModelInvoking {
    func reply(to instruction: ScoringInstruction) async throws -> String {
        throw ScoringTransportUnavailable.clientNotImplemented
    }
}

/// Raised by `AwaitingTransportScoringModel`. Distinguishable from a real transport
/// failure so a reader can tell "not built yet" from "no network".
enum ScoringTransportUnavailable: Error {
    case clientNotImplemented
}
