import Foundation
import MaximizeCore
import Observation

/// Holds the dashboard's selected `TrendInterval` (FR-3.1) and the plumbing to change
/// it. No date arithmetic lives here — every transition calls into `MaximizeCore`
/// (`WeekInterval`/`MonthInterval`'s `previous()`/`next()`, `TrendInterval.thisWeek`/
/// `.thisMonth`, `CustomDateRange.init`) and this model only holds the result and
/// converts a `DatePicker`'s raw `Date` into the day it names via
/// `CalendarDay.init(_:in:)`, `MaximizeCore`'s own single sanctioned entry point for
/// that conversion. See CLAUDE.md's "a view should read as: observe state, render it,
/// forward user intent" — this is that rule one layer below the view, for state a
/// view alone cannot own.
///
/// **This is the seam.** MAX-061 (calendar), MAX-062 (drift overlay) and MAX-063
/// (summary tiles) are each expected to read `state.interval` — via `.from`/
/// `.through` (see `TrendInterval`'s own documentation) — to know what to render.
/// None of them owns or mutates this model; `DashboardView` is expected to hold one
/// instance and pass the selection down to each section as it lands.
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

    /// Set when the picker's raw `customStartDate`/`customEndDate` do not currently
    /// form a valid range (end before start). `state` is left pointing at the last
    /// *valid* selection in that case — never pushed into a `TrendInterval` that
    /// couldn't be constructed (see `CustomDateRange`) — so an in-progress edit can
    /// never leave the model without something valid to hand its consumers.
    private(set) var customRangeError: String?

    /// Raw picker values backing the custom-range controls. Kept separate from
    /// `state` precisely so a momentarily-invalid pair of taps never has to become a
    /// `TrendInterval` at all; `applyCustomRange()` is what turns them into one, or
    /// declines to.
    private(set) var customStartDate: Date
    private(set) var customEndDate: Date

    private let timeZone: TimeZone

    /// Nil exactly when `state == .failed` — nothing below can compute "this week" or
    /// "this month" without knowing what day it is.
    private let today: CalendarDay?

    /// - Parameters:
    ///   - today: the day "this week"/"this month" resolve relative to. Defaults to
    ///     now, in `timeZone`. Overridable so a preview or a test can pin it rather
    ///     than depending on the wall clock.
    ///   - timeZone: the zone `today` is resolved in when not supplied explicitly —
    ///     matches `WorkoutDetailModel`'s convention of taking a zone from its caller
    ///     rather than assuming one internally.
    init(today: CalendarDay? = nil, timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        let resolvedToday = today ?? (try? CalendarDay(Date(), in: timeZone))
        self.today = resolvedToday

        if let resolvedToday, let thisWeek = try? TrendInterval.thisWeek(today: resolvedToday) {
            state = .ready(thisWeek)
        } else {
            state = .failed
        }

        let seedDate = resolvedToday.map { TrendIntervalSelectionModel.date(forSeeding: $0, in: timeZone) } ?? Date()
        customStartDate = seedDate
        customEndDate = seedDate
    }

    // MARK: - Choosing a shape

    func selectWeek() {
        guard let today, let interval = try? TrendInterval.thisWeek(today: today) else {
            state = .failed
            return
        }
        state = .ready(interval)
        customRangeError = nil
    }

    func selectMonth() {
        guard let today, let interval = try? TrendInterval.thisMonth(today: today) else {
            state = .failed
            return
        }
        state = .ready(interval)
        customRangeError = nil
    }

    /// Switches to a custom range, seeded from the day the athlete was already
    /// looking at (the current selection's `from`, or `today` if nothing has
    /// resolved yet) rather than an arbitrary default.
    func selectCustom() {
        if let seed = state.interval?.from ?? today {
            let seedDate = TrendIntervalSelectionModel.date(forSeeding: seed, in: timeZone)
            customStartDate = seedDate
            customEndDate = seedDate
        }
        applyCustomRange()
    }

    // MARK: - Week/month navigation

    /// No-op when the current selection is `.custom` — `TrendInterval.previous()`
    /// returns nil there by design (see its own documentation), and this model
    /// leaves the selection exactly where it was rather than guessing at one.
    func selectPrevious() {
        guard case .ready(let interval) = state,
              let stepped = try? interval.previous(),
              let previous = stepped
        else { return }
        state = .ready(previous)
    }

    func selectNext() {
        guard case .ready(let interval) = state,
              let stepped = try? interval.next(),
              let next = stepped
        else { return }
        state = .ready(next)
    }

    // MARK: - Custom range editing

    func updateCustomStart(_ date: Date) {
        customStartDate = date
        applyCustomRange()
    }

    func updateCustomEnd(_ date: Date) {
        customEndDate = date
        applyCustomRange()
    }

    /// The one place a picked `Date` becomes a day of record: both raw picker values
    /// go through `CalendarDay.init(_:in:)`, then `CustomDateRange.init`, which is
    /// where an end-before-start pair is rejected (FR-3.1's "a custom range must be
    /// unable to be invalid"). A rejection updates `customRangeError` and leaves
    /// `state` on the last valid selection; it never reaches this model's consumers.
    private func applyCustomRange() {
        do {
            let start = try CalendarDay(customStartDate, in: timeZone)
            let end = try CalendarDay(customEndDate, in: timeZone)
            let range = try CustomDateRange(start: start, end: end)
            state = .ready(.custom(range))
            customRangeError = nil
        } catch {
            customRangeError = "The end date must be on or after the start date."
        }
    }

    // MARK: - Seeding a picker from a `CalendarDay`

    /// The inverse of `CalendarDay.init(_:in:)`, scoped to *this model's own*
    /// `timeZone` so a `CalendarDay` used to seed a picker and the `CalendarDay` read
    /// back from it via `applyCustomRange()` always agree.
    ///
    /// Deliberately **not** `TrendIntervalFormatting.date(for:)` — that helper is
    /// pinned to GMT for label text that is only ever displayed, never round-tripped.
    /// Reusing it here would seed the picker at GMT noon while reading it back
    /// through this model's real (possibly very different) `timeZone`; for an
    /// extreme-offset zone that pair can disagree on which civil day GMT noon falls
    /// on, silently shifting the seeded date by one. Noon *local* keeps the
    /// reconstructed instant safely inside the same civil day through a DST
    /// transition, where midnight local would not be (a spring-forward can delete
    /// 00:00–00:59 entirely in some zones).
    ///
    /// `static`, taking `timeZone` explicitly, rather than an instance method reading
    /// `self.timeZone`: `init` needs to call this before every stored property has a
    /// value, and forming a reference to an instance method that captures `self`
    /// before then is invalid — a free function sidesteps that entirely.
    private static func date(forSeeding day: CalendarDay, in timeZone: TimeZone) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Unreachable for a valid `CalendarDay` and this model's `timeZone`, per the
        // same reasoning as `TrendIntervalFormatting.date(for:)`.
        return calendar.date(from: components) ?? Date()
    }
}
