import Foundation

/// Human-readable labels for a `CalendarDay` and a pair of them.
///
/// `CalendarDay.description` is the `YYYY-MM-DD` wire format — sortable, parseable, and
/// not what anybody wants to read in a list row. This is the other rendering, and it
/// lives in the core because the values it labels are decided here: a chat thread's
/// title and its frozen scope (A11) are core values, so the strings they carry have to
/// be derivable without a view.
///
/// ## No locale, on purpose
///
/// English month names from a fixed table, exactly as `FactSheetFormatting.weekdayName`
/// already does, rather than a `DateFormatter`. Three reasons, in order of weight:
///
/// 1. A thread title is **stored data's shadow** — the same thread must render the same
///    title on every launch, and a title that changed with the device's locale would
///    make a list row disagree with itself.
/// 2. A `DateFormatter` needs a `Date`, and turning a `CalendarDay` back into one needs
///    a time zone this type has no business choosing (`CalendarDay.init(_:in:)`'s own
///    reasoning, in reverse).
/// 3. It is testable with no fixture setup and no zone data, which is what makes the
///    truncation and range rules above it worth asserting on.
///
/// The cost is that this app speaks English. It already does — every `task` string, every
/// absence line, every fact-sheet heading — so this adds no new obligation.
enum CalendarDayLabel {

    /// "3 Aug 2026".
    static func full(_ day: CalendarDay) -> String {
        "\(day.day) \(shortMonthName(day.month)) \(day.year)"
    }

    /// "3 Aug" — the form used inside a range that already states its year.
    static func dayAndMonth(_ day: CalendarDay) -> String {
        "\(day.day) \(shortMonthName(day.month))"
    }

    /// The narrowest unambiguous label for an inclusive day range.
    ///
    /// - "3 Aug 2026" when both bounds are the same day
    /// - "3 – 9 Aug 2026" within one month
    /// - "28 Jul – 3 Aug 2026" within one year
    /// - "28 Dec 2025 – 3 Jan 2026" across a year boundary
    ///
    /// The last case is the one worth having: a training thread's scope is frozen at
    /// creation (§3.4, A11), so a thread opened in the first week of January is
    /// permanently about a range that straddles two years, and a label reading
    /// "28 Dec – 3 Jan" would be read as the wrong December.
    static func range(from start: CalendarDay, through end: CalendarDay) -> String {
        if start == end {
            return full(start)
        }
        if start.year != end.year {
            return "\(full(start)) – \(full(end))"
        }
        if start.month == end.month {
            return "\(start.day) – \(end.day) \(shortMonthName(end.month)) \(end.year)"
        }
        return "\(dayAndMonth(start)) – \(full(end))"
    }

    /// - Parameter month: 1...12, `CalendarDay`'s own domain. The `default` is
    ///   unreachable for a value that came from a `CalendarDay`; it exists because force
    ///   unwraps and fatal errors are both banned in non-test code, and an empty string
    ///   is visibly wrong rather than a crash.
    static func shortMonthName(_ month: Int) -> String {
        switch month {
        case 1: return "Jan"
        case 2: return "Feb"
        case 3: return "Mar"
        case 4: return "Apr"
        case 5: return "May"
        case 6: return "Jun"
        case 7: return "Jul"
        case 8: return "Aug"
        case 9: return "Sep"
        case 10: return "Oct"
        case 11: return "Nov"
        case 12: return "Dec"
        default: return ""
        }
    }
}
