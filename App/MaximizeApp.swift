import SwiftUI
import MaximizeCore

/// App entry point.
///
/// Deliberately thin: no business logic here. See CLAUDE.md — "thin shell, fat
/// core." Anything beyond wiring up the root view belongs in MaximizeCore.
@main
struct MaximizeApp: App {
    /// Present solely so HealthKit observer queries can be registered from
    /// `application(_:didFinishLaunchingWithOptions:)`, which Apple requires for
    /// background delivery (FR-0.1). A SwiftUI-only lifecycle has no equivalent hook
    /// that is guaranteed to run on a launch where iOS never builds a scene — and a
    /// background wake is exactly that kind of launch. See `MaximizeAppDelegate`.
    @UIApplicationDelegateAdaptor(MaximizeAppDelegate.self) private var appDelegate

    /// MAX-086. `.shared` — the same instance `SettingsView` reads and writes — so an
    /// appearance change made in the settings sheet is observed here too, and this is
    /// the one place in the app `AppearancePreference` is turned into
    /// `.preferredColorScheme`. See `SettingsModel.shared`'s docs for why one shared
    /// instance, not two independently loaded ones, is what makes the change apply
    /// without a relaunch.
    @State private var settingsModel = SettingsModel.shared

    /// MAX-169. Whether there is a store at all — the one fact that decides between the
    /// app and a single screen saying why there is not. Constructed here rather than
    /// inside `RootTabView` because the answer has to be known *before* the tabs exist:
    /// mounting them is what builds every screen's model, and a model built while the
    /// store is shut holds that nil for the life of the process.
    @State private var storeAvailability = StoreAvailabilityModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let notice = storeAvailability.notice {
                    StoreUnavailableView(notice: notice) { storeAvailability.perform($0) }
                } else {
                    RootTabView()
                }
            }
            // `id:` rather than a bare `.task`, so a store that opened on a second attempt
            // gets its settings read. The first run of this happened while there was no
            // repository to read from, which left `state == .failed` — and a screen that
            // still says settings could not be loaded, after the app has just told the
            // athlete their history opened, would be the app disagreeing with itself.
            .task(id: storeAvailability.availability.isUsable) { await settingsModel.load() }
            .preferredColorScheme(preferredColorScheme)
        }
    }

    /// `AppearancePreference` → `ColorScheme?` is a platform-facing decision, so
    /// `MaximizeCore` only goes as far as `ResolvedColorScheme?` (it cannot import
    /// SwiftUI — see CLAUDE.md). This is the single place that last step happens.
    ///
    /// `.loading` and `.failed` both resolve to `nil` — impose nothing — rather than
    /// guessing at a scheme before the real preference is known, or after the store
    /// has failed to open. Forcing one here would just be a different way of
    /// disregarding what the athlete actually chose, which is the whole defect this
    /// ticket fixes.
    private var preferredColorScheme: ColorScheme? {
        guard case let .loaded(settings) = settingsModel.state else { return nil }
        switch settings.appearance.resolvedColorScheme {
        case .light: return .light
        case .dark: return .dark
        case nil: return nil
        }
    }
}
