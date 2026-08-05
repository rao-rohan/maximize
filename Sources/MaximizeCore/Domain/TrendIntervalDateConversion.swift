import Foundation

/// Turning a pair of civil days — a `TrendInterval`, or the widened bounds one of its
/// consumers needs — into the instant range a repository query takes.
///
/// ## Why this exists as one function
///
/// `WorkoutRepository.workouts(startingIn:)` takes a `DateInterval`, and `TrendInterval`
/// carries `CalendarDay`s. Three surfaces consume the interval (the score-coloured
/// calendar, the cross-run drift overlay, and the trend tiles), so without a single
/// conversion each would write its own — and the three would not agree at the edges.
/// A run recorded at 00:30 could then appear in one surface's week and not another's,
/// which is the same class of drift D2 exists to prevent: two notions of the same
/// boundary, disagreeing invisibly until a number contradicts itself on screen.
///
/// **MAX-083 note.** Until the custom range was removed, callers who needed the *widened*
/// C1 range (whole Monday-first weeks around the selection) reached it by wrapping their
/// widened bounds in a throwaway `TrendInterval.custom(...)` purely to borrow this
/// conversion. That is why `.custom` appeared in `ScoreCalendarModel` and
/// `TrendTilesModel`, neither of which had anything custom about it. With the case gone,
/// the widening is expressed directly — `trainingWeekAlignedDateInterval(in:)` below —
/// so there is still exactly one conversion and no call site has to fabricate an
/// interval shape it does not mean.
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
    /// **`DateInterval.contains(_:)` is the wrong way to ask.** Foundation's interval is
    /// closed at both ends, so it calls the exclusive upper bound a member. Since
    /// consecutive intervals share that instant, a closed reading double-counts a run
    /// starting exactly at midnight. `WorkoutRepository.workouts(startingIn:)` documents
    /// and implements the half-open comparison instead; the `DateInterval` returned here
    /// is a pair of bounds, not a membership test.
    ///
    /// - Parameter timeZone: the zone whose midnights bound the days. This is the
    ///   athlete's zone, not the device's current one, wherever the two differ.
    public func dateInterval(in timeZone: TimeZone) throws -> DateInterval {
        try DateInterval.covering(from: from, through: through, in: timeZone)
    }

    /// The instant range covering every **whole Monday-first training week** this
    /// interval touches — C1's obligation, expressed once.
    ///
    /// `RestDayBudgeting` must never see a partial training week: ranking a missed day is
    /// relative to the other misses *in its week*, so a slice reaches a different answer
    /// than the whole week would. `TalliesInput` and `ScoreCalendar` both document the
    /// resulting requirement on the workouts they are handed, and both of their callers
    /// were widening by hand before this existed. A week interval is already aligned, so
    /// this returns the same range `dateInterval(in:)` does; a month or a year almost
    /// never is.
    ///
    /// The widening is only ever *outward*, so the returned range is a superset of
    /// `dateInterval(in:)`'s. `TalliesCalculator`, `ScoreCalendar` and `TrendTileData`
    /// each narrow the extra days back out themselves; nothing counts a workout from an
    /// edge week into the interval's own figures.
    public func trainingWeekAlignedDateInterval(in timeZone: TimeZone) throws -> DateInterval {
        try DateInterval.covering(
            from: from.startOfTrainingWeek(),
            through: through.startOfTrainingWeek().adding(days: 6),
            in: timeZone
        )
    }
}

extension DateInterval {
    /// The half-open instant range covering `from` through `through` inclusive, in
    /// `timeZone`. See `TrendInterval.dateInterval(in:)` for the boundary contract —
    /// this is the same conversion, reachable by callers holding a day pair that is not
    /// itself a `TrendInterval` (the widened C1 bounds above being the only one today).
    ///
    /// - Throws: `DomainError.inconsistent` when `through` precedes `from`. An inverted
    ///   pair is a caller bug; returning an empty range would look like "nothing
    ///   happened here", which is a different and much quieter answer.
    public static func covering(
        from: CalendarDay,
        through: CalendarDay,
        in timeZone: TimeZone
    ) throws -> DateInterval {
        guard from <= through else {
            throw DomainError.inconsistent(
                reason: "DateInterval.covering: from (\(from)) must not be after through (\(through))"
            )
        }
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
    /// exists to end. `DateInterval.covering(from:through:in:)` is the supported door.
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
