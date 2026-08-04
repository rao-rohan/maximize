import SwiftUI

/// The app's top-level three-tab structure implied by PRD §7.4: workouts, the
/// longitudinal dashboard, and settings.
///
/// No styling decisions live here. Colors, Liquid Glass chrome, and typography are
/// MAX-040's job, not this scaffold's — these are placeholder views wired up so later
/// tickets have somewhere to land.
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

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
