import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-186: what the workout screen's chat card says, asserted against what the
/// function actually returns rather than against a fixture built to match it.
final class WorkoutChatCardPresentationTests: XCTestCase {

    // MARK: - No thread at all

    func testNoThreadIsTheInvitation() {
        XCTAssertEqual(WorkoutChatCardPresentation.state(for: nil), .invitation)
    }

    // MARK: - A thread nobody has spoken in

    func testAThreadWithNoVisibleMessagesIsAlsoTheInvitation() throws {
        let thread = try Fixture.thread(subject: .workout(Fixture.workoutID), messages: [])
        XCTAssertEqual(WorkoutChatCardPresentation.state(for: thread), .invitation)
    }

    /// A thread whose only turn is the seeded system context (D3) has nothing a person
    /// said — `ChatThreadSummary.preview` already treats that as no preview, and this
    /// type has to inherit the same rule rather than reading `messages.last` for itself.
    func testAThreadWithOnlyASystemSeedIsTheInvitation() throws {
        let thread = try Fixture.thread(
            subject: .workout(Fixture.workoutID),
            messages: [try Fixture.message(.system, "Seeded context", at: 0)]
        )
        XCTAssertEqual(WorkoutChatCardPresentation.state(for: thread), .invitation)
    }

    // MARK: - A real conversation

    func testAThreadWithMessagesCarriesTheLastExchange() throws {
        let thread = try Fixture.thread(
            subject: .workout(Fixture.workoutID),
            messages: [
                try Fixture.message(.user, "Why did my heart rate climb at 4k?", at: 0),
                try Fixture.message(.assistant, "It tracked the grade — that stretch climbs.", at: 30),
            ]
        )

        guard case let .lastExchange(preview, lastActivityAt) = WorkoutChatCardPresentation.state(for: thread) else {
            return XCTFail("expected .lastExchange")
        }
        XCTAssertEqual(preview, "It tracked the grade — that stretch climbs.")
        XCTAssertEqual(lastActivityAt, thread.lastActivityAt)
    }

    /// The preview is `ChatThreadSummary`'s own field, not a second derivation — proven
    /// by comparing against what that type actually returns for the same thread, rather
    /// than against a hand-typed string this test could get wrong the same way the
    /// implementation might.
    func testThePreviewAgreesWithChatThreadSummary() throws {
        let longReply = String(repeating: "pace, drift and cadence all together ", count: 5)
        let thread = try Fixture.thread(
            subject: .workout(Fixture.workoutID),
            messages: [
                try Fixture.message(.user, "How did this one go overall?", at: 0),
                try Fixture.message(.assistant, longReply, at: 30),
            ]
        )

        guard case let .lastExchange(preview, _) = WorkoutChatCardPresentation.state(for: thread) else {
            return XCTFail("expected .lastExchange")
        }
        XCTAssertEqual(preview, ChatThreadSummary(thread).preview)
    }

    // MARK: - The VoiceOver sentence

    func testTheAccessibilityLabelNamesTheTimestampBeforeThePreview() {
        let label = WorkoutChatCardPresentation.accessibilityLabel(
            preview: "It tracked the grade.",
            spokenTimestamp: "3 hours ago"
        )
        XCTAssertEqual(label, "Last message, 3 hours ago. It tracked the grade.")
    }
}
