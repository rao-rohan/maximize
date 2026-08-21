import SwiftUI
import MaximizeCore
import Observation

/// The chat section on the workout detail screen (FR-2.1).
///
/// ## MAX-098: this card lost its button, and MAX-186 gave it back
///
/// MAX-098 removed the card's "Open chat" button on the argument that the persistent
/// Ask control was the app's one door into chat, and two buttons on one screen opening
/// the same conversation was worse than either alone (§2.1). What that removal missed:
/// **the card still reads as tappable.** A surface showing your last message and its
/// timestamp is exactly the shape a person expects to tap, and having nothing happen is
/// its own, worse defect — the audit that reopened this (`docs/CHAT-AUDIT.md` §2.2)
/// found the card had no tap target of any kind.
///
/// The reconciliation is not "pick one door" — it is that this card was never a second
/// *button*, it is a **preview with an affordance**. It already carries data the Ask
/// control does not (the last exchange, when it happened); making it open the same
/// thread the Ask control would have opened is completing what it already implies,
/// not duplicating a control that says nothing.
///
/// So the whole card is now a button. It opens exactly the thread the persistent Ask
/// control opens for this screen — `ChatSheet(subject: .workout(workoutID))`, the same
/// route `ChatEntryPoint.resolve(focus:currentInterval:)` resolves to when a workout
/// detail screen is focused — rather than inventing a second way to reach a thread.
/// `PlanAuthoringView`'s own conversational-route sheet (MAX-166) already presents
/// `ChatSheet` locally rather than only from `RootTabView`; this follows the same
/// precedent.
///
/// ## What remains is what design review §4.4 asked this card to be
///
/// **A preview of the last exchange, or the invitation copy.** A card that repeated the
/// invitation forever while a conversation existed behind it was the review's original
/// complaint — the screen never showed that the run had already been discussed. That
/// half of the design is unchanged; only "and now it opens, and now it notices" is new.
///
/// ## Refreshing when the sheet dismisses
///
/// `.task` (below) fires on this view's first appearance and never again — returning
/// from a sheet presented over this screen is not a new appearance, so a card that only
/// reloaded there would show the invitation after a conversation had just happened,
/// which is verbatim the defect this card exists to prevent. `.sheet(item:onDismiss:)`
/// is the fix: the closure runs exactly once, exactly when the sheet goes away, however
/// it was dismissed (Done, a downward drag, or the system). No polling, no
/// `onAppear`/`onDisappear` pair to keep in sync by hand, and no call to Claude — the
/// reload is a local read of stored records, matching `load()`'s own behaviour on first
/// appearance (A14: opening or closing this sheet never calls the model).
///
/// ## Why there is no loading state
///
/// The initial state *is* the invitation, and the read either replaces it with a real
/// last message or leaves it. That is honest rather than convenient: before anything is
/// known, "ask about this run" is exactly what this card has to say, and a spinner for a
/// single local read would be a worse answer to the same moment. A failed read says so
/// instead, in `ChatConversationCopy`'s wording.
///
/// No glass is applied: this is a content surface holding data (FR-4.2), including while
/// it is also a button — `RunsStripView`'s chips are the same shape, a data affordance
/// rather than chrome.
struct WorkoutChatSectionView: View {
    let workoutID: UUID

    @State private var model: WorkoutChatPreviewModel

    /// Non-nil exactly while this card's own chat sheet is up. Carries the subject
    /// resolved at the moment of the tap, mirroring `RootTabView.ChatOpening` and
    /// `PlanAuthoringView.ConversationalRouteOpening` — both exist for the same reason:
    /// `sheet(item:)` wants an `Identifiable`, and `ChatSubject` already is one.
    @State private var opening: ChatOpening?

    private struct ChatOpening: Identifiable {
        let subject: ChatSubject
        var id: ChatSubject { subject }
    }

    init(workoutID: UUID) {
        self.workoutID = workoutID
        _model = State(initialValue: WorkoutChatPreviewModel(
            workoutID: workoutID,
            chatThreadRepository: PersistenceComposition.store
        ))
    }

    var body: some View {
        Button {
            opening = ChatOpening(subject: .workout(workoutID))
        } label: {
            VStack(alignment: .leading, spacing: Spacing.compact) {
                header
                content
            }
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.minimumTapTarget, alignment: .leading)
            .contentSurface(.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One element, one sentence: the visible card draws a heading, a body and
        // (sometimes) a timestamp as three separate `Text`s, but a VoiceOver user does
        // not need three swipes to learn what one card says. `accessibilityLabelText`
        // restates the heading because `.ignore` drops it from the tree along with
        // everything else here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens this run's conversation.")
        .accessibilityAddTraits(.isButton)
        .task { await model.load() }
        // The refresh mechanism this ticket chose — see this file's doc comment.
        .sheet(item: $opening, onDismiss: { Task { await model.load() } }) { opening in
            ChatSheet(subject: opening.subject)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.tight) {
            Text("Chat")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: Spacing.tight)
            // A shape cue that this card opens something, for the sighted reader who
            // never touches it to find out — CLAUDE.md's "no information carried by hue
            // alone" applies in both directions: the affordance has to exist as more
            // than a change in cursor. Matches `WorkoutRow`'s own disclosure chevron,
            // drawn by hand for the same reason (this card is not inside a `List`).
            Image(systemName: "chevron.right")
                .font(.metricLabel)
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
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
        }
    }

    /// What VoiceOver reads for the whole card. The heading is restated here — see the
    /// note beside `.accessibilityElement(children: .ignore)` above — and everything
    /// after it is `WorkoutChatCardPresentation`'s decision, not this view's: the same
    /// split `ChatThreadListRow.accessibilityLabel(spokenTimestamp:)` draws between a
    /// sentence (core, tested) and the phrase inside it (`RelativeDateTimeFormatter`,
    /// platform-owned).
    private var accessibilityLabelText: String {
        let stateText: String
        switch model.state {
        case .invitation:
            stateText = ChatConversationCopy.emptyTranscriptInvitation(for: .workout)
        case .failed:
            stateText = ChatConversationCopy.failedToLoad(for: .workout)
        case let .lastExchange(preview, lastActivityAt):
            stateText = WorkoutChatCardPresentation.accessibilityLabel(
                preview: preview,
                spokenTimestamp: RelativeTimestampFormatting.spoken(lastActivityAt)
            )
        }
        return "Chat. \(stateText)"
    }
}

/// The one stored read behind the card above: the most recent thread for this run, and
/// what to say about it — `WorkoutChatCardPresentation`'s decision (MAX-186), not this
/// type's.
///
/// Nothing here decides copy. Whether a thread has anything worth previewing is
/// `WorkoutChatCardPresentation.state(for:)`'s answer, built on `ChatThreadSummary` —
/// including *how* the preview line is collapsed and truncated — so the preview on this
/// card and the preview on the same thread's row in §2.3's list are the same text
/// produced by the same function, not two views that both shorten a string.
@MainActor
@Observable
final class WorkoutChatPreviewModel {

    private(set) var state: WorkoutChatCardState = .invitation

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
            let thread = try await chatThreadRepository.mostRecentThread(for: .workout(workoutID))
            state = WorkoutChatCardPresentation.state(for: thread)
        } catch {
            state = .failed
        }
    }
}
