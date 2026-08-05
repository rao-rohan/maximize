import SwiftUI
import MaximizeCore

/// The proposal card in the transcript (CHAT-FIRST-SPEC.md §4.6, MAX-101).
///
/// **This view decides nothing.** What the card says — the headline, the summary, every
/// row's label and value, which rows changed and what they changed from, the sentence
/// about lifts, and what accepting and discarding each promise — is all
/// `PlanProposalReview`, computed in `MaximizeCore` and covered by
/// `PlanProposalReviewTests`. This file lays those strings out and forwards two taps,
/// which is the "observe, render, forward intent" shape every other view here follows.
///
/// ## Why a card rather than prose
///
/// §4.6: a proposal is a structured object reviewed as a whole, not something to read as
/// it arrives. Rendering it as a bubble would put fourteen unchanged fields and one
/// changed one in the same undifferentiated paragraph, which is precisely what the diff
/// exists to prevent.
///
/// ## Density, and the choice this makes about it
///
/// The card **leads with the diff and keeps the full plan behind a disclosure** on a
/// revision. That is a deliberate departure from "numerals do the hierarchy work": the
/// full statement is twenty-odd rows, and dropping twenty rows into a chat transcript
/// buries the two that matter under the eighteen that do not — which is the failure §4.6
/// describes, arriving by a different route. The full plan stays one tap away and is
/// never hidden on a *first* plan, where there is no diff and the statement is the point.
///
/// ## Accessibility
///
/// - Each row is one accessibility element speaking `Row.spokenDescription`, so VoiceOver
///   reads "Heart-rate cap, changed from 152 bpm to 148 bpm" rather than three fragments.
/// - **No state is carried by colour alone.** A changed row is marked with the word
///   `Change.marker` supplies ("Changed", "New") as well as tinted, per CLAUDE.md's rule
///   and the 1.02:1 instance that motivated it.
/// - Every fixed dimension is `@ScaledMetric(relativeTo:)`.
struct PlanProposalCardView: View {
    let review: PlanProposalReview
    let onAccept: () -> Void
    let onDiscard: () -> Void

    /// Revisions open showing only the diff; a first plan has no diff, so it opens
    /// showing everything.
    @State private var showsEveryRow: Bool

    /// Matches `ChatThreadRow`'s own leading glyph column, so the card's header and the
    /// thread list line up at every Dynamic Type size.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 20

    init(review: PlanProposalReview, onAccept: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.review = review
        self.onAccept = onAccept
        self.onDiscard = onDiscard
        _showsEveryRow = State(initialValue: !review.isRevision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            header
            Divider().overlay(Color.separator)
            sections
            if review.isRevision {
                disclosureToggle
            }
            Text(review.liftNote)
                .font(.microLabel)
                .foregroundStyle(Color.textSecondary)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.compact) {
            Image(systemName: "list.clipboard")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(review.headline)
                    .font(.sectionHeading)
                    .foregroundStyle(Color.textPrimary)
                Text(review.summary)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The rows

    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            ForEach(visibleSections) { section in
                VStack(alignment: .leading, spacing: Spacing.snug) {
                    Text(section.title)
                        .font(.microLabel)
                        .foregroundStyle(Color.textTertiary)
                        .textCase(.uppercase)

                    ForEach(rows(of: section)) { row in
                        ProposalRowView(row: row)
                    }
                }
            }

            // A revision that changes nothing is a real answer, not a blank card: the
            // model was asked and proposed the plan already in force. Said plainly rather
            // than rendered as an empty list.
            if review.isRevision, !showsEveryRow, review.changedRowCount == 0 {
                Text("This proposal matches the plan already in force, field for field.")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// While the diff is showing, a section with nothing changed in it is not drawn at
    /// all — an empty "Goals" heading would read as a section that failed to load.
    private var visibleSections: [PlanProposalReview.Section] {
        guard review.isRevision, !showsEveryRow else { return review.sections }
        return review.sections.filter(\.hasChanges)
    }

    private func rows(of section: PlanProposalReview.Section) -> [PlanProposalReview.Row] {
        guard review.isRevision, !showsEveryRow else { return section.rows }
        return section.changedRows
    }

    private var disclosureToggle: some View {
        // Bound to a `String` before it reaches `Label`, so the `StringProtocol`
        // initializer is chosen rather than the `LocalizedStringKey` one — this app has
        // no localization tables, and an interpolated key would look for one.
        let title: String = showsEveryRow
            ? "Show only what changed"
            : "Show the whole plan (\(review.rowCount) fields)"
        return Button {
            showsEveryRow.toggle()
        } label: {
            Label(title, systemImage: showsEveryRow ? "chevron.up" : "chevron.down")
                .font(.metricLabel)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accent)
    }

    // MARK: - Accept and discard

    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            Text(PlanProposalReview.acceptExplanation)
                .font(.microLabel)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: Spacing.snug) {
                Button(PlanProposalReview.acceptTitle, action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .accessibilityHint(PlanProposalReview.acceptExplanation)

                Button(PlanProposalReview.discardTitle, action: onDiscard)
                    .buttonStyle(.bordered)
                    .accessibilityHint(PlanProposalReview.discardExplanation)
            }
        }
    }
}

/// One field of the plan, with its change state carried by a word as well as a tint.
private struct ProposalRowView: View {
    let row: PlanProposalReview.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Text(row.label)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)

            Spacer(minLength: Spacing.snug)

            VStack(alignment: .trailing, spacing: Spacing.hairspace) {
                Text(row.value)
                    .font(.metricLabel)
                    .foregroundStyle(row.isChange ? Color.textPrimary : Color.textSecondary)
                    .multilineTextAlignment(.trailing)

                if case let .changed(previous) = row.change {
                    // The old value, struck through as well as dimmed — a second channel
                    // for the same fact, so "this used to be something else" survives
                    // Increase Contrast and colour-vision differences alike.
                    Text(previous)
                        .font(.microLabel)
                        .foregroundStyle(Color.textTertiary)
                        .strikethrough()
                }
            }

            if let marker = row.change.marker {
                Text(marker)
                    .font(.microLabel)
                    .foregroundStyle(Color.textOnSaturatedFill)
                    .padding(.horizontal, Spacing.tight)
                    .padding(.vertical, Spacing.hairspace)
                    // A capsule rather than a hand-picked radius: the platform's own
                    // shape for a badge, and one fewer number to keep on the ramp.
                    .background(Color.accent, in: Capsule())
            }
        }
        // One element, one sentence — see the card's accessibility note.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenDescription)
    }
}
