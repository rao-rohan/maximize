import Foundation
import MaximizeCore
import Observation

/// Loads and persists `AppSettings` for the settings screen (MAX-049). Mirrors every
/// other repository-backed screen's model — `WorkoutsListModel`, `WorkoutDetailModel`,
/// `TrendTilesModel`, `ScoreCalendarModel` — down to the `LoadState` shape: the view
/// only observes `state` and forwards edits to `save(_:)`; no repository selection or
/// persistence decision is made in the view itself.
///
/// **Why this exists.** MAX-049 was `SettingsView` reaching a no-op stub because a
/// defaulted initialiser parameter silently fell back to one. The fix is not "make the
/// stub write somewhere real" — it is to give the store the same reachable-only-through-
/// `PersistenceComposition.store` shape every other screen already has, so the same
/// mistake can't recur here by a future edit defaulting a parameter differently.
@MainActor
@Observable
final class SettingsModel {
    enum LoadState: Equatable {
        case loading
        case loaded(AppSettings)
        /// The store could not be opened, or a read/write failed. Deliberately one
        /// case, matching `WorkoutsListModel.LoadState.failed` and siblings — and
        /// deliberately *not* the same as `.loaded(.standard)`. `.standard` is the
        /// honest answer for an athlete who has never touched a setting; `.failed` is
        /// the honest answer for an athlete whose store is unavailable. Showing
        /// `.standard` for the second case would let a rest-day budget look saved
        /// when nothing was, or could be, written — exactly MAX-049's defect.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let settingsRepository: (any SettingsRepository)?

    /// - Parameter settingsRepository: defaults to `PersistenceComposition.store`.
    ///   Overridable so a preview or a test can inject a fake instead of reaching for
    ///   the real on-device store. There is deliberately no other fallback: MAX-049
    ///   was exactly a defaulted parameter reaching a no-op stub in production, and
    ///   this type must not give a future caller the same footgun.
    init(settingsRepository: (any SettingsRepository)? = nil) {
        if let settingsRepository {
            self.settingsRepository = settingsRepository
        } else {
            self.settingsRepository = PersistenceComposition.store
        }
    }

    func load() async {
        guard let settingsRepository else {
            state = .failed
            return
        }
        do {
            state = .loaded(try await settingsRepository.settings())
        } catch {
            state = .failed
        }
    }

    /// Persists `settings` and only then reflects it in `state`. Deliberately not
    /// optimistic: `state` must equal what the repository actually holds, never what
    /// the screen merely hopes it holds — an edit that fails to persist moves the
    /// whole screen to `.failed` rather than leaving a stale, unsaved value on
    /// display, the same "looks saved, isn't" shape MAX-049 fixes at the load path.
    func save(_ settings: AppSettings) async {
        guard let settingsRepository else {
            state = .failed
            return
        }
        do {
            try await settingsRepository.store(settings)
            state = .loaded(settings)
        } catch {
            state = .failed
        }
    }
}
