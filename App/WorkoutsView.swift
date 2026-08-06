import SwiftUI
import MaximizeCore

/// The workout list — the minimum surrounding view MAX-041 needs to reach the detail
/// screen's plan-verdict header (FR-1.1). Rows are deliberately plain (see
/// `WorkoutRow`); everything richer belongs to later tickets.
///
/// **MAX-164** adds the setup card above the list (FIRST-RUN-SPEC §5, §8): a fixed
/// header, present in every load state below, that names what a fresh install still
/// needs and disappears — permanently, per state — once it is done. `FirstRunModel`
/// decides which of the six states is showing, if any; this view's job is presenting the
/// screen each of the card's three actions leads to and asking the model to look again
/// afterward (§5.4 — checked on appear, and after returning from wherever the action
/// sent the athlete).
struct WorkoutsView: View {
    @State private var model = WorkoutsListModel()
    @State private var firstRunModel = FirstRunModel()

    /// The two destinations the card's actions can lead to that this screen does not
    /// already own a path to. `.requestHealthAccess` needs neither — it is answered in
    /// place by `firstRunModel.requestHealthAccessTapped()` — so it has no case here.
    @State private var isAuthoringFirstPlan = false
    @State private var isPresentingSettingsFromCard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let card = firstRunModel.card {
                    FirstRunCardView(
                        state: card,
                        isPerformingAction: firstRunModel.isRequestingHealthAccess,
                        action: { performAction(for: card) }
                    )
                    .screenMargins()
                    .padding(.top, Spacing.regular)
                    .padding(.bottom, Spacing.compact)
                }

                content
            }
            .navigationTitle("Workouts")
            .contentSurface(.screen)
            .navigationDestination(for: UUID.self) { workoutID in
                WorkoutDetailView(workoutID: workoutID)
            }
            // Pushed, matching `PlanView`'s own "Author a plan" entry point — the exact
            // action this card's `.authorAPlan` step offers, worded identically
            // (`FirstRunCopy.actionLabel(for: .authorAPlan)`) — rather than presented as
            // a sheet the way `SettingsView.planSection` opens it. This is a second door
            // to the one screen that writes a plan version, not a second screen.
            .navigationDestination(isPresented: $isAuthoringFirstPlan) {
                PlanAuthoringView()
            }
            // Same sheet shape `SettingsToolbar.swift`'s private `SettingsSheet` already
            // presents from the toolbar button — duplicated rather than shared, because
            // that state is private to a modifier this ticket's scope does not touch
            // (⚠️ files are `WorkoutsView.swift` and two new `App/FirstRun/` files).
            // Three lines of chrome, not a decision, so the duplication costs little;
            // a future ticket touching both spots is the natural place to fold it into
            // one.
            .sheet(isPresented: $isPresentingSettingsFromCard) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresentingSettingsFromCard = false }
                            }
                        }
                }
            }
            // MAX-081: settings is a button on both tabs, not a tab of its own.
            // Attached to the root only — pushing a workout should show that
            // screen's own bar, not carry an app-level control into it.
            .settingsToolbarItem()
        }
        .task { await model.load() }
        .onAppear { Task { await firstRunModel.load() } }
        // Neither `.navigationDestination(isPresented:)` nor `.sheet(isPresented:)`
        // guarantees `onAppear` fires again on this screen when they close — a sheet
        // dismissal in particular never disappears the presenter — so both are also
        // watched directly. Reloading twice on a pop that *does* refire `onAppear` costs
        // one cheap, idempotent read; missing the reload entirely would leave a
        // completed step on screen (FIRST-RUN-SPEC §5.4's "does not come back" cuts both
        // ways — it must not linger, either).
        .onChange(of: isAuthoringFirstPlan) { _, isPresented in
            guard !isPresented else { return }
            Task { await firstRunModel.load() }
        }
        .onChange(of: isPresentingSettingsFromCard) { _, isPresented in
            guard !isPresented else { return }
            Task { await firstRunModel.load() }
        }
    }

    /// Forwards the card's one action. Only `FirstRunCardState.step` decides what
    /// happens — this reads it once and switches on it, exactly as `FirstRunCardView`
    /// switches on nothing else about the state itself.
    private func performAction(for state: FirstRunCardState) {
        switch state.step {
        case .requestHealthAccess:
            firstRunModel.requestHealthAccessTapped()
        case .authorAPlan:
            isAuthoringFirstPlan = true
        case .addAnAPIKey:
            isPresentingSettingsFromCard = true
        case nil:
            // `.healthDataUnavailable` and `.awaitingFirstWorkout` — both told, not
            // asked. `FirstRunCardView` does not draw a button for either.
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            // MAX-154. Both sentences come from `MaximizeCore` now, and the reason they
            // are two sentences rather than one is R10: an empty list and a refused
            // Health read are indistinguishable from inside this app, so the failure
            // copy says it is *not* the absence, and the absence copy names the other
            // possibility without asserting it. See `FailureCopy`.
            Text(FailureCopy.couldNotLoad(.workoutList))
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(data) where data.workouts.isEmpty:
            // Whenever the setup card is showing, it is already this screen's answer to
            // "why is the list empty" — every one of its six states either explains that
            // directly (the three Health ones, `.awaitingFirstWorkout`) or explains a
            // different reason capture is not the whole picture yet (`.noPlanAuthored`,
            // `.noAPIKeyStored`). Drawing `FailureCopy.noWorkoutsRecorded` underneath it
            // would be a second absence sentence on the same screen — precisely what
            // FIRST-RUN-SPEC §8 tried collapsing into one string before deciding two
            // sentences, worded for two different moments, read better than one
            // (`FirstRunCopy`'s own note) — that reasoning does not extend to running
            // both surfaces on screen at once. Once the card is gone, this is the sole
            // absence message again, exactly as before this ticket.
            if firstRunModel.card == nil {
                Text(FailureCopy.noWorkoutsRecorded)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .screenMargins()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        case let .loaded(data):
            ScrollView {
                LazyVStack(spacing: Spacing.compact) {
                    ForEach(data.workouts) { workout in
                        NavigationLink(value: workout.id) {
                            WorkoutRow(workout: workout, distanceUnit: data.distanceUnit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .screenMargins()
                .padding(.vertical, Spacing.regular)
            }
        }
    }
}
