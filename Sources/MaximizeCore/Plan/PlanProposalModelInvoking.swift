/// Sends a plan-drafting instruction to the model and returns its raw, unparsed reply
/// (CHAT-FIRST-SPEC.md §4.7).
///
/// Raw rather than parsed, for the reason `ScoringModelInvoking` gives: `PlanProposal`
/// owns validation, and a transport that pre-interpreted a reply would be a second
/// opinion about what the model said. It would also be a second opinion living in the App
/// layer, which CI compiles and never executes.
///
/// The implementation is MAX-100 (`AnthropicPlanProposalClient`), and it is a
/// **non-streaming** call: a proposal is a structured object the athlete reviews as a
/// card, not prose to watch arrive, so there is nothing to stream. §4.7 names this Phase
/// A and is explicit that Phase B — a proposal emerging mid-stream — needs either tool use
/// or fenced-JSON detection inside a streaming bubble, and buys a better feel rather than
/// a new capability.
///
/// Two obligations on whoever implements it, both inherited rather than new:
///
/// - **No prompt text.** Every word sent belongs to `PlanProposalInstruction`, including
///   the retry wording. A client that composed its own instruction would be a second
///   author of what the model is asked to do.
/// - **No response body in an error.** `ScoringModelError` sets the precedent and states
///   the rule: an error may say that a request failed and its status code, never its body.
///   A plan-drafting request carries the athlete's training in `factSheet`.
///
/// A14's invariant applies unchanged: **no unattended chat call, ever.** A proposal is
/// obtained because the athlete tapped "Draft a plan from this conversation" — one call
/// per tap, bounded by being a button.
public protocol PlanProposalModelInvoking: Sendable {
    func reply(to instruction: PlanProposalInstruction) async throws -> String
}
