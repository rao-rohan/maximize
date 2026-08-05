import Foundation
import XCTest
@testable import MaximizeCore

/// A22/MAX-145 — what the workout detail screen shows about muscle groups, and what the
/// picker will and will not let the athlete record.
final class MuscleGroupEntryDataTests: XCTestCase {

    private func entry(_ groups: Set<MuscleGroup>) throws -> MuscleGroupEntry {
        try MuscleGroupEntry(
            id: Fixture.muscleGroupEntryID,
            workoutID: Fixture.workoutID,
            groups: groups,
            recordedAt: Fixture.at(60)
        )
    }

    // MARK: - Which workouts are asked

    /// A22 spends the manual-entry non-goal for one field on **one kind of workout**.
    /// A run is never asked what muscles it worked, and this is the assertion that keeps
    /// the permission that narrow.
    func testARunIsNeverAskedWhatItTrained() {
        for activityType in [ActivityType.running, .treadmillRunning, .cycling, .walking, .hiking] {
            let data = MuscleGroupEntryData.resolve(activityType: activityType, entry: nil)
            XCTAssertEqual(data.state, .notALift, "\(activityType) should not be asked")
            XCTAssertFalse(data.isShown)
        }
    }

    func testALiftWithNothingEnteredIsAwaitingTheAthlete() {
        let data = MuscleGroupEntryData.resolve(
            activityType: .traditionalStrengthTraining,
            entry: nil
        )
        XCTAssertEqual(data.state, .awaitingEntry)
        XCTAssertTrue(data.isShown)
        XCTAssertNil(data.groups)
    }

    func testALiftWithGroupsEnteredShowsThem() throws {
        let data = MuscleGroupEntryData.resolve(
            activityType: .traditionalStrengthTraining,
            entry: try entry([.chest, .arms])
        )
        XCTAssertEqual(data.state, .entered([.chest, .arms]))
        XCTAssertEqual(data.groups, [.chest, .arms])
    }

    // MARK: - Copy

    /// The prompt is the feature's onboarding (A22): a lift the athlete has not answered
    /// for must ask a question, not show a blank.
    func testTheWaitingStateAsksAQuestionRatherThanShowingABlank() {
        let data = MuscleGroupEntryData.resolve(activityType: .traditionalStrengthTraining, entry: nil)
        XCTAssertEqual(data.headline, MuscleGroupEntryCopy.awaitingEntryHeadline)
        XCTAssertFalse(data.headline.isEmpty)
        XCTAssertFalse(data.detail.isEmpty)
        XCTAssertEqual(data.actionTitle, MuscleGroupEntryCopy.setAction)
    }

    /// Once answered, the section reads back the answer and offers to change it — the
    /// two states must not share a headline, or the screen would look unchanged after
    /// the athlete had told it something.
    func testTheEnteredStateReadsBackTheAnswer() throws {
        let data = MuscleGroupEntryData.resolve(
            activityType: .traditionalStrengthTraining,
            entry: try entry([.chest, .back])
        )
        XCTAssertEqual(data.headline, "Chest and back")
        XCTAssertNotEqual(data.headline, MuscleGroupEntryCopy.awaitingEntryHeadline)
        XCTAssertEqual(data.actionTitle, MuscleGroupEntryCopy.changeAction)
        XCTAssertNotEqual(data.detail, MuscleGroupEntryCopy.awaitingEntryDetail)
    }

    /// The verdict header and the section ask the same question in the same words —
    /// one screen, one voice — and the header's *reason* is its own sentence, because
    /// the two surfaces are explaining different things (why there is no score, versus
    /// why the app is asking).
    func testTheHeaderAndTheSectionAskTheSameQuestionAndGiveDifferentReasons() {
        XCTAssertNotEqual(
            MuscleGroupEntryCopy.awaitingEntryVerdictDetail,
            MuscleGroupEntryCopy.awaitingEntryDetail
        )
        for line in [
            MuscleGroupEntryCopy.awaitingEntryHeadline,
            MuscleGroupEntryCopy.awaitingEntryDetail,
            MuscleGroupEntryCopy.awaitingEntryVerdictDetail,
            MuscleGroupEntryCopy.enteredDetail,
            MuscleGroupEntryCopy.editorFooter,
        ] {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains(where: \.isNewline), "\(line) must be a single line")
        }
    }

    func testTheAccessibilityLabelReadsAsOneSentence() {
        let waiting = MuscleGroupEntryData.resolve(activityType: .traditionalStrengthTraining, entry: nil)
        XCTAssertTrue(waiting.accessibilityLabel.contains(MuscleGroupEntryCopy.sectionTitle))
        XCTAssertTrue(waiting.accessibilityLabel.contains(MuscleGroupEntryCopy.awaitingEntryHeadline))
        XCTAssertTrue(waiting.accessibilityLabel.contains(MuscleGroupEntryCopy.awaitingEntryDetail))
    }

    // MARK: - Naming the groups

    func testTheDisplayNamesAreTheOnesThePlanScreenAlreadyUses() {
        XCTAssertEqual(
            MuscleGroup.allCases.map(\.displayName),
            ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"]
        )
    }

    /// One canonical order, so the same session does not read "shoulders, chest" one
    /// launch and "chest, shoulders" the next.
    func testGroupsAreDescribedInACanonicalOrder() {
        XCTAssertEqual(MuscleGroupEntryCopy.describe([.legs]), "Legs")
        XCTAssertEqual(MuscleGroupEntryCopy.describe([.shoulders, .chest]), "Chest and shoulders")
        XCTAssertEqual(
            MuscleGroupEntryCopy.describe([.core, .chest, .back]),
            "Chest, back and core"
        )
        XCTAssertEqual(
            MuscleGroupEntryCopy.describe([.back, .chest, .core]),
            MuscleGroupEntryCopy.describe([.core, .back, .chest])
        )
    }

    /// The editor's empty state, and the only place an empty set is ever described: a
    /// stored entry can never hold zero groups.
    func testAnEmptySelectionIsDescribedAsSuch() {
        XCTAssertEqual(MuscleGroupEntryCopy.describe([]), MuscleGroupEntryCopy.noneSelected)
    }

    // MARK: - The picker's rules

    func testAFreshSelectionStartsFromWhatIsAlreadyRecorded() throws {
        let data = MuscleGroupEntryData.resolve(
            activityType: .traditionalStrengthTraining,
            entry: try entry([.legs, .core])
        )
        XCTAssertEqual(data.selection.groups, [.legs, .core])
    }

    func testAWaitingSelectionStartsEmpty() {
        let data = MuscleGroupEntryData.resolve(activityType: .traditionalStrengthTraining, entry: nil)
        XCTAssertTrue(data.selection.groups.isEmpty)
        XCTAssertNil(data.selection.recorded)
    }

    func testTogglingAddsAndRemoves() {
        var selection = MuscleGroupSelection(recorded: nil)
        selection.toggle(.chest)
        XCTAssertTrue(selection.contains(.chest))
        selection.toggle(.back)
        XCTAssertEqual(selection.groups, [.chest, .back])
        selection.toggle(.chest)
        XCTAssertEqual(selection.groups, [.back])
    }

    /// "I trained nothing" must not be reachable from the picker either.
    func testAnEmptySelectionCannotBeSaved() {
        var selection = MuscleGroupSelection(recorded: [.chest])
        XCTAssertFalse(selection.canSave, "an unchanged selection is not worth a record")
        selection.toggle(.chest)
        XCTAssertTrue(selection.groups.isEmpty)
        XCTAssertFalse(selection.canSave)
    }

    /// Entries are additive, so re-saving the same set would grow the log by a record
    /// that says nothing.
    func testAnUnchangedSelectionCannotBeSavedButAChangedOneCan() {
        var selection = MuscleGroupSelection(recorded: [.chest, .back])
        XCTAssertFalse(selection.canSave)
        selection.toggle(.arms)
        XCTAssertTrue(selection.canSave)
        selection.toggle(.arms)
        XCTAssertFalse(selection.canSave)
    }

    /// The picker's Save button is a convenience, not the guard: the type refuses an
    /// empty entry whatever a view does.
    func testASelectionCannotMintAnEmptyEntry() {
        let selection = MuscleGroupSelection(recorded: nil)
        XCTAssertThrowsError(
            try selection.entry(
                id: Fixture.muscleGroupEntryID,
                workoutID: Fixture.workoutID,
                recordedAt: Fixture.epoch
            )
        )
    }

    func testASelectionMintsTheEntryItShows() throws {
        var selection = MuscleGroupSelection(recorded: nil)
        selection.toggle(.shoulders)
        selection.toggle(.arms)
        let minted = try selection.entry(
            id: Fixture.muscleGroupEntryID,
            workoutID: Fixture.workoutID,
            recordedAt: Fixture.at(30)
        )
        XCTAssertEqual(minted.groups, [.shoulders, .arms])
        XCTAssertEqual(minted.workoutID, Fixture.workoutID)
        XCTAssertEqual(minted.recordedAt, Fixture.at(30))
        XCTAssertEqual(selection.summary, "Shoulders and arms")
    }
}
