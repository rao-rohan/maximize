import SwiftUI

/// App entry point.
///
/// Deliberately thin: no business logic here. See CLAUDE.md — "thin shell, fat
/// core." Anything beyond wiring up the root view belongs in MaximizeCore.
@main
struct MaximizeApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
