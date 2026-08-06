import MaximizeCore

/// In-memory stand-in for `FirstRunPresentationRecording`, substitutable wherever the
/// real `UserDefaults`-backed store would be injected.
///
/// `UserDefaults` cannot be exercised meaningfully in this repo's CI beyond "it works
/// like a dictionary" (see CLAUDE.md — "What CI can and cannot prove"), so every decision
/// that matters — whether the cover should present, whether the recording survives past
/// the object that wrote it — is written to be verifiable against this fake instead.
///
/// `startingPresented` lets a test construct the fake as if a prior launch had already
/// recorded the presentation, which is how `FirstRunCoverGateTests` simulates a relaunch
/// without a second process: a fresh instance seeded with the prior value stands in for
/// "the app was quit and reopened", the same way a fresh `FirstRunChecklist` built from
/// stored facts stands in for a relaunch elsewhere in this module.
public final class FakeFirstRunPresentationRecording: FirstRunPresentationRecording {
    public private(set) var hasPresentedHealthRequest: Bool

    /// Number of times `recordHealthRequestPresented()` has been called, for tests that
    /// assert idempotence rather than just end state.
    public private(set) var recordCallCount = 0

    public init(startingPresented: Bool = false) {
        self.hasPresentedHealthRequest = startingPresented
    }

    public func recordHealthRequestPresented() {
        recordCallCount += 1
        hasPresentedHealthRequest = true
    }
}
