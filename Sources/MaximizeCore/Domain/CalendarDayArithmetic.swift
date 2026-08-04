import Foundation

/// Day and week arithmetic on `CalendarDay` — the substrate the plan calendar is
/// resolved with (MAX-011).
///
/// ## Why `Calendar` and not seconds
///
/// The tempting spelling of "a week later" is `date.addingTimeInterval(7 * 86_400)`, and
/// it is wrong twice a year: the week containing a daylight-saving transition is 23 or 25
/// hours long, so interval arithmetic lands an hour either side of midnight and quietly
/// moves a day onto its neighbour. On a plan calendar that means a run scored against the
/// wrong scheduled session — the misclassification PRD §13 names, arriving by the back
/// door. Every shift and difference below goes through `Calendar`, which counts days as
/// days.
///
/// ## Why this is still deterministic
///
/// `Calendar.current` and `TimeZone.current` are inputs that change under the code: the
/// same historical day would resolve differently after the device flies somewhere else,
/// which is exactly what D1 forbids. So the arithmetic runs in a calendar pinned to
/// values that cannot vary — proleptic Gregorian, GMT, POSIX locale — over a
/// `CalendarDay`, which carries no time and no zone. A shift here therefore cannot cross
/// a DST boundary at all; it is civil-date arithmetic, and the fixed calendar is only the
/// engine that knows how long February is.
///
/// The one place a zone genuinely matters is turning an *instant* into a day, and that
/// has a single entry point which demands the zone from its caller
/// (`CalendarDay.init(_:in:)`, MAX-010). Nothing in this file infers one.
extension CalendarDay {
    /// The calendar all day arithmetic runs in.
    ///
    /// Every field that could otherwise be read from user or system state is set
    /// explicitly. `firstWeekday` and `minimumDaysInFirstWeek` are pinned to ISO-8601
    /// values even though nothing here asks for a week-of-year: leaving them at whatever
    /// the platform's locale supplies would leave a locale-shaped trap for the next
    /// person who does.
    static let civilCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = Weekday.monday.foundationWeekdayNumber
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    /// Midnight GMT on this day, as the anchor `Calendar` needs to count from.
    ///
    /// Internal, and deliberately not `public`: handing callers a `Date` invites the
    /// instant-versus-day confusion `CalendarDay` exists to end. The GMT midnight is an
    /// implementation detail of the arithmetic, not a claim about when the day started
    /// for the athlete.
    func civilAnchor() throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let anchor = CalendarDay.civilCalendar.date(from: components) else {
            // Unreachable: `CalendarDay` only exists for dates the Gregorian calendar
            // has. Surfaced as an error rather than a force unwrap so an unreachable
            // case stays unreachable instead of becoming a crash.
            throw DomainError.malformed(field: "CalendarDay.civilAnchor", value: description)
        }
        return anchor
    }

    /// Whole days from this day to `other`; negative when `other` is earlier.
    ///
    /// `self.days(until: self) == 0`, so this is a difference, not a count of days
    /// covered.
    public func days(until other: CalendarDay) throws -> Int {
        let from = try civilAnchor()
        let to = try other.civilAnchor()
        let difference = CalendarDay.civilCalendar.dateComponents([.day], from: from, to: to)
        guard let days = difference.day else {
            throw DomainError.malformed(field: "CalendarDay.days(until:)", value: "\(self)…\(other)")
        }
        return days
    }

    /// The day `days` later (earlier, for a negative value).
    public func adding(days: Int) throws -> CalendarDay {
        let anchor = try civilAnchor()
        guard let shifted = CalendarDay.civilCalendar.date(byAdding: .day, value: days, to: anchor) else {
            throw DomainError.malformed(field: "CalendarDay.adding(days:)", value: "\(self)+\(days)")
        }
        return try CalendarDay(shifted, in: .gmt)
    }

    /// The day `weeks` seven-day weeks later. A week is seven days here by definition,
    /// not by multiplication of an hour count.
    public func adding(weeks: Int) throws -> CalendarDay {
        try adding(days: weeks * 7)
    }

    /// The 1-based week this day falls in, counting seven-day blocks from `start`.
    ///
    /// This is the indexing `LongRunArc.Week` documents ("1-based and indexed relative to
    /// the plan's `effectiveFrom`"): `start` itself is week 1, `start + 6` days is still
    /// week 1, `start + 7` days is week 2.
    ///
    /// The week therefore begins on whatever weekday `start` falls on, which makes the
    /// *choice of `start`* the load-bearing decision rather than anything here. See
    /// `PlanCalendar.arcWeek(for:under:)`, which anchors it to the Monday on or before
    /// the plan's effective date so arc weeks line up with the Monday-first weekly
    /// template.
    ///
    /// Nil before `start`. A day the arc does not reach backwards to is not week zero and
    /// not week one; it belongs to whatever came before, and saying so is the caller's
    /// job.
    public func weekIndex(since start: CalendarDay) throws -> Int? {
        let elapsed = try start.days(until: self)
        guard elapsed >= 0 else { return nil }
        return elapsed / 7 + 1
    }

    /// The Monday on or before this day.
    ///
    /// `Weekday` is ISO-8601 (Monday = 1), so the offset back to Monday is simply the
    /// weekday's raw value minus one — Monday returns itself, Sunday steps back six days.
    /// The training week is Monday-first because the weekly template is written that way.
    public func startOfTrainingWeek() throws -> CalendarDay {
        try adding(days: -(weekday.rawValue - 1))
    }

    /// Every day from `start` through `end`, inclusive at both ends, ascending.
    ///
    /// Throws rather than returning empty when the bounds are inverted: an inverted range
    /// is a caller bug, and an empty calendar would look like "the plan asks for nothing
    /// here", which is a different and much quieter answer.
    public static func days(from start: CalendarDay, through end: CalendarDay) throws -> [CalendarDay] {
        guard start <= end else {
            throw DomainError.inconsistent(
                reason: "CalendarDay.days(from:through:) needs start (\(start)) ≤ end (\(end))"
            )
        }
        var days: [CalendarDay] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            cursor = try cursor.adding(days: 1)
        }
        return days
    }
}

extension Weekday {
    /// This weekday in `Foundation`'s numbering (Sunday = 1), for the rare places that
    /// have to speak to `Calendar`. The domain speaks ISO-8601 (Monday = 1) everywhere
    /// else because the weekly training template is written Monday-first.
    var foundationWeekdayNumber: Int {
        self == .sunday ? 1 : rawValue + 1
    }
}
