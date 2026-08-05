import Foundation
import MaximizeCore
import Observation

/// Loads the runs in the selected interval and hands `MaximizeCore` everything it needs
/// to build the cross-run drift overlay (FR-3.3, D5).
///
/// Every decision about the overlay — which runs qualify, how a curve is normalised onto
/// the %-elapsed axis, how many are stacked, what each omission is called — lives in
/// `HeartRateDriftOverlayData` and is unit tested there. This class fetches records and
/// holds the athlete's stacking selection; it decides nothing.
///
/// **It deliberately does not pre-filter.** Every workout the interval contains becomes a
/// `Candidate`, including hard sessions and runs with no stored curve, so the reason a run
/// is missing from the chart is decided in one tested place rather than half here and half
/// there. That costs a heart-rate blob read for runs the overlay will not draw — D7 sizes
/// those for exactly this kind of whole-curve read, and correctness in one place is worth
/// more than the saved read.
@MainActor
@Observable
final class DriftOverlayModel {
    enum LoadState: Equatable {
        case loading
        case loaded(HeartRateDriftOverlayData)
        /// The store could not be opened, or a read failed. One case, matching
        /// `WorkoutDetailModel.LoadState.failed` — see its documentation for why.
        case failed
    }

    private(set) var state: LoadState = .loading

    /// Runs the athlete has un-stacked (FR-3.3's "selectable which runs are stacked").
    /// Held here rather than in the view because it survives a redraw, and rebuilding the
    /// overlay from it needs no refetch.
    private(set) var hiddenWorkoutIDs: Set<UUID> = []

    /// The interval's runs, kept so toggling a legend row re-derives the overlay from
    /// memory instead of hitting the store again.
    private var candidates: [HeartRateDriftOverlayData.Candidate] = []

    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?

    /// The athlete's zone, used for the one supported `TrendInterval` → `DateInterval`
    /// conversion. `.current` is the honest answer for a single-user, single-device app
    /// with no stored preference, the same call `WorkoutDetailModel` makes.
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutRepository/scoreRepository: each defaults to the app's shared store.
    ///     Overridable so a preview or a test can inject fakes instead of the real
    ///     on-device store.
    init(
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        timeZone: TimeZone = .current
    ) {
        self.workoutRepository = workoutRepository ?? PersistenceComposition.store
        self.scoreRepository = scoreRepository ?? PersistenceComposition.store
        self.timeZone = timeZone
    }

    /// Builds the overlay for `interval`. Call again whenever the selection changes —
    /// `DriftOverlayView` does this via `.task(id: interval)`, so a new selection always
    /// supersedes an in-flight load rather than racing it.
    func load(for interval: TrendInterval) async {
        guard let workoutRepository, let scoreRepository else {
            state = .failed
            return
        }
        do {
            // `TrendInterval.dateInterval(in:)` is the single supported conversion — it is
            // half-open, matching `workouts(startingIn:)`, so a run starting at midnight
            // belongs to exactly one interval. Nothing here reaches for `Calendar`.
            let dateInterval = try interval.dateInterval(in: timeZone)
            let workouts = try await workoutRepository.workouts(startingIn: dateInterval)

            var loaded: [HeartRateDriftOverlayData.Candidate] = []
            for workout in workouts {
                loaded.append(
                    HeartRateDriftOverlayData.Candidate(
                        workout: workout,
                        series: try await workoutRepository.heartRateSeries(forWorkout: workout.id),
                        // The classification the scorer stored on the immutable auto-score
                        // (D8). Read, never re-derived — see `Candidate.classification`.
                        classification: try await scoreRepository
                            .ledger(forWorkout: workout.id)?
                            .automatic
                            .actualClassification,
                        metrics: try await workoutRepository.derivedMetrics(forWorkout: workout.id)
                    )
                )
            }

            candidates = loaded
            // A selection made in one interval must not silently hide a run in another.
            hiddenWorkoutIDs.formIntersection(Set(workouts.map(\.id)))
            rebuild()
        } catch {
            state = .failed
        }
    }

    /// Adds or removes a run from the stack. Rebuilding is cheap and local: the curves are
    /// resampled from series already in memory.
    func toggleStacking(of workoutID: UUID) {
        if hiddenWorkoutIDs.contains(workoutID) {
            hiddenWorkoutIDs.remove(workoutID)
        } else {
            hiddenWorkoutIDs.insert(workoutID)
        }
        rebuild()
    }

    private func rebuild() {
        state = .loaded(
            HeartRateDriftOverlayData(candidates: candidates, hiddenWorkoutIDs: hiddenWorkoutIDs)
        )
    }
}
