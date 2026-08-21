import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-194 — the decision `PlanConversationDoor` makes: which training thread a run's
/// conversation opens, and what its offer says.
///
/// Reasoned against the same fixture `SurroundingWeekTests` uses: `Fixture.plan()`,
/// effective from **Thursday 2026-01-01**, cap 150 bpm. The subject run here is
/// **Tuesday 2026-01-06**, whose Monday-first week is **5–11 Jan 2026**.
final class PlanConversationDoorTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func workout(id: UUID, on dayText: String, activityType: ActivityType = .running) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(8 * 3_600)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 10_000,
            activeEnergyKilocalories: 500,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(3_660)
        )
    }

    private func metrics(workoutID: UUID) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            planVersion: PlanVersion(1)
        )
    }

    private func ledger(workoutID: UUID) throws -> ScoreLedger {
        try ScoreLedger(automatic: try Fixture.score(points: 82, workoutID: workoutID))
    }

    /// `ContextBuilder.surroundingWeek`'s own output — the week a workout thread's fact
    /// sheet actually renders — so every assertion below is against what the system
    /// under test produced, not a hand-reconstructed date.
    private func week(
        subjectID: UUID = UUID(),
        planCalendar: PlanCalendar?,
        today: String = "2026-06-01"
    ) throws -> WorkoutContext.SurroundingWeek {
        let record = try ContextInputs.WorkoutRecord(
            workout: try workout(id: subjectID, on: "2026-01-06"),
            metrics: try metrics(workoutID: subjectID),
            ledger: try ledger(workoutID: subjectID)
        )
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day(today),
            planCalendar: planCalendar,
            restDayBudget: .standard,
            records: [record]
        )
        return try ContextBuilder.surroundingWeek(around: try day("2026-01-06"), from: inputs)
    }

    private func plan() throws -> PlanCalendar {
        try PlanCalendar([Fixture.plan()])
    }

    // MARK: - The target: the run's own week, never a second notion of "which week"

    /// The scope the door opens is built straight from the week the fact sheet already
    /// rendered — asserted against that week's own `from`/`through`, not against a date
    /// this test typed independently.
    func testOfferTargetsTheRunsOwnWeekBounds() throws {
        let week = try week(planCalendar: try plan())
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running))

        XCTAssertEqual(offer.scope.from, week.from)
        XCTAssertEqual(offer.scope.through, week.through)
    }

    /// Restated as dates, so a future change to `SurroundingWeek`'s own Monday
    /// resolution is caught here too rather than only by `SurroundingWeekTests`.
    func testOfferTargetsMondayFifthThroughSundayEleventh() throws {
        let week = try week(planCalendar: try plan())
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running))

        XCTAssertEqual(offer.scope.from, try day("2026-01-05"))
        XCTAssertEqual(offer.scope.through, try day("2026-01-11"))
    }

    // MARK: - Copy: worded to the plan's presence, never hidden

    /// A plan governs the fixture week (effective from 1 Jan) — the ordinary case.
    func testButtonLabelWhenAPlanGovernsTheWeek() throws {
        let week = try week(planCalendar: try plan())
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running))

        XCTAssertNotNil(week.plan, "the fixture plan is effective from before this week")
        XCTAssertEqual(offer.buttonLabel, "Ask about the plan")
        XCTAssertFalse(offer.accessibilityHint.contains("No plan"))
    }

    /// No plan has ever been authored — the door is still offered (§3.5's "always
    /// offered"), worded to say so rather than hidden or worded identically to the
    /// governed case.
    func testButtonLabelWhenNoPlanGovernsTheWeek() throws {
        let week = try week(planCalendar: nil)
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running))

        XCTAssertNil(week.plan)
        XCTAssertEqual(offer.buttonLabel, "Ask about starting a plan")
        XCTAssertTrue(offer.accessibilityHint.contains("No plan has been authored yet"))
    }

    /// The VoiceOver hint names the destination — CLAUDE.md's "a VoiceOver label naming
    /// what it opens" — using the same window label `TrainingScope` itself renders.
    func testAccessibilityHintNamesTheWeekItOpens() throws {
        let week = try week(planCalendar: try plan())
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running))

        let scope = try TrainingScope(from: week.from, through: week.through)
        XCTAssertTrue(offer.accessibilityHint.contains(scope.label), offer.accessibilityHint)
    }

    // MARK: - Continuity: one honest line, naming the run it came from

    /// The continuity note names the same run the same way the workout thread's own
    /// title already does — one vocabulary for "which run", reused rather than a second
    /// one invented for this note.
    func testContinuityNoteNamesTheRunTheSameWayItsOwnThreadTitleDoes() throws {
        let week = try week(planCalendar: try plan())
        let day = try day("2026-01-06")
        let offer = try XCTUnwrap(PlanConversationDoor.offer(for: week, day: day, activityType: .running))

        let expectedRunDescription = ChatThreadTitle.workout(WorkoutThreadFacts(day: day, activityType: .running))
        XCTAssertEqual(offer.continuityNote, "Continued from \(expectedRunDescription).")
    }

    /// A different activity type changes the note — nothing here is hard-coded to
    /// "Running".
    func testContinuityNoteNamesTheActualActivityType() throws {
        let week = try week(planCalendar: try plan())
        let day = try day("2026-01-06")
        let offer = try XCTUnwrap(
            PlanConversationDoor.offer(for: week, day: day, activityType: .traditionalStrengthTraining)
        )

        XCTAssertTrue(offer.continuityNote.contains("Strength training"), offer.continuityNote)
    }

    /// The note is short, one line, and does not restate anything measured about the
    /// run — no distance, no pace, no heart rate. It names the run; it does not
    /// summarise it.
    func testContinuityNoteCarriesNoMeasuredFigures() throws {
        let week = try week(planCalendar: try plan())
        let offer = try XCTUnwrap(
            PlanConversationDoor.offer(for: week, day: try day("2026-01-06"), activityType: .running)
        )

        XCTAssertFalse(offer.continuityNote.contains("\n"))
        for token in ["km", "bpm", "%", "pace"] {
            XCTAssertFalse(
                offer.continuityNote.lowercased().contains(token.lowercased()),
                "\(offer.continuityNote) unexpectedly names a measured figure"
            )
        }
    }
}
