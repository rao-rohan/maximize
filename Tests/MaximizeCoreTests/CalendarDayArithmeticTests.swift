import Foundation
import XCTest
@testable import MaximizeCore

final class CalendarDayArithmeticTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    // MARK: - Differences

    func testDayDifferenceIsSignedAndZeroForTheSameDay() throws {
        let start = try day("2026-01-01")
        XCTAssertEqual(try start.days(until: start), 0)
        XCTAssertEqual(try start.days(until: day("2026-01-08")), 7)
        XCTAssertEqual(try day("2026-01-08").days(until: start), -7)
    }

    func testDayDifferenceCrossesMonthsYearsAndLeapDays() throws {
        XCTAssertEqual(try day("2026-01-31").days(until: day("2026-02-01")), 1)
        XCTAssertEqual(try day("2025-12-31").days(until: day("2026-01-01")), 1)
        // 2024 is a leap year: February contributes 29 days.
        XCTAssertEqual(try day("2024-02-01").days(until: day("2024-03-01")), 29)
        XCTAssertEqual(try day("2026-02-01").days(until: day("2026-03-01")), 28)
        // 1900 is divisible by four and not a leap year — the century rule, which
        // interval arithmetic on a 365.25-day year gets wrong.
        XCTAssertEqual(try day("1900-02-01").days(until: day("1900-03-01")), 28)
        XCTAssertEqual(try day("2000-02-01").days(until: day("2000-03-01")), 29)
    }

    // MARK: - Shifts

    func testAddingDaysAndWeeksRollsOverMonthAndYearBoundaries() throws {
        XCTAssertEqual(try day("2026-01-31").adding(days: 1), try day("2026-02-01"))
        XCTAssertEqual(try day("2026-12-31").adding(days: 1), try day("2027-01-01"))
        XCTAssertEqual(try day("2026-01-01").adding(days: -1), try day("2025-12-31"))
        XCTAssertEqual(try day("2024-02-28").adding(days: 1), try day("2024-02-29"))
        XCTAssertEqual(try day("2026-02-28").adding(days: 1), try day("2026-03-01"))
        XCTAssertEqual(try day("2026-01-01").adding(weeks: 2), try day("2026-01-15"))
        XCTAssertEqual(try day("2026-01-01").adding(weeks: 0), try day("2026-01-01"))
    }

    func testAddingIsTheInverseOfDifferencing() throws {
        let start = try day("2026-03-01")
        for offset in stride(from: -400, through: 400, by: 37) {
            let shifted = try start.adding(days: offset)
            XCTAssertEqual(try start.days(until: shifted), offset, "offset \(offset)")
        }
    }

    /// The trap this file exists for. A week is seven days, not 604 800 seconds; in a
    /// zone that observes DST those are different amounts of time, and the difference
    /// is enough to move a late-evening run onto the next calendar day.
    func testAWeekAcrossASpringForwardIsStillSevenDays() throws {
        // US DST begins 2026-03-08. The week 2026-03-07 → 2026-03-14 contains it.
        XCTAssertEqual(try day("2026-03-07").adding(weeks: 1), try day("2026-03-14"))
        XCTAssertEqual(try day("2026-03-07").days(until: day("2026-03-14")), 7)
        // European DST begins 2026-03-29, on a different date — a second reason not to
        // model "a week" as a fixed number of seconds in the athlete's zone.
        XCTAssertEqual(try day("2026-03-28").adding(weeks: 1), try day("2026-04-04"))
        // And the autumn transition, which errs the other way.
        XCTAssertEqual(try day("2026-10-31").adding(weeks: 1), try day("2026-11-07"))
        XCTAssertEqual(try day("2026-10-31").days(until: day("2026-11-07")), 7)
    }

    /// Demonstrates the bug rather than merely asserting its absence: adding 7 × 86 400
    /// seconds to a late-evening instant in a DST-observing zone lands on the *following*
    /// calendar day, while the day arithmetic lands where a person would say it should.
    func testIntervalArithmeticWouldHaveShiftedTheDayButCalendarArithmeticDoesNot() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork

        // 2026-03-07T23:30 local, the evening before the spring-forward.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        components.hour = 23
        components.minute = 30
        let instant = try XCTUnwrap(calendar.date(from: components))

        let startDay = try CalendarDay(instant, in: newYork)
        XCTAssertEqual(startDay, try day("2026-03-07"))

        let naive = try CalendarDay(instant.addingTimeInterval(7 * 86_400), in: newYork)
        XCTAssertEqual(naive, try day("2026-03-15"), "interval math loses the hour and rolls the day")
        XCTAssertEqual(try startDay.adding(weeks: 1), try day("2026-03-14"))
        XCTAssertNotEqual(try startDay.adding(weeks: 1), naive)
    }

    // MARK: - Week index

    func testWeekIndexCountsSevenDayBlocksFromTheStart() throws {
        let start = try day("2026-01-01")
        XCTAssertEqual(try start.weekIndex(since: start), 1)
        XCTAssertEqual(try day("2026-01-07").weekIndex(since: start), 1)
        XCTAssertEqual(try day("2026-01-08").weekIndex(since: start), 2)
        XCTAssertEqual(try day("2026-01-14").weekIndex(since: start), 2)
        XCTAssertEqual(try day("2026-04-16").weekIndex(since: start), 16)
        // Past the end of any 16-week block: the arithmetic keeps counting, and what to
        // do about it is the plan calendar's decision, not this function's.
        XCTAssertEqual(try day("2026-05-14").weekIndex(since: start), 20)
    }

    func testWeekIndexIsNilBeforeTheStart() throws {
        let start = try day("2026-01-01")
        XCTAssertNil(try day("2025-12-31").weekIndex(since: start))
        XCTAssertNil(try day("2025-01-01").weekIndex(since: start))
    }

    func testWeekIndexSurvivesADaylightSavingTransitionInsideTheWeek() throws {
        let start = try day("2026-03-04")
        XCTAssertEqual(try day("2026-03-10").weekIndex(since: start), 1)
        XCTAssertEqual(try day("2026-03-11").weekIndex(since: start), 2)
    }

    // MARK: - Ranges

    func testDayRangeIsInclusiveAtBothEndsAndAscending() throws {
        let days = try CalendarDay.days(from: day("2026-02-26"), through: day("2026-03-02"))
        XCTAssertEqual(
            days.map(\.description),
            ["2026-02-26", "2026-02-27", "2026-02-28", "2026-03-01", "2026-03-02"]
        )
        XCTAssertEqual(try CalendarDay.days(from: day("2026-01-01"), through: day("2026-01-01")).count, 1)
    }

    func testDayRangeRejectsInvertedBounds() throws {
        assertThrows(
            .inconsistent,
            try CalendarDay.days(from: day("2026-01-02"), through: day("2026-01-01"))
        )
    }

    // MARK: - Agreement with Foundation

    /// `CalendarDay.weekday` is computed with Zeller's congruence (MAX-010) while the
    /// arithmetic above goes through `Calendar`. Two notions of the same calendar are
    /// exactly the sort of thing that agrees until it doesn't, so this pins them
    /// together across four years, two leap days and both DST transitions.
    func testZellerWeekdayAgreesWithFoundationAcrossFourYears() throws {
        var cursor = try day("2024-01-01")
        let end = try day("2028-01-01")
        while cursor <= end {
            let anchor = try cursor.civilAnchor()
            let foundationWeekday = CalendarDay.civilCalendar.component(.weekday, from: anchor)
            XCTAssertEqual(cursor.weekday.foundationWeekdayNumber, foundationWeekday, "\(cursor)")
            cursor = try cursor.adding(days: 1)
        }
    }

    func testFoundationWeekdayNumberingMapsSundayToOne() {
        XCTAssertEqual(Weekday.sunday.foundationWeekdayNumber, 1)
        XCTAssertEqual(Weekday.monday.foundationWeekdayNumber, 2)
        XCTAssertEqual(Weekday.saturday.foundationWeekdayNumber, 7)
    }

    /// The arithmetic must not read `Calendar.current` or `TimeZone.current`: a device
    /// that changes zone must not change what a past day resolved to (D1).
    func testArithmeticIsPinnedToAZoneAndLocaleThatCannotVary() {
        XCTAssertEqual(CalendarDay.civilCalendar.identifier, .gregorian)
        XCTAssertEqual(CalendarDay.civilCalendar.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(CalendarDay.civilCalendar.locale?.identifier, "en_US_POSIX")
        XCTAssertEqual(CalendarDay.civilCalendar.firstWeekday, Weekday.monday.foundationWeekdayNumber)
    }
}
