import SwiftUI

/// Settings' entry point, now that it is not a tab (MAX-081).
///
/// Settings is a place you visit occasionally to change a preference and then leave.
/// A tab spends a permanent third of the tab bar on it and, worse, makes it a
/// *destination* — somewhere you navigate to and have to navigate back from. A toolbar
/// button plus a sheet costs nothing when it is not in use and returns you exactly
/// where you were, which is the interaction settings actually wants.
///
/// It is a `ViewModifier` rather than a copy-pasted `.toolbar` block in each tab
/// because there are two tabs today and the presentation — sheet, title, close button —
/// must not drift between them.
///
/// ## No glass here, deliberately
///
/// Both surfaces this touches are chrome, and both already get Liquid Glass from the
/// system on iOS 26: the navigation bar the button sits in (FR-4.1, see the note on
/// `ChromeRole`) and the sheet itself. Calling `glassChrome(_:)` on either would be
/// re-applying the platform's own material to the platform's own control.
extension View {

    /// Adds the app-wide Settings button to this screen's navigation bar.
    ///
    /// Apply it **inside** a `NavigationStack`, on the same view as the screen's
    /// `navigationTitle` — a toolbar attached outside the navigation container has no
    /// bar to attach to.
    func settingsToolbarItem() -> some View {
        modifier(SettingsToolbarItemModifier())
    }
}

private struct SettingsToolbarItemModifier: ViewModifier {
    @State private var isPresentingSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingSettings = true
                    } label: {
                        // Icon-only is stated rather than left to the toolbar's default
                        // so the bar's width does not depend on it, at any Dynamic Type
                        // size. `.iconOnly` still exposes the label's text to
                        // accessibility; the explicit `accessibilityLabel` pins it, so
                        // VoiceOver reads "Settings" and not a gear glyph (FR-4.5).
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isPresentingSettings) {
                SettingsSheet()
            }
    }
}

/// The sheet wrapper around `SettingsView`.
///
/// `SettingsView()` is constructed with no arguments on purpose: its initializer
/// defaults the key store to the real Keychain and forwards a nil repository to
/// `SettingsModel`, which resolves it to `PersistenceComposition.store` and treats a
/// store that would not open as `.failed`. There is no stub to default to (MAX-049,
/// tracker R13), and nothing here introduces one.
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
