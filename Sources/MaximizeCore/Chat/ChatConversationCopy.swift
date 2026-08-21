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
    /// a ride, a hike or a walk is never scored, so there is no score coming for chat to
    /// wait on. **Not a lift, since MAX-168** — that one waits, and reads `notYetScored`.
    ///
    /// The sentence stopped saying *"the plan scores runs"* for the same reason: it is now
    /// the wrong half of the truth, since the plan also scores lifts. What it says instead
    /// is the thing that is actually true of every workout that reaches this state.
    public static let noVerdict =
        "The plan has no rule for this kind of workout, so there's no score — and chat starts from one."

    // MARK: - `ChatModel.DisplayMessage`'s flags (MAX-150, MAX-197)

    /// `DisplayMessage.wasTruncated` — the reply ran out of the model's usable reply
    /// budget. Moved here for the same reason `notYetScored`/`noVerdict` were: the flag
    /// is a fact `ChatModel` already decided, and the sentence stating it belongs beside
    /// every other string that reads off that decision rather than inline in the bubble
    /// that draws it.
    public static let truncatedCaption = "Cut short — hit the reply length limit."

    /// `DisplayMessage.wasInterruptedByFailure` — a partial reply survived a dropped
    /// connection (constraint #4). See `truncatedCaption`'s own note.
    public static let interruptedByFailureCaption = "Connection dropped before this reply finished."

    /// `DisplayMessage.wasStoppedByAthlete` — the athlete stopped this reply and what had
    /// arrived by then is still on screen (MAX-197, §6.4).
    ///
    /// **The second sentence is the one that earns its place.** A stopped turn is never
    /// written to the thread — `ChatModel`'s "only completed turns are persisted" rule
    /// covers it exactly as it covers a dropped connection — so this text will not be
    /// here after the sheet closes. The athlete cannot know that by looking, and
    /// `couldNotSaveReply` already sets the precedent for saying it plainly rather than
    /// letting somebody discover it when they come back.
    ///
    /// Says nothing about *why* it stopped: the athlete is the reason, and an app
    /// explaining a person's own tap back to them is the "never restate a fact the
    /// surface already stated" rule broken from the other end.
    public static let stoppedByAthleteCaption =
        "You stopped this reply. It stays here until you close this conversation."

    /// The `.notice` row for a reply stopped before one token of it had arrived
    /// (MAX-197) — the case where there is no bubble for `stoppedByAthleteCaption` to sit
    /// under, and where a blank under the question would otherwise be the whole answer.
    ///
    /// Absence as a designed state, in CLAUDE.md's sense: the app knows this happened, so
    /// it says so.
    public static let stoppedBeforeAnyReplyArrived =
        "You stopped this reply before any of it arrived."

    // MARK: - MAX-152: the rungs of `ChatReplyPhase`

    /// What the transcript says *in place of* a reply that has not arrived yet, and the
    /// text the waiting animation is drawn over.
    ///
    /// Its existence is the point. CLAUDE.md's "no information carried by hue alone"
    /// generalises: a state carried only by an animation is a state that vanishes under
    /// Reduce Motion, and a shimmer with nothing underneath it is exactly that. The words
    /// are the channel; the sweep is decoration on top of the words, which is also how
    /// Claude's own interface does it.
    ///
    /// Not worded from the subject, unlike the three strings at the top of this file:
    /// "waiting for a reply" is the same fact on a run thread and a training thread, and
    /// two sentences that differ in no useful way are two sentences to keep in step for
    /// nothing.
    public static let awaitingFirstReply = "Thinking…"

    /// `ChatReplyPhase.stalled` — the reply started, stopped, and the connection is still
    /// open.
    ///
    /// Worded to say the two things a person actually wants at that moment: nothing is
    /// broken, and nothing is being asked of them. It deliberately does not offer an
    /// action — there is nothing useful to do while a stream is quiet, and a button that
    /// abandons a reply that is about to resume would be a worse outcome than waiting.
    public static let replyStalled = "Still connected — nothing new for a moment."

    /// The line shown beneath or in place of the pending reply, or nil where the reply
    /// itself is the statement.
    ///
    /// `.streaming` is the nil that matters: once the first token lands, the words on
    /// screen say everything a status line could, and leaving an indicator beside them
    /// would be the app talking over its own answer. That is the ladder's second rung
    /// stated as copy — waiting ends when text begins.
    public static func pendingStatus(for phase: ChatReplyPhase) -> String? {
        switch phase {
        case .awaitingFirstToken: return awaitingFirstReply
        case .stalled: return replyStalled
        case .streaming, .idle, .complete, .truncated, .emptyReply, .stopped, .failed: return nil
        }
    }

    /// What VoiceOver reads for the pending-reply row, for each of the three live rungs.
    ///
    /// Separate from `pendingStatus(for:)` because the two differ for `.streaming`: there
    /// is no visible status while text arrives, but a person who cannot see the text
    /// arriving still needs to be told that it is. Terminal rungs are absent on purpose —
    /// each has already produced a row that says what happened (a reply bubble, its
    /// truncated caption, or a `ChatFailureNotice`), and announcing a second sentence
    /// about a row already on screen is the "never restate a fact the surface already
    /// stated" rule from MAX-150's voice.
    public static func pendingAccessibilityLabel(for phase: ChatReplyPhase) -> String? {
        switch phase {
        case .awaitingFirstToken: return "Waiting for Claude's reply."
        case .streaming: return "Claude is replying."
        case .stalled: return "Still connected. Waiting for more of the reply."
        case .idle, .complete, .truncated, .emptyReply, .stopped, .failed: return nil
        }
    }

    /// The action offered on a failure that is worth asking again
    /// (`ChatReplyPhase.offersRetry`). One tap, one call — see `ChatFailureNotice`'s
    /// retry note for why nothing here is automatic.
    public static let retryAction = "Try again"

    /// What that action does, for VoiceOver — said as a fact about cost, because a
    /// person cannot see that this is the app's only path to spending another call.
    public static let retryActionHint = "Asks Claude the same question again."

    // MARK: - MAX-191: transcript cap notice

    /// A note shown when earlier messages of the conversation are not replayed to the
    /// model, so the athlete knows why the response might not reference them.
    ///
    /// Returns nil when the dropped count is zero — a "0 earlier messages" line is noise.
    /// The core decides whether there is anything to say, so a view need never
    /// `if count > 0` on its own.
    ///
    /// - Parameter droppedMessageCount: how many messages are not replayed. When zero or
    ///   negative, this returns nil.
    /// - Returns: a one-line notice naming the count, or nil if there is nothing to say.
    ///
    /// The fact that a conversation is capped reads the same regardless of subject, so
    /// this function does not branch on kind. It states what is true for both: earlier
    /// messages won't reach the model, stated in the app's voice.
    public static func droppedTurnsNotice(droppedMessageCount: Int) -> String? {
        guard droppedMessageCount > 0 else { return nil }
        let messageWord = droppedMessageCount == 1 ? "message" : "messages"
        return "\(droppedMessageCount) earlier \(messageWord) aren't included in what Claude sees."
    }
}
