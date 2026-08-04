import SwiftUI

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

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
