import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-147: the scorer's task text learns which discipline it is scoring.
///
/// MAX-133 taught `RubricEvaluator` to resolve a workout against its own discipline's
/// ask; MAX-136 taught `WorkoutFactSheet` to stop describing a lift in running
/// vocabulary. Both left `WorkoutScorer`'s task text — the instruction wrapped around
/// that fact sheet — opening with "You are scoring one running workout" for every call,
/// lift included. This file is the third piece.
///
/// Two things have to be proven in opposite directions: the run branch must not have
/// moved at all, and the lift branch must not have inherited any of the vocabulary or
/// invitations that only make sense against a run's record.
final class ScorerTaskTextTests: XCTestCase {

    // MARK: - The run branch does not move

    /// Pinned as a literal rather than asserted against a substring, precisely so that
    /// an edit made in service of the lift branch cannot drift this one silently. The
    /// paragraphs this ticket does not own — `RationaleContract`'s rules,
    /// `ScoreProposal`'s reply format, and MAX-175's absence rule — are read live rather
    /// than duplicated here: they belong to a different ticket, and hardcoding their
    /// current wording a second time would make this test fail on an edit that has
    /// nothing to do with MAX-147. Each is pinned as a literal in its own owner's file
    /// (`HonestRefusalAcrossPromptsTests` for the absence rule).
    func testTheRunTaskTextIsUnchanged() throws {
        let subject = try ScoringFixture.context()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        XCTAssertEqual(instruction.task, Self.pinnedRunTaskText)
    }

    private static let pinnedRunTaskText = """
        You are scoring one running workout against the athlete's training plan.

        The plan's rubric has already been applied deterministically, and you are told \
        which rule matched and the score range that rule permits. Your job is the part \
        the rubric cannot do:

        1. Choose the exact score within the permitted range, using the run's measured \
        numbers to decide where in that range it belongs. The bottom of the range means \
        the run barely satisfied the rule; the top means it satisfied it emphatically.
        2. Write the one-line rationale shown in the app's verdict header.

        Do not argue with the matched rule and do not score outside the permitted range. \
        A score outside it will be rejected and you will be asked again.

        \(WorkoutScorer.absenceRule)

        Rationale rules:
        \(RationaleContract.instructionText)

        Reply with a single JSON object and nothing else — no prose before or after it:
        \(ScoreProposal.responseFormatDescription)
        """

    // MARK: - The lift branch carries no running vocabulary

    /// LIFTING-SPEC §10.1's list, read onto the instruction rather than just the fact
    /// sheet: none of a run's vocabulary belongs in a lift's task text either, because a
    /// lift's fact sheet carries none of the figures these words describe.
    func testTheLiftTaskTextCarriesNoRunningVocabulary() throws {
        let subject = try Self.liftContext()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        for term in ["pace", "cadence", "cap", "splits", "distance"] {
            XCTAssertFalse(
                instruction.task.lowercased().contains(term),
                "lift task text should not mention '\(term)'"
            )
        }
    }

    /// §8.3: no rubric band references a load or a volume, because no such number
    /// exists in the record. The task text must not invite the model to reason about
    /// work it was never shown.
    func testTheLiftTaskTextDoesNotInviteJudgingLoadOrVolume() throws {
        let subject = try Self.liftContext()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        for term in ["load", "volume", "weight", " reps", " sets", "how much"] {
            XCTAssertFalse(
                instruction.task.lowercased().contains(term),
                "lift task text should not invite judging '\(term)'"
            )
        }
    }

    /// The opening line MAX-133's report named directly.
    func testTheLiftTaskTextDoesNotOpenAsARunningWorkout() throws {
        let subject = try Self.liftContext()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        XCTAssertFalse(instruction.task.contains("running workout"))
        XCTAssertTrue(instruction.task.contains("lifting workout"))
    }

    /// A20's positive framing: adherence is what a lift **is** judged on, so the task
    /// text should say so rather than only saying what it is not.
    func testTheLiftTaskTextDescribesAdherence() throws {
        let subject = try Self.liftContext()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        XCTAssertTrue(instruction.task.contains("prescribed day"))
        XCTAssertTrue(instruction.task.contains("prescribed length"))
    }

    /// The two disciplines must not fork the contract itself — only what is being
    /// scored, never how an answer is judged or shaped.
    func testTheLiftAndRunTaskTextsShareTheRationaleAndReplyContract() throws {
        let run = try ScoringFixture.context()
        let lift = try Self.liftContext()

        let runInstruction = try WorkoutScorer.instruction(for: run, evaluation: RubricEvaluator.evaluate(run))
        let liftInstruction = try WorkoutScorer.instruction(for: lift, evaluation: RubricEvaluator.evaluate(lift))

        for task in [runInstruction.task, liftInstruction.task] {
            XCTAssertTrue(task.contains(RationaleContract.instructionText))
            XCTAssertTrue(task.contains(ScoreProposal.responseFormatDescription))
            XCTAssertTrue(task.contains("Do not argue with the matched rule"))
            // MAX-175: what to do with an absence is a property of the reply, not of the
            // discipline, so neither branch may carry it alone.
            XCTAssertTrue(task.contains(WorkoutScorer.absenceRule))
        }
    }

    /// The stable half stays stable within a discipline — no health data, no numbers —
    /// which is what makes either variant safe to cache (MAX-147 amends the type's own
    /// doc comment to say "per discipline" rather than "for every workout").
    func testTheLiftTaskHalfCarriesNoHealthData() throws {
        let light = try Self.liftContext(averageHeartRateBPM: 118)
        let heavy = try Self.liftContext(averageHeartRateBPM: 171)

        let first = try WorkoutScorer.instruction(for: light, evaluation: RubricEvaluator.evaluate(light))
        let second = try WorkoutScorer.instruction(for: heavy, evaluation: RubricEvaluator.evaluate(heavy))

        XCTAssertEqual(first.task, second.task)
        XCTAssertFalse(first.task.contains("bpm"))
        XCTAssertFalse(first.task.contains("118"))
        XCTAssertFalse(first.task.contains("171"))
    }

    // MARK: - Scaffolding

    /// Tuesday of the fixture week, carrying a lift ask as well as its run ask — the
    /// normal case A17 describes. Mirrors `DisciplineMatchedEvaluationTests`' shape,
    /// kept minimal here because this file is about the task text, not about routing.
    private static func liftContext(averageHeartRateBPM: Double = 138) throws -> WorkoutContext {
        try WorkoutContextBuilder.build(
            workout: Fixture.workout(
                activityType: .traditionalStrengthTraining,
                durationSeconds: 2_700,
                distanceMeters: nil,
                hasRoute: false
            ),
            on: CalendarDay(iso8601: ScoringFixture.easyDay),
            metrics: DerivedMetrics(
                workoutID: Fixture.workoutID,
                averageHeartRateBPM: averageHeartRateBPM,
                maximumHeartRateBPM: averageHeartRateBPM + 16,
                zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .three, seconds: 2_000)]),
                planVersion: PlanVersion(1)
            ),
            classification: .other,
            planCalendar: PlanCalendar([Self.liftPlan()]),
            audience: .scoring,
            existingScore: nil
        )
    }

    private static func liftPlan() throws -> Plan {
        try Plan(
            version: PlanVersion(1),
            effectiveFrom: CalendarDay(iso8601: "2026-01-01"),
            weeklyTemplate: Fixture.weeklyTemplate(lift: [
                .tuesday: ScheduledSession(
                    kind: .lift,
                    durationSeconds: 2_700,
                    note: "45 minutes",
                    muscleGroups: [.chest, .shoulders]
                ),
            ]),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Self.liftRubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    /// One unconditional lift band, wide enough that any heart rate this file passes in
    /// matches it — this file is testing the task text, not band selection, which
    /// `DisciplineMatchedEvaluationTests` and `LiftRubricVocabularyTests` already cover.
    private static func liftRubric() throws -> ScoringRubric {
        try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: "lift.metTheAsk",
                    appliesTo: [.lift],
                    conditions: [.actualDiscipline(oneOf: [.lift])],
                    scoreRange: ScoreRange(lowest: 50, highest: 100),
                    rationale: "Lifted for the session the plan asked for."
                ),
            ]
        )
    }
}
