import SwiftUI

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
struct HealthAccessSettingsSection: View {
    @State private var statusMessage = "Health access has not been requested yet on this launch."
    @State private var isRequesting = false

    var body: some View {
        Section("Apple Health") {
            Text("Maximize reads completed workouts, heart rate, distance, energy, steps and route. It never writes to Health.")

            Button("Request Health access", action: request)
                .disabled(isRequesting)

            Text(statusMessage)
        }
    }

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

            statusMessage = "Health access was requested. iOS does not report whether read access was granted; workouts will appear if it was."
        } catch HealthKitObserverError.healthDataUnavailable {
            statusMessage = "HealthKit is not available on this device."
        } catch {
            // Generic on purpose: this string is the only thing that reaches the
            // screen, and health data must not leak into UI text or logs (CLAUDE.md).
            statusMessage = "Could not complete the Health access request."
        }
    }
}
