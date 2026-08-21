import Foundation
import XCTest
@testable import MaximizeCore

/// §6.8, MAX-201: which turns of a transcript get a day separator, and what it says.
///
/// `CalendarDay.days(until:)` is the zone-aware machinery MAX-180 already switched to
/// after finding one defect from fixed 86,400-second blocks standing in for a calendar
/// day (`MuscleFatigue`'s own note). The timezone-boundary fixture below reuses
/// `MuscleFatigueTests`' exact instants and its `Pacific/Honolulu` zone rather than
/// inventing a second pair, so the same class of bug cannot come back through a second,
/// unrelated feature that also happens to ask "how many days ago was this."
final class ChatTranscriptDaySeparatorTests: XCTestCase {

    private func message(_ content: String, at timestamp: Date) throws -> ChatMessage {
        try ChatMessage(id: UUID(), role: .user, content: content, timestamp: timestamp)
    }

    // MARK: - The timezone-boundary case (MAX-180's pattern)

    /// The case that motivates this file, restated for a transcript rather than a
    /// muscle-fatigue caption: a message sent Sunday 22:00 UTC, and a reply read back
    /// ten hours later, Monday 08:00 UTC. In UTC that is two different calendar days —
    /// "yesterday" and "today" — even though barely ten of the 86,400 seconds in a day
    /// separate the two instants that follow. The two rows must get two separators.
    func testASessionSpanningLateEveningToNextMorningGetsTwoSeparatorsInUTC() throws {
        let sundayTenPM = Date(timeIntervalSince1970: 1_786_917_600) // 2026-08-16T22:00:00Z
        let mondayEightAM = Date(timeIntervalSince1970: 1_786_953_600) // 2026-08-17T08:00:00Z
        XCTAssertEqual(mondayEightAM.timeIntervalSince(sundayTenPM), 10 * 3_600, "fixture sanity: 10 hours apart")

        let first = try message("Anything I should watch for tomorrow?", at: sundayTenPM)
        let second = try message("Good morning — following up", at: mondayEightAM)

        let labels = ChatTranscriptDaySeparators.labels(
            for: [first, second],
            now: mondayEightAM,
            timeZone: .gmt
        )

        XCTAssertEqual(labels[first.id], "Yesterday")
        XCTAssertEqual(labels[second.id], "Today")
    }

    /// **The same two instants, a different zone, a different calendar-correct
    /// answer** — proof this is genuinely timezone-aware rather than a closer
    /// approximation of the same bug. In Honolulu (UTC−10, no DST) both instants fall
    /// on the *same* local calendar day (2026-08-16): the first is local noon, the
    /// second is local 22:00 the same evening. Zero calendar days have passed there,
    /// so the second message gets no separator of its own — only the first does, for
    /// being the first message in the thread.
    func testTheSameTwoInstantsGetOneSeparatorInATenHourEarlierZone() throws {
        let sundayTenPM = Date(timeIntervalSince1970: 1_786_917_600) // 2026-08-16T22:00:00Z
        let mondayEightAM = Date(timeIntervalSince1970: 1_786_953_600) // 2026-08-17T08:00:00Z
        let honolulu = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))

        let first = try message("Anything I should watch for tomorrow?", at: sundayTenPM)
        let second = try message("Good morning — following up", at: mondayEightAM)

        let labels = ChatTranscriptDaySeparators.labels(
            for: [first, second],
            now: mondayEightAM,
            timeZone: honolulu
        )

        XCTAssertEqual(labels.count, 1, "only the first message should carry a separator in Honolulu: \(labels)")
        XCTAssertEqual(labels[first.id], "Today")
        XCTAssertNil(labels[second.id])
    }

    // MARK: - The ladder

    /// A thread whose every turn falls on one day gets exactly one separator: the
    /// first message always gets one, so a conversation states which day it belongs to
    /// whether or not it has ever been resumed.
    func testAThreadEntirelyWithinOneDayGetsExactlyOneSeparator() throws {
        let morning = Date(timeIntervalSince1970: 1_785_916_800) // 2026-08-05T08:00:00Z
        let first = try message("Question one", at: morning)
        let second = try message("Question two", at: morning.addingTimeInterval(3_600))
        let third = try message("Question three", at: morning.addingTimeInterval(7_200))

        let labels = ChatTranscriptDaySeparators.labels(
            for: [first, second, third],
            now: morning.addingTimeInterval(7_200),
            timeZone: .gmt
        )

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[first.id], "Today")
    }

    func testAMessageFromYesterdayReadsAsYesterday() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200) // 2026-08-05T12:00:00Z
        let yesterday = now.addingTimeInterval(-20 * 3_600)
        let turn = try message("A question", at: yesterday)

        let labels = ChatTranscriptDaySeparators.labels(for: [turn], now: now, timeZone: .gmt)
        XCTAssertEqual(labels[turn.id], "Yesterday")
    }

    /// Within the previous week, but not yesterday: the weekday name, matching the
    /// thread list's own compact stamp so the two surfaces read as one system.
    func testAMessageFromFourDaysAgoReadsAsItsWeekdayName() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200) // 2026-08-05T12:00:00Z, a Wednesday
        let fourDaysAgo = now.addingTimeInterval(-4 * 86_400)
        let turn = try message("A question", at: fourDaysAgo)

        let labels = ChatTranscriptDaySeparators.labels(for: [turn], now: now, timeZone: .gmt)
        // Four days before Wednesday 5 Aug is Saturday 1 Aug.
        XCTAssertEqual(labels[turn.id], "Sat")
    }

    /// Beyond a week, within the same year: a dated label with no year, matching
    /// `CalendarDayLabel.dayAndMonth`. Reuses `ChatThreadListPresentationTests`' own
    /// validated fixture for this exact offset (5 Aug 2026 minus 7 days is 29 Jul)
    /// rather than a second hand-computed one.
    func testAMessageFromThisYearBeyondAWeekReadsWithNoYear() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200) // 2026-08-05T12:00:00Z
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)
        let turn = try message("A question", at: sevenDaysAgo)

        let labels = ChatTranscriptDaySeparators.labels(for: [turn], now: now, timeZone: .gmt)
        XCTAssertEqual(labels[turn.id], "29 Jul")
    }

    /// From an earlier year: the year is stated, for the same reason a range crossing
    /// a year boundary states it — a label reading "3 Jan" in August would be read as
    /// this January. Reuses `ChatThreadListPresentationTests`' own validated fixture
    /// (5 Aug 2026 minus 300 days is 9 Oct 2025).
    func testAMessageFromAnEarlierYearStatesTheYear() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200) // 2026-08-05T12:00:00Z
        let overAYearAgo = now.addingTimeInterval(-300 * 86_400)
        let turn = try message("A question", at: overAYearAgo)

        let labels = ChatTranscriptDaySeparators.labels(for: [turn], now: now, timeZone: .gmt)
        XCTAssertEqual(labels[turn.id], "9 Oct 2025")
    }

    /// A separator marks a change of day from the message immediately before it — a
    /// week of silence followed by one more message gets exactly one new separator, on
    /// that message, not a separator restating every day since the last turn.
    func testAGapOfSeveralDaysProducesExactlyOneNewSeparator() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200) // 2026-08-05T12:00:00Z
        let aWeekAgo = now.addingTimeInterval(-7 * 86_400)
        let first = try message("Before the gap", at: aWeekAgo)
        let second = try message("After the gap", at: now)

        let labels = ChatTranscriptDaySeparators.labels(for: [first, second], now: now, timeZone: .gmt)
        XCTAssertEqual(labels.count, 2)
        XCTAssertNotNil(labels[first.id])
        XCTAssertNotNil(labels[second.id])
    }

    /// A message dated on a calendar day after today's — clock skew, or a device that
    /// changed zones mid-thread — reads as "Today" rather than a label implying it has
    /// not happened yet. Two days ahead, not a few hours, so this actually exercises
    /// the negative-elapsed branch rather than landing on today's date anyway.
    func testAFutureDatedMessageClampsToToday() throws {
        let now = Date(timeIntervalSince1970: 1_785_931_200)
        let turn = try message("From the future", at: now.addingTimeInterval(2 * 86_400))

        let labels = ChatTranscriptDaySeparators.labels(for: [turn], now: now, timeZone: .gmt)
        XCTAssertEqual(labels[turn.id], "Today")
    }

    func testNoMessagesProducesNoSeparators() {
        XCTAssertTrue(ChatTranscriptDaySeparators.labels(for: [], now: Date(), timeZone: .gmt).isEmpty)
    }
}
