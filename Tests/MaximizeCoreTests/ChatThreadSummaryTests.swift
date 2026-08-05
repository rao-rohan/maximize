import Foundation
import XCTest
@testable import MaximizeCore

/// §2.4 / §2.3: how a thread gets its name and what a list row renders.
///
/// Every assertion here is a pure function of stored data. That is the point of the
/// ticket: *a model call to title a thread is rejected*, so titling has to be something
/// CI can check on every commit rather than something a human reads in a screenshot.
final class ChatThreadTitleTests: XCTestCase {

    private func trainingThread(
        scope: TrainingScope,
        messages: [ChatMessage] = []
    ) throws -> ChatThread {
        try Fixture.thread(subject: .training(scope), messages: messages)
    }

    private var august: TrainingScope {
        get throws { try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)) }
    }

    // MARK: - A workout thread names the run

    func testAWorkoutThreadIsTitledByItsDateAndActivityType() throws {
        let thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        let title = ChatThreadTitle.derive(
            for: thread,
            workoutFacts: WorkoutThreadFacts(day: try Fixture.day(2026, 8, 3), activityType: .running)
        )
        XCTAssertEqual(title, "3 Aug 2026 · Running")
    }

    func testAnIndoorRunIsNamedAsItself() throws {
        XCTAssertEqual(
            ChatThreadTitle.workout(
                WorkoutThreadFacts(day: try Fixture.day(2026, 1, 12), activityType: .treadmillRunning)
            ),
            "12 Jan 2026 · Treadmill running"
        )
    }

    /// HealthKit gains activity types every release; one we have never heard of must
    /// still print something a person can read (`ActivityType` is a string wrapper for
    /// exactly this reason).
    func testAnUnknownActivityTypeStillProducesAReadableTitle() throws {
        XCTAssertEqual(
            ChatThreadTitle.workout(
                WorkoutThreadFacts(
                    day: try Fixture.day(2026, 3, 9),
                    activityType: ActivityType(rawValue: "paddling")
                )
            ),
            "9 Mar 2026 · Paddling"
        )
    }

    /// Unreachable in practice — deleting a workout deletes its thread — so this pins
    /// the fallback as an honest placeholder rather than a crash or a blank row.
    func testAWorkoutThreadWithNoResolvableRunFallsBackRatherThanFailing() throws {
        let thread = try Fixture.thread(subject: .workout(Fixture.workoutID))
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "Workout")
    }

    /// A run's title never depends on the conversation: there is one thread per run, so
    /// the title has to identify the run.
    func testAWorkoutThreadIsNotTitledByWhatWasAskedAboutIt() throws {
        let facts = WorkoutThreadFacts(day: try Fixture.day(2026, 8, 3), activityType: .running)
        let thread = try Fixture.thread(
            subject: .workout(Fixture.workoutID),
            messages: [try Fixture.message(.user, "Why did my heart rate climb after mile 3?", at: 0)]
        )
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: facts), "3 Aug 2026 · Running")
    }

    // MARK: - A training thread names the question

    func testAnEmptyTrainingThreadFallsBackToItsIntervalLabel() throws {
        let thread = try trainingThread(scope: try august)
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "1 – 31 Aug 2026")
    }

    /// The seed context is a `.system` turn and is not what the athlete said.
    func testATrainingThreadWithOnlyASeedStillFallsBackToTheLabel() throws {
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.system, "Training roll-up for August…", at: 0)]
        )
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "1 – 31 Aug 2026")
    }

    func testAShortOpeningQuestionBecomesTheTitleVerbatim() throws {
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, "Has my drift flattened?", at: 0)]
        )
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "Has my drift flattened?")
    }

    /// The title is the *first* thing asked, not the latest — a conversation keeps its
    /// name as it grows.
    func testTheTitleIsTheFirstQuestionAndDoesNotChangeAsTheThreadGrows() throws {
        var thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, "Has my drift flattened?", at: 0)]
        )
        thread = try thread.appending(Fixture.message(.assistant, "Slightly, over four weeks.", at: 10))
        thread = try thread.appending(Fixture.message(.user, "What about cadence?", at: 20))

        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "Has my drift flattened?")
    }

    // MARK: - Truncation

    func testALongQuestionIsCutOnAWordBoundary() throws {
        let question = "Has my heart rate drift flattened out over the last four weeks of easy running?"
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, question, at: 0)]
        )
        let title = ChatThreadTitle.derive(for: thread, workoutFacts: nil)

        XCTAssertEqual(title, "Has my heart rate drift flattened out over the…")
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertFalse(title.hasSuffix(" …"), "no dangling space before the ellipsis")
        XCTAssertLessThanOrEqual(title.count, ChatThreadTitle.maximumLength + 1)
        XCTAssertTrue(
            question.hasPrefix(String(title.dropLast())),
            "the kept text is a prefix of what was actually asked"
        )
    }

    /// A word longer than the whole budget has to be cut somewhere. The rule degrades to
    /// a hard cut rather than returning something over budget.
    func testAWordLongerThanTheBudgetIsCutHard() throws {
        let question = "Supercalifragilisticexpialidociousandthensomemoreletterstomakeitverylongindeed yes"
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, question, at: 0)]
        )
        let title = ChatThreadTitle.derive(for: thread, workoutFacts: nil)

        XCTAssertEqual(title.count, ChatThreadTitle.maximumLength + 1)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    /// Collapsing happens before truncation, or a row's whole budget is spent on the
    /// blank lines a pasted question happens to start with.
    func testNewlinesAndRunsOfSpacesCollapseBeforeTruncation() throws {
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, "  Has   my\n\n  drift\tflattened?  ", at: 0)]
        )
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), "Has my drift flattened?")
    }

    func testExactlyTheBudgetIsNotTruncated() throws {
        let question = String(repeating: "a", count: ChatThreadTitle.maximumLength)
        let thread = try trainingThread(
            scope: try august,
            messages: [try Fixture.message(.user, question, at: 0)]
        )
        XCTAssertEqual(ChatThreadTitle.derive(for: thread, workoutFacts: nil), question)
    }
}

/// §2.2 / §3.6(b): the sheet's subtitle.
final class ChatThreadSubtitleTests: XCTestCase {

    func testAWorkoutThreadsSubtitleNamesWhatItIsOf() throws {
        XCTAssertEqual(ChatThreadSubtitle.text(for: .workout(Fixture.workoutID)), "This run")
    }

    func testATrainingThreadsSubtitleStatesTheFrozenWindow() throws {
        let scope = try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))
        XCTAssertEqual(ChatThreadSubtitle.text(for: .training(scope)), scope.label)
    }

    /// §3.6(b)'s whole point: the title can drift to "what was asked", so the subtitle
    /// has to keep stating the window on its own, independent of any messages.
    func testTheSubtitleDoesNotDependOnWhatWasAsked() throws {
        let scope = try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))
        let emptyThread = ChatSubject.training(scope)
        XCTAssertEqual(ChatThreadSubtitle.text(for: emptyThread), scope.label)
    }
}

/// The value a thread-list row renders from (§2.3).
final class ChatThreadSummaryTests: XCTestCase {

    func testASummaryCarriesEveryFieldTheRowDraws() throws {
        let thread = try Fixture.thread(
            subject: .workout(Fixture.workoutID),
            messages: [
                try Fixture.message(.system, "Workout context…", at: 0),
                try Fixture.message(.user, "Was that on plan?", at: 5),
                try Fixture.message(.assistant, "Yes — Tuesday is an 8 km easy run.", at: 9),
            ]
        )
        let summary = ChatThreadSummary(
            thread,
            workoutFacts: WorkoutThreadFacts(day: try Fixture.day(2026, 8, 3), activityType: .running)
        )

        XCTAssertEqual(summary.id, thread.id)
        XCTAssertEqual(summary.subject, .workout(Fixture.workoutID))
        XCTAssertEqual(summary.title, "3 Aug 2026 · Running")
        XCTAssertEqual(summary.lastActivityAt, Fixture.at(9))
        XCTAssertEqual(summary.preview, "Yes — Tuesday is an 8 km easy run.")
    }

    func testAThreadNobodyHasSpokenInHasNoPreview() throws {
        let summary = ChatThreadSummary(try Fixture.thread(subject: .workout(Fixture.workoutID)))
        XCTAssertNil(summary.preview)
    }

    /// The seed is not a bubble, so it is not a preview either — a row must never show
    /// the athlete a fact sheet they never wrote.
    func testTheSeedContextIsNeverPreviewed() throws {
        let thread = try Fixture.thread(
            subject: .training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))),
            messages: [try Fixture.message(.system, "Plan version 3; 12 runs in scope…", at: 0)]
        )
        XCTAssertNil(ChatThreadSummary(thread).preview)
    }

    func testALongReplyIsPreviewedAsOneTruncatedLine() throws {
        let reply = """
            Your average heart rate over that block was 148 bpm,
            which sits four beats above the cap your plan sets,
            and the drift figure follows from it.
            """
        let thread = try Fixture.thread(
            subject: .training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))),
            messages: [
                try Fixture.message(.user, "Why was August marginal?", at: 0),
                try Fixture.message(.assistant, reply, at: 10),
            ]
        )
        let preview = try XCTUnwrap(ChatThreadSummary(thread).preview)

        XCTAssertEqual(
            preview,
            "Your average heart rate over that block was 148 bpm, which sits four beats above the cap your plan…"
        )
        XCTAssertFalse(preview.contains("\n"), "a row draws one line")
        XCTAssertLessThanOrEqual(preview.count, ChatThreadSummary.maximumPreviewLength + 1)
    }

    // MARK: - Ordering

    func testSortingIsNewestFirst() throws {
        let oldest = ChatThreadSummary(try Fixture.thread(lastActivityAt: Fixture.at(0)))
        let newest = ChatThreadSummary(try Fixture.thread(lastActivityAt: Fixture.at(1_000)))
        let middle = ChatThreadSummary(try Fixture.thread(lastActivityAt: Fixture.at(500)))

        XCTAssertEqual(
            ChatThreadSummary.sortedByActivity([oldest, newest, middle]).map(\.lastActivityAt),
            [Fixture.at(1_000), Fixture.at(500), Fixture.at(0)]
        )
    }

    /// A sort with no total order lets a list reshuffle between two reads of identical
    /// data — the class of defect MAX-048 was filed for.
    ///
    /// The direction is not arbitrary: it matches `mostRecentThread(for:)`, which takes
    /// the maximum, so the list's top row is the thread the Ask button opens.
    /// `ChatThreadRepositoryTests` pins the two against each other.
    // MARK: - MAX-150: the row's absence copy

    /// `ChatThreadListCopy.noMessagesYetPreview` is what a nil `preview` stands for on
    /// the row — both the row's visible caption and its VoiceOver label read this one
    /// constant, so the two cannot state the absence two different ways.
    func testNoMessagesYetPreviewIsNotEmpty() {
        XCTAssertFalse(ChatThreadListCopy.noMessagesYetPreview.isEmpty)
    }

    func testTiesAreBrokenByIdentifierSoTheOrderIsTotal() throws {
        let low = ChatThreadSummary(try Fixture.thread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            lastActivityAt: Fixture.epoch
        ))
        let high = ChatThreadSummary(try Fixture.thread(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID(),
            lastActivityAt: Fixture.epoch
        ))

        XCTAssertEqual(ChatThreadSummary.sortedByActivity([low, high]).map(\.id), [high.id, low.id])
        XCTAssertEqual(ChatThreadSummary.sortedByActivity([high, low]).map(\.id), [high.id, low.id])
    }
}
