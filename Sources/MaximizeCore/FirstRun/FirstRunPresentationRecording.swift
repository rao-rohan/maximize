import Foundation

/// Whether the first-launch cover's one action — presenting the iOS Health permission
/// sheet — has ever happened on this device (MAX-163, FIRST-RUN-SPEC §4.4).
///
/// ## Device-lifetime, not per-launch
///
/// `FirstRunFacts`' own doc comment flags the trap this protocol exists to close:
/// `HealthAccessState.notRequestedYet` means "not presented *on this launch*", because
/// the Settings section that introduced it holds its answer in `@State` and starts every
/// launch not having asked. A cover gated on that value would present itself on every
/// launch of a perfectly working install — the nagging §5.4 forbids, one screen earlier.
///
/// This protocol is what makes the device-lifetime answer possible: the app writes to it
/// exactly once, when the cover's Continue button presents the sheet, and reads it at
/// every launch after, including ones in a process that never ran the write.
///
/// ## Why a protocol here, not a concrete `UserDefaults` type
///
/// CLAUDE.md: "Platform frameworks are reached through protocols defined in the core and
/// implemented in the app layer." `MaximizeCore` does not import HealthKit or decide
/// *where* the flag is stored — only the shape a store for it must have. The app supplies
/// the real adapter (`UserDefaultsFirstRunPresentationStore`); tests supply an in-memory
/// fake and can simulate a relaunch by constructing a fresh gate check against a fake that
/// already holds `true`.
///
/// ## What this does *not* record
///
/// Not whether Health access was granted, refused, or is working — HealthKit never tells
/// this app that (R10). Only whether the sheet has been put to the athlete. A recorded
/// presentation composes with `HealthAccessState.requestAnswered`, which means exactly
/// this and nothing more: the sheet was presented and answered, and what it was answered
/// with is not knowable.
public protocol FirstRunPresentationRecording {
    /// Whether the Health permission sheet has been presented on this device before — on
    /// any launch, including ones before this process started.
    var hasPresentedHealthRequest: Bool { get }

    /// Records that the sheet has now been presented. Idempotent: calling it a second
    /// time leaves the recording exactly as presented as calling it once did.
    func recordHealthRequestPresented()
}

/// Whether the first-launch cover should appear on this run of the app (MAX-163,
/// FIRST-RUN-SPEC §4.4).
///
/// A one-line decision, and it still lives in the core rather than the view: CLAUDE.md
/// treats "whether a screen should appear" as logic, and the per-launch/device-lifetime
/// trap `FirstRunFacts` flags is exactly the kind of mistake that is invisible in a diff
/// and only shows up as a nag screen on a real device. Keeping the check here means it is
/// verified by `FirstRunCoverGateTests` on every commit; the view calls this once, on
/// appear, and otherwise only forwards the Continue tap.
///
/// **Deliberately not part of `FirstRunChecklist`.** That type answers "what is left to
/// set up" from `FirstRunFacts`; the cover's question is narrower and different in kind —
/// "has this specific one-shot screen been shown before". `FirstRunChecklist`'s own doc
/// says so directly: it is MAX-164's seam, and the cover's gate is this type instead.
public enum FirstRunCoverGate {
    /// `true` until the sheet has been presented on this device; `false` on every launch
    /// after.
    ///
    /// A reinstall resets the recording along with everything else the device knew about
    /// this install — correctly, per FIRST-RUN-SPEC §4.4: CloudKit backup is deferred
    /// (A8), so a reinstall already loses history, and a reinstall's first launch is a
    /// fresh install as far as the Health sheet is concerned.
    public static func shouldPresent(_ recording: FirstRunPresentationRecording) -> Bool {
        !recording.hasPresentedHealthRequest
    }
}
