import SwiftUI
import MaximizeCore

/// The setup card at the top of the Workouts tab (MAX-164, FIRST-RUN-SPEC §5, §8).
///
/// **This view decides nothing.** Which of `FirstRunCardState`'s six cases is showing is
/// `FirstRunChecklist.card`; every word is `FirstRunCopy.card(_:)`. Both are
/// `MaximizeCore` (MAX-162), and both are read here and nowhere else is a sentence
/// written — matching `PlanProposalCardView`'s "observe, render, forward intent" shape,
/// which this view's layout borrows directly.
///
/// ## One layout, six states
///
/// One heading, one sentence, an optional second sentence at secondary weight, and at
/// most one button (FIRST-RUN-SPEC §5.3). The body below is unconditional except for
/// `if let` on `copy.detail` and `copy.actionLabel` — both of which are already `nil` on
/// the states that have no second sentence or no button — so nothing here branches on
/// which of the six states it is.
///
/// ## R10
///
/// No string is written in this file. Every word comes from `FirstRunCopy`, which
/// `FailureCopyTests` holds to the banned-phrase list (FIRST-RUN-SPEC §9.3) — this view
/// has nothing to get wrong about what Health access means, because it never states it.
///
/// ## Accessibility
///
/// - Heading and body are one VoiceOver element, matching `PlanProposalCardView.header`
///   — "Health access has not been requested. Maximize cannot see any workouts…" reads
///   as one sentence rather than two stops.
/// - The button is left as its own element, not combined into the card: a
///   `.combine`d element containing an interactive control loses the control's own
///   double-tap-to-activate behaviour.
/// - No state here is carried by colour alone — the heading and body text are the
///   channel, and the token pair (`textPrimary`/`textSecondary`) already degrades
///   correctly under Increase Contrast (MAX-070's palette).
struct FirstRunCardView: View {
    let state: FirstRunCardState

    /// True only while the Health request is in flight — see `FirstRunModel`. Ignored by
    /// every state but the two Health ones, which are the only states whose action does
    /// not simply navigate elsewhere.
    let isPerformingAction: Bool

    let action: () -> Void

    private var copy: FirstRunCardCopy { FirstRunCopy.card(state) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(copy.heading)
                    .font(.sectionHeading)
                    .foregroundStyle(Color.textPrimary)

                Text(copy.body)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityElement(children: .combine)

            if let detail = copy.detail {
                Text(detail)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }

            if let actionLabel = copy.actionLabel {
                Button(action: action) {
                    // A fixed-width row rather than a compact button: this card is
                    // always the widest element on the tab (it shares `screenMargins()`
                    // with the list beneath it), and a button that does not match that
                    // width would be the one narrow control on an otherwise full-bleed
                    // screen.
                    HStack {
                        Spacer(minLength: 0)
                        if isPerformingAction {
                            ProgressView()
                        } else {
                            Text(actionLabel)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(isPerformingAction)
                // The label is swapped for a spinner while the request is in flight;
                // VoiceOver should still say what the button does rather than nothing.
                .accessibilityLabel(actionLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }
}
