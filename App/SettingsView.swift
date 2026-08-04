import SwiftUI
import MaximizeCore

/// Settings entry point for the Anthropic API key (MAX-022), plus the trivial
/// MaximizeCore-linkage proof from MAX-006. The real settings screen
/// (rest-days-per-week, display/accessibility prefs) still arrives with MAX-064.
///
/// Structurally plain on purpose — MAX-040 (design system) owns styling decisions,
/// not this ticket. No custom colors, fonts, or layout beyond a plain `Form`.
///
/// **The stored key is never shown here, not even partially masked.** This view
/// only ever asks the store whether a key is present (`retrieve() != nil`); it never
/// reads `.revealed()` on a key that came back from storage. The only raw key text
/// that exists is what the user is actively typing into the `SecureField` to set a
/// *new* key, and that never round-trips back onto screen once saved.
struct SettingsView: View {
    private let keyStore: AnthropicAPIKeyStoring

    @State private var isKeyStored = false
    @State private var isCheckingStatus = true
    @State private var enteredKey = ""
    @State private var statusMessage: String?

    init(keyStore: AnthropicAPIKeyStoring = KeychainAnthropicAPIKeyStore()) {
        self.keyStore = keyStore
    }

    var body: some View {
        Form {
            Section("MaximizeCore") {
                Text("MaximizeCore \(MaximizeCore.version)")
            }

            // MAX-030. The observer query is registered at launch without any user
            // action; only the permission sheet needs a foreground, which is why it
            // is here and not on the launch path.
            HealthAccessSettingsSection()

            Section("Anthropic API key") {
                storedKeyStatusRow

                SecureField("Anthropic API key", text: $enteredKey)
                    .textContentType(.password)
                    .disableAutocorrection(true)

                Button("Save", action: save)
                    .disabled(enteredKey.isEmpty)

                if isKeyStored {
                    Button("Clear", role: .destructive, action: clear)
                }

                if let statusMessage {
                    Text(statusMessage)
                }
            }
        }
        .onAppear(perform: refreshStoredStatus)
    }

    @ViewBuilder
    private var storedKeyStatusRow: some View {
        if isCheckingStatus {
            Text("Checking Keychain…")
        } else {
            Text(isKeyStored ? "A key is stored." : "No key is stored.")
        }
    }

    private func refreshStoredStatus() {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        do {
            isKeyStored = try keyStore.retrieve() != nil
        } catch {
            // Deliberately generic: whatever the underlying failure is, this label
            // is the only thing that reaches the screen or could reach a log if this
            // view were ever instrumented later.
            isKeyStored = false
            statusMessage = "Could not check Keychain status."
        }
    }

    private func save() {
        do {
            let key = try AnthropicAPIKey(enteredKey)
            try keyStore.store(key)
            enteredKey = ""
            statusMessage = "Key saved."
            refreshStoredStatus()
        } catch AnthropicAPIKeyError.emptyKey {
            statusMessage = "Enter a key first."
        } catch {
            statusMessage = "Could not save the key."
        }
    }

    private func clear() {
        do {
            try keyStore.delete()
            statusMessage = "Key cleared."
            refreshStoredStatus()
        } catch {
            statusMessage = "Could not clear the key."
        }
    }
}
