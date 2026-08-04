import Foundation
import XCTest
@testable import MaximizeCore

final class CalendarDayTests: XCTestCase {
    func testRejectsImpossibleMonthsAndDays() {
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 13, day: 1))
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 0, day: 1))
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 1, day: 0))
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 1, day: 32))
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 4, day: 31))
        assertThrows(.outOfRange, try CalendarDay(year: 0, month: 1, day: 1))
    }

    func testLeapYearsDecideWhetherFebruary29Exists() throws {
        XCTAssertNoThrow(try CalendarDay(year: 2024, month: 2, day: 29))
        XCTAssertNoThrow(try CalendarDay(year: 2000, month: 2, day: 29))
        assertThrows(.outOfRange, try CalendarDay(year: 2026, month: 2, day: 29))
        // 1900 is divisible by 4 but not a leap year — the century rule.
        assertThrows(.outOfRange, try CalendarDay(year: 1900, month: 2, day: 29))
    }

    func testWeekdayIsComputedArithmetically() throws {
        XCTAssertEqual(try CalendarDay(year: 2026, month: 8, day: 4).weekday, .tuesday)
        XCTAssertEqual(try CalendarDay(year: 2000, month: 1, day: 1).weekday, .saturday)
        XCTAssertEqual(try CalendarDay(year: 2024, month: 2, day: 29).weekday, .thursday)
        XCTAssertEqual(try CalendarDay(year: 2026, month: 1, day: 1).weekday, .thursday)
        // January and February are handled as months 13/14 of the prior year by
        // Zeller's congruence; this is the case that regresses if that is dropped.
        XCTAssertEqual(try CalendarDay(year: 2025, month: 2, day: 28).weekday, .friday)
    }

    func testOrderingIsChronological() throws {
        XCTAssertLessThan(try CalendarDay(year: 2026, month: 1, day: 31), try CalendarDay(year: 2026, month: 2, day: 1))
        XCTAssertLessThan(try CalendarDay(year: 2025, month: 12, day: 31), try CalendarDay(year: 2026, month: 1, day: 1))
        XCTAssertEqual(try CalendarDay(year: 2026, month: 3, day: 3), try CalendarDay(year: 2026, month: 3, day: 3))
    }

    func testISO8601TextIsZeroPaddedAndRoundTrips() throws {
        let day = try CalendarDay(year: 2026, month: 8, day: 4)
        XCTAssertEqual(day.description, "2026-08-04")
        XCTAssertEqual(try CalendarDay(iso8601: "2026-08-04"), day)
        XCTAssertEqual(try roundTripped(day), day)
    }

    func testRejectsMalformedISO8601() {
        assertThrows(.malformed, try CalendarDay(iso8601: "2026-8-4"))
        assertThrows(.malformed, try CalendarDay(iso8601: "2026/08/04"))
        assertThrows(.malformed, try CalendarDay(iso8601: ""))
        assertThrows(.malformed, try CalendarDay(iso8601: "20260804"))
        // Well-formed shape, impossible date: still rejected, by the range check.
        assertThrows(.outOfRange, try CalendarDay(iso8601: "2026-02-30"))
    }

    /// The reason `CalendarDay` exists: the same instant is a different day in
    /// different zones, and the caller has to say which one it means.
    func testInstantToDayDependsOnTimeZone() throws {
        let instant = Date(timeIntervalSince1970: 1_767_240_000) // 2026-01-01T04:00:00Z
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let pacific = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3_600))

        XCTAssertEqual(try CalendarDay(instant, in: utc), try CalendarDay(year: 2026, month: 1, day: 1))
        XCTAssertEqual(try CalendarDay(instant, in: pacific), try CalendarDay(year: 2025, month: 12, day: 31))
    }
}
