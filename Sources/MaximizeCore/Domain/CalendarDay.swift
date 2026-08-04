import Foundation

/// A day on the proleptic Gregorian calendar, with no time and no time zone.
///
/// The plan calendar (`PlanDay`), rest-day overrides, and plan effectivity are all
/// *day*-scoped, not instant-scoped: "the plan version in effect on the workout's
/// date" (D1) is a statement about a calendar day. Storing those as `Date` invites
/// the classic bug where a run at 23:40 local lands on the following day once a
/// `Date` is interpreted in UTC.
///
/// Converting an instant to a day requires a time zone, so that conversion is an
/// explicit, single entry point (`init(_:in:)`) rather than something that happens
/// implicitly wherever a date is compared.
public struct CalendarDay: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// - Parameters:
    ///   - year: 1...9999. The lower bound exists so the weekday arithmetic below has
    ///     a defined domain, not because the app cares about the first millennium.
    ///   - month: 1 (January) ... 12 (December).
    ///   - day: 1 ... the length of the given month, leap years included.
    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year) else {
            throw DomainError.outOfRange(
                field: "CalendarDay.year", value: Double(year), lowerBound: 1, upperBound: 9999
            )
        }
        guard (1...12).contains(month) else {
            throw DomainError.outOfRange(
                field: "CalendarDay.month", value: Double(month), lowerBound: 1, upperBound: 12
            )
        }
        let lastDay = CalendarDay.daysInMonth(month: month, year: year)
        guard (1...lastDay).contains(day) else {
            throw DomainError.outOfRange(
                field: "CalendarDay.day", value: Double(day), lowerBound: 1, upperBound: Double(lastDay)
            )
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. This is also the wire format used by `Codable`.
    public init(iso8601 text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw DomainError.malformed(field: "CalendarDay", value: text)
        }
        try self.init(year: year, month: month, day: day)
    }

    /// The one place an instant becomes a day. The time zone is required, never
    /// inferred: the answer genuinely differs across zones and the caller is the only
    /// one who knows which zone the user was running in.
    public init(_ instant: Date, in timeZone: TimeZone) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw DomainError.malformed(field: "CalendarDay", value: "\(instant)")
        }
        try self.init(year: year, month: month, day: day)
    }

    public var description: String {
        "\(CalendarDay.pad(year, width: 4))-\(CalendarDay.pad(month, width: 2))-\(CalendarDay.pad(day, width: 2))"
    }

    /// Day of week, computed arithmetically (Zeller's congruence) rather than through
    /// `Calendar`, so weekly-template resolution stays a pure, deterministic function
    /// with no locale or time-zone input.
    public var weekday: Weekday {
        var m = month
        var y = year
        if m < 3 {
            m += 12
            y -= 1
        }
        let k = y % 100
        let j = y / 100
        let h = (day + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7
        // Zeller yields 0 = Saturday; Weekday is ISO-8601 (1 = Monday).
        let iso = ((h + 5) % 7) + 1
        // `iso` is 1...7 by construction; the coalesce only exists because force
        // unwraps are banned in non-test code, and it is covered by tests.
        return Weekday(rawValue: iso) ?? .monday
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(iso8601: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func pad(_ value: Int, width: Int) -> String {
        var text = String(value)
        while text.count < width { text = "0" + text }
        return text
    }
}

/// Day of week, numbered as ISO-8601 does (Monday = 1). Chosen over Foundation's
/// Sunday-first numbering because the weekly training template is written
/// Monday-first.
public enum Weekday: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
