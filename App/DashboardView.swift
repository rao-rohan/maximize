import SwiftUI
import MaximizeCore

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
///
/// **MAX-081 gave this screen a `NavigationStack`.** It had none, so it had no bar to
/// hang the settings button on, and its title was an in-content `Text`. The title moved
/// to `navigationTitle` rather than being duplicated — the workouts tab already titles
/// itself that way, and two titles on one screen is what a stacked bar plus an inline
/// heading would have been. The stack pushes nothing today; it exists for the bar.
///
/// **MAX-098 moved ownership of the interval model up to `RootTabView`.** This screen
/// still renders and mutates it and is still the only place it can be changed from —
/// what changed is that the persistent Ask button also reads it, on every tab, to know
/// which window a training thread would be about (§3.4). One control, one notion of
/// "what period are we talking about"; a second one is the class of mistake D2 and D3
/// exist to prevent. This view is otherwise unchanged.
struct DashboardView: View {
    let intervalModel: TrendIntervalSelectionModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    TrendIntervalSelectorView(model: intervalModel)

                    // Order follows FR-3: the calendar (3.2), the overlay (3.3), then
                    // the tiles (3.4).
                    if let interval = intervalModel.state.interval {
                        ScoreCalendarView(interval: interval)
                        DriftOverlayView(interval: interval)
                        TrendTilesView(interval: interval)
                    } else {
                        // MAX-154. This branch did not exist: with no interval — the
                        // selector's `.failed` state, i.e. a system clock outside
                        // `CalendarDay`'s domain — the screen drew the selector's one
                        // line and then nothing at all, three sections deep. A blank is
                        // not a designed state, and "the whole dashboard is missing" is
                        // the one thing a person could not work out from a caption on a
                        // control above it.
                        Text(FailureCopy.dashboardUnavailableWithoutToday)
                            .font(.bodyCopy)
                            .foregroundStyle(Color.textSecondary)
                            .contentSurface(.card)
                    }
                }
                .screenMargins()
                .padding(.vertical, Spacing.roomy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentSurface(.screen)
            .navigationTitle("Dashboard")
            .settingsToolbarItem()
        }
    }
}
