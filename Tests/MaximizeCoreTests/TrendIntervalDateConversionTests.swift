import Foundation
import XCTest
@testable import MaximizeCore

/// The single day-range → instant-range conversion (MAX-060 follow-up, MAX-083).
///
/// This exists so that the calendar, the drift section and the trend tiles cannot each
/// invent their own boundary. The tests worth having are therefore the ones about
/// *edges*: what happens at the first and last instant of an interval, and what happens
/// on the two days a year when a day is not 24 hours long.
final class TrendIntervalDateConversionTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")
    private let kathmandu = TimeZone(identifier: "Asia/Kathmandu")

    /// The day-pair door. Until MAX-083 these tests reached it by wrapping the pair in
    /// `TrendInterval.custom(...)`, which is exactly the workaround the removal of that
    /// case replaced with a named entry point.
    private func range(from: CalendarDay, through: CalendarDay, in zone: TimeZone) throws -> DateInterval {
        try DateInterval.covering(from: from, through: through, in: zone)
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> CalendarDay {
        try CalendarDay(year: year, month: month, day: dayOfMonth)
    }

    // MARK: - The half-open boundary

    /// The range ends at the first instant of the day *after* `through`, so a run
    /// beginning at 23:59:59 on the final day is inside it and one beginning the next
    /// morning is not.
    ///
    /// Asserted on the bounds themselves rather than through `DateInterval.contains(_:)`,
    /// because Foundation's `contains` is **closed at both ends** and would call the
    /// exclusive upper bound a member. The half-open reading is the repository's
    /// (`WorkoutRepository.workouts(startingIn:)` documents `start <= x < end`); the
    /// `DateInterval` is a pair of instants here, not a membership test.
    func testTheRangeEndsAtTheFirstInstantAfterTheFinalDay() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let through = try day(2026, 3, 8)
        let interval = try range(from: try day(2026, 3, 2), through: through, in: zone)

        XCTAssertEqual(interval.start, try day(2026, 3, 2).firstInstant(in: zone))
        XCTAssertEqual(interval.end, try through.adding(days: 1).firstInstant(in: zone))
    }

    /// The reason the upper bound must be treated as exclusive, pinned so nobody
    /// "fixes" the repository predicate back to `<=`: consecutive intervals share that
    /// instant, so a closed reading puts a run starting exactly at midnight into both.
    func testTheSharedBoundaryInstantIsTheStartOfTheLaterIntervalOnly() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let earlier = try range(from: try day(2026, 3, 2), through: try day(2026, 3, 8), in: zone)
        let later = try range(from: try day(2026, 3, 9), through: try day(2026, 3, 15), in: zone)

        XCTAssertEqual(earlier.end, later.start)
        // Foundation's own membership test is closed, which is exactly why the
        // repository does not use it.
        XCTAssertTrue(earlier.contains(earlier.end))
    }

    func testAdjacentIntervalsMeetExactlyWithNoGapOrOverlap() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let first = try range(from: try day(2026, 3, 2), through: try day(2026, 3, 8), in: zone)
        let second = try range(from: try day(2026, 3, 9), through: try day(2026, 3, 15), in: zone)

        XCTAssertEqual(first.end, second.start)
    }

    /// An inverted pair is a caller bug. Returning an empty range would look like
    /// "nothing happened here", which is a different and much quieter answer.
    func testAnInvertedDayPairIsRejected() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        assertThrows(
            .inconsistent,
            try range(from: try day(2026, 3, 9), through: try day(2026, 3, 8), in: zone)
        )
    }

    // MARK: - Daylight saving

    /// The week containing a spring-forward transition is 23 hours short of seven full
    /// days. Interval arithmetic (`7 * 86_400`) would land an hour inside the following
    /// day and quietly move a run onto its neighbour; going through `Calendar` counts
    /// days as days.
    func testAWeekContainingASpringForwardIsShorterThanSevenFullDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        // US DST began 2026-03-08.
        let interval = try range(from: try day(2026, 3, 2), through: try day(2026, 3, 8), in: zone)

        XCTAssertEqual(interval.duration, 7 * 86_400 - 3_600, accuracy: 1)
    }

    func testAWeekContainingAFallBackIsLongerThanSevenFullDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        // US DST ended 2026-11-01.
        let interval = try range(from: try day(2026, 10, 26), through: try day(2026, 11, 1), in: zone)

        XCTAssertEqual(interval.duration, 7 * 86_400 + 3_600, accuracy: 1)
    }

    /// An ordinary week with no transition is exactly seven days, which is what makes
    /// the two assertions above meaningful rather than noise.
    func testAnOrdinaryWeekIsExactlySevenDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let interval = try range(from: try day(2026, 6, 1), through: try day(2026, 6, 7), in: zone)

        XCTAssertEqual(interval.duration, 7 * 86_400, accuracy: 1)
    }

    // MARK: - The zone is the caller's, and it matters

    /// The same civil days in two zones are two different instant ranges. If this ever
    /// stopped being true, the conversion would be reading a zone of its own somewhere.
    func testTheSameDaysInDifferentZonesAreDifferentInstants() throws {
        guard let east = kathmandu, let west = newYork else { return XCTFail("missing time zone") }
        let first = try day(2026, 6, 1)
        let last = try day(2026, 6, 7)

        XCTAssertNotEqual(
            try range(from: first, through: last, in: east).start,
            try range(from: first, through: last, in: west).start
        )
    }

    /// A zone at a non-hour offset (Kathmandu is UTC+05:45) is where a conversion that
    /// secretly rounded to hours would show itself.
    func testAZoneWithANonHourOffsetStillStartsAtItsOwnMidnight() throws {
        guard let zone = kathmandu else { return XCTFail("missing time zone") }
        let only = try day(2026, 6, 1)
        let interval = try range(from: only, through: only, in: zone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: interval.start)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.second, 0)
    }

    // MARK: - Degenerate and shaped intervals

    func testASingleDayIntervalCoversThatWholeDay() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let only = try day(2026, 6, 1)

        XCTAssertEqual(try range(from: only, through: only, in: zone).duration, 86_400, accuracy: 1)
    }

    func testAMonthIntervalCoversEveryDayOfTheMonth() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let interval = try TrendInterval.month(try MonthInterval(year: 2026, month: 2)).dateInterval(in: zone)

        // 2026 is not a leap year.
        XCTAssertEqual(interval.duration, 28 * 86_400, accuracy: 1)
    }

    func testAWeekIntervalCoversSevenDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let week = try WeekInterval(containing: try day(2026, 6, 1))
        let interval = try TrendInterval.week(week).dateInterval(in: zone)

        XCTAssertEqual(interval.duration, 7 * 86_400, accuracy: 1)
    }

    // MARK: - Year (MAX-083)

    /// A year's range runs from the first instant of January 1st to the first instant of
    /// the *following* January 1st — the same half-open contract, at a much larger scale
    /// where an off-by-one day would be invisible in a duration check.
    func testAYearIntervalEndsAtTheFirstInstantOfTheFollowingYear() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let interval = try TrendInterval.year(try YearInterval(year: 2026)).dateInterval(in: zone)

        XCTAssertEqual(interval.start, try day(2026, 1, 1).firstInstant(in: zone))
        XCTAssertEqual(interval.end, try day(2027, 1, 1).firstInstant(in: zone))
    }

    /// A leap year is one day longer, and both years absorb their own two DST
    /// transitions — so the durations are exact day counts, not day counts plus an hour.
    /// Asserting this in a zone that *has* transitions is the point; the arithmetic runs
    /// through `Calendar`, which counts days as days.
    func testALeapYearCoversOneMoreDayThanAnOrdinaryYear() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let leap = try TrendInterval.year(try YearInterval(year: 2024)).dateInterval(in: zone)
        let ordinary = try TrendInterval.year(try YearInterval(year: 2026)).dateInterval(in: zone)

        XCTAssertEqual(leap.duration, 366 * 86_400, accuracy: 1)
        XCTAssertEqual(ordinary.duration, 365 * 86_400, accuracy: 1)
        XCTAssertEqual(leap.duration - ordinary.duration, 86_400, accuracy: 1)
    }

    /// February 29th is inside the leap year's range and outside the following year's —
    /// the day an off-by-one around the leap boundary would land on.
    func testTheLeapDayFallsInsideItsOwnYearsRange() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let leapDay = try day(2024, 2, 29).firstInstant(in: zone)
        let leapYear = try TrendInterval.year(try YearInterval(year: 2024)).dateInterval(in: zone)
        let nextYear = try TrendInterval.year(try YearInterval(year: 2025)).dateInterval(in: zone)

        XCTAssertTrue(leapDay >= leapYear.start && leapDay < leapYear.end)
        XCTAssertTrue(leapDay < nextYear.start)
    }

    /// Consecutive years meet exactly, the same way consecutive weeks do — a run started
    /// at midnight on New Year's Day belongs to the later year only.
    func testConsecutiveYearsMeetExactly() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let leap = try TrendInterval.year(try YearInterval(year: 2024)).dateInterval(in: zone)
        let following = try TrendInterval.year(try YearInterval(year: 2025)).dateInterval(in: zone)

        XCTAssertEqual(leap.end, following.start)
    }

    // MARK: - C1's widened range

    /// A week interval is already Monday-aligned, so widening it changes nothing. If
    /// this ever stopped holding, the widening would be reaching past the interval it
    /// was given.
    func testWideningAWeekIntervalIsTheSameRange() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let week = TrendInterval.week(try WeekInterval(containing: try day(2026, 6, 3)))

        XCTAssertEqual(
            try week.trainingWeekAlignedDateInterval(in: zone),
            try week.dateInterval(in: zone)
        )
    }

    /// A month almost never is. August 2026 begins on a Saturday and ends on a Monday,
    /// so the widened range reaches back to Monday July 27th and forward to Sunday
    /// September 6th — every whole training week the month touches, which is what
    /// `RestDayBudgeting` must never be given a slice of (C1).
    func testWideningAMonthReachesTheWholeTrainingWeeksItTouches() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let august = TrendInterval.month(try MonthInterval(year: 2026, month: 8))
        let widened = try august.trainingWeekAlignedDateInterval(in: zone)

        XCTAssertEqual(widened.start, try day(2026, 7, 27).firstInstant(in: zone))
        XCTAssertEqual(widened.end, try day(2026, 9, 7).firstInstant(in: zone))
    }

    /// The widened range is always a superset of the interval's own — the widening only
    /// ever reaches outward, so no day of the selection can fall out of it.
    func testTheWidenedRangeAlwaysContainsTheIntervalsOwnRange() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let intervals: [TrendInterval] = [
            .week(try WeekInterval(containing: try day(2026, 6, 3))),
            .month(try MonthInterval(year: 2026, month: 8)),
            .month(try MonthInterval(year: 2024, month: 2)),
            .year(try YearInterval(year: 2024)),
            .year(try YearInterval(year: 2026)),
        ]
        for interval in intervals {
            let own = try interval.dateInterval(in: zone)
            let widened = try interval.trainingWeekAlignedDateInterval(in: zone)
            XCTAssertLessThanOrEqual(widened.start, own.start, "\(interval)")
            XCTAssertGreaterThanOrEqual(widened.end, own.end, "\(interval)")
            // Never wider than six days either side: a whole extra week would mean the
            // widening had rounded rather than aligned.
            XCTAssertLessThanOrEqual(own.start.timeIntervalSince(widened.start), 6 * 86_400 + 3_600)
            XCTAssertLessThanOrEqual(widened.end.timeIntervalSince(own.end), 6 * 86_400 + 3_600)
        }
    }

    /// 2026 opens on a Thursday, so a year's widened range starts in the previous
    /// December — the property that makes a calendar year and a training week compose
    /// rather than conflict.
    func testWideningAYearReachesIntoTheAdjacentYearsPartialWeeks() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let widened = try TrendInterval.year(try YearInterval(year: 2026))
            .trainingWeekAlignedDateInterval(in: zone)

        // 2026-01-01 is a Thursday; its Monday is 2025-12-29.
        XCTAssertEqual(widened.start, try day(2025, 12, 29).firstInstant(in: zone))
        // 2026-12-31 is a Thursday; its week ends Sunday 2027-01-03.
        XCTAssertEqual(widened.end, try day(2027, 1, 4).firstInstant(in: zone))
    }
}
