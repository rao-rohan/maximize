import Foundation

/// Which turns of a transcript should be preceded by a day separator, and what it says
/// (§6.8, MAX-201).
///
/// A training thread is frozen to a window that can span months (§3.4); a workout
/// thread is short-lived but nothing stops an athlete from returning to one days later
/// to ask a follow-up. Either way, before this ticket, nothing on screen said *when*
/// anything in the transcript was said — the thread list has a compact stamp and
/// recency bands, and the transcript had neither. This is the display-data decision
/// behind the one row `ChatConversationView` adds: given a thread's own stored turns,
/// which of them start a new calendar day, and what that day is called.
///
/// ## Why this takes `ChatMessage`, never `ChatModel.DisplayMessage`
///
/// `DisplayMessage` is the transcript's rendered row, and it can hold things that never
/// reach storage — an app-generated notice ("the connection dropped"), or an assistant
/// reply still arriving. Neither carries a timestamp of its own, and inventing one (the
/// moment the row was drawn, say) would let a separator claim a day for something that
/// has not actually happened yet as far as the thread is concerned. `ChatMessage`,
/// `ChatThread.visibleMessages`' own element, is what was actually stored and when —
/// the same distinction `ChatModel.canDraftPlan`'s own documentation draws between "on
/// screen" and "in the thread". A message that has just been sent and has not yet been
/// persisted (`ChatModel.send()`) therefore draws with no separator until the reply
/// resolves and the transcript is read again — which cannot happen inside the same
/// session, so nothing here needs to reach across a still-open request to answer it.
public enum ChatTranscriptDaySeparators {

    /// - Parameters:
    ///   - messages: a thread's own `visibleMessages`, oldest first, exactly as
    ///     stored.
    ///   - now / timeZone: the athlete's clock and zone, read fresh at render time —
    ///     they decide only the wording (`ChatTranscriptDayLabel`), never which
    ///     messages differ from their predecessor, so a separator already on screen
    ///     cannot silently relabel itself mid-scroll the way `ChatThreadListModel`'s own
    ///     documentation warns a *band* could.
    /// - Returns: message id → the separator's text, for every message whose calendar
    ///   day (in `timeZone`) differs from the message immediately before it — including
    ///   the first, which has no predecessor and therefore always differs from one. A
    ///   thread with every turn on one day gets exactly one separator, at the top; a
    ///   thread resumed after a gap gets one at every resumption.
    public static func labels(
        for messages: [ChatMessage],
        now: Date,
        timeZone: TimeZone
    ) -> [UUID: String] {
        guard let today = try? CalendarDay(now, in: timeZone) else { return [:] }

        var result: [UUID: String] = [:]
        var previousDay: CalendarDay?
        for message in messages {
            // A message whose stored timestamp cannot resolve to a day (outside
            // `CalendarDay`'s 1...9999 domain — effectively unreachable) draws with no
            // separator rather than a wrong one; it also does not update
            // `previousDay`, so a corrupted single row cannot manufacture a spurious
            // separator on the row after it either.
            guard let day = try? CalendarDay(message.timestamp, in: timeZone) else { continue }
            if previousDay != day {
                result[message.id] = ChatTranscriptDayLabel.text(for: day, today: today)
            }
            previousDay = day
        }
        return result
    }
}

/// The wording for one of `ChatTranscriptDaySeparators`' labels.
///
/// The same ladder `ChatThreadListPresentation.compactTimestamp` uses beyond its own
/// first rung — Today, Yesterday, a weekday name within the previous week, then a dated
/// label — so a conversation reads the same way whether the athlete is scanning the
/// list or the transcript itself. Kept as its own small switch rather than sharing that
/// function's: `compactTimestamp`'s first rung answers "how many hours ago", a question
/// a day separator is never asked, and forcing the two to share an implementation would
/// mean threading an hours-vs-days branch through a function that has no use for it.
enum ChatTranscriptDayLabel {
    static func text(for day: CalendarDay, today: CalendarDay) -> String {
        guard let elapsedDays = try? day.days(until: today) else {
            // Unreachable outside a corrupted record — a dated label is still honest.
            return CalendarDayLabel.full(day)
        }
        switch elapsedDays {
        // A day that has not happened yet by the clock reading this — skew, or a device
        // that changed zones mid-thread — reads as "Today" rather than a label implying
        // it is still to come, matching `ChatThreadRecency.band(for:today:)`'s own
        // reasoning for a thread dated in the future.
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2...6: return CalendarDayLabel.shortWeekdayName(day.weekday)
        default:
            return day.year == today.year
                ? CalendarDayLabel.dayAndMonth(day)
                : CalendarDayLabel.full(day)
        }
    }
}
