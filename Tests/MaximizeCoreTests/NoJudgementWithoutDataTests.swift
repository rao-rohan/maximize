import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-175, second half — **where the data required for a judgement is absent, the app
/// produces no judgement rather than a degraded one.**
///
/// ## Why this file exists when nothing was broken
///
/// The behaviour is already right, everywhere it was looked for. MAX-130 stopped
/// fabricating a cadence for a lift; MAX-136 omits the figures a lift was never measured
/// by and says once why; MAX-168's ingestion gates all fail closed, leaving a workout
/// stored and unscored rather than scored badly; `.awaitingScore` and `.noVerdict` are
/// designed states with their own sentences; `Tallies.averageScore` refuses to report
/// `0.0` for "nothing has been scored". Each of those is pinned by the test file of the
/// ticket that built it.
///
/// **What did not exist was the rule.** Six correct decisions taken six times are not an
/// invariant a seventh ticket inherits — they are six decisions, and the seventh author
/// has to arrive at the same conclusion unaided. So this file holds the rule rather than
/// any one feature, and each test below names the seam it is standing at. Some of these
/// assertions restate, from the rule's side, something a per-ticket file already checks.
/// That overlap is the point: those files can be deleted with their tickets, and this one
/// is the rule.
///
/// Two seams are deliberately *not* restated here, because their fixtures are large and
/// their homes are unambiguous — but they are part of the same invariant and a reader
/// should know where they live:
///
/// - **Ingestion**, in `WorkoutIngestionPipelineTests`: a workout predating every plan, a
///   rubric with no matching band, and a model call that overruns its budget all end with
///   a stored, unscored workout and no fabricated metrics.
/// - **The roll-up**, in `ContextBuilderTests`: an empty window says so, an unscored
///   session reads "no verdict", and a field the record does not carry is omitted rather
///   than nil-rendered.
final class NoJudgementWithoutDataTests: XCTestCase {

    // MARK: - The rubric refuses rather than defaults

    /// No plan governed the day, so there is no ask to be measured against — and
    /// therefore nothing to judge. The refusal is what keeps a run from being scored
    /// against a plan that was not in force (D1).
    func testADayNoPlanGovernedYieldsNoEvaluationRatherThanADefaultOne() throws {
        assertThrowsScoring(
            .noPlanInEffect,
            try RubricEvaluator.evaluate(ScoringFixture.context(on: ScoringFixture.beforeAnyPlan))
        )
    }

    /// The strap dropped, so every band that decides an easy run needs a number nobody
    /// measured. The run is refused rather than judged on whatever else happens to be on
    /// file: a band has not been *shown* to apply, and "we could not tell" is a different
    /// answer from "you ran badly".
    func testARunWhoseDecidingMetricWasNeverMeasuredIsRefusedRatherThanScoredOnWhatIsLeft() throws {
        assertThrowsScoring(
            .noBandMatched,
            try RubricEvaluator.evaluate(
                ScoringFixture.context(
                    metrics: try ScoringFixture.metrics(
                        averageHeartRateBPM: nil,
                        maximumHeartRateBPM: nil,
                        heartRateDriftFraction: nil
                    )
                )
            )
        )
    }

    // MARK: - A reply that cannot be accepted is not repaired

    /// Clamping would turn a reply the app does not believe into a score it will keep
    /// forever (D8). Both directions are refused: outside the matched band, and outside
    /// the scale entirely.
    func testAProposalOutsideWhatTheRubricPermitsIsRejectedRatherThanClamped() throws {
        let context = try ScoringFixture.context()
        let evaluation = try RubricEvaluator.evaluate(context)
        // The fixture's easy run matches "easy.onCap.lowDrift", which permits 90–100.
        XCTAssertEqual(evaluation.permittedScores.lowest.points, 90)

        assertThrowsScoring(
            .scoreOutsideBand,
            try WorkoutScorer.score(
                context: context,
                evaluation: evaluation,
                proposal: ScoreProposal(score: 88, rationale: "Held the cap with minimal drift."),
                scoredAt: ScoringFixture.scoredAt
            )
        )
        assertThrowsScoring(
            .scoreOutOfPermittedRange,
            try WorkoutScorer.score(
                context: context,
                evaluation: evaluation,
                proposal: ScoreProposal(score: 137, rationale: "Held the cap with minimal drift."),
                scoredAt: ScoringFixture.scoredAt
            )
        )
    }

    /// The verdict header is prose the app cannot check for truth, so the one thing it can
    /// check is that something was actually said. An empty rationale is refused rather
    /// than backfilled with the band's own wording — a header quoting the rubric at the
    /// athlete would read as a judgement the model never made.
    func testARationaleThatSaysNothingIsRejectedRatherThanFilledIn() {
        for empty in ["", "   ", "\n"] {
            XCTAssertThrowsError(try RationaleContract.validated(empty))
        }
    }

    // MARK: - Aggregates do not invent a figure out of an empty set

    /// A recorded workout nobody has scored is a workout day and nothing else. The average
    /// is nil rather than `0.0`, and the excluded count says which nil this is — "nothing
    /// has been scored" and "everything scored was set aside" are different facts, and
    /// neither is "you averaged zero".
    func testAWindowWhoseOnlyWorkoutWasNeverScoredHasNoAverageRatherThanAZero() throws {
        let tallies = try TalliesCalculator.compute(
            TalliesInput(
                from: try CalendarDay(iso8601: "2026-01-01"),
                through: try CalendarDay(iso8601: "2026-01-01"),
                timeZone: .gmt,
                today: try CalendarDay(iso8601: "2026-12-31"),
                workouts: [try Fixture.workout()],
                scoreLedgers: [:],
                planCalendar: try PlanCalendar([Fixture.plan()]),
                restDayBudget: .standard
            )
        )

        XCTAssertEqual(tallies.workoutDays, 1, "the workout is real and is counted as one")
        XCTAssertNil(tallies.averageScore, "no score exists to average — not a fabricated 0.0")
        XCTAssertEqual(tallies.averageScoreExcludedMiscategorisedCount, 0)
    }

    // MARK: - No verdict, no conversation about a verdict

    /// The strictest form of the rule in the codebase, and worth naming as such: an
    /// unscored run does not get a *quieter* chat, it gets none. A thread would need a
    /// classification to describe the run at all, and the only classification that exists
    /// is the one the scorer recorded — deriving a second one here to fill the gap is
    /// precisely the fabrication this file is about.
    func testAnUnscoredRunHasNoConversationToOpenAtAll() throws {
        let record = try ContextInputs.WorkoutRecord(
            workout: try Fixture.workout(),
            metrics: try ScoringFixture.metrics(),
            ledger: nil
        )
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try CalendarDay(iso8601: "2026-06-01"),
            planCalendar: try PlanCalendar([Fixture.plan()]),
            restDayBudget: .standard,
            records: [record]
        )

        XCTAssertThrowsError(try ContextBuilder.build(for: .workout(Fixture.workoutID), from: inputs))
    }

    // MARK: - A muscle group nobody logged is not a recovered one

    /// MAX-179's seam. A fatigue figure of `0.0` for a group no session ever named
    /// would read as **fully recovered**, which is a claim about the athlete's body
    /// from a record that says nothing about it — they may have trained legs every day
    /// and told the app nothing (A22: "I have not told you yet" is not "I trained
    /// nothing").
    ///
    /// So the reading is `.neverLogged` and its `fraction` is nil. The group beside it
    /// is the contrast that makes the point: worked a fortnight ago, decayed below the
    /// model's floor, and **still carrying a figure** — because there, recovery is
    /// something the app was actually told enough to judge.
    func testAMuscleGroupNoSessionEverNamedHasNoFatigueFigureRatherThanAZero() throws {
        let map = try MuscleFatigueCalculator.compute(
            MuscleFatigueInput(
                now: Fixture.epoch,
                sessions: [
                    try MuscleFatigueSession(
                        workoutID: Fixture.workoutID,
                        groups: [.chest],
                        endedAt: Fixture.epoch.addingTimeInterval(-14 * 24 * 3_600),
                        durationSeconds: 2_700
                    )
                ]
            )
        )

        XCTAssertEqual(map[.legs], .neverLogged)
        XCTAssertNil(map[.legs].fraction, "no session named legs — not a fabricated 0.0")
        XCTAssertNotNil(
            map[.chest].fraction,
            "a group worked a fortnight ago is judged recovered, which is a different fact"
        )
        XCTAssertNotEqual(map[.chest], .neverLogged)
    }

    /// The same rule one level up: an athlete who has logged nothing gets the map's own
    /// absence state, not six regions drawn at zero. `hasNoLoggedSessions` is the
    /// question a screen asks instead of inferring it from six figures that would all
    /// have had to be invented.
    func testAnAthleteWhoHasLoggedNoStrengthSessionGetsNoMapRatherThanAnEmptyOne() throws {
        let map = try MuscleFatigueCalculator.compute(
            MuscleFatigueInput(now: Fixture.epoch, sessions: [])
        )

        XCTAssertTrue(map.hasNoLoggedSessions)
        XCTAssertEqual(map.neverLogged, Set(MuscleGroup.allCases))
        XCTAssertTrue(
            map.ordered.allSatisfy { $0.reading.fraction == nil },
            "every region is an absence, and none of them is a zero"
        )
    }
}
