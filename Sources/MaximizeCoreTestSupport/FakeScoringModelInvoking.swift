import MaximizeCore

/// In-memory stand-in for `ScoringModelInvoking`, for MAX-033 (the ingestion
/// pipeline) and any test that needs to drive `WorkoutScorer` without a network call.
///
/// This is what makes MAX-023's seam testable at all: `AnthropicScoringModelClient`
/// talks to a real server and is not exercised by this repo's CI (see CLAUDE.md,
/// "What CI can and cannot prove"), so every caller that reasons about a scoring
/// reply — happy path or failure — is written against this fake instead, leaving the
/// real client thin and decision-free.
///
/// Mirrors `FakeAnthropicAPIKeyStore`'s shape: a scripted outcome plus a record of
/// what was actually asked, so a test can assert on both what came back and on
/// exactly what reached the transport.
public final class FakeScoringModelInvoking: ScoringModelInvoking, @unchecked Sendable {
    /// What `reply(to:)` does on its next call.
    public enum Outcome {
        /// Return this string, as if it were the model's raw reply.
        case reply(String)
        /// Throw this error, as if the transport failed this way.
        case failure(ScoringModelError)
    }

    /// The outcome the next call to `reply(to:)` produces. A `var` rather than a
    /// fixed value at `init` so a single test can script a sequence — e.g. fail once
    /// with `.rateLimited`, then switch to a `.reply` before asserting a retry
    /// succeeds.
    public var outcome: Outcome

    /// Every instruction passed to `reply(to:)`, in call order. Lets a test assert
    /// on exactly what reached the transport — e.g. that a retry re-sent the same
    /// `subject` rather than a stale one — not just on how many times it was asked.
    public private(set) var receivedInstructions: [ScoringInstruction] = []

    /// Number of times `reply(to:)` has been called, for tests that only care about
    /// the count.
    public var callCount: Int { receivedInstructions.count }

    /// Defaults to a minimal, always-acceptable scoring reply — a score in the
    /// middle of the permitted 0...100 range with a short rationale under
    /// `RationaleContract.maximumCharacters` — so a caller that only cares about the
    /// transport being invoked, not about the specific answer, does not have to
    /// configure one. Callers that need the reply to land in a *specific* rubric
    /// band should still supply their own, since 50 will not fall inside every band.
    public init(outcome: Outcome = .reply(#"{"score": 50, "rationale": "Baseline fixture reply."}"#)) {
        self.outcome = outcome
    }

    public func reply(to instruction: ScoringInstruction) async throws -> String {
        receivedInstructions.append(instruction)
        switch outcome {
        case let .reply(text):
            return text
        case let .failure(error):
            throw error
        }
    }
}
