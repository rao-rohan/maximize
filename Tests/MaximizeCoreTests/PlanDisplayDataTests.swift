import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-102: the read-only plan screen's prepared value.
///
/// The fixture calendar has two versions:
/// - **v1**, effective **2026-01-05** (a Monday), superseded by v2.
/// - **v2**, effective **2026-06-01** (also a Monday), the current version.
///
/// `today` is **2026-08-05**, 65 days after v2's `effectiveFrom` — chosen so the
/// arc-week arithmetic below is checkable by hand: 65 elapsed days / 7 + 1 = week 10.
final class PlanDisplayDataTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private var today: CalendarDay {
        get throws { try day("2026-08-05") }
    }

    private func plan(
        version: Int,
        effectiveFrom: String,
        lift: [Weekday: ScheduledSession] = [:]
    ) throws -> Plan {
        try Plan(
            version: PlanVersion(version),
            effectiveFrom: day(effectiveFrom),
            weeklyTemplate: Fixture.weeklyTemplate(lift: lift),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(statements: ["Half marathon"], targetDay: try day("2026-11-15"))
        )
    }

    private func twoVersionCalendar() throws -> PlanCalendar {
        try PlanCalendar([
            plan(version: 1, effectiveFrom: "2026-01-05"),
            plan(version: 2, effectiveFrom: "2026-06-01"),
        ])
    }

    // MARK: - No plan authored

    func testNilCalendarProducesNotAuthored() throws {
        let display = try PlanDisplayData.build(from: nil, today: try today)
        XCTAssertEqual(display, .notAuthored)
    }

    // MARK: - Version labelling and current-vs-historical

    func testDefaultViewingIsTheHighestStoredVersion() throws {
        let display = try PlanDisplayData.build(from: try twoVersionCalendar(), today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.viewing.version, try PlanVersion(2))
        XCTAssertTrue(authored.viewing.isCurrent)
        XCTAssertNil(authored.viewing.effectiveThrough, "the current version has no successor yet")
    }

    func testExplicitlyViewingAnEarlierVersionShowsItAsHistorical() throws {
        let display = try PlanDisplayData.build(
            from: try twoVersionCalendar(),
            viewing: try PlanVersion(1),
            today: try today
        )
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.viewing.version, try PlanVersion(1))
        XCTAssertFalse(authored.viewing.isCurrent)
        XCTAssertEqual(
            authored.viewing.effectiveThrough, try day("2026-05-31"),
            "governed through the day before v2 took effect"
        )
    }

    func testViewingAVersionNotInTheCalendarThrows() throws {
        XCTAssertThrowsError(
            try PlanDisplayData.build(
                from: try twoVersionCalendar(),
                viewing: try PlanVersion(99),
                today: try today
            )
        )
    }

    func testHistoryListsEveryVersionNewestFirstWithCurrentAndViewingFlagged() throws {
        let display = try PlanDisplayData.build(from: try twoVersionCalendar(), today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.history.map(\.version), [try PlanVersion(2), try PlanVersion(1)])

        let current = authored.history[0]
        XCTAssertTrue(current.isCurrent)
        XCTAssertTrue(current.isViewing, "the default view is the current version")
        XCTAssertNil(current.effectiveThrough)

        let superseded = authored.history[1]
        XCTAssertFalse(superseded.isCurrent)
        XCTAssertFalse(superseded.isViewing)
        XCTAssertEqual(superseded.effectiveThrough, try day("2026-05-31"))
    }

    func testHistoryMarksTheHistoricalVersionAsViewingWhenThatIsWhatIsShown() throws {
        let display = try PlanDisplayData.build(
            from: try twoVersionCalendar(),
            viewing: try PlanVersion(1),
            today: try today
        )
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        let v1 = try PlanVersion(1)
        let v2 = try PlanVersion(2)
        XCTAssertTrue(authored.history.first { $0.version == v1 }?.isViewing ?? false)
        XCTAssertFalse(authored.history.first { $0.version == v2 }?.isViewing ?? true)
    }

    // MARK: - The arc's current week

    func testCurrentArcWeekIsMarkedOnTheCurrentVersion() throws {
        let display = try PlanDisplayData.build(from: try twoVersionCalendar(), today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        // 2026-08-05 is 65 days after 2026-06-01 (v2's effectiveFrom, a Monday):
        // 65 / 7 + 1 = week 10, past the fixture's three-week arc — so no row is
        // marked, but the index is still resolved (nothing in the arc *contradicts*
        // week 10, it simply has no entry).
        XCTAssertEqual(authored.viewing.currentArcWeekIndex, 10)
        XCTAssertTrue(authored.viewing.arc.allSatisfy { !$0.isCurrentWeek })
    }

    func testCurrentArcWeekLandsInsideTheArcWhenTodayIsEarlier() throws {
        // A week 2 day: 2026-06-08 is 7 days after 2026-06-01.
        let display = try PlanDisplayData.build(
            from: try twoVersionCalendar(),
            today: try day("2026-06-08")
        )
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.viewing.currentArcWeekIndex, 2)
        XCTAssertEqual(authored.viewing.arc.filter(\.isCurrentWeek).map(\.index), [2])
    }

    /// D1: a historical version is shown as-is, and that specifically means it never
    /// claims to have a "current" week — it is not governing any day right now.
    func testHistoricalVersionHasNoCurrentArcWeekEvenThoughTodayFallsWithinItsOwnArc() throws {
        // 2026-01-19 is week 3 of v1's own arc, and v1 is still the version that would
        // have governed that day — but v1 is not the version governing `today`
        // (2026-08-05), so nothing should be marked current on it.
        let display = try PlanDisplayData.build(
            from: try twoVersionCalendar(),
            viewing: try PlanVersion(1),
            today: try today
        )
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertNil(authored.viewing.currentArcWeekIndex)
        XCTAssertTrue(authored.viewing.arc.allSatisfy { !$0.isCurrentWeek })
    }

    // MARK: - Content carried through as-is

    func testWeekIsSevenRowsMondayFirstMatchingTheStoredTemplate() throws {
        let display = try PlanDisplayData.build(from: try twoVersionCalendar(), today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(
            authored.viewing.week.map(\.weekday),
            [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        )
        XCTAssertEqual(authored.viewing.week.first { $0.weekday == .sunday }?.kind, .long)
        XCTAssertEqual(authored.viewing.week.first { $0.weekday == .sunday }?.distanceMeters, 18_000)
        XCTAssertEqual(authored.viewing.week.first { $0.weekday == .monday }?.kind, .rest)
    }

    func testGoalsAndThresholdsAndCapCarryThroughUnchanged() throws {
        let display = try PlanDisplayData.build(from: try twoVersionCalendar(), today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.viewing.goalStatements, ["Half marathon"])
        XCTAssertEqual(authored.viewing.goalTargetDay, try day("2026-11-15"))
        XCTAssertEqual(authored.viewing.heartRateCapBPM, 150)
        XCTAssertEqual(authored.viewing.cadenceTarget.lowStepsPerMinute, 165)
        XCTAssertEqual(authored.viewing.effectiveThreshold, try ScoreValue(70))
        XCTAssertEqual(authored.viewing.marginalThreshold, try ScoreValue(45))
        XCTAssertFalse(authored.viewing.bands.isEmpty)
    }

    /// A single-version calendar has no successor for anything, so both the header and
    /// the lone history row read "current, open-ended."
    func testASingleVersionCalendarHasNoHistoricalRows() throws {
        let calendar = try PlanCalendar([plan(version: 1, effectiveFrom: "2026-01-05")])
        let display = try PlanDisplayData.build(from: calendar, today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        XCTAssertEqual(authored.history.count, 1)
        XCTAssertTrue(authored.history[0].isCurrent)
        XCTAssertNil(authored.viewing.effectiveThrough)
    }

    // MARK: - The lift slot, both slots on one row (MAX-138, A17)

    /// The regression this ticket must not cause: a run-only plan — no lift
    /// prescribed anywhere, which is every plan authored before MAX-129 and every
    /// plan an athlete simply never asked to lift in — carries `liftSession.isRest`
    /// on every one of the seven rows, and `obligationSummary` never reports
    /// `.liftOnly` or `.both`. `PlanFormatting.weekdayLines` reads exactly this fact
    /// to omit the lift line entirely, which is what makes the screen read
    /// byte-for-byte as it did before this ticket.
    func testRunOnlyPlanCarriesRestOnEveryLiftSlot() throws {
        let calendar = try PlanCalendar([plan(version: 1, effectiveFrom: "2026-01-05")])
        let display = try PlanDisplayData.build(from: calendar, today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }

        XCTAssertEqual(authored.viewing.week.count, 7)
        for day in authored.viewing.week {
            XCTAssertTrue(day.liftSession.isRest, "\(day.weekday) should have no lift asked")
            XCTAssertNotEqual(day.obligationSummary, .liftOnly)
            XCTAssertNotEqual(day.obligationSummary, .both)
        }
    }

    /// A day prescribing both a run and a lift carries both slots, and
    /// `obligationSummary` reports `.both` for it — while a weekday untouched by the
    /// lift map stays exactly what it always was.
    func testWeekCarriesBothSlotsAlongsideTheRunSlot() throws {
        let calendar = try PlanCalendar([
            plan(
                version: 1,
                effectiveFrom: "2026-01-05",
                lift: [
                    // Monday is rest on the run side (Fixture.weeklyTemplate) — this
                    // makes it a lift-only day.
                    .monday: try ScheduledSession(kind: .lift, muscleGroups: [.legs]),
                    // Tuesday already prescribes an easy run — this makes it a
                    // both-obligation day.
                    .tuesday: try ScheduledSession(kind: .lift, muscleGroups: [.chest, .shoulders]),
                ]
            )
        ])
        let display = try PlanDisplayData.build(from: calendar, today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        let week = authored.viewing.week

        let monday = try XCTUnwrap(week.first { $0.weekday == .monday })
        XCTAssertEqual(monday.kind, .rest)
        XCTAssertEqual(monday.liftSession.kind, .lift)
        XCTAssertEqual(monday.liftSession.muscleGroups, [.legs])
        XCTAssertEqual(monday.obligationSummary, .liftOnly)

        let tuesday = try XCTUnwrap(week.first { $0.weekday == .tuesday })
        XCTAssertEqual(tuesday.kind, .easy)
        XCTAssertEqual(tuesday.distanceMeters, 8_000)
        XCTAssertEqual(tuesday.liftSession.muscleGroups, [.chest, .shoulders])
        XCTAssertEqual(tuesday.obligationSummary, .both)

        // Untouched by the lift map — reads exactly as a run-only day always has.
        let wednesday = try XCTUnwrap(week.first { $0.weekday == .wednesday })
        XCTAssertTrue(wednesday.liftSession.isRest)
        XCTAssertEqual(wednesday.obligationSummary, .runOnly)

        let friday = try XCTUnwrap(week.first { $0.weekday == .friday })
        XCTAssertEqual(friday.kind, .rest)
        XCTAssertTrue(friday.liftSession.isRest)
        XCTAssertEqual(friday.obligationSummary, .rest)
    }

    /// The lift slot's second empty state: a lift is asked for, but the plan has not
    /// said which muscle groups — a real, distinct fact from "no lift asked"
    /// (`LiftPrescriptionSummary.unstatedGroups`), reachable straight off the carried
    /// `liftSession` without this type re-deriving it.
    func testLiftSlotWithNoStatedGroupsReadsAsUnstatedRatherThanRest() throws {
        let calendar = try PlanCalendar([
            plan(
                version: 1,
                effectiveFrom: "2026-01-05",
                lift: [.wednesday: try ScheduledSession(kind: .lift)]
            )
        ])
        let display = try PlanDisplayData.build(from: calendar, today: try today)
        guard case let .authored(authored) = display else {
            return XCTFail("expected .authored")
        }
        let wednesday = try XCTUnwrap(authored.viewing.week.first { $0.weekday == .wednesday })

        XCTAssertEqual(wednesday.liftSession.liftPrescriptionSummary, .unstatedGroups)
        XCTAssertEqual(wednesday.obligationSummary, .both, "Wednesday already prescribes a hard run")
    }
}
