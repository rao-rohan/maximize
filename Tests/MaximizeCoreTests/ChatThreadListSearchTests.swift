import Foundation
import XCTest
@testable import MaximizeCore

/// §4.3, MAX-201: `.searchable` over titles and previews, filtered in the core.
///
/// The audit's warning was specific — the list's rows are banded by recency, and a
/// filter must not lose that banding or leave a header with nothing under it. Every
/// test here is built around that: `sections(for:matching:now:timeZone:)` is asked
/// for the *sections* a query produces, never the raw filtered list, so a test that
/// only checked "the right threads survived" could pass while the headers above them
/// were wrong or missing.
final class ChatThreadListSearchTests: XCTestCase {

    private let zone = TimeZone.gmt

    /// 2026-08-05T12:00:00Z, a Wednesday.
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    private func date(daysAgo: Double = 0) -> Date {
        now.addingTimeInterval(-daysAgo * 86_400)
    }

    private func summary(
        id: UUID = UUID(),
        title: String = "A thread",
        at date: Date,
        preview: String? = "The last thing said"
    ) -> ChatThreadSummary {
        ChatThreadSummary(
            id: id,
            subject: .workout(Fixture.workoutID),
            title: title,
            lastActivityAt: date,
            preview: preview
        )
    }

    // MARK: - Banding survives a filter

    /// The case the audit's warning is about, made concrete: threads across four bands,
    /// a query that matches one thread in each of three of them. The result must still
    /// carry three separate section headers, each with exactly the one row that
    /// matched — not a flat list, and not a header left standing over nothing.
    func testAFilterThatMatchesAcrossBandsKeepsEachBandSeparate() {
        let sections = ChatThreadListPresentation.sections(
            for: [
                summary(title: "Why did my HR climb today", at: date(daysAgo: 0)),
                summary(title: "Cadence question", at: date(daysAgo: 1)),
                summary(title: "HR drift on the long run", at: date(daysAgo: 4)),
                summary(title: "Plan review", at: date(daysAgo: 14)),
                summary(title: "HR cap discussion", at: date(daysAgo: 40)),
            ],
            matching: "HR",
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(sections.map(\.recency), [.today, .previousSevenDays, .earlier])
        XCTAssertEqual(sections.map { $0.rows.count }, [1, 1, 1])
        XCTAssertEqual(sections.flatMap { $0.rows.map(\.title) }, [
            "Why did my HR climb today",
            "HR drift on the long run",
            "HR cap discussion",
        ])
    }

    /// A band where every row is filtered out must disappear, not survive as a heading
    /// with nothing under it — MAX-153's own rule, now asked to hold for a subset.
    func testABandEmptiedByAFilterIsNotEmittedAsAHeadingOverNothing() {
        let sections = ChatThreadListPresentation.sections(
            for: [
                summary(title: "Cadence question", at: date(daysAgo: 0)),
                summary(title: "HR drift", at: date(daysAgo: 1)),
            ],
            matching: "HR",
            now: now,
            timeZone: zone
        )

        XCTAssertEqual(sections.map(\.recency), [.yesterday])
        XCTAssertEqual(sections.first?.rows.map(\.title), ["HR drift"])
    }

    /// A query nothing matches produces no sections at all — the designed absence state
    /// is the view's decision, but the core must not hand back a heading with no rows to
    /// justify one.
    func testAQueryNothingMatchesProducesNoSections() {
        let sections = ChatThreadListPresentation.sections(
            for: [summary(title: "Cadence question", at: date(daysAgo: 0))],
            matching: "nonexistent",
            now: now,
            timeZone: zone
        )
        XCTAssertTrue(sections.isEmpty)
    }

    /// A blank query — nothing typed, or only whitespace — is "not searching", not "a
    /// filter matching nothing": the unfiltered list, banding and all.
    func testABlankQueryReturnsTheUnfilteredList() {
        let summaries = [
            summary(title: "Cadence question", at: date(daysAgo: 0)),
            summary(title: "Plan review", at: date(daysAgo: 14)),
        ]
        let unfiltered = ChatThreadListPresentation.sections(for: summaries, now: now, timeZone: zone)
        XCTAssertEqual(
            ChatThreadListPresentation.sections(for: summaries, matching: "", now: now, timeZone: zone),
            unfiltered
        )
        XCTAssertEqual(
            ChatThreadListPresentation.sections(for: summaries, matching: "   ", now: now, timeZone: zone),
            unfiltered
        )
    }

    /// Ordering within a surviving band is unaffected by filtering — newest first,
    /// exactly as the unfiltered list orders it.
    func testFilteredRowsKeepTheUnfilteredOrderWithinABand() {
        let sections = ChatThreadListPresentation.sections(
            for: [
                summary(title: "HR — oldest", at: date(daysAgo: 5)),
                summary(title: "Cadence — not a match", at: date(daysAgo: 4)),
                summary(title: "HR — newest", at: date(daysAgo: 3)),
            ],
            matching: "HR",
            now: now,
            timeZone: zone
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.rows.map(\.title), ["HR — newest", "HR — oldest"])
    }

    // MARK: - What matches

    func testATitleMatchIsCaseInsensitive() {
        XCTAssertTrue(
            ChatThreadListPresentation.matches(summary(title: "Why did my Heart Rate climb", at: now), query: "heart rate")
        )
    }

    func testAPreviewMatchCountsEvenWhenTheTitleDoesNot() {
        let summary = summary(title: "Cadence question", at: now, preview: "Drift was 4.2% across the block")
        XCTAssertTrue(ChatThreadListPresentation.matches(summary, query: "drift"))
    }

    func testNoMatchInEitherFieldFails() {
        let summary = summary(title: "Cadence question", at: now, preview: "Stayed under cap")
        XCTAssertFalse(ChatThreadListPresentation.matches(summary, query: "strain"))
    }

    /// A thread nobody has spoken in yet has a nil preview — matching must not force
    /// it, only fall back to no match from that field.
    func testAThreadWithNoPreviewIsMatchedOnTitleAlone() {
        let summary = summary(title: "HR cap discussion", at: now, preview: nil)
        XCTAssertTrue(ChatThreadListPresentation.matches(summary, query: "hr"))
        XCTAssertFalse(ChatThreadListPresentation.matches(summary, query: "drift"))
    }

    /// The scope line a training row can show is not searched — §4.3 asks for titles
    /// and previews, not a third field a row draws.
    func testTheWindowLabelIsNotItselfSearchedBeyondWhatTheTitleAlreadyStates() throws {
        let scope = try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))
        let summary = ChatThreadSummary(
            id: UUID(),
            subject: .training(scope),
            title: "Cadence question",
            lastActivityAt: now,
            preview: "Stayed under cap"
        )
        XCTAssertFalse(ChatThreadListPresentation.matches(summary, query: "August"))
    }
}
