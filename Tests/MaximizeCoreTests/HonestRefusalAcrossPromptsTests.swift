import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-175, first half — **the app does not invent**, held over the *set* of prompts
/// rather than in four places that each happen to remember it.
///
/// ## What was actually missing
///
/// The rule itself was not. Three of the app's four model-facing prompts already told
/// Claude to name an absence rather than fill it, in the file that owns each prompt's
/// words: `ChatModel.workoutTask`, `ChatModel.trainingTask` and
/// `PlanProposalInstruction.taskDescription`. `ChatInstruction` carries no such clause
/// because it carries no task text at all — its `task` has no default and its own
/// documentation says why — so looking for the rule there finds the one file
/// deliberately built not to hold it.
///
/// What was missing is this file: **no test held the four prompts to the rule as a
/// set.** Four independent good sentences are not an invariant; they are four sentences,
/// and the fifth prompt carries the rule only if its author remembers. A reword that
/// drops the clause from any one of them changed nothing that CI could see.
///
/// The one prompt that genuinely lacked the rule was the scorer's
/// (`WorkoutScorer.absenceRule` — see that constant for why its wording is a prohibition
/// rather than a refusal, and why the rationale is the part that made it worth adding).
///
/// ## Why the phrases are pinned per prompt rather than shared
///
/// Each prompt says the rule in its own vocabulary — a fact sheet, a summary, a
/// conversation, a record — because each is describing a different thing the model is
/// looking at. Collapsing them into one shared literal would have replaced four accurate
/// sentences with one that is slightly wrong in three places, and would have added a
/// second statement of a rule to prompts that already state it. So the *rule* is held as
/// a set here; the *words* stay with their owners.
@MainActor
final class HonestRefusalAcrossPromptsTests: XCTestCase {

    /// Every stable prompt half this app puts in front of Claude, with the clause each
    /// one uses to say what to do with an absence.
    ///
    /// **A new model-facing prompt belongs in this list.** That obligation cannot be
    /// enforced by a type — nothing makes a fifth `static let` of prompt text announce
    /// itself — which is exactly why it is written down here and in `PROJECT_TRACKER.md`
    /// rather than left to be noticed.
    ///
    /// The scorer's **lift** branch is held in `ScorerTaskTextTests` instead, beside the
    /// lift fixture that file already owns: `testTheLiftAndRunTaskTextsShareTheRationale…`
    /// asserts both branches carry `WorkoutScorer.absenceRule`, so the set is complete
    /// across the two files and neither duplicates the other's scaffolding.
    private static func promptsAndTheirAbsenceClauses() throws -> [(name: String, task: String, clause: String)] {
        let run = try ScoringFixture.context()
        let runInstruction = try WorkoutScorer.instruction(
            for: run,
            evaluation: RubricEvaluator.evaluate(run)
        )
        return [
            (
                "ChatModel.workoutTask",
                ChatModel.workoutTask,
                "Never invent a number, split, or detail the fact sheet does not state"
            ),
            (
                "ChatModel.trainingTask",
                ChatModel.trainingTask,
                "Never invent a figure it does not state"
            ),
            (
                "PlanProposalInstruction.taskDescription",
                PlanProposalInstruction.taskDescription,
                "Do not invent facts about the athlete."
            ),
            (
                "WorkoutScorer.taskDescription(.run)",
                runInstruction.task,
                WorkoutScorer.absenceRule
            ),
        ]
    }

    // MARK: - The rule, over the set

    func testEveryModelFacingPromptSaysWhatToDoWithAnAbsence() throws {
        for prompt in try Self.promptsAndTheirAbsenceClauses() {
            XCTAssertTrue(
                prompt.task.contains(prompt.clause),
                "\(prompt.name) no longer tells the model what to do when something is not "
                    + "in front of it"
            )
        }
    }

    /// The two chat prompts also say what to do when the *absence is of an answer* —
    /// a question outside the subject — and the training one refuses a second opinion on
    /// a score. Both are the same principle pointed at a different gap, and both were
    /// found by reading rather than assumed, so they are pinned here beside the rest.
    func testTheChatPromptsAlsoDeclineWhatIsOutsideWhatTheyWereGiven() {
        XCTAssertTrue(ChatModel.workoutTask.contains("say that is outside what you can see here"))
        XCTAssertTrue(ChatModel.trainingTask.contains("never re-score a session"))
        XCTAssertTrue(ChatModel.trainingTask.contains("No medical advice"))
    }

    // MARK: - The scorer's clause, pinned

    /// Pinned as a literal here — the one file that owns MAX-175's words — so that
    /// `ScorerTaskTextTests` can read it live without either file being the only thing
    /// standing between a reword and CI.
    func testTheScorersAbsenceRuleReadsExactlyAsPinned() {
        XCTAssertEqual(WorkoutScorer.absenceRule, Self.pinnedAbsenceRule)
    }

    private static let pinnedAbsenceRule = """
        The record you are given states its own absences. Where it says a figure was not \
        recorded, does not apply, or was not computed, do not supply one and do not reason \
        as though you had it: score and justify from what is stated.
        """

    // MARK: - Still no health data in the stable half

    /// The half that carries the rule is the half that caches, and it caches precisely
    /// because it says nothing about this athlete. A clause added to it must not be the
    /// thing that quietly changes that.
    ///
    /// Digits are the check for the three prose prompts because a figure about a person is
    /// what one would carry — the same assertion `ChatModelTests` already makes for its
    /// two, extended over the set.
    func testNoProsePromptCarriesAFigureAboutTheAthlete() {
        for task in [
            ChatModel.workoutTask,
            ChatModel.trainingTask,
            PlanProposalInstruction.taskDescription,
            WorkoutScorer.absenceRule,
        ] {
            XCTAssertNil(task.rangeOfCharacter(from: .decimalDigits), task)
        }
    }

    /// The scorer's whole task text cannot use the digit check — it numbers its two
    /// instructions and `RationaleContract` states a character limit — so the same claim
    /// is made the way it can be: the stable half does not move when the run does.
    func testTheScorersStableHalfDoesNotVaryWithTheRunBeingScored() throws {
        let cool = try ScoringFixture.context(
            metrics: try ScoringFixture.metrics(averageHeartRateBPM: 131)
        )
        let warm = try ScoringFixture.context(
            metrics: try ScoringFixture.metrics(averageHeartRateBPM: 148)
        )

        let first = try WorkoutScorer.instruction(for: cool, evaluation: RubricEvaluator.evaluate(cool))
        let second = try WorkoutScorer.instruction(for: warm, evaluation: RubricEvaluator.evaluate(warm))

        XCTAssertEqual(first.task, second.task)
        XCTAssertNotEqual(first.subject, second.subject, "the run itself is the half that varies")
    }
}
