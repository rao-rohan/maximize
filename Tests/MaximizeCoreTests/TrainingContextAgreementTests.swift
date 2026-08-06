import Foundation
import XCTest
@testable import MaximizeCore

/// **CHAT-FIRST-SPEC.md §3.6(a), and it is an acceptance criterion of MAX-095.**
///
/// > *Build a `TrainingContext` and a `TrendTileData` over the same interval from the same
/// > stored inputs and assert the figures are equal. That is a plain unit test in the core,
/// > it runs on every commit, and it is the difference between claiming the property and
/// > having it.*
///
/// The property is that **chat and the dashboard cannot disagree**. Both now describe the
/// same numbers to the same person, so a figure quoted in a bubble that contradicts the
/// tile behind it is a *visible product defect* rather than an internal untidiness — and
/// the way it would happen is not malice but convenience: a helper averaging a few drift
/// figures inside `TrainingContext` to save a call into the tallies is D2's drift arriving
/// in a prompt, where nothing on screen contradicts it and nobody notices.
///
/// So every test below builds **one** set of stored records, feeds it to **both** paths,
/// and compares. If `TrainingContext` ever starts computing an aggregate itself, one of
/// these fails.
final class TrainingContextAgreementTests: XCTestCase {

    // MARK: - The one set of stored records both paths are built from

    private struct StoredRecords {
        let workouts: [Workout]
        let ledgers: [UUID: ScoreLedger]
        let records: [ContextInputs.WorkoutRecord]
    }

    private static let today = "2026-06-01"

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func calendar() throws -> PlanCalendar {
        try PlanCalendar([Fixture.plan()])
    }

    private func workout(id: UUID, on dayText: String, distanceMeters: Double = 8_000) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(8 * 3_600)
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 500,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(3_660)
        )
    }

    /// - Parameter sessions: `(day, score, correction)`. A nil score is a recorded but
    ///   unscored session — the state of every workout between capture and scoring, and
    ///   the permanent state of every non-run since MAX-111.
    private func stored(_ sessions: [(day: String, points: Int?, correctedTo: Int?)]) throws -> StoredRecords {
        var workouts: [Workout] = []
        var ledgers: [UUID: ScoreLedger] = [:]
        var records: [ContextInputs.WorkoutRecord] = []

        for session in sessions {
            let id = UUID()
            let run = try workout(id: id, on: session.day)
            workouts.append(run)

            var ledger: ScoreLedger?
            if let points = session.points {
                var built = try ScoreLedger(automatic: try Fixture.score(points: points, workoutID: id))
                if let correctedTo = session.correctedTo {
                    built = try built.annotated(
                        with: try Fixture.annotation(points: correctedTo, workoutID: id)
                    )
                }
                ledgers[id] = built
                ledger = built
            }

            records.append(
                try ContextInputs.WorkoutRecord(
                    workout: run,
                    metrics: try DerivedMetrics(
                        workoutID: id,
                        averageHeartRateBPM: 142,
                        maximumHeartRateBPM: 160,
                        timeAboveCapSeconds: 250,
                        heartRateDriftFraction: 0.032,
                        planVersion: PlanVersion(1)
                    ),
                    ledger: ledger
                )
            )
        }

        return StoredRecords(workouts: workouts, ledgers: ledgers, records: records)
    }

    // MARK: - Both paths, over the same window

    private func rollUp(
        _ stored: StoredRecords,
        from: String,
        through: String,
        today: String = TrainingContextAgreementTests.today
    ) throws -> TrainingContext {
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day(today),
            planCalendar: try calendar(),
            restDayBudget: .standard,
            records: stored.records
        )
        switch try ContextBuilder.build(
            for: .training(try TrainingScope(from: try day(from), through: try day(through))),
            from: inputs
        ) {
        case let .training(context): return context
        case .workout: throw DomainError.inconsistent(reason: "expected a training context")
        }
    }

    private func dashboardTallies(
        _ stored: StoredRecords,
        from: String,
        through: String,
        today: String = TrainingContextAgreementTests.today
    ) throws -> Tallies {
        try TalliesCalculator.compute(
            TalliesInput(
                from: try day(from),
                through: try day(through),
                timeZone: .gmt,
                today: try day(today),
                workouts: stored.workouts,
                scoreLedgers: stored.ledgers,
                planCalendar: try calendar(),
                restDayBudget: .standard
            )
        )
    }

    private func dashboardTiles(
        _ stored: StoredRecords,
        kind: TrendIntervalKind,
        tallies: Tallies
    ) throws -> TrendTileData {
        try TrendTileData(
            kind: kind,
            tallies: tallies,
            workouts: stored.workouts,
            timeZone: .gmt,
            planCalendar: try calendar(),
            distanceUnit: .kilometers
        )
    }

    // MARK: - The property

    /// Monday rest · Tuesday easy, effective · Wednesday hard, effective · Thursday easy,
    /// nothing recorded (the week's only miss, converted by the budget of 1) · Friday rest ·
    /// Saturday recorded but unscored · Sunday long, effective. The same week
    /// `TalliesTests` hand-works, so the tallies below have an independently reasoned
    /// answer as well as an agreeing one.
    func testEveryTalliedFigureAgreesWithTheDashboardsOwn() throws {
        let stored = try stored([
            (day: "2026-01-06", points: 80, correctedTo: nil),
            (day: "2026-01-07", points: 75, correctedTo: nil),
            (day: "2026-01-10", points: nil, correctedTo: nil),
            (day: "2026-01-11", points: 90, correctedTo: nil),
        ])

        let context = try rollUp(stored, from: "2026-01-05", through: "2026-01-11")
        let tallies = try dashboardTallies(stored, from: "2026-01-05", through: "2026-01-11")
        let tiles = try dashboardTiles(stored, kind: .week, tallies: tallies)

        // The whole rollup, read not re-derived: this is the assertion that makes every
        // figure below a formatting question rather than a measurement one.
        XCTAssertEqual(context.tallies, tallies)

        let sheet = context.factSheet()

        // …and the rendered figures are the tiles' own strings, so they cannot differ in
        // shape or in rounding either (§3.6(c)).
        let effectiveDays = try XCTUnwrap(tiles.effectiveDays)
        // MAX-157: the fact sheet's label is "Effective sessions", not "Effective days" —
        // since MAX-134 the denominator counts prescribed obligations, not calendar days.
        XCTAssertTrue(sheet.contains("Effective sessions: \(effectiveDays.value)"), sheet)

        let averageScore = try XCTUnwrap(tiles.averageScore)
        XCTAssertTrue(sheet.contains("Average score: \(averageScore.value)"), sheet)

        XCTAssertTrue(sheet.contains("Current streak: \(tiles.streak.value) days"), sheet)

        // `workoutDays` is deliberately absent from the weekly tile set, so it is checked
        // against the tally itself — the same stored figure the monthly tile reads.
        XCTAssertTrue(sheet.contains("Days with at least one workout: \(tallies.workoutDays)"), sheet)
    }

    /// The monthly tile set is the one that shows `workoutDays`, so the roll-up's line for
    /// it is checked against the tile that actually renders it.
    func testTheWorkoutDaysFigureAgreesWithTheMonthlyTile() throws {
        let stored = try stored([
            (day: "2026-01-06", points: 80, correctedTo: nil),
            (day: "2026-01-13", points: 72, correctedTo: nil),
            (day: "2026-01-20", points: 64, correctedTo: nil),
        ])

        let context = try rollUp(stored, from: "2026-01-01", through: "2026-01-31")
        let tallies = try dashboardTallies(stored, from: "2026-01-01", through: "2026-01-31")
        let tiles = try dashboardTiles(stored, kind: .month, tallies: tallies)

        XCTAssertEqual(context.tallies, tallies)

        let workoutDays = try XCTUnwrap(tiles.workoutDays)
        XCTAssertTrue(
            context.factSheet().contains("Days with at least one workout: \(workoutDays.value)"),
            context.factSheet()
        )
    }

    /// A manual correction moves the tallies (§8: where an annotation exists, tallies use
    /// it) and must move the roll-up's average by exactly the same amount — while the
    /// per-session line keeps showing both numbers, because the auto-score is immutable
    /// (D8) and the average is built from the correction.
    func testACorrectionMovesBothTheTileAndTheRollUpIdentically() throws {
        let uncorrected = try stored([
            (day: "2026-01-06", points: 60, correctedTo: nil),
            (day: "2026-01-07", points: 80, correctedTo: nil),
        ])
        let corrected = try stored([
            (day: "2026-01-06", points: 60, correctedTo: 90),
            (day: "2026-01-07", points: 80, correctedTo: nil),
        ])

        for snapshot in [uncorrected, corrected] {
            let context = try rollUp(snapshot, from: "2026-01-05", through: "2026-01-11")
            let tallies = try dashboardTallies(snapshot, from: "2026-01-05", through: "2026-01-11")
            let tiles = try dashboardTiles(snapshot, kind: .week, tallies: tallies)

            XCTAssertEqual(context.tallies, tallies)
            let averageScore = try XCTUnwrap(tiles.averageScore)
            XCTAssertTrue(context.factSheet().contains("Average score: \(averageScore.value)"))
        }

        let correctedContext = try rollUp(corrected, from: "2026-01-05", through: "2026-01-11")
        // 90 and 80, not 60 and 80.
        XCTAssertTrue(correctedContext.factSheet().contains("Average score: 85.0"), correctedContext.factSheet())
        // …and the immutable auto-score is still on the line beside it.
        XCTAssertTrue(
            correctedContext.factSheet().contains("Score: 60/100 (marginal), corrected by hand to 90/100"),
            correctedContext.factSheet()
        )
    }

    /// The two paths must agree about **absence** too, and this is the case where a
    /// fabricated zero would be easiest to write: `TrendTileData` renders no average-score
    /// tile at all when nothing has been scored, and the roll-up must not answer "0.0".
    func testAnAbsentAverageIsAbsentOnBothSurfaces() throws {
        let stored = try stored([
            (day: "2026-01-06", points: nil, correctedTo: nil),
            (day: "2026-01-07", points: nil, correctedTo: nil),
        ])

        let context = try rollUp(stored, from: "2026-01-05", through: "2026-01-11")
        let tallies = try dashboardTallies(stored, from: "2026-01-05", through: "2026-01-11")
        let tiles = try dashboardTiles(stored, kind: .week, tallies: tallies)

        XCTAssertNil(tiles.averageScore)
        XCTAssertNil(context.tallies.averageScore)

        let sheet = context.factSheet()
        XCTAssertTrue(sheet.contains("Average score: nothing in this window has been scored yet"), sheet)
        XCTAssertFalse(sheet.contains("Average score: 0.0"), sheet)
    }

    /// Likewise for the effective-day ratio: `EffectiveObligationTally.rate` is nil when nothing
    /// was eligible, `TrendTileData` withholds the tile, and the roll-up says which kind
    /// of nothing it is rather than printing "0/0".
    func testAnEmptyEffectiveDayRatioIsWithheldOnBothSurfaces() throws {
        let stored = try stored([])

        // A window entirely before the first plan version: nothing was ever asked of it.
        let context = try rollUp(stored, from: "2025-12-22", through: "2025-12-28")
        let tallies = try dashboardTallies(stored, from: "2025-12-22", through: "2025-12-28")
        let tiles = try dashboardTiles(stored, kind: .week, tallies: tallies)

        XCTAssertNil(tiles.effectiveDays)
        XCTAssertNil(context.tallies.effectiveDays.rate)

        let sheet = context.factSheet()
        // MAX-157: same label fix as the populated case above, and the same absence
        // wording either way — a mislabelled unit is no less wrong when the count is zero.
        XCTAssertTrue(sheet.contains("Effective sessions: nothing in this window was eligible"), sheet)
        XCTAssertFalse(sheet.contains("Effective sessions: 0/0"), sheet)
        XCTAssertFalse(sheet.contains("Effective days:"), sheet)
    }

    /// MAX-110's rule, arriving in a prompt: a window reaching into the future must not
    /// have its unfinished days counted as misses on either surface. `today` is an input
    /// to both paths and neither reads a clock.
    func testAWindowReachingIntoTheFutureAgreesAboutWhatIsNotYetKnown() throws {
        let stored = try stored([
            (day: "2026-01-06", points: 80, correctedTo: nil),
        ])

        let context = try rollUp(stored, from: "2026-01-05", through: "2026-01-11", today: "2026-01-07")
        let tallies = try dashboardTallies(stored, from: "2026-01-05", through: "2026-01-11", today: "2026-01-07")

        XCTAssertEqual(context.tallies, tallies)
        // Tuesday is decided and effective; Wednesday onward has not happened.
        XCTAssertEqual(context.tallies.effectiveDays.eligibleCount, 1)
        XCTAssertEqual(context.tallies.effectiveDays.effectiveCount, 1)
    }

    // MARK: - MAX-160: a labelled score, on both surfaces

    /// Built by hand rather than through `stored()` — that helper has no way to attach a
    /// `MiscategorisedScoreLabel`, and widening its tuple would force every call site above
    /// to spell out a fourth field it does not care about.
    private func storedWithLabel(
        workoutID: UUID,
        on dayText: String,
        points: Int
    ) throws -> StoredRecords {
        let recorded = try workout(id: workoutID, on: dayText)
        let score = try Fixture.score(points: points, workoutID: workoutID)
        let label = try MiscategorisedScoreLabel(
            id: UUID(),
            workoutID: workoutID,
            judgedAgainst: score.scheduledSession.kind,
            actualDiscipline: .lift,
            recordedAt: Fixture.epoch
        )
        let ledger = try ScoreLedger(automatic: score, labels: [label])
        return StoredRecords(
            workouts: [recorded],
            ledgers: [workoutID: ledger],
            records: [
                try ContextInputs.WorkoutRecord(
                    workout: recorded,
                    metrics: try DerivedMetrics(
                        workoutID: workoutID,
                        averageHeartRateBPM: 142,
                        maximumHeartRateBPM: 160,
                        timeAboveCapSeconds: 250,
                        heartRateDriftFraction: 0.032,
                        planVersion: PlanVersion(1)
                    ),
                    ledger: ledger
                ),
            ]
        )
    }

    /// The one scored workout in the window carries a label, so `TrendTileData` withholds
    /// the tile entirely (MAX-160: no value to caption a reason onto) while the fact sheet
    /// — which is prose, not a value/caption pair — can and does say which kind of "no
    /// average" this is. Both paths must still agree it is *not* the ordinary "nothing has
    /// been scored yet" absence.
    func testALabelledScoreLeavesNoAverageAndTheFactSheetSaysWhy() throws {
        let workoutID = UUID()
        let stored = try storedWithLabel(workoutID: workoutID, on: "2026-01-06", points: 30)

        let context = try rollUp(stored, from: "2026-01-05", through: "2026-01-11")
        let tallies = try dashboardTallies(stored, from: "2026-01-05", through: "2026-01-11")
        let tiles = try dashboardTiles(stored, kind: .week, tallies: tallies)

        XCTAssertEqual(context.tallies, tallies)
        XCTAssertNil(tiles.averageScore, "the only scored workout is labelled, so nothing is left to average")
        XCTAssertEqual(tallies.averageScoreExcludedMiscategorisedCount, 1)

        let sheet = context.factSheet()
        XCTAssertTrue(
            sheet.contains("Average score: every score in this window (1) was judged before the plan "
                + "distinguished lifting"),
            sheet
        )
        XCTAssertFalse(
            sheet.contains("Average score: nothing in this window has been scored yet"),
            "a verdict does exist here — it was excluded, which is a different fact — \(sheet)"
        )
    }
}
