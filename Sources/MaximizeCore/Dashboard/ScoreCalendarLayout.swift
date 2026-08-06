import Foundation

/// How a run of `ScoreCalendarDay`s is arranged on screen for the span it covers
/// (MAX-083, FR-3.2).
///
/// `ScoreCalendar.resolve` decides *what each day is*; this decides *where each day
/// goes*. Both are arithmetic — grid padding, week bucketing, which column earns a
/// month label — and arithmetic is what CI verifies in this repo, so both live here and
/// `ScoreCalendarView` renders the result without computing an index.
///
/// Which arrangement a span gets is `TrendIntervalKind.scoreCalendarRepresentation`;
/// see `DashboardSpanPresentation.swift` for the reasoning behind the choice.
public enum ScoreCalendarLayout: Hashable, Sendable {
    /// Seven columns of dated cells, Monday-first.
    case dayGrid(ScoreCalendarDayGrid)

    /// Seven weekday rows by one column per training week.
    case weekColumns(ScoreCalendarHeatmap)

    /// Arranges `days` — ascending and contiguous, as `ScoreCalendar.resolve` returns
    /// them — for `representation`.
    ///
    /// - Throws: `DomainError.inconsistent` when `days` is not ascending and gap-free.
    ///   Both arrangements below place a day by arithmetic on its date rather than by
    ///   its position in the array, so a gap would silently misalign a column rather
    ///   than visibly losing a cell — the kind of wrongness that looks like data.
    public static func resolve(
        _ days: [ScoreCalendarDay],
        as representation: ScoreCalendarRepresentation
    ) throws -> ScoreCalendarLayout {
        try requireContiguous(days)
        switch representation {
        case .dayGrid:
            return .dayGrid(try ScoreCalendarDayGrid(days: days))
        case .weekColumnHeatmap:
            return .weekColumns(try ScoreCalendarHeatmap(days: days))
        }
    }

    private static func requireContiguous(_ days: [ScoreCalendarDay]) throws {
        for (earlier, later) in zip(days, days.dropFirst()) {
            guard try earlier.date.adding(days: 1) == later.date else {
                throw DomainError.inconsistent(
                    reason: "ScoreCalendarLayout: days must be ascending and contiguous; "
                        + "\(earlier.date) is followed by \(later.date)"
                )
            }
        }
    }
}

/// The week and month arrangement: one dated cell per day in a Monday-first,
/// seven-column grid.
public struct ScoreCalendarDayGrid: Hashable, Sendable {
    /// Blank cells to emit before the first day, so it lands under its own weekday
    /// column. Zero when the range starts on a Monday, which a week interval always
    /// does and a month interval rarely does.
    ///
    /// Computed here rather than in the view — it was a `first.date.weekday.rawValue - 1`
    /// living in `ScoreCalendarView` before MAX-083 — because it is the one piece of
    /// arithmetic that, if wrong, shifts every day in the month onto the wrong weekday
    /// while still looking like a plausible calendar.
    public let leadingBlankCount: Int

    /// Ascending, one per day of the interval.
    public let days: [ScoreCalendarDay]

    init(days: [ScoreCalendarDay]) throws {
        self.days = days
        self.leadingBlankCount = days.first.map { $0.date.weekday.rawValue - 1 } ?? 0
    }
}

/// The year arrangement: seven weekday rows (Monday at the top) by one column per
/// training week, each day a single small mark.
///
/// A year is 52 or 53 columns, which fits a phone's content width at roughly six points
/// per cell, and reads as one block the height of a month grid rather than as fifty-three
/// rows of scrolling. See `ScoreCalendarRepresentation.weekColumnHeatmap` for why the
/// rows are weekdays rather than months, and for the legibility cost that choice carries.
public struct ScoreCalendarHeatmap: Hashable, Sendable {
    /// One training week.
    public struct Column: Hashable, Sendable, Identifiable {
        public var id: CalendarDay { weekStart }

        /// The Monday this column covers — `CalendarDay.startOfTrainingWeek()`, the same
        /// boundary `WeekInterval`, `TalliesCalculator` and `PlanCalendar.arcWeek` use.
        /// The heatmap's columns are therefore the athlete's actual training weeks, not
        /// arbitrary seven-day blocks counted from January 1st.
        public let weekStart: CalendarDay

        /// Exactly seven entries, Monday through Sunday.
        ///
        /// **Nil means the day is outside the selected interval**, not that nothing
        /// happened on it — the first and last columns of a year are usually partial,
        /// since a calendar year begins and ends mid-week. A view draws nil as empty
        /// space, never as a neutral or a zero cell; drawing it would extend the year by
        /// up to twelve days it does not contain.
        public let days: [ScoreCalendarDay?]

        /// The first of the month this column belongs to, on the columns that open a new
        /// month — nil on every other column. Drives the month ticks along the top of the
        /// heatmap; the view formats the name.
        ///
        /// **A column's month is the month of its Thursday.** A week straddling a month
        /// boundary has to be assigned to one of the two, and ISO-8601's own rule for
        /// this — the week belongs to the year (here, month) containing its Thursday, the
        /// majority day — is already what `CalendarDay.civilCalendar` is pinned to
        /// (`minimumDaysInFirstWeek = 4`). Reusing it means the ticks never sit more than
        /// three days off the true boundary, and never require a second convention.
        ///
        /// The one wrinkle is the partial week at either end, where the Thursday can fall
        /// outside the interval entirely — a year ending on a Tuesday has a final column
        /// whose Thursday is already in January. Labelling that "Jan" at the right-hand
        /// edge of last year's heatmap would be wrong twice over, so when the Thursday is
        /// not in the interval the month is taken from the first day the column actually
        /// shows. The result is exactly twelve ascending ticks over any calendar year,
        /// which `ScoreCalendarLayoutTests` pins for both an ordinary and a leap year.
        public let monthStart: CalendarDay?
    }

    /// Ascending by `weekStart`, one per training week the interval touches.
    public let columns: [Column]

    init(days: [ScoreCalendarDay]) throws {
        guard let first = days.first, let last = days.last else {
            self.columns = []
            return
        }

        var byDate: [CalendarDay: ScoreCalendarDay] = [:]
        byDate.reserveCapacity(days.count)
        for day in days { byDate[day.date] = day }

        var columns: [Column] = []
        // A single comparable key rather than a `(year, month)` pair: an optional tuple
        // has no `==`, and reaching for a force unwrap to compare one is banned here.
        var previousMonthKey: Int?
        var weekStart = try first.date.startOfTrainingWeek()
        let finalWeekStart = try last.date.startOfTrainingWeek()

        while weekStart <= finalWeekStart {
            var cells: [ScoreCalendarDay?] = []
            cells.reserveCapacity(7)
            for offset in 0..<7 {
                let date = try weekStart.adding(days: offset)
                cells.append(byDate[date])
            }

            // The majority day, falling back to the first day the column actually shows
            // when the Thursday is outside the interval — see `Column.monthStart`.
            let thursday = try weekStart.adding(days: 3)
            let reference = byDate[thursday]?.date ?? cells.compactMap { $0?.date }.first
            let monthStart: CalendarDay?
            if let reference {
                let monthKey = reference.year * 12 + reference.month
                if monthKey == previousMonthKey {
                    monthStart = nil
                } else {
                    monthStart = try CalendarDay(year: reference.year, month: reference.month, day: 1)
                }
                previousMonthKey = monthKey
            } else {
                monthStart = nil
            }

            columns.append(Column(weekStart: weekStart, days: cells, monthStart: monthStart))
            weekStart = try weekStart.adding(weeks: 1)
        }

        self.columns = columns
    }
}

extension ScoreCalendarDayState {
    /// Whether the heatmap should draw this day as a hollow outline rather than a filled
    /// block.
    ///
    /// At heatmap density a cell carries no date and no glyph, so MAX-061's second
    /// channel — an activity icon for a bad run, a dedicated "×" for a day nothing
    /// happened — has nowhere to live. This restores the more important half of it
    /// without hue: `.missed` and `.scored(.ineffective, _)` deliberately share a red
    /// fill (D9 says a miss "shows red", and the rubric's own "skipped → 0–15" band lands
    /// inside `.ineffective`'s range), and those are the two states it matters most not
    /// to confuse — "I ran badly" and "I did not run" are different problems with
    /// different fixes.
    ///
    /// It does not restore the whole channel by itself: `.effective` versus `.marginal`
    /// needed a separate fix, since neither carries a state of its own for this property
    /// to distinguish (both are `.scored`, just with different bands). See
    /// `ScoreBandHeatmapMark` (MAX-087) for that channel, and
    /// `ScoreCalendarRepresentation.weekColumnHeatmap` for how the two combine.
    ///
    /// **`.forthcoming` is deliberately not hollow** (MAX-105). Hollow already means
    /// "the plan asked and nothing came of it" at this density, and a day that has not
    /// arrived is the one thing that must never read that way. It draws as an ordinary
    /// neutral mark, alongside rest and awaiting-score — every no-verdict day looks the
    /// same at six points, which is the honest rendering of a year whose second half
    /// has not happened. The VoiceOver sentence still says which it is.
    ///
    /// **`.noVerdict` is not hollow either** (MAX-126), and for the stronger version of
    /// the same reason: a lift is a day the athlete *trained*. Drawing it as the outline
    /// that means "asked and not delivered" would turn a session that happened into a
    /// miss at year density — the one misreading this whole state exists to prevent.
    /// **`.partiallyMet` is hollow too, and that is a deliberate collapse** (MAX-135). A
    /// year mark is ~6pt with no glyph, so the shape channel that separates a mixed day
    /// from a plain miss in the month grid does not exist here. Of the two renderings
    /// available, hollow is the true one — an obligation the plan set went unmet — and
    /// solid would have had to be either a band colour it did not earn or a full-footprint
    /// red that reads against `.effective`'s full-footprint green on hue alone. So the two
    /// states look identical at this density and the spoken sentence carries the
    /// difference, exactly as `.scheduledRest` and `.convertedRest` are already left to it.
    public var isDrawnHollowAtHeatmapDensity: Bool {
        switch self {
        case .missed, .partiallyMet: return true
        case .scored, .awaitingScore, .noVerdict, .convertedRest, .scheduledRest,
             .forthcoming, .unplanned: return false
        }
    }

    /// Whether the day-grid cell draws no fill at all — an outline with nothing in it.
    ///
    /// The day grid's counterpart to `isDrawnHollowAtHeatmapDensity`, and the channel
    /// that separates a `.forthcoming` day from every other neutral one. `.awaitingScore`,
    /// `.noVerdict`, `.scheduledRest`, `.convertedRest` and `.unplanned` all sit on the
    /// same neutral fill (`ScoreBandColors.swift`: a day with no verdict is not a fourth
    /// band), which is fine for states told apart by their glyphs — but `.forthcoming`
    /// would have been one more neutral cell carrying a session glyph, which is very
    /// nearly `.awaitingScore` at a glance and means the opposite thing.
    ///
    /// So a forthcoming day is drawn as the plan's outline around empty space: a slot
    /// with the athlete's name on it and nothing in it yet. It is the same figure/ground
    /// argument the whole plan layer rests on, applied to the one state where the ground
    /// is all there is — and unfilled-versus-filled survives greyscale and every kind of
    /// colour vision, so it costs nothing from the band contrast budget MAX-084 and
    /// MAX-087 already spent.
    ///
    /// A useful side effect worth stating, because a later ticket will want it: the
    /// boundary between the filled cells and the unfilled ones *is* today. The calendar
    /// gains a "you are here" reading without spending a channel on one — see
    /// `docs/DESIGN-REVIEW.md` §5.4, which proposed an accent ring on the current day
    /// for that job.
    public var isDrawnUnfilledInTheDayGrid: Bool {
        if case .forthcoming = self { return true }
        return false
    }
}
