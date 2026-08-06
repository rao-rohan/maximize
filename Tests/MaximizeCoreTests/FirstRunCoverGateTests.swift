import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// MAX-163: whether the first-launch cover should appear, and the seam that has to be
/// device-lifetime rather than per-launch (FIRST-RUN-SPEC §4.4).
///
/// The trap this file exists to catch is named directly on `FirstRunFacts`: a cover
/// gated on a value that resets every launch nags forever on a working install. Nothing
/// here can prove `UserDefaults` itself persists across a real relaunch — that is a
/// device check, listed in the PR — but everything about the *decision* the app makes
/// from a persisted value is provable, and this is where it is proven.
final class FirstRunCoverGateTests: XCTestCase {

    // MARK: - Fresh install

    func testTheCoverPresentsOnAFreshInstall() {
        let recording = FakeFirstRunPresentationRecording(startingPresented: false)
        XCTAssertTrue(FirstRunCoverGate.shouldPresent(recording))
    }

    // MARK: - It does not reappear once recorded

    func testTheCoverDoesNotPresentAfterBeingRecorded() {
        let recording = FakeFirstRunPresentationRecording(startingPresented: false)
        recording.recordHealthRequestPresented()
        XCTAssertFalse(FirstRunCoverGate.shouldPresent(recording))
    }

    /// The exact defect `FirstRunFacts` warns about, written as a test: recording the
    /// presentation must not be something the gate has to be asked about repeatedly in
    /// one process to "stick" — one write is the whole of what "shown" means.
    func testRecordingIsIdempotent() {
        let recording = FakeFirstRunPresentationRecording(startingPresented: false)
        recording.recordHealthRequestPresented()
        recording.recordHealthRequestPresented()
        recording.recordHealthRequestPresented()

        XCTAssertEqual(recording.recordCallCount, 3)
        XCTAssertTrue(recording.hasPresentedHealthRequest)
        XCTAssertFalse(FirstRunCoverGate.shouldPresent(recording))
    }

    // MARK: - The recording survives a simulated relaunch

    /// A fresh instance of the recording, seeded with the value a prior instance wrote,
    /// stands in for the process having quit and restarted — the same technique
    /// `FirstRunChecklistTests` uses for "a fresh install" by constructing `FirstRunFacts`
    /// values directly rather than running a process twice. What a real relaunch does to
    /// an actual `UserDefaults` write is outside what CI can prove — see the PR.
    func testTheRecordingSurvivesASimulatedRelaunch() {
        let firstLaunch = FakeFirstRunPresentationRecording(startingPresented: false)
        XCTAssertTrue(FirstRunCoverGate.shouldPresent(firstLaunch))
        firstLaunch.recordHealthRequestPresented()

        // A brand-new instance — a different object, standing in for a new process —
        // seeded with what the first one recorded.
        let secondLaunch = FakeFirstRunPresentationRecording(
            startingPresented: firstLaunch.hasPresentedHealthRequest
        )
        XCTAssertFalse(
            FirstRunCoverGate.shouldPresent(secondLaunch),
            "the cover reappeared on a simulated relaunch after being recorded"
        )
    }

    /// And the inverse: a device that never presented the sheet stays gated to present it
    /// across as many simulated relaunches as asked.
    func testAnUnrecordedDeviceKeepsPresentingAcrossRelaunches() {
        for _ in 0..<3 {
            let launch = FakeFirstRunPresentationRecording(startingPresented: false)
            XCTAssertTrue(FirstRunCoverGate.shouldPresent(launch))
        }
    }

    /// A reinstall is a fresh install as far as this recording is concerned (A8: CloudKit
    /// is deferred, so a reinstall already loses history) — stated here as the same
    /// fresh-install case above, so a reader does not have to infer it.
    func testAReinstallReappearsTheCoverBecauseItIsAFreshRecording() {
        let reinstalled = FakeFirstRunPresentationRecording(startingPresented: false)
        XCTAssertTrue(FirstRunCoverGate.shouldPresent(reinstalled))
    }
}
