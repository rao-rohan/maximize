import SwiftUI
import Charts
import MaximizeCore

/// FR-1.3: the run's average cadence set against the plan's target band, with the
/// average called out.
///
/// ## What this view does and does not decide
///
/// Every number here is precomputed by `MaximizeCore.CadenceChartData` (MAX-043): the
/// average (`DerivedMetrics.averageCadenceStepsPerMinute`, D2, read never recomputed),
/// the band (`Plan.cadenceTarget`, D1, read never hardcoded — the current 165–170
/// band does not appear anywhere in this file), and the axis domain both are plotted
/// against. This view only maps those numbers onto `Chart` marks and design-system
/// tokens.
///
/// Deliberately absent: any call to `CadenceBand.contains(_:)`, any in/above/below
/// verdict, and any color coding of one. The band and the average are drawn at their
/// true positions and left to speak for themselves — FR-1.3 asks for the comparison,
/// not a judgment, and the score-band colors (green/amber/red) are reserved for the
/// calendar and verdict header (FR-4.3).
///
/// ## The three states FR-1.3 has to get right
///
/// - **No cadence at all** (`averageStepsPerMinute == nil`): this run has no step
///   count (MAX-010's "absent, not empty") — stated as an absence, never as 0 spm.
/// - **No plan governs the day** (`band == nil`): the average is still meaningful on
///   its own, so it is still stated; there is simply no band to plot it against.
/// - **In band, above band, below band**: all three are ordinary outcomes, rendered
///   identically — the marker's position relative to the shaded band is the entire
///   comparison, with no verdict text or color layered on top.
struct CadenceBandView: View {
    let data: CadenceChartData

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Cadence")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            if let average = data.averageStepsPerMinute {
                averageReadout(average)
                if data.band != nil {
                    track(average: average)
                } else {
                    Text("No plan governs this day, so there's no target band to compare against.")
                        .font(.metricLabel)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                noDataMessage
            }
        }
        .contentSurface(.card)
    }

    // MARK: - Stated figure (FR-1.3's "current-run average called out")

    @ViewBuilder
    private func averageReadout(_ average: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
            Text("\(Int(average.rounded()))")
                .font(.metricPrimary)
                .foregroundStyle(Color.textPrimary)
            Text("spm avg")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Band

    @ViewBuilder
    private func track(average: Double) -> some View {
        Chart {
            if let band = data.band {
                RectangleMark(
                    xStart: .value("Band low", band.lowStepsPerMinute),
                    xEnd: .value("Band high", band.highStepsPerMinute)
                )
                .foregroundStyle(Color.chartThreshold.opacity(0.2))

                RuleMark(x: .value("Band low", band.lowStepsPerMinute))
                    .foregroundStyle(Color.chartThreshold)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(Int(band.lowStepsPerMinute.rounded()))")
                            .font(.microLabel)
                            .foregroundStyle(Color.textTertiary)
                    }

                RuleMark(x: .value("Band high", band.highStepsPerMinute))
                    .foregroundStyle(Color.chartThreshold)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(Int(band.highStepsPerMinute.rounded()))")
                            .font(.microLabel)
                            .foregroundStyle(Color.textTertiary)
                    }
            }

            PointMark(x: .value("Average", average), y: .value("", 0))
                .symbolSize(160)
                .foregroundStyle(Color.chartSeriesPrimary)
        }
        .chartXScale(domain: data.axisDomain)
        .chartYScale(domain: -1...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(Color.chartGridline)
                AxisValueLabel()
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: LayoutMetrics.compactChartHeight)
        .contentSurface(.inset)
    }

    // MARK: - No data

    private var noDataMessage: some View {
        Text("No cadence data for this workout.")
            .font(.bodyCopy)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface(.inset)
    }
}
