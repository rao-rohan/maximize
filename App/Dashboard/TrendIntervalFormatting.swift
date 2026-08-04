import Foundation
import MaximizeCore

/// Plain-text labels for `TrendInterval` (FR-3.1) — no decisions, only formatting.
///
/// Mirrors `WorkoutDisplayFormatting`'s own doc comment: which shape a `TrendInterval`
/// is, and its bounds, are already decided by `MaximizeCore`; this only turns them
/// into copy, so there is exactly one place the selector and any future consumer
/// (MAX-061/062/063 sections showing "which interval am I looking at") can drift on
/// wording, and it is this file.
enum TrendIntervalFormatting {

    /// "Aug 3 – Aug 9" for a week or custom range, "Aug 3, 2025 – Jan 2, 2026" when the
    /// range crosses a year boundary, "August 2026" for a month.
    static func label(for interval: TrendInterval) -> String {
        switch interval {
        case .month(let month):
            return monthFormatter.string(from: date(for: month.start))
        case .week(let week):
            return rangeLabel(from: week.start, through: week.end)
        case .custom(let range):
            return rangeLabel(from: range.start, through: range.end)
        }
    }

    private static func rangeLabel(from start: CalendarDay, through end: CalendarDay) -> String {
        if start.year == end.year {
            return "\(dayFormatter.string(from: date(for: start))) – \(dayFormatter.string(from: date(for: end)))"
        }
        // Crossing a year boundary (a week spanning New Year's, or a custom range) —
        // spell out both years so the label is never ambiguous about which one.
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
    /// `DateFormatter` and never read back into a `CalendarDay`. `TrendIntervalSelectionModel`
    /// has its own near-identical helper for seeding its `DatePicker`s rather than
    /// reusing this one, precisely because *that* result **is** read back (when the
    /// athlete edits the picker) and must round-trip through the model's real
    /// `timeZone`, not GMT — see that type's own documentation for why reusing this
    /// one there would be a latent bug in an extreme-offset zone.
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = .gmt
        return formatter
    }()
}
