import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// CHAT-FIRST-SPEC.md §4.5, MAX-101: the retry policy.
///
/// **One, not zero and not a loop.** Zero throws away a recoverable failure — the errors
/// `PlanProposal.parse` produces were written specific enough to correct, and
/// `PlanProposalInstruction(retryingAfter:)` exists solely to put one back in front of
/// the model. A loop is the failure mode §4.5 names outright: *"a loop burning the
/// owner's tokens against a model that keeps proposing a 400 bpm cap."* Both halves are
/// asserted here.
final class PlanProposalDraftingTests: XCTestCase {

    // MARK: - Fixtures

    private static let goodReply = """
    {
      "heartRateCapBPM": 150,
      "cadenceLowStepsPerMinute": 165,
      "cadenceHighStepsPerMinute": 172,
      "effectiveThresholdPoints": 70,
      "marginalThresholdPoints": 45,
      "week": [
        {"weekday": "monday", "kind": "rest"},
        {"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000},
        {"weekday": "wednesday", "kind": "hard", "note": "6 × 800m"},
        {"weekday": "thursday", "kind": "easy", "distanceMeters": 6000},
        {"weekday": "friday", "kind": "rest"},
        {"weekday": "saturday", "kind": "easy", "distanceMeters": 6000},
        {"weekday": "sunday", "kind": "long", "distanceMeters": 18000}
      ],
      "longRunArc": [{"index": 1, "distanceMeters": 16000}],
      "goalStatements": ["Sub-1:45 half marathon"]
    }
    """

    /// A cap no plan can carry. Rejected at the proposal boundary in the door's own
    /// vocabulary, which is exactly the sentence §4.5 wants sent back.
    private static let implausibleCapReply = goodReply.replacingOccurrences(
        of: #""heartRateCapBPM": 150"#,
        with: #""heartRateCapBPM": 400"#
    )

    private func turns() throws -> [ChatTurn] {
        [
            try ChatTurn(speaker: .user, text: "16 weeks to a half on 15 November. Four runs a week."),
            try ChatTurn(speaker: .assistant, text: "Got it — four runs, long run on Sunday."),
        ]
    }

    private func draft(
        _ outcome: FakePlanProposalModelInvoking.Outcome
    ) async throws -> (PlanDraftingOutcome, FakePlanProposalModelInvoking) {
        let model = FakePlanProposalModelInvoking(outcome: outcome)
        let result = await PlanProposalDrafting.proposal(
            from: model,
            factSheet: "Training window: 1 Jul – 4 Aug 2026. No plan authored.",
            turns: try turns()
        )
        return (result, model)
    }

    // MARK: - The happy path is one call

    func testAUsableFirstReplyIsOneCallAndNoRetry() async throws {
        let (outcome, model) = try await draft(.reply(Self.goodReply))

        guard case let .proposed(proposal) = outcome else {
            return XCTFail("expected a proposal, got \(outcome)")
        }
        XCTAssertEqual(proposal.heartRateCapBPM, 150)
        XCTAssertEqual(model.callCount, 1)
        XCTAssertEqual(model.receivedInstructions.first?.isRetry, false)
    }

    /// The instruction is assembled by `PlanProposalInstruction` and nowhere else: the
    /// fact sheet travels verbatim (D3, A12 rule 1) and the schema travels beside `task`
    /// rather than through an audience (§4.9).
    func testTheFirstInstructionCarriesTheFactSheetVerbatimAndTheSchemaBesideTheTask() async throws {
        let sheet = "Training window: 1 Jul – 4 Aug 2026. No plan authored."
        let (_, model) = try await draft(.reply(Self.goodReply))
        let instruction = try XCTUnwrap(model.receivedInstructions.first)

        XCTAssertEqual(instruction.factSheet, sheet)
        XCTAssertEqual(instruction.schema, PlanProposal.schemaDescription)
        XCTAssertEqual(instruction.task, PlanProposalInstruction.taskDescription)
        XCTAssertEqual(instruction.turns.count, 2)
    }

    // MARK: - One retry, with the reason

    /// §4.5 step 1. The retry is not a repeat of the same request: it carries the
    /// rejection's own `description`, which is what makes asking again worth a call.
    func testAnUnusableReplyIsAskedAgainOnceWithTheReason() async throws {
        let model = FakePlanProposalModelInvoking(outcome: .reply(Self.implausibleCapReply))
        // The fake answers from a single `outcome`, so flipping it after the first call
        // is how a scripted sequence is expressed — see its own documentation.
        let result = await withCorrection(model, to: Self.goodReply)

        guard case .proposed = result else {
            return XCTFail("the corrected reply should have produced a proposal, got \(result)")
        }
        XCTAssertEqual(model.callCount, PlanProposalDrafting.maximumAttempts)

        let retry = try XCTUnwrap(model.receivedInstructions.last)
        XCTAssertTrue(retry.isRetry)
        XCTAssertTrue(
            retry.task.contains(PlanAuthoringError.heartRateCapImplausible(
                permitted: HeartRateSample.plausibleBPM
            ).description),
            "the retry has to name what was wrong; got: \(retry.task)"
        )
        // The retry is still the same request in every other respect.
        XCTAssertEqual(retry.factSheet, model.receivedInstructions.first?.factSheet)
        XCTAssertEqual(retry.schema, PlanProposal.schemaDescription)
    }

    /// §4.5 step 2, and the half that bounds the cost: **two failures stop**, they do not
    /// become three. Asserted as a call count against `maximumAttempts` rather than
    /// against a literal, so the policy has one place to change.
    func testTwoUnusableRepliesStopRatherThanLooping() async throws {
        let (outcome, model) = try await draft(.reply(Self.implausibleCapReply))

        guard case let .failed(.rejected(error)) = outcome else {
            return XCTFail("expected a rejection after two attempts, got \(outcome)")
        }
        XCTAssertEqual(model.callCount, PlanProposalDrafting.maximumAttempts)
        XCTAssertEqual(
            error,
            .rejectedByAuthoring(.heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM))
        )
        // The sentence the athlete reads names what was wrong and says nothing changed.
        XCTAssertTrue(PlanDraftingFailure.rejected(error).description.contains("Nothing has changed"))
    }

    /// A reply that is not JSON at all takes the same path — §4.5's policy is uniform,
    /// and `PlanProposalError` deliberately has no `isWorthRetrying` for that reason.
    func testProseInsteadOfAProposalIsRetriedOnceAndThenReported() async throws {
        let (outcome, model) = try await draft(.reply("Sure! Here is a plan for you."))

        guard case .failed(.rejected) = outcome else {
            return XCTFail("expected a rejection, got \(outcome)")
        }
        XCTAssertEqual(model.callCount, 2)
    }

    // MARK: - Transport failures are not retried here

    /// A14: plan drafting is one call per tap. A transport failure is not a failure of
    /// the proposal's *content*, so §4.5's correction has nothing to say to it and the
    /// app does not spend a second call on the athlete's behalf.
    func testATransportFailureIsReportedWithoutASecondCall() async throws {
        for failure in [PlanProposalModelError.rateLimited, .timedOut, .refused, .noAPIKeyStored] {
            let (outcome, model) = try await draft(.failure(failure))

            XCTAssertEqual(outcome, .failed(.transport(failure)))
            XCTAssertEqual(model.callCount, 1, "\(failure) should not be retried here")
        }
    }

    /// The no-key case is the one an athlete meets on a fresh install, and it gets the
    /// same "go add a key in Settings" sentence chat already uses rather than a status
    /// code.
    func testTheNoKeySentencePointsAtTheFix() {
        let text = PlanDraftingFailure.transport(.noAPIKeyStored).description
        XCTAssertTrue(text.contains("Settings"))
        XCTAssertFalse(text.contains("401"))
    }

    // MARK: - Nothing to draft from

    /// An empty transcript is not a degraded request, it is not a request at all — and
    /// it costs zero calls to find that out.
    func testAnEmptyTranscriptCostsNoCallAtAll() async throws {
        let model = FakePlanProposalModelInvoking(outcome: .reply(Self.goodReply))
        let outcome = await PlanProposalDrafting.proposal(
            from: model,
            factSheet: "Training window: 1 Jul – 4 Aug 2026.",
            turns: []
        )

        XCTAssertEqual(outcome, .failed(.nothingToDraftFrom))
        XCTAssertEqual(model.callCount, 0)
    }

    /// A transcript opening with the assistant is the same non-request:
    /// `PlanProposalInstruction` refuses it in the core rather than letting it become a
    /// 400 from a live server.
    func testATranscriptThatDoesNotOpenWithTheAthleteCostsNoCall() async throws {
        let model = FakePlanProposalModelInvoking(outcome: .reply(Self.goodReply))
        let outcome = await PlanProposalDrafting.proposal(
            from: model,
            factSheet: "Training window: 1 Jul – 4 Aug 2026.",
            turns: [try ChatTurn(speaker: .assistant, text: "Shall I draft something?")]
        )

        XCTAssertEqual(outcome, .failed(.nothingToDraftFrom))
        XCTAssertEqual(model.callCount, 0)
    }

    // MARK: - Helper

    /// Runs a draft where the model answers badly first and correctly second.
    ///
    /// `FakePlanProposalModelInvoking` answers from a single `outcome`, and there is no
    /// hook to change it *between* two calls made inside one `await`. The wrapper below
    /// sequences them instead, still passing every instruction through the fake so
    /// `receivedInstructions` and `callCount` remain the things the assertions read.
    private func withCorrection(
        _ model: FakePlanProposalModelInvoking,
        to reply: String
    ) async -> PlanDraftingOutcome {
        let sequenced = SequencedPlanProposalModel(inner: model, correctedReply: reply)
        return await PlanProposalDrafting.proposal(
            from: sequenced,
            factSheet: "Training window: 1 Jul – 4 Aug 2026. No plan authored.",
            turns: (try? turns()) ?? []
        )
    }

    /// Answers the first call from the wrapped fake and every later call with a corrected
    /// reply, while still recording each instruction on the fake so the assertions above
    /// can read them.
    private final class SequencedPlanProposalModel: PlanProposalModelInvoking, @unchecked Sendable {
        private let inner: FakePlanProposalModelInvoking
        private let correctedReply: String

        init(inner: FakePlanProposalModelInvoking, correctedReply: String) {
            self.inner = inner
            self.correctedReply = correctedReply
        }

        func reply(to instruction: PlanProposalInstruction) async throws -> String {
            let answer = try await inner.reply(to: instruction)
            return inner.callCount > 1 ? correctedReply : answer
        }
    }
}
