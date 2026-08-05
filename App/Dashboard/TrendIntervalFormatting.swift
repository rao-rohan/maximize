import Foundation
import MaximizeCore

/// Plain-text labels for `TrendInterval` (FR-3.1) — no decisions, only formatting.
///
/// Mirrors `WorkoutDisplayFormatting`'s own doc comment: which shape a `TrendInterval`
/// is, and its bounds, are already decided by `MaximizeCore`; this only turns them
/// into copy, so there is exactly one place the selector and every dashboard section
/// showing "which interval am I looking at" can drift on wording, and it is this file.
enum TrendIntervalFormatting {

    /// The segment title and the noun in "Previous week" / "Next year".
    static func name(for kind: TrendIntervalKind) -> String {
        switch kind {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// "Aug 3 – Aug 9" for a week, "Aug 3, 2025 – Jan 2, 2026" when the week crosses a
    /// year boundary, "August 2026" for a month, "2026" for a year.
    static func label(for interval: TrendInterval) -> String {
        switch interval {
        case .year(let year):
            return String(year.year)
        case .month(let month):
            return monthFormatter.string(from: date(for: month.start))
        case .week(let week):
            return rangeLabel(from: week.start, through: week.end)
        }
    }

    /// "Aug" — the month ticks along the top of the year heatmap
    /// (`ScoreCalendarHeatmap.Column.monthStart`).
    static func shortMonthName(for day: CalendarDay) -> String {
        shortMonthFormatter.string(from: date(for: day))
    }

    private static func rangeLabel(from start: CalendarDay, through end: CalendarDay) -> String {
        if start.year == end.year {
            return "\(dayFormatter.string(from: date(for: start))) – \(dayFormatter.string(from: date(for: end)))"
        }
        // Crossing a year boundary (a week spanning New Year's) — spell out both years so
        // the label is never ambiguous about which one.
        let startText = "\(dayFormatter.string(from: date(for: start))), \(start.year)"
        let endText = "\(dayFormatter.string(from: date(for: end))), \(end.year)"
        return "\(startText) – \(endText)"
    }

    /// A `Date` at GMT noon carrying exactly `day`'s calendar fields and nothing
    /// else — reconstructed only because `DateFormatter` speaks `Date`, not
    /// `CalendarDay`. Pinned to GMT so the printed date never shifts against a
    /// device's own time zone.
    ///
    /// This is a one-way bridge for *display only* — its result is fed straight to a
    /// `DateFormatter` and never read back into a `CalendarDay`. Nothing in the app
    /// round-trips a picked date any more: MAX-083 removed the custom range, which was
    /// the only control that did, along with the near-identical seeding helper
    /// `TrendIntervalSelectionModel` kept for it.
    private static func date(for day: CalendarDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // `Calendar.date(from:)` only returns nil for components outside its domain;
        // `day`'s own fields are already known-valid (it is a `CalendarDay`), so this
        // is unreachable — `Date()` is a harmless, visibly-wrong-if-it-ever-fired
        // fallback rather than a force unwrap.
        return calendar.date(from: components) ?? Date()
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.timeZone = .gmt
        return formatter
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        formatter.timeZone = .gmt
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = .gmt
        return formatter
    }()
}
