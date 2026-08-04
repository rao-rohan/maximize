import Foundation
import XCTest
@testable import MaximizeCore

/// The single `TrendInterval` → `DateInterval` conversion (MAX-060 follow-up).
///
/// This exists so that MAX-061, MAX-062 and MAX-063 cannot each invent their own
/// boundary. The tests worth having are therefore the ones about *edges*: what happens
/// at the first and last instant of an interval, and what happens on the two days a
/// year when a day is not 24 hours long.
final class TrendIntervalDateConversionTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")
    private let kathmandu = TimeZone(identifier: "Asia/Kathmandu")

    private func interval(from: CalendarDay, through: CalendarDay) throws -> TrendInterval {
        .custom(try CustomDateRange(start: from, end: through))
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
        let through = try CalendarDay(year: 2026, month: 3, day: 8)
        let range = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 2),
            through: through
        ).dateInterval(in: zone)

        XCTAssertEqual(range.start, try CalendarDay(year: 2026, month: 3, day: 2).firstInstant(in: zone))
        XCTAssertEqual(range.end, try through.adding(days: 1).firstInstant(in: zone))
    }

    /// The reason the upper bound must be treated as exclusive, pinned so nobody
    /// "fixes" the repository predicate back to `<=`: consecutive intervals share that
    /// instant, so a closed reading puts a run starting exactly at midnight into both.
    func testTheSharedBoundaryInstantIsTheStartOfTheLaterIntervalOnly() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let earlier = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 2),
            through: try CalendarDay(year: 2026, month: 3, day: 8)
        ).dateInterval(in: zone)
        let later = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 9),
            through: try CalendarDay(year: 2026, month: 3, day: 15)
        ).dateInterval(in: zone)

        XCTAssertEqual(earlier.end, later.start)
        // Foundation's own membership test is closed, which is exactly why the
        // repository does not use it.
        XCTAssertTrue(earlier.contains(earlier.end))
    }

    func testAdjacentIntervalsMeetExactlyWithNoGapOrOverlap() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let first = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 2),
            through: try CalendarDay(year: 2026, month: 3, day: 8)
        ).dateInterval(in: zone)
        let second = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 9),
            through: try CalendarDay(year: 2026, month: 3, day: 15)
        ).dateInterval(in: zone)

        XCTAssertEqual(first.end, second.start)
    }

    // MARK: - Daylight saving

    /// The week containing a spring-forward transition is 23 hours short of seven full
    /// days. Interval arithmetic (`7 * 86_400`) would land an hour inside the following
    /// day and quietly move a run onto its neighbour; going through `Calendar` counts
    /// days as days.
    func testAWeekContainingASpringForwardIsShorterThanSevenFullDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        // US DST began 2026-03-08.
        let range = try interval(
            from: try CalendarDay(year: 2026, month: 3, day: 2),
            through: try CalendarDay(year: 2026, month: 3, day: 8)
        ).dateInterval(in: zone)

        XCTAssertEqual(range.duration, 7 * 86_400 - 3_600, accuracy: 1)
    }

    func testAWeekContainingAFallBackIsLongerThanSevenFullDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        // US DST ended 2026-11-01.
        let range = try interval(
            from: try CalendarDay(year: 2026, month: 10, day: 26),
            through: try CalendarDay(year: 2026, month: 11, day: 1)
        ).dateInterval(in: zone)

        XCTAssertEqual(range.duration, 7 * 86_400 + 3_600, accuracy: 1)
    }

    /// An ordinary week with no transition is exactly seven days, which is what makes
    /// the two assertions above meaningful rather than noise.
    func testAnOrdinaryWeekIsExactlySevenDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let range = try interval(
            from: try CalendarDay(year: 2026, month: 6, day: 1),
            through: try CalendarDay(year: 2026, month: 6, day: 7)
        ).dateInterval(in: zone)

        XCTAssertEqual(range.duration, 7 * 86_400, accuracy: 1)
    }

    // MARK: - The zone is the caller's, and it matters

    /// The same civil days in two zones are two different instant ranges. If this ever
    /// stopped being true, the conversion would be reading a zone of its own somewhere.
    func testTheSameDaysInDifferentZonesAreDifferentInstants() throws {
        guard let east = kathmandu, let west = newYork else { return XCTFail("missing time zone") }
        let days = try interval(
            from: try CalendarDay(year: 2026, month: 6, day: 1),
            through: try CalendarDay(year: 2026, month: 6, day: 7)
        )

        XCTAssertNotEqual(try days.dateInterval(in: east).start, try days.dateInterval(in: west).start)
    }

    /// A zone at a non-hour offset (Kathmandu is UTC+05:45) is where a conversion that
    /// secretly rounded to hours would show itself.
    func testAZoneWithANonHourOffsetStillStartsAtItsOwnMidnight() throws {
        guard let zone = kathmandu else { return XCTFail("missing time zone") }
        let range = try interval(
            from: try CalendarDay(year: 2026, month: 6, day: 1),
            through: try CalendarDay(year: 2026, month: 6, day: 1)
        ).dateInterval(in: zone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: range.start)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.second, 0)
    }

    // MARK: - Degenerate and shaped intervals

    func testASingleDayIntervalCoversThatWholeDay() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let day = try CalendarDay(year: 2026, month: 6, day: 1)
        let range = try interval(from: day, through: day).dateInterval(in: zone)

        XCTAssertEqual(range.duration, 86_400, accuracy: 1)
    }

    func testAMonthIntervalCoversEveryDayOfTheMonth() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let range = try TrendInterval.month(try MonthInterval(year: 2026, month: 2)).dateInterval(in: zone)

        // 2026 is not a leap year.
        XCTAssertEqual(range.duration, 28 * 86_400, accuracy: 1)
    }

    func testAWeekIntervalCoversSevenDays() throws {
        guard let zone = newYork else { return XCTFail("missing time zone") }
        let week = try WeekInterval(containing: try CalendarDay(year: 2026, month: 6, day: 1))
        let range = try TrendInterval.week(week).dateInterval(in: zone)

        XCTAssertEqual(range.duration, 7 * 86_400, accuracy: 1)
    }
}
