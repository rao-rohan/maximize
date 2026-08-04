import Foundation

/// Why a streaming chat turn ended without a complete answer.
///
/// The mirror of `ScoringModelError`, one feature over, and it keeps that type's two
/// hard rules:
///
/// - **Never carries a response body, and never carries the key.** The only
///   associated value anywhere below is a bare HTTP status code — a number the server
///   put on the wire, not text it or the model wrote. Health data lives in the
///   request this describes the failure of, and none of it is reachable from any
///   case's payload.
/// - **A caller deciding whether to ask again reads `isWorthRetrying`**, not a message
///   string and not a case name.
///
/// ## This is a value, not a thrown error
///
/// It arrives as `ChatStreamEvent.failed`, inside a stream that does not throw. The
/// reason is FR-2.4's shape: by the time a chat call fails, the screen may already be
/// showing half an answer. A `throw` invites a `catch` that replaces the bubble with
/// an error state and drops the text; an event says "that is all there will be" while
/// leaving everything already delivered exactly where it is. See
/// `ChatStreamEvent`'s documentation for the full rule.
public enum ChatStreamError: Error, Hashable, Sendable, CustomStringConvertible {

    // MARK: - Before any request could be sent

    /// No key is stored in Keychain. The state of the app the moment it is installed,
    /// and a first-class outcome rather than a crash — the same case
    /// `ScoringModelError.noAPIKeyStored` covers for scoring, and for the same reason.
    case noAPIKeyStored

    /// The key store itself failed — a corrupt Keychain item, or a Keychain that
    /// would not answer.
    ///
    /// Deliberately *not* folded into `noAPIKeyStored`, matching
    /// `AnthropicScoringModelClient`'s reasoning: "no key was ever stored" and "the
    /// stored key could not be read" want different words on screen, and collapsing
    /// them hides a Keychain-integrity problem behind a "go add a key" message that
    /// will not fix it.
    case keyStoreUnavailable

    // MARK: - The request could not complete

    /// A connectivity failure below the HTTP layer: offline, DNS failure, a dropped
    /// connection before any bytes arrived.
    case requestFailed

    /// The response never began inside the caller-configured budget.
    ///
    /// Scoped to the wait *before* the first byte on purpose. Once tokens are arriving
    /// there is text on screen, and a connection that then stalls is reported as
    /// `interrupted` — the case whose whole meaning is "this is all there will be, and
    /// what you already have still stands". Splitting them this way means the two
    /// failures a chat view has to render differently are two cases, not one.
    case timedOut

    // MARK: - The API responded with an HTTP failure

    /// 401 — the stored key was rejected. Retrying the same key fails identically;
    /// the fix is a new key in Settings.
    case invalidAPIKey

    /// 429 before the stream opened, or a `rate_limit_error` arriving inside it.
    case rateLimited

    /// 5xx, including 529 (overloaded). Carries the status code for diagnostics only.
    case serverUnavailable(statusCode: Int)

    /// Any other non-2xx status this client does not otherwise distinguish. A 400
    /// here means this client built a request the API rejected — a bug in
    /// `AnthropicStreamingChatClient`, not a fact about the workout being discussed —
    /// so the identical request will fail the same way every time.
    case unexpectedStatus(Int)

    // MARK: - The stream opened, but the turn did not finish

    /// `stop_reason: "refusal"` — the model's safety classifiers declined, with HTTP
    /// 200 and no error at the transport layer. A policy outcome for this exact
    /// exchange; asking again unchanged will very likely be declined again.
    case refused

    /// The connection ended before the turn did — no `message_stop`, no stop reason.
    ///
    /// The ordinary shape of a phone losing signal mid-answer, and the case that makes
    /// the partial-text rule matter: everything already delivered is still true, it
    /// just stops there. Worth retrying, but a retry asks the question again from
    /// scratch and produces a *new* answer — it does not resume this one, and a caller
    /// that splices the two together would be inventing a reply the model never gave.
    case interrupted

    /// An `error` event arrived inside an already-successful stream, and it was not
    /// rate limiting.
    ///
    /// Treated as transient. A request the API considers malformed never reaches 200
    /// in the first place, so what actually arrives here is Anthropic-side overload or
    /// infrastructure trouble mid-generation, which is exactly the kind of fault that
    /// clears on its own.
    case midStreamFailure

    /// A frame arrived that this client could not read: a `data:` payload that is not
    /// JSON, or JSON that is not the Messages API's streaming shape. An API contract
    /// mismatch — version drift, or a malformed request — not a per-call fluke a retry
    /// would route around.
    case unreadableResponse

    /// Whether asking again, unchanged, could plausibly produce a different outcome.
    ///
    /// Same split as `ScoringModelError.isWorthRetrying`: `true` means the fault was
    /// transient — the network, this moment's load on Anthropic's side, a clock running
    /// out — and `false` means something has to change first (a key in Settings, a fix
    /// to this client, or Anthropic's policy verdict on this exact exchange).
    public var isWorthRetrying: Bool {
        switch self {
        case .requestFailed, .timedOut, .rateLimited, .serverUnavailable, .interrupted, .midStreamFailure:
            return true
        case .noAPIKeyStored, .keyStoreUnavailable, .invalidAPIKey, .unexpectedStatus, .refused, .unreadableResponse:
            return false
        }
    }

    public var description: String {
        switch self {
        case .noAPIKeyStored:
            return "No Anthropic API key is stored"
        case .keyStoreUnavailable:
            return "The stored Anthropic API key could not be read"
        case .requestFailed:
            return "The chat request could not be sent (connectivity failure)"
        case .timedOut:
            return "The chat response stalled and timed out"
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
        case .interrupted:
            return "The connection ended before the reply finished"
        case .midStreamFailure:
            return "The Anthropic API reported an error part-way through the reply"
        case .unreadableResponse:
            return "The response was not a recognizable streaming reply"
        }
    }
}
