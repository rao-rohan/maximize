import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-103 — the "Runs in this conversation" strip's core-side display data
/// (CHAT-FIRST-SPEC.md §2.2, §6.2).
///
/// Every test here builds a `TrainingContext` the same way `ChatModel` does — through
/// `ContextBuilder.build(for: .training(scope), from:)`, never `TrainingContext`'s own
/// internal initializer — so what is asserted is the same shape `RunsStripData.build(from:)`
/// actually receives in the app.
final class RunsStripDataTests: XCTestCase {

    // MARK: - Fixtures

    private static let today = "2026-06-01"

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func calendar() throws -> PlanCalendar {
        try PlanCalendar([Fixture.plan()])
    }

    private func workout(
        id: UUID,
        on dayText: String,
        activityType: ActivityType = .running
    ) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(8 * 3_600)
        return try Workout(
            id: id,
            activityType: activityType,
            start: start,
            end: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 8_000,
            activeEnergyKilocalories: 500,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(3_660)
        )
    }

    private func record(
        id: UUID,
        on dayText: String,
        activityType: ActivityType = .running,
        points: Int = 80
    ) throws -> ContextInputs.WorkoutRecord {
        try ContextInputs.WorkoutRecord(
            workout: try workout(id: id, on: dayText, activityType: activityType),
            metrics: try DerivedMetrics(
                workoutID: id,
                averageHeartRateBPM: 142,
                maximumHeartRateBPM: 160,
                timeAboveCapSeconds: 250,
                heartRateDriftFraction: 0.032,
                planVersion: PlanVersion(1)
            ),
            ledger: try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: id))
        )
    }

    private func trainingContext(
        from: String,
        through: String,
        records: [ContextInputs.WorkoutRecord],
        today: String = RunsStripDataTests.today
    ) throws -> TrainingContext {
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day(today),
            planCalendar: try calendar(),
            restDayBudget: .standard,
            records: records
        )
        let built = try ContextBuilder.build(
            for: .training(try TrainingScope(from: try day(from), through: try day(through))),
            from: inputs
        )
        guard case let .training(context) = built else {
            throw DomainError.inconsistent(reason: "expected a training context")
        }
        return context
    }

    // MARK: - Labels

    /// "3 Aug 2026 · Running" — the same date form and separator
    /// `ChatThreadTitle.workout` names a run by, so the same run reads identically in its
    /// own thread's title and as a chip here.
    func testLabelNamesTheDayAndTheActivity() throws {
        let id = UUID()
        let context = try trainingContext(
            from: "2026-01-05",
            through: "2026-01-11",
            records: [try record(id: id, on: "2026-01-06", activityType: .running)]
        )

        guard case let .chips(chips, omittedCount) = RunsStripData.build(from: context) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(omittedCount, 0)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].workoutID, id)
        XCTAssertEqual(chips[0].label, "6 Jan 2026 · Running")
    }

    /// A lift reads as a lift, not as an unusually short run — the same fact
    /// `TrainingContext.Session.activityType`'s own documentation says every line must
    /// carry (LIFTING-SPEC §10.2).
    func testLabelNamesALiftByItsOwnActivityType() throws {
        let id = UUID()
        let context = try trainingContext(
            from: "2026-01-05",
            through: "2026-01-11",
            records: [try record(id: id, on: "2026-01-07", activityType: .traditionalStrengthTraining)]
        )

        guard case let .chips(chips, _) = RunsStripData.build(from: context) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(chips[0].label, "7 Jan 2026 · Strength training")
    }

    // MARK: - Ordering

    /// Chips read chronologically regardless of the order records were supplied in — the
    /// same order `TrainingContext.sessions` (and therefore the fact sheet) already holds
    /// them, per `RunsStripData.build(from:)`'s own "never a second, silently different
    /// notion of the order."
    func testChipsAreOrderedChronologicallyRegardlessOfInputOrder() throws {
        let earliest = UUID()
        let middle = UUID()
        let latest = UUID()

        let context = try trainingContext(
            from: "2026-01-05",
            through: "2026-01-11",
            records: [
                try record(id: latest, on: "2026-01-11"),
                try record(id: earliest, on: "2026-01-06"),
                try record(id: middle, on: "2026-01-08"),
            ]
        )

        guard case let .chips(chips, _) = RunsStripData.build(from: context) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(chips.map(\.workoutID), [earliest, middle, latest])
    }

    // MARK: - Absence

    /// A window that genuinely holds nothing — distinct from a cap withholding what is
    /// there (below).
    func testAWindowWithNoSessionsReportsNoSessionsInWindow() throws {
        let context = try trainingContext(from: "2026-01-05", through: "2026-01-11", records: [])

        XCTAssertEqual(RunsStripData.build(from: context), .empty(.noSessionsInWindow))
        XCTAssertEqual(
            RunsStripCopy.text(for: .noSessionsInWindow),
            "No sessions recorded in this window yet."
        )
    }

    /// `TrainingContext.maximumRenderedSessions` biting means the fact sheet itself named
    /// no session by day or activity — the strip must not do what the prompt would not,
    /// so it reports the same withholding rather than listing anything.
    func testAWindowBeyondTrainingContextsOwnCapReportsWithheldByCap() throws {
        let count = TrainingContext.maximumRenderedSessions + 1
        let context = try windowOf(sessionCount: count)

        XCTAssertTrue(context.sessionsWereWithheldByTheCap)
        XCTAssertEqual(
            RunsStripData.build(from: context),
            .empty(.withheldByCap(sessionCount: count))
        )
        XCTAssertEqual(
            RunsStripCopy.text(for: .withheldByCap(sessionCount: count)),
            "This window holds \(count) sessions — too many to list individually."
        )
    }

    // MARK: - The strip's own cap

    /// Exactly the cap: every session is still listed, and nothing is reported omitted —
    /// mirroring `ContextBuilderTests.testExactlyTheCapIsStillListed`'s own boundary case
    /// for `TrainingContext.maximumRenderedSessions`.
    func testExactlyTheStripsCapIsStillListedInFull() throws {
        let context = try windowOf(sessionCount: RunsStripData.maximumChips)

        guard case let .chips(chips, omittedCount) = RunsStripData.build(from: context) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(chips.count, RunsStripData.maximumChips)
        XCTAssertEqual(omittedCount, 0)
    }

    /// One past the strip's own cap: `TrainingContext.maximumRenderedSessions` (200) has
    /// not been reached, so the fact sheet named every one of these sessions — but the
    /// strip still folds the extra one into a count rather than laying out an
    /// unbounded scroll.
    func testBeyondTheStripsOwnCapTheRemainderIsCountedNotListed() throws {
        let count = RunsStripData.maximumChips + 1
        XCTAssertLessThan(count, TrainingContext.maximumRenderedSessions)
        let context = try windowOf(sessionCount: count)
        XCTAssertFalse(context.sessionsWereWithheldByTheCap)

        guard case let .chips(chips, omittedCount) = RunsStripData.build(from: context) else {
            return XCTFail("expected chips")
        }
        XCTAssertEqual(chips.count, RunsStripData.maximumChips)
        XCTAssertEqual(omittedCount, 1)
        XCTAssertEqual(RunsStripCopy.omittedCountLabel(omittedCount), "+1 more")
        XCTAssertEqual(
            RunsStripCopy.omittedCountAccessibilityLabel(omittedCount),
            "1 more session in this conversation, not shown"
        )
    }

    /// The plural form, and "session" rather than "run" — a chip can name a lift
    /// (`testLabelNamesALiftByItsOwnActivityType` above), so the sentence naming however
    /// many were left off must not claim they are all runs.
    func testOmittedCountAccessibilityLabelPluralises() {
        XCTAssertEqual(
            RunsStripCopy.omittedCountAccessibilityLabel(3),
            "3 more sessions in this conversation, not shown"
        )
    }

    /// One workout a day on consecutive days from Monday 2026-01-05, exactly as
    /// `ContextBuilderTests.windowOf(sessionCount:)` builds its own fixture — a window
    /// this test suite reasons about the same way that one does.
    private func windowOf(sessionCount: Int) throws -> TrainingContext {
        let start = try day("2026-01-05")
        var records: [ContextInputs.WorkoutRecord] = []
        for offset in 0..<sessionCount {
            let id = UUID()
            records.append(try record(id: id, on: try start.adding(days: offset).description))
        }
        return try trainingContext(
            from: start.description,
            through: try start.adding(days: sessionCount - 1).description,
            records: records,
            today: "2027-01-01"
        )
    }
}
