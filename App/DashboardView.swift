import SwiftUI

/// Placeholder. The real dashboard (interval selector, score-colored calendar,
/// cross-run HR-drift overlay, summary tiles) arrives with MAX-060 onward.
///
/// MAX-040 only put it on the standard opaque content background. Everything the
/// dashboard actually shows is data, so every surface it grows should be a
/// `contentSurface` — never glass (FR-4.2).
struct DashboardView: View {
    var body: some View {
        Text("Dashboard")
            .font(.screenTitle)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentSurface(.screen)
    }
}
