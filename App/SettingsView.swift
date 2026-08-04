import SwiftUI
import MaximizeCore

/// Placeholder. The real settings screen (rest-days-per-week, display/accessibility
/// prefs) arrives with MAX-064.
///
/// For now this exists to prove the app target actually links `MaximizeCore` — the
/// whole point of this ticket. Displaying `MaximizeCore.version` is the trivial,
/// visible proof of that linkage; it is not meant to be the real Settings content.
struct SettingsView: View {
    var body: some View {
        Text("MaximizeCore \(MaximizeCore.version)")
    }
}
