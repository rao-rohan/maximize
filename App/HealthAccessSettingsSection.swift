import SwiftUI
import MaximizeCore

/// The foreground affordance for granting Health access (MAX-030).
///
/// HealthKit's permission sheet requires a foreground, so it cannot be requested from
/// the launch path that registers the observer query — a background wake has no UI to
/// present from. This is that request, kept deliberately structurally plain: no
/// colors, fonts, or layout beyond a `Section`, because MAX-040 owns styling and this
/// ticket does not.
///
/// ## Why the status wording is so careful
///
/// The view never claims access was granted, because the app cannot know.
/// `HKHealthStore.authorizationStatus(for:)` reports *share* status only; Apple does
/// not expose read status by design, so that an app cannot distinguish "denied" from
/// "no data recorded" and infer something about the person from the difference. The
/// strongest true statement available is that the sheet was answered, so that is the
/// only thing said here.
///
/// **MAX-154 moved the wording itself into `MaximizeCore`.** The care above was real
/// but unenforced: it lived in four string literals in this file, which CI compiles and
/// never runs, so nothing but a reader could tell whether the next edit kept it.
/// `HealthAccessState` has no `granted` case and no `denied` case for exactly that
/// reason, and `FailureCopyTests` asserts that no sentence derived from it claims
/// either. This view now holds a state and renders it — see CLAUDE.md's "observe state,
/// render it, forward user intent."
struct HealthAccessSettingsSection: View {
    @State private var accessState: HealthAccessState = .notRequestedYet
    @State private var isRequesting = false

    var body: some View {
        Section("Apple Health") {
            Text("Maximize reads completed workouts, heart rate, distance, energy, steps and route. It never writes to Health.")

            Button("Request Health access", action: request)
                .disabled(isRequesting)

            Text(FailureCopy.healthAccess(accessState))
        }
    }

    /// `@MainActor` so the `Task` it spawns inherits main-actor isolation: the work
    /// touches `@State` and the main-actor-isolated composition root, and an
    /// unisolated `Task` would be free to do both off the main thread.
    @MainActor
    private func request() {
        isRequesting = true
        Task {
            await requestAuthorization()
            isRequesting = false
        }
    }

    @MainActor
    private func requestAuthorization() async {
        do {
            try await IngestionComposition.workoutObserver.requestReadAuthorization()

            // Registration is idempotent, and re-running it here is what makes the
            // very first grant take effect without a relaunch: at the launch that
            // preceded this tap there was no authorization, so background delivery
            // could not be enabled.
            IngestionComposition.workoutObserver.startObservingWorkouts()

            accessState = .requestAnswered
        } catch HealthKitObserverError.healthDataUnavailable {
            accessState = .healthDataUnavailable
        } catch {
            // The caught error is deliberately not read, not logged, and not carried
            // into the state: an arbitrary `Error` from HealthKit may carry sample
            // values in its `userInfo`, and health data does not go into strings a
            // person or a log can read (CLAUDE.md). What reaches the screen is a fixed
            // sentence chosen in `MaximizeCore` from a case with no payload.
            accessState = .requestFailed
        }
    }
}
