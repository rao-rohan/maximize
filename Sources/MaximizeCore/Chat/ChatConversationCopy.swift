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
public enum ChatConversationCopy {

    /// `ChatModel.LoadState.failed` — a repository was unavailable, the subject's
    /// records could not be read, or a context could not be assembled from them.
    public static func failedToLoad(for kind: ChatSubjectKind) -> String {
        switch kind {
        case .workout: return "Chat could not be loaded for this workout."
        case .training: return "Chat could not be loaded for this training window."
        }
    }

    /// Shown in place of the transcript before the first message — never blank, per
    /// CLAUDE.md's "absence is a designed state."
    public static func emptyTranscriptInvitation(for kind: ChatSubjectKind) -> String {
        switch kind {
        case .workout: return "Ask about this run — pacing, drift, whether it matched the plan."
        case .training: return "Ask about your training — volume, drift, whether the block is on plan."
        }
    }

    /// The composer's placeholder text.
    public static func composerPlaceholder(for kind: ChatSubjectKind) -> String {
        switch kind {
        case .workout: return "Ask about this run…"
        case .training: return "Ask about your training…"
        }
    }
}
