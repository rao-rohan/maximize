import Foundation
import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// Exercises the seam MAX-023 owns: `ScoringModelInvoking` and `ScoringModelError`,
/// through `FakeScoringModelInvoking` — the real client (`AnthropicScoringModelClient`,
/// App layer) is not exercised here, for the same reason the Keychain adapter isn't in
/// `AnthropicAPIKeyStoringTests` (see CLAUDE.md, "What CI can and cannot prove").
final class ScoringModelInvokingTests: XCTestCase {

    // MARK: - isWorthRetrying

    /// The distinction MAX-033 needs: a transient fault (network, rate limit,
    /// Anthropic's own overload, a timed-out clock) is worth asking again; anything
    /// that will fail identically on the same input is not.
    func testTransientFaultsAreWorthRetrying() {
        XCTAssertTrue(ScoringModelError.requestFailed.isWorthRetrying)
        XCTAssertTrue(ScoringModelError.timedOut.isWorthRetrying)
        XCTAssertTrue(ScoringModelError.rateLimited.isWorthRetrying)
        XCTAssertTrue(ScoringModelError.serverUnavailable(statusCode: 500).isWorthRetrying)
        XCTAssertTrue(ScoringModelError.serverUnavailable(statusCode: 529).isWorthRetrying)
    }

    func testPermanentFaultsAreNotWorthRetrying() {
        XCTAssertFalse(ScoringModelError.noAPIKeyStored.isWorthRetrying)
        XCTAssertFalse(ScoringModelError.invalidAPIKey.isWorthRetrying)
        XCTAssertFalse(ScoringModelError.unexpectedStatus(400).isWorthRetrying)
        XCTAssertFalse(ScoringModelError.refused.isWorthRetrying)
        XCTAssertFalse(ScoringModelError.truncated.isWorthRetrying)
        XCTAssertFalse(ScoringModelError.unreadableResponse.isWorthRetrying)
    }

    /// The one case CLAUDE.md calls out as a first-class outcome, not a crash: no key
    /// stored is a real, expected state (the moment the app is installed), and it
    /// must not be worth silently retrying into the same missing key forever.
    func testNoAPIKeyStoredIsNotWorthRetrying() {
        XCTAssertFalse(ScoringModelError.noAPIKeyStored.isWorthRetrying)
    }

    // MARK: - No leak paths

    /// Every case's description is either a fixed sentence or carries a bare HTTP
    /// status code (an `Int`) — never a response body, never a key. This is a
    /// structural guarantee (no case's payload can hold a `String` at all except the
    /// fixed sentences below), but pinning the exact text here means a future case
    /// added with a `String` payload fails a clearly-named test rather than silently
    /// creating a leak path.
    func testDescriptionsCarryOnlyStatusCodesNeverFreeText() {
        XCTAssertEqual(ScoringModelError.noAPIKeyStored.description, "No Anthropic API key is stored")
        XCTAssertTrue(ScoringModelError.serverUnavailable(statusCode: 503).description.contains("503"))
        XCTAssertTrue(ScoringModelError.unexpectedStatus(403).description.contains("403"))
        XCTAssertFalse(ScoringModelError.refused.description.contains("stop_details"))
    }

    // MARK: - FakeScoringModelInvoking

    func testFakeReturnsItsScriptedReply() async throws {
        let fake = FakeScoringModelInvoking(outcome: .reply(#"{"score": 91, "rationale": "Held the cap."}"#))
        let subject = try ScoringFixture.context()
        let instruction = try WorkoutScorer.instruction(for: subject, evaluation: RubricEvaluator.evaluate(subject))

        let reply = try await fake.reply(to: instruction)

        XCTAssertEqual(reply, #"{"score": 91, "rationale": "Held the cap."}"#)
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertEqual(fake.receivedInstructions, [instruction])
    }

    func testFakeThrowsItsScriptedFailure() async throws {
        let fake = FakeScoringModelInvoking(outcome: .failure(.rateLimited))
        let subject = try ScoringFixture.context()
        let instruction = try WorkoutScorer.instruction(for: subject, evaluation: RubricEvaluator.evaluate(subject))

        do {
            _ = try await fake.reply(to: instruction)
            XCTFail("Expected the fake to throw its scripted failure")
        } catch {
            XCTAssertEqual(error as? ScoringModelError, .rateLimited)
        }
        XCTAssertEqual(fake.callCount, 1)
    }

    /// The retry shape MAX-033 needs to drive: script a transient failure, retry,
    /// switch the outcome, and confirm the second call is what actually reaches the
    /// scorer as a reply — not a leftover from the first attempt.
    func testOutcomeCanBeReconfiguredBetweenCallsToScriptARetry() async throws {
        let fake = FakeScoringModelInvoking(outcome: .failure(.timedOut))
        let subject = try ScoringFixture.context()
        let instruction = try WorkoutScorer.instruction(for: subject, evaluation: RubricEvaluator.evaluate(subject))

        do {
            _ = try await fake.reply(to: instruction)
            XCTFail("Expected the fake to throw its scripted failure")
        } catch {
            XCTAssertEqual(error as? ScoringModelError, .timedOut)
        }

        fake.outcome = .reply(#"{"score": 95, "rationale": "Held the cap comfortably."}"#)
        let reply = try await fake.reply(to: instruction)

        XCTAssertEqual(reply, #"{"score": 95, "rationale": "Held the cap comfortably."}"#)
        XCTAssertEqual(fake.callCount, 2)
        XCTAssertEqual(fake.receivedInstructions, [instruction, instruction])
    }

    /// Mirrors `AnthropicAPIKeyStoringTests.testConsumersDependOnlyOnTheProtocol`:
    /// this is how `WorkoutScorer`'s caller (MAX-033, and the interactive scoring
    /// flow) will be written — against `ScoringModelInvoking`, never against
    /// `AnthropicScoringModelClient` directly.
    func testConsumersDependOnlyOnTheProtocol() async throws {
        func score(
            _ context: WorkoutContext,
            using transport: ScoringModelInvoking,
            scoredAt: Date
        ) async throws -> Score {
            let evaluation = try RubricEvaluator.evaluate(context)
            let instruction = try WorkoutScorer.instruction(for: context, evaluation: evaluation)
            let reply = try await transport.reply(to: instruction)
            return try WorkoutScorer.score(
                context: context,
                evaluation: evaluation,
                modelResponse: reply,
                scoredAt: scoredAt
            )
        }

        let subject = try ScoringFixture.context()
        let fake = FakeScoringModelInvoking(outcome: .reply(#"{"score": 97, "rationale": "Textbook easy run."}"#))

        let result = try await score(subject, using: fake, scoredAt: ScoringFixture.scoredAt)

        XCTAssertEqual(result.value.points, 97)
        XCTAssertEqual(result.rationale, "Textbook easy run.")
        XCTAssertEqual(fake.callCount, 1)
    }

    /// The full round trip through the seam this ticket owns: `WorkoutScorer` builds
    /// the instruction, a `ScoringModelInvoking` answers it, and a scored-outside-band
    /// reply is rejected exactly as it would be from the real transport — the fake
    /// changes nothing about `WorkoutScorer`'s own validation.
    func testATransportReplyOutsideTheMatchedBandIsStillRejected() async throws {
        let subject = try ScoringFixture.context()
        let evaluation = try RubricEvaluator.evaluate(subject)
        let instruction = try WorkoutScorer.instruction(for: subject, evaluation: evaluation)
        // Band is "easy.onCap.lowDrift" (90...100); 60 is a valid score but outside it.
        let fake = FakeScoringModelInvoking(outcome: .reply(#"{"score": 60, "rationale": "Fine run."}"#))

        let reply = try await fake.reply(to: instruction)

        assertThrowsScoring(
            .scoreOutsideBand,
            try WorkoutScorer.score(
                context: subject,
                evaluation: evaluation,
                modelResponse: reply,
                scoredAt: ScoringFixture.scoredAt
            )
        )
    }
}
