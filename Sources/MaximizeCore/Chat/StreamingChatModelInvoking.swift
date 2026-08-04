import Foundation

/// Sends one chat turn to the model and yields the reply as it arrives (D10, FR-2.4).
///
/// The sibling of `ScoringModelInvoking`, and the seam MAX-024 owns: the caller says
/// what to ask, something conforming to this moves the bytes, and the caller decides
/// what to do with the text. Neither side needs to know how the other half works —
/// the real implementation (`AnthropicStreamingChatClient`, App layer) speaks the
/// Messages API's server-sent-event stream over `URLSession`, and
/// `MaximizeCoreTestSupport` supplies `FakeStreamingChatModelInvoking` for everything
/// that needs to drive a chat surface without a network call, which today is every
/// test in this repo (CLAUDE.md, "What CI can and cannot prove").
///
/// ## Why it neither throws nor is `async`
///
/// `stream(_:)` returns immediately with a stream that has not started. Failure is a
/// value inside it — including "no key is stored", the app's ordinary condition on the
/// day it is installed — so a caller renders an error the same way it renders a reply,
/// and a chat view can never be brought down by a `throw` from a transport. See
/// `ChatStreamEvent` for the three guarantees the stream makes, and `ChatStreamError`
/// for why partial text outlives a failure.
///
/// Cancellation is the consuming task's: stop iterating (or cancel the task doing it)
/// and the implementation is expected to abandon the request. A stream abandoned
/// part-way emits no terminal event, because nothing failed — the caller left.
public protocol StreamingChatModelInvoking: Sendable {
    func stream(_ instruction: ChatInstruction) -> AsyncStream<ChatStreamEvent>
}
