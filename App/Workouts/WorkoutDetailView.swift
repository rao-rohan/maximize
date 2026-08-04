import SwiftUI
import MaximizeCore

/// The workout detail screen (FR-1.1–1.6).
///
/// MAX-041 built the plan-verdict header and the scaffold needed to reach it. MAX-042
/// adds the HR curve. MAX-043 adds cadence vs. target. Route map (MAX-044), splits
/// and summary tiles (MAX-045), and the chat entry point (MAX-051) all land as
/// further siblings inside `content` below — the seam is still this view's body, and
/// `WorkoutDetailData` (see `WorkoutDetailModel`) is where each of those adds its
/// section's data without touching `WorkoutVerdict`.
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel

    init(workoutID: UUID) {
        _model = State(initialValue: WorkoutDetailModel(workoutID: workoutID))
    }

    var body: some View {
        ScrollView {
            content
                .screenMargins()
                .padding(.vertical, Spacing.roomy)
        }
        .contentSurface(.screen)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Render what is stored first, then give a workout the background wake could
            // not score its chance (R8, MAX-033). Both steps are no-ops when there is
            // nothing to do, and neither decides anything: `scoreIfNeeded` forwards to the
            // core, which is where "does this run need a score?" is answered and tested.
            await model.load()
            await model.scoreIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.hero)
        case .failed:
            Text("Could not load this workout.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.hero)
        case let .loaded(data):
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                VerdictHeaderView(verdict: data.verdict)
                HRCurveView(chartData: data.heartRateChart)
                CadenceBandView(data: data.cadence)
                // MAX-044 (route map), MAX-045 (splits/tiles), MAX-051 (chat entry
                // point) land here.
            }
        }
    }
}
