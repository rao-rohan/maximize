import SwiftUI
import MaximizeCore

/// A single historical plan version, pushed from `PlanView`'s version-history list
/// (MAX-102, A15).
///
/// Reuses `PlanDetailSections` — the exact rendering the current-plan screen uses — so
/// a historical version reads as the same kind of record, not a lesser one. What it
/// deliberately does **not** carry over from `PlanView`:
///
/// - **No revise affordance.** Authoring a revision always supersedes the *current*
///   version (`PlanAuthoringSession`, D1); offering "revise" from an old version would
///   suggest a door that does not exist — you cannot resume editing history.
/// - **No version-history list of its own.** Drilling further is a pop back to
///   `PlanView` and a different tap, rather than a second copy of the same list one
///   level deeper. The back button is the way out.
struct PlanVersionDetailView: View {
    let version: PlanVersion

    @State private var model: PlanViewModel

    init(version: PlanVersion) {
        self.version = version
        _model = State(initialValue: PlanViewModel(version: version))
    }

    var body: some View {
        content
            .navigationTitle(PlanFormatting.versionTitle(version))
            .navigationBarTitleDisplayMode(.inline)
            .contentSurface(.screen)
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed, .loaded(.notAuthored, _):
            // `.notAuthored` is unreachable here — this screen only opens from a
            // version already read off a stored calendar — and folded into the same
            // failure copy as an opened store rather than given a distinct, dead
            // branch to maintain.
            Text("Couldn't load this plan version.")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(.authored(authored), distanceUnit):
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    PlanDetailSections(detail: authored.viewing, distanceUnit: distanceUnit)
                }
                .screenMargins()
                .padding(.vertical, Spacing.roomy)
            }
        }
    }
}
