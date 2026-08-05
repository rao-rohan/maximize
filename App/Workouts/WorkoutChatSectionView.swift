import SwiftUI
import MaximizeCore
import Observation

/// The chat section on the workout detail screen (FR-2.1).
///
/// ## MAX-098: this card lost its button, and gained something to say
///
/// It used to carry an "Open chat" button, and it was the only door into chat. The
/// persistent Ask control is that door now, on every screen including this one, where it
/// reads "Ask about this run" and opens exactly the thread this button used to open.
/// Two chat buttons on one screen, six inches apart, opening the same conversation is
/// worse than either alone (§2.1), so the button is gone.
///
/// What remains is what design review §4.4 asked this card to be: **a preview of the
/// last exchange, or the invitation copy.** A card that repeated the invitation forever
/// while a conversation existed behind it was the review's complaint — the screen never
/// showed that the run had already been discussed.
///
/// ## Why there is no loading state
///
/// The initial state *is* the invitation, and the read either replaces it with a real
/// last message or leaves it. That is honest rather than convenient: before anything is
/// known, "ask about this run" is exactly what this card has to say, and a spinner for a
/// single local read would be a worse answer to the same moment. A failed read says so
/// instead, in `ChatConversationCopy`'s wording.
///
/// No glass is applied: this is a content surface holding data (FR-4.2).
struct WorkoutChatSectionView: View {
    let workoutID: UUID

    @State private var model: WorkoutChatPreviewModel

    init(workoutID: UUID) {
        self.workoutID = workoutID
        _model = State(initialValue: WorkoutChatPreviewModel(
            workoutID: workoutID,
            chatThreadRepository: PersistenceComposition.store
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Chat")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .invitation:
            // The same string the empty transcript shows, from the same place — this
            // card is an invitation to the conversation the sheet opens, so the two
            // saying different things would be two voices for one idea.
            Text(ChatConversationCopy.emptyTranscriptInvitation(for: .workout))
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)

        case .failed:
            Text(ChatConversationCopy.failedToLoad(for: .workout))
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)

        case let .lastExchange(preview, lastActivityAt):
            VStack(alignment: .leading, spacing: Spacing.tight) {
                // Two lines rather than the list row's one: this card has the width of
                // the screen and no neighbours competing for it, and a reply cut after
                // a hundred characters mid-sentence is what makes a preview useless.
                Text(preview)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)

                Text(lastActivityAt, style: .relative)
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Last message, \(RelativeTimestampFormatting.spoken(lastActivityAt)). \(preview)"
            )
        }
    }
}

/// The one stored read behind the card above: the most recent thread for this run, and
/// the last line of it if there is one.
///
/// Nothing here decides copy. Whether a thread has anything worth previewing is
/// `ChatThreadSummary`'s answer — including *how* the line is collapsed and truncated —
/// so the preview on this card and the preview on the same thread's row in §2.3's list
/// are the same text produced by the same function, not two views that both shorten a
/// string.
@MainActor
@Observable
final class WorkoutChatPreviewModel {

    enum State: Equatable {
        /// Nothing known yet, or nothing to show: no thread for this run, or one nobody
        /// has spoken in.
        case invitation
        /// The store could not be opened, or the read failed — mirrors every sibling
        /// view's `.failed`.
        case failed
        case lastExchange(String, Date)
    }

    private(set) var state: State = .invitation

    private let workoutID: UUID
    private let chatThreadRepository: (any ChatThreadRepository)?

    /// - Parameter chatThreadRepository: supplied explicitly, with nil meaning "no
    ///   store" rather than this type resolving one for itself — `ChatThreadListModel`
    ///   and `ChatModel` both take it the same way, for MAX-049's reason.
    init(workoutID: UUID, chatThreadRepository: (any ChatThreadRepository)?) {
        self.workoutID = workoutID
        self.chatThreadRepository = chatThreadRepository
    }

    func load() async {
        guard let chatThreadRepository else {
            state = .failed
            return
        }
        do {
            guard let thread = try await chatThreadRepository.mostRecentThread(
                for: .workout(workoutID)
            ) else {
                state = .invitation
                return
            }
            // `workoutFacts` is only ever used to derive a *title*, which this card does
            // not show — the screen it sits on is already the run.
            guard let preview = ChatThreadSummary(thread).preview else {
                state = .invitation
                return
            }
            state = .lastExchange(preview, thread.lastActivityAt)
        } catch {
            state = .failed
        }
    }
}
