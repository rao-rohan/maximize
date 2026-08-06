import Foundation
import HealthKit
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
/// ## `healthAccess` reads MAX-163's device-lifetime recording
///
/// `FirstRunFacts.healthAccess` wants the *device-lifetime* answer — has the Health sheet
/// ever been presented, on any past launch, not just this one — and that answer now comes
/// from `FirstRunPresentationRecording` (MAX-163), the same record `FirstRunCoverGate`
/// reads to decide whether the launch cover should appear. `resolveHealthAccess()` is the
/// composition:
///
/// - Not yet presented (`hasPresentedHealthRequest == false`) → `.notRequestedYet`.
/// - Presented, and this device can provide Health data → `.requestAnswered`. The
///   recording only ever means "the sheet was presented and answered" (its own doc
///   comment) — never granted or refused (R10) — so `.requestAnswered` is the honest
///   ceiling of what a `true` recording can mean.
/// - Presented, but `isHealthDataAvailable()` says this device has no Health store →
///   `.healthDataUnavailable`, **not** `.requestAnswered`. This is the case MAX-163's PR
///   named directly: the recording is written unconditionally the instant the cover's
///   Continue button is tapped, deliberately not conditioned on the Health call
///   succeeding — a device with no Health store fails that call identically forever, so
///   gating the *recording* on success would rebuild the every-launch nag through another
///   door. Reconciling the two facts here, rather than trusting the recording alone, is
///   what keeps a card on an iPad from asking for a plan and a key toward data that can
///   never arrive. `isHealthDataAvailable()` is a synchronous capability check with no
///   privacy surface of its own — it answers "does this hardware support HealthKit at
///   all", not anything about the athlete — so calling it on every `load()` costs nothing
///   and needs no permission.
///
/// `.requestFailed` is deliberately unreachable from the recording: once presented, the
/// recording never un-presents itself, so a relaunch cannot distinguish "answered" from
/// "failed for some reason other than device capability" — and MAX-163's own reasoning is
/// that this does not need distinguishing, because a repeat `requestAuthorization` call is
/// itself idempotent and harmless once the sheet has been shown. `.requestFailed` still
/// exists as a same-session signal: see `sessionHealthAccessOverride` below, which is what
/// lets this card show it immediately after a failed tap, before the persisted state
/// (which cannot express it) takes back over on the next `load()`.
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
    private let presentationRecording: FirstRunPresentationRecording
    private let isHealthDataAvailable: () -> Bool
    private let performHealthAccessRequest: @MainActor () async -> HealthAccessState

    /// This tap's own result, shown in place of the persisted-and-reconciled answer until
    /// the next cold launch constructs a fresh model. Exists for exactly one case the
    /// persisted recording cannot express — see the type's doc comment on
    /// `.requestFailed`. `nil` before any tap this session, which is the ordinary case.
    private var sessionHealthAccessOverride: HealthAccessState?

    /// - Parameters:
    ///   - planRepository/workoutRepository: each defaults to
    ///     `PersistenceComposition.store`, matching every other repository-backed model
    ///     in this app. Overridable so a preview or a future test can hand this a fake.
    ///   - keyStore: defaults to the real Keychain store, matching `SettingsView`.
    ///   - presentationRecording: defaults to the real `UserDefaults`-backed store
    ///     (MAX-163) — the same adapter `RootTabView` constructs for the launch cover.
    ///     A second instance rather than the one `RootTabView` holds: both read and write
    ///     the same underlying `UserDefaults` key with no in-memory cache of their own, so
    ///     two instances agree by construction and sharing one would only add a coupling
    ///     between two independently-scoped views for no behavioural gain.
    ///   - isHealthDataAvailable: defaults to the real HealthKit capability check.
    ///     Injectable for the same reason as everything else here.
    ///   - performHealthAccessRequest: the Health permission request itself, injectable
    ///     for the same reason. Defaults to the real HealthKit call, wired through
    ///     `IngestionComposition` — the same call `HealthAccessSettingsSection` and
    ///     `FirstRunCoverView` make, duplicated deliberately rather than shared: both
    ///     views are out of this ticket's scope, and the call itself is three lines of
    ///     adapter, not a decision.
    init(
        planRepository: (any PlanRepository)? = nil,
        workoutRepository: (any WorkoutRepository)? = nil,
        keyStore: AnthropicAPIKeyStoring = KeychainAnthropicAPIKeyStore(),
        presentationRecording: FirstRunPresentationRecording = UserDefaultsFirstRunPresentationStore(),
        isHealthDataAvailable: @escaping () -> Bool = HKHealthStore.isHealthDataAvailable,
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
        self.presentationRecording = presentationRecording
        self.isHealthDataAvailable = isHealthDataAvailable
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
                healthAccess: resolveHealthAccess(),
                hasAuthoredPlan: hasAuthoredPlan,
                apiKeyPresence: resolveKeyPresence(),
                hasCapturedWorkout: hasCapturedWorkout
            )
            card = FirstRunChecklist(facts: facts).card
        } catch {
            card = nil
        }
    }

    /// See the type's doc comment for the full reconciliation this performs.
    private func resolveHealthAccess() -> HealthAccessState {
        if let sessionHealthAccessOverride {
            return sessionHealthAccessOverride
        }
        guard presentationRecording.hasPresentedHealthRequest else {
            return .notRequestedYet
        }
        return isHealthDataAvailable() ? .requestAnswered : .healthDataUnavailable
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
    /// `.healthRequestDidNotComplete`). Records the presentation, requests access, keeps
    /// this tap's own result for the current session, and re-resolves the card.
    ///
    /// **Reachable in practice, unlike the cover's own Continue button**: this is state
    /// 1's fallback path — "a cover dismissed by a crash, a store that failed at the wrong
    /// moment" (`FirstRunCardState.healthAccessNotRequested`'s own doc comment) — so it
    /// has to keep the device-lifetime recording correct exactly as the cover does, or a
    /// crash-recovery tap here would leave `FirstRunCoverGate` believing the sheet was
    /// never presented and reopen the full-screen cover on top of an otherwise working
    /// install on the very next launch.
    func requestHealthAccessTapped() {
        guard !isRequestingHealthAccess else { return }
        isRequestingHealthAccess = true

        // Recorded the moment the athlete acts, matching `FirstRunCoverView
        // .continueTapped()` exactly — not conditioned on what the request below
        // returns. See that view's own comment: a device with no Health store fails the
        // same way on every future attempt, so gating the recording on success would
        // rebuild the nag this whole mechanism exists to prevent.
        presentationRecording.recordHealthRequestPresented()

        Task {
            sessionHealthAccessOverride = await performHealthAccessRequest()
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
