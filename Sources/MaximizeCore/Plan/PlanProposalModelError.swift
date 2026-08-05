import Foundation

/// Why a plan-drafting call failed at the **transport** layer — never at the content
/// layer, which is `PlanProposalError`'s job.
///
/// The split mirrors `ScoringModelError` / `ScoringError` deliberately, and for the
/// same reason: `PlanProposalError` covers "the model answered, and the JSON (or the
/// plan data behind it) was wrong somehow" — it is what `PlanProposal.parse` throws
/// once a reply string exists. This type covers everything before a reply string
/// exists at all, or that arrives instead of one: no key, no network, an HTTP status
/// the API returned, or a response whose *shape* (not its content) was not a plan
/// answer.
///
/// A caller driving §4.5's one permitted retry needs to tell "ask again, this can
/// plausibly succeed" from "do not ask again until something changes" without
/// inspecting a message string or guessing from a case name —
/// `isWorthRetrying` makes that explicit, the same role it plays on
/// `ScoringModelError`. Note that §4.5's retry is orthogonal to this: that retry is
/// driven by a *content* failure (`PlanProposalError`, a malformed or rejected
/// proposal) and is MAX-101's policy. This type's `isWorthRetrying` is about the
/// transport call itself failing before any content existed to judge.
///
/// **Never carries a response body, and never carries the key.** Every associated
/// value here is a bare status code — a number the server put on the wire, not text
/// it or the model wrote. See CLAUDE.md, "Health and privacy": *"An error you surface
/// may say that a request failed and its status code — never its body."* A
/// plan-drafting request carries the athlete's training in `factSheet`.
public enum PlanProposalModelError: Error, Hashable, Sendable, CustomStringConvertible {

    // MARK: - Before any request could be sent

    /// No key is stored in Keychain. The state of the app the moment it is
    /// installed, and a first-class outcome rather than a crash — see
    /// `AnthropicPlanProposalClient`, which checks this before building a request
    /// rather than letting an absent key surface as a header the API rejects.
    case noAPIKeyStored

    // MARK: - The request could not complete

    /// A connectivity failure below the HTTP layer: offline, DNS failure, a dropped
    /// connection, and similar. The device's radio state is transient by nature, so
    /// asking again — once there is a network to ask over — can plausibly succeed.
    case requestFailed

    /// No response arrived inside the caller-configured budget. Deliberately not a
    /// fixed constant on this type: the caller states its own budget, and this type
    /// only reports whichever one it was given.
    case timedOut

    // MARK: - The API responded with an HTTP failure

    /// 401 — the stored key was rejected. Retrying the same key fails identically;
    /// the fix is a new key in Settings, not another attempt with this one.
    case invalidAPIKey

    /// 429 — rate limited. The API's own signal that the right response is to slow
    /// down and ask again later, not to stop asking altogether.
    case rateLimited

    /// 5xx, including 529 (overloaded) — a fault on Anthropic's side, not this
    /// request's. Carries the status code for diagnostics only.
    case serverUnavailable(statusCode: Int)

    /// Any other non-2xx status this client does not otherwise distinguish (400,
    /// 403, 404, 413, …). A 400 here means this client built a request the API
    /// rejected — a bug in `AnthropicPlanProposalClient`, not a fact about the
    /// athlete's plan — so retrying the identical request will fail the same way
    /// every time.
    case unexpectedStatus(Int)

    // MARK: - The API responded, but not with a plan answer

    /// `stop_reason: "refusal"` — the model's safety classifiers declined the
    /// request, with HTTP 200 and no exception raised at the HTTP layer. A policy
    /// outcome for this exact instruction, not a fluke; the same instruction sent
    /// again will very likely be declined again.
    case refused

    /// `stop_reason: "max_tokens"` — the reply was cut off before it finished. A
    /// truncated proposal is worse than a failed one, because the envelope check in
    /// `PlanProposal.parse` may still see a `{` and a `}` around a JSON object that
    /// is missing its closing fields — so this is reported distinctly rather than
    /// left to surface as a decoding failure downstream. Hitting it signals a
    /// configuration problem in the client (too small a `max_tokens`), not the model
    /// struggling with this athlete's plan. Retrying the identical request truncates
    /// again.
    case truncated

    /// The response was 2xx, but its body was not the Messages API shape this
    /// client expects, or carried no usable text content. An API contract
    /// mismatch — a version drift or a malformed client request — not a per-call
    /// fluke that a retry would route around.
    case unreadableResponse

    /// Whether asking again, unchanged, could plausibly produce a different
    /// outcome.
    ///
    /// `true` means the fault was transient — the network, this moment's load on
    /// Anthropic's side, or a clock running out — and the same request may simply
    /// succeed next time. `false` means something has to change first: a key stored
    /// in Settings, a fix to this client's request shape, or Anthropic's policy
    /// verdict on this exact instruction — a retry loop around any of those just
    /// spends a token budget to relearn the same fact.
    public var isWorthRetrying: Bool {
        switch self {
        case .requestFailed, .timedOut, .rateLimited, .serverUnavailable:
            return true
        case .noAPIKeyStored, .invalidAPIKey, .unexpectedStatus, .refused, .truncated, .unreadableResponse:
            return false
        }
    }

    public var description: String {
        switch self {
        case .noAPIKeyStored:
            return "No Anthropic API key is stored"
        case .requestFailed:
            return "The plan-drafting request could not be sent (connectivity failure)"
        case .timedOut:
            return "The plan-drafting request timed out"
        case .invalidAPIKey:
            return "The Anthropic API rejected the stored key (401)"
        case .rateLimited:
            return "The Anthropic API rate-limited this request (429)"
        case let .serverUnavailable(statusCode):
            return "The Anthropic API returned a server error (status \(statusCode))"
        case let .unexpectedStatus(statusCode):
            return "The Anthropic API returned an unexpected status (\(statusCode))"
        case .refused:
            return "The model declined to answer this request (stop_reason: refusal)"
        case .truncated:
            return "The model's reply was cut off before it finished (stop_reason: max_tokens)"
        case .unreadableResponse:
            return "The response was not a recognizable plan-drafting reply"
        }
    }
}
