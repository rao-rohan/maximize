import Foundation

/// Every way a chat turn can fail, turned into one sentence the athlete can act on and
/// one decision about whether asking again is worth it (MAX-152).
///
/// ## Why this exists
///
/// Before this ticket the transcript's failure text was
/// `ChatStreamError.description` for all but one case — a diagnostic string written for
/// a developer reading a value, not for a person reading a chat. It leaked HTTP status
/// codes ("(401)"), API vocabulary ("stop_reason: refusal") and, in the case the owner
/// actually hit on a device, the sentence *"The response was not a recognizable
/// streaming reply"*, which tells a person nothing they can do. `ChatStreamError` keeps
/// that `description` — it is the right text for a value's `CustomStringConvertible` —
/// and this type is what the screen shows instead.
///
/// ## The rules the copy follows
///
/// - **Say what happened, then what to do about it.** Every message below names the
///   thing that went wrong in ordinary words and, where there is an action, names it.
/// - **No codes, no enum names, no server prose.** `ChatStreamError` is already
///   documented as never carrying a response body, so nothing a server wrote can reach
///   here; this type additionally never prints the status number it was handed. A number
///   in a chat bubble is a dead end for the person reading it, and `ChatFailureNoticeTests`
///   asserts no message contains one.
/// - **Two failures that need different actions get different words.** "No key stored"
///   and "the stored key was rejected" are the sharpest case: one means *add* a key, the
///   other means *replace* one, and a single "check your API key" would send the athlete
///   to look at a key that is present and looks fine.
/// - **No health data, ever.** Nothing here interpolates a question, a reply, a workout
///   or a figure — every string below is a constant. That is what makes them safe on
///   screen and would make them safe in a log, which this app still does not write.
///
/// ## Retry, decided
///
/// **No failure retries itself. Not once, not on a timer, not in the background.** The
/// precedent in this codebase is `PlanProposalDrafting`, which permits exactly one
/// automatic retry — and it is deliberately *not* followed here, for the reason that
/// type's own documentation gives for its transport failures: its retry exists to put a
/// *correction* in front of the model when the reply's content could not be used, and
/// none of the failures below are content failures. There is nothing to correct in
/// "you are offline", so a second automatic call would be the same call, and a loop of
/// them is A14's named failure mode — spending the owner's credit without anybody asking.
///
/// So `offersRetry` gates an affordance the athlete taps, one call per tap, exactly like
/// `send()` and `draftPlan()`. Its value comes from `ChatStreamError.isWorthRetrying`,
/// which already owns the transient/permanent split: a failure that needs a key changed,
/// a question reworded, or a bug fixed in this app offers no retry, because a button that
/// re-runs a call guaranteed to fail identically is worse than no button.
public struct ChatFailureNotice: Hashable, Sendable {

    /// What the transcript shows, as a `.notice` row. Safe on screen by construction —
    /// see this type's rules.
    public let message: String

    /// Whether the surface offers "Try again" for this failure. See this type's retry
    /// note: never automatic, and false wherever asking again unchanged cannot help.
    public let offersRetry: Bool

    private init(_ message: String, offersRetry: Bool) {
        self.message = message
        self.offersRetry = offersRetry
    }

    // MARK: - The stream failed

    /// The one mapping from `ChatStreamError` to words, exhaustive over every case with
    /// no `default` — so adding a case to that enum is a compile error here rather than
    /// a silent fall-through to a generic apology.
    ///
    /// - Parameter subject: what the thread is about, for the one message that has to
    ///   name it. `nil` while a thread-id-opened model has not resolved a subject yet,
    ///   which `ChatConversationCopy` handles the same way.
    public static func notice(
        for error: ChatStreamError,
        subject: ChatSubjectKind?
    ) -> ChatFailureNotice {
        ChatFailureNotice(message(for: error, subject: subject), offersRetry: error.isWorthRetrying)
    }

    private static func message(for error: ChatStreamError, subject: ChatSubjectKind?) -> String {
        switch error {
        case .noAPIKeyStored:
            return noAPIKeyStored(for: subject)

        case .keyStoreUnavailable:
            // Deliberately not "add a key": one is stored, and telling someone to add
            // what they already added is how a keychain problem becomes a loop.
            return "Your saved Anthropic key could not be read from the keychain. "
                + "Open Settings and enter it again."

        case .requestFailed:
            return "Claude could not be reached. Check your connection, then try again."

        case .timedOut:
            return "Claude did not start replying in time. Try again — this usually clears on its own."

        case .invalidAPIKey:
            // The sharpest of the four key states, and the reason it is worded around
            // *replacing* rather than checking: the key is present and looks fine, so
            // "check your key" sends the athlete to stare at something correct-looking.
            return "Anthropic rejected the saved key. Enter a current one in Settings — "
                + "the key stored here is either wrong or has been revoked."

        case .rateLimited:
            return "You have asked Anthropic for too much too quickly. Wait a minute, then try again."

        case .serverUnavailable:
            // The status code is not printed. It is diagnostics for a developer reading
            // the value, and a number in a chat bubble is a dead end for a reader.
            return "Anthropic is having trouble at their end. Nothing is wrong with your key "
                + "or your data — try again in a moment."

        case .unexpectedStatus:
            return "Anthropic turned this request down and this app cannot say why. "
                + "Asking again will not help; this one is a fault to fix in the app."

        case .refused:
            return "Claude declined to answer this one. Rewording the question is more likely "
                + "to help than asking the same thing again."

        case .interrupted:
            // The one message that describes what happened to text already on screen.
            // Constraint #4 keeps that text; saying so is what stops a partial reply
            // reading as a complete one.
            return "The connection dropped before the reply finished. Whatever arrived is kept "
                + "above — asking again starts a new answer rather than resuming this one."

        case .midStreamFailure:
            return "Anthropic hit a problem part-way through the reply. Try again in a moment."

        case .unreadableResponse:
            // The device report behind MAX-107 surfaced as "The response was not a
            // recognizable streaming reply", which is the exact sentence this ticket was
            // told to do better than. What a person needs to know is that their data is
            // fine and that trying again is not the fix.
            return "Claude's reply arrived in a shape this app could not read. Nothing of yours "
                + "was lost, and asking again will not change it — this one is a fault to fix in the app."
        }
    }

    /// FR-2.4's ordinary day-one state, worded from the subject.
    ///
    /// **These three sentences are `ChatModel.userFacingMessage(for:)`'s, verbatim.**
    /// They shipped, they are right, and this ticket moved them rather than writing a
    /// second set — "worded from the subject, because 'this workout' is a lie on a thread
    /// about a month" is the reasoning that put them there and it is unchanged.
    private static func noAPIKeyStored(for subject: ChatSubjectKind?) -> String {
        switch subject {
        case .workout:
            return "Add an Anthropic API key in Settings to chat about this workout."
        case .training:
            return "Add an Anthropic API key in Settings to chat about your training."
        case nil:
            return "Add an Anthropic API key in Settings to chat."
        }
    }

    // MARK: - The turn failed without the stream failing

    /// The request worked and the reply was empty (`ChatReplyPhase.emptyReply`).
    ///
    /// Its own notice rather than being folded into `.interrupted`: nothing dropped, so a
    /// sentence about a dropped connection would be a lie, and the athlete would go
    /// looking at their signal for a fault that is not there.
    public static let emptyReply = ChatFailureNotice(
        "Claude finished without saying anything. Try again — that usually clears it.",
        offersRetry: true
    )

    /// The reply arrived and could not be written to the thread — a storage failure, not
    /// a transport one.
    ///
    /// The reply stays on screen (`ChatModel` keeps it), so the honest thing to say is
    /// what happens to it next: the transcript and the store now disagree, and the store
    /// is what survives closing the sheet. No retry: asking Claude again would not fix a
    /// write, and would spend a call on a problem that is not Claude's.
    public static let couldNotSaveReply = ChatFailureNotice(
        "This reply arrived but could not be saved. It is above for now, and it will be gone "
            + "when you close this conversation.",
        offersRetry: false
    )

    /// The message could not be turned into a request at all — an empty question, or a
    /// transcript this app could not assemble. Unreachable in practice (`canSend` has
    /// already refused an empty composer) and worded rather than left as a crash.
    ///
    /// No retry: nothing was sent, so there is nothing to send again — the question is
    /// still the athlete's to reword.
    public static let couldNotSendMessage = ChatFailureNotice(
        "That message could not be sent. Try rewording it and sending it again.",
        offersRetry: false
    )
}
