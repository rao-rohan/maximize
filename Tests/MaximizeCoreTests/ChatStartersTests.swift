import Foundation
import XCTest
@testable import MaximizeCore

/// §6.7, MAX-200: the tappable starters on an empty thread.
///
/// Pinned as literals rather than asserted by shape (count, non-empty, distinctness)
/// alone — CLAUDE.md's "assert against returned output" cuts the other way here: a
/// starter that silently drifted to a question the current fact sheet can no longer
/// answer would pass every structural check and still be the defect this ticket exists
/// to prevent. Pinning the exact wording means a future change to what a fact sheet
/// carries has to touch this file on purpose, not by accident.
final class ChatStartersTests: XCTestCase {

    // MARK: - Pinned literals

    func testWorkoutStartersArePinned() {
        XCTAssertEqual(ChatStarters.starters(for: .workout), [
            "Did this match what today's plan asked for?",
            "What does this session's strain number actually mean?",
            "How does this fit into my week so far?",
        ])
    }

    func testTrainingStartersArePinned() {
        XCTAssertEqual(ChatStarters.starters(for: .training), [
            "Am I hitting the plan's ask on both my runs and lifts this window?",
            "What does my acute:chronic load balance look like right now?",
            "What's dragging my average score down this window, if anything?",
        ])
    }

    /// The one state `ChatConversationView` never actually reaches (`model.subject` is
    /// always resolved by the time it draws starters at all) — still asserted, because
    /// `starters(for:)` is total and a nil kind reaching it by some future path must
    /// still get a safe answer rather than a crash or a guess.
    func testANilKindOffersNoStarters() {
        XCTAssertEqual(ChatStarters.starters(for: nil), [])
    }

    // MARK: - Shape, kept as a second, independent check on the literals above

    func testEveryKindOffersAHandfulOfStarters() {
        for kind in ChatSubjectKind.allCases {
            let starters = ChatStarters.starters(for: kind)
            XCTAssertGreaterThanOrEqual(starters.count, 2, "\(kind) starters")
            XCTAssertLessThanOrEqual(starters.count, 3, "\(kind) starters")
        }
    }

    func testNoStarterIsBlankAndEveryStarterIsAQuestion() {
        for kind in ChatSubjectKind.allCases {
            for starter in ChatStarters.starters(for: kind) {
                XCTAssertFalse(starter.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertTrue(starter.hasSuffix("?"), starter)
            }
        }
    }

    func testStartersWithinAKindAreDistinct() {
        for kind in ChatSubjectKind.allCases {
            let starters = ChatStarters.starters(for: kind)
            XCTAssertEqual(starters.count, Set(starters).count, "\(kind) repeats a starter")
        }
    }

    func testTheTwoKindsShareNoStarter() {
        let workout = Set(ChatStarters.starters(for: .workout))
        let training = Set(ChatStarters.starters(for: .training))
        XCTAssertTrue(workout.isDisjoint(with: training))
    }

    /// A workout thread only ever offers starters for a run or a lift (a ride, a hike or
    /// a walk resolve to `.noVerdict` before the transcript that draws these ever
    /// appears — MAX-126, MAX-168), and `WorkoutFactSheet` omits every run-only figure
    /// for a lift (§10.1). A starter naming one of them would be unanswerable on exactly
    /// the discipline this set has to also hold for.
    func testWorkoutStartersNameNoRunOnlyFigure() {
        let runOnlyVocabulary = ["pace", "cadence", "drift", "split", "grade-adjusted", "kilometre", "mile"]
        for starter in ChatStarters.starters(for: .workout) {
            let lowercased = starter.lowercased()
            for word in runOnlyVocabulary {
                XCTAssertFalse(lowercased.contains(word), "\(starter) names run-only vocabulary: \(word)")
            }
        }
    }

    /// §3.4/A11: a training thread's scope is frozen at creation and does not move with
    /// the calendar. A starter asking it to reach outside that window — "compared to
    /// last month", "versus my previous block" — is exactly the shape of question
    /// MAX-175's honest-refusal rule declines, and a starter that trips that rule reads
    /// as the feature being broken rather than the model being honest.
    func testTrainingStartersDoNotReachOutsideTheFrozenWindow() {
        let outOfScopePhrases = ["last month", "last week", "previous", "compared to", "versus my", "before this"]
        for starter in ChatStarters.starters(for: .training) {
            let lowercased = starter.lowercased()
            for phrase in outOfScopePhrases {
                XCTAssertFalse(lowercased.contains(phrase), "\(starter) reaches outside its frozen window: \(phrase)")
            }
        }
    }
}
