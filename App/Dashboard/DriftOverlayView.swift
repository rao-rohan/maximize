import SwiftUI
import Charts
import MaximizeCore

/// FR-3.3 / D5: several runs' heart-rate curves on one chart, each normalised onto a
/// 0–100% elapsed axis so runs of different durations can be compared by shape. PRD §1
/// names this as the chart no other app draws.
///
/// ## What this view does and does not decide
///
/// Nothing here resamples, filters, averages or judges. `MaximizeCore`'s
/// `HeartRateDriftOverlayData` decides which runs qualify, turns each stored curve into
/// `bucketCount` time-weighted means on the shared axis, caps how many are stacked, and
/// writes the sentences explaining what was left out — all unit tested, because all of it
/// is arithmetic. This view maps that data onto `Chart` marks and design-system tokens.
///
/// The drift percentage in the legend is `DerivedMetrics.heartRateDriftFraction` (D2),
/// stored once at ingestion, printed as it was stored. This view never derives a second
/// drift figure from the curves it is drawing — the two would sit on the same screen
/// disagreeing, which is precisely what D2 exists to prevent.
///
/// ## Legibility with N curves
///
/// - **One curve** reads as a single run's shape, drawn in `chartSeriesPrimary` at full
///   strength. The overlay is still the right home for it: the axis and the empty legend
///   say plainly that there is one qualifying run in this interval.
/// - **Six curves** are the case this is designed around. The most recent is the primary
///   series; the five behind it are `chartSeriesMuted`, fading with age down a ramp whose
///   floor keeps the oldest legible.
/// - **Thirty curves** never happen. `HeartRateDriftOverlayData.defaultStackLimit` stacks
///   the twelve most recent and the caption states how many were held back; un-stacking a
///   recent run brings an older one forward. Twelve fading lines read as a history behind
///   one foreground run — thirty would read as a texture.
///
/// The curves are deliberately *not* given N distinguishable hues. FR-4.3 spends the
/// saturated-colour budget on the accent and the three score bands, and those three are
/// reserved for the calendar and the verdict header (`ScoreBandColors.swift`); recency,
/// not hue, is the axis that separates these lines.
struct DriftOverlayView: View {
    let interval: TrendInterval

    @State private var model = DriftOverlayModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("HR drift across runs")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.roomy)
            case .failed:
                Text("Couldn't load the runs in this interval.")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            case .loaded(let data):
                loaded(data)
            }
        }
        .contentSurface(.card)
        .task(id: interval) {
            await model.load(for: interval)
        }
    }

    // MARK: - Loaded

    /// A nil `bpmAxisDomain` is exactly the "nothing is stacked" state — there is no
    /// chart to draw rather than an empty one — so unwrapping it is also the branch.
    @ViewBuilder
    private func loaded(_ data: HeartRateDriftOverlayData) -> some View {
        if let bpmAxisDomain = data.bpmAxisDomain {
            chart(data, bpmAxisDomain: bpmAxisDomain)
            Text(data.stackSummary)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
            legend(data)
        } else {
            emptyState(data)
        }
        notes(data)
    }

    /// No curve qualified. Said as a sentence — never as an empty axis, and never as a
    /// flat line at zero (`exclusionNotes` below explains which runs were left out and
    /// why).
    @ViewBuilder
    private func emptyState(_ data: HeartRateDriftOverlayData) -> some View {
        Text(
            data.candidateCount == 0
                ? "No runs in this interval."
                : "No run in this interval has a heart-rate curve to normalise."
        )
        .font(.bodyCopy)
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.inset)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(_ data: HeartRateDriftOverlayData, bpmAxisDomain: ClosedRange<Double>) -> some View {
        Chart {
            // `curves` arrives oldest-first, so the most recent run is drawn last and
            // therefore on top of its own history.
            ForEach(data.curves) { curve in
                ForEach(curve.points, id: \.percentElapsed) { point in
                    LineMark(
                        x: .value("Elapsed", point.percentElapsed),
                        y: .value("Heart rate", point.beatsPerMinute),
                        // Without an explicit series every curve would be joined into one
                        // path, which is how a stack of runs becomes a single scribble.
                        series: .value("Run", curve.workoutID.uuidString)
                    )
                }
                .foregroundStyle(strokeColor(for: curve, in: data))
                .lineStyle(StrokeStyle(lineWidth: curve.isMostRecent ? 2 : 1, lineJoin: .round))
                .interpolationMethod(.linear)
            }
        }
        .chartXScale(domain: HeartRateDriftOverlayData.percentElapsedDomain)
        .chartYScale(domain: bpmAxisDomain)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100] as [Double]) { value in
                AxisGridLine().foregroundStyle(Color.chartGridline)
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                            .font(.microLabel)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(Color.chartGridline)
                AxisValueLabel()
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(minHeight: LayoutMetrics.minimumChartHeight)
        .contentSurface(.inset)
        .accessibilityLabel("Heart-rate curves for \(data.curves.count) runs, on a shared percent-elapsed axis")
    }

    /// The most recent run is the foreground series; everything older recedes behind it by
    /// the ramp `MaximizeCore` computes (and tests). No hue carries meaning here.
    private func strokeColor(for curve: NormalizedHeartRateCurve, in data: HeartRateDriftOverlayData) -> Color {
        let base = curve.isMostRecent ? Color.chartSeriesPrimary : Color.chartSeriesMuted
        return base.opacity(
            HeartRateDriftOverlayData.contextOpacity(
                recencyRank: curve.recencyRank,
                stackedCount: data.curves.count
            )
        )
    }

    // MARK: - Legend (FR-3.3's "selectable which runs are stacked")

    @ViewBuilder
    private func legend(_ data: HeartRateDriftOverlayData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            // Newest first: the legend reads in the order an athlete thinks about their
            // runs, while the chart draws in the order that paints correctly.
            ForEach(Array(data.curves.reversed())) { curve in
                stackedRow(curve, in: data)
            }
            ForEach(data.excluded.filter { $0.reason == .hiddenByAthlete }) { run in
                hiddenRow(run)
            }
        }
    }

    private func stackedRow(_ curve: NormalizedHeartRateCurve, in data: HeartRateDriftOverlayData) -> some View {
        Button {
            model.toggleStacking(of: curve.workoutID)
        } label: {
            HStack(spacing: Spacing.snug) {
                Capsule()
                    .fill(strokeColor(for: curve, in: data))
                    .frame(width: 20, height: curve.isMostRecent ? 3 : 2)

                Text(curve.start, format: .dateTime.month(.abbreviated).day())
                    .font(.metricLabel)
                    .foregroundStyle(Color.textPrimary)

                Text(WorkoutDisplayFormatting.describe(curve.classification))
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                // `DerivedMetrics.heartRateDriftFraction`, as stored (D2). Absent for a run
                // that carries none — omitted, never printed as a zero.
                if let drift = curve.formattedDriftPercent {
                    Text("\(drift)% drift")
                        .font(.metricLabel)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Un-stack this run")
    }

    private func hiddenRow(_ run: HeartRateDriftOverlayData.ExcludedRun) -> some View {
        Button {
            model.toggleStacking(of: run.workoutID)
        } label: {
            HStack(spacing: Spacing.snug) {
                Capsule()
                    .strokeBorder(Color.separator, lineWidth: LayoutMetrics.hairline)
                    .frame(width: 20, height: 3)

                Text(run.start, format: .dateTime.month(.abbreviated).day())
                    .font(.metricLabel)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text("Not stacked")
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stack this run")
    }

    // MARK: - What is not on the chart, and why

    @ViewBuilder
    private func notes(_ data: HeartRateDriftOverlayData) -> some View {
        if !data.exclusionNotes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                ForEach(data.exclusionNotes, id: \.self) { note in
                    Text(note)
                        .font(.microLabel)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
