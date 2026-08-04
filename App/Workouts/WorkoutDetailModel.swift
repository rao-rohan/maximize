import Foundation
import MaximizeCore
import Observation

/// Loads one workout and derives its `WorkoutVerdict` (MaximizeCore) for the detail
/// screen's header. Everything that decides *what the header should say* — unscored
/// vs. scored, plan vs. no plan, auto-score vs. correction — lives in `WorkoutVerdict`
/// and is unit tested there; this class only fetches the three records that feed it
/// and hands the result to the view.
@MainActor
@Observable
final class WorkoutDetailModel {
    enum LoadState: Equatable {
        case loading
        case loaded(verdict: WorkoutVerdict)
        /// The store could not be opened, the workout no longer exists, or a read
        /// failed. See `WorkoutsListModel.LoadState.failed` for why this stays one
        /// case rather than several.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let workoutID: UUID
    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?

    /// The zone the athlete's day boundary is drawn in. `Workout.calendarDay(in:)`
    /// requires one rather than guessing (see its doc comment); `.current` is the
    /// honest answer for a single-user, single-device app with no stored preference
    /// for it (PRD's device-only scope, A1).
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutID: which workout to load.
    ///   - workoutRepository/scoreRepository/planRepository: each defaults to
    ///     `PersistenceComposition.store`. Overridable so a preview or a future test
    ///     can inject fakes instead of the real on-device store.
    init(
        workoutID: UUID,
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        timeZone: TimeZone = .current
    ) {
        self.workoutID = workoutID
        if let workoutRepository {
            self.workoutRepository = workoutRepository
        } else {
            self.workoutRepository = PersistenceComposition.store
        }
        if let scoreRepository {
            self.scoreRepository = scoreRepository
        } else {
            self.scoreRepository = PersistenceComposition.store
        }
        if let planRepository {
            self.planRepository = planRepository
        } else {
            self.planRepository = PersistenceComposition.store
        }
        self.timeZone = timeZone
    }

    func load() async {
        guard let workoutRepository, let scoreRepository, let planRepository else {
            state = .failed
            return
        }
        do {
            guard let workout = try await workoutRepository.workout(id: workoutID) else {
                state = .failed
                return
            }
            let ledger = try await scoreRepository.ledger(forWorkout: workoutID)
            let planCalendar = try await planRepository.planCalendar()
            let day = try workout.calendarDay(in: timeZone)
            let planDay = try planCalendar?.planDay(on: day)

            state = .loaded(verdict: WorkoutVerdict(workout: workout, planDay: planDay, ledger: ledger))
        } catch {
            state = .failed
        }
    }
}
