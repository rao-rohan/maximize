import Foundation

/// Turns the lines of a server-sent-event stream into `ChatStreamEvent`s.
///
/// ## Why this is in the core
///
/// This is the half of MAX-024 that has decisions in it — what a frame means, which
/// deltas are the athlete's answer and which are not, when a turn is over, what a stop
/// reason implies — and CLAUDE.md's rule is that decisions live where CI can check
/// them. Written inside a `for try await line in bytes.lines` loop in the app layer,
/// every branch below would be reachable only from a device with a network and a key;
/// written here, all of it is a pure `String` in, `[ChatStreamEvent]` out.
///
/// The app layer keeps exactly what cannot move: opening the socket and handing over
/// the lines it produces.
///
/// ## The framing rules it implements
///
/// Server-sent events (the `text/event-stream` format the Messages API uses with
/// `"stream": true`) are line-oriented:
///
/// - A blank line ends a frame. Everything buffered is then one event.
/// - `data:` lines carry the payload; a frame with several is their contents joined by
///   newlines. The Messages API sends one single-line JSON object per frame today, but
///   the joining rule is the spec's and costs one line to honour, so a future
///   pretty-printed payload does not silently decode as garbage.
/// - A line starting with `:` is a comment — the keep-alive heartbeat — and means
///   nothing.
/// - Every other field, `event:` included, is ignored. The `event:` name duplicates the
///   `type` inside the JSON payload, and this decoder branches on the payload because
///   that is the value the API documents as authoritative.
///
/// ## What it deliberately drops
///
/// Only `text_delta`s become `.text`. `thinking_delta`, `signature_delta` and
/// `input_json_delta` are silently discarded, and so are `content_block_start` /
/// `content_block_stop` / `message_start`. Two reasons: they are not what the athlete
/// asked to read, and one of them must not be shown — a thinking delta is the model
/// reasoning out loud about this person's health data, and rendering it into a chat
/// bubble would put reasoning the product never promised on screen. An unknown frame
/// type is likewise ignored rather than treated as an error, so an API that grows a
/// new event type does not break a shipped build.
public struct ChatStreamDecoder {
    /// `data:` payloads seen since the last frame boundary.
    private var frameLines: [String] = []

    /// The stop reason from `message_delta`, held until `message_stop` closes the turn.
    private var stopReason: String?

    /// Set by the one terminal event this decoder will ever emit. Everything after it
    /// is ignored — see `ChatStreamEvent`'s "exactly one terminal event" contract,
    /// which this flag is what actually enforces.
    private var hasEmittedTerminal = false

    public init() {}

    /// Feeds one line from the stream, returning whatever it completes.
    ///
    /// Most lines complete nothing and return an empty array; that is the normal case,
    /// not a failure.
    public mutating func consume(_ line: String) -> [ChatStreamEvent] {
        guard !hasEmittedTerminal else { return [] }

        // The stream may use CRLF. Left on, a trailing carriage return would make
        // "data:" fail its prefix test and turn a whole reply into silence.
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if line.isEmpty {
            return completeFrame()
        }
        if line.hasPrefix(":") {
            return []
        }
        guard line.hasPrefix(Self.dataFieldName) else {
            // `event:`, `id:`, `retry:`, or a field this decoder has no use for.
            return []
        }

        // A new `data:` closes the buffered frame **only when that buffer is already a
        // complete JSON value**, which is what makes this independent of blank lines
        // without giving up multi-line `data:` fields.
        //
        // **This is MAX-107's fix.** SSE says a blank line ends an event, and the
        // original decoder trusted that exclusively — every test synthesised the blank
        // line itself, so the suite only ever saw an idealised stream. The real
        // transport does not guarantee one: `URLSession.AsyncBytes.lines` is a line
        // sequence, not an SSE parser, and a stream whose blank lines do not survive it
        // leaves every frame accumulating into one buffer. The joined payload is then
        // several JSON objects separated by newlines, which is not JSON at all, and the
        // whole turn dies as `unreadableResponse` — on every turn, for every model,
        // which is exactly the failure reported from the device.
        //
        // The completeness test is what distinguishes the two cases, and they are
        // genuinely different streams rather than a trade-off to pick between:
        //
        // - **One `data:` per event, blank lines lost.** The buffer holds a whole JSON
        //   object, so the next `data:` closes it. This is what the Messages API sends.
        // - **A multi-line `data:` field**, which SSE permits and `parts` of a payload
        //   split across lines. Each fragment alone is not valid JSON, so the buffer
        //   keeps accumulating and the blank line joins them, exactly as before.
        //
        // Blank-line completion is kept below regardless: it is what the format
        // specifies, and it is what closes the final frame of a well-behaved stream.
        var completed: [ChatStreamEvent] = []
        if bufferHoldsACompleteValue {
            completed = completeFrame()
            if hasEmittedTerminal { return completed }
        }

        var payload = String(line.dropFirst(Self.dataFieldName.count))
        // The format allows exactly one optional space after the colon, and it is not
        // part of the value.
        if payload.hasPrefix(" ") {
            payload.removeFirst()
        }
        frameLines.append(payload)
        return completed
    }

    /// Tells the decoder the connection ended, returning whatever that implies.
    ///
    /// Two things can still be outstanding. A frame may be buffered without its
    /// trailing blank line — the last frame of a response that closed promptly — and
    /// dropping it would lose a `message_stop`, turning a perfectly good turn into a
    /// spurious failure. And if no terminal event has been emitted by then, the
    /// connection ended mid-turn, which is `ChatStreamError.interrupted`.
    ///
    /// Callers must invoke this exactly once, after the last line, so that the
    /// "exactly one terminal event" contract holds for streams that die quietly.
    public mutating func finish() -> [ChatStreamEvent] {
        guard !hasEmittedTerminal else { return [] }
        var events = completeFrame()
        if !hasEmittedTerminal {
            hasEmittedTerminal = true
            events.append(.failed(.interrupted))
        }
        return events
    }

    // MARK: - Frames

    private static let dataFieldName = "data:"

    /// Whether what has been buffered so far is already a whole JSON value.
    ///
    /// The question a multi-line `data:` field and a lost blank line answer
    /// differently, and the only thing that tells them apart from inside the decoder:
    /// a fragment of a payload split across lines does not parse on its own, and a
    /// complete event does. Deliberately `JSONSerialization` rather than a `Frame`
    /// decode — `Frame`'s fields are all optional, so it would accept a fragment that
    /// merely happened to be object-shaped, and the point here is strict completeness.
    private var bufferHoldsACompleteValue: Bool {
        guard !frameLines.isEmpty,
              let data = frameLines.joined(separator: "\n").data(using: .utf8)
        else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private mutating func completeFrame() -> [ChatStreamEvent] {
        guard !frameLines.isEmpty else { return [] }
        let payload = frameLines.joined(separator: "\n")
        frameLines.removeAll()

        guard let data = payload.data(using: .utf8),
              let frame = try? JSONDecoder().decode(Frame.self, from: data)
        else {
            // A `data:` line that is not the documented JSON shape means this client
            // and the API disagree about the protocol. Failing loudly beats carrying
            // on and silently dropping half an answer.
            return terminal(.failed(.unreadableResponse))
        }

        // Coalesced rather than switched on as an optional: a frame with no `type` at
        // all is not one this decoder knows, which is exactly what `default` is for.
        switch frame.type ?? "" {
        case "content_block_delta":
            guard let delta = frame.delta, delta.type == "text_delta",
                  let text = delta.text, !text.isEmpty
            else {
                return []
            }
            return [.text(text)]

        case "message_delta":
            // Carries the stop reason but not the end of the turn; `message_stop` is
            // what actually closes it.
            if let reason = frame.delta?.stopReason {
                stopReason = reason
            }
            return []

        case "message_stop":
            return terminal(Self.outcome(forStopReason: stopReason))

        case "error":
            return terminal(.failed(Self.failure(forErrorType: frame.error?.type)))

        default:
            // `message_start`, `content_block_start`, `content_block_stop`, `ping`, and
            // anything the API adds later.
            return []
        }
    }

    private mutating func terminal(_ event: ChatStreamEvent) -> [ChatStreamEvent] {
        hasEmittedTerminal = true
        return [event]
    }

    /// Maps a `stop_reason` to the turn's outcome.
    ///
    /// A missing stop reason is treated as a normal end rather than an error: by the
    /// time `message_stop` arrives the text has already been delivered, and refusing to
    /// accept a turn the model plainly finished — because a field this client only uses
    /// for labelling was absent — would throw away a good answer over a formality.
    private static func outcome(forStopReason reason: String?) -> ChatStreamEvent {
        switch reason ?? "" {
        case "max_tokens":
            return .completed(.truncated)
        case "refusal":
            return .failed(.refused)
        default:
            // "end_turn", "stop_sequence" (this client sets none), nil, or a reason
            // added after this was written.
            return .completed(.endTurn)
        }
    }

    /// Maps the `type` of a mid-stream `error` event to this client's taxonomy.
    ///
    /// The API's error *type* is a fixed token from a documented set, and only the
    /// token is read — the accompanying `message` is free text written by the server
    /// and is never looked at, let alone carried into a `ChatStreamError`. See that
    /// type's "never carries a response body" rule.
    private static func failure(forErrorType type: String?) -> ChatStreamError {
        switch type ?? "" {
        case "rate_limit_error":
            return .rateLimited
        default:
            // `overloaded_error`, `api_error`, or anything else: transient by
            // construction, since a request the API considers invalid never reaches a
            // 200 and therefore never gets to stream an error at all.
            return .midStreamFailure
        }
    }

    /// The slice of the streaming wire format this decoder actually reads.
    ///
    /// Every field is optional because one struct decodes several frame shapes:
    /// `content_block_delta` carries `delta.type`/`delta.text`, `message_delta` carries
    /// `delta.stop_reason`, and `error` carries `error.type`. Modelling the union
    /// precisely would buy nothing — the `switch` above already branches on `type`, and
    /// a frame missing the field its type implies is handled there.
    private struct Frame: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, text
                case stopReason = "stop_reason"
            }
        }

        struct APIError: Decodable {
            /// The error's type token only. `message` is deliberately absent from this
            /// model, so there is no path by which server-written prose could reach a
            /// log or an error value.
            let type: String?
        }

        let type: String?
        let delta: Delta?
        let error: APIError?
    }
}
