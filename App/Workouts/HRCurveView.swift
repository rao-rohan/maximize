import SwiftUI
import Charts
import MaximizeCore

/// FR-1.2: the HR curve with the plan's cap drawn as a horizontal line, and the time
/// spent above it shaded — "the chart PRD §1 names as something no other app draws".
///
/// ## What this view does and does not decide
///
/// Every number here is precomputed by `MaximizeCore.HeartRateChartData` (MAX-042):
/// the curve's own points, the cap (D1 — `Plan.heartRateCapBPM`, never a literal),
/// the shaded excursions, and the axis domains. This view only maps that data onto
/// `Chart` marks and design-system tokens. Nothing here buckets, interpolates, or
/// sums a duration — see `HeartRateChartData`'s documentation for where that
/// discipline lives and why it matters.
///
/// **The shaded region and the stated figure are drawn from two different fields, on
/// purpose.** `aboveCapExcursions` (shape only) drives the `AreaMark`s below;
/// `timeAboveCapSeconds` (`DerivedMetrics.timeAboveCapSeconds`, D2, computed once at
/// ingestion) drives the text in `timeAboveCapSummary`. They are never combined or
/// cross-checked here — doing so would be exactly the kind of second-source-of-truth
/// arithmetic D2 exists to prevent. `HeartRateChartData` computes them from the same
/// curve and the same cap so they agree on *where* the line crosses, but this view has
/// no way to turn the shape back into a number, because it never tries to.
///
/// ## The four states FR-1.2 has to get right
///
/// - **No HR data at all** (`chartData == nil`): there is no chart to draw, so this
///   says so rather than rendering an empty axis.
/// - **An indoor run**: needs nothing special. The curve never reads `Workout.hasRoute`
///   — FR-0.6 makes an indoor run's HR curve the point, not a degraded case, and the
///   simplest way to honor that is to have no route-shaped branch to fall into.
/// - **A run entirely below the cap**: `aboveCapExcursions` is empty and
///   `timeAboveCapSeconds` is zero — a success, stated as one ("Held the cap for the
///   entire run"), not left blank as though nothing was measured.
/// - **No plan governs the day**: `capBPM` is nil, so no `RuleMark` and no shading are
///   drawn — there is nothing to draw a cap *against* — but the curve itself still
///   renders in full; a note explains the absence rather than leaving it silent.
struct HRCurveView: View {
    let chartData: HeartRateChartData?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Heart rate")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            if let chartData {
                curve(for: chartData)
                summary(for: chartData)
            } else {
                noDataMessage
            }
        }
        .contentSurface(.card)
    }

    // MARK: - Chart

    @ViewBuilder
    private func curve(for data: HeartRateChartData) -> some View {
        Chart {
            // Shaded time-above-cap, drawn first so the curve and the cap line sit on
            // top of it. Flattening the excursions is safe: each one already begins and
            // ends exactly at a cap crossing, so the zero-height segment "between" two
            // excursions draws nothing — see `HeartRateCurve.excursionsAbove(_:)`.
            ForEach(Array(data.aboveCapExcursions.flatMap { $0 }.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Elapsed", point.offsetSeconds),
                    yStart: .value("Cap", data.capBPM ?? point.beatsPerMinute),
                    yEnd: .value("Heart rate", point.beatsPerMinute)
                )
            }
            .foregroundStyle(Color.chartThreshold.opacity(0.2))
            .interpolationMethod(.linear)

            ForEach(data.points, id: \.offsetSeconds) { point in
                LineMark(
                    x: .value("Elapsed", point.offsetSeconds),
                    y: .value("Heart rate", point.beatsPerMinute)
                )
            }
            .foregroundStyle(Color.chartSeriesPrimary)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            if let capBPM = data.capBPM {
                RuleMark(y: .value("Cap", capBPM))
                    .foregroundStyle(Color.chartThreshold)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Cap \(Int(capBPM.rounded())) bpm")
                            .font(.microLabel)
                            .foregroundStyle(Color.chartThreshold)
                    }
            }
        }
        .chartXScale(domain: data.offsetSecondsDomain)
        .chartYScale(domain: data.bpmAxisDomain)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(Color.chartGridline)
                AxisValueLabel()
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
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
    }

    // MARK: - Stated figure (never derived from the chart above)

    @ViewBuilder
    private func summary(for data: HeartRateChartData) -> some View {
        if data.capBPM == nil {
            Text("No plan governs this day, so there's no cap to compare against.")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        } else if let seconds = data.timeAboveCapSeconds {
            Text(timeAboveCapSummary(seconds))
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// States `DerivedMetrics.timeAboveCapSeconds` as it was stored (D2) — the only
    /// number this view ever prints for "time above cap". Zero reads as a success, not
    /// an absence (see the type documentation).
    private func timeAboveCapSummary(_ seconds: Double) -> String {
        guard seconds > 0 else { return "Held the cap for the entire run." }
        return "\(HeartRateChartData.formattedDuration(seconds: seconds)) above cap"
    }

    // MARK: - No data

    private var noDataMessage: some View {
        Text("No heart-rate data for this workout.")
            .font(.bodyCopy)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface(.inset)
    }
}
