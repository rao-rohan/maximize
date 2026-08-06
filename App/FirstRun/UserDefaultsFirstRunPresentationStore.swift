import Foundation
import MaximizeCore

/// The `UserDefaults`-backed adapter for `FirstRunPresentationRecording` (MAX-163,
/// FIRST-RUN-SPEC §4.4).
///
/// ## Why `UserDefaults`, and not the file `FileWorkoutQueryAnchorStore` uses
///
/// That store rejected `UserDefaults` explicitly: it writes back on its own schedule,
/// and the anchor's correctness depends on "durable the instant `save` returns" — a
/// promise `UserDefaults` does not make. A boolean saying "this device has shown the
/// cover" carries no such requirement. The failure mode of a delayed or lost write is the
/// cover appearing one extra time on a device that has already seen it — mildly
/// redundant, and iOS itself makes a repeat `requestAuthorization` call idempotent (it
/// completes without presenting anything once the sheet has been answered). That is a
/// world apart from the anchor's failure mode, which is a workout silently never
/// ingested. Where the anchor needed a promise `UserDefaults` cannot make, this flag
/// needs only "eventually true," which is exactly what `UserDefaults` is for — and it is
/// what FIRST-RUN-SPEC §4.4 names as "the obvious candidate."
///
/// ## Why not `AppSettings` (the SwiftData-backed settings record)
///
/// FIRST-RUN-SPEC §4.4, stated directly: a SwiftData record that fails to open would make
/// the cover reappear on every launch, and the one screen guaranteed to appear when the
/// store is broken should not be the one asking for health permissions. `UserDefaults` has
/// no comparable "the container failed to open" failure mode — reading an unset key
/// returns `false`, not an error, which is the correct default (a device that has never
/// recorded anything has, definitionally, never shown the cover).
///
/// ## What a reinstall does to this flag, stated rather than left implicit
///
/// `UserDefaults.standard` is scoped to the app's container and is removed along with it
/// on deletion, so a reinstall starts this flag at `false` again — the cover reappears,
/// which FIRST-RUN-SPEC §4.4 calls correct: A8 defers CloudKit, so a reinstall already
/// loses every workout, plan and score on the device, and re-asking the one question that
/// cannot be asked twice per install is exactly the intended behaviour, not a bug this
/// store needs to work around.
///
/// ## What this file is and is not tested by
///
/// Nothing here runs in CI: `UserDefaults` on the Linux `swift test` runner behaves like a
/// dictionary and proves nothing about real persistence across an app relaunch on a
/// device. `FirstRunCoverGateTests` (`MaximizeCoreTests`) proves the *decision* this store
/// feeds — `FirstRunCoverGate.shouldPresent(_:)` — against a fake that simulates a
/// relaunch by construction. What only a device can prove is listed in this ticket's PR
/// under "Needs device verification."
final class UserDefaultsFirstRunPresentationStore: FirstRunPresentationRecording {
    private let defaults: UserDefaults

    /// Namespaced with the app's reverse-DNS prefix. This is the first `UserDefaults` key
    /// this app writes — `AppearancePreference` (MAX-086) lives in the SwiftData-backed
    /// `AppSettings` instead — so there is no existing convention to match; the prefix is
    /// here so a future key never collides with this one by accident.
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.maximize.firstRun.hasPresentedHealthRequest") {
        self.defaults = defaults
        self.key = key
    }

    var hasPresentedHealthRequest: Bool {
        defaults.bool(forKey: key)
    }

    func recordHealthRequestPresented() {
        defaults.set(true, forKey: key)
    }
}
