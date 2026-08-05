import SwiftUI

/// The app's top-level structure: the two surfaces PRD §7.4 describes as places you
/// *look at* — the workout list and the longitudinal dashboard.
///
/// **Settings is deliberately not a third tab (MAX-081).** A tab bar advertises the
/// app's parallel modes, and settings is not one of them: it is somewhere you go to
/// change a preference and immediately leave. It now reaches both tabs as a toolbar
/// button, via `settingsToolbarItem()` — see that file for the reasoning and for why
/// the sheet applies no glass of its own.
///
/// No styling decisions live here. Colors, Liquid Glass chrome, and typography are
/// MAX-040's job.
struct RootTabView: View {
    var body: some View {
        TabView {
            WorkoutsView()
                .tabItem {
                    Label("Workouts", systemImage: "figure.run")
                }

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }
        }
    }
}
