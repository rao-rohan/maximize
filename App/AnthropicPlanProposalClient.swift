import Foundation
import MaximizeCore

/// `PlanProposalModelInvoking` against the real Anthropic Messages API
/// (CHAT-FIRST-SPEC.md §4.7, Phase A).
///
/// The sibling of `AnthropicScoringModelClient`, thin in the same way: it turns a
/// `PlanProposalInstruction` into an HTTP request and turns the HTTP response back
/// into a raw string, or into a `PlanProposalModelError` when it cannot. It does not
/// parse the reply as JSON, does not look at any field of the plan the model
/// proposed, and does not decide whether that plan is any good — `PlanProposal.parse`
/// owns all of that.
///
/// **Non-streaming**, per `PlanProposalModelInvoking`'s own documentation: a proposal
/// is reviewed as a whole, as a card (§4.6), not read as it arrives, so there is
/// nothing here for D10's token-by-token requirement to apply to — that requirement
/// is chat's (`AnthropicStreamingChatClient`), not this call's.
///
/// **No prompt text in this file.** Every word sent belongs to `PlanProposalInstruction`
/// — `task`, `schema`, `factSheet` — and to `ChatTurn`. This file only carries them to
/// the wire.
///
/// Model: `claude-sonnet-5` at `medium` effort — the same tier `AnthropicScoringModelClient`
/// and `AnthropicStreamingChatClient` run, per the owner's cost instruction (§8.3). A plan
/// proposal is a larger, more structured output than either of those calls, and §8.3
/// considered stepping the tier up for exactly that reason — but decided against it,
/// because a proposal is reviewed field by field before anything is stored (§4), which is
/// the strongest possible check on a weaker answer. Ship it at the same tier.
///
/// **Not exercised by CI.** As with the scoring and chat clients, this repo has no Swift
/// toolchain, simulator, device, or API key locally, and CI never makes a network request
/// (see CLAUDE.md, "What CI can and cannot prove"). Every branch below is reviewed, not
/// run — `FakePlanProposalModelInvoking` (`MaximizeCoreTestSupport`) is what actually
/// exercises a caller against this protocol in tests.
///
/// `@unchecked Sendable`: every stored property is an immutable `let` set at `init` and
/// never mutated afterward, the same shape as `AnthropicScoringModelClient` and
/// `AnthropicStreamingChatClient` in this directory — there is no shared mutable state for
/// the compiler's stricter checking to actually be protecting.
final class AnthropicPlanProposalClient: PlanProposalModelInvoking, @unchecked Sendable {
    /// The model this client asks. A fixed literal rather than something read from
    /// settings or plan data, for the reason `AnthropicScoringModelClient.model`
    /// documents: `swift build` fails loudly if this string is ever mistyped, and D1
    /// versions the plan's *rubric and thresholds*, not which model drafted a proposal
    /// of them.
    static let model = "claude-sonnet-5"

    /// Fixed and hardcoded — never derived from user input, plan data or a server
    /// response, so there is no surface here for redirecting a request carrying health
    /// data somewhere it should not go.
    ///
    /// Held as a string and parsed at call time rather than as a force-unwrapped `URL`,
    /// for the reason `AnthropicScoringModelClient` documents at length: CLAUDE.md's ban
    /// on force unwraps is written without a "unless it is provably safe" exception, and
    /// a security review rejected `URL(string:)!` in that exact sibling file.
    private static let endpointURLString = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"

    /// Sized against a full proposal's JSON, not a chat turn's prose (§4.3): a
    /// heart-rate cap and two cadence bounds, two score thresholds, seven weekday
    /// entries each carrying a kind, an optional distance and an optional note, an
    /// up-to-sixteen-week long-run arc of index/distance pairs, and a handful of goal
    /// statements. Estimating generously per field — a weekday entry with a
    /// substantial coaching note runs to a few hundred characters, sixteen arc weeks
    /// are compact but add up, and goals can run to a few sentences each — the whole
    /// object comfortably fits inside a couple of thousand output tokens even with
    /// verbose formatting. `maxTokens` below is set with headroom well past that
    /// estimate, for the same reason `AnthropicScoringModelClient.maxTokens` is not
    /// tuned down to its expected reply size: a proposal that legitimately needs more
    /// than this is the client's problem to fix (`PlanProposalModelError.truncated`),
    /// and the ticket that sizes this call names its own hazard plainly — **a
    /// truncated proposal is worse than a failed one**, because `PlanProposal.parse`'s
    /// envelope check (`{` … `}`) can still pass on a reply that is missing whatever
    /// field came last, producing a proposal that looks parsed but is silently wrong
    /// rather than a call that visibly failed. Sized well clear of that edge rather
    /// than tight against it.
    private static let maxTokens = 4096

    private let keyStore: AnthropicAPIKeyStoring
    private let session: URLSession

    /// Wall-clock budget for the whole request. Unlike `AnthropicStreamingChatClient`'s
    /// `idleTimeout` — an inactivity timer that resets as tokens stream in — this call
    /// is non-streaming, so the *entire* generation has to land inside this window
    /// before anything is returned at all. Set higher than
    /// `AnthropicScoringModelClient`'s 20-second default for exactly that reason: a
    /// proposal generates substantially more output than a score's integer and a
    /// sentence, and there is no partial progress to lean on while it does. Not a
    /// fixed constant on this type regardless — the caller states its own budget, as
    /// `AnthropicScoringModelClient.timeout` explains, and this call is initiated by
    /// an athlete's tap (§4.7, A14), which can reasonably wait somewhat longer than an
    /// unattended background wake could.
    private let timeout: TimeInterval

    init(
        keyStore: AnthropicAPIKeyStoring,
        session: URLSession = .shared,
        timeout: TimeInterval = 45
    ) {
        self.keyStore = keyStore
        self.session = session
        self.timeout = timeout
    }

    func reply(to instruction: PlanProposalInstruction) async throws -> String {
        // `retrieve()` can also throw `AnthropicAPIKeyError` (a corrupt Keychain
        // item) — deliberately left unwrapped rather than folded into
        // `PlanProposalModelError`, for the same reason `AnthropicScoringModelClient`
        // leaves it unwrapped: that is a different failure from "no key was ever
        // stored", and collapsing the two would hide a Keychain-integrity problem
        // behind the same "go add a key" message a first launch gets.
        guard let key = try keyStore.retrieve() else {
            throw PlanProposalModelError.noAPIKeyStored
        }

        let request = try Self.makeRequest(for: instruction, key: key, timeout: timeout)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw PlanProposalModelError.timedOut
        } catch {
            // Every other transport-level failure (offline, DNS, a dropped
            // connection, a cancelled task) collapses to one case: none of them are
            // this client's fault, and none of them mean anything different to a
            // caller deciding whether to retry.
            throw PlanProposalModelError.requestFailed
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlanProposalModelError.unreadableResponse
        }
        try Self.checkStatus(http.statusCode)

        return try Self.text(from: data)
    }

    // MARK: - Request

    private static func makeRequest(
        for instruction: PlanProposalInstruction,
        key: AnthropicAPIKey,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let endpoint = URL(string: endpointURLString) else {
            // Unreachable for a compile-time constant. Surfaced as an error rather than
            // a force unwrap so it cannot become a crash on an athlete's tap.
            throw PlanProposalModelError.requestFailed
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
            // Three cacheable system blocks, in stability order — the four-way split
            // `PlanProposalInstruction` documents, minus `turns`, which is never
            // stable. A breakpoint caches everything before it, so in order:
            //   1. `task` — identical for every first-attempt proposal in the app.
            //   2. `schema` — `PlanProposal.schemaDescription`, identical for every
            //      proposal regardless of athlete.
            //   3. `factSheet` — the only block that carries PII, and the only one
            //      that varies per athlete.
            // As with the scoring and chat clients, text under this tier's
            // 1024-token cacheable minimum simply creates no cache entry — no error,
            // no benefit. Unlike those two clients' system blocks, `task` and
            // `schema` combined are the first system-block prefix in the app with a
            // real chance of crossing that minimum on their own, independent of the
            // fact sheet: `PlanProposalInstruction.taskDescription` and
            // `PlanProposal.schemaDescription` are both substantially longer prose
            // than `ScoringInstruction.task`, because a plan's schema — seven
            // weekday session shapes, a long-run arc, goal statements, and the
            // vocabulary each field accepts — is a much larger contract to state
            // than a scoring rubric. Whether it actually crosses 1024 tokens can only
            // be confirmed with `count_tokens` against the real model (§8.2's own
            // caveat); this comment states the expectation, not a measurement no
            // test in this repo can make.
            system: Self.systemBlocks(for: instruction),
            // Disabled deliberately, matching both sibling clients: `medium` effort
            // is ample for filling in a fixed schema from a conversation and a fact
            // sheet already assembled by the core (D3), and disabling is what lets
            // this call sit at `medium` at all — see `outputConfig`'s trap below.
            thinking: RequestBody.Thinking(),
            // The athlete's cost lever, matching `AnthropicScoringModelClient` and
            // `AnthropicStreamingChatClient` (§8.3). Disabling thinking above is
            // accepted only at `high` effort or below, so raising this to `xhigh` or
            // `max` without also removing the `thinking` block is a 400.
            outputConfig: RequestBody.OutputConfig(),
            messages: instruction.turns.map {
                RequestBody.Message(role: $0.speaker.rawValue, content: $0.text)
            }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// The three system blocks, `task` marked cacheable only on a first attempt.
    ///
    /// `PlanProposalInstruction.isRetry` exists precisely so a transport can make this
    /// call — see that property's doc comment. On a retry, `task` carries the specific
    /// rejection text §4.5 appends, which is unique to this one call and will never be
    /// asked again identically; marking it `cache_control` would pay a cache-write cost
    /// for an entry with no future read to pay it back. `schema` and `factSheet` are
    /// still marked: `schema` is identical text on a retry too (only `task` grew a
    /// paragraph), and `factSheet` is unchanged from the seed attempt within the one
    /// conversation §4.5 permits a retry inside of.
    private static func systemBlocks(for instruction: PlanProposalInstruction) -> [RequestBody.SystemBlock] {
        [
            RequestBody.SystemBlock(text: instruction.task, cached: !instruction.isRetry),
            RequestBody.SystemBlock(text: instruction.schema, cached: true),
            RequestBody.SystemBlock(text: instruction.factSheet, cached: true),
        ]
    }

    private struct RequestBody: Encodable {
        struct SystemBlock: Encodable {
            let type = "text"
            let text: String
            let cacheControl: CacheControl?

            struct CacheControl: Encodable {
                let type = "ephemeral"
            }

            init(text: String, cached: Bool) {
                self.text = text
                self.cacheControl = cached ? CacheControl() : nil
            }

            enum CodingKeys: String, CodingKey {
                case type, text
                case cacheControl = "cache_control"
            }

            // Hand-written rather than synthesized: the synthesized `encode(to:)`
            // would call `container.encode(cacheControl, forKey:)`, and encoding a
            // `nil` `Optional<CacheControl>` through the *non*-`IfPresent` overload
            // writes `"cache_control": null` rather than omitting the key. A null is
            // not documented as equivalent to an absent marker, and the whole point
            // of `cached: false` is to send a block with no cache marker at all —
            // exactly what an uncacheable retry `task` needs — so this uses
            // `encodeIfPresent` explicitly to actually omit the key when `cached` is
            // `false`.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encode(text, forKey: .text)
                try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
            }
        }

        struct Thinking: Encodable {
            let type = "disabled"
        }

        /// Effort is an output-level control, not a thinking budget: it is accepted
        /// alongside disabled thinking and bounds how much work the model does on the
        /// reply. See `AnthropicScoringModelClient.RequestBody.OutputConfig`; all
        /// three clients deliberately run at the same tier so a cost change is one
        /// decision.
        struct OutputConfig: Encodable {
            let effort = "medium"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let maxTokens: Int
        let system: [SystemBlock]
        let thinking: Thinking
        let outputConfig: OutputConfig
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, system, thinking, messages
            case maxTokens = "max_tokens"
            case outputConfig = "output_config"
        }
    }

    // MARK: - Response

    private static func checkStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401:
            throw PlanProposalModelError.invalidAPIKey
        case 429:
            throw PlanProposalModelError.rateLimited
        case 500...599:
            throw PlanProposalModelError.serverUnavailable(statusCode: statusCode)
        default:
            throw PlanProposalModelError.unexpectedStatus(statusCode)
        }
    }

    private static func text(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw PlanProposalModelError.unreadableResponse
        }

        // Checked before `content` is read at all, and in this order: a refusal can
        // carry an empty `content` array, and reading it unconditionally is exactly
        // the pitfall the Anthropic API's own documentation warns about — always
        // check `stop_reason` first.
        if decoded.stopReason == "refusal" {
            throw PlanProposalModelError.refused
        }
        if decoded.stopReason == "max_tokens" {
            throw PlanProposalModelError.truncated
        }

        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty
        else {
            throw PlanProposalModelError.unreadableResponse
        }
        return text
    }

    /// The slice of the Messages API response shape this client actually reads.
    /// Deliberately not a full model of the response — every other field (`id`,
    /// `model`, `usage`, …) is either unneeded here or would belong to a caller that
    /// wants it, and this type does not parse the reply's *content* at all (see the
    /// type doc comment).
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
