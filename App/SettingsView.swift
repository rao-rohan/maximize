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
/// All settings are persisted through `SettingsModel`, which talks to the real
/// on-device store (`PersistenceComposition.store`), and survive relaunch.
///
/// **MAX-049.** Before this ticket, this view's `settingsRepository` parameter defaulted
/// to a no-op stub — since deleted — whose `store(_:)` did nothing and whose
/// `settings()` always answered `.standard`. The
/// screen still moved a picker and showed a value; the value simply never survived
/// relaunch, and rest-day budget feeds rest-day conversion (MAX-061's calendar,
/// MAX-017's tallies), so the whole app ran on `.standard` regardless of what the
/// athlete chose. `SettingsModel` fixes this the same way every other repository-backed
/// screen in the app already reaches the store: an optional repository parameter that,
/// left nil, resolves to `PersistenceComposition.store` — never to a stub. See
/// `SettingsModel` for the load/save shape and how a store that failed to open is kept
/// distinct from "settings are default".
///
/// **The stored API key is never shown here, not even partially masked.** This view
/// only ever asks the store whether a key is present; it never reads or displays
/// an actual key. The only raw key text that exists is what the user actively types
/// into the `SecureField`, and that never round-trips back onto screen once saved.
struct SettingsView: View {
    private let keyStore: AnthropicAPIKeyStoring

    @State private var model: SettingsModel

    @State private var isKeyStored = false
    @State private var enteredKey = ""
    @State private var keyStatusMessage: String?

    /// MAX-081. The key field is the only text entry on this screen, so one flag is
    /// enough; it exists so saving, clearing, and the keyboard's own Done button can
    /// all put the keyboard away, which nothing here could do before.
    @FocusState private var isKeyFieldFocused: Bool

    /// MAX-080. Presented rather than pushed: this screen is itself already presented
    /// (MAX-081 moved it behind a toolbar button), and pushing onto a host stack this
    /// view does not own would put the plan editor's title in someone else's bar.
    @State private var isAuthoringPlan = false

    /// - Parameters:
    ///   - keyStore: where the Anthropic API key lives. Defaults to the real Keychain
    ///     store; a test or preview passes a fake.
    ///   - settingsRepository: forwarded to `SettingsModel`, which defaults it to
    ///     `PersistenceComposition.store` — never to a stub. See that type's docs.
    init(
        keyStore: AnthropicAPIKeyStoring = KeychainAnthropicAPIKeyStore(),
        settingsRepository: (any SettingsRepository)? = nil
    ) {
        self.keyStore = keyStore
        _model = State(initialValue: SettingsModel(settingsRepository: settingsRepository))
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

            // MAX-080. The entry point to the only screen that writes a `Plan` record.
            // Not gated on `model.state`: the plan lives in a different repository from
            // settings, and a settings read that failed says nothing about whether a
            // plan can be authored. `PlanAuthoringView` reports its own store's health.
            planSection

            // MAX-064: Rest days per week (D9/A6)
            trainingPlanSection

            // MAX-064: Display preferences
            displaySection

            // MAX-022: Anthropic API key section (keep styled consistently)
            Section("Anthropic API key") {
                Text(isKeyStored ? "A key is stored." : "No key is stored.")

                // MAX-081. `SecureField` is single-line, so the return key really does
                // submit: `.done` names the action the key press performs, and
                // `onSubmit` runs the same save the button does rather than leaving
                // Return inert. Autocapitalization is switched off explicitly because
                // an API key is case-sensitive and a capitalized first character is a
                // key that silently fails to authenticate.
                SecureField("Anthropic API key", text: $enteredKey)
                    .textContentType(.password)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .focused($isKeyFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(saveKey)

                Button("Save", action: saveKey)
                    .disabled(enteredKey.isEmpty)

                if isKeyStored {
                    Button("Clear", role: .destructive, action: clearKey)
                }

                if let keyStatusMessage {
                    Text(keyStatusMessage)
                        .font(.metricLabel)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        // MAX-081: two ways out of the keyboard, neither of which existed before — a
        // drag anywhere on the form, and an explicit button above the keyboard for
        // anyone who cannot make that gesture (FR-4.5).
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isKeyFieldFocused = false }
                    .accessibilityHint("Dismisses the keyboard")
            }
        }
        .task {
            await model.load()
            refreshStoredKeyStatus()
        }
        .sheet(isPresented: $isAuthoringPlan) {
            NavigationStack {
                PlanAuthoringView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isAuthoringPlan = false }
                        }
                    }
            }
        }
    }

    // MARK: - Plan section (MAX-080)

    @ViewBuilder
    private var planSection: some View {
        Section("Plan") {
            Button("Training plan…") { isAuthoringPlan = true }

            Text(
                "Heart-rate cap, cadence target, weekly template, long-run arc and score "
                    + "thresholds. Saving any change writes a new plan version rather than "
                    + "editing the current one, so scores already recorded stay reproducible."
            )
            .font(.metricLabel)
            .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Rest days section

    @ViewBuilder
    private var trainingPlanSection: some View {
        Section("Training plan") {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed:
                unavailableMessage
            case let .loaded(appSettings):
                HStack {
                    Text("Discretionary rest days per week")
                    Spacer()
                    Picker(
                        "Rest days",
                        selection: Binding(
                            get: { appSettings.restDayBudget.daysPerWeek },
                            set: { newValue in
                                guard let budget = try? RestDayBudget(daysPerWeek: newValue) else { return }
                                save(updating(appSettings, restDayBudget: budget))
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
    }

    // MARK: - Display preferences section

    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed:
                unavailableMessage
            case let .loaded(appSettings):
                Picker(
                    "Distance unit",
                    selection: Binding(
                        get: { appSettings.distanceUnit },
                        set: { save(updating(appSettings, distanceUnit: $0)) }
                    )
                ) {
                    Text("Miles").tag(DistanceUnit.miles)
                    Text("Kilometers").tag(DistanceUnit.kilometers)
                }

                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { appSettings.appearance },
                        set: { save(updating(appSettings, appearance: $0)) }
                    )
                ) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
            }
        }
    }

    /// Shown in place of the pickers whenever `model.state` is `.failed` — MAX-049's
    /// second half. An athlete whose store could not be opened must not see a
    /// rest-day budget (or any other setting) that looks editable and saved when
    /// nothing was, or could be, written.
    private var unavailableMessage: some View {
        Text("Settings are unavailable right now, so changes here would not be saved.")
            .font(.metricLabel)
            .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Editing an immutable value

    /// `AppSettings` is a value type whose properties are all `let` — deliberately, so
    /// nothing can mutate a settings record in place behind a reader's back. Editing one
    /// therefore means constructing a new one from the last value `SettingsModel` loaded
    /// or saved, which is what this helper does.
    ///
    /// Note what it carries forward untouched: the three accessibility fields. This
    /// screen exposes no control for them (see the Accessibility note above), so a
    /// settings write from here must never silently overwrite whatever a future ticket
    /// has seeded into them from the OS.
    private func updating(
        _ base: AppSettings,
        restDayBudget: RestDayBudget? = nil,
        distanceUnit: DistanceUnit? = nil,
        appearance: AppearancePreference? = nil
    ) -> AppSettings {
        AppSettings(
            restDayBudget: restDayBudget ?? base.restDayBudget,
            distanceUnit: distanceUnit ?? base.distanceUnit,
            appearance: appearance ?? base.appearance,
            reducesTransparency: base.reducesTransparency,
            increasesContrast: base.increasesContrast,
            reducesMotion: base.reducesMotion
        )
    }

    /// Routes an edit through `SettingsModel.save`, which persists it and only then
    /// updates `model.state` to match — see that method's documentation for why this
    /// is deliberately not optimistic.
    private func save(_ updated: AppSettings) {
        Task { await model.save(updated) }
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
            // MAX-081: only the success path resigns focus. Both failures below leave
            // the keyboard up because both leave the user with something to type — an
            // empty field to fill in, or a cleared one to re-enter.
            isKeyFieldFocused = false
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
