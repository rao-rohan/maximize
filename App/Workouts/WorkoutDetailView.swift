import SwiftUI
import MaximizeCore

/// The workout detail screen (FR-1.1–1.6).
///
/// MAX-041 built the plan-verdict header and the scaffold needed to reach it. MAX-042
/// adds the HR curve. MAX-043 adds cadence vs. target. Route map (MAX-044), summary
/// tiles (MAX-045), the pace splits (MAX-046), and the chat entry point (MAX-051) all
/// land as further siblings inside `content` below — the seam is still this view's body, and
/// `WorkoutDetailData` (see `WorkoutDetailModel`) is where each of those adds its
/// section's data without touching `WorkoutVerdict`.
///
/// ## MAX-098: this screen tells the Ask button what it is looking at
///
/// The persistent chat control is subject-aware (§2.1): on this screen it reads "Ask
/// about this run" and opens *this run's* thread rather than a training one.
/// `chatEntryPointFocus(workoutID:)` is the whole of this view's part in that — it
/// reports an identifier while the screen is on top and nothing else. Every decision
/// downstream of it, including the rule that makes paging between two runs
/// (`DayWorkoutsView`) land on the right one, is `ChatEntryPoint` in `MaximizeCore`.
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel

    /// Kept alongside `model` (rather than read back out of it) purely so `content`
    /// below can hand it to `WorkoutChatSectionView`, whose sheet owns its own
    /// `ChatModel` (MAX-051) and is loaded independently of
    /// `WorkoutDetailModel`'s read-only snapshot — chat is live and bidirectional, not
    /// another `WorkoutDetailData` field.
    private let workoutID: UUID

    init(workoutID: UUID) {
        self.workoutID = workoutID
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
        .chatEntryPointFocus(workoutID: workoutID)
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
                VerdictHeaderView(verdict: data.verdict, distanceUnit: data.distanceUnit)
                HRCurveView(chartData: data.heartRateChart)
                CadenceBandView(data: data.cadence)
                RouteMapView(data: data.routeMap)
                SplitsView(data: data.splits)
                SummaryTilesView(data: data.summaryTiles)
                WorkoutChatSectionView(workoutID: workoutID)
            }
        }
    }
}
