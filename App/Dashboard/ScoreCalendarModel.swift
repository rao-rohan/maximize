import Foundation
import MaximizeCore
import Observation

/// Loads and resolves the score-colored calendar (FR-3.2, D4, D9, A6) for a selected
/// `TrendInterval`. All it does is fetch the records `ScoreCalendar.resolve` needs
/// and hand them over — see CLAUDE.md's "thin shell": the day-state decision itself
/// lives entirely in `MaximizeCore.ScoreCalendar`, and *where each day goes* in
/// `MaximizeCore.ScoreCalendarLayout`, both unit tested there.
///
/// **What a year costs to load.** 365 days is one workout query, one ledger read per
/// workout in the range, one plan-calendar read and one settings read — a few hundred
/// small rows, and no `.externalStorage` blobs: nothing on this surface reads a
/// heart-rate curve or a GPS track. The day-state resolution itself is a linear pass over
/// the range. This is the surface a year scales on most easily; the drift section is the
/// one that needed a different representation to stay affordable (see
/// `DriftSectionRepresentation.loadsStoredHeartRateCurves`).
///
/// **MAX-105 added no reads.** The plan layer needs the plan calendar, which was already
/// being loaded for the missed/rest decision, and the plan-versus-execution comparison
/// comes off the score ledgers this model already fetches — `Score` carries both the
/// prescription it judged against and the classification MAX-013 stored (D2). The only
/// new input is `today`, which costs one clock read at init.
@MainActor
@Observable
final class ScoreCalendarModel {
    enum LoadState: Equatable {
        case loading
        case loaded(ScoreCalendarLayout)
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

    /// The athlete's current day, resolved once here and handed to
    /// `ScoreCalendar.resolve` (MAX-105).
    ///
    /// **This is the only place in the calendar that reads a clock.** The core decides
    /// whether a scheduled day is forthcoming or missed, and it cannot do that without
    /// knowing what day it is — but a `Date()` inside `MaximizeCore`, or inside a
    /// SwiftUI `body`, would make that decision untestable and would re-read the wall
    /// clock on every render. So the ambient read happens here, in the shell, exactly
    /// once, the same way `TrendIntervalSelectionModel` resolves the day its three
    /// interval shapes are relative to.
    ///
    /// Nil only when the system clock is outside `CalendarDay`'s 1...9999 AD domain,
    /// which surfaces as `.failed` rather than being guessed at — again matching
    /// `TrendIntervalSelectionModel.State.failed`.
    ///
    /// It is captured at init, so an app left open across midnight keeps yesterday's
    /// boundary until the model is rebuilt. That is the same staleness the interval
    /// selector already has (its "this week" does not roll over either), and it is worth
    /// stating rather than hiding: the visible consequence is that yesterday's scheduled
    /// run keeps reading as forthcoming for one extra day.
    private let today: CalendarDay?

    /// - Parameters:
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository: each
    ///     defaults to the app's shared store. Overridable so a preview or a test can
    ///     inject fakes instead of the real on-device store.
    ///   - today: defaults to now, in `timeZone`. Overridable for the same reason
    ///     `TrendIntervalSelectionModel` allows it — a preview or a test pinning the day
    ///     rather than depending on when it happens to run.
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
        // The real store, like the three above it — never the no-op stub. Defaulting
        // this one to a stub is MAX-049's defect appearing a second time, and it bites
        // hardest here: the rest-day budget is what decides which missed days convert,
        // so a stubbed `.standard` colours the calendar with a budget the athlete never
        // chose, on the one screen where that choice is visible.
        self.settingsRepository = settingsRepository ?? PersistenceComposition.store
        self.timeZone = timeZone
        self.today = today ?? (try? CalendarDay(Date(), in: timeZone))
    }

    /// Resolves the calendar for `interval`. Call again whenever the selection
    /// changes — `ScoreCalendarView` does this via `.task(id: interval)`, so a new
    /// selection always supersedes an in-flight load rather than racing it.
    func load(for interval: TrendInterval) async {
        guard let workoutRepository, let scoreRepository, let planRepository,
              let settingsRepository, let today else {
            state = .failed
            return
        }
        do {
            // C1: `ScoreCalendar.resolve` must see every workout in the Monday-first
            // weeks touching the interval, not merely the interval itself — the same
            // obligation `TalliesInput.workouts` documents, for the identical reason
            // (`RestDayBudgeting` ranks a missed day against the other misses in its
            // week). The widening is `MaximizeCore`'s, not this model's: before MAX-083
            // it was three lines of date arithmetic here, ending in a throwaway
            // `.custom` range built only to borrow the one supported day-range → instant
            // -range conversion.
            let workouts = try await workoutRepository.workouts(
                startingIn: interval.trainingWeekAlignedDateInterval(in: timeZone)
            )

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
                today: today,
                workouts: workouts,
                scoreLedgers: scoreLedgers,
                planCalendar: planCalendar,
                restDayBudget: settings.restDayBudget
            )
            // Which arrangement this span gets, and the arrangement itself, are both
            // decided in the core (`DashboardSpanPresentation.swift`,
            // `ScoreCalendarLayout`). This model picks nothing.
            state = .loaded(
                try ScoreCalendarLayout.resolve(days, as: interval.kind.scoreCalendarRepresentation)
            )
        } catch {
            state = .failed
        }
    }
}
