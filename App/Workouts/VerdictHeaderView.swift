import SwiftUI
import MaximizeCore

/// FR-1.1's plan-verdict header: the scheduled session, the actual type, the
/// effectiveness score, whether it was effective, and the one-line rationale — or the
/// honest absence of a score.
///
/// ## Both scoreless states are first-class, and they are not the same state
///
/// A workout with no score is ordinary here, and there are two ways to be one.
/// `awaitingScoreSection` is a run whose score has not landed yet — seconds after a
/// run finishes, or indefinitely with no API key and no network — and it says so with a
/// spinner, because the screen really will change. `noVerdictSection` (MAX-126) is a
/// lift, a ride or a hike: MAX-111 stopped the running rubric being applied to those, so
/// no score is coming, ever, and a spinner there is the app promising something it
/// cannot deliver. It carries no spinner and no future tense.
///
/// Neither is a dimmed or empty copy of the scored layout: each has its own copy on its
/// own neutral surface, and each carries **none** of the three saturated score-band
/// colors. Coloring an undecided state would say a verdict exists when it does not;
/// coloring a state that will never have one would be worse.
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
    /// MAX-047 — the athlete's chosen `DistanceUnit`, needed here for the scheduled
    /// session's distance (`WorkoutDisplayFormatting.describeScheduledSession`).
    let distanceUnit: DistanceUnit

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
        WorkoutDisplayFormatting.describeScheduledSession(verdict.scheduledSession, unit: distanceUnit)
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
        case .awaitingScore:
            awaitingScoreSection
        case .noVerdict:
            noVerdictSection
        case let .scored(automatic, annotation):
            scoredSection(automatic: automatic, annotation: annotation)
        }
    }

    /// No score badge, no band color — nothing has been decided yet (see the type doc
    /// comment above). `contentSurface(.inset)` keeps it visually a *part of* the
    /// header rather than a sibling card, since it is standing in for the score area,
    /// not narrating something separate.
    private var awaitingScoreSection: some View {
        HStack(spacing: Spacing.compact) {
            ProgressView()
            scorelessCopy(
                headline: "Not yet scored",
                detail: "Scoring runs automatically once the run is captured."
            )
            Spacer(minLength: 0)
        }
        .contentSurface(.inset)
    }

    /// The same neutral surface as `awaitingScoreSection`, with the spinner removed and
    /// the sentence in the present tense.
    ///
    /// **The spinner is the part that was lying**, so it is the part that goes: it is an
    /// indeterminate progress indicator over a process that is not running, and
    /// VoiceOver announces it as "in progress". What replaces it is not an error icon
    /// and not an empty slot — the workout was captured in full, and the only thing
    /// absent is a number the plan has no way to produce. Stating that plainly, once, is
    /// the whole design (CLAUDE.md: absence is a designed state).
    ///
    /// The two lines are combined into one accessibility element so VoiceOver reads the
    /// fact and its reason as a single sentence rather than as two unrelated labels.
    private var noVerdictSection: some View {
        HStack(spacing: Spacing.compact) {
            scorelessCopy(
                headline: "Recorded, not scored",
                detail: "The plan scores runs, so there's no score for this workout."
            )
            Spacer(minLength: 0)
        }
        .contentSurface(.inset)
        .accessibilityElement(children: .combine)
    }

    /// Shared so the two scoreless states cannot drift apart in weight or colour — one
    /// voice, one weight, one surface. Only the words differ, which is the only thing
    /// that should.
    private func scorelessCopy(headline: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(headline)
                .font(.metricSecondary)
                .foregroundStyle(Color.textPrimary)
            Text(detail)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
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
                // The same non-colour band channel the calendar carries (MAX-084). The
                // chip's copy is binary — `Score.isEffective` is a threshold, not a
                // band — so `.marginal` and `.ineffective` both read "Not effective"
                // and were told apart by hue alone, at 1.66:1 in dark and 1.04:1 in
                // light. The mark is the channel that does not depend on seeing hue.
                ScoreBandMarkView(
                    band: automatic.band,
                    diameter: LayoutMetrics.prominentScoreBandMarkSize
                )
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
