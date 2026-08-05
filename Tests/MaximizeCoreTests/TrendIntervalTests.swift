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

    // MARK: - Year (MAX-083)

    func testYearContainingResolvesToJanuaryFirstThroughDecemberThirtyFirst() throws {
        let year = try YearInterval(containing: day("2026-08-15"))
        XCTAssertEqual(year.start, try day("2026-01-01"))
        XCTAssertEqual(year.end, try day("2026-12-31"))
        XCTAssertEqual(year.year, 2026)
    }

    /// The boundary days are themselves in the year they open and close, which is the
    /// off-by-one a half-open habit invites.
    func testYearContainingItsOwnBoundaryDaysStaysInThatYear() throws {
        XCTAssertEqual(try YearInterval(containing: day("2026-01-01")).year, 2026)
        XCTAssertEqual(try YearInterval(containing: day("2026-12-31")).year, 2026)
    }

    /// A leap year is 366 days and contains February 29th. Both are asserted through
    /// `CalendarDay`'s own arithmetic rather than a constant, since that is the table
    /// `YearInterval` deliberately does not duplicate.
    func testLeapYearCoversThreeHundredAndSixtySixDays() throws {
        let leap = try YearInterval(year: 2024)
        XCTAssertEqual(try leap.start.days(until: leap.end), 365) // a difference, so 366 days
        XCTAssertEqual(try YearInterval(containing: day("2024-02-29")).year, 2024)

        let ordinary = try YearInterval(year: 2026)
        XCTAssertEqual(try ordinary.start.days(until: ordinary.end), 364)
    }

    /// A century year divisible by 100 but not 400 is *not* a leap year — the rule
    /// `CalendarDay.isLeapYear` encodes, checked through this type so a future
    /// hand-rolled year length here would fail.
    func testYearLengthFollowsTheGregorianCenturyRule() throws {
        let nineteenHundred = try YearInterval(year: 1900)
        XCTAssertEqual(try nineteenHundred.start.days(until: nineteenHundred.end), 364)

        let twoThousand = try YearInterval(year: 2000)
        XCTAssertEqual(try twoThousand.start.days(until: twoThousand.end), 365)
    }

    func testYearPreviousAndNextStepWholeYearsAndRoundTrip() throws {
        let year = try YearInterval(year: 2026)
        let previous = try year.previous()
        XCTAssertEqual(previous.year, 2025)
        XCTAssertEqual(previous.start, try day("2025-01-01"))
        XCTAssertEqual(previous.end, try day("2025-12-31"))

        let next = try year.next()
        XCTAssertEqual(next.year, 2027)

        XCTAssertEqual(try previous.next(), year)
        XCTAssertEqual(try next.previous(), year)
    }

    /// Stepping in and out of a leap year must not shift a bound: February's length is
    /// the only thing that changes, and neither bound is in February.
    func testYearStepsAcrossALeapYearWithoutDisturbingItsBounds() throws {
        let leap = try YearInterval(year: 2024)
        XCTAssertEqual(try leap.previous().end, try day("2023-12-31"))
        XCTAssertEqual(try leap.next().start, try day("2025-01-01"))
        XCTAssertEqual(try leap.previous().next(), leap)
    }

    /// `CalendarDay`'s domain is 1...9999, so the ends of it are where `previous()` and
    /// `next()` run out. They throw rather than clamping — a clamp would silently show
    /// year 1 twice in a row.
    func testYearRejectsSteppingOutsideCalendarDaysDomain() throws {
        assertThrows(.outOfRange, try YearInterval(year: 1).previous())
        assertThrows(.outOfRange, try YearInterval(year: 9_999).next())
        assertThrows(.outOfRange, try YearInterval(year: 0))
        assertThrows(.outOfRange, try YearInterval(year: 10_000))
    }

    /// Every day of a leap year resolves to that same year, and to a day inside its
    /// bounds — the exhaustive form of the two assertions above.
    func testEveryDayOfALeapYearFallsInsideItsOwnYearInterval() throws {
        let year = try YearInterval(year: 2024)
        var cursor = year.start
        var count = 0
        while cursor <= year.end {
            XCTAssertEqual(try YearInterval(containing: cursor), year, "\(cursor)")
            count += 1
            cursor = try cursor.adding(days: 1)
        }
        XCTAssertEqual(count, 366)
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

        let year = try TrendInterval.thisYear(today: day("2026-08-04"))
        XCTAssertEqual(year.from, try day("2026-01-01"))
        XCTAssertEqual(year.through, try day("2026-12-31"))
        XCTAssertEqual(year.kind, .year)
    }

    /// The selector renders `allCases` directly, so the set of spans and their order are
    /// stated once. Ascending span, most detail first.
    func testTrendIntervalKindEnumeratesTheThreeSpansInAscendingOrder() {
        XCTAssertEqual(TrendIntervalKind.allCases, [.week, .month, .year])
    }

    // MARK: - Navigation

    func testTrendIntervalPreviousAndNextDelegateToTheUnderlyingCase() throws {
        let week = try TrendInterval.thisWeek(today: day("2026-08-04"))
        XCTAssertEqual(try week.previous().from, try day("2026-07-27"))

        let month = try TrendInterval.thisMonth(today: day("2026-08-04"))
        XCTAssertEqual(try month.next().from, try day("2026-09-01"))

        let year = try TrendInterval.thisYear(today: day("2026-08-04"))
        XCTAssertEqual(try year.previous().from, try day("2025-01-01"))
        XCTAssertEqual(try year.previous().through, try day("2025-12-31"))
        XCTAssertEqual(try year.next().from, try day("2027-01-01"))
    }

    /// Every step preserves the shape it started in — a step never converts a year into
    /// twelve months or a month into four weeks.
    func testSteppingPreservesTheIntervalsKind() throws {
        for interval in [
            try TrendInterval.thisWeek(today: day("2026-08-04")),
            try TrendInterval.thisMonth(today: day("2026-08-04")),
            try TrendInterval.thisYear(today: day("2026-08-04")),
        ] {
            XCTAssertEqual(try interval.previous().kind, interval.kind)
            XCTAssertEqual(try interval.next().kind, interval.kind)
            XCTAssertEqual(try interval.previous().next(), interval)
        }
    }

    // MARK: - Equality (Hashable/Equatable synthesis sanity)

    func testEqualIntervalsCompareEqual() throws {
        let a = try TrendInterval.thisWeek(today: day("2026-08-04"))
        let b = try TrendInterval.thisWeek(today: day("2026-08-06")) // same week, different day
        XCTAssertEqual(a, b)
    }
}
