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

    /// The athlete's current day, resolved once here and handed to `TalliesInput`
    /// (MAX-110). **This is the only place these tiles read a clock.**
    /// `TalliesCalculator` decides whether a scheduled day is still forthcoming or has
    /// been missed, and whether it is eligible to extend the streak, and it cannot do
    /// that without knowing what day it is — but a `Date()` inside `MaximizeCore`, or
    /// inside a SwiftUI `body`, would make that decision untestable and would re-read
    /// the wall clock on every render. So the ambient read happens here, exactly once,
    /// the same way `ScoreCalendarModel` resolves the `today` it hands to
    /// `ScoreCalendar.resolve` — the calendar and these tiles must describe the same
    /// day the same way, or the two halves of the same screen can disagree.
    ///
    /// Nil only when the system clock is outside `CalendarDay`'s 1...9999 AD domain,
    /// which surfaces as `.failed` rather than being guessed at.
    ///
    /// Captured at init, so an app left open across midnight keeps yesterday's boundary
    /// until the model is rebuilt — the same staleness `ScoreCalendarModel.today`
    /// already accepts and documents.
    private let today: CalendarDay?

    /// - Parameters:
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository: each
    ///     defaults to `PersistenceComposition.store`. Overridable so a preview or a
    ///     test can inject fakes instead of the real on-device store.
    ///   - today: defaults to now, in `timeZone`. Overridable for the same reason
    ///     `ScoreCalendarModel` allows it — a preview or a test pinning the day rather
    ///     than depending on when it happens to run.
    init(
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        today: CalendarDay? = nil,
        timeZone: TimeZone = .current
    ) {
        self.workoutRepository = workoutRepository ?? PersistenceComposition.store
        self.scoreRepository = scoreRepository ?? PersistenceComposition.store
        self.planRepository = planRepository ?? PersistenceComposition.store
        self.settingsRepository = settingsRepository ?? PersistenceComposition.store
        self.timeZone = timeZone
        self.today = today ?? (try? CalendarDay(Date(), in: timeZone))
    }

    func load(interval: TrendInterval) async {
        guard let workoutRepository, let scoreRepository, let planRepository, let settingsRepository,
              let today else {
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
                today: today,
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
