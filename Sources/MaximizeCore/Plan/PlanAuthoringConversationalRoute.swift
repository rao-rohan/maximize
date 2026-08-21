import Foundation

/// Whether the plan-authoring screen's conversational route can be offered right now, and
/// what the screen says about it either way (MAX-166).
///
/// ## What this is a door to, and what it is not
///
/// `ChatConversationView` already ships "Draft a plan from this conversation" (MAX-101) —
/// this type builds nothing new there. FIRST-RUN-SPEC §10 argues at length that a
/// conversational *first run* is the wrong build, and settles on the one place a
/// conversational route does belong: "the authoring screen is where the conversational
/// route should be offered, since that is where a person who dislikes the form is
/// standing." §13 decision 5 makes it concrete — "Offer it, from the authoring screen
/// only, gated on a stored key." This type is that gate. It decides nothing about the
/// conversation itself, only whether the door to it is open.
///
/// ## Why the gate is a key, not a plan or a workout
///
/// The conversational route ends in a Claude call the moment the athlete describes
/// anything (`ChatModel.draftPlan()`), and every client of `AnthropicAPIKeyStoring` fails
/// identically without a key. Nothing else this screen already knows — whether a plan is
/// being revised, how much history is stored — changes whether that call can succeed, so
/// nothing else belongs in this gate.
///
/// ## `.unknown` reads as available, matching `StoredAPIKeyPresence.permitsClearing`
///
/// A Keychain read that failed is not evidence that no key is stored. `FirstRunChecklist`
/// makes the identical call for its own "add a key" step (see that type's own comment: a
/// first-run card built on a failed read "would be a second voice on one fact, and a nag
/// built on a guess"), and Settings' own **Clear** button is offered on the same two
/// cases for the same reason (`StoredAPIKeyPresence.permitsClearing`). So this affordance
/// stays enabled on `.unknown`; if a key genuinely is not there, the conversation itself
/// says so once a call is attempted — `ChatFailureNotice.noAPIKeyStored(for:)` already
/// owns that sentence, and this type does not duplicate it.
///
/// ## Never a hidden button
///
/// CLAUDE.md: "Absence is a designed state." `isAvailable == false` does not mean "draw
/// nothing" — the view still renders the action, disabled, with `explanation` underneath
/// stating why, the same way every other absence in this app gets real copy rather than a
/// control that silently stops appearing.
///
/// ## Bounding the loop with `ChatSheet` (MAX-190, `docs/CHAT-AUDIT.md` §2.6)
///
/// This screen is reachable two ways: directly (Plan tab, Settings, Workouts — no
/// proposal), or pushed by `ChatSheet` itself, prefilled from an accepted proposal
/// (MAX-101). The second case is already standing inside a conversation this exact
/// button would reopen — tapping it presented a second `ChatSheet` on top of the first,
/// and if *that* one's own proposal were accepted, a third, unbounded. `arrivedFromConversation`
/// is what tells this screen which case it is in, and it wins outright over
/// `apiKeyPresence`: a stored key does not make reopening the conversation you are
/// already inside a sensible action. The screen still renders the button, disabled, with
/// `explanation` naming the way back — Back, not a second door — matching this type's own
/// "never a hidden button" rule above. Nothing else about the gate changes: the ordinary,
/// direct-authoring path still reads `apiKeyPresence` exactly as before.
public struct PlanAuthoringConversationalRoute: Hashable, Sendable {

    /// Whether the action should be enabled. `false` for `.notStored`, and for
    /// `arrivedFromConversation == true` regardless of `apiKeyPresence`.
    public let isAvailable: Bool

    /// What the screen says under the action, in either state — never empty, and never
    /// dependent on which of `.stored`/`.unknown` produced `isAvailable == true`, so
    /// nothing here claims to know more about the key than `StoredAPIKeyPresence` does.
    public let explanation: String

    /// - Parameters:
    ///   - apiKeyPresence: whether a Claude call could succeed at all. Ignored when
    ///     `arrivedFromConversation` is true — see this type's own "Bounding the loop".
    ///   - arrivedFromConversation: true exactly when this authoring screen was pushed by
    ///     `ChatSheet` from an accepted proposal, rather than opened directly. Fixed for
    ///     the screen's whole lifetime — `PlanAuthoringModel` snapshots it once at `init`
    ///     from `proposal != nil` rather than reading the mutable `proposal` property
    ///     each time, precisely so a successful `save()` (which clears `proposal`) does
    ///     not reopen this door. Defaults to `false`, the ordinary case of an athlete
    ///     opening this screen by hand.
    public init(apiKeyPresence: StoredAPIKeyPresence, arrivedFromConversation: Bool = false) {
        if arrivedFromConversation {
            isAvailable = false
            explanation = PlanAuthoringConversationalRoute.arrivedFromConversationExplanation
            return
        }
        switch apiKeyPresence {
        case .stored, .unknown:
            isAvailable = true
            explanation = PlanAuthoringConversationalRoute.availableExplanation
        case .notStored:
            isAvailable = false
            explanation = PlanAuthoringConversationalRoute.unavailableExplanation
        }
    }

    /// FIRST-RUN-SPEC §12: "or describe it in a conversation." Stated as what happens,
    /// matching `PlanProposalReview.acceptTitle`'s own register — a name for the action,
    /// not a question.
    public static let actionLabel = "Describe it in a conversation"

    /// A13/CHAT-FIRST §2.5, restated for this door: chat cannot write here either. Worded
    /// as the boundary rather than the outcome, matching `PlanProposalReview
    /// .acceptExplanation`'s own shape for the same reason — an athlete who reads this and
    /// taps knows they are opening a conversation, not saving anything.
    static let availableExplanation =
        "Opens a conversation where you describe the plan you want instead of filling in "
            + "the fields below. Chat still ends at this screen — nothing is saved until you "
            + "review it here and save it yourself."

    /// Matches `ChatFailureNotice.noAPIKeyStored(for:)`'s own phrasing ("Add an Anthropic
    /// API key in Settings to chat about…") rather than writing a second sentence about
    /// the same fact.
    static let unavailableExplanation =
        "Add an Anthropic API key in Settings to describe a plan in a conversation."

    /// MAX-190: this screen was reached from the conversation this button would reopen.
    /// Names the way back rather than repeating `availableExplanation`'s "opens a
    /// conversation" — that sentence would read as an offer to open a second one.
    static let arrivedFromConversationExplanation =
        "This form came from the conversation you were just in. Go back to keep "
            + "describing changes there, rather than opening another one."
}
