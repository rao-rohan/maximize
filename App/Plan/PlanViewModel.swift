import Foundation
import MaximizeCore
import Observation

/// Loads `PlanDisplayData` for the plan tab (MAX-102) and, when pushed with a specific
/// `version`, for a historical version's own screen.
///
/// **No plan logic lives here.** Which version counts as current, how a superseded
/// version's effective range reads, and which arc week is "this week" are all
/// `PlanDisplayData.build(from:viewing:today:)`'s answers, computed in `MaximizeCore`
/// under test. What is genuinely this layer's is the same two things every other model
/// in `App/` owns: reading the wall clock, and picking a time zone to turn an instant
/// into a civil day — see `WorkoutDetailModel` and `PlanAuthoringModel` for the same
/// split.
@MainActor
@Observable
final class PlanViewModel {

    enum LoadState: Equatable {
        case loading
        /// The display data, and the athlete's chosen `DistanceUnit` (MAX-047) — kept
        /// unlabelled and positional, matching every other `LoadState` in `App/`.
        case loaded(PlanDisplayData, DistanceUnit)
        /// The store could not be opened, or a read failed. Never shown for "no plan
        /// exists" — that is `PlanDisplayData.notAuthored`, a loaded state.
        case failed
    }

    private(set) var state: LoadState = .loading

    /// Nil shows the current plan (the tab root). Non-nil pins the screen to one
    /// historical version, regardless of what gets authored later.
    private let version: PlanVersion?

    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?
    private let timeZone: TimeZone
    private let todayOverride: CalendarDay?

    /// - Parameters:
    ///   - version: which stored version to show. Nil for the tab root (the current
    ///     plan); a specific version when pushed from the history list.
    ///   - planRepository/settingsRepository: default to `PersistenceComposition.store`
    ///     — never to a stub (MAX-049, tracker R13). Overridable only for previews and
    ///     tests.
    ///   - today: the athlete's civil day. Defaults to now in `timeZone`; pinned by
    ///     tests and previews so the screen does not depend on the wall clock.
    ///   - timeZone: `.current`, matching `WorkoutDetailModel` and
    ///     `PlanAuthoringModel`'s own convention for a single-user, single-device app.
    init(
        version: PlanVersion? = nil,
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        today: CalendarDay? = nil,
        timeZone: TimeZone = .current
    ) {
        self.version = version
        if let planRepository {
            self.planRepository = planRepository
        } else {
            self.planRepository = PersistenceComposition.store
        }
        if let settingsRepository {
            self.settingsRepository = settingsRepository
        } else {
            self.settingsRepository = PersistenceComposition.store
        }
        self.timeZone = timeZone
        self.todayOverride = today
    }

    func load() async {
        guard let planRepository,
              let today = todayOverride ?? (try? CalendarDay(Date(), in: timeZone))
        else {
            state = .failed
            return
        }
        do {
            let calendar = try await planRepository.planCalendar()
            let display = try PlanDisplayData.build(from: calendar, viewing: version, today: today)
            state = .loaded(display, await loadedDistanceUnit())
        } catch {
            state = .failed
        }
    }

    /// A settings read that fails is not a reason to refuse to show the plan — the unit
    /// is a display preference, and `AppSettings.standard`'s is a defensible answer.
    /// Mirrors `PlanAuthoringModel.loadedDistanceUnit()`.
    private func loadedDistanceUnit() async -> DistanceUnit {
        guard let settingsRepository,
              let settings = try? await settingsRepository.settings()
        else {
            return AppSettings.standard.distanceUnit
        }
        return settings.distanceUnit
    }
}
