import Foundation

/// Turning a `TrendInterval` — a pair of civil days — into the instant range a
/// repository query needs.
///
/// ## Why this exists as one function
///
/// `WorkoutRepository.workouts(startingIn:)` takes a `DateInterval`, and `TrendInterval`
/// carries `CalendarDay`s. Three tickets consume the interval (the score-coloured
/// calendar, the cross-run drift overlay, and the trend tiles), so without a single
/// conversion each would write its own — and the three would not agree at the edges.
/// A run recorded at 00:30 could then appear in one surface's week and not another's,
/// which is the same class of drift D2 exists to prevent: two notions of the same
/// boundary, disagreeing invisibly until a number contradicts itself on screen.
///
/// ## Why the time zone is a parameter and not a default
///
/// `CalendarDay` deliberately carries no zone, and `TrendInterval`'s own documentation
/// declines to pick one. Reading `TimeZone.current` here would make the same historical
/// week resolve differently after the athlete flies somewhere else — exactly what D1
/// forbids of anything feeding a score. So the caller supplies it, the same way
/// `CalendarDay.init(_:in:)`, `Workout.calendarDay(in:)` and `TalliesInput` already
/// demand it.
extension TrendInterval {
    /// The instant range covering every moment of this interval's days, in `timeZone`.
    ///
    /// Half-open: it starts at the first instant of `from` and ends at the first instant
    /// of the day *after* `through`. That is the shape a "started during this interval"
    /// query wants — a run beginning at 23:59:59 on the last day is inside, and one
    /// beginning at 00:00:00 the next morning is not, with no sub-second gap between the
    /// two where a workout could fall through.
    ///
    /// - Parameter timeZone: the zone whose midnights bound the days. This is the
    ///   athlete's zone, not the device's current one, wherever the two differ.
    public func dateInterval(in timeZone: TimeZone) throws -> DateInterval {
        let start = try from.firstInstant(in: timeZone)
        let end = try through.adding(days: 1).firstInstant(in: timeZone)
        return DateInterval(start: start, end: end)
    }
}

extension CalendarDay {
    /// The first instant of this day in `timeZone`.
    ///
    /// Not simply "midnight": in a zone that has skipped a midnight for a DST
    /// transition, midnight on that date never happened, and asking `Calendar` for it
    /// yields either the wrong day or nothing. Anchoring at noon — an hour no
    /// transition has ever removed — and walking back to the day's start gives the
    /// first instant that actually existed, which is what a range boundary needs.
    ///
    /// Internal rather than public for the reason `civilAnchor()` is: handing callers a
    /// bare `Date` for a day invites the instant-versus-day confusion `CalendarDay`
    /// exists to end. `TrendInterval.dateInterval(in:)` is the supported door.
    func firstInstant(in timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let noon = calendar.date(from: components) else {
            // Unreachable: `CalendarDay` only exists for dates the Gregorian calendar
            // has. Surfaced as an error rather than a force unwrap so an unreachable
            // case stays unreachable instead of becoming a crash.
            throw DomainError.inconsistent(
                reason: "CalendarDay \(self) has no representation in \(timeZone.identifier)."
            )
        }
        return calendar.startOfDay(for: noon)
    }
}
