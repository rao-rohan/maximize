import SwiftUI
import MaximizeCore

/// FR-1.1's plan-verdict header: the scheduled session, the actual type, the
/// effectiveness score, whether it was effective, and the one-line rationale — or the
/// honest absence of a score.
///
/// ## The unscored state is first-class
///
/// MAX-015/MAX-023 are still in flight, so in practice **every workout this renders
/// today is unscored** — either scoring hasn't run yet (seconds to minutes after a run
/// finishes) or never will (no API key, no network). `unscoredSection` is not a dimmed
/// or empty copy of the scored layout: it has its own copy, its own neutral surface,
/// and it carries **none** of the three saturated score-band colors. Coloring an
/// undecided state would say a verdict exists when it does not.
///
/// ## Manual annotations sit alongside the auto-score, never over it
///
/// D8: the auto-score is immutable; a correction is additive. Per PRD §8 ("where a
/// manual annotation exists, tallies use it; the auto-score remains recorded"), both
/// are shown here — the auto-score keeps the header's one saturated color
/// (`Color.scoreBand(automatic.band)`, the *only* band this view is ever handed), and a
/// correction, if present, is a plain-text line underneath with no color of its own.
/// `ScoreBand` cannot be computed from a raw number (D1) — only the scorer, reading the
/// plan version in force, may do that — and a manual score is exactly a raw number with
/// no stored band to read. Inventing a color for it here would be the same mistake
/// `Color.scoreBand(_:)` refuses to allow at its call site, just moved one file over.
struct VerdictHeaderView: View {
    let verdict: WorkoutVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            labeledRow(label: "Scheduled", value: scheduledSessionLabel)
            labeledRow(label: "Actual", value: actualLabel)

            Divider().overlay(Color.separator)

            scoringSection
        }
        .contentSurface(.card)
    }

    private var scheduledSessionLabel: String {
        WorkoutDisplayFormatting.describeScheduledSession(verdict.scheduledSession)
    }

    // MARK: Scheduled / actual

    private func labeledRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: Spacing.regular)
            Text(value)
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var actualLabel: String {
        switch verdict.actual {
        case let .unclassified(activityType):
            return WorkoutDisplayFormatting.describe(activityType)
        case let .classified(classification):
            return WorkoutDisplayFormatting.describe(classification)
        }
    }

    // MARK: Scoring

    @ViewBuilder
    private var scoringSection: some View {
        switch verdict.scoring {
        case .unscored:
            unscoredSection
        case let .scored(automatic, annotation):
            scoredSection(automatic: automatic, annotation: annotation)
        }
    }

    /// No score badge, no band color — nothing has been decided yet (see the type doc
    /// comment above). `contentSurface(.inset)` keeps it visually a *part of* the
    /// header rather than a sibling card, since it is standing in for the score area,
    /// not narrating something separate.
    private var unscoredSection: some View {
        HStack(spacing: Spacing.compact) {
            ProgressView()
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("Not yet scored")
                    .font(.metricSecondary)
                    .foregroundStyle(Color.textPrimary)
                Text("Scoring runs automatically once the run is captured.")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .contentSurface(.inset)
    }

    private func scoredSection(automatic: Score, annotation: ScoreAnnotation?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(alignment: .center, spacing: Spacing.compact) {
                Text("\(automatic.value)")
                    .font(.metricHero)
                    .foregroundStyle(Color.textOnSaturatedFill)
                Text(automatic.isEffective ? "Effective" : "Not effective")
                    .font(.metricSecondary)
                    .foregroundStyle(Color.textOnSaturatedFill)
                Spacer(minLength: 0)
            }
            .padding(Spacing.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.scoreBand(automatic.band),
                in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
            )

            Text(automatic.rationale)
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)

            if let annotation {
                annotationRow(annotation)
            }
        }
    }

    /// Deliberately no color: see the type doc comment for why a manual correction
    /// cannot carry a `ScoreBand`.
    private func annotationRow(_ annotation: ScoreAnnotation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("Manually corrected to \(annotation.manualScore)")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
            if let note = annotation.note {
                Text(note)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.inset)
    }
}
