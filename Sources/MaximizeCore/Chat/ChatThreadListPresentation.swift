import Foundation

/// Which recency band a thread falls in (§2.3, MAX-153).
///
/// The bands are the ones Mail, Notes and Files already group by, and the reason to take
/// them rather than invent a set is that the athlete has read them a hundred times this
/// week in Apple's own apps. Novelty in a section header buys nothing.
///
/// Ordering is the declaration order, newest band first, which is also `sections(for:)`'s
/// output order — so a list never has to sort bands, only fill them.
public enum ChatThreadRecency: Int, Hashable, Sendable, CaseIterable, Comparable {
    case today = 0
    case yesterday = 1
    case previousSevenDays = 2
    case previousThirtyDays = 3
    case earlier = 4

    public var sectionTitle: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .previousSevenDays: return "Previous 7 days"
        case .previousThirtyDays: return "Previous 30 days"
        case .earlier: return "Earlier"
        }
    }

    public static func < (lhs: ChatThreadRecency, rhs: ChatThreadRecency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// - Parameters:
    ///   - day: the thread's last activity, as a calendar day in the athlete's zone.
    ///   - today: today, same zone.
    ///
    /// A thread dated in the future bands as `.today`. That is not a hypothetical: a
    /// device whose clock moved backwards, or a record written across a zone change,
    /// produces one, and the alternative — a "Later" band above "Today" — would be a
    /// section header explaining a bug to the athlete.
    public static func band(for day: CalendarDay, today: CalendarDay) -> ChatThreadRecency {
        guard let elapsed = try? day.days(until: today) else { return .earlier }
        switch elapsed {
        case ..<1: return .today
        case 1: return .yesterday
        case 2...7: return .previousSevenDays
        case 8...30: return .previousThirtyDays
        default: return .earlier
        }
    }
}

/// One row of §2.3's list, fully resolved.
///
/// Every string a row draws is here. That is a deliberate step past what
/// `ChatThreadSummary` alone gave the view: before MAX-153 the row assembled its own
/// VoiceOver sentence out of four fields and its own nil-handling for the preview, which
/// is three decisions in a `body`. The view now draws six strings and a glyph name.
///
/// ## The scope line is new, and it is the densest thing on the row
///
/// §2.3 asked for title, glyph, timestamp and one line of the last message. This adds the
/// thread's **scope**, for §3.6(b)'s reason rather than for density's sake: a training
/// thread's title becomes the athlete's first question the moment they ask one, at which
/// point nothing on the row says which window the conversation was frozen against. Two
/// rows reading "Why did my HR climb" over two different months are the same row twice.
/// The scope is what tells them apart, and it is the same string the sheet's subtitle
/// shows once the thread is open (`ChatThreadSubtitle`), so the two cannot drift. It is
/// nil wherever it would only repeat the title — see `scope` below.
public struct ChatThreadListRow: Hashable, Sendable, Identifiable {

    /// The thread's own identifier — what a tap carries and what a delete takes.
    public let id: UUID

    public let kind: ChatSubjectKind

    public let glyphSystemImageName: String

    /// `ChatThreadTitle`'s derived name, never generated (§2.4).
    public let title: String

    /// The thread's frozen window, when stating it adds something.
    ///
    /// **Nil in the two cases where it would be noise**, which is a decision rather than
    /// an omission:
    ///
    /// - A **workout** thread's title is already the run's date and activity type
    ///   (§2.4), so "This run" underneath it is a second line saying what the first line
    ///   said. The sheet shows that subtitle because a sheet has one title and needs the
    ///   scope stated unconditionally; a list row has a glyph and a kind beside it.
    /// - A **training** thread nobody has spoken in yet is *titled* by its window
    ///   (`ChatThreadTitle.training`'s fallback), so the same string would appear twice.
    ///
    /// Once the athlete asks something, a training thread's title becomes their question
    /// and this line is the only thing left saying which month it was about — which is
    /// §3.6(b)'s whole mechanism, and the case worth the row's third line.
    public let scope: String?

    /// One line of the last visible turn, or the absence sentence.
    public let preview: String

    /// True when `preview` is the absence sentence rather than something that was said,
    /// so the view can draw it a step quieter — the same distinction, in weight, that
    /// the words already make.
    public let previewIsAbsence: Bool

    /// The compact timestamp: "now", "12m", "5h", "Yesterday", "Tue", "3 Aug",
    /// "3 Aug 2025". See `ChatThreadListPresentation.compactTimestamp(for:now:timeZone:)`.
    public let timestamp: String

    /// Kept so a view can render its own richer date treatment (a tooltip, a spoken
    /// form) without the list having to hand back the summary as well.
    public let lastActivityAt: Date

    public init(
        id: UUID,
        kind: ChatSubjectKind,
        glyphSystemImageName: String,
        title: String,
        scope: String?,
        preview: String,
        previewIsAbsence: Bool,
        timestamp: String,
        lastActivityAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.glyphSystemImageName = glyphSystemImageName
        self.title = title
        self.scope = scope
        self.preview = preview
        self.previewIsAbsence = previewIsAbsence
        self.timestamp = timestamp
        self.lastActivityAt = lastActivityAt
    }

    /// What VoiceOver reads for the whole row, as one sentence.
    ///
    /// - Parameter spokenTimestamp: the app layer's `RelativeDateTimeFormatter` output —
    ///   "3 hours ago" rather than this row's "3h". Injected rather than derived here
    ///   because that formatter is locale-driven and OS-version-driven, and a core test
    ///   asserting its output would be asserting Foundation's behaviour on whichever
    ///   platform CI happened to run. The *sentence* is the decision; the phrase inside it
    ///   is the platform's.
    ///
    /// The glyph is spoken as `kind.accessibilityKindLabel` rather than skipped: a sighted
    /// athlete distinguishes a run thread from a training thread at a glance by its shape,
    /// and that channel has to exist in words too.
    public func accessibilityLabel(spokenTimestamp: String) -> String {
        [kind.accessibilityKindLabel, title, scope, spokenTimestamp, preview]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

/// One recency band with at least one row in it. Empty bands are never emitted — a
/// section header with nothing under it is a heading for an absence that is not there.
public struct ChatThreadListSection: Hashable, Sendable, Identifiable {
    public var id: ChatThreadRecency { recency }
    public let recency: ChatThreadRecency
    public let rows: [ChatThreadListRow]

    public var title: String { recency.sectionTitle }

    public init(recency: ChatThreadRecency, rows: [ChatThreadListRow]) {
        self.recency = recency
        self.rows = rows
    }
}

/// Turning stored thread summaries into §2.3's list (MAX-153).
///
/// All of it: ordering, banding, the compact timestamp, which string stands in for a
/// missing preview. `ChatThreadListModel` calls this once and holds the result;
/// `ChatThreadListView` draws it. Neither of them decides anything, which is CLAUDE.md's
/// thin shell taken literally — and it is why the grouping's edge cases (a thread at
/// exactly seven days, a thread dated tomorrow, two threads sharing an instant) are
/// checked by CI rather than by scrolling a list on a device.
public enum ChatThreadListPresentation {

    /// Everything §2.3's list renders, newest band first and newest row first inside it.
    ///
    /// - Parameters:
    ///   - summaries: as stored. Re-sorted here rather than trusted, so the banding cannot
    ///     be handed an order that makes a section read backwards.
    ///   - now: the present. A parameter, not `Date()`, so "today" is one notion this
    ///     function is told rather than one it invents — the same shape `ChatModel` uses.
    ///   - timeZone: the athlete's zone. A conversation at 00:30 belongs to the day they
    ///     were living, not to UTC's.
    ///
    /// Total by construction. A date that cannot be converted to a `CalendarDay` — a
    /// domain of 1...9999 AD, so effectively only a corrupted record — bands as `.earlier`
    /// rather than throwing: a list that refuses to draw because one row has a bad
    /// timestamp is a worse outcome than that row sorting last.
    public static func sections(
        for summaries: [ChatThreadSummary],
        now: Date,
        timeZone: TimeZone
    ) -> [ChatThreadListSection] {
        let today = try? CalendarDay(now, in: timeZone)
        let ordered = ChatThreadSummary.sortedByActivity(summaries)

        var banded: [ChatThreadRecency: [ChatThreadListRow]] = [:]
        for summary in ordered {
            let band: ChatThreadRecency
            if let today, let day = try? CalendarDay(summary.lastActivityAt, in: timeZone) {
                band = ChatThreadRecency.band(for: day, today: today)
            } else {
                band = .earlier
            }
            banded[band, default: []].append(row(for: summary, now: now, timeZone: timeZone))
        }

        // `ChatThreadRecency.allCases` is declared newest-first, so iterating it is the
        // section order — no sort, and no way for a new band to be added without being
        // given a position.
        return ChatThreadRecency.allCases.compactMap { (recency) -> ChatThreadListSection? in
            guard let rows = banded[recency], !rows.isEmpty else { return nil }
            return ChatThreadListSection(recency: recency, rows: rows)
        }
    }

    /// One row. Exposed for the same reason `ChatThreadSummary`'s own initializer is:
    /// a caller with a single thread should not have to build a one-element list.
    public static func row(
        for summary: ChatThreadSummary,
        now: Date,
        timeZone: TimeZone
    ) -> ChatThreadListRow {
        ChatThreadListRow(
            id: summary.id,
            kind: summary.subject.kind,
            glyphSystemImageName: summary.subject.kind.glyphSystemImageName,
            title: summary.title,
            scope: scope(for: summary),
            preview: summary.preview ?? ChatThreadListCopy.noMessagesYetPreview,
            previewIsAbsence: summary.preview == nil,
            timestamp: compactTimestamp(for: summary.lastActivityAt, now: now, timeZone: timeZone),
            lastActivityAt: summary.lastActivityAt
        )
    }

    /// See `ChatThreadListRow.scope` for the two cases this deliberately drops.
    ///
    /// It reads `ChatThreadSubtitle` rather than re-deriving the window, so a row and the
    /// sheet it opens cannot spell one window two ways — the drift §3.6(b) is built to
    /// stop.
    private static func scope(for summary: ChatThreadSummary) -> String? {
        let stated = ChatThreadSubtitle.text(for: summary.subject)
        switch summary.subject {
        case .workout:
            return nil
        case .training:
            return stated == summary.title ? nil : stated
        }
    }

    /// §4.3: `.searchable` over titles and previews, filtered here so the app layer
    /// never holds a second notion of "what matches" — and so a filter and the banding
    /// above it can never disagree about which rows exist.
    ///
    /// Composed from the two calls a caller could otherwise make separately —
    /// `matches(_:query:)`, then the plain `sections(for:now:timeZone:)` — rather than a
    /// second banding implementation. That is the whole answer to the audit's warning
    /// (§4.3, §6.9) that a filtered list must not lose its section headers or keep one
    /// with nothing under it: MAX-153's "an empty band is never emitted" already holds
    /// for whatever list is handed in, so it holds for a filtered one for free.
    ///
    /// - Parameter query: exactly what `.searchable` hands back on every keystroke.
    ///   Blank, including whitespace-only, means "not searching" — the unfiltered list,
    ///   never a filter nothing can match.
    public static func sections(
        for summaries: [ChatThreadSummary],
        matching query: String,
        now: Date,
        timeZone: TimeZone
    ) -> [ChatThreadListSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sections(for: summaries, now: now, timeZone: timeZone)
        }
        return sections(for: summaries.filter { matches($0, query: trimmed) }, now: now, timeZone: timeZone)
    }

    /// Whether `summary` matches a search typed into §4.3's field — over the same two
    /// fields its own row draws, title and preview, and nothing a row does not show:
    /// not the scope line, which is a derived label rather than something the athlete
    /// wrote or Claude said.
    ///
    /// Case-insensitive, and deliberately nothing more clever than that — matching
    /// `compactTimestamp`'s own reasoning for staying off `DateFormatter`: the app is
    /// single-user and not distributed, so a search that found something on one phone
    /// and not another for the same query, because the two disagreed about a locale,
    /// would be a worse bug than the one this ticket is fixing.
    ///
    /// Does not itself treat a blank query specially — see
    /// `sections(for:matching:now:timeZone:)`, which decides that once rather than
    /// leaving every caller of this function to reimplement "empty means everything".
    public static func matches(_ summary: ChatThreadSummary, query: String) -> Bool {
        let needle = query.lowercased()
        if summary.title.lowercased().contains(needle) { return true }
        if let preview = summary.preview, preview.lowercased().contains(needle) { return true }
        return false
    }

    /// The narrowest honest timestamp for a list row.
    ///
    /// | Age | Reads |
    /// |---|---|
    /// | under a minute | `now` |
    /// | under an hour | `12m` |
    /// | earlier today | `5h` |
    /// | yesterday | `Yesterday` |
    /// | within the previous week | `Tue` |
    /// | this year | `3 Aug` |
    /// | older | `3 Aug 2025` |
    ///
    /// This is Messages' ladder, and it is worth taking rather than improving on: each
    /// rung is the shortest form that is still unambiguous at that distance, which is
    /// exactly what a row with a title competing for the same line needs.
    ///
    /// **A departure from what this list showed before MAX-153**, which was
    /// `Text(_:style:.relative)` — a live-updating "3 hours ago" that is wider than the
    /// title beside it at any Dynamic Type size above default, re-lays-out every minute
    /// while the list is on screen, and says "0 seconds ago" for a thread created a moment
    /// ago. The spoken form keeps the long phrasing (`ChatThreadListRow.accessibilityLabel`),
    /// where width costs nothing.
    ///
    /// English-only, deliberately and consistently with every other string in this
    /// package — the app is single-user and not distributed (CLAUDE.md's Keychain
    /// tripwire says so in the other direction). It is also why this is built from
    /// `CalendarDay` arithmetic rather than a `DateFormatter`: the output is then the same
    /// on Apple's Foundation and on the swift-corelibs Foundation CI's core job runs
    /// against, which is what makes it testable at all.
    public static func compactTimestamp(for date: Date, now: Date, timeZone: TimeZone) -> String {
        let elapsed = now.timeIntervalSince(date)

        // A thread stamped in the future — clock skew, or a zone change mid-write — reads
        // as "now" rather than as a negative age.
        if elapsed < 60 { return "now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }

        guard
            let today = try? CalendarDay(now, in: timeZone),
            let day = try? CalendarDay(date, in: timeZone),
            let elapsedDays = try? day.days(until: today)
        else {
            // Unreachable outside a corrupted record; an hours figure is still true.
            return "\(Int(elapsed / 3600))h"
        }

        switch elapsedDays {
        case ..<1: return "\(Int(elapsed / 3600))h"
        case 1: return "Yesterday"
        case 2...6: return CalendarDayLabel.shortWeekdayName(day.weekday)
        default:
            return day.year == today.year
                ? CalendarDayLabel.dayAndMonth(day)
                : CalendarDayLabel.full(day)
        }
    }

    /// The outcome of attempting to delete a thread (§2.5, MAX-189).
    ///
    /// Given the state before a delete, the id of the thread to delete, and the error
    /// (if any) that occurred, returns the new summaries, sections, and error message
    /// to display.
    ///
    /// A successful delete (error is nil) removes the thread from storage. A failed
    /// delete keeps it and surfaces a notice saying so, in the same voice as
    /// `couldNotSaveReply`: what happened, what remains, what to do.
    ///
    /// - Parameters:
    ///   - summaries: the current list of stored threads
    ///   - attemptedThreadID: the id of the thread the model tried to delete
    ///   - error: nil if the delete succeeded, the error thrown if it failed
    ///   - now: the present time, for banding
    ///   - timeZone: the athlete's zone, for banding
    ///
    /// Returns a tuple of:
    /// - `summaries`: the list to store (with the thread removed on success, unchanged on failure)
    /// - `sections`: the banded, ordered list to display
    /// - `errorMessage`: the notice to show (nil on success, the failure message on error)
    public static func deletionOutcome(
        from summaries: [ChatThreadSummary],
        attemptedThreadID: UUID,
        error: Error?,
        now: Date,
        timeZone: TimeZone
    ) -> (summaries: [ChatThreadSummary], sections: [ChatThreadListSection], errorMessage: String?) {
        var updated = summaries
        let errorMessage: String?

        if error == nil {
            // Successful delete — remove the thread
            updated.removeAll { $0.id == attemptedThreadID }
            errorMessage = nil
        } else {
            // Failed delete — keep the thread and state the failure
            errorMessage = ChatThreadListCopy.couldNotDeleteThread
        }

        let sections = Self.sections(for: updated, now: now, timeZone: timeZone)
        return (updated, sections, errorMessage)
    }
}
