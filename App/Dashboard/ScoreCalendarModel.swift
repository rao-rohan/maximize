import Foundation
import MaximizeCore
import Observation

/// Loads and resolves the score-colored calendar (FR-3.2, D4, D9, A6) for a selected
/// `TrendInterval`. All it does is fetch the records `ScoreCalendar.resolve` needs
/// and hand them over — see CLAUDE.md's "thin shell": the day-state decision itself
/// lives entirely in `MaximizeCore.ScoreCalendar`, unit tested there.
@MainActor
@Observable
final class ScoreCalendarModel {
    enum LoadState: Equatable {
        case loading
        case loaded([ScoreCalendarDay])
        /// A store could not be opened, or a read failed. See
        /// `WorkoutsListModel.LoadState.failed` for why this stays one case.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?

    /// The zone the athlete's day boundaries are drawn in — never `.current` read
    /// inside `MaximizeCore` (see `TrendInterval.dateInterval(in:)`'s own
    /// documentation), so this model is where it is decided, the same way
    /// `WorkoutDetailModel` and `TrendIntervalSelectionModel` each take it.
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository: each
    ///     defaults to the app's shared store. Overridable so a preview or a test can
    ///     inject fakes instead of the real on-device store.
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
        // The real store, like the three above it — never the no-op stub. Defaulting
        // this one to a stub is MAX-049's defect appearing a second time, and it bites
        // hardest here: the rest-day budget is what decides which missed days convert,
        // so a stubbed `.standard` colours the calendar with a budget the athlete never
        // chose, on the one screen where that choice is visible.
        self.settingsRepository = settingsRepository ?? PersistenceComposition.store
        self.timeZone = timeZone
    }

    /// Resolves the calendar for `interval`. Call again whenever the selection
    /// changes — `ScoreCalendarView` does this via `.task(id: interval)`, so a new
    /// selection always supersedes an in-flight load rather than racing it.
    func load(for interval: TrendInterval) async {
        guard let workoutRepository, let scoreRepository, let planRepository,
              let settingsRepository else {
            state = .failed
            return
        }
        do {
            // C1: `ScoreCalendar.resolve` must see every workout in the Monday-first
            // weeks touching the interval, not merely the interval itself — the same
            // obligation `TalliesInput.workouts` documents, for the identical reason
            // (`RestDayBudgeting` ranks a missed day against the other misses in its
            // week). Widen to week boundaries, then go through the one supported
            // `TrendInterval` → `DateInterval` conversion rather than inventing a
            // second one here.
            let widenedStart = try interval.from.startOfTrainingWeek()
            let widenedEnd = try interval.through.startOfTrainingWeek().adding(days: 6)
            let widenedRange = TrendInterval.custom(try CustomDateRange(start: widenedStart, end: widenedEnd))
            let workouts = try await workoutRepository.workouts(startingIn: widenedRange.dateInterval(in: timeZone))

            var scoreLedgers: [UUID: ScoreLedger] = [:]
            for workout in workouts {
                if let ledger = try await scoreRepository.ledger(forWorkout: workout.id) {
                    scoreLedgers[workout.id] = ledger
                }
            }

            let planCalendar = try await planRepository.planCalendar()
            let settings = try await settingsRepository.settings()

            let days = try ScoreCalendar.resolve(
                from: interval.from,
                through: interval.through,
                timeZone: timeZone,
                workouts: workouts,
                scoreLedgers: scoreLedgers,
                planCalendar: planCalendar,
                restDayBudget: settings.restDayBudget
            )
            state = .loaded(days)
        } catch {
            state = .failed
        }
    }
}
