import Foundation

/// What the workout screen's chat card shows (MAX-098, MAX-186).
///
/// `WorkoutChatSectionView` reads exactly one of these three states and draws it. Which
/// one — and every string built around it — is decided here rather than in the view's
/// `body`, for the reason `ChatThreadListRow` already established for the thread list: a
/// card that decided "is there anything to preview" for itself would be a decision CI
/// cannot see.
public enum WorkoutChatCardState: Equatable, Sendable {
    /// No thread for this run yet, or one nobody has spoken in.
    case invitation
    /// The store could not be opened, or the read failed.
    case failed
    /// One line of the last visible turn, and when it happened.
    case lastExchange(preview: String, lastActivityAt: Date)
}

/// Resolves `WorkoutChatCardState` from the one stored read behind the card
/// (`ChatThreadRepository.mostRecentThread(for:)`), and the VoiceOver sentence for its
/// `.lastExchange` case.
///
/// ## Builds on `ChatThreadSummary`, rather than beside it
///
/// `preview` here is exactly `ChatThreadSummary`'s own field — already whitespace-
/// collapsed and truncated on a word boundary by that type's initializer. A card that
/// re-derived a preview from `thread.messages` by hand would be a second, and possibly
/// slightly different, notion of "the last thing said" next to the one the thread list
/// already shows for the same conversation (§2.3). Extending the existing type rather
/// than adding a parallel one is the whole of this type's job.
public enum WorkoutChatCardPresentation {

    /// - Parameter thread: the most recent thread for this run
    ///   (`ChatThreadRepository.mostRecentThread(for:)`), or nil when there is none.
    ///   A thread nobody has spoken in yet (`ChatThreadSummary.preview == nil`) reads
    ///   the same as no thread at all — both are the invitation, because neither has
    ///   anything to preview.
    public static func state(for thread: ChatThread?) -> WorkoutChatCardState {
        guard let thread else { return .invitation }
        guard let preview = ChatThreadSummary(thread).preview else { return .invitation }
        return .lastExchange(preview: preview, lastActivityAt: thread.lastActivityAt)
    }

    /// What VoiceOver reads for the `.lastExchange` state, as one sentence.
    ///
    /// - Parameter spokenTimestamp: the app layer's `RelativeDateTimeFormatter` output —
    ///   "3 hours ago" rather than the card's live-updating relative `Text`. Injected
    ///   rather than derived here for the reason `ChatThreadListRow
    ///   .accessibilityLabel(spokenTimestamp:)` gives its own equivalent parameter: that
    ///   formatter is locale-driven and OS-version-driven, and a core test asserting its
    ///   output would be asserting Foundation's behaviour on whichever platform CI
    ///   happened to run. The *sentence* is this type's decision; the phrase inside it is
    ///   the platform's.
    public static func accessibilityLabel(preview: String, spokenTimestamp: String) -> String {
        "Last message, \(spokenTimestamp). \(preview)"
    }
}
