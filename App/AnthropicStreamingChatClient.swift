import Foundation
import MaximizeCore

/// `StreamingChatModelInvoking` against the real Anthropic Messages API, in streaming
/// mode (D10, FR-2.4).
///
/// The sibling of `AnthropicScoringModelClient`, and thin in the same way: it turns a
/// `ChatInstruction` into an HTTP request, hands the response's lines to
/// `ChatStreamDecoder` (`MaximizeCore`), and forwards whatever that decoder makes of
/// them. It does not decide what a frame means, when a turn is over, or what a stop
/// reason implies — every one of those decisions lives in the core, where CI checks
/// it. What is left here is the part that genuinely cannot move: opening a socket.
///
/// It also does not decide what Claude is told. `instruction.factSheet` is MAX-014's
/// output, passed through untouched (D3); nothing in this file reads a workout, and
/// there is no prompt text in it to read.
///
/// Model: `claude-opus-5`, matching `AnthropicScoringModelClient`.
///
/// **Not exercised by CI.** As with the scoring client and the Keychain store, this
/// repo has no Swift toolchain, simulator, device or API key locally, and CI never
/// makes a network request (CLAUDE.md, "What CI can and cannot prove"). Every branch
/// below is reviewed, not run — `FakeStreamingChatModelInvoking`
/// (`MaximizeCoreTestSupport`) is what actually exercises callers against this
/// protocol, and `ChatStreamDecoderTests` is what exercises the parsing this file
/// delegates to.
///
/// **It logs nothing, deliberately.** Every byte flowing through here is either the
/// key, the athlete's fact sheet, or Claude talking about the athlete's runs — health
/// data by CLAUDE.md's definition, which rules it out of logs without qualification.
/// Rather than reason case-by-case about which interpolation is safe, this file has no
/// logger at all; the failure taxonomy (`ChatStreamError`) is the diagnostic, and it
/// reaches the screen where the person who can act on it is.
///
/// `@unchecked Sendable`: every stored property is an immutable `let` set at `init`
/// and never mutated afterward, the same shape as `AnthropicScoringModelClient` and
/// the HealthKit adapters in this directory — there is no shared mutable state for the
/// compiler's stricter checking to be protecting.
final class AnthropicStreamingChatClient: StreamingChatModelInvoking, @unchecked Sendable {
    /// A fixed literal rather than something read from settings or plan data: D1
    /// versions the scoring rubric, not which model the app talks to, and `swift build`
    /// fails loudly if this string is ever mistyped.
    static let model = "claude-opus-5"

    /// Fixed and hardcoded — never derived from user input, plan data or a server
    /// response, so there is no surface here for redirecting a request carrying health
    /// data somewhere it should not go.
    ///
    /// Held as a string and parsed at call time rather than as a force-unwrapped `URL`,
    /// for the reason `AnthropicScoringModelClient` documents at length: CLAUDE.md's
    /// ban on force unwraps is written without a "unless it is provably safe"
    /// exception, and a security review rejected `URL(string:)!` in that exact file.
    private static let endpointURLString = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"

    /// Output cap for one chat turn. Generous for an answer to a question about a
    /// single run, and small enough that a runaway reply cannot bill indefinitely.
    /// Hitting it is not a failure here — the decoder reports it as
    /// `ChatTurnCompletion.truncated`, and four usable paragraphs are still four usable
    /// paragraphs.
    private static let maxTokens = 2048

    private let keyStore: AnthropicAPIKeyStoring
    private let session: URLSession

    /// Budget for a *stall*, not for the whole turn.
    ///
    /// `URLRequest.timeoutInterval` on a streaming response is an inactivity timer: it
    /// resets as data arrives, so a long answer that keeps producing tokens is never
    /// cut off, and only a connection that has genuinely stopped talking trips it. That
    /// is the right shape for FR-2.4 — §11 asks for a first token within seconds, and
    /// a turn that takes a while after that is working, not stuck.
    ///
    /// Which failure it produces depends on when it fires: before the response begins
    /// it is `ChatStreamError.timedOut`; after tokens have started arriving it lands in
    /// the read loop and is reported as `interrupted`, because by then there is text on
    /// screen that has to survive (see that case's documentation).
    private let idleTimeout: TimeInterval

    init(
        keyStore: AnthropicAPIKeyStoring,
        session: URLSession = .shared,
        idleTimeout: TimeInterval = 60
    ) {
        self.keyStore = keyStore
        self.session = session
        self.idleTimeout = idleTimeout
    }

    func stream(_ instruction: ChatInstruction) -> AsyncStream<ChatStreamEvent> {
        AsyncStream { continuation in
            let work = Task { [self] in
                await deliver(instruction, to: continuation)
                continuation.finish()
            }
            // The consumer walking away — a view dismissed mid-answer — cancels the
            // request rather than leaving it streaming tokens nobody will read.
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - Delivery

    private func deliver(
        _ instruction: ChatInstruction,
        to continuation: AsyncStream<ChatStreamEvent>.Continuation
    ) async {
        let key: AnthropicAPIKey
        do {
            guard let stored = try keyStore.retrieve() else {
                // The app's ordinary state the day it is installed, not an error to
                // crash on and not something to retry into forever.
                continuation.yield(.failed(.noAPIKeyStored))
                return
            }
            key = stored
        } catch {
            // A corrupt Keychain item. Kept distinct from "no key stored" on purpose —
            // see `ChatStreamError.keyStoreUnavailable`. The caught error is never
            // inspected or interpolated anywhere: `AnthropicAPIKeyError` carries an
            // adapter-supplied status description, and this file logs nothing.
            continuation.yield(.failed(.keyStoreUnavailable))
            return
        }

        let request: URLRequest
        do {
            request = try Self.makeRequest(for: instruction, key: key, timeout: idleTimeout)
        } catch {
            // Unreachable for a compile-time endpoint and an all-`String` body.
            // Surfaced as a first-class failure rather than a force unwrap so it cannot
            // become a crash in a chat view.
            continuation.yield(.failed(.requestFailed))
            return
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError where error.code == .timedOut {
            continuation.yield(.failed(.timedOut))
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            // Offline, DNS, a refused connection: none of them are this client's fault
            // and none mean anything different to a caller deciding whether to retry.
            continuation.yield(.failed(.requestFailed))
            return
        }

        guard let http = response as? HTTPURLResponse else {
            continuation.yield(.failed(.unreadableResponse))
            return
        }
        if let failure = Self.failure(forStatusCode: http.statusCode) {
            // The body of a non-2xx response is a JSON error object. It is not read:
            // status codes are safe to carry, server prose is not.
            continuation.yield(.failed(failure))
            return
        }

        var decoder = ChatStreamDecoder()
        do {
            for try await line in bytes.lines {
                for event in decoder.consume(line) {
                    continuation.yield(event)
                    if event.isTerminal {
                        // Nothing after the terminal event matters, and dropping
                        // `bytes` here tears the connection down.
                        return
                    }
                }
            }
        } catch let error as URLError where error.code == .cancelled {
            // The consumer cancelled. Nothing failed, so nothing is reported — a
            // terminal event here would make a dismissed view look like a broken one.
            return
        } catch is CancellationError {
            return
        } catch {
            // The socket dropped part-way through the answer, including on a stall
            // (`URLError.timedOut`). Either way the decoder has the last word on what
            // that means for the turn, and it says `interrupted` — text already
            // delivered stands.
            emit(decoder.finish(), to: continuation)
            return
        }

        // The stream ended cleanly. Usually that is a `message_stop` already handled
        // above; if it is not, `finish()` supplies the missing terminal event so the
        // "exactly one terminal event" contract holds either way.
        emit(decoder.finish(), to: continuation)
    }

    private func emit(
        _ events: [ChatStreamEvent],
        to continuation: AsyncStream<ChatStreamEvent>.Continuation
    ) {
        for event in events {
            continuation.yield(event)
        }
    }

    // MARK: - Request

    private enum RequestConstructionFailure: Error {
        case unbuildableEndpoint
    }

    private static func makeRequest(
        for instruction: ChatInstruction,
        key: AnthropicAPIKey,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let endpoint = URL(string: endpointURLString) else {
            throw RequestConstructionFailure.unbuildableEndpoint
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        // `.revealed()` is the one place this client is allowed to see the raw key
        // value, and it goes straight into a request header — never into a log
        // statement, an error, or anything else in this file. See
        // `AnthropicAPIKey.revealed()`'s own documentation.
        request.setValue(key.revealed(), forHTTPHeaderField: "x-api-key")

        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            // Two cacheable system blocks, in stability order, which is the whole
            // reason `ChatInstruction` splits them. A breakpoint caches everything
            // before it, so the first covers the task text — identical for every chat
            // turn in the app — and the second covers task + fact sheet, identical for
            // every turn of one workout's thread (D6). A five-message conversation
            // therefore re-sends the run's facts four times at cache-read price instead
            // of full price. As with the scoring client, today's text may fall under
            // the model's cacheable minimum, in which case this is a harmless no-op
            // that starts working if the text grows.
            system: [
                RequestBody.SystemBlock(text: instruction.task),
                RequestBody.SystemBlock(text: instruction.factSheet),
            ],
            // Disabled deliberately, and the reason is this ticket's requirement rather
            // than a preference. D10 asks for a token-by-token reveal and §11 asks for
            // a first token within seconds; on this model thinking is on by default and
            // its content is not returned, so an adaptive turn shows the athlete a
            // silent pause of unknown length and *then* text. That is the one shape
            // FR-2.4 rules out.
            //
            // Two consequences a later ticket must not trip over. Disabling thinking is
            // only accepted at effort `high` or below, and this request sends no effort
            // (so: the default, `high`) — adding `xhigh` or `max` here without removing
            // this line is a 400. And with thinking off the model can occasionally emit
            // an internal XML tag into its visible answer; the fix for that is a line in
            // the prompt, which belongs to whoever owns `instruction.task`, not here —
            // this file does not write prompt text.
            thinking: RequestBody.Thinking(),
            messages: instruction.turns.map {
                RequestBody.Message(role: $0.speaker.rawValue, content: $0.text)
            }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private struct RequestBody: Encodable {
        struct SystemBlock: Encodable {
            let type = "text"
            let text: String
            let cacheControl = CacheControl()

            struct CacheControl: Encodable {
                let type = "ephemeral"
            }

            enum CodingKeys: String, CodingKey {
                case type, text
                case cacheControl = "cache_control"
            }
        }

        struct Thinking: Encodable {
            let type = "disabled"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let maxTokens: Int
        /// The whole point of this client. Without it the API answers with one JSON
        /// object and D10 is not satisfied.
        let stream = true
        let system: [SystemBlock]
        let thinking: Thinking
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, stream, system, thinking, messages
            case maxTokens = "max_tokens"
        }
    }

    // MARK: - Response

    /// The failure a status code implies, or nil when the stream may proceed.
    ///
    /// Same mapping as `AnthropicScoringModelClient.checkStatus`, expressed as a value
    /// rather than a throw because nothing in this file throws at its caller.
    private static func failure(forStatusCode statusCode: Int) -> ChatStreamError? {
        switch statusCode {
        case 200..<300:
            return nil
        case 401:
            return .invalidAPIKey
        case 429:
            return .rateLimited
        case 500...599:
            return .serverUnavailable(statusCode: statusCode)
        default:
            return .unexpectedStatus(statusCode)
        }
    }
}
