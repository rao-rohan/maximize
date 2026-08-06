import Foundation

/// What the athlete reads when a plan proposal is rejected twice — the sibling of
/// `PlanProposalError.description`, which stays the words put back in front of the
/// model (MAX-158).
///
/// ## Why `PlanProposalError.description` is not screen text
///
/// It was written to be read by both: `PlanProposalInstruction(retryingAfter:)` appends
/// it to the retry as a correction, and `PlanDraftingNotice` used to carry it straight
/// onto the plan proposal card, unchanged, as the "deliberate exception" its own
/// documentation named. That was the right call for the retry and the wrong one for the
/// screen. A model told *"the reply left out `liftKind`, which the plan schema
/// requires"* can fix it — the sentence names the exact key a retry has to add. An
/// athlete told the same sentence is handed a field name and the word "schema" and has
/// no way to act on either: nothing on their screen is called `liftKind`, and there is
/// no schema for them to have gotten wrong. §4.5 already drew this line for the case
/// `PlanAuthoringError` covers — *"already has athlete-readable text"* — this type draws
/// it for the ten cases that only exist at the model boundary and that sentence cannot
/// reach.
///
/// So there are two renderings of one error, not one reworded string:
/// `PlanProposalError.description` keeps the wire vocabulary the retry needs, and this
/// type is the words the athlete gets instead. Two renderings rather than a second
/// `description`-shaped property on the same enum, for the reason this codebase already
/// prefers a sibling type over a sibling property: a second `String` sitting next to
/// `description` is a naming convention a call site can still get backwards — nothing
/// stops `error.description` from being read as though it, too, were safe to show, which
/// is exactly the defect this ticket exists to fix. A distinct type with its own name
/// (`PlanProposalErrorNotice`, not `PlanProposalError`) cannot be handed to a screen by
/// accident, because a screen wanting text has exactly one type here that offers any.
///
/// ## One case does not need a second sentence, and says why
///
/// `.rejectedByAuthoring(let authoringError)` is not rewritten here. `PlanAuthoringError`
/// was built for exactly this readership — its own documentation says its cases "say
/// what the athlete did and what to do instead," `FailureCopy` calls it "already
/// athlete-facing," and it never carries a field name, the word "JSON," or the word
/// "schema": a heart-rate cap out of range, an inverted threshold pair, a rest day with a
/// distance. Writing a second sentence for it here would be two descriptions of the same
/// plan-authoring rule, free to drift the moment one of them is edited and the other is
/// not — this codebase's stated reason for keeping one context builder and one set of
/// derived metrics (D2/D3) applies exactly as well to a rejection sentence. So this is
/// the single case that is one string serving two readers, and it earns that by already
/// being the athlete-facing rendering everywhere else it is used.
///
/// ## What every other case does
///
/// The remaining fourteen cases each get their own constant sentence — never
/// interpolated, matching `ChatFailureNotice`'s and `PlanDraftingNotice.transportMessage`'s
/// rule that a message keyed only by its case cannot let a value slip through it by
/// accident. None of them says what was structurally wrong (a missing key, an unknown
/// enum case, an object that failed to parse) in those terms; each says what is wrong
/// with the *plan* in words that match the vocabulary `PlanCopy` and the authoring
/// screen already use — a run kind, a lift kind, a muscle group, a rest day, a long-run
/// week — because that is the vocabulary the athlete can act on by rewording what they
/// asked for.
public struct PlanProposalErrorNotice: Hashable, Sendable {

    /// What the transcript shows, as part of a `.notice` row. Safe on screen by
    /// construction — see this type's rules.
    public let message: String

    private init(_ message: String) {
        self.message = message
    }

    /// The one mapping from `PlanProposalError` to words, exhaustive over every case
    /// with no `default` — so a case added to that enum is a compile error here rather
    /// than a silent fall-through to a generic apology.
    public static func notice(for error: PlanProposalError) -> PlanProposalErrorNotice {
        PlanProposalErrorNotice(message(for: error))
    }

    private static func message(for error: PlanProposalError) -> String {
        switch error {
        case .malformedResponse:
            return "Claude's reply couldn't be read as a plan."

        case .missingField:
            return "Claude's plan proposal left out something this app needs before it "
                + "can be saved."

        case .forbiddenField:
            return "Claude's plan proposal tried to set something only this app decides."

        case .unknownSessionKind:
            return "One of the days in Claude's plan asked for a kind of run this app "
                + "doesn't recognize."

        case .unknownWeekday:
            return "Claude's plan named a day of the week this app doesn't recognize."

        case .unknownLiftKind:
            return "One of the days in Claude's plan asked for a kind of lift this app "
                + "doesn't recognize."

        case .unknownMuscleGroup:
            return "Claude's plan named a muscle group this app doesn't recognize."

        case .weekIsNotOneSessionPerWeekday:
            return "Claude's plan didn't cover each day of the week exactly once."

        case .restDayIsNotEmpty:
            return "One of the rest days in Claude's plan also asked for a run, which a "
                + "rest day can't do."

        case .liftRestDayIsNotEmpty:
            return "One of the no-lift days in Claude's plan also carried lift details, "
                + "which a day with no lift can't do."

        case .malformedGoalTargetDay:
            return "The goal date in Claude's plan wasn't a date this app could read."

        case .longRunArcIsEmpty:
            return "Claude's plan didn't include a long-run progression to follow."

        case .longRunArcWeekNotPositive:
            return "Claude's plan numbered a long-run week in a way this app couldn't use."

        case .longRunArcOutOfOrder:
            return "The long-run progression in Claude's plan didn't stay in order from "
                + "one week to the next."

        case let .rejectedByAuthoring(authoringError):
            // Not rewritten — see this type's note on why one case is one sentence for
            // both readers.
            return authoringError.description
        }
    }
}
