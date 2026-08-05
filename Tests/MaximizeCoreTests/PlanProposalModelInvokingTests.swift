import Foundation
import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// Exercises the seam MAX-100 owns: `PlanProposalModelInvoking` and
/// `PlanProposalModelError`, through `FakePlanProposalModelInvoking` — the real
/// client (`AnthropicPlanProposalClient`, App layer) is not exercised here, for the
/// same reason `AnthropicScoringModelClient` isn't in `ScoringModelInvokingTests`
/// (see CLAUDE.md, "What CI can and cannot prove").
final class PlanProposalModelInvokingTests: XCTestCase {

    private let factSheet = """
        # Training — 20 Jul 2026 – 2 Aug 2026
        Plan version 3, heart-rate cap 150 bpm.
        """

    private func turns() throws -> [ChatTurn] {
        [try ChatTurn(speaker: .user, text: "16 weeks, half marathon on 15 November.")]
    }

    private let validReply = """
        {"heartRateCapBPM": 148, "cadenceLowStepsPerMinute": 165, \
        "cadenceHighStepsPerMinute": 172, "effectiveThresholdPoints": 70, \
        "marginalThresholdPoints": 45, "week": [\
        {"weekday": "monday", "kind": "rest", "liftKind": "rest"}, \
        {"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}, \
        {"weekday": "wednesday", "kind": "hard", "note": "6 × 800m", "liftKind": "rest"}, \
        {"weekday": "thursday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}, \
        {"weekday": "friday", "kind": "rest", "liftKind": "rest"}, \
        {"weekday": "saturday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}, \
        {"weekday": "sunday", "kind": "long", "distanceMeters": 20000, "liftKind": "rest"}], \
        "longRunArc": [{"index": 1, "distanceMeters": 16000}], \
        "goalStatements": ["Half marathon"], "goalTargetDay": "2026-11-15"}
        """

    // MARK: - isWorthRetrying

    /// The distinction a caller driving a transport-level retry needs: a transient
    /// fault (network, rate limit, Anthropic's own overload, a timed-out clock) is
    /// worth asking again; anything that will fail identically on the same input is
    /// not. Note this is separate from §4.5's *content* retry — see the type's doc
    /// comment.
    func testTransientFaultsAreWorthRetrying() {
        XCTAssertTrue(PlanProposalModelError.requestFailed.isWorthRetrying)
        XCTAssertTrue(PlanProposalModelError.timedOut.isWorthRetrying)
        XCTAssertTrue(PlanProposalModelError.rateLimited.isWorthRetrying)
        XCTAssertTrue(PlanProposalModelError.serverUnavailable(statusCode: 500).isWorthRetrying)
        XCTAssertTrue(PlanProposalModelError.serverUnavailable(statusCode: 529).isWorthRetrying)
    }

    func testPermanentFaultsAreNotWorthRetrying() {
        XCTAssertFalse(PlanProposalModelError.noAPIKeyStored.isWorthRetrying)
        XCTAssertFalse(PlanProposalModelError.invalidAPIKey.isWorthRetrying)
        XCTAssertFalse(PlanProposalModelError.unexpectedStatus(400).isWorthRetrying)
        XCTAssertFalse(PlanProposalModelError.refused.isWorthRetrying)
        XCTAssertFalse(PlanProposalModelError.truncated.isWorthRetrying)
        XCTAssertFalse(PlanProposalModelError.unreadableResponse.isWorthRetrying)
    }

    // MARK: - No leak paths

    /// Every case's description is either a fixed sentence or carries a bare HTTP
    /// status code (an `Int`) — never a response body, never a key.
    func testDescriptionsCarryOnlyStatusCodesNeverFreeText() {
        XCTAssertEqual(PlanProposalModelError.noAPIKeyStored.description, "No Anthropic API key is stored")
        XCTAssertTrue(PlanProposalModelError.serverUnavailable(statusCode: 503).description.contains("503"))
        XCTAssertTrue(PlanProposalModelError.unexpectedStatus(403).description.contains("403"))
        XCTAssertFalse(PlanProposalModelError.refused.description.contains("stop_details"))
    }

    // MARK: - FakePlanProposalModelInvoking

    func testFakeReturnsItsScriptedReplyAndItParsesIntoAProposal() async throws {
        let fake = FakePlanProposalModelInvoking(outcome: .reply(validReply))
        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        let reply = try await fake.reply(to: instruction)
        let proposal = try PlanProposal.parse(reply)

        XCTAssertEqual(proposal.heartRateCapBPM, 148)
        XCTAssertEqual(proposal[.monday], .rest)
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertEqual(fake.receivedInstructions, [instruction])
    }

    func testFakeThrowsItsScriptedFailure() async throws {
        let fake = FakePlanProposalModelInvoking(outcome: .failure(.rateLimited))
        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        do {
            _ = try await fake.reply(to: instruction)
            XCTFail("Expected the fake to throw its scripted failure")
        } catch {
            XCTAssertEqual(error as? PlanProposalModelError, .rateLimited)
        }
        XCTAssertEqual(fake.callCount, 1)
    }

    /// The retry shape MAX-101 needs to drive: script a transient failure, retry
    /// with the corrected instruction §4.5 describes, switch the outcome, and
    /// confirm the second call is what actually reaches the caller as a reply — and
    /// that the two instructions the fake recorded are the seed attempt and the
    /// retry, not two copies of one or the other.
    func testOutcomeCanBeReconfiguredBetweenCallsToScriptARetry() async throws {
        let fake = FakePlanProposalModelInvoking(outcome: .failure(.timedOut))
        let seedInstruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        do {
            _ = try await fake.reply(to: seedInstruction)
            XCTFail("Expected the fake to throw its scripted failure")
        } catch {
            XCTAssertEqual(error as? PlanProposalModelError, .timedOut)
        }

        let retryInstruction = try PlanProposalInstruction(
            factSheet: factSheet,
            turns: turns(),
            retryingAfter: .longRunArcIsEmpty
        )
        fake.outcome = .reply(validReply)
        let reply = try await fake.reply(to: retryInstruction)

        XCTAssertEqual(reply, validReply)
        XCTAssertTrue(retryInstruction.isRetry)
        XCTAssertFalse(seedInstruction.isRetry)
        XCTAssertEqual(fake.callCount, 2)
        XCTAssertEqual(fake.receivedInstructions, [seedInstruction, retryInstruction])
    }

    /// Mirrors `ScoringModelInvokingTests.testConsumersDependOnlyOnTheProtocol`: this
    /// is how a caller (MAX-101) will be written — against `PlanProposalModelInvoking`,
    /// never against `AnthropicPlanProposalClient` directly.
    func testConsumersDependOnlyOnTheProtocol() async throws {
        func draftProposal(
            _ instruction: PlanProposalInstruction,
            using transport: PlanProposalModelInvoking
        ) async throws -> PlanProposal {
            try PlanProposal.parse(await transport.reply(to: instruction))
        }

        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())
        let fake = FakePlanProposalModelInvoking(outcome: .reply(validReply))

        let proposal = try await draftProposal(instruction, using: fake)

        XCTAssertEqual(proposal.goalStatements, ["Half marathon"])
        XCTAssertEqual(fake.callCount, 1)
    }
}
