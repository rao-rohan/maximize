import Foundation

/// Why a plan could not be drafted from a conversation, in words the athlete can act on
/// (CHAT-FIRST-SPEC.md §4.5, MAX-101).
///
/// Three cases, because there are three genuinely different things to say. A transport
/// failure is about the network or the key and says nothing about the plan; a rejected
/// proposal is about what the model wrote and is the one the athlete should read
/// verbatim; and a request that could not be assembled at all is about the conversation
/// being too thin to draft from.
///
/// **Carries no health data and no raw reply.** `PlanProposalModelError` is documented as
/// never carrying a response body, and `PlanProposalError` as never carrying the fact
/// sheet or the model's text — so `description` is safe to put on screen, which is
/// exactly what §4.5 step 2 asks for.
public enum PlanDraftingFailure: Error, Hashable, Sendable, CustomStringConvertible {

    /// The call never produced a reply: no key, no network, a status, a refusal.
    case transport(PlanProposalModelError)

    /// Two replies in a row could not be used. Carries the **second** rejection, not the
    /// first: the first has already been shown to the model as a correction it failed to
    /// act on, so the second is what is actually true about the proposal in hand.
    case rejected(PlanProposalError)

    /// There was nothing to ask with — an empty transcript, or a transcript that does
    /// not open with the athlete. Not a model failure at all; the conversation simply is
    /// not one a plan can be drafted from yet.
    case nothingToDraftFrom

    public var description: String {
        switch self {
        case .transport(.noAPIKeyStored):
            // Worded like `ChatModel.userFacingMessage(for:)`'s own no-key sentence:
            // pointed at the fix rather than left as a diagnostic.
            return "Add an Anthropic API key in Settings to draft a plan from this conversation."
        case let .transport(error):
            return "The plan could not be drafted. \(error.description)."
        case let .rejected(error):
            return "Claude's plan was not one this app could use, twice: \(error.description) "
                + "Nothing has changed — say what you want and ask again."
        case .nothingToDraftFrom:
            return "Say what you want the plan to do first — a plan is drafted from the "
                + "conversation, and there is nothing here to draft from yet."
        }
    }
}

/// The result of one **tap** on "Draft a plan from this conversation".
public enum PlanDraftingOutcome: Hashable, Sendable {
    case proposed(PlanProposal)
    case failed(PlanDraftingFailure)
}

/// §4.5's retry policy: **one automatic retry, never two, and only for a content
/// failure** (MAX-101).
///
/// ## Why the number is one
///
/// §4.5 argues both ends of it. Zero retries throws away a recoverable failure: the
/// errors `PlanProposal.parse` produces were deliberately written specific enough to
/// correct — "monday is not a session kind", "the week has to name each of the seven
/// weekdays exactly once" — and `PlanProposalInstruction(factSheet:turns:retryingAfter:)`
/// exists solely to put that sentence back in front of the model. A loop is worse:
/// *"a loop burning the owner's tokens against a model that keeps proposing a 400 bpm
/// cap is the failure mode to design against."* One is the only number that is neither.
///
/// ## Why a transport failure is not retried here
///
/// A14 bounds cost by making plan drafting *one call per tap*, and a transport failure —
/// offline, rate limited, no key — is not a failure of the proposal's content, so the
/// correction §4.5 describes has nothing to say to it. `PlanProposalModelError` carries
/// its own `isWorthRetrying` for callers that want to reason about that, and its
/// documentation says so explicitly: *"§4.5's retry is orthogonal to this."* An athlete
/// whose network dropped taps again; the app does not decide on their behalf to spend a
/// second call, and never spends one on a timer (A14).
///
/// ## Where the policy lives
///
/// Here, in the core, under test — not in the view model that calls it and not in the
/// transport. `PlanProposalInstruction` owns *what to say* when making a retry (that is
/// prompt text, and its doc comment claims that split explicitly); this owns *how many
/// times to ask*.
public enum PlanProposalDrafting {

    /// One seed attempt plus at most one correction. Public so a test can assert the
    /// policy by name rather than by counting to two.
    public static let maximumAttempts = 2

    /// Asks the model for a proposal, correcting it once if the first reply cannot be
    /// used.
    ///
    /// - Parameters:
    ///   - model: the transport (`AnthropicPlanProposalClient` in the app,
    ///     `FakePlanProposalModelInvoking` in tests). Called at most
    ///     `maximumAttempts` times, and only because the athlete tapped (A14).
    ///   - factSheet: `PromptContext.factSheet()`, verbatim — the one context builder's
    ///     output and the only part of the request carrying PII (D3, A12 rule 1).
    ///     Nothing here reads a workout, a plan or a score.
    ///   - turns: the conversation the plan is drafted from, oldest first.
    ///
    /// - Returns: the proposal, or the failure to state in the transcript. Deliberately
    ///   not `throws`: every one of these outcomes is an ordinary product state with a
    ///   sentence attached, and a caller that has to remember to catch is a caller that
    ///   can forget to say anything.
    public static func proposal(
        from model: any PlanProposalModelInvoking,
        factSheet: String,
        turns: [ChatTurn]
    ) async -> PlanDraftingOutcome {
        var previousFailure: PlanProposalError?

        for _ in 1...maximumAttempts {
            let instruction: PlanProposalInstruction
            do {
                instruction = try PlanProposalInstruction(
                    factSheet: factSheet,
                    turns: turns,
                    retryingAfter: previousFailure
                )
            } catch {
                // `PlanProposalInstruction` refuses an empty fact sheet and a transcript
                // that does not open with the athlete. Neither becomes truer on a second
                // attempt, so this returns rather than continuing the loop.
                return .failed(.nothingToDraftFrom)
            }

            let reply: String
            do {
                reply = try await model.reply(to: instruction)
            } catch let error as PlanProposalModelError {
                return .failed(.transport(error))
            } catch {
                // The protocol does not constrain what an implementation throws. An
                // unrecognised error is reported as the transport failing in a way this
                // app cannot name, rather than as a fault in the model's plan.
                return .failed(.transport(.requestFailed))
            }

            do {
                return .proposed(try PlanProposal.parse(reply))
            } catch let error as PlanProposalError {
                guard previousFailure == nil else {
                    // Second content failure. §4.5 step 2: the athlete sees the error
                    // text and the authoring screen stays where MAX-080 already puts it.
                    return .failed(.rejected(error))
                }
                previousFailure = error
            } catch {
                // `PlanProposal.parse` throws nothing else. Handled rather than assumed
                // impossible, and treated as the content failure it would have to be.
                guard previousFailure == nil else {
                    return .failed(.rejected(.malformedResponse(reason: "the reply could not be read")))
                }
                previousFailure = .malformedResponse(reason: "the reply could not be read")
            }
        }

        // Unreachable: the loop either returns or sets `previousFailure`, and the second
        // iteration returns unconditionally. Stated as the failure it would be rather
        // than as a `fatalError`.
        return .failed(.rejected(previousFailure ?? .malformedResponse(reason: "no reply was usable")))
    }
}
