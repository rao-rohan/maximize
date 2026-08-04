import Foundation
import XCTest
@testable import MaximizeCore

/// Exercises the half of MAX-024 that has decisions in it: what a server-sent-event
/// frame means, which deltas are the athlete's answer, and when a turn is over.
///
/// The real client (`AnthropicStreamingChatClient`, App layer) is not exercised here —
/// it opens a socket, which CI cannot do (CLAUDE.md, "What CI can and cannot prove").
/// Everything it *decides* is in this decoder, which is why these tests exist at all.
final class ChatStreamDecoderTests: XCTestCase {

    // MARK: - Helpers

    /// Runs `lines` through a fresh decoder and closes the stream, returning everything
    /// it produced. Mirrors what the app layer does with `bytes.lines`.
    private func decode(_ lines: [String]) -> [ChatStreamEvent] {
        var decoder = ChatStreamDecoder()
        var events: [ChatStreamEvent] = []
        for line in lines {
            events += decoder.consume(line)
        }
        events += decoder.finish()
        return events
    }

    /// A `data:` frame plus the blank line that closes it.
    private func frame(_ json: String) -> [String] {
        ["data: \(json)", ""]
    }

    private func textDelta(_ text: String) -> [String] {
        frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}"#)
    }

    private func messageDelta(stopReason: String) -> [String] {
        frame(#"{"type":"message_delta","delta":{"stop_reason":"\#(stopReason)","stop_sequence":null},"usage":{"output_tokens":12}}"#)
    }

    private var messageStop: [String] {
        frame(#"{"type":"message_stop"}"#)
    }

    // MARK: - Text

    /// The happy path, and the assertion that matters most: the reply comes out in
    /// order, and nothing else in the stream does.
    func testOnlyTextDeltasBecomeText() {
        let events = decode(
            frame(#"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}"#)
                + frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
                + textDelta("Your heart rate ")
                + textDelta("climbed after mile 3.")
                + frame(#"{"type":"content_block_stop","index":0}"#)
                + messageDelta(stopReason: "end_turn")
                + messageStop
        )

        XCTAssertEqual(events, [
            .text("Your heart rate "),
            .text("climbed after mile 3."),
            .completed(.endTurn),
        ])
    }

    /// Thinking is not the answer, and it is the model reasoning out loud about this
    /// person's health data — it must never reach a chat bubble. Tool-input and
    /// signature deltas are dropped for the plainer reason that they are not text.
    func testNonTextDeltasAreDropped() {
        let events = decode(
            frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The athlete's cap is 150..."}}"#)
                + frame(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"a\":"}}"#)
                + frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#)
                + textDelta("Answer.")
                + messageDelta(stopReason: "end_turn")
                + messageStop
        )

        XCTAssertEqual(events, [.text("Answer."), .completed(.endTurn)])
    }

    /// An empty delta is not a token, and forwarding it would make a view redraw for
    /// nothing.
    func testEmptyTextDeltasAreDropped() {
        let events = decode(textDelta("") + textDelta("Real.") + messageDelta(stopReason: "end_turn") + messageStop)

        XCTAssertEqual(events, [.text("Real."), .completed(.endTurn)])
    }

    // MARK: - How a turn ends

    func testMaxTokensCompletesAsTruncated() {
        let events = decode(textDelta("Half an ") + messageDelta(stopReason: "max_tokens") + messageStop)

        // Deliberately a completion, not a failure: unlike a cut-off scoring reply, a
        // cut-off chat answer is still an answer.
        XCTAssertEqual(events, [.text("Half an "), .completed(.truncated)])
    }

    func testRefusalFailsTheTurn() {
        let events = decode(messageDelta(stopReason: "refusal") + messageStop)

        XCTAssertEqual(events, [.failed(.refused)])
    }

    /// A stop reason this client has never heard of, or none at all, is not a reason to
    /// throw away a turn the model plainly finished.
    func testUnknownOrAbsentStopReasonCompletesNormally() {
        XCTAssertEqual(
            decode(textDelta("Done.") + messageDelta(stopReason: "stop_sequence") + messageStop),
            [.text("Done."), .completed(.endTurn)]
        )
        XCTAssertEqual(
            decode(textDelta("Done.") + messageStop),
            [.text("Done."), .completed(.endTurn)]
        )
    }

    // MARK: - Failure

    /// The case that makes the partial-text rule matter: a phone loses signal
    /// mid-answer. Everything already delivered still stands, and the turn is reported
    /// as interrupted rather than quietly ending as though it had finished.
    func testConnectionEndingMidTurnInterruptsAndKeepsPartialText() {
        let events = decode(textDelta("Your heart rate ") + textDelta("climbed"))

        XCTAssertEqual(events, [
            .text("Your heart rate "),
            .text("climbed"),
            .failed(.interrupted),
        ])
    }

    func testRateLimitErrorEventIsReportedAsRateLimiting() {
        let events = decode(frame(#"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#))

        XCTAssertEqual(events, [.failed(.rateLimited)])
    }

    /// Anything else arriving as an `error` frame is Anthropic-side trouble mid
    /// generation — a request the API considers invalid never gets a 200 to stream
    /// from — so it is worth asking again.
    func testOtherErrorEventsAreReportedAsTransient() {
        let events = decode(frame(#"{"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}"#))

        XCTAssertEqual(events, [.failed(.midStreamFailure)])
        XCTAssertTrue(ChatStreamError.midStreamFailure.isWorthRetrying)
    }

    /// A `data:` payload that is not the documented shape means this client and the API
    /// disagree about the protocol. Better a loud failure than a silently truncated
    /// answer.
    func testUnparseableFrameFailsTheStream() {
        XCTAssertEqual(decode(frame("not json at all")), [.failed(.unreadableResponse)])
    }

    /// An `error` frame with no recognizable body still ends the stream rather than
    /// leaving a chat view spinning forever.
    func testErrorFrameWithoutATypeStillEndsTheStream() {
        XCTAssertEqual(decode(frame(#"{"type":"error"}"#)), [.failed(.midStreamFailure)])
    }

    // MARK: - The one-terminal-event contract

    func testNothingIsEmittedAfterTheTerminalEvent() {
        var decoder = ChatStreamDecoder()
        var events: [ChatStreamEvent] = []
        for line in messageDelta(stopReason: "end_turn") + messageStop + textDelta("stray") + messageStop {
            events += decoder.consume(line)
        }

        XCTAssertEqual(events, [.completed(.endTurn)])
        XCTAssertEqual(decoder.finish(), [], "finish() must not add a second terminal event")
    }

    /// `finish()` is called by the app layer on every path, including the ones where a
    /// terminal event has already been sent. Calling it twice must still be quiet.
    func testFinishIsIdempotent() {
        var decoder = ChatStreamDecoder()
        XCTAssertEqual(decoder.finish(), [.failed(.interrupted)])
        XCTAssertEqual(decoder.finish(), [])
    }

    // MARK: - Framing

    /// A response that closes promptly can leave its last frame without the trailing
    /// blank line. Dropping it would lose the `message_stop` and turn a good turn into
    /// a spurious `interrupted`.
    func testFinalFrameWithoutATrailingBlankLineIsStillDelivered() {
        var decoder = ChatStreamDecoder()
        var events: [ChatStreamEvent] = []
        for line in textDelta("Done.") + messageDelta(stopReason: "end_turn") {
            events += decoder.consume(line)
        }
        events += decoder.consume(#"data: {"type":"message_stop"}"#)
        events += decoder.finish()

        XCTAssertEqual(events, [.text("Done."), .completed(.endTurn)])
    }

    /// The format's own rule: several `data:` lines in one frame are its value joined
    /// by newlines. The API sends single-line JSON today; honouring the rule means a
    /// pretty-printed payload would not decode as garbage.
    func testMultiLineDataFramesAreJoined() {
        let events = decode([
            #"data: {"type":"content_block_delta","index":0,"#,
            #"data: "delta":{"type":"text_delta","text":"Split."}}"#,
            "",
        ] + messageStop)

        XCTAssertEqual(events, [.text("Split."), .completed(.endTurn)])
    }

    /// Comment lines are the keep-alive heartbeat; `event:` duplicates the `type` in
    /// the payload, which is the value the API documents as authoritative.
    func testCommentAndEventNameLinesAreIgnored() {
        let events = decode(
            [": ping", "event: content_block_delta"]
                + textDelta("Text.")
                + ["event: message_stop"]
                + messageStop
        )

        XCTAssertEqual(events, [.text("Text."), .completed(.endTurn)])
    }

    /// A stray carriage return left on the end of a line would make "data:" fail its
    /// prefix test and turn a whole reply into silence.
    func testCarriageReturnsAreTolerated() {
        let events = decode([
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"CRLF."}}"# + "\r",
            "\r",
            #"data: {"type":"message_stop"}"# + "\r",
            "\r",
        ])

        XCTAssertEqual(events, [.text("CRLF."), .completed(.endTurn)])
    }

    /// The space after `data:` is optional in the format, and is not part of the value.
    func testDataFieldWithoutASpaceAfterTheColonIsRead() {
        let events = decode([
            #"data:{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Tight."}}"#,
            "",
        ] + messageStop)

        XCTAssertEqual(events, [.text("Tight."), .completed(.endTurn)])
    }

    /// Forward compatibility: an event type added after this was written must not break
    /// a shipped build.
    func testUnknownFrameTypesAreIgnored() {
        let events = decode(
            frame(#"{"type":"something_new_2027","payload":{"a":1}}"#)
                + textDelta("Still fine.")
                + messageStop
        )

        XCTAssertEqual(events, [.text("Still fine."), .completed(.endTurn)])
    }

    /// Blank lines with nothing buffered are frame boundaries, not empty frames.
    func testBlankLinesAloneProduceNothing() {
        var decoder = ChatStreamDecoder()
        XCTAssertEqual(decoder.consume(""), [])
        XCTAssertEqual(decoder.consume(""), [])
    }
}
