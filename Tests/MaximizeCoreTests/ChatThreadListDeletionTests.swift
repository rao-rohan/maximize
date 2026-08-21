import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// Tests for thread list deletion and error handling (MAX-189, §2.5).
///
/// The decision logic — given a failed or successful delete, what should the list
/// show — lives in `ChatThreadListPresentation.deletionOutcome()` where CI can verify
/// it. This test suite ensures the decision is correct.
final class ChatThreadListDeletionTests: XCTestCase {

    private let zone = TimeZone.gmt
    /// 2026-08-05T12:00:00Z, a Wednesday
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    private var workoutSubject: ChatSubject { .workout(Fixture.workoutID) }

    private func summary(
        id: UUID = UUID(),
        subject: ChatSubject? = nil,
        title: String = "A thread",
        at date: Date? = nil
    ) -> ChatThreadSummary {
        ChatThreadSummary(
            id: id,
            subject: subject ?? workoutSubject,
            title: title,
            lastActivityAt: date ?? now,
            preview: "The last thing said"
        )
    }

    // MARK: - Successful delete

    func testSuccessfulDeleteRemovesTheRowAndClearsMessage() {
        let summary = summary()
        let result = ChatThreadListPresentation.deletionOutcome(
            from: [summary],
            attemptedThreadID: summary.id,
            error: nil,
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(result.summaries.count, 0, "row is removed from summaries")
        XCTAssertNil(result.errorMessage, "no error message on success")
        XCTAssertEqual(result.sections.count, 0, "sections are empty when list is empty")
    }

    func testSuccessfulDeletePreservesOtherRows() {
        let doomed = summary(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())
        let survivor = summary(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID())

        let result = ChatThreadListPresentation.deletionOutcome(
            from: [doomed, survivor],
            attemptedThreadID: doomed.id,
            error: nil,
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(result.summaries.count, 1, "one row removed, one remains")
        XCTAssertEqual(result.summaries[0].id, survivor.id, "the right row survives")
        XCTAssertNil(result.errorMessage)
    }

    // MARK: - Failed delete

    func testFailedDeleteRestoresTheRowAndSetsErrorMessage() {
        let summary = summary()
        struct DeleteFailure: Error {}

        let result = ChatThreadListPresentation.deletionOutcome(
            from: [summary],
            attemptedThreadID: summary.id,
            error: DeleteFailure(),
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(result.summaries.count, 1, "row is restored")
        XCTAssertEqual(result.summaries[0].id, summary.id, "it is the same row")
        XCTAssertEqual(result.errorMessage, ChatThreadListCopy.couldNotDeleteThread, "error message is set")
        XCTAssertEqual(result.sections.count, 1, "row is in sections")
    }

    func testFailedDeletePreservesAllRows() {
        let one = summary(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID())
        let two = summary(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID())
        let three = summary(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID())
        struct DeleteFailure: Error {}

        let result = ChatThreadListPresentation.deletionOutcome(
            from: [one, two, three],
            attemptedThreadID: two.id,
            error: DeleteFailure(),
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(result.summaries.count, 3, "all rows survive a failed delete")
        XCTAssertEqual(result.summaries.map(\.id), [one.id, two.id, three.id])
        XCTAssertEqual(result.errorMessage, ChatThreadListCopy.couldNotDeleteThread)
    }

    // MARK: - Error message rules

    func testErrorMessageHasNoRawCodes() {
        let message = ChatThreadListCopy.couldNotDeleteThread
        XCTAssertFalse(message.contains("Error"), "no 'Error' keyword")
        XCTAssertFalse(message.contains("Domain"), "no 'Domain' keyword")
        XCTAssertFalse(message.contains("Code"), "no 'Code' keyword")
    }

    func testErrorMessageStatesWhatHappenedAndWhyItMatters() {
        let message = ChatThreadListCopy.couldNotDeleteThread
        XCTAssertTrue(
            message.contains("could not be deleted") || message.contains("cannot be deleted"),
            "message states what happened"
        )
        XCTAssertTrue(
            message.contains("still here") || message.contains("remains"),
            "message states the consequence"
        )
    }
}
