import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-137: the authoring screen can prescribe both slots. What CI can prove is the
/// decisions this ticket puts in `MaximizeCore` — what the lift picker offers, how a
/// weekday's two asks summarise, and what the lift slot's two empty states read as —
/// plus the round trip through `PlanAuthoringSession` that a device can't be trusted to
/// exercise on its own.
final class PlanAuthoringLiftSlotTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private var today: CalendarDay {
        get throws { try day("2026-08-05") }
    }

    // MARK: - The lift slot's own vocabulary

    /// The lift picker offers a smaller, different vocabulary than the run picker —
    /// not `prescribable` with one case swapped, but exactly "prescribed or not".
    func testLiftPrescribableIsRestAndLiftOnly() {
        XCTAssertEqual(ScheduledSessionKind.liftPrescribable, [.rest, .lift])
        XCTAssertFalse(ScheduledSessionKind.liftPrescribable.contains(.easy))
        XCTAssertFalse(ScheduledSessionKind.liftPrescribable.contains(.long))
        XCTAssertFalse(ScheduledSessionKind.liftPrescribable.contains(.hard))
        XCTAssertFalse(ScheduledSessionKind.liftPrescribable.contains(.other))
    }

    /// `prescribable` (the run picker's vocabulary) still excludes `.lift`, unchanged
    /// by this ticket — a lift must never be reachable from the run slot's picker.
    func testPrescribableStillExcludesLift() {
        XCTAssertFalse(ScheduledSessionKind.prescribable.contains(.lift))
        XCTAssertEqual(ScheduledSessionKind.prescribable.count, ScheduledSessionKind.allCases.count - 1)
    }

    // MARK: - LiftPrescriptionSummary: the two empty states, kept distinct

    func testLiftPrescriptionSummaryDistinguishesRestFromUnstatedGroups() {
        let rest = LiftPrescriptionSummary(kind: .rest, muscleGroups: [])
        let unstated = LiftPrescriptionSummary(kind: .lift, muscleGroups: [])
        let stated = LiftPrescriptionSummary(kind: .lift, muscleGroups: [.chest, .back])

        XCTAssertEqual(rest, .rest)
        XCTAssertEqual(unstated, .unstatedGroups)
        XCTAssertEqual(stated, .groups([.chest, .back]))

        // The whole point: none of these three collapse into another.
        XCTAssertNotEqual(rest, unstated)
        XCTAssertNotEqual(unstated, stated)
        XCTAssertNotEqual(rest, stated)
    }

    /// A non-lift kind reads as rest regardless of what `muscleGroups` happens to
    /// carry — matching `ScheduledSession`'s own rule that only a lift may name groups.
    func testLiftPrescriptionSummaryIgnoresGroupsOnANonLiftKind() {
        XCTAssertEqual(LiftPrescriptionSummary(kind: .easy, muscleGroups: []), .rest)
        XCTAssertEqual(LiftPrescriptionSummary(kind: .rest, muscleGroups: []), .rest)
    }

    func testScheduledSessionExposesTheSameSummary() throws {
        XCTAssertEqual(ScheduledSession.rest.liftPrescriptionSummary, .rest)
        XCTAssertEqual(
            try ScheduledSession(kind: .lift).liftPrescriptionSummary,
            .unstatedGroups
        )
        XCTAssertEqual(
            try ScheduledSession(kind: .lift, muscleGroups: [.legs]).liftPrescriptionSummary,
            .groups([.legs])
        )
    }

    // MARK: - PlanDraft.DayDraft: editing the lift slot

    private func seededDraft() throws -> PlanDraft {
        try PlanAuthoring.session(revising: nil, today: try today).draft
    }

    func testANewDraftPrescribesNoLiftingAnywhere() throws {
        let draft = try seededDraft()
        for day in draft.week {
            XCTAssertEqual(day.liftKind, .rest)
            XCTAssertTrue(day.liftMuscleGroups.isEmpty)
            XCTAssertEqual(day.liftSummary, .rest)
            XCTAssertNotEqual(day.obligationSummary, .liftOnly)
            XCTAssertNotEqual(day.obligationSummary, .both)
        }
    }

    func testSettingLiftKindToLiftLeavesGroupsUnstatedUntilNamed() throws {
        var draft = try seededDraft()
        draft.setLiftKind(.lift, on: .tuesday)

        XCTAssertEqual(draft[.tuesday].liftKind, .lift)
        XCTAssertEqual(draft[.tuesday].liftSummary, .unstatedGroups)

        draft.toggleLiftMuscleGroup(.chest, on: .tuesday)
        draft.toggleLiftMuscleGroup(.back, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].liftMuscleGroups, [.chest, .back])
        XCTAssertEqual(draft[.tuesday].liftSummary, .groups([.chest, .back]))

        draft.toggleLiftMuscleGroup(.chest, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].liftMuscleGroups, [.back])
    }

    /// Choosing rest on the lift slot clears any groups already named — the same
    /// "always convertible" rule `setKind(.rest)` enforces on the run slot.
    func testChoosingRestOnTheLiftSlotClearsItsGroups() throws {
        var draft = try seededDraft()
        draft.setLiftKind(.lift, on: .tuesday)
        draft.setLiftMuscleGroups([.chest, .shoulders], on: .tuesday)
        XCTAssertFalse(draft[.tuesday].liftMuscleGroups.isEmpty)

        draft.setLiftKind(.rest, on: .tuesday)
        XCTAssertTrue(draft[.tuesday].liftMuscleGroups.isEmpty)
        XCTAssertEqual(draft[.tuesday].liftSummary, .rest)

        // And groups set afterwards are ignored, matching `setDistanceMeters`'s own
        // "parked, not silently accepted" behaviour on a rest day.
        draft.toggleLiftMuscleGroup(.legs, on: .tuesday)
        XCTAssertTrue(draft[.tuesday].liftMuscleGroups.isEmpty)
    }

    func testLiftSessionBuildsTheAskTheDraftDescribes() throws {
        var draft = try seededDraft()
        draft.setLiftKind(.lift, on: .friday)
        draft.setLiftMuscleGroups([.legs, .core], on: .friday)

        let session = try draft[.friday].liftSession()
        XCTAssertEqual(session.kind, .lift)
        XCTAssertEqual(session.muscleGroups, [.legs, .core])
    }

    /// A revision's carried-forward note (not editable on this screen) survives the
    /// round trip through `liftSession()` untouched.
    func testCarriedLiftNoteSurvivesTheDraftRoundTrip() throws {
        let stored = try Plan(
            version: PlanVersion(1),
            effectiveFrom: try day("2026-01-01"),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .tuesday: try ScheduledSession(kind: .lift, note: "45 minutes", muscleGroups: [.chest]),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let draft = try PlanDraft(stored)
        let rebuilt = try draft[.tuesday].liftSession()
        XCTAssertEqual(rebuilt, try ScheduledSession(kind: .lift, note: "45 minutes", muscleGroups: [.chest]))
    }

    // MARK: - ObligationSummary: how a weekday's two asks are summarised

    /// `ObligationSummary` is shared with `PlanDisplayData.WeekdayRow` (MAX-138) —
    /// tested here directly off its own initializer, independent of `PlanDraft`, so a
    /// change to the draft's plumbing can never silently stop exercising it.
    func testObligationSummaryInitializerCoversAllFourCombinations() {
        XCTAssertEqual(ObligationSummary(runKind: .rest, liftKind: .rest), .rest)
        XCTAssertEqual(ObligationSummary(runKind: .easy, liftKind: .rest), .runOnly)
        XCTAssertEqual(ObligationSummary(runKind: .rest, liftKind: .lift), .liftOnly)
        XCTAssertEqual(ObligationSummary(runKind: .long, liftKind: .lift), .both)
    }

    func testObligationSummaryCoversAllFourCombinations() throws {
        var draft = try seededDraft()
        // Tuesday is prescribed a run by the seed; force it to rest to control the case.
        draft.setKind(.rest, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].obligationSummary, .rest)

        draft.setKind(.easy, on: .tuesday)
        draft.setDistanceMeters(5_000, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].obligationSummary, .runOnly)

        draft.setLiftKind(.lift, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].obligationSummary, .both)

        draft.setKind(.rest, on: .tuesday)
        XCTAssertEqual(draft[.tuesday].obligationSummary, .liftOnly)
    }

    // MARK: - The whole round trip through PlanAuthoringSession

    /// Both slots, authored end to end: the draft's edits reach the saved `Plan`.
    func testAuthoringBothSlotsProducesAPlanCarryingBoth() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.setLiftKind(.lift, on: .tuesday)
        draft.setLiftMuscleGroups([.chest, .shoulders], on: .tuesday)
        draft.setLiftKind(.lift, on: .friday)
        draft.setLiftMuscleGroups([.legs, .core], on: .friday)

        let plan = try session.plan(from: draft, effectiveFrom: try day("2026-08-03"))

        XCTAssertEqual(plan.weeklyTemplate.session(on: .tuesday, for: .lift).kind, .lift)
        XCTAssertEqual(
            plan.weeklyTemplate.session(on: .tuesday, for: .lift).muscleGroups,
            [.chest, .shoulders]
        )
        XCTAssertEqual(
            plan.weeklyTemplate.session(on: .friday, for: .lift).muscleGroups,
            [.legs, .core]
        )
        // Every other weekday's lift slot is still rest — this ticket did not touch
        // the days the athlete never asked to prescribe.
        XCTAssertEqual(plan.weeklyTemplate.scheduledLiftCount, 2)

        // The run half is completely unaffected by the lift edits.
        XCTAssertEqual(plan.weeklyTemplate.session(on: .tuesday, for: .run).kind, .easy)
    }

    /// The regression this ticket must not cause: a run-only plan — no lift edits at
    /// all — authors exactly as it did before this ticket. Every lift slot is rest,
    /// and the saved plan is identical to what the unmodified seed would have produced.
    func testARunOnlyPlanAuthorsExactlyAsBefore() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        let plan = try session.plan(from: session.draft, effectiveFrom: try day("2026-08-03"))

        XCTAssertEqual(plan.weeklyTemplate.scheduledLiftCount, 0)
        for weekday in Weekday.allCases {
            XCTAssertTrue(plan.weeklyTemplate.session(on: weekday, for: .lift).isRest)
        }
    }

    /// A revision that never touches the lift slot still carries forward whatever the
    /// stored plan already prescribed — the draft's lift fields are decomposed for
    /// editing now, but decomposition must not mean "silently reset."
    func testARevisionThatDoesNotTouchTheLiftSlotCarriesItForwardUnchanged() throws {
        let stored = try Plan(
            version: PlanVersion(1),
            effectiveFrom: try day("2026-01-01"),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .tuesday: try ScheduledSession(kind: .lift, muscleGroups: [.chest, .back]),
                .friday: try ScheduledSession(kind: .lift, muscleGroups: [.legs]),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let session = try PlanAuthoring.session(revising: try PlanCalendar([stored]), today: try today)
        var draft = session.draft
        draft.heartRateCapBPM = 148 // an unrelated edit

        let revised = try session.plan(from: draft, effectiveFrom: try day("2026-08-06"))
        XCTAssertEqual(revised.weeklyTemplate, stored.weeklyTemplate)
    }

    func testGovernedDaysCarryTheLiftAskAlongsideTheRunAsk() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.setLiftKind(.lift, on: .tuesday)
        draft.setLiftMuscleGroups([.chest], on: .tuesday)

        let start = try day("2026-08-03") // Monday
        let tuesdayDate = try day("2026-08-04")
        let days = try session.governedDays(from: draft, effectiveFrom: start)
        guard let tuesday = days.first(where: { $0.date == tuesdayDate }) else {
            return XCTFail("expected a Tuesday in the governed week")
        }
        XCTAssertEqual(tuesday.scheduledSession(for: .lift).muscleGroups, [.chest])
        XCTAssertEqual(tuesday.scheduledSession(for: .run).kind, .easy)
    }
}
