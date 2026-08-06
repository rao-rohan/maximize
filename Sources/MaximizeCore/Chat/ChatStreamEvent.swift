import Foundation

/// How a chat turn ended, when it ended normally.
///
/// "Normally" is doing work here: both cases mean the model produced a reply and the
/// text delivered so far is the whole of what it said. The failures live in
/// `ChatStreamError`.
public enum ChatTurnCompletion: Hashable, Sendable {
    /// `stop_reason: "end_turn"` — the model finished on its own. The ordinary case.
    case endTurn

    /// `stop_reason: "max_tokens"` — the reply ran into this client's output cap.
    ///
    /// A completion rather than a failure, and the distinction is the point: unlike
    /// scoring, where a truncated answer is unusable (a cut-off JSON object is not a
    /// score), a chat answer cut off after four paragraphs is four usable paragraphs.
    /// The turn is real and can be stored; the UI is the thing that should say it was
    /// cut short.
    case truncated
}

/// One thing that happened while a chat reply was streaming (D10, FR-2.4).
///
/// ## The contract callers may rely on
///
/// 1. **Text arrives in order and is never retracted.** A `.text` event appends; it
///    never replaces or corrects anything already delivered.
/// 2. **Exactly one terminal event is emitted, and it is last.** Every stream ends
///    with either `.completed` or `.failed`, including streams that end badly — a
///    stream that simply stops without one is a bug in the decoder, not a state the
///    UI has to defend against.
/// 3. **Partial text survives a failure.** `.failed` after three `.text` events means
///    "those three are all there will be", not "discard them". This is a deliberate
///    decision and the reason failure is a *value* here rather than a thrown error: a
///    `for try await` loop with a `catch` makes dropping the partial reply the path of
///    least resistance, and half an answer plus "the connection dropped" is strictly
///    more useful to the athlete than an empty bubble.
///
/// ## What partial text is *not*
///
/// It is not a stored turn. `ChatThread` already says so — "a partially-received
/// assistant turn is transport state; only the completed turn is appended here" — and
/// this type keeps that true: a caller may render text from a `.failed` stream, but
/// only a `.completed` one produces a `ChatMessage` worth persisting (D6, MAX-050).
public enum ChatStreamEvent: Hashable, Sendable {
    /// More assistant text, to be appended to whatever has arrived already.
    case text(String)

    /// The API's `ping` — the connection is open and carrying nothing (MAX-152).
    ///
    /// Dropped by the decoder until this ticket, on the reasonable ground that it is not
    /// part of the answer. It is not part of the answer, but it is the only thing on the
    /// wire that distinguishes a reply that has gone quiet from one that is still
    /// arriving: silence looks identical to a caller either way, and a heartbeat is the
    /// transport saying which of the two this is. `ChatReplyProgress` is what turns some
    /// number of these into `ChatReplyPhase.stalled`; how many is a product decision and
    /// lives there, not here.
    ///
    /// Carries nothing. There is nothing in a ping worth carrying, and a heartbeat that
    /// carried a timestamp would invite a caller to do arithmetic on it.
    case heartbeat

    /// Terminal. The model finished; see `ChatTurnCompletion`.
    case completed(ChatTurnCompletion)

    /// Terminal. The turn did not finish; text already delivered still stands.
    case failed(ChatStreamError)

    /// Whether this event ends the stream.
    ///
    /// Lives here rather than in the app layer because it is a rule about the protocol,
    /// not about `URLSession`: the transport stops reading the socket the moment this
    /// is true, and a view stops its typing indicator on the same signal. One
    /// definition, checked by CI, used by both.
    public var isTerminal: Bool {
        switch self {
        case .text, .heartbeat:
            return false
        case .completed, .failed:
            return true
        }
    }
}
