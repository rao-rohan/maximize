import Foundation
import XCTest
@testable import MaximizeCore

/// PRD §10.3's worked example, pinned row by row.
///
/// These are the tests that make the design decision real: band selection is a pure
/// function of the context and the plan version, so the same run always lands in the
/// same band with no model in the loop. Everything MAX-071 wants to assert
/// ("known-good runs → expected score bands") rests on this file.
final class RubricEvaluationTests: XCTestCase {

    private func evaluate(
        on day: String = ScoringFixture.easyDay,
        classification: WorkoutClassification = .easy,
        metrics: DerivedMetrics? = nil,
        distanceMeters: Double? = 10_000,
        rubric: ScoringRubric? = nil
    ) throws -> RubricEvaluation {
        try RubricEvaluator.evaluate(
            ScoringFixture.context(
                on: day,
                classification: classification,
                metrics: metrics,
                distanceMeters: distanceMeters,
                rubric: rubric
            )
        )
    }

    // MARK: - §10.3, row by row

    /// "easy run: HR ≤ cap with low drift → 90–100"
    func testEasyRunUnderCapWithLowDriftTakesTheTopBand() throws {
        let evaluation = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142, heartRateDriftFraction: 0.03)
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.onCap.lowDrift")
        XCTAssertEqual(evaluation.permittedScores.lowest.points, 90)
        XCTAssertEqual(evaluation.permittedScores.highest.points, 100)
    }

    /// "under cap but late drift → 75–89". The same run, differing only in drift, falls
    /// past the first band to the second — which is what first-match-wins buys.
    func testEasyRunUnderCapWithHighDriftFallsToTheSecondBand() throws {
        let evaluation = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142, heartRateDriftFraction: 0.081)
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.onCap.lateDrift")
        XCTAssertEqual(evaluation.permittedScores.lowest.points, 75)
        XCTAssertEqual(evaluation.permittedScores.highest.points, 89)
    }

    /// "avg 151–158 → 55–74", expressed as ≤ cap + 8 so the row survives a cap change.
    func testEasyRunSlightlyOverCapTakesTheThirdBand() throws {
        let evaluation = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 155, heartRateDriftFraction: 0.02)
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.slightlyOverCap")
        XCTAssertEqual(evaluation.permittedScores.lowest.points, 55)
        XCTAssertEqual(evaluation.permittedScores.highest.points, 74)
    }

    /// "avg ≥ 159 → 20–45". 160 against a cap of 150 is one bpm past the 151–158 band.
    func testEasyRunWellOverCapTakesTheBottomBand() throws {
        let evaluation = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 160, heartRateDriftFraction: 0.02)
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.wellOverCap")
        XCTAssertEqual(evaluation.permittedScores.lowest.points, 20)
        XCTAssertEqual(evaluation.permittedScores.highest.points, 45)
    }

    /// "or hard-instead → 20–45". Classification decides this row, not heart rate: a
    /// hard session is judged as the wrong session, not as a very fast easy one.
    func testHardSessionOnAnEasyDayTakesTheHardInsteadBand() throws {
        let evaluation = try evaluate(
            classification: .hard,
            // Drift is withheld on hard sessions (§9), so the band must not need it.
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 168, heartRateDriftFraction: nil)
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.ranHardInstead")
        XCTAssertEqual(evaluation.classification, .hard)
        XCTAssertEqual(evaluation.scheduledSession.kind, .easy)
    }

    // MARK: - The shape of evaluation

    /// The cap is read from the plan, never from the code. The identical run scores in
    /// two different bands under two plan versions — which is the whole of D1 in one
    /// assertion.
    func testTheSameRunFallsInADifferentBandUnderADifferentCap() throws {
        let run = try ScoringFixture.metrics(averageHeartRateBPM: 155, heartRateDriftFraction: 0.02)

        let underTightCap = try RubricEvaluator.evaluate(
            WorkoutContextBuilder.build(
                workout: Fixture.workout(),
                on: CalendarDay(iso8601: ScoringFixture.easyDay),
                metrics: run,
                classification: .easy,
                planCalendar: PlanCalendar([ScoringFixture.plan(heartRateCapBPM: 150)])
            )
        )
        let underLooseCap = try RubricEvaluator.evaluate(
            WorkoutContextBuilder.build(
                workout: Fixture.workout(),
                on: CalendarDay(iso8601: ScoringFixture.easyDay),
                metrics: run,
                classification: .easy,
                planCalendar: PlanCalendar([ScoringFixture.plan(heartRateCapBPM: 160)])
            )
        )

        XCTAssertEqual(underTightCap.band.identifier, "easy.slightlyOverCap")
        XCTAssertEqual(underLooseCap.band.identifier, "easy.onCap.lowDrift")
    }

    /// Bands are filtered by what the plan *asked for*, so an easy-day row cannot fire
    /// on a long-run Sunday even when the numbers would satisfy it.
    func testBandsAreFilteredByTheScheduledSessionKind() throws {
        let evaluation = try evaluate(
            on: ScoringFixture.longDay,
            classification: .long,
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142, heartRateDriftFraction: 0.03),
            distanceMeters: 18_000
        )

        XCTAssertEqual(evaluation.band.identifier, "long.completedTheDistance")
    }

    func testEvaluationIsDeterministic() throws {
        let context = try ScoringFixture.context()

        let first = try RubricEvaluator.evaluate(context)
        let second = try RubricEvaluator.evaluate(context)

        XCTAssertEqual(first, second)
    }

    // MARK: - Absence

    /// A rubric row that needs a number nobody measured has not been *shown* to apply,
    /// so it does not fire. Here every easy row needs an average heart rate, and a
    /// workout without one matches nothing at all rather than silently taking a band.
    func testAMissingMetricDoesNotSatisfyItsCondition() throws {
        assertThrowsScoring(
            .noBandMatched,
            try evaluate(
                metrics: ScoringFixture.metrics(
                    averageHeartRateBPM: nil,
                    maximumHeartRateBPM: nil,
                    heartRateDriftFraction: nil
                )
            )
        )
    }

    /// …and a rubric that wants to say something about the missing case says it
    /// explicitly. This is the escape hatch that makes the policy above safe.
    func testAnExplicitUnavailableRowMatchesWhenTheMetricIsMissing() throws {
        let rubric = try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: "easy.noHeartRateData",
                    appliesTo: [.easy],
                    conditions: [.metricUnavailable(.averageHeartRateBPM)],
                    scoreRange: ScoreRange(lowest: 50, highest: 70),
                    rationale: "The run happened, but without heart-rate data it cannot be judged on cap."
                ),
            ]
        )

        let evaluation = try evaluate(
            metrics: ScoringFixture.metrics(
                averageHeartRateBPM: nil,
                maximumHeartRateBPM: nil,
                heartRateDriftFraction: nil
            ),
            rubric: rubric
        )

        XCTAssertEqual(evaluation.band.identifier, "easy.noHeartRateData")
    }

    /// Wednesday's session is "6 × 800m" with no prescribed distance (P4), so
    /// `.scheduledDistance` cannot resolve. An unresolvable right-hand side is not a
    /// match, and the run falls through rather than being compared against nothing.
    func testAnUnresolvableReferenceDoesNotMatch() throws {
        assertThrowsScoring(
            .noBandMatched,
            try evaluate(
                on: ScoringFixture.hardDay,
                classification: .hard,
                metrics: ScoringFixture.metrics(heartRateDriftFraction: nil)
            )
        )
    }

    /// The "skipped → 0–15" row can never fire while scoring a workout, because a
    /// context exists only when a workout was recorded. Ordered first here so the test
    /// would fail loudly if it were treated as a catch-all.
    func testTheSkippedRowNeverMatchesARecordedWorkout() throws {
        let rubric = try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: "skipped",
                    conditions: [.noWorkoutRecorded],
                    scoreRange: ScoreRange(lowest: 0, highest: 15),
                    rationale: "No workout recorded for a scheduled session."
                ),
                RubricBand(
                    identifier: "easy.any",
                    appliesTo: [.easy],
                    scoreRange: ScoreRange(lowest: 70, highest: 100),
                    rationale: "Ran on an easy day."
                ),
            ]
        )

        let evaluation = try evaluate(rubric: rubric)

        XCTAssertEqual(evaluation.band.identifier, "easy.any")
    }

    // MARK: - Refusals

    /// An incomplete rubric is refused, never defaulted. Falling back to some built-in
    /// range would be a score threshold living in Swift, which is the D1 violation the
    /// rubric exists to prevent.
    ///
    /// The rubric used here is `Fixture.rubric()` — MAX-010's, which expresses only the
    /// "hard-instead" half of §10.3's final row and has nothing to say about an easy run
    /// at 160 bpm. That gap is the subject of this test.
    func testARunNoBandCoversIsRefusedRatherThanDefaulted() throws {
        assertThrowsScoring(
            .noBandMatched,
            try evaluate(
                metrics: ScoringFixture.metrics(averageHeartRateBPM: 160, heartRateDriftFraction: 0.02),
                rubric: Fixture.rubric()
            )
        )
    }

    /// A run from before the plan existed has no ask to be measured against. It is
    /// stored and shown; it is simply not scored.
    func testARunBeforeAnyPlanVersionIsNotScoreable() throws {
        assertThrowsScoring(
            .noPlanInEffect,
            try evaluate(on: ScoringFixture.beforeAnyPlan)
        )
    }

    func testStructuralRefusalsAreNotWorthRetrying() throws {
        XCTAssertFalse(ScoringError.noBandMatched(scheduled: .easy, actual: .hard).isWorthRetrying)
        XCTAssertFalse(
            ScoringError.noPlanInEffect(day: try CalendarDay(iso8601: "2026-01-06")).isWorthRetrying
        )
        XCTAssertFalse(ScoringError.contextAlreadyScored(workoutID: Fixture.workoutID).isWorthRetrying)
    }

    // MARK: - Score → band, the one place entitled to decide it

    func testScoreBandReadsTheRubricsOwnThresholds() throws {
        let rubric = try ScoringFixture.workedExampleRubric(
            effectiveThreshold: 70, marginalThreshold: 45
        )

        XCTAssertEqual(rubric.scoreBand(for: try ScoreValue(70)), .effective)
        XCTAssertEqual(rubric.scoreBand(for: try ScoreValue(69)), .marginal)
        XCTAssertEqual(rubric.scoreBand(for: try ScoreValue(45)), .marginal)
        XCTAssertEqual(rubric.scoreBand(for: try ScoreValue(44)), .ineffective)
    }

    /// The reason `ScoreBand` has no `init(score:)`: the same number is a different band
    /// under a different plan version, and a historical score must keep the answer its
    /// own version gave.
    func testTheSameScoreIsADifferentBandUnderADifferentRubric() throws {
        let lenient = try ScoringFixture.workedExampleRubric(effectiveThreshold: 70, marginalThreshold: 45)
        let strict = try ScoringFixture.workedExampleRubric(effectiveThreshold: 80, marginalThreshold: 60)
        let seventyFive = try ScoreValue(75)

        XCTAssertEqual(lenient.scoreBand(for: seventyFive), .effective)
        XCTAssertEqual(strict.scoreBand(for: seventyFive), .marginal)
    }

    /// Where the rubric settles the verdict on its own, and where §10.3 hands it back to
    /// the model. 55–74 straddles an effective threshold of 70, so a run in that band is
    /// effective or not depending on the number chosen inside it.
    func testWhetherABandSettlesTheVerdictIsVisible() throws {
        let topBand = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142, heartRateDriftFraction: 0.03)
        )
        let straddlingBand = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 155, heartRateDriftFraction: 0.02)
        )
        let bottomBand = try evaluate(
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 160, heartRateDriftFraction: 0.02)
        )

        XCTAssertTrue(topBand.verdictIsSettledByRubric)
        XCTAssertEqual(topBand.settledScoreBand, .effective)

        XCTAssertFalse(straddlingBand.verdictIsSettledByRubric)
        XCTAssertNil(straddlingBand.settledScoreBand)

        // Settled as "not effective", but 20–45 crosses the marginal cut at 45, so the
        // exact colour of the calendar day still depends on the number.
        XCTAssertTrue(bottomBand.verdictIsSettledByRubric)
        XCTAssertNil(bottomBand.settledScoreBand)
    }
}
