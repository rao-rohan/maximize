import MaximizeCore

/// In-memory stand-in for `PlanProposalModelInvoking`, for MAX-101 (conversational
/// plan authoring) and any test that needs to drive a plan-drafting call without a
/// network call.
///
/// This is what makes MAX-100's seam testable at all: `AnthropicPlanProposalClient`
/// talks to a real server and is not exercised by this repo's CI (see CLAUDE.md,
/// "What CI can and cannot prove"), so every caller that reasons about a proposal
/// reply — happy path or failure — is written against this fake instead, leaving the
/// real client thin and decision-free.
///
/// Mirrors `FakeScoringModelInvoking`'s shape exactly: a scripted outcome plus a
/// record of what was actually asked, so a test can assert on both what came back and
/// on exactly what reached the transport — e.g. that a retry re-sent the corrected
/// `task` (`PlanProposalInstruction.isRetry`), not a stale one.
public final class FakePlanProposalModelInvoking: PlanProposalModelInvoking, @unchecked Sendable {
    /// What `reply(to:)` does on its next call.
    public enum Outcome {
        /// Return this string, as if it were the model's raw reply.
        case reply(String)
        /// Throw this error, as if the transport failed this way.
        case failure(PlanProposalModelError)
    }

    /// The outcome the next call to `reply(to:)` produces. A `var` rather than a
    /// fixed value at `init` so a single test can script a sequence — e.g. fail once
    /// with `.rateLimited`, then switch to a `.reply` before asserting a retry
    /// succeeds.
    public var outcome: Outcome

    /// Every instruction passed to `reply(to:)`, in call order. Lets a test assert
    /// on exactly what reached the transport, not just on how many times it was
    /// asked.
    public private(set) var receivedInstructions: [PlanProposalInstruction] = []

    /// Number of times `reply(to:)` has been called, for tests that only care about
    /// the count.
    public var callCount: Int { receivedInstructions.count }

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    public func reply(to instruction: PlanProposalInstruction) async throws -> String {
        receivedInstructions.append(instruction)
        switch outcome {
        case let .reply(text):
            return text
        case let .failure(error):
            throw error
        }
    }
}
