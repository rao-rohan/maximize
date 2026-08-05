import SwiftUI

/// The dashboard tab (FR-3): a trends surface scoped to an interval.
///
/// MAX-060 lands the interval selector — the rest of the surface arrives with later
/// tickets, each reading `intervalModel.state.interval` to know what to render:
///
/// - MAX-061 — the score-colored calendar (FR-3.2)
/// - MAX-062 — the cross-run HR-drift overlay (FR-3.3), landed
/// - MAX-063 — the summary tiles (FR-3.4)
///
/// None of them owns `intervalModel`; this view does, and passes the selection down.
///
/// MAX-040 only put the screen on the standard opaque content background. Everything
/// the dashboard shows is data, so every surface it grows should be a
/// `contentSurface` — never glass (FR-4.2).
struct DashboardView: View {
    @State private var intervalModel = TrendIntervalSelectionModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Dashboard")
                    .font(.screenTitle)
                    .foregroundStyle(Color.textPrimary)

                TrendIntervalSelectorView(model: intervalModel)

                // Order follows FR-3: the calendar (3.2), the overlay (3.3), then the
                // tiles (3.4).
                if let interval = intervalModel.state.interval {
                    ScoreCalendarView(interval: interval)
                    DriftOverlayView(interval: interval)
                    TrendTilesView(interval: interval)
                }
            }
            .screenMargins()
            .padding(.vertical, Spacing.roomy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface(.screen)
    }
}
