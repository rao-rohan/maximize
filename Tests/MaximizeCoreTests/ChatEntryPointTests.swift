import Foundation
import XCTest
@testable import MaximizeCore

/// §2.1 / §7 — the persistent Ask button's subject and its wording.
///
/// The claim under test is the one MAX-098 exists to make true: **the button says which
/// pile of the athlete's data a tap is about to send, and it is right about it.** None
/// of that is verifiable by looking at a screen in CI, and all of it is verifiable here.
final class ChatEntryPointTests: XCTestCase {

    private var thisMonth: TrendInterval {
        get throws { try TrendInterval.thisMonth(today: Fixture.day(2026, 8, 17)) }
    }

    // MARK: - Which subject

    /// Every screen that is not a workout detail screen — the Workouts list, the
    /// Dashboard, the Plan tab, Settings — asks about training over the dashboard's
    /// current window (§2.1, A10).
    func testNoFocusedWorkoutAsksAboutTrainingOverTheCurrentInterval() throws {
        let interval = try thisMonth
        let entry = try XCTUnwrap(
            ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: interval)
        )

        XCTAssertEqual(entry.subject, .training(try TrainingScope(resolving: interval)))
        XCTAssertEqual(entry.label, "Ask")
    }

    /// On a workout detail screen the button changes subject to that run (§7.5).
    func testAFocusedWorkoutAsksAboutThatRun() throws {
        let entry = try XCTUnwrap(
            ChatEntryPoint.resolve(
                focus: ChatEntryPointFocus(workoutID: Fixture.workoutID),
                currentInterval: try thisMonth
            )
        )

        XCTAssertEqual(entry.subject, .workout(Fixture.workoutID))
        XCTAssertEqual(entry.label, "Ask about this run")
    }

    /// A run reached from the dashboard's calendar (MAX-108) is still a run: the focused
    /// workout wins over an interval that is also on screen behind it.
    func testAFocusedWorkoutWinsOverTheDashboardInterval() throws {
        let entry = try XCTUnwrap(
            ChatEntryPoint.resolve(
                focus: ChatEntryPointFocus(workoutID: Fixture.workoutID),
                currentInterval: try thisMonth
            )
        )
        XCTAssertEqual(entry.subject.kind, .workout)
    }

    /// A workout entry point needs no interval at all — pushing a run from a tab whose
    /// interval could not resolve must not silently drop the button.
    func testAFocusedWorkoutResolvesWithoutAnInterval() throws {
        let entry = try XCTUnwrap(
            ChatEntryPoint.resolve(
                focus: ChatEntryPointFocus(workoutID: Fixture.workoutID),
                currentInterval: nil
            )
        )
        XCTAssertEqual(entry.subject, .workout(Fixture.workoutID))
    }

    /// The one state with no subject to open: nothing focused and no window resolvable
    /// (`TrendIntervalSelectionModel.State.failed`). Unreachable on any date a device can
    /// be set to; stated rather than guessed at.
    func testNoFocusAndNoIntervalResolvesToNothing() {
        XCTAssertNil(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: nil))
    }

    /// The scope is frozen from the interval on screen at the moment the button is
    /// drawn, so stepping the dashboard back changes what a tap opens (§3.4).
    func testTheTrainingScopeTracksTheIntervalItWasResolvedFrom() throws {
        let august = try thisMonth
        let july = try august.previous()

        let inAugust = try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: august))
        let inJuly = try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: july))

        XCTAssertNotEqual(inAugust.subject, inJuly.subject)
        XCTAssertEqual(inJuly.subject, .training(try TrainingScope(resolving: july)))
    }

    // MARK: - What it says

    /// The two labels must be different, or the button has stopped telling the athlete
    /// anything — which is the entire justification for the label's pixels (§2.1).
    func testTheTwoSubjectsAreLabelledDifferently() throws {
        let training = try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: try thisMonth))
        let workout = try XCTUnwrap(
            ChatEntryPoint.resolve(focus: ChatEntryPointFocus(workoutID: Fixture.workoutID), currentInterval: try thisMonth)
        )

        XCTAssertNotEqual(training.label, workout.label)
        XCTAssertNotEqual(training.compactLabel, workout.compactLabel)
        XCTAssertNotEqual(training.accessibilityLabel, workout.accessibilityLabel)
    }

    /// Nothing the button can render is allowed to be blank — absence is a designed
    /// state everywhere else in this app, and a chrome control with no words is not one.
    func testEveryStringIsNonEmpty() throws {
        for entry in try bothEntryPoints() {
            XCTAssertFalse(entry.label.isEmpty)
            XCTAssertFalse(entry.compactLabel.isEmpty)
            XCTAssertFalse(entry.accessibilityLabel.isEmpty)
            XCTAssertFalse(entry.accessibilityHint.isEmpty)
        }
    }

    /// The compact form exists for a bar the system sizes and for the minimised tab bar.
    /// It is only useful if it is actually shorter — or identical, which is the training
    /// case's deliberate answer.
    func testTheCompactLabelIsNeverLongerThanTheFullOne() throws {
        for entry in try bothEntryPoints() {
            XCTAssertLessThanOrEqual(entry.compactLabel.count, entry.label.count)
        }
    }

    /// Dropping the verb is allowed; dropping the scope is not. "This run" still says
    /// which pile of data a tap sends — the ranking this type documents.
    func testTheCompactWorkoutLabelKeepsTheScope() throws {
        let workout = try XCTUnwrap(
            ChatEntryPoint.resolve(focus: ChatEntryPointFocus(workoutID: Fixture.workoutID), currentInterval: nil)
        )
        XCTAssertTrue(workout.compactLabel.lowercased().contains("run"), workout.compactLabel)
    }

    /// A VoiceOver user cannot glance at the screen behind the button, so "Ask" alone
    /// would be the one place this control tells them nothing.
    func testTheSpokenLabelNamesTheSubjectEvenWhenTheVisibleOneDoesNot() throws {
        let training = try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: try thisMonth))

        XCTAssertEqual(training.label, "Ask")
        XCTAssertNotEqual(training.accessibilityLabel, "Ask")
        XCTAssertTrue(training.accessibilityLabel.lowercased().contains("training"), training.accessibilityLabel)
    }

    /// §2.1's point, for the case where the visible label deliberately omits the window:
    /// the hint is where a training entry point states which days a tap is about.
    func testTheTrainingHintNamesTheWindow() throws {
        let interval = try thisMonth
        let training = try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: interval))

        XCTAssertTrue(
            training.accessibilityHint.contains(try TrainingScope(resolving: interval).label),
            training.accessibilityHint
        )
    }

    /// One control, one place, one icon — a glyph that changed as you navigated would
    /// read as a different control. Pinned so a later ticket has to argue with it.
    func testTheGlyphIsFixedAndWellFormed() {
        let name = ChatEntryPoint.glyphSystemImageName
        XCTAssertFalse(name.isEmpty)
        XCTAssertEqual(name, name.lowercased(), "SF Symbol names are lowercase: \(name)")
        XCTAssertFalse(name.contains(where: \.isWhitespace), "Whitespace in \(name)")
        XCTAssertNotEqual(
            name,
            ChatSubjectKind.workout.glyphSystemImageName,
            "The button's icon is not the thread list's per-subject glyph."
        )
    }

    // MARK: - Focus, and the ordering it has to survive

    func testFocusingAWorkoutHoldsIt() {
        var focus = ChatEntryPointFocus()
        focus.focus(Fixture.workoutID)
        XCTAssertEqual(focus.workoutID, Fixture.workoutID)
    }

    func testReleasingTheHeldWorkoutClearsIt() {
        var focus = ChatEntryPointFocus(workoutID: Fixture.workoutID)
        focus.release(Fixture.workoutID)
        XCTAssertNil(focus.workoutID)
    }

    /// The regression this type exists for. Paging from run A to run B in
    /// `DayWorkoutsView` can deliver `appear(B)` before `disappear(A)`; clearing
    /// unconditionally would leave the button reading "Ask" on a screen showing run B.
    func testALateDisappearanceOfThePreviousScreenDoesNotClearTheCurrentOne() {
        let runA = UUID()
        let runB = UUID()

        var focus = ChatEntryPointFocus(workoutID: runA)
        focus.focus(runB)      // B appeared first…
        focus.release(runA)    // …and only then did A report that it had gone.

        XCTAssertEqual(focus.workoutID, runB, "The screen the athlete is looking at lost its subject.")
    }

    /// The other ordering has to land in the same place.
    func testTheOppositeOrderingConvergesOnTheSameScreen() {
        let runA = UUID()
        let runB = UUID()

        var focus = ChatEntryPointFocus(workoutID: runA)
        focus.release(runA)
        focus.focus(runB)

        XCTAssertEqual(focus.workoutID, runB)
    }

    /// Popping back to a list clears the subject, so the button returns to "Ask".
    func testReleasingTheHeldWorkoutReturnsTheButtonToTraining() throws {
        var focus = ChatEntryPointFocus(workoutID: Fixture.workoutID)
        focus.release(Fixture.workoutID)

        let entry = try XCTUnwrap(ChatEntryPoint.resolve(focus: focus, currentInterval: try thisMonth))
        XCTAssertEqual(entry.subject.kind, .training)
        XCTAssertEqual(entry.label, "Ask")
    }

    // MARK: - Helpers

    private func bothEntryPoints() throws -> [ChatEntryPoint] {
        let interval = try thisMonth
        return [
            try XCTUnwrap(ChatEntryPoint.resolve(focus: ChatEntryPointFocus(), currentInterval: interval)),
            try XCTUnwrap(
                ChatEntryPoint.resolve(
                    focus: ChatEntryPointFocus(workoutID: Fixture.workoutID),
                    currentInterval: interval
                )
            ),
        ]
    }
}
