import Foundation

/// Subject-dependent copy for the conversation surface itself — what it says before the
/// athlete has typed anything, and what it says if it could not load at all.
///
/// Mirrors `ChatModel.userFacingMessage(for:)`'s established pattern: "worded from the
/// subject, because 'this workout' is a lie on a thread about a month." That reasoning
/// covers the "no key stored" notice already; this covers the other two places a
/// thread's subject decides what a person reads before a reply has ever arrived —
/// absence, in CLAUDE.md's sense, is a designed state, and a training thread's absence
/// copy is not the workout copy with a word swapped in a view.
///
/// **The workout strings are pinned exactly as `WorkoutChatView` wrote them before this
/// ticket** — MAX-097 generalises the surface, not its wording for the path that already
/// shipped.
///
/// ## Why every function below takes an optional kind (MAX-097 review)
///
/// A model opened by thread id (`ChatModel.init(threadID:...)`, §2.3) can be `.failed`
/// or mid-`.loading` before its subject has ever been read off the stored thread —
/// `ChatModel.subject` is `nil` in exactly that window. These three strings are the only
/// copy in this type that a nil subject can actually reach, so each one degrades to a
/// generic-but-honest fallback rather than forcing every call site to unwrap a value
/// that, in the one state each is actually shown for, is unreachable in practice but not
/// unreachable in the type.
public enum ChatConversationCopy {

    /// `ChatModel.LoadState.failed` — a repository was unavailable, the subject's
    /// records could not be read, or a context could not be assembled from them.
    public static func failedToLoad(for kind: ChatSubjectKind?) -> String {
        switch kind {
        case .workout: return "Chat could not be loaded for this workout."
        case .training: return "Chat could not be loaded for this training window."
        case nil: return "Chat could not be loaded."
        }
    }

    /// Shown in place of the transcript before the first message — never blank, per
    /// CLAUDE.md's "absence is a designed state."
    public static func emptyTranscriptInvitation(for kind: ChatSubjectKind?) -> String {
        switch kind {
        case .workout: return "Ask about this run — pacing, drift, whether it matched the plan."
        case .training: return "Ask about your training — volume, drift, whether the block is on plan."
        case nil: return "Ask a question to get started."
        }
    }

    /// The composer's placeholder text.
    public static func composerPlaceholder(for kind: ChatSubjectKind?) -> String {
        switch kind {
        case .workout: return "Ask about this run…"
        case .training: return "Ask about your training…"
        case nil: return "Ask a question…"
        }
    }

    /// `ChatModel.LoadState.threadNotFound` (§2.3) — a thread reached by id that no
    /// longer resolves to a stored thread, most often because it (or the workout it
    /// belonged to) was deleted from another screen. The subject is never known here —
    /// the lookup that would have supplied it is the lookup that just failed — so,
    /// unlike the three strings above, this one does not vary by kind.
    public static let threadNotFound = "This conversation no longer exists."

    // MARK: - MAX-150: the other two `ChatModel.LoadState` cases

    /// `ChatModel.LoadState.notYetScored` — a workout thread opened before its run has a
    /// score (FR-2.1 seeds chat from one). Ordinary, not a failure, and reached for a
    /// workout subject only.
    ///
    /// Moved here from `ChatConversationView` (MAX-150): it is chosen by the same
    /// `model.loadState` switch as `failedToLoad` and `threadNotFound` above, and having
    /// two of that switch's four cases in `MaximizeCore` and two as view literals was the
    /// inconsistency — one state machine, one voice, one place.
    public static let notYetScored =
        "This run hasn't been scored yet — chat opens once it has a score."

    /// `ChatModel.LoadState.noVerdict` (MAX-126) — the opposite tense of `notYetScored`:
    /// a lift is never scored (MAX-111), so there is no score coming for chat to wait on.
    public static let noVerdict =
        "The plan scores runs, so there's no score for this workout — and chat starts from one."

    // MARK: - MAX-150: `ChatModel.DisplayMessage`'s two flags

    /// `DisplayMessage.wasTruncated` — the reply ran out of the model's usable reply
    /// budget. Moved here for the same reason `notYetScored`/`noVerdict` were: the flag
    /// is a fact `ChatModel` already decided, and the sentence stating it belongs beside
    /// every other string that reads off that decision rather than inline in the bubble
    /// that draws it.
    public static let truncatedCaption = "Cut short — hit the reply length limit."

    /// `DisplayMessage.wasInterruptedByFailure` — a partial reply survived a dropped
    /// connection (constraint #4). See `truncatedCaption`'s own note.
    public static let interruptedByFailureCaption = "Connection dropped before this reply finished."
}
