import Foundation
import MaximizeCore

/// `ScoringModelInvoking` against the real Anthropic Messages API.
///
/// Thin and decision-free, per CLAUDE.md's "thin shell, fat core": every decision
/// about what to ask or whether an answer is acceptable belongs to `WorkoutScorer`
/// (`MaximizeCore`); this type's only job is turning a `ScoringInstruction` into an
/// HTTP request and turning the HTTP response back into a raw string, or into a
/// `ScoringModelError` when it cannot. It does not parse the reply as JSON, does not
/// look at `score` or `rationale`, and does not decide whether a workout is
/// scoreable — `ScoreProposal.parse` and `WorkoutScorer` own all of that.
///
/// Model: `claude-opus-5` (see `model` below) — no model is named in this ticket's
/// spec, so the project's current default applies.
///
/// **Not exercised by CI.** As with `KeychainAnthropicAPIKeyStore`, this repo has no
/// Swift toolchain, simulator, device, or API key locally, and CI never makes a
/// network request (see CLAUDE.md, "What CI can and cannot prove"). Every branch
/// below is reviewed, not run — `FakeScoringModelInvoking` (`MaximizeCoreTestSupport`)
/// is what actually exercises `WorkoutScorer` against this protocol in tests.
///
/// `@unchecked Sendable`: every stored property is an immutable `let` set at `init`
/// and never mutated afterward, the same shape as `HealthKitWorkoutFetcher` and
/// `HealthKitWorkoutSampleFetcher` in this directory — there is no shared mutable
/// state for the compiler's stricter checking to actually be protecting.
final class AnthropicScoringModelClient: ScoringModelInvoking, @unchecked Sendable {
    /// The model this client asks. A fixed literal rather than something read from
    /// settings or plan data: D1 versions the *scoring rubric*, not which model
    /// executes it, and swift build fails loudly if this string is ever mistyped.
    static let model = "claude-opus-5"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    /// Generous headroom for a reply that, on the happy path, is a JSON object
    /// containing an integer and a sentence under
    /// `RationaleContract.maximumCharacters`. Not tuned down further: a reply that
    /// legitimately needs more than this is the client's problem to fix (see
    /// `ScoringModelError.truncated`), and 512 tokens costs very little even when
    /// entirely unused.
    private static let maxTokens = 512

    private let keyStore: AnthropicAPIKeyStoring
    private let session: URLSession

    /// Wall-clock budget for the whole request, including any retries the
    /// `URLSession` configuration performs internally. Not a fixed constant on this
    /// type: a caller invoked from a background HealthKit wake has a short,
    /// unspecified budget (tracker R8) and must not assume a foreground's patience,
    /// while an interactive rescore from a view can afford to wait longer. The
    /// caller states its own budget; this type only enforces whichever one it is
    /// given.
    private let timeout: TimeInterval

    init(
        keyStore: AnthropicAPIKeyStoring,
        session: URLSession = .shared,
        timeout: TimeInterval = 20
    ) {
        self.keyStore = keyStore
        self.session = session
        self.timeout = timeout
    }

    func reply(to instruction: ScoringInstruction) async throws -> String {
        // `retrieve()` can also throw `AnthropicAPIKeyError` (a corrupt Keychain
        // item) — deliberately left unwrapped rather than folded into
        // `ScoringModelError`. That is a different failure from "no key was ever
        // stored", and collapsing the two would hide a Keychain-integrity problem
        // behind the same "go add a key" message a first launch gets.
        guard let key = try keyStore.retrieve() else {
            throw ScoringModelError.noAPIKeyStored
        }

        let request = try Self.makeRequest(for: instruction, key: key, timeout: timeout)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ScoringModelError.timedOut
        } catch {
            // Every other transport-level failure (offline, DNS, a dropped
            // connection, a cancelled task) collapses to one case: none of them are
            // this client's fault, and none of them mean anything different to a
            // caller deciding whether to retry.
            throw ScoringModelError.requestFailed
        }

        guard let http = response as? HTTPURLResponse else {
            throw ScoringModelError.unreadableResponse
        }
        try Self.checkStatus(http.statusCode)

        return try Self.text(from: data)
    }

    // MARK: - Request

    private static func makeRequest(
        for instruction: ScoringInstruction,
        key: AnthropicAPIKey,
        timeout: TimeInterval
    ) throws -> URLRequest {
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
            // `instruction.task` is identical for every workout (see
            // `ScoringInstruction`'s documentation) — sent as a cacheable system
            // block for exactly the reason that type's doc comment states. Today's
            // task text is short enough that it may fall under Claude Opus 5's
            // 512-token cacheable minimum, in which case this is a harmless no-op;
            // if the task text ever grows, caching starts working with no further
            // change here.
            system: [RequestBody.SystemBlock(text: instruction.task)],
            // Disabled deliberately, for latency: §11 asks for scoring within
            // seconds of ingestion, and a background wake's budget is short and
            // unspecified (tracker R8) — thinking adds generation time this call
            // cannot spare for a task that is "pick a number in a range and write
            // one sentence", not open-ended reasoning. This call makes no tool
            // calls, so the failure mode of disabled thinking on Claude Opus 5 that
            // matters here is a reply with stray formatting around the JSON; that
            // already surfaces as `ScoringError.malformedResponse`, which
            // `WorkoutScorer` already treats as worth retrying.
            thinking: RequestBody.Thinking(),
            messages: [RequestBody.Message(content: instruction.subject)]
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
            let role = "user"
            let content: String
        }

        let model: String
        let maxTokens: Int
        let system: [SystemBlock]
        let thinking: Thinking
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, system, thinking, messages
            case maxTokens = "max_tokens"
        }
    }

    // MARK: - Response

    private static func checkStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401:
            throw ScoringModelError.invalidAPIKey
        case 429:
            throw ScoringModelError.rateLimited
        case 500...599:
            throw ScoringModelError.serverUnavailable(statusCode: statusCode)
        default:
            throw ScoringModelError.unexpectedStatus(statusCode)
        }
    }

    private static func text(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw ScoringModelError.unreadableResponse
        }

        // Checked before `content` is read at all, and in this order: a refusal can
        // carry an empty `content` array, and reading it unconditionally is exactly
        // the pitfall the Anthropic API's own documentation warns about — always
        // check `stop_reason` first.
        if decoded.stopReason == "refusal" {
            throw ScoringModelError.refused
        }
        if decoded.stopReason == "max_tokens" {
            throw ScoringModelError.truncated
        }

        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty
        else {
            throw ScoringModelError.unreadableResponse
        }
        return text
    }

    /// The slice of the Messages API response shape this client actually reads.
    /// Deliberately not a full model of the response — every other field (`id`,
    /// `model`, `usage`, …) is either unneeded here or would belong to a caller
    /// that wants it, and this type does not parse the reply's *content* at all
    /// (see the type doc comment).
    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentBlock]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }
}
