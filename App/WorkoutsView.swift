import SwiftUI

/// Placeholder. The real workout list and detail view (plan-verdict header, HR
/// curve, cadence, route map, splits) arrive with MAX-041 onward, once the design
/// system (MAX-040) and persistence layer (MAX-020) exist.
///
/// Still a placeholder — the only change MAX-040 made here was to put it on the
/// standard opaque content background, so the shell is not the one screen in the app
/// that ignores the design system. Real content is MAX-041's job.
struct WorkoutsView: View {
    var body: some View {
        Text("Workouts")
            .font(.screenTitle)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentSurface(.screen)
    }
}
