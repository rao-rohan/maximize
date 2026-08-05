import Foundation
import MaximizeCore
import Observation

/// Everything `WorkoutsView` needs to render one row: the workout itself plus the
/// athlete's distance unit (MAX-047) each row formats its distance in — bundled the
/// same way `WorkoutDetailData` bundles a workout's sections, so the unit does not
/// need a `LoadState` case of its own.
struct WorkoutsListData: Equatable {
    let workouts: [Workout]
    let distanceUnit: DistanceUnit
}

/// Loads the workout list. All it does is call the repository and hold the result —
/// see CLAUDE.md's "thin shell": there is no filtering, scoring, or date logic here,
/// only the async plumbing a SwiftUI view cannot do for itself.
@MainActor
@Observable
final class WorkoutsListModel {
    enum LoadState: Equatable {
        case loading
        case loaded(WorkoutsListData)
        /// The store could not be opened, or the read failed. Deliberately one case
        /// rather than several: the distinctions a user could act on (wrong disk
        /// permissions vs. a migration failure) don't exist yet, and inventing them
        /// here would be guessing at a diagnosis this layer cannot make.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let workoutRepository: (any WorkoutRepository)?
    private let settingsRepository: (any SettingsRepository)?

    /// - Parameters:
    ///   - workoutRepository/settingsRepository: each defaults to
    ///     `PersistenceComposition.store`. Overridable so a preview or a future test
    ///     can hand this a fake instead of reaching for the real on-device store.
    init(
        workoutRepository: (any WorkoutRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil
    ) {
        if let workoutRepository {
            self.workoutRepository = workoutRepository
        } else {
            self.workoutRepository = PersistenceComposition.store
        }
        if let settingsRepository {
            self.settingsRepository = settingsRepository
        } else {
            self.settingsRepository = PersistenceComposition.store
        }
    }

    func load() async {
        guard let workoutRepository, let settingsRepository else {
            state = .failed
            return
        }
        do {
            // Every workout, most recent first. FR-3.1's interval selector is the
            // dashboard's (MAX-060), not this list's — narrowing the range here would
            // be inventing a filter this ticket has no requirement for.
            let workouts = try await workoutRepository.workouts(
                startingIn: DateInterval(start: .distantPast, end: .distantFuture)
            )
            let distanceUnit = try await settingsRepository.settings().distanceUnit
            state = .loaded(WorkoutsListData(
                workouts: workouts.sorted { $0.start > $1.start },
                distanceUnit: distanceUnit
            ))
        } catch {
            state = .failed
        }
    }
}
