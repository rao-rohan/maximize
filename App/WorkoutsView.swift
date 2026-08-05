import SwiftUI
import MaximizeCore

/// The workout list — the minimum surrounding view MAX-041 needs to reach the detail
/// screen's plan-verdict header (FR-1.1). Rows are deliberately plain (see
/// `WorkoutRow`); everything richer belongs to later tickets.
struct WorkoutsView: View {
    @State private var model = WorkoutsListModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workouts")
                .contentSurface(.screen)
                .navigationDestination(for: UUID.self) { workoutID in
                    WorkoutDetailView(workoutID: workoutID)
                }
                // MAX-081: settings is a button on both tabs, not a tab of its own.
                // Attached to the root only — pushing a workout should show that
                // screen's own bar, not carry an app-level control into it.
                .settingsToolbarItem()
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text("Could not load workouts.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(data) where data.workouts.isEmpty:
            Text("No workouts yet.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(data):
            ScrollView {
                LazyVStack(spacing: Spacing.compact) {
                    ForEach(data.workouts) { workout in
                        NavigationLink(value: workout.id) {
                            WorkoutRow(workout: workout, distanceUnit: data.distanceUnit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .screenMargins()
                .padding(.vertical, Spacing.regular)
            }
        }
    }
}
