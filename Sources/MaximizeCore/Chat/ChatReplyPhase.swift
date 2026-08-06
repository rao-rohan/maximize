import Foundation

/// Where one chat reply stands, between the athlete pressing send and the answer being
/// whole (MAX-152, FR-2.4).
///
/// ## Why this is a core type rather than three booleans in a view
///
/// Before this ticket the surface had exactly one bit — `ChatModel.isStreaming` — and it
/// was asked to mean three different things at once: "the request is in flight and
/// nothing has come back", "text is arriving", and "text stopped arriving but the
/// connection is still open". A view cannot tell those apart from a bit and a string, so
/// it did the only thing available and drew an ellipsis in a bubble for all of them. The
/// three are different facts about the same request, an athlete reads them differently
/// ("is it thinking, is it typing, is it stuck"), and CLAUDE.md's central rule says a
/// fact the app knows is decided where CI can check it. So the ladder is a closed enum
/// here, `ChatReplyProgress` below is the only thing that moves between its rungs, and
/// the view renders whichever rung it is handed without inspecting a single stream
/// event.
///
/// ## The rungs
///
/// 1. `.awaitingFirstToken` — the true waiting state, and the only one that gets an
///    indicator. Nothing has been said yet, so there is nothing to read.
/// 2. `.streaming` — the first token has landed. Waiting is *over*: the indicator gives
///    way to the words rather than sitting beside them, which is why no phase means
///    "waiting and streaming at once."
/// 3. `.stalled` — the transport says the connection is open and the model is not
///    speaking. Distinct from both of the above, and see `ChatReplyProgress` for the
///    signal that distinguishes it.
/// 4. `.complete` / `.truncated` / `.emptyReply` / `.failed` — the four ways a reply
///    stops. Each is a designed state with its own words; none of them is a blank.
public enum ChatReplyPhase: Hashable, Sendable {

    /// No reply has been asked for, or the last one has been read and cleared by a
    /// reload. The resting state of the surface.
    case idle

    /// The request is open and not one token has arrived. The waiting state.
    case awaitingFirstToken

    /// Text is arriving. There is something on screen to read.
    case streaming

    /// Text has stopped arriving and the connection is still open — not finished, not
    /// dropped. The state that was previously indistinguishable from `.streaming`,
    /// which is how a stalled reply came to look exactly like a working one.
    case stalled

    /// `stop_reason: "end_turn"` — the model finished and the whole reply is on screen.
    case complete

    /// `stop_reason: "max_tokens"` — a real reply that ran out of room. Still stored,
    /// still usable; the surface says it was cut short
    /// (`ChatConversationCopy.truncatedCaption`).
    case truncated

    /// The stream ended normally having produced nothing usable. Not a transport
    /// failure — the request worked — and not a complete reply either, so it is neither
    /// of those cases rather than being folded into whichever one is nearer.
    case emptyReply

    /// The turn did not finish. Carries the failure so the surface can say which one it
    /// was and whether asking again is worth it — see `ChatFailureNotice`, the single
    /// place a `ChatStreamError` becomes words.
    case failed(ChatStreamError)

    /// Whether a request is open: something is expected, and `canSend` is therefore
    /// false. True for exactly the first three rungs.
    ///
    /// This is what `ChatModel.isStreaming` is defined as, so there is one answer to
    /// "is a reply in flight" rather than a stored flag that can disagree with the phase.
    public var isLive: Bool {
        switch self {
        case .awaitingFirstToken, .streaming, .stalled:
            return true
        case .idle, .complete, .truncated, .emptyReply, .failed:
            return false
        }
    }

    /// Whether the reply has stopped for good, one way or another.
    public var isTerminal: Bool {
        switch self {
        case .complete, .truncated, .emptyReply, .failed:
            return true
        case .idle, .awaitingFirstToken, .streaming, .stalled:
            return false
        }
    }

    /// Whether asking the same question again could plausibly produce a better outcome.
    ///
    /// Reads `ChatStreamError.isWorthRetrying` rather than re-deciding it — that type
    /// already owns the transient/permanent split and documents every case. An empty
    /// reply is retryable for the same reason `.midStreamFailure` is: nothing about the
    /// question caused it.
    ///
    /// **Nothing in this app acts on this by itself.** It gates an affordance the athlete
    /// taps; see `ChatModel.retry()` and this file's retry note below.
    public var offersRetry: Bool {
        switch self {
        case let .failed(error):
            return error.isWorthRetrying
        case .emptyReply:
            return true
        case .idle, .awaitingFirstToken, .streaming, .stalled, .complete, .truncated:
            return false
        }
    }
}

/// Something that happened to a reply in flight, in the vocabulary of the ladder rather
/// than of the wire.
///
/// Deliberately not `ChatStreamEvent`. That type is the transport's contract — what a
/// frame meant — and this one is the product's: `.heartbeat` is a wire fact, "the
/// connection is alive and nothing is being said" is the product fact, and the mapping
/// between them is a decision (how many quiet beats is a stall) that belongs under test.
public enum ChatReplyEvent: Hashable, Sendable {

    /// `send()` (or `retry()`) opened a request. Always restarts the ladder at the
    /// bottom, from whatever rung it was on.
    case requestOpened

    /// A `ChatStreamEvent.text` delta arrived.
    case textArrived

    /// A `ChatStreamEvent.heartbeat` arrived — the API's own `ping`, meaning the
    /// connection is open and carrying nothing.
    case heartbeat

    /// The stream ended normally. `ChatTurnCompletion` says which normal ending.
    case completed(ChatTurnCompletion)

    /// The stream ended normally but produced no text this app could use — an empty
    /// reply, or one that is entirely whitespace. Sent by `ChatModel` rather than
    /// derived here, because "usable" means "storable as a `ChatMessage`", which is the
    /// caller's question and not this machine's.
    case producedNoUsableText

    /// The stream ended with `ChatStreamEvent.failed`.
    case failed(ChatStreamError)

    /// The stream stopped without a terminal event at all. Forbidden by
    /// `ChatStreamEvent`'s contract and handled anyway, because nothing in the type
    /// system enforces that contract on this side of the seam.
    case endedWithoutTerminalEvent
}

/// The ladder's only mover: fold a `ChatReplyEvent` into a `ChatReplyPhase`.
///
/// A value type with one property and one method, so the whole state machine is a pure
/// function CI runs in microseconds — no clock, no task, no simulator.
///
/// ## How a stall is detected, and why not with a timer
///
/// The Messages API sends `ping` events on an open stream. A `ping` is the transport
/// saying, in its own words, "I am still here and I have nothing for you" — which is
/// precisely the fact that separates a stalled reply from a working one, and it arrives
/// as an event rather than having to be inferred from elapsed time.
///
/// A wall-clock watchdog was the obvious alternative and was rejected. It would put the
/// decision behind a `Task.sleep` racing a stream, which is the one shape this repo's
/// CI cannot verify honestly: a test either sleeps (slow, flaky) or injects a fake clock
/// and proves only that the fake was called. CLAUDE.md's rule is that the decision lives
/// where the robots check it, and `heartbeatsBeforeStall` is checkable to the beat.
///
/// **The cost is stated rather than hidden**: a connection that hangs and sends no pings
/// at all stays `.streaming` until the client's own idle timeout turns it into
/// `.failed(.interrupted)` (`AnthropicStreamingChatClient.idleTimeout`, 60s). That is
/// still an honest label — nothing has told the app the stream went quiet — and the
/// terminal state it lands in is a designed one. Whether real pings arrive during a real
/// stall is a device question, and it is in the PR.
public struct ChatReplyProgress: Hashable, Sendable {

    /// Quiet beats, with no text between them, before the reply is called stalled.
    ///
    /// Two rather than one, because the API is documented as free to send a `ping` at
    /// any time — including in the middle of a perfectly healthy reply, between two text
    /// deltas. One beat would therefore flag a working stream as stalled; two in a row
    /// with no token between them will not happen to a stream that is producing text.
    ///
    /// Public so a test asserts the policy by name rather than by counting to two.
    public static let heartbeatsBeforeStall = 2

    public private(set) var phase: ChatReplyPhase = .idle

    /// Beats since the last token. Reset by every `.textArrived`, which is what makes
    /// the threshold mean "consecutive" rather than "cumulative over the turn".
    private var quietBeats = 0

    public init() {}

    public mutating func apply(_ event: ChatReplyEvent) {
        switch event {
        case .requestOpened:
            // From any rung, including a terminal one: a retry is a new request, and it
            // starts at the bottom of the ladder like every other.
            quietBeats = 0
            phase = .awaitingFirstToken

        case .textArrived:
            quietBeats = 0
            // Text outside an open request is not a state this machine invents. It
            // cannot happen through `ChatModel`, which only feeds events from a stream
            // it opened, and is ignored rather than trusted.
            guard phase.isLive else { return }
            phase = .streaming

        case .heartbeat:
            guard phase.isLive else { return }
            quietBeats += 1
            // A beat while still waiting for the first token leaves the phase alone, on
            // purpose. "The model has not started speaking" is what `.awaitingFirstToken`
            // already says truthfully, and calling that a stall would invent a fault out
            // of a model that is simply thinking — the state the shimmer exists for.
            // A stall is specifically a reply that started and stopped.
            guard phase == .streaming || phase == .stalled else { return }
            if quietBeats >= Self.heartbeatsBeforeStall {
                phase = .stalled
            }

        case let .completed(completion):
            guard phase.isLive else { return }
            // A stream that completes without ever having delivered a token cannot be a
            // complete reply, whatever its stop reason said. `ChatModel` reaches the same
            // conclusion from the text it holds and sends `.producedNoUsableText`; this
            // is the same answer derived from this machine's own history, so the two
            // cannot disagree.
            guard phase != .awaitingFirstToken else {
                phase = .emptyReply
                return
            }
            phase = completion == .truncated ? .truncated : .complete

        case .producedNoUsableText:
            guard phase.isLive else { return }
            phase = .emptyReply

        case let .failed(error):
            guard phase.isLive else { return }
            phase = .failed(error)

        case .endedWithoutTerminalEvent:
            guard phase.isLive else { return }
            // `ChatStreamError.interrupted` is exactly this situation named — "the
            // connection ended before the turn did" — so it is reused rather than given
            // a parallel case that would need its own sentence saying the same thing.
            phase = .failed(.interrupted)
        }
    }

    /// Puts the ladder back to `.idle` — what a reload does, since a phase describes a
    /// request and a reload has abandoned the one it described.
    public mutating func reset() {
        self = ChatReplyProgress()
    }
}
