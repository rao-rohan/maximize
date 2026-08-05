import Foundation
import XCTest
@testable import MaximizeCore

/// §3.6(b) — the quiet note offering a new chat when a training thread's frozen scope
/// no longer matches the dashboard's current interval.
final class ChatScopeNoticeTests: XCTestCase {

    private var august: TrendInterval {
        get throws { try TrendInterval.thisMonth(today: Fixture.day(2026, 8, 17)) }
    }

    func testAMatchingScopeProducesNoNote() throws {
        let scope = try TrainingScope(resolving: try august)
        XCTAssertNil(ChatScopeNotice.text(for: .training(scope), currentInterval: try august))
    }

    /// The case the mechanism exists for: the thread's frozen window and the dashboard's
    /// live one have drifted apart.
    func testAMismatchedScopeNamesBothWindows() throws {
        let scope = try TrainingScope(resolving: try august)
        let september = try august.next()

        let note = try XCTUnwrap(ChatScopeNotice.text(for: .training(scope), currentInterval: september))

        XCTAssertTrue(note.contains(scope.label), "names the thread's own window: \(note)")
        XCTAssertTrue(note.contains(try TrainingScope(resolving: september).label), "names the current window: \(note)")
    }

    /// A workout thread's scope is the run itself — there is no second notion of "which
    /// run" for it to disagree with, so this is nil unconditionally.
    func testAWorkoutSubjectNeverProducesANote() throws {
        XCTAssertNil(ChatScopeNotice.text(for: .workout(Fixture.workoutID), currentInterval: try august))
    }

    /// A one-day difference is still a difference — the rule is equality, not "close
    /// enough."
    func testAOneDayShiftStillCountsAsAMismatch() throws {
        let week = try TrendInterval.thisWeek(today: Fixture.day(2026, 8, 3))
        let scope = try TrainingScope(resolving: week)
        let nextWeek = try week.next()
        XCTAssertNotNil(ChatScopeNotice.text(for: .training(scope), currentInterval: nextWeek))
    }
}
