import SwiftUI
import MaximizeCore

/// FIRST-RUN-SPEC §4: the first-launch cover. Its single action presents the iOS Health
/// permission sheet — the one step in first run iOS will not let this app offer twice
/// (§4.1), which is the entire reason a cover exists here and nowhere else in setup.
///
/// **Three elements and a button. Nothing else** — no carousel, no feature tour, no
/// illustration (§4.2). Every word on screen is `FirstRunCopy.cover`, read here and
/// nowhere else in this module, so there is exactly one place that sentence is written.
///
/// **`fullScreenCover`, not `sheet`.** A sheet is dismissible by a drag, and a drag past
/// the one screen that explains what the app is about to ask for is a gesture nobody
/// meant to make (§4.1) — a deliberate departure from the lighter-weight presentation this
/// app otherwise reaches for (`ChatSheet`, the Settings sheet), named here because CLAUDE.md
/// asks that a departure from the familiar default say why.
///
/// **No success state, ever.** iOS never reports whether *read* access was granted (R10),
/// so the moment Continue's work finishes, this view simply dismisses — there is no
/// checkmark, no "you're all set," because there is no result it could honestly draw. See
/// `continueTapped()`.
struct FirstRunCoverView: View {
    /// Owned by whoever presents this view (`RootTabView`), which is also what decided to
    /// present it in the first place (`FirstRunCoverGate`). This view's only say over the
    /// binding is setting it to `false` once Continue's work is done.
    @Binding var isPresented: Bool

    /// The device-lifetime record that this device has shown the cover. `RootTabView`
    /// supplies the real `UserDefaultsFirstRunPresentationStore`.
    let recording: FirstRunPresentationRecording

    @State private var isRequesting = false

    private let copy = FirstRunCopy.cover

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.section)

            VStack(spacing: Spacing.roomy) {
                Text(copy.title)
                    .font(.screenTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: Spacing.regular) {
                    ForEach(copy.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.bodyCopy)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .screenMargins()

            Spacer(minLength: Spacing.hero)

            Button(action: continueTapped) {
                Text(copy.continueLabel)
                    .frame(maxWidth: .infinity)
            }
            // The current bordered-prominent + accent pairing, matching the other primary
            // calls to action in this app (`PlanView`'s "Author a plan") rather than a
            // hand-rolled capsule — content buttons take the system's own current style,
            // the same rule `glassChrome` applies to chrome.
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .controlSize(.large)
            .disabled(isRequesting)
            .screenMargins()
            .padding(.bottom, Spacing.roomy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A full screen of the app's own flat background, not chrome — this is content
        // (words explaining the app), and FR-4.2 keeps content surfaces opaque regardless
        // of the fact that the presentation itself is a system-level cover.
        .contentSurface(.screen)
    }

    /// `@MainActor` so the spawned `Task` inherits main-actor isolation: the work touches
    /// `@State` and the main-actor-isolated `IngestionComposition`, and an unisolated
    /// `Task` would be free to touch both off the main thread — the same reasoning
    /// `HealthAccessSettingsSection.request()` documents for its own `Task`.
    @MainActor
    private func continueTapped() {
        isRequesting = true

        // Recorded the moment the athlete acts, not conditioned on what the Health call
        // below returns. Two reasons, not one:
        //
        // 1. "Has this device shown this screen" (FIRST-RUN-SPEC §4.4's own words) is a
        //    fact about the cover, not about HealthKit's answer — the cover's one job is
        //    putting the question to iOS, and that job is done the instant this fires.
        // 2. Conditioning it on success would risk exactly the nag loop this ticket was
        //    warned about, on the one path recording-on-success cannot recover from: a
        //    device with no Health store at all (`HealthKitObserverError
        //    .healthDataUnavailable`) fails the same way on every future attempt, so a
        //    cover that only records on success would present itself every single launch
        //    forever. Recording unconditionally costs nothing on the success path — iOS
        //    itself makes a second `requestAuthorization` call after the sheet has been
        //    answered complete without presenting anything, so there is no second sheet
        //    to lose by asking again — and it is what actually keeps the promise "shown
        //    once."
        recording.recordHealthRequestPresented()

        Task {
            await presentHealthSheet()
            isRequesting = false
            // §4.3: dismisses claiming no result, whatever happened above.
            isPresented = false
        }
    }

    @MainActor
    private func presentHealthSheet() async {
        do {
            try await IngestionComposition.workoutObserver.requestReadAuthorization()

            // Mirrors `HealthAccessSettingsSection.requestAuthorization()`: registration
            // is idempotent, and re-running it here is what makes the very first grant
            // take effect without waiting for a relaunch — at the launch that preceded
            // this tap there was no authorization yet, so background delivery could not
            // have been enabled.
            IngestionComposition.workoutObserver.startObservingWorkouts()
        } catch {
            // Deliberately not inspected further. This view draws no result from the
            // call either way (§4.3), and an arbitrary `Error` from HealthKit may carry
            // sample values in its `userInfo` — health data does not go into anything a
            // view holds or a log reads (CLAUDE.md). The setup card (MAX-164) is where a
            // failed request gets a sentence, from `HealthAccessState.requestFailed`.
        }
    }
}
