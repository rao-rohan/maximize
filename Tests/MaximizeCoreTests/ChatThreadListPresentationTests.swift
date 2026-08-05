import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-153, §2.3: how the thread list groups, orders, dates and words itself.
///
/// Every assertion here replaces something the view used to decide in its `body` — the
/// relative timestamp, the nil-preview fallback, the VoiceOver sentence — plus the
/// grouping the list did not have at all. The boundaries (a thread at exactly seven days,
/// one dated tomorrow, two sharing an instant) are the cases nobody finds by scrolling a
/// list on a device.
final class ChatThreadListPresentationTests: XCTestCase {

    private let zone = TimeZone.gmt

    /// 2026-08-05T12:00:00Z, a Wednesday — midday, so a "yesterday" fixture cannot be
    /// pushed into today by a few hours of arithmetic.
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    private func date(daysAgo: Double = 0, hoursAgo: Double = 0, minutesAgo: Double = 0) -> Date {
        now.addingTimeInterval(-(daysAgo * 86_400 + hoursAgo * 3_600 + minutesAgo * 60))
    }

    private func summary(
        id: UUID = UUID(),
        subject: ChatSubject = .workout(Fixture.workoutID),
        title: String = "A thread",
        at date: Date,
        preview: String? = "The last thing said"
    ) -> ChatThreadSummary {
        ChatThreadSummary(id: id, subject: subject, title: title, lastActivityAt: date, preview: preview)
    }

    private var august: TrainingScope {
        get throws { try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)) }
    }

    // MARK: - Banding

    func testEachBandTakesTheThreadsItShould() {
        let sections = ChatThreadListPresentation.sections(
            for: [
                summary(title: "this morning", at: date(daysAgo: 0, hoursAgo: 3)),
                summary(title: "yesterday", at: date(daysAgo: 1)),
                summary(title: "four days", at: date(daysAgo: 4)),
                summary(title: "a fortnight", at: date(daysAgo: 14)),
                summary(title: "last spring", at: date(daysAgo: 120)),
            ],
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(
            sections.map(\.recency),
            [.today, .yesterday, .previousSevenDays, .previousThirtyDays, .earlier]
        )
        XCTAssertEqual(
            sections.map(\.title),
            ["Today", "Yesterday", "Previous 7 days", "Previous 30 days", "Earlier"]
        )
        XCTAssertEqual(sections.map { $0.rows.count }, [1, 1, 1, 1, 1])
    }

    /// The boundaries, named. Seven days is the last day of "Previous 7 days" and thirty
    /// is the last of "Previous 30 days" — an off-by-one here moves a row between two
    /// headings that both look plausible, which is why it is asserted rather than read.
    func testTheBandBoundariesAreWhereTheHeadingsSayTheyAre() throws {
        let today = try Fixture.day(2026, 8, 5)
        func band(daysAgo: Int) throws -> ChatThreadRecency {
            ChatThreadRecency.band(for: try today.adding(days: -daysAgo), today: today)
        }

        XCTAssertEqual(try band(daysAgo: 0), .today)
        XCTAssertEqual(try band(daysAgo: 1), .yesterday)
        XCTAssertEqual(try band(daysAgo: 2), .previousSevenDays)
        XCTAssertEqual(try band(daysAgo: 7), .previousSevenDays)
        XCTAssertEqual(try band(daysAgo: 8), .previousThirtyDays)
        XCTAssertEqual(try band(daysAgo: 30), .previousThirtyDays)
        XCTAssertEqual(try band(daysAgo: 31), .earlier)
    }

    /// A device whose clock moved backwards, or a record written across a zone change.
    /// A "Later" heading above "Today" would be a section header explaining a bug.
    func testAThreadDatedInTheFutureBandsAsToday() throws {
        let today = try Fixture.day(2026, 8, 5)
        XCTAssertEqual(ChatThreadRecency.band(for: try today.adding(days: 1), today: today), .today)
    }

    func testAnEmptyBandIsNotEmittedAsAHeadingWithNothingUnderIt() {
        let sections = ChatThreadListPresentation.sections(
            for: [summary(at: date(daysAgo: 200))],
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(sections.map(\.recency), [.earlier])
    }

    func testNoThreadsProducesNoSections() {
        XCTAssertTrue(ChatThreadListPresentation.sections(for: [], now: now, timeZone: zone).isEmpty)
    }

    // MARK: - Ordering

    /// Handed in backwards, ordered forwards. Banding is done on a re-sorted list rather
    /// than on whatever order the store returned, so a section cannot read oldest-first.
    func testRowsAreNewestFirstWithinABandRegardlessOfInputOrder() {
        let sections = ChatThreadListPresentation.sections(
            for: [
                summary(title: "oldest", at: date(daysAgo: 5)),
                summary(title: "newest", at: date(daysAgo: 3)),
                summary(title: "middle", at: date(daysAgo: 4)),
            ],
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.rows.map(\.title), ["newest", "middle", "oldest"])
    }

    /// The tie is `ChatThreadSummary.sortedByActivity`'s, unchanged — the same one
    /// `mostRecentThread(for:)` uses, so the row at the top of a band is the thread the
    /// Ask button would open.
    func testThreadsSharingAnInstantKeepTheStoredTiebreak() {
        let instant = date(daysAgo: 2)
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID()

        let sections = ChatThreadListPresentation.sections(
            for: [summary(id: low, title: "low", at: instant), summary(id: high, title: "high", at: instant)],
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(sections.first?.rows.map(\.title), ["high", "low"])
    }

    // MARK: - The compact timestamp

    func testTheTimestampLadderReadsAsMessagesDoes() throws {
        func stamp(_ date: Date) -> String {
            ChatThreadListPresentation.compactTimestamp(for: date, now: now, timeZone: zone)
        }

        XCTAssertEqual(stamp(date(minutesAgo: 0)), "now")
        XCTAssertEqual(stamp(date(minutesAgo: 0.5)), "now")
        XCTAssertEqual(stamp(date(minutesAgo: 12)), "12m")
        XCTAssertEqual(stamp(date(minutesAgo: 59)), "59m")
        XCTAssertEqual(stamp(date(hoursAgo: 5)), "5h")
        XCTAssertEqual(stamp(date(daysAgo: 1)), "Yesterday")
        // 2026-08-05 is a Wednesday; three days back is the Sunday.
        XCTAssertEqual(stamp(date(daysAgo: 3)), "Sun")
        XCTAssertEqual(stamp(date(daysAgo: 6)), "Thu")
        XCTAssertEqual(stamp(date(daysAgo: 7)), "29 Jul")
        XCTAssertEqual(stamp(date(daysAgo: 300)), "9 Oct 2025")
    }

    /// Clock skew reads as "now" rather than as a negative age.
    func testAFutureTimestampReadsAsNow() {
        XCTAssertEqual(
            ChatThreadListPresentation.compactTimestamp(
                for: now.addingTimeInterval(3_600),
                now: now,
                timeZone: zone
            ),
            "now"
        )
    }

    /// The athlete's zone, not UTC's: a conversation at 00:30 belongs to the day they
    /// were living. Same instant, two zones, two answers.
    func testTheTimestampIsResolvedInTheAthletesZone() throws {
        // 2026-08-05T00:30:00Z. Read in UTC that is 11½ hours ago today; read in
        // California (UTC−7 in August) it is half past five the previous evening.
        let justAfterMidnightUTC = Date(timeIntervalSince1970: 1_785_889_800)

        XCTAssertEqual(
            ChatThreadListPresentation.compactTimestamp(for: justAfterMidnightUTC, now: now, timeZone: .gmt),
            "11h"
        )
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(
            ChatThreadListPresentation.compactTimestamp(for: justAfterMidnightUTC, now: now, timeZone: losAngeles),
            "Yesterday"
        )
    }

    // MARK: - What a row carries

    func testATrainingRowStatesItsFrozenWindowBesideItsTitle() throws {
        let row = ChatThreadListPresentation.row(
            for: summary(subject: .training(try august), title: "Why did my HR climb", at: date(hoursAgo: 2)),
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(row.title, "Why did my HR climb")
        XCTAssertEqual(try XCTUnwrap(row.scope), "1 – 31 Aug 2026")
        XCTAssertEqual(row.kind, .training)
        XCTAssertEqual(row.glyphSystemImageName, "chart.line.uptrend.xyaxis")
    }

    /// The scope on the row is the same string the sheet's subtitle shows once the thread
    /// is open. Two spellings of one window is exactly the drift §3.6(b) is built to stop.
    func testTheRowsScopeIsTheSheetsSubtitle() throws {
        let subject = ChatSubject.training(try august)
        let row = ChatThreadListPresentation.row(
            for: summary(subject: subject, at: date(hoursAgo: 1)),
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(try XCTUnwrap(row.scope), ChatThreadSubtitle.text(for: subject))
    }

    /// The sheet states "This run" under a workout thread's title because a sheet has one
    /// title and §3.6(b) wants the scope stated unconditionally. A row has a glyph and a
    /// kind beside it, and its title is already the run's date — so the third line would
    /// be the second line again.
    func testAWorkoutRowDropsAScopeItsTitleAlreadyStates() {
        let row = ChatThreadListPresentation.row(
            for: summary(subject: .workout(Fixture.workoutID), title: "3 Aug 2026 · Running", at: date(hoursAgo: 1)),
            now: now,
            timeZone: zone
        )
        XCTAssertNil(row.scope)
        XCTAssertEqual(row.glyphSystemImageName, "figure.run")
    }

    /// A training thread nobody has spoken in yet is *titled* by its window
    /// (`ChatThreadTitle.training`'s fallback), so stating the scope beneath it would
    /// print the same string twice.
    func testAnUnspokenTrainingRowDoesNotPrintItsWindowTwice() throws {
        let scope = try august
        let row = ChatThreadListPresentation.row(
            for: summary(
                subject: .training(scope),
                title: ChatThreadTitle.training(scope: scope, firstUserMessage: nil),
                at: date(hoursAgo: 1),
                preview: nil
            ),
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(row.title, "1 – 31 Aug 2026")
        XCTAssertNil(row.scope)
    }

    /// Absence is a designed state, and the row says which of the two it is drawing so the
    /// view can weight it without re-testing the string.
    func testAThreadNobodyHasSpokenInSaysSoRatherThanRenderingABlank() {
        let row = ChatThreadListPresentation.row(
            for: summary(at: date(hoursAgo: 1), preview: nil),
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(row.preview, ChatThreadListCopy.noMessagesYetPreview)
        XCTAssertTrue(row.previewIsAbsence)
    }

    func testASpokenThreadIsNotMarkedAsAnAbsence() {
        let row = ChatThreadListPresentation.row(
            for: summary(at: date(hoursAgo: 1), preview: "Held the cap"),
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(row.preview, "Held the cap")
        XCTAssertFalse(row.previewIsAbsence)
    }

    // MARK: - VoiceOver

    /// Everything a sighted athlete reads on the row, in one sentence, including the
    /// glyph — a shape that distinguishes two kinds of thread at a glance has to exist in
    /// words too. The timestamp phrase is injected because it is the platform's, not this
    /// package's (see the method's own note).
    func testTheSpokenRowCarriesEveryChannelTheVisualRowDoes() throws {
        let row = ChatThreadListPresentation.row(
            for: summary(
                subject: .training(try august),
                title: "Why did my HR climb",
                at: date(hoursAgo: 3),
                preview: "Drift was 4.2% across the block"
            ),
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(
            row.accessibilityLabel(spokenTimestamp: "3 hours ago"),
            "Training chat. Why did my HR climb. 1 – 31 Aug 2026. 3 hours ago. Drift was 4.2% across the block"
        )
    }

    func testTheSpokenRowStatesTheAbsenceRatherThanTrailingOff() {
        let row = ChatThreadListPresentation.row(
            for: summary(title: "3 Aug 2026 · Running", at: date(hoursAgo: 1), preview: nil),
            now: now,
            timeZone: zone
        )
        XCTAssertTrue(row.accessibilityLabel(spokenTimestamp: "an hour ago").hasSuffix("No messages yet"))
    }

    /// A row with no scope line to draw has no scope phrase to speak either — the spoken
    /// sentence follows what is on screen rather than restating something dropped for
    /// being redundant.
    func testTheSpokenRowOmitsAScopeTheRowItselfDoesNotShow() {
        let row = ChatThreadListPresentation.row(
            for: summary(title: "3 Aug 2026 · Running", at: date(hoursAgo: 1), preview: "Held the cap"),
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(
            row.accessibilityLabel(spokenTimestamp: "an hour ago"),
            "Workout chat. 3 Aug 2026 · Running. an hour ago. Held the cap"
        )
    }
}
