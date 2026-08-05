import Foundation
import MaximizeCore
import Observation

/// Loads `TrendTileData` (FR-3.4) for the dashboard's selected `TrendInterval`. All of
/// this class does is fetch the records `TalliesCalculator` and `TrendTileData` need
/// and hand the result to the view — see CLAUDE.md's "thin shell": no date arithmetic,
/// no tallying, no formatting happens here, and since MAX-083 no choice about *which*
/// figures the span calls for either.
@MainActor
@Observable
final class TrendTilesModel {
    enum LoadState: Equatable {
        case loading
        case loaded(TrendTileData)
        /// A repository could not be opened, or a read failed. One case rather than
        /// several, matching `WorkoutsListModel.LoadState.failed` and
        /// `WorkoutDetailModel.LoadState.failed`.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?

    /// The zone the athlete's day boundary is drawn in. Matches `WorkoutDetailModel`'s
    /// own convention: `.current` is the honest default for a single-user, single-device
    /// app with no stored "athlete time zone" preference (A1) — never read as
    /// `TimeZone.current` inside `MaximizeCore` itself, only threaded in from here.
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository: each
    ///     defaults to `PersistenceComposition.store`. Overridable so a preview or a
    ///     test can inject fakes instead of the real on-device store.
    init(
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        timeZone: TimeZone = .current
    ) {
        self.workoutRepository = workoutRepository ?? PersistenceComposition.store
        self.scoreRepository = scoreRepository ?? PersistenceComposition.store
        self.planRepository = planRepository ?? PersistenceComposition.store
        self.settingsRepository = settingsRepository ?? PersistenceComposition.store
        self.timeZone = timeZone
    }

    func load(interval: TrendInterval) async {
        guard let workoutRepository, let scoreRepository, let planRepository, let settingsRepository else {
            state = .failed
            return
        }
        do {
            let planCalendar = try await planRepository.planCalendar()
            let settings = try await settingsRepository.settings()
            let restDayBudget = settings.restDayBudget

            // `TalliesInput.workouts` must cover the whole Monday-first weeks touching
            // the interval, not merely the interval itself (C1, see that type's own
            // documentation) — so the fetch is widened to those weeks before anything
            // else runs. The widening lives in `MaximizeCore` (MAX-083); before that it
            // was three lines of date arithmetic here, ending in a throwaway `.custom`
            // range built only to borrow the one sanctioned day-range → instant-range
            // conversion.
            let workouts = try await workoutRepository.workouts(
                startingIn: interval.trainingWeekAlignedDateInterval(in: timeZone)
            )

            var scoreLedgers: [UUID: ScoreLedger] = [:]
            for workout in workouts {
                if let ledger = try await scoreRepository.ledger(forWorkout: workout.id) {
                    scoreLedgers[workout.id] = ledger
                }
            }

            let talliesInput = try TalliesInput(
                from: interval.from,
                through: interval.through,
                timeZone: timeZone,
                workouts: workouts,
                scoreLedgers: scoreLedgers,
                planCalendar: planCalendar,
                restDayBudget: restDayBudget
            )
            let tallies = try TalliesCalculator.compute(talliesInput)

            // `workouts` is the widened C1 set; `TrendTileData` filters it back down to
            // `tallies.from...tallies.through` itself (see its own documentation), so
            // it is handed the same set rather than a second, narrower fetch.
            let tileData = try TrendTileData(
                // Which figures this span's tiles measure follows from the kind, through
                // the one table in `DashboardSpanPresentation.swift`. This model does not
                // choose a tile set — passing the kind is the whole of its involvement.
                kind: interval.kind,
                tallies: tallies,
                workouts: workouts,
                timeZone: timeZone,
                planCalendar: planCalendar,
                distanceUnit: settings.distanceUnit
            )
            state = .loaded(tileData)
        } catch {
            state = .failed
        }
    }
}
