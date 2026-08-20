import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-181 — the fact sheet renders the lift slot.
///
/// `TrainingFactSheet`'s plan block iterated `plan.weeklyTemplate.entries` and rendered
/// only `entry.session`, the run slot, leaving `entry.liftSession` unrendered since
/// MAX-129 gave the template a second slot. A training thread's model was told the
/// week's run prescription and silently not its lift one — MAX-174 §5.3's G2, filed
/// against MAX-136 in `PROJECT_TRACKER.md`, and a live instance of the exact failure
/// MAX-175's absence rule forbids.
///
/// Every assertion here pins a *whole rendered line*, not a substring of one, because a
/// defect that only ever gets checked with a loose `.contains` on part of a line is
/// exactly the shape of defect that let the lift slot go unrendered for as long as it
/// did — `TrainingContextAgreementTests` already covers this file's other sections and
/// never once asserted on the plan block's weekday lines.
final class TrainingFactSheetPlanBlockTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// One window, one plan, no recorded sessions — the plan block does not need any to
    /// render, and keeping the fixture minimal is what keeps these tests about the
    /// weekly template alone.
    private func context(plan: Plan) throws -> TrainingContext {
        let scope = try TrainingScope(from: try day("2026-01-05"), through: try day("2026-01-11"))
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day("2026-06-01"),
            planCalendar: try PlanCalendar([plan]),
            restDayBudget: .standard,
            records: []
        )
        switch try ContextBuilder.build(for: .training(scope), from: inputs) {
        case let .training(context): return context
        case .workout: throw DomainError.inconsistent(reason: "expected a training context")
        }
    }

    /// The convention sentence that makes a day's missing "Lift:" clause a stated fact
    /// rather than an unlabelled gap — pinned once here, reused by every test below.
    private static let convention = "Weekly template, Monday first. A day names a lift ask "
        + "(tagged \"Lift:\") only when the plan prescribes one — a day with no lift clause "
        + "prescribes no lifting that day."

    // MARK: - A week with no lift at all

    /// Every lift slot at rest — `Fixture.plan()`'s default, and what every plan on disk
    /// prescribed before MAX-129. No weekday line may carry "Lift:", and the convention
    /// sentence is what lets the model read that as "this plan asks no lifting" rather
    /// than as a renderer that dropped something.
    func testAWeekWithNoLiftRendersNoLiftClauseOnAnyDay() throws {
        let sheet = try context(plan: try Fixture.plan()).factSheet()

        XCTAssertTrue(sheet.contains(Self.convention), sheet)
        XCTAssertTrue(sheet.contains("Monday: rest\n"), sheet)
        XCTAssertTrue(sheet.contains("Tuesday: easy, 8.0 km\n"), sheet)
        XCTAssertTrue(sheet.contains("Wednesday: hard, (6 × 800m)\n"), sheet)
        XCTAssertTrue(sheet.contains("Thursday: easy, 8.0 km\n"), sheet)
        XCTAssertTrue(sheet.contains("Friday: rest\n"), sheet)
        XCTAssertTrue(sheet.contains("Saturday: easy, 6.0 km\n"), sheet)
        XCTAssertTrue(sheet.contains("Sunday: long, 18.0 km\n"), sheet)
        // Scoped to the weekday lines, not the whole sheet: the convention sentence names
        // the tag in prose, so "Lift:" legitimately appears above them. The invariant is
        // that no *day* claims a lift ask, which is the only place a stray clause would
        // mislead the model.
        let weekdays = [
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        ]
        let weekdayLines = sheet.split(separator: "\n").filter { line in
            weekdays.contains { line.hasPrefix("\($0): ") }
        }
        XCTAssertEqual(weekdayLines.count, 7, sheet)
        XCTAssertFalse(weekdayLines.contains { $0.contains("Lift:") }, sheet)
    }

    // MARK: - A week with lifts on some days

    /// Tuesday gets a full lift ask (duration and muscle groups), Thursday a bare one
    /// (kind only) — every other day renders exactly as the no-lift test above, proving
    /// the omission is per-weekday and not a whole-plan branch.
    func testAWeekWithLiftsOnSomeDaysNamesOnlyThoseDays() throws {
        let plan = try Fixture.plan(lift: [
            .tuesday: try ScheduledSession(
                kind: .lift,
                durationSeconds: 2_700,
                muscleGroups: [.chest, .shoulders]
            ),
            .thursday: try ScheduledSession(kind: .lift),
        ])
        let sheet = try context(plan: plan).factSheet()

        XCTAssertTrue(sheet.contains(Self.convention), sheet)
        XCTAssertTrue(sheet.contains("Monday: rest\n"), sheet)
        XCTAssertTrue(
            sheet.contains(
                "Tuesday: easy, 8.0 km · Lift: lift, 45m 0s, muscle groups: chest, shoulders\n"
            ),
            sheet
        )
        XCTAssertTrue(sheet.contains("Wednesday: hard, (6 × 800m)\n"), sheet)
        XCTAssertTrue(sheet.contains("Thursday: easy, 8.0 km · Lift: lift\n"), sheet)
        XCTAssertTrue(sheet.contains("Friday: rest\n"), sheet)
        XCTAssertTrue(sheet.contains("Saturday: easy, 6.0 km\n"), sheet)
        XCTAssertTrue(sheet.contains("Sunday: long, 18.0 km\n"), sheet)
        // Neither of the days above the fixture leaves at rest gained a "Lift:" clause.
        XCTAssertFalse(sheet.contains("Friday: rest · Lift:"), sheet)
        XCTAssertFalse(sheet.contains("Saturday: easy, 6.0 km · Lift:"), sheet)
        XCTAssertFalse(sheet.contains("Sunday: long, 18.0 km · Lift:"), sheet)
    }

    // MARK: - A weekday prescribing both slots

    /// Sunday's run ask (long, 18 km) and lift ask — duration, muscle groups, and a note,
    /// every field `FactSheetFormatting.liftPrescription` renders — sit on one line
    /// together rather than the screen's two rows, per this file's own documented reason.
    func testAWeekdayPrescribingBothSlotsRendersBothOnOneLine() throws {
        let plan = try Fixture.plan(lift: [
            .sunday: try ScheduledSession(
                kind: .lift,
                durationSeconds: 1_800,
                note: "core work",
                muscleGroups: [.core]
            ),
        ])
        let sheet = try context(plan: plan).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Sunday: long, 18.0 km · Lift: lift, 30m 0s, muscle groups: core (core work)\n"
            ),
            sheet
        )
        // Exactly one line for the day — not a second row repeating "Sunday".
        XCTAssertEqual(sheet.components(separatedBy: "Sunday:").count - 1, 1, sheet)
    }
}
