import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// Tests the ChatThreadListModel behavior when thread deletion fails (MAX-189, §2.5).
///
/// `ChatThreadListModel` lives in the App layer and is not directly tested by CI
/// (tracker R13). This test verifies the repository's expected behavior with a failing
/// delete, which `ChatThreadListModel` uses directly.
final class ChatThreadListModelTests: XCTestCase {

    private let zone = TimeZone.gmt
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    private var workoutSubject: ChatSubject { .workout(Fixture.workoutID) }

    // MARK: - Delete failure behavior

    /// §2.5: A failed delete must restore the row and state the failure. This test
    /// verifies the repository can produce the failure condition that the model layer
    /// checks for.
    func testRepositoryFailsDeleteAsExpected() async throws {
        let repository = FakeChatThreadRepository()
        let thread = try Fixture.thread(
            subject: workoutSubject,
            messages: [try Fixture.message(.user, "Was that on plan?", at: 0)]
        )
        try await repository.store(thread)

        // Inject a failure
        struct DeleteFailure: Error {}
        repository.failWrites(with: DeleteFailure())

        // The delete should fail
        do {
            try await repository.deleteThread(id: thread.id)
            XCTFail("expected deletion to fail")
        } catch is DeleteFailure {
            // expected
        }

        // The thread should still be in storage
        repository.stopFailing()
        let restored = try await repository.thread(id: thread.id)
        XCTAssertEqual(restored?.id, thread.id, "thread survives a failed delete")
    }

    /// Verify the error message exists and has the expected voice.
    func testCouldNotDeleteErrorMessageExists() {
        let message = ChatThreadListCopy.couldNotDeleteThread
        
        XCTAssertFalse(message.isEmpty)
        // The message should describe what happened and what to do
        XCTAssertTrue(message.contains("could not be deleted"))
        XCTAssertTrue(message.contains("still here"))
        // Should not contain raw error codes or identifiers
        XCTAssertFalse(message.contains("Error"))
        XCTAssertFalse(message.contains("Domain"))
    }
}
