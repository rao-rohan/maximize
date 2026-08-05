import Foundation

/// The interval a trends surface is scoped to (FR-3.1): this week, this month, or this
/// year.
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
/// why). `TrendIntervalDateConversion.swift` is the single supported door for that.
///
/// ## Why every case reuses MAX-011's boundary rather than inventing one
///
/// `WeekInterval` is Monday-first because the training week already is (`Weekday` is
/// ISO-8601 for exactly that reason) — it is built directly on
/// `CalendarDay.startOfTrainingWeek()`, the same boundary `TalliesCalculator` and
/// `PlanCalendar.arcWeek(for:under:)` already anchor to. A dashboard interval that
/// disagreed with the calendar underneath it would be the same shape of drift D2
/// exists to prevent, just wearing a different case name. `MonthInterval` and
/// `YearInterval` likewise resolve their bounds through `CalendarDay` itself rather
/// than through a second copy of "how long is February".
///
/// ## Why there is no custom range (MAX-083)
///
/// MAX-060 shipped a fourth case, `.custom(CustomDateRange)`, with a pair of date
/// pickers. It is gone, at the owner's direction, and its removal is deliberately
/// total: there is no dead case, no vestigial payload type, and no picker. The reasons
/// it is not missed are worth recording, because "add a custom range back" is an easy
/// thing to propose:
///
/// - **It had no predecessor.** `previous()`/`next()` returned nil for it — a 19-day
///   range has no natural adjacent one — so the chevrons silently did nothing on a
///   quarter of the selector's states. With `.custom` gone, `previous()`/`next()` are
///   total, and no longer return an `Optional` that every call site had to defend
///   against.
/// - **It made every downstream surface's span unbounded.** Week, month and year are
///   three spans that can each be given a representation that suits them (see
///   `DashboardSpanPresentation.swift`); "17 days" is a span nothing can be designed
///   for, so every surface had to be designed for the worst case instead.
public enum TrendInterval: Hashable, Sendable {
    case week(WeekInterval)
    case month(MonthInterval)
    case year(YearInterval)

    /// Inclusive lower bound.
    public var from: CalendarDay {
        switch self {
        case .week(let week): return week.start
        case .month(let month): return month.start
        case .year(let year): return year.start
        }
    }

    /// Inclusive upper bound.
    public var through: CalendarDay {
        switch self {
        case .week(let week): return week.end
        case .month(let month): return month.end
        case .year(let year): return year.end
        }
    }

    /// Which of the three shapes this is, for a selection UI that needs to know which
    /// segment is active without switching over the payload (e.g. to drive a
    /// segmented control's binding), and for the per-span presentation table in
    /// `DashboardSpanPresentation.swift`.
    public var kind: TrendIntervalKind {
        switch self {
        case .week: return .week
        case .month: return .month
        case .year: return .year
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

    /// The calendar year containing `today`.
    public static func thisYear(today: CalendarDay) throws -> TrendInterval {
        .year(try YearInterval(containing: today))
    }

    /// The adjacent earlier interval of the same shape — the whole previous week,
    /// month or year, never a slice of one.
    ///
    /// Total, not optional: every shape has exactly one predecessor now that
    /// `.custom` is gone. It still throws, because the predecessor of the first
    /// representable year does not exist — `CalendarDay`'s domain starts at 1 AD, and
    /// walking off the end of it is a caller error rather than a silent clamp.
    public func previous() throws -> TrendInterval {
        switch self {
        case .week(let week): return .week(try week.previous())
        case .month(let month): return .month(try month.previous())
        case .year(let year): return .year(try year.previous())
        }
    }

    /// The adjacent later interval of the same shape. See `previous()`.
    public func next() throws -> TrendInterval {
        switch self {
        case .week(let week): return .week(try week.next())
        case .month(let month): return .month(try month.next())
        case .year(let year): return .year(try year.next())
        }
    }
}

/// Which shape a `TrendInterval` is, independent of its payload.
///
/// `CaseIterable` in declaration order — week, month, year — which is also the order a
/// segmented control should present them in: ascending span, most detail first.
public enum TrendIntervalKind: Hashable, Sendable, CaseIterable {
    case week
    case month
    case year
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

/// A calendar year — January 1st through December 31st (MAX-083).
///
/// ## Why a calendar year and not a rolling twelve months
///
/// A rolling window ("the last 365 days") is the tempting alternative, and it is wrong
/// for this selector for three reasons:
///
/// 1. **It has no clean predecessor.** `previous()` on a rolling window would mean
///    "the twelve months ending a year ago", which overlaps nothing and lines up with
///    nothing; step back twice and the two windows share no boundary with each other
///    or with any month or week the rest of the app reasons in.
/// 2. **It is not reproducible.** The same selection resolves to a different range
///    tomorrow, so the number on screen changes without the data changing. That is the
///    shape of non-determinism D1 forbids of anything feeding a score, and while a
///    dashboard is not the scorer, a range that quietly moves under the athlete is a
///    bad property in either place.
/// 3. **It cannot be labelled.** "2026" is unambiguous; "Aug 5 2025 – Aug 4 2026" is a
///    header nobody reads.
///
/// The cost is real and accepted: on January 2nd, "year" shows two days. That is
/// exactly the property `MonthInterval` already has on the 1st of a month, and the
/// remedy is the same one — the chevron steps back to the whole previous year.
///
/// ## What it is anchored to
///
/// The calendar year, not the training week. A year therefore begins mid-week: 2026
/// opens on a Thursday. That is deliberate and it composes: `TrendInterval`'s
/// consumers already widen to whole Monday-first weeks when the C1 obligation demands
/// it (`trainingWeekAlignedDateInterval(in:)`), exactly as they must for a month,
/// which has the same property. Anchoring the year to a Monday instead would have made
/// "2026" mean a range not equal to 2026, which is a worse trade in a label the
/// athlete reads.
///
/// Leap years need no special handling and get none: `end` is December 31st, which
/// exists in every year, and the 366th day arrives on its own because `CalendarDay`
/// already knows February's length. `TrendIntervalTests` pins 2024 anyway — a leap
/// year is precisely the case where an off-by-one hides.
public struct YearInterval: Hashable, Sendable {
    /// January 1st.
    public let start: CalendarDay
    /// December 31st.
    public let end: CalendarDay

    public var year: Int { start.year }

    /// The year containing `day`.
    public init(containing day: CalendarDay) throws {
        try self.init(year: day.year)
    }

    /// - Parameter year: 1...9999, `CalendarDay`'s own domain. Outside it this throws
    ///   rather than clamping, which is what makes `previous()`/`next()` safe to be
    ///   total at every other year.
    public init(year: Int) throws {
        self.start = try CalendarDay(year: year, month: 1, day: 1)
        self.end = try CalendarDay(year: year, month: 12, day: 31)
    }

    public func previous() throws -> YearInterval {
        try YearInterval(year: year - 1)
    }

    public func next() throws -> YearInterval {
        try YearInterval(year: year + 1)
    }
}
