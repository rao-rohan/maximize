import Foundation
import XCTest
@testable import MaximizeCore

final class TrendIntervalTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    // MARK: - Week

    func testWeekContainingResolvesToTheMondayFirstWeek() throws {
        // 2026-08-04 is a Tuesday.
        let week = try WeekInterval(containing: day("2026-08-04"))
        XCTAssertEqual(week.start, try day("2026-08-03")) // Monday
        XCTAssertEqual(week.end, try day("2026-08-09")) // Sunday
    }

    func testWeekContainingAMondayStartsOnItself() throws {
        let monday = try day("2026-08-03")
        let week = try WeekInterval(containing: monday)
        XCTAssertEqual(week.start, monday)
    }

    func testWeekContainingASundayEndsOnItself() throws {
        let sunday = try day("2026-08-09")
        let week = try WeekInterval(containing: sunday)
        XCTAssertEqual(week.end, sunday)
        XCTAssertEqual(week.start, try day("2026-08-03"))
    }

    func testWeekMatchesCalendarDayStartOfTrainingWeek() throws {
        // The whole point of building on top of `startOfTrainingWeek()` rather than a
        // second notion of "which day is Monday" (TrendInterval's own doc comment).
        var cursor = try day("2026-01-01")
        let end = try day("2026-12-31")
        while cursor <= end {
            let week = try WeekInterval(containing: cursor)
            XCTAssertEqual(week.start, try cursor.startOfTrainingWeek(), "\(cursor)")
            cursor = try cursor.adding(days: 1)
        }
    }

    func testWeekPreviousAndNextStayAlignedToCalendarWeeks() throws {
        let week = try WeekInterval(containing: day("2026-08-04"))
        let previous = try week.previous()
        XCTAssertEqual(previous.start, try day("2026-07-27"))
        XCTAssertEqual(previous.end, try day("2026-08-02"))

        let next = try week.next()
        XCTAssertEqual(next.start, try day("2026-08-10"))
        XCTAssertEqual(next.end, try day("2026-08-16"))

        // Round-tripping stays exact rather than drifting.
        XCTAssertEqual(try previous.next(), week)
        XCTAssertEqual(try next.previous(), week)
    }

    /// The trap `CalendarDayArithmeticTests` documents at length: a week must stay
    /// seven days even when it contains a DST transition.
    func testWeekAcrossADaylightSavingTransitionIsStillSevenDays() throws {
        // US DST begins 2026-03-08, inside the week 2026-03-02...2026-03-08.
        let week = try WeekInterval(containing: day("2026-03-04"))
        XCTAssertEqual(week.start, try day("2026-03-02"))
        XCTAssertEqual(week.end, try day("2026-03-08"))
        XCTAssertEqual(try week.start.days(until: week.end), 6)

        let next = try week.next()
        XCTAssertEqual(next.start, try day("2026-03-09"))
        XCTAssertEqual(next.end, try day("2026-03-15"))
    }

    func testWeekPreviousCrossesAYearBoundary() throws {
        let week = try WeekInterval(containing: day("2026-01-02")) // Friday, week of Dec 29
        XCTAssertEqual(week.start, try day("2025-12-29"))
        let previous = try week.previous()
        XCTAssertEqual(previous.start, try day("2025-12-22"))
        XCTAssertEqual(previous.end, try day("2025-12-28"))
    }

    // MARK: - Month

    func testMonthContainingResolvesToTheFirstAndLastDay() throws {
        let month = try MonthInterval(containing: day("2026-08-15"))
        XCTAssertEqual(month.start, try day("2026-08-01"))
        XCTAssertEqual(month.end, try day("2026-08-31"))
        XCTAssertEqual(month.year, 2026)
        XCTAssertEqual(month.month, 8)
    }

    func testMonthEndAccountsForVaryingMonthLengths() throws {
        XCTAssertEqual(try MonthInterval(year: 2026, month: 2).end, try day("2026-02-28")) // 28
        XCTAssertEqual(try MonthInterval(year: 2024, month: 2).end, try day("2024-02-29")) // 29, leap year
        XCTAssertEqual(try MonthInterval(year: 2026, month: 4).end, try day("2026-04-30")) // 30
        XCTAssertEqual(try MonthInterval(year: 2026, month: 1).end, try day("2026-01-31")) // 31
    }

    func testMonthPreviousAndNextRollOverYearBoundaries() throws {
        let january = try MonthInterval(year: 2026, month: 1)
        let previous = try january.previous()
        XCTAssertEqual(previous.year, 2025)
        XCTAssertEqual(previous.month, 12)
        XCTAssertEqual(previous.end, try day("2025-12-31"))

        let december = try MonthInterval(year: 2025, month: 12)
        let next = try december.next()
        XCTAssertEqual(next.year, 2026)
        XCTAssertEqual(next.month, 1)
    }

    func testMonthPreviousAndNextRollOverAcrossLeapFebruary() throws {
        let march = try MonthInterval(year: 2024, month: 3)
        let previous = try march.previous()
        XCTAssertEqual(previous.month, 2)
        XCTAssertEqual(previous.end, try day("2024-02-29"))

        let next = try previous.next()
        XCTAssertEqual(next.start, march.start)
        XCTAssertEqual(next.end, march.end)
    }

    func testMonthRejectsOutOfRangeMonth() throws {
        assertThrows(.outOfRange, try MonthInterval(year: 2026, month: 13))
        assertThrows(.outOfRange, try MonthInterval(year: 2026, month: 0))
    }

    // MARK: - Custom range

    func testCustomRangeAcceptsAStartEqualToEnd() throws {
        let sameDay = try day("2026-08-04")
        let range = try CustomDateRange(start: sameDay, end: sameDay)
        XCTAssertEqual(range.start, sameDay)
        XCTAssertEqual(range.end, sameDay)
    }

    func testCustomRangeAcceptsAnOrderedRange() throws {
        let range = try CustomDateRange(start: try day("2026-07-01"), end: try day("2026-08-04"))
        XCTAssertEqual(range.start, try day("2026-07-01"))
        XCTAssertEqual(range.end, try day("2026-08-04"))
    }

    /// The illegal state this whole type exists to make unrepresentable.
    func testCustomRangeRejectsAnEndBeforeItsStart() throws {
        assertThrows(
            .inconsistent,
            try CustomDateRange(start: try day("2026-08-04"), end: try day("2026-08-03"))
        )
    }

    // MARK: - TrendInterval bounds

    func testTrendIntervalFromAndThroughMatchEachCasesBounds() throws {
        let week = try TrendInterval.thisWeek(today: day("2026-08-04"))
        XCTAssertEqual(week.from, try day("2026-08-03"))
        XCTAssertEqual(week.through, try day("2026-08-09"))
        XCTAssertEqual(week.kind, .week)

        let month = try TrendInterval.thisMonth(today: day("2026-08-04"))
        XCTAssertEqual(month.from, try day("2026-08-01"))
        XCTAssertEqual(month.through, try day("2026-08-31"))
        XCTAssertEqual(month.kind, .month)

        let custom = TrendInterval.custom(
            try CustomDateRange(start: try day("2026-01-01"), end: try day("2026-01-10"))
        )
        XCTAssertEqual(custom.from, try day("2026-01-01"))
        XCTAssertEqual(custom.through, try day("2026-01-10"))
        XCTAssertEqual(custom.kind, .custom)
    }

    // MARK: - Navigation

    func testTrendIntervalPreviousAndNextDelegateToTheUnderlyingCase() throws {
        let week = try TrendInterval.thisWeek(today: day("2026-08-04"))
        let previousWeek = try XCTUnwrap(week.previous())
        XCTAssertEqual(previousWeek.from, try day("2026-07-27"))

        let month = try TrendInterval.thisMonth(today: day("2026-08-04"))
        let nextMonth = try XCTUnwrap(month.next())
        XCTAssertEqual(nextMonth.from, try day("2026-09-01"))
    }

    /// A custom range has no natural predecessor or successor — the selection UI is
    /// expected to ask for a new range rather than this type guessing at one.
    func testTrendIntervalPreviousAndNextAreNilForCustom() throws {
        let custom = TrendInterval.custom(
            try CustomDateRange(start: try day("2026-01-01"), end: try day("2026-01-10"))
        )
        XCTAssertNil(try custom.previous())
        XCTAssertNil(try custom.next())
    }

    // MARK: - Equality (Hashable/Equatable synthesis sanity)

    func testEqualIntervalsCompareEqual() throws {
        let a = try TrendInterval.thisWeek(today: day("2026-08-04"))
        let b = try TrendInterval.thisWeek(today: day("2026-08-06")) // same week, different day
        XCTAssertEqual(a, b)
    }
}
