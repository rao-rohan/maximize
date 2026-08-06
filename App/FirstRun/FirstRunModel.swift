import Foundation
import MaximizeCore
import Observation

/// Loads `FirstRunChecklist.card` for the Workouts tab (MAX-164, FIRST-RUN-SPEC §5, §8).
///
/// Mirrors `WorkoutsListModel` and `SettingsModel`'s own shape: this is the async
/// plumbing a SwiftUI view cannot do for itself, and nothing more. Every decision about
/// which of the six states is showing, and every word in it, is
/// `FirstRunChecklist`/`FirstRunCopy` in `MaximizeCore` (MAX-162) — this type only reads
/// the four facts those decisions are made from and hands the result to the view.
///
/// ## The one fact this model cannot get right yet
///
/// `FirstRunFacts.healthAccess` is documented as wanting the *device-lifetime* answer —
/// has the Health sheet ever been presented, on any past launch, not just this one. That
/// answer is meant to come from `FirstRunPresentationRecording`, MAX-163's own protocol
/// (FIRST-RUN-SPEC §4.4), which does not exist in `Sources/MaximizeCore/FirstRun/` yet —
/// confirmed against `PROJECT_TRACKER.md`'s MAX-162 section, which names it as
/// "deliberately not defined here." Per this ticket's scope, that protocol is MAX-163's
/// to add, not this one's — adding a second definition here is exactly the collision the
/// two tickets' split was written to avoid.
///
/// So `healthAccess` below is held in memory, for the life of this model, seeded
/// `.notRequestedYet`. That is correct on a genuine fresh install and conservative
/// everywhere else: it can only make the card *keep showing* the Health step after a
/// past launch already resolved it, never claim a step is outstanding that never was.
/// **This is a real, reported gap, not an oversight**: until `WorkoutsView` is wired to
/// read `FirstRunPresentationRecording` once MAX-163 lands, an athlete who granted Health
/// access on a previous launch and force-quit the app (never touching this model since)
/// will see state 1 again on the next cold launch, once every other step is also done.
/// See this ticket's PR.
@MainActor
@Observable
final class FirstRunModel {
    private(set) var card: FirstRunCardState?

    /// True while `requestHealthAccessTapped()`'s request is in flight, so the card can
    /// disable its button and show that something is happening rather than let a second
    /// tap fire a second request.
    private(set) var isRequestingHealthAccess = false

    private let planRepository: (any PlanRepository)?
    private let workoutRepository: (any WorkoutRepository)?
    private let keyStore: AnthropicAPIKeyStoring
    private let performHealthAccessRequest: @MainActor () async -> HealthAccessState

    /// See the type's doc comment on why this is in-memory rather than device-lifetime.
    private var healthAccess: HealthAccessState = .notRequestedYet

    /// - Parameters:
    ///   - planRepository/workoutRepository: each defaults to
    ///     `PersistenceComposition.store`, matching every other repository-backed model
    ///     in this app. Overridable so a preview or a future test can hand this a fake.
    ///   - keyStore: defaults to the real Keychain store, matching `SettingsView`.
    ///   - performHealthAccessRequest: the Health permission request itself, injectable
    ///     for the same reason. Defaults to the real HealthKit call, wired through
    ///     `IngestionComposition` — the same call `HealthAccessSettingsSection` makes,
    ///     duplicated deliberately rather than shared: that view is out of this ticket's
    ///     scope (§ scope discipline), and the call itself is three lines of adapter, not
    ///     a decision.
    init(
        planRepository: (any PlanRepository)? = nil,
        workoutRepository: (any WorkoutRepository)? = nil,
        keyStore: AnthropicAPIKeyStoring = KeychainAnthropicAPIKeyStore(),
        performHealthAccessRequest: @escaping @MainActor () async -> HealthAccessState = FirstRunModel.requestRealHealthAccess
    ) {
        if let planRepository {
            self.planRepository = planRepository
        } else {
            self.planRepository = PersistenceComposition.store
        }
        if let workoutRepository {
            self.workoutRepository = workoutRepository
        } else {
            self.workoutRepository = PersistenceComposition.store
        }
        self.keyStore = keyStore
        self.performHealthAccessRequest = performHealthAccessRequest
    }

    /// Re-resolves `card` from the four facts. Safe to call repeatedly: on appear, and
    /// after returning from whichever screen the card's action sent the athlete to
    /// (FIRST-RUN-SPEC §5.4) — `WorkoutsView` is what calls it at both those moments.
    func load() async {
        guard let planRepository, let workoutRepository else {
            // No store to read. `WorkoutsListModel` already tells the athlete its own
            // list could not load; a first-run card guessing at a state on top of that
            // would be a second, possibly wrong, thing said about the same failure.
            card = nil
            return
        }
        do {
            let hasAuthoredPlan = try await planRepository.planCalendar() != nil
            // Every workout ever stored, matching `WorkoutsListModel`'s own query — the
            // only question here is whether the set is empty, not what is in it.
            let hasCapturedWorkout = try await !workoutRepository.workouts(
                startingIn: DateInterval(start: .distantPast, end: .distantFuture)
            ).isEmpty

            let facts = FirstRunFacts(
                healthAccess: healthAccess,
                hasAuthoredPlan: hasAuthoredPlan,
                apiKeyPresence: resolveKeyPresence(),
                hasCapturedWorkout: hasCapturedWorkout
            )
            card = FirstRunChecklist(facts: facts).card
        } catch {
            card = nil
        }
    }

    /// `SettingsView.refreshStoredKeyStatus()`'s own three-state read, duplicated for the
    /// same scope reason as `performHealthAccessRequest` above.
    private func resolveKeyPresence() -> StoredAPIKeyPresence {
        do {
            return try keyStore.retrieve() == nil ? .notStored : .stored
        } catch {
            return .unknown
        }
    }

    /// The card's action for both Health states (`.healthAccessNotRequested`,
    /// `.healthRequestDidNotComplete`). Requests access, records what happened in memory,
    /// and re-resolves the card — so a state 1 card that receives `.healthDataUnavailable`
    /// becomes that card, and one that receives `.requestAnswered` moves on to whatever
    /// is next, in the same tap.
    func requestHealthAccessTapped() {
        guard !isRequestingHealthAccess else { return }
        isRequestingHealthAccess = true
        Task {
            healthAccess = await performHealthAccessRequest()
            isRequestingHealthAccess = false
            await load()
        }
    }

    /// The real HealthKit request, wired through the same composition root
    /// `HealthAccessSettingsSection` uses. No explicit `@MainActor` needed on this
    /// declaration: it is a static member of a `@MainActor` type, so it inherits the
    /// isolation, and `IngestionComposition` — what it calls — is `@MainActor` too.
    static func requestRealHealthAccess() async -> HealthAccessState {
        do {
            try await IngestionComposition.workoutObserver.requestReadAuthorization()
            // Idempotent, matching `HealthAccessSettingsSection.requestAuthorization()`:
            // re-running this is what makes the very first grant take effect without a
            // relaunch, since the launch that preceded this tap had no authorization to
            // enable background delivery with.
            IngestionComposition.workoutObserver.startObservingWorkouts()
            return .requestAnswered
        } catch HealthKitObserverError.healthDataUnavailable {
            return .healthDataUnavailable
        } catch {
            // The caught error is deliberately not read or logged — see
            // `HealthAccessSettingsSection.requestAuthorization()` for why an arbitrary
            // HealthKit `Error` never reaches a string.
            return .requestFailed
        }
    }
}
