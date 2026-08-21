import SwiftUI
import MaximizeCore

/// §6.7, MAX-200: the tappable questions under the empty-thread invitation.
///
/// Draws nothing this file decided. `ChatStarters` (`MaximizeCore`) already chose which
/// questions to offer, in which order, from the thread's subject — this view only lays
/// out the strings it is handed and forwards a tap, the same "observe, render, forward
/// intent" shape every other view here follows.
///
/// ## One composed state with the invitation above it
///
/// `ChatConversationView` draws this directly under
/// `ChatConversationCopy.emptyTranscriptInvitation(for:)`, inside the same leading-aligned
/// stack, at the same spacing that stack already uses between its own rows — deliberately
/// not a bordered card or a second heading of its own. The brief is explicit that this
/// should read as the invitation sentence continuing into something tappable, not a
/// second widget bolted beside it.
///
/// ## Full-width rows, not a horizontal scroller
///
/// `RunsStripView`'s chips are short session labels in a horizontal `ScrollView` with
/// `.lineLimit(1)` — the right shape for "10 Aug run", the wrong one for a full sentence.
/// A starter is a question, long enough that `.lineLimit(1)` would truncate it to an
/// ellipsis at any Dynamic Type size past the smallest, which is exactly the bug this
/// ticket's constraints name. So each starter is its own full-width row that wraps to
/// as many lines as it needs, stacked vertically — nothing here is ever cut off.
///
/// ## Gone the instant the thread is not empty
///
/// This view draws only from the `starters` array it is handed. `ChatConversationView`
/// passes one only while `model.messages.isEmpty && !model.isStreaming` — the same guard
/// that already gates the invitation sentence — so the first turn (from either party)
/// removes both in the same render; there is no separate dismissal to wire up and no
/// state here that could leave a stale row on screen.
struct ChatStartersView: View {
    let starters: [String]

    /// A tap sends the starter's exact text as the next turn — see this file's own
    /// "Send immediately" note on `ChatConversationView`'s call site for the argument.
    let onSelect: (String) -> Void

    /// Guarantees the platform's own minimum hit target even for a one-line starter at
    /// the smallest Dynamic Type size; a long starter's own wrapped height already clears
    /// this once type grows, so the two never fight.
    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = LayoutMetrics.minimumTapTarget

    var body: some View {
        if !starters.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.snug) {
                ForEach(starters, id: \.self) { starter in
                    row(starter)
                }
            }
        }
    }

    private func row(_ starter: String) -> some View {
        Button {
            onSelect(starter)
        } label: {
            Text(starter)
                .font(.metricLabel)
                .foregroundStyle(Color.textPrimary)
                // No `.lineLimit` — this file's own note on why a starter must never
                // truncate to an ellipsis.
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: minimumRowHeight, alignment: .leading)
                .contentSurface(.inset)
        }
        .buttonStyle(.plain)
        // The row's own text is already the question; VoiceOver needs the hint to say
        // what a tap *does*, which the visible text does not — the same split
        // `RunsStripView`'s chip button makes for the identical reason.
        .accessibilityLabel(starter)
        .accessibilityHint("Asks this question and starts the reply.")
    }
}
