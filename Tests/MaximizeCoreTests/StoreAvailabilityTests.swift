import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-169: a store that will not open, as a state the app has rather than the absence of
/// one.
///
/// **Nothing in this repository has ever opened a store that refused to open.** There is
/// no simulator and no device in CI (tracker R2), the core cannot import SwiftData at all,
/// and `MaximizeModelContainer.makeOnDisk()` has never executed anywhere in this pipeline.
/// So the part of this feature that can be checked is the part that was deliberately
/// pushed down into values: what state follows an attempt, whether a control is offered,
/// and what the athlete reads. That is this file. What it cannot prove is that a real
/// store failing to open produces the error codes classified below — see the PR's **Needs
/// device verification** section, which is the whole point of the ticket.
final class StoreAvailabilityTests: XCTestCase {

    private func failure(
        _ reason: StoreOpenFailureReason,
        triedAgain: Bool = false
    ) -> StoreAvailability {
        .couldNotOpen(StoreOpenFailure(reason: reason, hasAlreadyBeenTriedAgain: triedAgain))
    }

    /// The notice for a state that must have one. Unwrapped here rather than at each call
    /// site so the assertions below read as assertions about copy rather than about
    /// optionals — and so a state that renders nothing fails as itself.
    private func notice(
        for availability: StoreAvailability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> StoreAvailabilityNotice {
        try XCTUnwrap(FailureCopy.storeAvailability(availability), file: file, line: line)
    }

    // MARK: - Reading the error, without reading the error

    /// The documented `NSCocoaErrorDomain` codes, each mapped to the reason it is
    /// classified as.
    ///
    /// The values are Apple's constants, written out here as well as in the source so that
    /// a "tidy-up" edit changing one of them has to change it in two places and explain
    /// why. A wrong mapping does not crash anything — it shows the wrong second paragraph,
    /// and in one direction withholds a retry that would have worked.
    func testDocumentedStoreErrorsAreClassified() {
        let expected: [Int: StoreOpenFailureReason] = [
            257: .deviceHadNotBeenUnlocked, // NSFileReadNoPermissionError
            513: .deviceHadNotBeenUnlocked, // NSFileWriteNoPermissionError
            640: .noRoomOnDevice, // NSFileWriteOutOfSpaceError
            134_020: .shapeThisBuildCannotOpen, // NSPersistentStoreIncompatibleSchemaError
            134_100: .shapeThisBuildCannotOpen, // NSPersistentStoreIncompatibleVersionHashError
            134_110: .shapeThisBuildCannotOpen, // NSMigrationError
            134_130: .shapeThisBuildCannotOpen, // NSMigrationMissingSourceModelError
            134_140: .shapeThisBuildCannotOpen, // NSMigrationMissingMappingModelError
            134_190: .shapeThisBuildCannotOpen, // NSInferredMappingModelError
        ]

        for (code, reason) in expected {
            XCTAssertEqual(
                StoreOpenFailureReason.classifying(errorDomain: NSCocoaErrorDomain, errorCode: code),
                reason,
                "Cocoa error \(code) is classified as something other than \(reason)"
            )
        }
    }

    /// Anything not recognised is `unknown`, which offers the retry. The alternative —
    /// guessing at the nearest neighbour — would be how an athlete gets told to free up
    /// space on a phone with plenty of it.
    func testAnythingElseIsUnknownRatherThanTheNearestGuess() {
        XCTAssertEqual(
            StoreOpenFailureReason.classifying(errorDomain: NSCocoaErrorDomain, errorCode: 4),
            .unknown
        )
        XCTAssertEqual(
            StoreOpenFailureReason.classifying(errorDomain: NSCocoaErrorDomain, errorCode: 134_999),
            .unknown
        )
        // A code from another domain that collides numerically with one of ours must not
        // be read as ours. `POSIXErrorDomain` 640 means nothing at all.
        XCTAssertEqual(
            StoreOpenFailureReason.classifying(errorDomain: NSPOSIXErrorDomain, errorCode: 640),
            .unknown
        )
        XCTAssertEqual(
            StoreOpenFailureReason.classifying(errorDomain: "com.example.something", errorCode: 257),
            .unknown
        )
    }

    // MARK: - A button is offered only where a button could help

    /// The rule the ticket turns on: a control that cannot help is worse than no control,
    /// because it is a second thing that does not work. A retry is offered where the
    /// device's state can change between two attempts — an unlock, or space freed — and
    /// withheld where the same attempt would be repeated against the same store.
    func testTryingAgainIsOfferedExactlyWhereItCouldWork() throws {
        XCTAssertTrue(StoreOpenFailureReason.deviceHadNotBeenUnlocked.isWorthTryingAgain)
        XCTAssertTrue(StoreOpenFailureReason.noRoomOnDevice.isWorthTryingAgain)
        XCTAssertTrue(StoreOpenFailureReason.unknown.isWorthTryingAgain)
        XCTAssertFalse(StoreOpenFailureReason.shapeThisBuildCannotOpen.isWorthTryingAgain)

        for reason in StoreOpenFailureReason.allCases {
            for triedAgain in [false, true] {
                let rendered = try notice(for: failure(reason, triedAgain: triedAgain))
                XCTAssertEqual(
                    rendered.action == .tryAgain,
                    reason.isWorthTryingAgain,
                    "\(reason) offers a retry that disagrees with whether one could work"
                )
                // A button and its title arrive together or not at all: a label without an
                // action would draw a control that does nothing when pressed.
                XCTAssertEqual(rendered.action == nil, rendered.actionLabel == nil)
            }
        }
    }

    /// A failed attempt does not withdraw the button. A phone still locked, or a disk
    /// still full, is not evidence that the *next* attempt fails — and taking away the
    /// only control on the screen after one press would leave a wall of text and nothing
    /// to do with it.
    func testAFailedAttemptDoesNotWithdrawTheOnlyControl() throws {
        for reason in StoreOpenFailureReason.allCases where reason.isWorthTryingAgain {
            let after = try notice(for: failure(reason, triedAgain: true))
            XCTAssertEqual(after.action, .tryAgain, "\(reason) withdrew its retry after one press")
        }
    }

    /// The state a second attempt cannot clear says so, in the place a person would
    /// otherwise look for the missing button.
    func testTheUnclearableStateSaysWhyThereIsNoButton() throws {
        let rendered = try notice(for: failure(.shapeThisBuildCannotOpen))
        XCTAssertNil(rendered.action)
        XCTAssertNil(rendered.actionLabel)

        let detail = try XCTUnwrap(rendered.detail)
        XCTAssertTrue(detail.contains("A second attempt would do exactly the same thing"))
        // And it says the thing that matters more than the button: the history is intact.
        XCTAssertTrue(detail.contains("still on the device"))
    }

    // MARK: - Nothing here can destroy anything (A8)

    /// **The assertion this file exists to hold.** CloudKit is deferred, so the store on
    /// this device is the athlete's only copy of their history. A "reset", "start over" or
    /// "reinstall" control beside an alarming message is how somebody loses years of
    /// training at six in the morning, and the fact that no such control exists today is
    /// worth exactly nothing unless something fails when one is added.
    func testNoticeActionsAreOnlyTheTwoNonDestructiveOnes() {
        XCTAssertEqual(StoreNoticeAction.allCases, [.tryAgain, .goToTheApp])
    }

    /// No sentence on this screen suggests the destructive move either, which is the other
    /// half of the same rule: the copy must not talk an athlete into doing by hand what the
    /// app rightly refuses to offer as a button.
    func testNoStoreCopySuggestsDeletingOrRebuildingAnything() {
        let banned = [
            "delete maximize", "delete the app", "reinstall", "re-install", "uninstall",
            "reset", "start over", "start again", "erase", "wipe", "clear your history",
        ]
        for state in FailureCopyTests.everyStoreAvailability {
            guard let rendered = FailureCopy.storeAvailability(state.value) else { continue }
            let text = ([rendered.heading, rendered.body, rendered.detail, rendered.actionLabel]
                .compactMap { $0 }
                .joined(separator: " "))
                .lowercased()
            for phrase in banned {
                XCTAssertFalse(
                    text.contains(phrase),
                    "\(state.label) suggests \"\(phrase)\", which would destroy the only copy"
                )
            }
        }
    }

    // MARK: - The state machine

    /// The ordinary launch says nothing, because nothing happened.
    func testAnOpenStoreProducesNoNotice() {
        XCTAssertEqual(StoreAvailability.afterFirstAttempt(.opened), .open)
        XCTAssertNil(FailureCopy.storeAvailability(.open))
        XCTAssertTrue(StoreAvailability.open.isUsable)
    }

    /// Every state that is not `.open` has something to say, and every state that cannot be
    /// read from says so.
    func testEveryStateThatIsNotOpenSaysSomething() {
        for state in FailureCopyTests.everyStoreAvailability where state.value != .open {
            XCTAssertNotNil(
                FailureCopy.storeAvailability(state.value),
                "\(state.label) renders nothing at all, which is the blank this ticket replaces"
            )
        }
        for reason in StoreOpenFailureReason.allCases {
            XCTAssertFalse(failure(reason).isUsable)
        }
    }

    /// The launch's first attempt has not been retried, by definition — the flag is about
    /// what the athlete has pressed, not about how many times the app has tried.
    func testTheFirstAttemptIsNotMarkedAsHavingBeenRetried() {
        guard case let .couldNotOpen(first) = StoreAvailability.afterFirstAttempt(
            .couldNotOpen(.noRoomOnDevice)
        ) else {
            return XCTFail("A first attempt that did not open must be a failure state")
        }
        XCTAssertEqual(first.reason, .noRoomOnDevice)
        XCTAssertFalse(first.hasAlreadyBeenTriedAgain)
    }

    /// A retry that fails is recorded as such, and the copy acknowledges the press before
    /// repeating the explanation — a screen that comes back word-for-word identical reads
    /// as a button that did nothing.
    func testARetryThatFailedIsAcknowledgedRatherThanRepeated() throws {
        let after = StoreAvailability
            .afterFirstAttempt(.couldNotOpen(.unknown))
            .afterTryingAgain(.couldNotOpen(.unknown))

        guard case let .couldNotOpen(second) = after else {
            return XCTFail("A retry that did not open must stay a failure state")
        }
        XCTAssertTrue(second.hasAlreadyBeenTriedAgain)

        let before = try notice(for: failure(.unknown))
        let again = try notice(for: after)
        XCTAssertNotEqual(before.detail, again.detail)
        XCTAssertTrue(try XCTUnwrap(again.detail).hasPrefix("Trying again did not open it."))
        // The body does not change: the facts about the athlete's history are the same
        // facts. Only the second paragraph answers the press.
        XCTAssertEqual(before.body, again.body)
    }

    /// A retry can also come back with a *different* reason — a locked phone that has since
    /// been unlocked but is now out of space. The new reason wins, and the press is still
    /// acknowledged.
    func testARetryReportsWhateverTheSecondAttemptFoundRatherThanTheFirst() {
        let after = StoreAvailability
            .afterFirstAttempt(.couldNotOpen(.deviceHadNotBeenUnlocked))
            .afterTryingAgain(.couldNotOpen(.noRoomOnDevice))

        guard case let .couldNotOpen(second) = after else {
            return XCTFail("A retry that did not open must stay a failure state")
        }
        XCTAssertEqual(second.reason, .noRoomOnDevice)
        XCTAssertTrue(second.hasAlreadyBeenTriedAgain)
    }

    /// A retry that works is not the same state as a launch that worked, and the difference
    /// is not cosmetic: the ingestion pipeline was assembled at launch, against no store,
    /// and does not come back until the app starts again. An athlete who is not told that
    /// discovers it as a run that never appeared.
    func testAStoreThatOpenedOnTheSecondAttemptSaysWhatDidNotComeBack() throws {
        let after = StoreAvailability
            .afterFirstAttempt(.couldNotOpen(.deviceHadNotBeenUnlocked))
            .afterTryingAgain(.opened)

        XCTAssertEqual(after, .openedAfterTryingAgain)
        XCTAssertTrue(after.isUsable)
        XCTAssertNotEqual(after, .open)

        let rendered = try notice(for: after)
        XCTAssertEqual(rendered.action, .goToTheApp)
        XCTAssertTrue(rendered.body.contains("next time Maximize starts"))
        // And it says nothing is lost while they wait, which is true by construction: with
        // no store the ingestion sink pins the HealthKit anchor rather than acknowledging
        // the batch (R9/R12).
        XCTAssertTrue(rendered.body.lowercased().contains("none of them are lost"))
    }

    /// Nothing re-opens a store that is open. A second `ModelContainer` over the same file
    /// is two SwiftData stacks writing one store, so the transition is a no-op here rather
    /// than a rule the one caller has to remember.
    func testAnOpenStoreIsNeverReopened() {
        XCTAssertEqual(StoreAvailability.open.afterTryingAgain(.opened), .open)
        XCTAssertEqual(
            StoreAvailability.open.afterTryingAgain(.couldNotOpen(.unknown)),
            .open
        )
        XCTAssertEqual(
            StoreAvailability.openedAfterTryingAgain.afterTryingAgain(.opened),
            .openedAfterTryingAgain
        )
        XCTAssertEqual(
            StoreAvailability.openedAfterTryingAgain.afterTryingAgain(.couldNotOpen(.unknown)),
            .openedAfterTryingAgain
        )
    }

    // MARK: - One fact, one wording

    /// Each reason gets its own second paragraph. A shared one would be the "four verbs for
    /// one event" defect of MAX-154 inverted — one verb for four events — and would make
    /// the retry's presence or absence unexplained.
    func testEveryReasonHasItsOwnExplanation() throws {
        var seen: [String: StoreOpenFailureReason] = [:]
        for reason in StoreOpenFailureReason.allCases {
            let detail = try XCTUnwrap(
                notice(for: failure(reason)).detail,
                "\(reason) has no second paragraph"
            )
            if let already = seen[detail] {
                XCTFail("\(reason) explains itself in \(already)'s words: \"\(detail)\"")
            }
            seen[detail] = reason
        }
        XCTAssertEqual(seen.count, StoreOpenFailureReason.allCases.count)
    }

    /// The two reasons an athlete can act on say what the action is, and both are actions
    /// they can actually take on the device in front of them.
    func testTheActionableReasonsNameTheAction() throws {
        let locked = try XCTUnwrap(notice(for: failure(.deviceHadNotBeenUnlocked)).detail)
        XCTAssertTrue(locked.contains("Unlock the phone"))

        let full = try XCTUnwrap(notice(for: failure(.noRoomOnDevice)).detail)
        XCTAssertTrue(full.contains("Free up some space"))
    }
}
