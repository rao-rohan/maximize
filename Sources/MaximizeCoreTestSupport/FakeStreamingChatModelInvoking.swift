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

    /// Defaults to a short, complete reply so a caller that only cares that the
    /// transport was invoked does not have to script one.
    public init(events: [ChatStreamEvent] = [.text("Fixture "), .text("reply."), .completed(.endTurn)]) {
        self.events = events
    }

    public func stream(_ instruction: ChatInstruction) -> AsyncStream<ChatStreamEvent> {
        receivedInstructions.append(instruction)
        let scripted = events
        return AsyncStream { continuation in
            for event in scripted {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
