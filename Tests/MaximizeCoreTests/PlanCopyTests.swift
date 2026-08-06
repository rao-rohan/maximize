import XCTest
@testable import MaximizeCore

/// MAX-104: `PlanCopy.day(_:)`, the plan screens' one date renderer.
///
/// Moved down from `App/Plan/PlanFormatting.swift` so `PlanAuthoringError.description`
/// — a core-declared string — could call through to it too, closing two call sites
/// (`PlanAuthoringView`'s governed-day preview, `PlanAuthoringModel`'s save
/// confirmation) that had drifted onto `CalendarDay.description`'s bare `YYYY-MM-DD`
/// wire format instead.
final class PlanCopyTests: XCTestCase {

    func testDayReadsAsMonthDayYear() throws {
        let day = try CalendarDay(iso8601: "2026-08-05")
        XCTAssertEqual(PlanCopy.day(day), "Aug 5, 2026")
    }

    /// The one-way bridge is pinned to GMT (matching `TrendIntervalFormatting.date(for:)`)
    /// so the printed date cannot shift against whatever zone the test runner's `Date`
    /// machinery resolves to — a day right at a year boundary is the case a zone bug
    /// would first show up in.
    func testDayDoesNotShiftAtAYearBoundary() throws {
        let day = try CalendarDay(iso8601: "2025-12-31")
        XCTAssertEqual(PlanCopy.day(day), "Dec 31, 2025")
    }

    /// This is the exact drift MAX-104 found: `CalendarDay.description`'s wire format
    /// must never be what an athlete reads.
    func testDayNeverReadsAsTheWireFormat() throws {
        let day = try CalendarDay(iso8601: "2026-08-05")
        XCTAssertNotEqual(PlanCopy.day(day), day.description)
    }
}
