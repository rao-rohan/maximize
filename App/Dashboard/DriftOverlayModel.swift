import Foundation
import MaximizeCore
import Observation

/// Loads the runs in the selected interval and hands `MaximizeCore` everything it needs
/// to build the HR-drift section (FR-3.3, D5) in whichever form that span calls for.
///
/// Every decision — which runs qualify, how a curve is normalised onto the %-elapsed
/// axis, how many are stacked, what each omission is called, and which of the two
/// representations a span gets — lives in `HeartRateDriftOverlayData`,
/// `DriftFigureSelection` and `DashboardSpanPresentation.swift`, and is unit tested
/// there. This class fetches records and holds the athlete's stacking selection; it
/// decides nothing.
///
/// ## Two load paths, and why the difference is not cosmetic (MAX-083)
///
/// At a **week or month** (`DriftSectionRepresentation.curveOverlayLed`) it deliberately
/// does not pre-filter. Every workout the interval contains becomes a `Candidate`,
/// including hard sessions and runs with no stored curve, so the reason a run is missing
/// from the chart is decided in one tested place rather than half here and half there.
/// That costs a heart-rate blob read for runs the overlay will not draw — D7 sizes those
/// for exactly this kind of whole-curve read, and correctness in one place is worth more
/// than the saved read.
///
/// At a **year** (`.trendlineOnly`) that trade reverses, because the chart the blobs
/// exist for is not on screen. ~200 runs would mean ~200 `.externalStorage` reads to draw
/// a dozen curves nobody asked for. So this path reads no curves at all: one stored drift
/// scalar and one stored classification per run, both small rows, into
/// `DriftFigureSelection`. `DriftSectionRepresentation.loadsStoredHeartRateCurves` is the
/// single place that says which path applies, so the view and the loader cannot disagree
/// about what is being drawn.
@MainActor
@Observable
final class DriftOverlayModel {
    enum LoadState: Equatable {
        case loading
        /// Week and month: the normalised curve stack, with its trendline beneath.
        case overlay(HeartRateDriftOverlayData)
        /// Year: the trendline alone, over every run carrying a stored drift figure.
        case trendline(DriftFigureSelection)
        /// The store could not be opened, or a read failed. One case, matching
        /// `WorkoutDetailModel.LoadState.failed` — see its documentation for why.
        case failed
    }

    private(set) var state: LoadState = .loading

    /// Runs the athlete has un-stacked (FR-3.3's "selectable which runs are stacked").
    /// Held here rather than in the view because it survives a redraw, and rebuilding the
    /// overlay from it needs no refetch. Meaningless in the trendline-only
    /// representation, which draws no per-run legend to toggle from.
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

    /// Builds the section for `interval`. Call again whenever the selection changes —
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
            // belongs to exactly one interval. Nothing here reaches for `Calendar`. Not
            // widened to whole weeks: unlike the calendar and the tiles, nothing in this
            // section consults the weekly rest-day budget, so C1 does not apply.
            let dateInterval = try interval.dateInterval(in: timeZone)
            let workouts = try await workoutRepository.workouts(startingIn: dateInterval)

            let representation = interval.kind.driftSectionRepresentation
            if representation.loadsStoredHeartRateCurves {
                try await loadCurves(workouts, from: workoutRepository, scores: scoreRepository)
            } else {
                try await loadStoredFigures(workouts, from: workoutRepository, scores: scoreRepository)
            }
        } catch {
            state = .failed
        }
    }

    private func loadCurves(
        _ workouts: [Workout],
        from workoutRepository: any WorkoutRepository,
        scores scoreRepository: any ScoreRepository
    ) async throws {
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
    }

    /// No `heartRateSeries(forWorkout:)` call anywhere in this path — that omission is
    /// the point of the year representation, not an oversight. See the type's own
    /// documentation.
    private func loadStoredFigures(
        _ workouts: [Workout],
        from workoutRepository: any WorkoutRepository,
        scores scoreRepository: any ScoreRepository
    ) async throws {
        var loaded: [DriftFigureSelection.Candidate] = []
        for workout in workouts {
            loaded.append(
                DriftFigureSelection.Candidate(
                    workoutID: workout.id,
                    start: workout.start,
                    classification: try await scoreRepository
                        .ledger(forWorkout: workout.id)?
                        .automatic
                        .actualClassification,
                    driftFraction: try await workoutRepository
                        .derivedMetrics(forWorkout: workout.id)?
                        .heartRateDriftFraction
                )
            )
        }

        // Curves belonging to a previous, shorter selection must not survive into this
        // one: the legend they back is not drawn here, and holding them would keep the
        // memory a year view exists to avoid.
        candidates = []
        hiddenWorkoutIDs = []
        state = .trendline(DriftFigureSelection(candidates: loaded))
    }

    /// Adds or removes a run from the stack. Rebuilding is cheap and local: the curves are
    /// resampled from series already in memory. A no-op in the trendline-only
    /// representation, which has no legend to tap.
    func toggleStacking(of workoutID: UUID) {
        guard case .overlay = state else { return }
        if hiddenWorkoutIDs.contains(workoutID) {
            hiddenWorkoutIDs.remove(workoutID)
        } else {
            hiddenWorkoutIDs.insert(workoutID)
        }
        rebuild()
    }

    private func rebuild() {
        state = .overlay(
            HeartRateDriftOverlayData(candidates: candidates, hiddenWorkoutIDs: hiddenWorkoutIDs)
        )
    }
}
