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
            let loadBalance = try await self.loadBalance(
                anchor: today,
                workoutRepository: workoutRepository
            )

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
                distanceUnit: settings.distanceUnit,
                loadBalance: loadBalance
            )
            state = .loaded(tileData)
        } catch {
            state = .failed
        }
    }

    /// The earliest calendar day a workout `WorkoutRepository` predates — used only to
    /// tell `LoadBalanceCalculator` whether the chronic window is fully inside the app's
    /// own horizon (`LoadBalanceInput.historyStart`, MAX-178). Not the athlete's actual
    /// training history: this app can only vouch for what it has stored.
    ///
    /// Bounded well before any HealthKit workout could plausibly exist rather than
    /// `Date.distantPast` — both are correct, but a concrete calendar day keeps the
    /// repository query inside `DateInterval.covering(from:through:in:)`'s ordinary
    /// contract instead of leaning on an extreme sentinel `Date`.
    private static let historyProbeFloor = (try? CalendarDay(year: 2010, month: 1, day: 1))

    /// Resolves `LoadBalanceCalculator.compute`'s input and calls it (MAX-178). Two
    /// repository reads: the chronic window itself, which the sums need regardless, and
    /// one bounded probe for "does anything exist before it" — cheaper than fetching
    /// every workout ever stored just to find the earliest one, and correct for the same
    /// reason `historyProbeFloor`'s doc comment gives: only *whether* history reaches
    /// back that far matters once it does, never the exact day it started.
    private func loadBalance(
        anchor: CalendarDay,
        workoutRepository: any WorkoutRepository
    ) async throws -> LoadBalanceReading {
        let chronicWindowStart = try anchor.adding(days: -(LoadBalanceCalculator.chronicWindowDays - 1))

        let chronicInterval = try DateInterval.covering(
            from: chronicWindowStart, through: anchor, in: timeZone
        )
        let chronicWorkouts = try await workoutRepository.workouts(startingIn: chronicInterval)

        var historyStart = anchor
        if let earliestChronicDay = try chronicWorkouts.map({ try $0.calendarDay(in: timeZone) }).min() {
            historyStart = earliestChronicDay
        }

        // Only worth probing further back when the chronic window's own earliest
        // workout has not already proven sufficiency on its own (a workout on the
        // window's first day already puts `historyStart` at or before it).
        if historyStart > chronicWindowStart, let floor = Self.historyProbeFloor, floor < chronicWindowStart {
            let priorInterval = try DateInterval.covering(
                from: floor,
                through: chronicWindowStart.adding(days: -1),
                in: timeZone
            )
            let priorWorkouts = try await workoutRepository.workouts(startingIn: priorInterval)
            if !priorWorkouts.isEmpty {
                // Sufficient either way — the exact day does not change the reading once
                // it is at or before `chronicWindowStart` (`LoadBalanceCalculator`'s
                // guard only compares against `chronicWindowDays`), so the window's own
                // start stands in for it rather than resolving a real minimum.
                historyStart = chronicWindowStart
            }
        }

        var derivedMetricsByWorkoutID: [UUID: DerivedMetrics] = [:]
        for workout in chronicWorkouts {
            if let metrics = try await workoutRepository.derivedMetrics(forWorkout: workout.id) {
                derivedMetricsByWorkoutID[workout.id] = metrics
            }
        }

        let input = try LoadBalanceInput(
            anchor: anchor,
            timeZone: timeZone,
            historyStart: historyStart,
            workouts: chronicWorkouts,
            derivedMetricsByWorkoutID: derivedMetricsByWorkoutID
        )
        return try LoadBalanceCalculator.compute(input)
    }
}
