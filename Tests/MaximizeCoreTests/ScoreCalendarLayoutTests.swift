import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-083 — where each resolved day goes on screen, for the span it belongs to.
///
/// `ScoreCalendarTests` covers *what* a day is; nothing here re-tests that. These are
/// about arrangement: grid padding, week bucketing, which column earns a month tick, and
/// the partial weeks at either end of a calendar year.
final class ScoreCalendarLayoutTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// Unplanned days throughout: this suite is about placement, and the state a cell
    /// carries is irrelevant to where it lands.
    private func days(from: String, through: String) throws -> [ScoreCalendarDay] {
        try CalendarDay.days(from: try day(from), through: try day(through))
            .map { ScoreCalendarDay(date: $0, state: .unplanned) }
    }

    /// Thrown rather than skipped: `resolve` returning the other arrangement for the
    /// representation it was handed is a failure, not a case to step over.
    private struct WrongArrangement: Error {}

    private func grid(from: String, through: String) throws -> ScoreCalendarDayGrid {
        let layout = try ScoreCalendarLayout.resolve(try days(from: from, through: through), as: .dayGrid)
        guard case .dayGrid(let grid) = layout else { throw WrongArrangement() }
        return grid
    }

    private func heatmap(from: String, through: String) throws -> ScoreCalendarHeatmap {
        let layout = try ScoreCalendarLayout.resolve(
            try days(from: from, through: through), as: .weekColumnHeatmap
        )
        guard case .weekColumns(let heatmap) = layout else { throw WrongArrangement() }
        return heatmap
    }

    // MARK: - Which arrangement a span gets

    /// The table in `DashboardSpanPresentation.swift`, pinned.
    func testWeekAndMonthGetTheDayGridAndAYearGetsTheHeatmap() {
        XCTAssertEqual(TrendIntervalKind.week.scoreCalendarRepresentation, .dayGrid)
        XCTAssertEqual(TrendIntervalKind.month.scoreCalendarRepresentation, .dayGrid)
        XCTAssertEqual(TrendIntervalKind.year.scoreCalendarRepresentation, .weekColumnHeatmap)
    }

    // MARK: - Day grid

    /// A training week always starts on a Monday, so it never needs padding.
    func testAWeekNeedsNoLeadingBlanks() throws {
        let grid = try grid(from: "2026-08-03", through: "2026-08-09") // Mon–Sun
        XCTAssertEqual(grid.leadingBlankCount, 0)
        XCTAssertEqual(grid.days.count, 7)
    }

    /// August 2026 opens on a Saturday, which is weekday 6 — five blanks before it so it
    /// lands in the sixth column.
    func testAMonthIsPaddedToItsFirstDaysWeekdayColumn() throws {
        let grid = try grid(from: "2026-08-01", through: "2026-08-31")
        XCTAssertEqual(grid.days.first?.date.weekday, .saturday)
        XCTAssertEqual(grid.leadingBlankCount, 5)
        XCTAssertEqual(grid.days.count, 31)
    }

    /// Every weekday, so the arithmetic is pinned rather than sampled — an off-by-one
    /// here shifts a whole month onto the wrong weekday while still looking plausible.
    func testLeadingBlanksMatchTheFirstDaysISOWeekdayForEveryMonthOfAYear() throws {
        for month in 1...12 {
            let interval = try MonthInterval(year: 2026, month: month)
            let grid = try grid(from: interval.start.description, through: interval.end.description)
            XCTAssertEqual(
                grid.leadingBlankCount,
                interval.start.weekday.rawValue - 1,
                "\(interval.start)"
            )
        }
    }

    /// February 2024 begins on a Thursday and runs 29 days — the leap month, where a
    /// grid built from a hardcoded month length would come up a cell short.
    func testALeapFebruaryFillsTwentyNineCells() throws {
        let grid = try grid(from: "2024-02-01", through: "2024-02-29")
        XCTAssertEqual(grid.days.count, 29)
        XCTAssertEqual(grid.leadingBlankCount, 3) // Thursday
    }

    // MARK: - Heatmap: columns are training weeks

    /// 2026 opens on a Thursday, so the first column is the week beginning Monday
    /// 2025-12-29 and its first three cells are outside the year.
    func testTheFirstColumnOfAYearIsThePartialWeekItStartsIn() throws {
        let heatmap = try heatmap(from: "2026-01-01", through: "2026-12-31")
        let first = try XCTUnwrap(heatmap.columns.first)

        XCTAssertEqual(first.weekStart, try day("2025-12-29"))
        XCTAssertEqual(first.days.count, 7)
        XCTAssertNil(first.days[0]) // Mon 29 Dec — outside the year
        XCTAssertNil(first.days[1])
        XCTAssertNil(first.days[2])
        XCTAssertEqual(first.days[3]?.date, try day("2026-01-01")) // Thu
        XCTAssertEqual(first.days[6]?.date, try day("2026-01-04")) // Sun
    }

    /// 2026 ends on a Thursday, so the final column trails off after it. Those trailing
    /// nils are days the year does not contain, and drawing them would extend it.
    func testTheFinalColumnOfAYearTrailsOffAfterItsLastDay() throws {
        let heatmap = try heatmap(from: "2026-01-01", through: "2026-12-31")
        let last = try XCTUnwrap(heatmap.columns.last)

        XCTAssertEqual(last.weekStart, try day("2026-12-28"))
        XCTAssertEqual(last.days[3]?.date, try day("2026-12-31")) // Thu
        XCTAssertNil(last.days[4])
        XCTAssertNil(last.days[5])
        XCTAssertNil(last.days[6])
    }

    /// Every column is exactly seven slots, every non-nil day sits in its own ISO
    /// weekday row, and every day of the year appears exactly once. That triple is what
    /// makes the transposed layout trustworthy — a day in the wrong row would read as a
    /// pattern the athlete does not have.
    func testEveryDayOfAYearAppearsExactlyOnceInItsOwnWeekdayRow() throws {
        let heatmap = try heatmap(from: "2026-01-01", through: "2026-12-31")

        var seen: Set<CalendarDay> = []
        for column in heatmap.columns {
            XCTAssertEqual(column.days.count, 7, "\(column.weekStart)")
            for (row, day) in column.days.enumerated() {
                guard let day else { continue }
                XCTAssertEqual(day.date.weekday.rawValue, row + 1, "\(day.date)")
                XCTAssertEqual(try column.weekStart.adding(days: row), day.date)
                XCTAssertTrue(seen.insert(day.date).inserted, "duplicate \(day.date)")
            }
        }
        XCTAssertEqual(seen.count, 365)
    }

    /// A leap year is one day and (here) one column longer. 2024 opens on a Monday, so
    /// its first column is complete — the case a layout built around "years start
    /// mid-week" would get wrong.
    func testALeapYearCoversAllThreeHundredAndSixtySixDays() throws {
        let heatmap = try heatmap(from: "2024-01-01", through: "2024-12-31")

        let placed = heatmap.columns.flatMap { $0.days }.compactMap { $0 }
        XCTAssertEqual(placed.count, 366)
        XCTAssertEqual(heatmap.columns.first?.weekStart, try day("2024-01-01")) // a Monday
        XCTAssertNotNil(heatmap.columns.first?.days[0])
        XCTAssertTrue(placed.contains { $0.date == (try? day("2024-02-29")) })
    }

    /// 52 or 53 columns, never more — the number the view's width budget is sized
    /// against.
    func testAYearIsFiftyTwoOrFiftyThreeColumns() throws {
        for year in 2020...2030 {
            let interval = try YearInterval(year: year)
            let heatmap = try heatmap(from: interval.start.description, through: interval.end.description)
            XCTAssertTrue(
                (52...53).contains(heatmap.columns.count),
                "\(year) produced \(heatmap.columns.count) columns"
            )
        }
    }

    // MARK: - Month ticks

    /// A column belongs to the month containing its Thursday — ISO-8601's own
    /// majority-day rule, the one `CalendarDay.civilCalendar` is already pinned to.
    func testAColumnIsLabelledWithTheMonthOfItsThursday() throws {
        let heatmap = try heatmap(from: "2026-01-01", through: "2026-12-31")

        // Week Mon 2025-12-29 – Sun 2026-01-04: Thursday is 2026-01-01, so January.
        XCTAssertEqual(heatmap.columns.first?.monthStart, try day("2026-01-01"))

        // Week Mon 2026-01-26 – Sun 2026-02-01 straddles the boundary; its Thursday is
        // 2026-01-29, so it stays January and February's tick waits for the next column.
        let straddling = try XCTUnwrap(heatmap.columns.first { $0.weekStart == (try? day("2026-01-26")) })
        XCTAssertNil(straddling.monthStart)
        let february = try XCTUnwrap(heatmap.columns.first { $0.weekStart == (try? day("2026-02-02")) })
        XCTAssertEqual(february.monthStart, try day("2026-02-01"))
    }

    /// Exactly twelve ticks across a year, ascending, one per month — never a repeat and
    /// never a gap, which is what a rule based on "does this column contain the 1st"
    /// would produce at either end.
    func testAYearCarriesExactlyTwelveAscendingMonthTicks() throws {
        for year in [2024, 2026] {
            let interval = try YearInterval(year: year)
            let heatmap = try heatmap(from: interval.start.description, through: interval.end.description)
            let ticks = heatmap.columns.compactMap(\.monthStart)

            XCTAssertEqual(ticks.count, 12, "\(year)")
            XCTAssertEqual(ticks.map(\.month), Array(1...12), "\(year)")
            XCTAssertEqual(ticks.map(\.year), Array(repeating: year, count: 12), "\(year)")
            XCTAssertTrue(ticks.allSatisfy { $0.day == 1 }, "\(year)")
        }
    }

    // MARK: - Degenerate input

    /// A gap in the days would silently misalign a column rather than visibly losing a
    /// cell, so it is rejected rather than tolerated.
    func testNonContiguousDaysAreRejected() throws {
        let gapped = [
            ScoreCalendarDay(date: try day("2026-08-03"), state: .unplanned),
            ScoreCalendarDay(date: try day("2026-08-05"), state: .unplanned),
        ]
        assertThrows(.inconsistent, try ScoreCalendarLayout.resolve(gapped, as: .dayGrid))
        assertThrows(.inconsistent, try ScoreCalendarLayout.resolve(gapped, as: .weekColumnHeatmap))
    }

    func testDescendingDaysAreRejected() throws {
        let descending = [
            ScoreCalendarDay(date: try day("2026-08-04"), state: .unplanned),
            ScoreCalendarDay(date: try day("2026-08-03"), state: .unplanned),
        ]
        assertThrows(.inconsistent, try ScoreCalendarLayout.resolve(descending, as: .dayGrid))
    }

    func testAnEmptyRangeProducesAnEmptyLayoutRatherThanThrowing() throws {
        guard case .dayGrid(let grid) = try ScoreCalendarLayout.resolve([], as: .dayGrid) else {
            return XCTFail("expected a day grid")
        }
        XCTAssertEqual(grid.leadingBlankCount, 0)
        XCTAssertTrue(grid.days.isEmpty)

        guard case .weekColumns(let heatmap) = try ScoreCalendarLayout.resolve([], as: .weekColumnHeatmap) else {
            return XCTFail("expected a heatmap")
        }
        XCTAssertTrue(heatmap.columns.isEmpty)
    }

    // MARK: - The one non-hue channel the heatmap keeps

    /// `.missed` and `.scored(.ineffective, _)` share a fill by design (D9), so the
    /// hollow/filled distinction is the only thing separating "I didn't run" from "I ran
    /// badly" at heatmap density.
    ///
    /// **Three states are hollow since MAX-159**, not one: the mixed day and the day that
    /// missed its ask and trained at something unjudged both join the miss here, because at
    /// ~6pt there is no glyph to separate them and "an obligation went unmet" is true of
    /// all three. They are indistinguishable at this density on purpose — see the
    /// accessor's own note — and the month grid and the spoken sentence are where the
    /// difference lives.
    func testOnlyAnUnmetObligationIsDrawnHollow() throws {
        XCTAssertTrue(ScoreCalendarDayState.missed(scheduledKind: .easy).isDrawnHollowAtHeatmapDensity)
        XCTAssertTrue(
            ScoreCalendarDayState.partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ).isDrawnHollowAtHeatmapDensity
        )
        XCTAssertTrue(
            ScoreCalendarDayState.missedWithUnjudgedSession(
                scheduledKind: .easy, recorded: .traditionalStrengthTraining
            ).isDrawnHollowAtHeatmapDensity,
            "a settled miss is hollow whether or not the athlete trained at something else that day"
        )

        let notHollow: [ScoreCalendarDayState] = [
            .scored(band: .ineffective, activityType: .running),
            .scored(band: .marginal, activityType: .running),
            .scored(band: .effective, activityType: .running),
            .awaitingScore(activityType: .running),
            // MAX-126: a lift is a day the athlete trained. Hollow means "asked and not
            // delivered" at this density, which is the one thing it must never read as.
            .noVerdict(activityType: .traditionalStrengthTraining),
            .convertedRest(scheduledKind: .easy),
            .scheduledRest,
            .unplanned,
        ]
        for state in notHollow {
            XCTAssertFalse(state.isDrawnHollowAtHeatmapDensity, "\(state)")
        }
    }

    // MARK: - MAX-105: the plan layer, per density

    /// The requirement the device report made non-negotiable, asserted at the density
    /// where it is easiest to get wrong: hollow means "asked and not delivered" in the
    /// year heatmap, and a day that has not arrived must never draw that way.
    func testAForthcomingDayIsNeverDrawnHollowAtHeatmapDensity() {
        XCTAssertFalse(
            ScoreCalendarDayState.forthcoming(scheduledKind: .easy).isDrawnHollowAtHeatmapDensity
        )
    }

    /// The day grid's counterpart channel: only a forthcoming day is unfilled. It is
    /// what keeps it from reading as `.awaitingScore`, which sits on the same neutral
    /// fill and carries a session glyph too.
    func testOnlyAForthcomingDayIsDrawnUnfilledInTheDayGrid() {
        XCTAssertTrue(
            ScoreCalendarDayState.forthcoming(scheduledKind: .long).isDrawnUnfilledInTheDayGrid
        )

        let filled: [ScoreCalendarDayState] = [
            .scored(band: .ineffective, activityType: .running),
            .scored(band: .marginal, activityType: .running),
            .scored(band: .effective, activityType: .running),
            .awaitingScore(activityType: .running),
            .noVerdict(activityType: .traditionalStrengthTraining),
            .missed(scheduledKind: .easy),
            // MAX-135: half a day's asks were met, so there is something to fill it with.
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ),
            // MAX-159: unfilled means "not yet due", and this day has been and gone.
            .missedWithUnjudgedSession(scheduledKind: .easy, recorded: .traditionalStrengthTraining),
            .convertedRest(scheduledKind: .easy),
            .scheduledRest,
            .unplanned,
        ]
        for state in filled {
            XCTAssertFalse(state.isDrawnUnfilledInTheDayGrid, "\(state)")
        }
    }

    /// The plan ring is a day-grid device only. See
    /// `ScoreCalendarRepresentation.drawsThePlanLayer` for why the year heatmap does
    /// without it rather than shrinking the channel MAX-087 bought.
    func testThePlanLayerIsDrawnInTheDayGridAndNotInTheYearHeatmap() {
        XCTAssertTrue(ScoreCalendarRepresentation.dayGrid.drawsThePlanLayer)
        XCTAssertFalse(ScoreCalendarRepresentation.weekColumnHeatmap.drawsThePlanLayer)

        XCTAssertTrue(TrendIntervalKind.week.scoreCalendarRepresentation.drawsThePlanLayer)
        XCTAssertTrue(TrendIntervalKind.month.scoreCalendarRepresentation.drawsThePlanLayer)
        XCTAssertFalse(TrendIntervalKind.year.scoreCalendarRepresentation.drawsThePlanLayer)
    }
}
