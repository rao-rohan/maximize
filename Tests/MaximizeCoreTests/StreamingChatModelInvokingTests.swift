import Foundation
import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// Exercises the seam MAX-024 owns: `StreamingChatModelInvoking`, `ChatInstruction`
/// and `ChatStreamError`, through `FakeStreamingChatModelInvoking`. The real client
/// (`AnthropicStreamingChatClient`, App layer) is not exercised here, for the same
/// reason the Keychain adapter isn't in `AnthropicAPIKeyStoringTests` and the scoring
/// client isn't in `ScoringModelInvokingTests` — see CLAUDE.md, "What CI can and
/// cannot prove".
final class StreamingChatModelInvokingTests: XCTestCase {

    // MARK: - Fixtures

    /// Deliberately not a real fact sheet: this ticket is transport, and building one
    /// would mean assembling prompt context, which D3 reserves for MAX-014.
    private static let factSheet = "## Workout\nFixture fact sheet, rendered elsewhere."
    private static let task = "Fixture task text. Contains no run data."

    private func instruction(
        turns: [ChatTurn]? = nil
    ) throws -> ChatInstruction {
        try ChatInstruction(
            task: Self.task,
            factSheet: Self.factSheet,
            turns: turns ?? [ChatTurn(speaker: .user, text: "Why did my HR drift at mile 3?")]
        )
    }

    private func collect(_ stream: AsyncStream<ChatStreamEvent>) async -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - ChatInstruction

    func testInstructionKeepsItsThreePartsSeparate() throws {
        let subject = try instruction()

        XCTAssertEqual(subject.task, Self.task)
        XCTAssertEqual(subject.factSheet, Self.factSheet)
        XCTAssertEqual(subject.turns.count, 1)
    }

    /// The Messages API requires the first message to be the user's, and a thread that
    /// opens with an assistant turn is nonsense to replay. Caught here, in the core,
    /// rather than as a 400 from a live server that CI can never see.
    func testInstructionRejectsAnAssistantSpeakingFirst() throws {
        let turns = [
            try ChatTurn(speaker: .assistant, text: "Unprompted."),
            try ChatTurn(speaker: .user, text: "Why?"),
        ]

        XCTAssertThrowsError(try instruction(turns: turns)) { error in
            guard let domainError = error as? DomainError, case .inconsistent = domainError else {
                XCTFail("Expected DomainError.inconsistent, got \(error)")
                return
            }
        }
    }

    func testInstructionRejectsAnEmptyConversation() {
        XCTAssertThrowsError(try instruction(turns: [])) { error in
            XCTAssertEqual(error as? DomainError, .empty(field: "ChatInstruction.turns"))
        }
    }

    func testInstructionRejectsMissingTaskOrFactSheet() throws {
        let turns = [try ChatTurn(speaker: .user, text: "Why?")]

        XCTAssertThrowsError(
            try ChatInstruction(task: "  ", factSheet: Self.factSheet, turns: turns)
        ) { error in
            XCTAssertEqual(error as? DomainError, .empty(field: "ChatInstruction.task"))
        }
        XCTAssertThrowsError(
            try ChatInstruction(task: Self.task, factSheet: "", turns: turns)
        ) { error in
            XCTAssertEqual(error as? DomainError, .empty(field: "ChatInstruction.factSheet"))
        }
    }

    func testTurnRejectsEmptyText() {
        XCTAssertThrowsError(try ChatTurn(speaker: .user, text: "\n ")) { error in
            XCTAssertEqual(error as? DomainError, .empty(field: "ChatTurn.text"))
        }
    }

    /// The seed context (FR-2.1) is not a conversational turn, so `ChatTurn` has no
    /// case for it — the fact sheet travels in its own property. This pins that
    /// decision: if a `system` speaker is ever added, this test says so.
    func testATurnCanOnlyBeUserOrAssistant() {
        XCTAssertEqual(ChatTurn.Speaker.allCases, [.user, .assistant])
    }

    // MARK: - ChatStreamEvent

    func testOnlyCompletionAndFailureAreTerminal() {
        XCTAssertFalse(ChatStreamEvent.text("partial").isTerminal)
        XCTAssertTrue(ChatStreamEvent.completed(.endTurn).isTerminal)
        XCTAssertTrue(ChatStreamEvent.completed(.truncated).isTerminal)
        XCTAssertTrue(ChatStreamEvent.failed(.interrupted).isTerminal)
    }

    // MARK: - ChatStreamError

    /// The distinction a chat surface needs to offer "try again" rather than "go fix
    /// your key": a transient fault is worth asking again; anything that will fail
    /// identically on the same input is not.
    func testTransientFaultsAreWorthRetrying() {
        XCTAssertTrue(ChatStreamError.requestFailed.isWorthRetrying)
        XCTAssertTrue(ChatStreamError.timedOut.isWorthRetrying)
        XCTAssertTrue(ChatStreamError.rateLimited.isWorthRetrying)
        XCTAssertTrue(ChatStreamError.serverUnavailable(statusCode: 529).isWorthRetrying)
        XCTAssertTrue(ChatStreamError.interrupted.isWorthRetrying)
        XCTAssertTrue(ChatStreamError.midStreamFailure.isWorthRetrying)
    }

    func testPermanentFaultsAreNotWorthRetrying() {
        XCTAssertFalse(ChatStreamError.noAPIKeyStored.isWorthRetrying)
        XCTAssertFalse(ChatStreamError.keyStoreUnavailable.isWorthRetrying)
        XCTAssertFalse(ChatStreamError.invalidAPIKey.isWorthRetrying)
        XCTAssertFalse(ChatStreamError.unexpectedStatus(400).isWorthRetrying)
        XCTAssertFalse(ChatStreamError.refused.isWorthRetrying)
        XCTAssertFalse(ChatStreamError.unreadableResponse.isWorthRetrying)
    }

    /// "No key stored" and "the stored key could not be read" are different problems
    /// with different fixes, and MAX-023 kept them apart for that reason. This pins
    /// that they stay apart here too.
    func testAMissingKeyIsDistinctFromAnUnreadableOne() {
        XCTAssertNotEqual(ChatStreamError.noAPIKeyStored, .keyStoreUnavailable)
        XCTAssertNotEqual(
            ChatStreamError.noAPIKeyStored.description,
            ChatStreamError.keyStoreUnavailable.description
        )
    }

    /// Every case's description is either a fixed sentence or carries a bare HTTP
    /// status code. This is structural — no case has a `String` payload at all — but
    /// pinning it means a future case added with one fails a clearly-named test rather
    /// than silently creating a leak path for a response body.
    func testDescriptionsCarryOnlyStatusCodesNeverFreeText() {
        XCTAssertEqual(ChatStreamError.noAPIKeyStored.description, "No Anthropic API key is stored")
        XCTAssertTrue(ChatStreamError.serverUnavailable(statusCode: 503).description.contains("503"))
        XCTAssertTrue(ChatStreamError.unexpectedStatus(403).description.contains("403"))
        XCTAssertFalse(ChatStreamError.midStreamFailure.description.contains("overloaded_error"))
    }

    // MARK: - FakeStreamingChatModelInvoking

    func testFakeYieldsItsScriptedEventsAndRecordsWhatWasAsked() async throws {
        let fake = FakeStreamingChatModelInvoking(events: [
            .text("Your HR "),
            .text("drifted."),
            .completed(.endTurn),
        ])
        let subject = try instruction()

        let events = await collect(fake.stream(subject))

        XCTAssertEqual(events, [.text("Your HR "), .text("drifted."), .completed(.endTurn)])
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertEqual(fake.receivedInstructions, [subject])
    }

    /// The shape a chat view has to render: text, then a failure, with the text still
    /// standing. A caller that treated `.failed` as "discard what you have" would show
    /// an empty bubble where half an answer belongs.
    func testPartialTextSurvivesAFailedTurn() async throws {
        let fake = FakeStreamingChatModelInvoking(events: [
            .text("Your HR "),
            .failed(.interrupted),
        ])

        let events = await collect(fake.stream(try instruction()))

        XCTAssertEqual(events.first, .text("Your HR "))
        XCTAssertEqual(events.last, .failed(.interrupted))
        XCTAssertEqual(events.filter(\.isTerminal).count, 1)
    }

    /// The app's ordinary condition the day it is installed, delivered as a value the
    /// UI can render rather than as a thrown error a chat view has to catch.
    func testAMissingKeyArrivesAsAnEventNotAThrow() async throws {
        let fake = FakeStreamingChatModelInvoking(events: [.failed(.noAPIKeyStored)])

        let events = await collect(fake.stream(try instruction()))

        XCTAssertEqual(events, [.failed(.noAPIKeyStored)])
    }
}
