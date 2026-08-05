import Foundation
import MaximizeCore
import Observation

/// Holds the dashboard's selected `TrendInterval` (FR-3.1) and the plumbing to change
/// it. No date arithmetic lives here — every transition calls into `MaximizeCore`
/// (`WeekInterval`/`MonthInterval`/`YearInterval`'s `previous()`/`next()`,
/// `TrendInterval.thisWeek`/`.thisMonth`/`.thisYear`) and this model only holds the
/// result. See CLAUDE.md's "a view should read as: observe state, render it, forward
/// user intent" — this is that rule one layer below the view, for state a view alone
/// cannot own.
///
/// **This is the seam.** The calendar, the drift section and the summary tiles each read
/// `state.interval` — via `.from`/`.through` for bounds, and via `.kind` for the
/// per-span presentation table in `DashboardSpanPresentation.swift` — to know what to
/// render. None of them owns or mutates this model; `DashboardView` holds one instance
/// and passes the selection down.
///
/// ## What MAX-083 removed
///
/// The custom range and its two `DatePicker`s are gone, along with `customRangeError`
/// and the raw picker dates that backed them. Everything this model does is now total:
/// there is no selection that can be momentarily invalid, so there is no error string to
/// hold and no "last valid selection" to fall back to. `selectPrevious()`/`selectNext()`
/// likewise stop being no-ops on a quarter of the model's states.
@MainActor
@Observable
final class TrendIntervalSelectionModel {
    enum State: Equatable {
        case ready(TrendInterval)
        /// `CalendarDay(Date(), in:)` failed to resolve "today". Unreachable on any
        /// date this app actually runs on — its only failure mode is a system clock
        /// outside `CalendarDay`'s 1...9999 AD domain — but surfaced rather than
        /// silently defaulted, the same way `WorkoutsListModel`/`WorkoutDetailModel`
        /// surface a failed read as `.failed` instead of guessing at a placeholder.
        case failed

        var interval: TrendInterval? {
            if case .ready(let interval) = self { return interval }
            return nil
        }
    }

    private(set) var state: State

    /// Nil exactly when `state == .failed` — nothing below can compute "this week",
    /// "this month" or "this year" without knowing what day it is.
    private let today: CalendarDay?

    /// - Parameters:
    ///   - today: the day the three shapes resolve relative to. Defaults to now, in
    ///     `timeZone`. Overridable so a preview or a test can pin it rather than
    ///     depending on the wall clock.
    ///   - timeZone: the zone `today` is resolved in when not supplied explicitly —
    ///     matches `WorkoutDetailModel`'s convention of taking a zone from its caller
    ///     rather than assuming one internally.
    init(today: CalendarDay? = nil, timeZone: TimeZone = .current) {
        let resolvedToday = today ?? (try? CalendarDay(Date(), in: timeZone))
        self.today = resolvedToday

        if let resolvedToday, let thisWeek = try? TrendInterval.thisWeek(today: resolvedToday) {
            state = .ready(thisWeek)
        } else {
            state = .failed
        }
    }

    // MARK: - Choosing a shape

    /// Switching shape always lands on the interval containing *today*, not on the one
    /// containing whatever the athlete had stepped back to. Carrying the offset across
    /// (week 12 of 2025 → month of March 2025) would be defensible, but it makes the
    /// segmented control's three taps unpredictable from the label alone; landing on the
    /// current period keeps "Year" meaning "this year".
    func select(_ kind: TrendIntervalKind) {
        guard let today else {
            state = .failed
            return
        }
        let interval: TrendInterval?
        switch kind {
        case .week: interval = try? TrendInterval.thisWeek(today: today)
        case .month: interval = try? TrendInterval.thisMonth(today: today)
        case .year: interval = try? TrendInterval.thisYear(today: today)
        }
        guard let interval else {
            state = .failed
            return
        }
        state = .ready(interval)
    }

    // MARK: - Stepping through periods

    /// The whole previous week, month or year. A no-op only when the step would leave
    /// `CalendarDay`'s 1...9999 AD domain, which the selector cannot reach from any date
    /// a device can be set to — the selection is left exactly where it was rather than
    /// clamped to a period the athlete did not ask for.
    func selectPrevious() {
        guard case .ready(let interval) = state,
              let previous = try? interval.previous()
        else { return }
        state = .ready(previous)
    }

    func selectNext() {
        guard case .ready(let interval) = state,
              let next = try? interval.next()
        else { return }
        state = .ready(next)
    }
}
