import MaximizeCore

/// In-memory stand-in for `StreamingChatModelInvoking`, for MAX-051's chat surface and
/// any test that needs a streamed reply without a network call.
///
/// This is what makes MAX-024's seam testable at all: `AnthropicStreamingChatClient`
/// talks to a real server and is not exercised by this repo's CI (see CLAUDE.md,
/// "What CI can and cannot prove"), so every caller that reasons about a streamed
/// reply — happy path, refusal, dropped connection mid-answer — is written against
/// this fake instead, leaving the real client thin.
///
/// Mirrors `FakeScoringModelInvoking`'s shape: a scripted outcome plus a record of
/// what was actually asked, so a test can assert on both what came back and on exactly
/// what reached the transport.
///
/// Never seeded with anything resembling a real credential or real health data — see
/// CLAUDE.md's "no secrets in the repo" rule, which applies to fixtures too.
public final class FakeStreamingChatModelInvoking: StreamingChatModelInvoking, @unchecked Sendable {
    /// The events the next call to `stream(_:)` yields, in order.
    ///
    /// A `var` rather than a fixed value at `init` so one test can script a sequence —
    /// e.g. drop the connection mid-answer, assert the partial text survived, then
    /// script a clean reply and assert the retry succeeded.
    public var events: [ChatStreamEvent]

    /// Every instruction passed to `stream(_:)`, in call order. Lets a test assert on
    /// exactly what reached the transport — that the fact sheet went across verbatim,
    /// say — not just on how many times it was asked.
    public private(set) var receivedInstructions: [ChatInstruction] = []

    public var callCount: Int { receivedInstructions.count }

    /// Runs immediately before the event at `index` is produced — and therefore after
    /// every earlier event has been consumed in full, because production is on demand
    /// (see `stream(_:)`). Nil by default, which is every test that predates MAX-197.
    ///
    /// The seam a cancellation test needs. Stopping a reply is a tap that lands *between*
    /// two frames of a live stream, and there is no way to place one there from outside:
    /// a test awaiting `send()` is suspended for exactly as long as the stream runs.
    /// Isolated to the main actor because the thing a test wants to do from here is call
    /// a method on `ChatModel`, which is `@MainActor`.
    public var beforeEachEvent: (@MainActor @Sendable (Int) -> Void)?

    /// Defaults to a short, complete reply so a caller that only cares that the
    /// transport was invoked does not have to script one.
    public init(events: [ChatStreamEvent] = [.text("Fixture "), .text("reply."), .completed(.endTurn)]) {
        self.events = events
    }

    /// One event per `next()`, produced when it is asked for rather than pushed into a
    /// buffer up front (MAX-197).
    ///
    /// The eager version this replaces handed the whole reply over before the consumer
    /// had read a word of it, which made the fake the one kind of stream a real one can
    /// never be: entirely arrived before it started. Nothing about a full drain changes —
    /// the same events come out in the same order — but a consumer that stops reading
    /// part-way now gets what a stopped connection actually gives it, nothing more, and
    /// `beforeEachEvent` has somewhere real to sit.
    public func stream(_ instruction: ChatInstruction) -> AsyncStream<ChatStreamEvent> {
        receivedInstructions.append(instruction)
        let scripted = events
        let hook = beforeEachEvent
        let cursor = Cursor()
        // Typed explicitly rather than inferred from the initializer's parameter: this
        // closure is the fake's whole contract now, and the one thing a reader should not
        // have to work out from context is what it is allowed to return.
        let produce: @Sendable () async -> ChatStreamEvent? = {
            let index = cursor.take()
            guard index < scripted.count else { return nil }
            // Awaited rather than optional-chained: the hook is main-actor isolated and
            // this closure is not, so the hop is the point — by the time it returns, a
            // `stop()` it performed has already been seen by the model.
            if let hook {
                await hook(index)
            }
            return scripted[index]
        }
        return AsyncStream(unfolding: produce)
    }

    /// How far through the script one call to `stream(_:)` has got.
    ///
    /// A box rather than a captured `var` because a producing closure cannot mutate one,
    /// and one per call rather than per fake so a retry replays the script from the top —
    /// which is what the streaming tests that script a failure and then a clean reply
    /// already assume.
    private final class Cursor: @unchecked Sendable {
        private var index = 0

        func take() -> Int {
            defer { index += 1 }
            return index
        }
    }
}
