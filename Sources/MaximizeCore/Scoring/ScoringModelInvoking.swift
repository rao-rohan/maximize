/// Sends a scoring instruction to the model and returns its raw, unparsed reply.
///
/// Raw rather than parsed: `WorkoutScorer` owns validation, and a transport that
/// pre-interpreted a reply would be a second opinion about what the model said.
///
/// This is the seam MAX-023 owns and MAX-033 (the ingestion pipeline) drives:
/// `WorkoutScorer.instruction(for:evaluation:)` decides what to ask, something
/// conforming to this protocol asks it, and `WorkoutScorer.score(context:evaluation:
/// modelResponse:scoredAt:)` decides whether the reply is acceptable. Nothing on
/// either side of that boundary needs to know how the other half is implemented.
///
/// The real implementation (`AnthropicScoringModelClient`, App layer) speaks the
/// Anthropic Messages API over `URLSession`; `MaximizeCoreTestSupport` supplies
/// `FakeScoringModelInvoking` for everything that needs to drive `WorkoutScorer`
/// without a network call, which today is every test in this repo — see CLAUDE.md,
/// "What CI can and cannot prove".
public protocol ScoringModelInvoking: Sendable {
    func reply(to instruction: ScoringInstruction) async throws -> String
}
