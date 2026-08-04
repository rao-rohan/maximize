import Foundation

/// The interval a trends surface is scoped to (FR-3.1): this week, this month, or a
/// custom range. This is the whole of MAX-060's scope — three tickets consume it
/// (MAX-061 the score-colored calendar, MAX-062 the cross-run HR-drift overlay,
/// MAX-063 the summary tiles) but build nothing here.
///
/// ## The seam
///
/// Every case resolves to `from`/`through` — the exact vocabulary `Tallies`,
/// `TalliesInput`, and `PlanCalendar.planDays(from:through:)` already use for an
/// inclusive day range (MAX-011/MAX-017). A consumer wanting workouts, plan days, or
/// tallies for the selected interval reads `interval.from`/`interval.through` and
/// hands them to whichever of those it already calls:
///
/// ```swift
/// let tallies = try TalliesCalculator.compute(TalliesInput(
///     from: interval.from, through: interval.through, timeZone: ..., workouts: ...,
///     planCalendar: ..., restDayBudget: ...
/// ))
/// let planDays = try planCalendar.planDays(from: interval.from, through: interval.through)
/// ```
///
/// No new vocabulary, and no second notion of "what range is selected" for D2 to let
/// drift from `Tallies`'s own. `WorkoutRepository.workouts(startingIn:)` takes a
/// `DateInterval` (an instant range) rather than a `CalendarDay` pair — turning
/// `from`/`through` into one needs a time zone, which is a decision this type
/// deliberately does not make (see `CalendarDay.init(_:in:)`'s own doc comment for
/// why). That conversion is the consuming ticket's job, the same way `TalliesInput`
/// and `WorkoutDetailModel` already take a time zone from their caller rather than
/// assuming `.current` themselves.
///
/// ## Why week and month reuse MAX-011's boundary rather than inventing one
///
/// `WeekInterval` is Monday-first because the training week already is (`Weekday` is
/// ISO-8601 for exactly that reason) — it is built directly on
/// `CalendarDay.startOfTrainingWeek()`, the same boundary `TalliesCalculator` and
/// `PlanCalendar.arcWeek(for:under:)` already anchor to. A dashboard interval that
/// disagreed with the calendar underneath it would be the same shape of drift D2
/// exists to prevent, just wearing a different case name.
public enum TrendInterval: Hashable, Sendable {
    case week(WeekInterval)
    case month(MonthInterval)
    case custom(CustomDateRange)

    /// Inclusive lower bound.
    public var from: CalendarDay {
        switch self {
        case .week(let week): return week.start
        case .month(let month): return month.start
        case .custom(let range): return range.start
        }
    }

    /// Inclusive upper bound.
    public var through: CalendarDay {
        switch self {
        case .week(let week): return week.end
        case .month(let month): return month.end
        case .custom(let range): return range.end
        }
    }

    /// Which of the three shapes this is, for a selection UI that needs to know which
    /// segment is active without switching over the payload (e.g. to drive a
    /// segmented control's binding).
    public var kind: TrendIntervalKind {
        switch self {
        case .week: return .week
        case .month: return .month
        case .custom: return .custom
        }
    }

    /// The Monday-first training week containing `today` — the dashboard's default
    /// "this week" selection.
    public static func thisWeek(today: CalendarDay) throws -> TrendInterval {
        .week(try WeekInterval(containing: today))
    }

    /// The calendar month containing `today` — the default "this month" selection.
    public static func thisMonth(today: CalendarDay) throws -> TrendInterval {
        .month(try MonthInterval(containing: today))
    }

    /// The adjacent earlier interval of the same shape — the whole previous week or
    /// month, never a slice of one.
    ///
    /// Nil for `.custom`: "the previous custom range" is not a well-defined operation
    /// (a 3-day range and a 19-day range have no natural predecessor), so the
    /// selection UI asks the athlete for a new range instead of guessing at an
    /// adjacent one.
    public func previous() throws -> TrendInterval? {
        switch self {
        case .week(let week): return .week(try week.previous())
        case .month(let month): return .month(try month.previous())
        case .custom: return nil
        }
    }

    /// The adjacent later interval of the same shape. See `previous()` for why
    /// `.custom` has none.
    public func next() throws -> TrendInterval? {
        switch self {
        case .week(let week): return .week(try week.next())
        case .month(let month): return .month(try month.next())
        case .custom: return nil
        }
    }
}

/// Which shape a `TrendInterval` is, independent of its payload.
public enum TrendIntervalKind: Hashable, Sendable, CaseIterable {
    case week
    case month
    case custom
}

/// A Monday-first training week (FR-3.1's "this week").
///
/// Built directly on `CalendarDay.startOfTrainingWeek()` (MAX-011) rather than
/// re-deriving "which day is Monday" here — see `TrendInterval`'s documentation for
/// why a second notion of the training week would be a problem, not a convenience.
public struct WeekInterval: Hashable, Sendable {
    /// Monday.
    public let start: CalendarDay
    /// Sunday.
    public let end: CalendarDay

    /// The week containing `day`.
    public init(containing day: CalendarDay) throws {
        try self.init(start: day.startOfTrainingWeek())
    }

    private init(start: CalendarDay) throws {
        self.start = start
        self.end = try start.adding(days: 6)
    }

    /// The whole previous Monday–Sunday week — never merely "seven days back from
    /// wherever the athlete last looked," so repeated calls stay aligned to calendar
    /// weeks rather than drifting off them.
    public func previous() throws -> WeekInterval {
        try WeekInterval(start: start.adding(weeks: -1))
    }

    public func next() throws -> WeekInterval {
        try WeekInterval(start: start.adding(weeks: 1))
    }
}

/// A calendar month (FR-3.1's "this month").
///
/// `end` is resolved through `CalendarDay`'s own leap-year table
/// (`CalendarDay.daysInMonth`, package-internal) rather than a second copy of "how
/// long is February" living here — a 28/29/30/31-day month is never a place this type
/// and `CalendarDay` could disagree.
public struct MonthInterval: Hashable, Sendable {
    /// The first of the month.
    public let start: CalendarDay
    /// The last day of the month.
    public let end: CalendarDay

    public var year: Int { start.year }
    public var month: Int { start.month }

    /// The month containing `day`.
    public init(containing day: CalendarDay) throws {
        try self.init(year: day.year, month: day.month)
    }

    /// - Parameters:
    ///   - year: 1...9999, `CalendarDay`'s own domain.
    ///   - month: 1 (January) ... 12 (December).
    public init(year: Int, month: Int) throws {
        let start = try CalendarDay(year: year, month: month, day: 1)
        let lastDay = CalendarDay.daysInMonth(month: month, year: year)
        self.start = start
        self.end = try CalendarDay(year: year, month: month, day: lastDay)
    }

    /// The preceding calendar month, rolling January back to December of the
    /// previous year.
    public func previous() throws -> MonthInterval {
        let dayBefore = try start.adding(days: -1)
        return try MonthInterval(year: dayBefore.year, month: dayBefore.month)
    }

    /// The following calendar month, rolling December forward to January of the
    /// next year.
    public func next() throws -> MonthInterval {
        let dayAfterEnd = try end.adding(days: 1)
        return try MonthInterval(year: dayAfterEnd.year, month: dayAfterEnd.month)
    }
}

/// A custom date range (FR-3.1).
///
/// Constructing one with `end` before `start` throws rather than clamping or
/// silently swapping the bounds — CLAUDE.md's "model illegal states as
/// unrepresentable," applied the same way `Tallies.init`, `TalliesInput.init`, and
/// `TrainingWeek.init` already guard `from ≤ through`.
///
/// There is no separate "empty range" case to reject: `CalendarDay` is whole-day
/// granularity and both bounds are always present and inclusive, so the shortest
/// representable range is one day (`start == end`). There is no way to construct a
/// zero-day range through this initializer at all, so nothing downstream has to
/// defend against one.
public struct CustomDateRange: Hashable, Sendable {
    public let start: CalendarDay
    public let end: CalendarDay

    /// - Throws: `DomainError.inconsistent` if `end` precedes `start`.
    public init(start: CalendarDay, end: CalendarDay) throws {
        guard start <= end else {
            throw DomainError.inconsistent(
                reason: "CustomDateRange: end (\(end)) must not be before start (\(start))"
            )
        }
        self.start = start
        self.end = end
    }
}
