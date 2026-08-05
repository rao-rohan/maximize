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

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task { await settingsModel.load() }
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
