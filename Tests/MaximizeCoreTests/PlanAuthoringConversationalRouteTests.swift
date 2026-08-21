import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-166: the gate for the plan-authoring screen's conversational route.
///
/// `App/Plan/PlanAuthoringView.swift` is never run by CI (tracker R2, R13) — this file is
/// what actually checks the gate, the same reasoning `FailureCopyTests` gives for its own
/// existence.
final class PlanAuthoringConversationalRouteTests: XCTestCase {

    // MARK: - Availability, over every case

    func testAvailableWhenStored() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        XCTAssertTrue(route.isAvailable)
    }

    /// A failed Keychain read is not evidence the key is absent — see the type's own
    /// note, and `StoredAPIKeyPresence.permitsClearing`, which makes the identical call.
    func testAvailableWhenUnknown() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .unknown)
        XCTAssertTrue(route.isAvailable)
    }

    func testUnavailableWhenNotStored() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .notStored)
        XCTAssertFalse(route.isAvailable)
    }

    // MARK: - Never a hidden button (CLAUDE.md: absence is a designed state)

    /// Every case, not just `.notStored`, carries a non-empty sentence — the affordance
    /// is disabled, never blank, whichever state produced it.
    func testEveryStateHasAnExplanation() {
        for presence in StoredAPIKeyPresence.allCases {
            let route = PlanAuthoringConversationalRoute(apiKeyPresence: presence)
            XCTAssertFalse(
                route.explanation.isEmpty,
                "\(presence) produced an empty explanation"
            )
        }
    }

    /// The two states read differently — an available door and an unavailable one must
    /// not share one sentence, or a person reading it could not tell which is true.
    func testAvailableAndUnavailableExplanationsDiffer() {
        let available = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        let unavailable = PlanAuthoringConversationalRoute(apiKeyPresence: .notStored)
        XCTAssertNotEqual(available.explanation, unavailable.explanation)
    }

    /// `.stored` and `.unknown` are both "available", and share the exact same sentence —
    /// neither claims to know more about the key than `StoredAPIKeyPresence` does, so
    /// there is nothing for the wording to differ on.
    func testStoredAndUnknownShareOneExplanation() {
        let stored = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        let unknown = PlanAuthoringConversationalRoute(apiKeyPresence: .unknown)
        XCTAssertEqual(stored.explanation, unknown.explanation)
    }

    // MARK: - What the unavailable state says

    /// Matches the register `ChatFailureNotice.noAPIKeyStored(for:)` already uses for the
    /// identical fact, rather than a second sentence about the same thing.
    func testUnavailableExplanationNamesWhereToAddAKey() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .notStored)
        XCTAssertTrue(route.explanation.contains("Settings"))
    }

    /// The unavailable sentence must not claim a key already exists — the exact
    /// conflation MAX-154 found and fixed elsewhere in this app.
    func testUnavailableExplanationDoesNotClaimAKeyIsStored() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .notStored)
        XCTAssertFalse(route.explanation.lowercased().contains("a key is stored"))
    }

    // MARK: - What the available state says (A13 / CHAT-FIRST §2.5)

    /// The one thing this sentence must say: nothing is saved from the conversation
    /// itself. Chat cannot write (A13, CHAT-FIRST §2.5), and this door does not change
    /// that.
    func testAvailableExplanationStatesNothingIsSavedUntilReviewed() {
        let route = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        XCTAssertTrue(route.explanation.contains("nothing is saved"))
    }

    // MARK: - The action label

    func testActionLabelIsNotEmpty() {
        XCTAssertFalse(PlanAuthoringConversationalRoute.actionLabel.isEmpty)
    }

    // MARK: - MAX-190: bounding the loop with ChatSheet (CHAT-AUDIT §2.6)

    /// The gate this ticket adds: arriving from a conversation disables the button even
    /// with a key stored — the two conditions that would otherwise both say "available"
    /// individually.
    func testUnavailableWhenArrivedFromConversationEvenWithKeyStored() {
        let route = PlanAuthoringConversationalRoute(
            apiKeyPresence: .stored,
            arrivedFromConversation: true
        )
        XCTAssertFalse(route.isAvailable)
    }

    /// `.unknown` is available on the ordinary path (`testAvailableWhenUnknown`) — this
    /// checks the override still wins over every `StoredAPIKeyPresence` case, not just
    /// `.stored`.
    func testArrivedFromConversationOverridesEveryKeyPresence() {
        for presence in StoredAPIKeyPresence.allCases {
            let route = PlanAuthoringConversationalRoute(
                apiKeyPresence: presence,
                arrivedFromConversation: true
            )
            XCTAssertFalse(
                route.isAvailable,
                "\(presence) with arrivedFromConversation still reported available"
            )
        }
    }

    /// Never a hidden button here either — the explanation is real copy, not a blank
    /// disabled control.
    func testArrivedFromConversationExplanationIsNotEmpty() {
        let route = PlanAuthoringConversationalRoute(
            apiKeyPresence: .stored,
            arrivedFromConversation: true
        )
        XCTAssertFalse(route.explanation.isEmpty)
    }

    /// The arrived-from-conversation sentence must read differently from both ordinary
    /// states — a person reading it needs to know this is not the same "add a key"
    /// message, and not the same "opens a conversation" invitation either.
    func testArrivedFromConversationExplanationDiffersFromBothOrdinaryStates() {
        let arrived = PlanAuthoringConversationalRoute(
            apiKeyPresence: .stored,
            arrivedFromConversation: true
        )
        let available = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        let unavailable = PlanAuthoringConversationalRoute(apiKeyPresence: .notStored)
        XCTAssertNotEqual(arrived.explanation, available.explanation)
        XCTAssertNotEqual(arrived.explanation, unavailable.explanation)
    }

    /// The explanation must point back rather than invite a second conversation — the
    /// exact defect being fixed.
    func testArrivedFromConversationExplanationNamesGoingBack() {
        let route = PlanAuthoringConversationalRoute(
            apiKeyPresence: .stored,
            arrivedFromConversation: true
        )
        XCTAssertTrue(route.explanation.lowercased().contains("back"))
    }

    /// The default parameter is the ordinary, ubiquitous call shape used everywhere but
    /// the one screen MAX-190 touches — it must resolve exactly as if `false` had been
    /// passed explicitly.
    func testArrivedFromConversationDefaultsToOrdinaryBehavior() {
        let implicit = PlanAuthoringConversationalRoute(apiKeyPresence: .stored)
        let explicit = PlanAuthoringConversationalRoute(
            apiKeyPresence: .stored,
            arrivedFromConversation: false
        )
        XCTAssertEqual(implicit, explicit)
    }
}
