import Foundation

/// What the transcript shows for a `PlanDraftingFailure` — the mirror of
/// `ChatFailureNotice`, for the door §4.5 calls "draft a plan from this conversation"
/// rather than for `send()` (MAX-155).
///
/// ## Why this exists
///
/// `PlanDraftingFailure.description` was written, in its own doc comment, to be the
/// on-screen text: *"`description` is safe to put on screen, which is exactly what
/// §4.5 step 2 asks for."* That claim was wrong for exactly the case that matters most.
/// `.transport(error)` interpolated `PlanProposalModelError.description` verbatim, and
/// that type — like `ChatStreamError` before MAX-152 — carries a bare HTTP status
/// number in two of its cases for a debugger's benefit. The result was a plan proposal
/// card reading *"The plan could not be drafted. The Anthropic API returned an
/// unexpected status (400)."*, the defect MAX-154's audit found and this ticket fixes.
///
/// `PlanDraftingFailure.description` is left exactly as it is (payload and all): the
/// codebase's standing rule, stated in `ChatFailureNotice`'s own documentation and in
/// `FailureCopy`'s, is that a `CustomStringConvertible` diagnostic on an `Error` type
/// stays a diagnostic — read in a debugger, never rendered — and the fix for a
/// diagnostic reaching a screen is a second type for the screen, not a rewrite of the
/// first. This is that second type. `ChatModel.noteDraftingFailure` is the only call
/// site, and it now reads `.message` here instead of `.description`.
///
/// ## Sibling to `ChatFailureNotice`, not folded into it
///
/// `ChatFailureNotice`'s own documentation calls it "the one mapping from
/// `ChatStreamError` to words, exhaustive over every case" — a claim that is true only
/// because it maps exactly one input type. `PlanDraftingFailure` is not a
/// `ChatStreamError`: it wraps `PlanProposalModelError` for a transport failure and
/// `PlanProposalError` for a rejected proposal, two types `ChatStreamError` knows
/// nothing about, so adding cases for them there would either force a third, unrelated
/// error type through `ChatFailureNotice`'s `notice(for:subject:)` signature or grow a
/// second entry point on the same type for a different input — both worse than a
/// sibling that keeps its own exhaustive switch. **A 400 from the drafting endpoint and
/// a 400 from the stream do warrant the same *words*** — both are `unexpectedStatus`,
/// both mean "this app built a request Anthropic rejected, and asking again unchanged
/// will not help" — but they are not the same *value*: `ChatStreamError.unexpectedStatus`
/// and `PlanProposalModelError.unexpectedStatus` are different types with different
/// case sets either side of it, so the sentence is written twice, once per type, the
/// same way `ChatFailureNotice` and this type each write their own `.noAPIKeyStored`
/// sentence rather than sharing a helper across two enums that happen to have a case by
/// that name.
///
/// ## The rules the copy follows
///
/// Identical to `ChatFailureNotice`'s, for the `.transport` mapping specifically:
///
/// - **Say what happened, then what to do about it.**
/// - **No status codes, no enum names, no server prose.** `PlanProposalModelError` never
///   carries a response body (see its own documentation), and this mapping additionally
///   never prints the status number it was handed.
/// - **No health data, ever.** Every `.transport` sentence below is a constant; the
///   fact sheet and the athlete's turns are never in reach of this mapping.
///
/// `.rejected` was carried through from `PlanProposalError.description` unchanged until
/// MAX-158, on the reasoning that it was "the one the athlete should read verbatim"
/// (MAX-101's own documentation). That reasoning held for the correction a retry needs
/// and did not hold for a screen: `description` speaks the wire vocabulary a model can
/// act on ("the reply left out `liftKind`, which the plan schema requires"), and a
/// person reading the same sentence is handed a field name and the word "schema" they
/// cannot do anything with. `PlanProposalErrorNotice` (`Plan/PlanProposalErrorNotice.swift`,
/// MAX-158, the file `PlanProposalError` now belongs to) is the second rendering that
/// keeps the correction channel untouched and gives the athlete a sentence built for
/// them instead — see that type's own documentation for why one case of it is still one
/// sentence for both readers.
///
/// ## Retry stays a button, unconditionally (MAX-152's rule)
///
/// Unlike `ChatFailureNotice`, this type has no `offersRetry`. `ChatModel` does not gate
/// "Draft a plan from this conversation" on the failure kind — the same button that
/// started the failed attempt is the only retry affordance, for every case, and tapping
/// it is what asks again. That already satisfies "a button the athlete presses, never
/// an automatic policy": there is no code path that re-drafts without a tap, so there is
/// no flag to compute. Adding one that nothing reads would be a second decision (this
/// failure "is not worth retrying") the button does not act on — dead weight, not
/// caution.
public struct PlanDraftingNotice: Hashable, Sendable {

    /// What the transcript shows, as a `.notice` row. Safe on screen by construction —
    /// see this type's rules.
    public let message: String

    private init(_ message: String) {
        self.message = message
    }

    /// The one mapping from `PlanDraftingFailure` to words, exhaustive over every case
    /// with no `default`.
    public static func notice(for failure: PlanDraftingFailure) -> PlanDraftingNotice {
        PlanDraftingNotice(message(for: failure))
    }

    private static func message(for failure: PlanDraftingFailure) -> String {
        switch failure {
        case let .transport(error):
            return transportMessage(for: error)
        case let .rejected(error):
            // `PlanProposalErrorNotice` is the athlete-facing rendering of `error`
            // (MAX-158); `error.description` itself stays the correction text a retry
            // needs and is never shown here.
            return "Claude's plan was not one this app could use, twice: "
                + "\(PlanProposalErrorNotice.notice(for: error).message) "
                + "Nothing has changed — say what you want and ask again."
        case .nothingToDraftFrom:
            return "Say what you want the plan to do first — a plan is drafted from the "
                + "conversation, and there is nothing here to draft from yet."
        }
    }

    /// The one mapping from `PlanProposalModelError` to words, exhaustive over every
    /// case with no `default` — so a case added to that enum is a compile error here
    /// rather than a silent fall-through to a generic apology, exactly the property
    /// `ChatFailureNotice.message(for:subject:)` keeps for `ChatStreamError`.
    private static func transportMessage(for error: PlanProposalModelError) -> String {
        switch error {
        case .noAPIKeyStored:
            // The same sentence `PlanDraftingFailure.description` already special-cased
            // — worded like `ChatFailureNotice`'s own no-key sentences, pointed at the
            // fix rather than left as a diagnostic.
            return "Add an Anthropic API key in Settings to draft a plan from this conversation."

        case .requestFailed:
            return "Claude could not be reached to draft this plan. Check your connection, "
                + "then try again."

        case .timedOut:
            return "Claude did not start drafting a plan in time. Try again — this usually "
                + "clears on its own."

        case .invalidAPIKey:
            // Worded around *replacing* the key, not checking it — the key is present
            // and looks fine, matching `ChatFailureNotice`'s reasoning for the same case.
            return "Anthropic rejected the saved key. Enter a current one in Settings — "
                + "the key stored here is either wrong or has been revoked."

        case .rateLimited:
            return "You have asked Anthropic for too much too quickly. Wait a minute, "
                + "then try again."

        case .serverUnavailable:
            // The status code is not printed — diagnostics for a developer reading the
            // value, and a dead end for a person reading a card.
            return "Anthropic is having trouble at their end. Nothing is wrong with your "
                + "key or your conversation — try again in a moment."

        case .unexpectedStatus:
            return "Anthropic turned this request down and this app cannot say why. "
                + "Asking again will not help; this one is a fault to fix in the app."

        case .refused:
            return "Claude declined to draft a plan from this conversation. Rewording what "
                + "you're asking for is more likely to help than asking again."

        case .truncated:
            return "Claude's plan was cut off before it finished. This is a fault to fix "
                + "in the app, not something asking again will change."

        case .unreadableResponse:
            return "Claude's reply arrived in a shape this app could not read. Nothing has "
                + "changed, and asking again will not fix it — this one is a fault to fix "
                + "in the app."
        }
    }
}
