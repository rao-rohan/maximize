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
/// ## MAX-139: a lift does not compose the run-only sections
///
/// Cadence, the route map and the pace splits describe a running prescription
/// (LIFTING-SPEC §10.1) — a cadence target is steps against a running gait, a route and
/// its splits assume a distance — and none belongs on a lift's screen, not even in its
/// own "no data" state. `SummaryTileData.showsRunOnlySections` is where that is decided
/// and tested (`Sources/MaximizeCore/Metrics/SummaryTileData.swift`); this view reads
/// the one flag rather than comparing a discipline itself, so the rule cannot drift
/// between what the tests pin and what the screen actually composes. `RouteMapView` and
/// `SplitsView` already render nothing for an indoor workout on their own account
/// (`hasRoute == false`, true of every lift), so the flag here is belt-and-braces for
/// them and does the entire job for `CadenceBandView`, which — unlike those two — still
/// draws a full "no cadence data" card when its average is absent for any reason.
///
/// `SummaryTilesView` renders `SummaryTileData.disciplineNote` in the same pass — the
/// one sentence standing in for the sections this view leaves out, rather than a blank
/// where they used to be (CLAUDE.md: absence is a designed state). The HR curve stays
/// for every discipline (a heart rate measured during a lift is still a heart rate);
/// only its cap line is discipline-gated, and that happens in `WorkoutDetailModel`,
/// where the cap value is assembled from the plan.
///
/// ## MAX-180: the muscle map is the athlete's state, not this workout's
///
/// `MuscleMapView` draws `WorkoutDetailData.muscleFatigue` — MAX-179's per-group decay
/// model as of the moment this screen loaded, not a fact derived from `workoutID`.
/// Unlike the run-only sections above, it is not gated by
/// `SummaryTileData.showsRunOnlySections`: "where does my recovery stand right now" is
/// a question worth answering from a lift's screen exactly as much as a run's, so it
/// composes unconditionally, directly under the section that lets the athlete answer
/// it for *this* session (`MuscleGroupEntryView`).
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
            Text(FailureCopy.couldNotLoad(.workoutDetail))
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.hero)
        case let .loaded(data):
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                VerdictHeaderView(verdict: data.verdict, distanceUnit: data.distanceUnit)
                // Directly under the header, because on a lift the header is where the
                // question is asked and this is where it is answered (A22). Renders
                // nothing at all on a run — `MuscleGroupEntryData.isShown`.
                MuscleGroupEntryView(data: data.muscleGroups) { groups in
                    Task { await model.setMuscleGroups(groups) }
                }
                // MAX-180. The athlete's whole-body recovery state, not a fact about
                // this one workout — drawn on every discipline's screen, unlike the
                // run-only sections below, for the reason `WorkoutDetailData
                // .muscleFatigue` gives.
                MuscleMapView(map: data.muscleFatigue)
                // A heart rate measured during a lift is still a heart rate — this stays
                // for every discipline. Only its cap line is gated, in
                // `WorkoutDetailModel`, against the plan's *run* cap.
                HRCurveView(chartData: data.heartRateChart)
                // MAX-139: the three sections that describe a running prescription.
                // `showsRunOnlySections` is `SummaryTileData`'s decision, not this
                // view's — see the type doc comment above.
                if data.summaryTiles.showsRunOnlySections {
                    CadenceBandView(data: data.cadence)
                    RouteMapView(data: data.routeMap)
                    SplitsView(data: data.splits)
                }
                SummaryTilesView(data: data.summaryTiles)
                WorkoutChatSectionView(workoutID: workoutID)
            }
        }
    }
}
