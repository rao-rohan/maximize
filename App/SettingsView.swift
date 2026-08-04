import SwiftUI
import MaximizeCore

/// Complete settings screen for the app (MAX-064).
///
/// Manages:
/// - Rest days per week (D9/A6): how many missed days per week can be converted to rest
/// - Display preferences: distance unit (km/miles), appearance (system/light/dark)
/// Accessibility is deliberately absent — the app honours the OS settings directly
/// rather than offering its own switches. See the note further down for why.
/// - Anthropic API key (MAX-022): entry point for authentication
/// - Health access (MAX-030): HealthKit permission request
///
/// All settings are persisted through the `SettingsRepository` and survive relaunch.
///
/// **The stored API key is never shown here, not even partially masked.** This view
/// only ever asks the store whether a key is present; it never reads or displays
/// an actual key. The only raw key text that exists is what the user actively types
/// into the `SecureField`, and that never round-trips back onto screen once saved.
struct SettingsView: View {
    private let keyStore: AnthropicAPIKeyStoring
    private let settingsRepository: SettingsRepository

    @State private var isKeyStored = false
    @State private var enteredKey = ""
    @State private var keyStatusMessage: String?

    @State private var appSettings: AppSettings = .standard

    init(
        keyStore: AnthropicAPIKeyStoring = KeychainAnthropicAPIKeyStore(),
        settingsRepository: SettingsRepository? = nil
    ) {
        self.keyStore = keyStore
        // In production, injected via environment; in tests, a custom impl is passed
        self.settingsRepository = settingsRepository ?? DefaultSettingsRepository.shared
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

            // MAX-064: Rest days per week (D9/A6)
            restDaysSection

            // MAX-064: Display preferences
            displaySection

            // MAX-022: Anthropic API key section (keep styled consistently)
            Section("Anthropic API key") {
                Text(isKeyStored ? "A key is stored." : "No key is stored.")

                SecureField("Anthropic API key", text: $enteredKey)
                    .textContentType(.password)
                    .disableAutocorrection(true)

                Button("Save", action: saveKey)
                    .disabled(enteredKey.isEmpty)

                if isKeyStored {
                    Button("Clear", role: .destructive, action: clearKey)
                }

                if let keyStatusMessage {
                    Text(keyStatusMessage)
                        .font(.metricLabel)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .onAppear(perform: loadSettings)
    }

    // MARK: - Rest days section

    @ViewBuilder
    private var restDaysSection: some View {
        Section("Training plan") {
            HStack {
                Text("Discretionary rest days per week")
                Spacer()
                Picker(
                    "Rest days",
                    selection: Binding(
                        get: { appSettings.restDayBudget.daysPerWeek },
                        set: { newValue in
                            if let budget = try? RestDayBudget(daysPerWeek: newValue) {
                                appSettings.restDayBudget = budget
                                Task { await saveSettings() }
                            }
                        }
                    )
                ) {
                    ForEach(0...7, id: \.self) { days in
                        Text("\(days)").tag(days)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Display preferences section

    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            Picker("Distance unit", selection: $appSettings.distanceUnit) {
                Text("Miles").tag(DistanceUnit.miles)
                Text("Kilometers").tag(DistanceUnit.kilometers)
            }

            Picker("Appearance", selection: $appSettings.appearance) {
                Text("System").tag(AppearancePreference.system)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
        }
        .onChange(of: appSettings.distanceUnit) { _, _ in
            Task { await saveSettings() }
        }
        .onChange(of: appSettings.appearance) { _, _ in
            Task { await saveSettings() }
        }
    }

    // MARK: - Accessibility
    //
    // There are deliberately no accessibility toggles here, and the omission is the
    // decision rather than an oversight.
    //
    // FR-4.5 asks the app to *honour* Reduce Transparency and Increase Contrast, and
    // MAX-040 already does: `glassChrome(_:)` reads the system value from
    // `@Environment(\.accessibilityReduceTransparency)`, and every colour token is a
    // four-way `Ink` whose high-contrast variants the OS selects on a trait change.
    // Nothing in the app reads `AppSettings` for any of this.
    //
    // So an in-app toggle would have been inert — it would persist a value nothing
    // consumes, which is worse than no control at all because it looks like one. And
    // wiring it up naively would be worse still: a switch that turns Reduce
    // Transparency *off* while iOS has it *on* is an accessibility regression wearing
    // a preference's clothing.
    //
    // `AppSettings` keeps the three fields — its own documentation calls them
    // *overrides* the app layer must seed from system values. Whichever ticket first
    // consumes them owes two things this ticket was not scoped to decide: seeding from
    // the system, and override-up-only semantics, so a user may strengthen an
    // accessibility setting but never defeat one the OS has asked for.

    // MARK: - Settings persistence

    private func loadSettings() {
        Task {
            do {
                appSettings = try await settingsRepository.settings()
                refreshStoredKeyStatus()
            } catch {
                keyStatusMessage = "Could not load settings."
            }
        }
    }

    private func saveSettings() async {
        do {
            try await settingsRepository.store(appSettings)
        } catch {
            keyStatusMessage = "Could not save settings."
        }
    }

    // MARK: - Key management

    private func refreshStoredKeyStatus() {
        do {
            isKeyStored = try keyStore.retrieve() != nil
        } catch {
            isKeyStored = false
            keyStatusMessage = "Could not check Keychain status."
        }
    }

    private func saveKey() {
        do {
            let key = try AnthropicAPIKey(enteredKey)
            try keyStore.store(key)
            enteredKey = ""
            keyStatusMessage = "Key saved."
            refreshStoredKeyStatus()
        } catch AnthropicAPIKeyError.emptyKey {
            keyStatusMessage = "Enter a key first."
            // FIX MAX-064 defect: keep enteredKey as-is so user can retry
        } catch {
            keyStatusMessage = "Could not save the key."
            // FIX MAX-064 defect: clear enteredKey on failure so sensitive data doesn't linger
            enteredKey = ""
        }
    }

    private func clearKey() {
        do {
            try keyStore.delete()
            keyStatusMessage = "Key cleared."
            refreshStoredKeyStatus()
        } catch {
            keyStatusMessage = "Could not clear the key."
        }
    }
}

// MARK: - Repository injection stub

/// Placeholder settings repository for when the real one cannot be injected.
/// The app container overrides this at launch with the real MaximizeStore.
actor DefaultSettingsRepository: SettingsRepository {
    static let shared = DefaultSettingsRepository()

    private init() {}

    func settings() async throws -> AppSettings {
        .standard
    }

    func store(_ settings: AppSettings) async throws {
        // No-op stub
    }
}
