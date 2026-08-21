import Foundation

/// The two facts a workout thread's title is made of (§2.4).
///
/// A `ChatSubject.workout` carries an identifier and nothing else — deliberately, since
/// duplicating a run's date onto the thread would create a second copy of it to drift
/// (D2). So the run's own facts are supplied by whoever holds the workout when a summary
/// is built.
///
/// Two fields, not a whole `Workout`: a summary is a list row, and handing a title
/// deriver an entire workout record invites the next ticket to put a distance or a score
/// in the title, which §2.4 rules out for a reason — a workout thread's title has to
/// identify the *run*, and only these two do that.
public struct WorkoutThreadFacts: Hashable, Sendable {
    public let day: CalendarDay
    public let activityType: ActivityType

    public init(day: CalendarDay, activityType: ActivityType) {
        self.day = day
        self.activityType = activityType
    }
}

/// How a thread gets its name (§2.4).
///
/// ## A model call to title a thread is rejected
///
/// The spec states it and this type is where it is enforced by construction: titling is
/// a pure function of stored data, so there is nowhere for a network call to go. The
/// reasoning, from §2.4 — one call per conversation for a string nobody reads twice,
/// against a key the owner pays for (§8), and a *second place that decides what a
/// conversation is about*, which is the same drift A12 spends its length preventing at
/// the context boundary.
///
/// Renaming by hand is a later ticket, not a v1 gap.
public enum ChatThreadTitle {

    /// The longest a derived title may be, in characters.
    ///
    /// A list row shows one line; the value is a budget for that line rather than a
    /// measurement of one, since the core cannot see a font. Truncation happens on a
    /// word boundary (`truncated(_:to:)`), so the real ceiling is this less the length
    /// of the last word dropped.
    public static let maximumLength = 48

    /// A run's date and activity type — "3 Aug 2026 · Running".
    ///
    /// Not the conversation's opening line, unlike a training thread: there is one
    /// thread per run (§12, question 3), so its title has to identify the run rather
    /// than what was asked about it.
    ///
    /// - Parameter facts: nil when the run cannot be resolved. In practice unreachable —
    ///   deleting a workout deletes its thread (`WorkoutAttachedRecord.chatThread`) — so
    ///   the fallback is an honest placeholder for a store that has drifted, not a state
    ///   the product has.
    public static func workout(_ facts: WorkoutThreadFacts?) -> String {
        guard let facts else { return "Workout" }
        return "\(CalendarDayLabel.full(facts.day)) · \(facts.activityType.displayName)"
    }

    /// The athlete's opening question, truncated on a word boundary; before there is
    /// one, the frozen scope's label.
    ///
    /// The fallback is a label rather than "New chat" because it is the more useful of
    /// the two — a list of threads all called "New chat" distinguishes nothing, and the
    /// window is exactly what distinguishes two training threads (§3.4). It also means
    /// an empty thread already states its scope, which is §3.6(b)'s obligation.
    ///
    /// The spec names `TrendIntervalFormatting.label(for:)` as the fallback's source.
    /// That function labels a `TrendInterval`, and a scope has deliberately forgotten
    /// which interval produced it (see `TrainingScope`), so the label is derived from
    /// the resolved days instead — "1 – 31 Aug 2026" where the interval selector would
    /// have said "August 2026". Same window, stated from what the thread actually
    /// stores rather than from a rule it must not keep.
    public static func training(scope: TrainingScope, firstUserMessage: String?) -> String {
        guard let firstUserMessage else { return scope.label }
        let collapsed = SingleLineText.collapsed(firstUserMessage)
        guard !collapsed.isEmpty else { return scope.label }
        return SingleLineText.truncated(collapsed, to: maximumLength)
    }

    /// The title for a thread, dispatching on its subject.
    ///
    /// - Parameter workoutFacts: ignored for a training subject, so a caller that cannot
    ///   cheaply resolve a run may pass nil for every thread and still get correct
    ///   training titles.
    public static func derive(for thread: ChatThread, workoutFacts: WorkoutThreadFacts?) -> String {
        switch thread.subject {
        case .workout:
            return Self.workout(workoutFacts)
        case let .training(scope):
            return Self.training(scope: scope, firstUserMessage: thread.firstUserMessage?.content)
        }
    }
}

/// The sheet's subtitle (§2.2, §3.6(b)) — the thread's scope, stated plainly under its
/// title.
///
/// ## Why this exists beside a title that can already say the same thing
///
/// For a workout thread the title already identifies the run (its date and activity
/// type), so a subtitle restating that would be near-redundant — it still appears,
/// worded as what the conversation is *of* rather than *when*, for the same reason the
/// spec asks for it unconditionally: a person opening the sheet should never have to
/// infer the scope from the title's shape.
///
/// For a training thread the title can drift away from stating the window at all — once
/// the athlete has asked a real question, `ChatThreadTitle` names *that* instead
/// (§2.4) — so the subtitle is what keeps the window visible for the entire life of the
/// conversation. That is §3.6(b)'s mechanism: the thread's scope is frozen and the
/// dashboard's is not, so stating the window everywhere it could matter is what turns a
/// disagreement between the two into a labelled difference rather than an ambush.
///
/// Unlike `ChatThreadTitle`, this needs no messages — only the subject — so it is known
/// the instant a thread is opened, before `ChatModel.load()` resolves anything.
public enum ChatThreadSubtitle {
    public static func text(for subject: ChatSubject) -> String {
        switch subject {
        case .workout:
            return "This run"
        case let .training(scope):
            return scope.label
        }
    }
}

/// What a thread-list row renders from (§2.3).
///
/// A value, not a view model: the row shows a title, a subject glyph, a relative
/// timestamp and one line of the last message, and every one of those is decided here
/// where CI can see it. The view's job is to draw five fields.
///
/// It deliberately does **not** carry the transcript. A list of twenty threads holding
/// twenty full conversations is twenty JSON blobs decoded to render twenty single lines,
/// and — the reason that matters more — health data in memory for a screen that shows
/// none of it.
public struct ChatThreadSummary: Hashable, Sendable, Identifiable {
    /// The thread's own identifier — what `ChatThreadRepository.thread(id:)` and
    /// `deleteThread(id:)` take, so a row can open or delete itself without the list
    /// holding anything more.
    public let id: UUID

    public let subject: ChatSubject

    /// Derived, never generated. See `ChatThreadTitle`.
    public let title: String

    public let lastActivityAt: Date

    /// One line of the last visible turn, whitespace collapsed and truncated. Nil for a
    /// thread nobody has spoken in yet — an absence the row states rather than a blank
    /// it renders.
    public let preview: String?

    /// The longest a preview may be, in characters. Longer than a title's budget
    /// because a preview is allowed to trail off; a title is a name.
    public static let maximumPreviewLength = 100

    public init(
        id: UUID,
        subject: ChatSubject,
        title: String,
        lastActivityAt: Date,
        preview: String?
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.lastActivityAt = lastActivityAt
        self.preview = preview
    }

    /// - Parameter workoutFacts: the run's facts for a workout subject; see
    ///   `WorkoutThreadFacts`. Ignored for a training subject.
    public init(_ thread: ChatThread, workoutFacts: WorkoutThreadFacts? = nil) {
        // `ChatMessage` already rejects whitespace-only content, so an empty result here
        // is unreachable; it is mapped back to nil anyway so that "no preview" has one
        // representation rather than two the view would have to test for separately.
        var preview: String?
        if let last = thread.lastVisibleMessage {
            let line = SingleLineText.truncated(
                SingleLineText.collapsed(last.content),
                to: Self.maximumPreviewLength
            )
            preview = line.isEmpty ? nil : line
        }
        self.init(
            id: thread.id,
            subject: thread.subject,
            title: ChatThreadTitle.derive(for: thread, workoutFacts: workoutFacts),
            lastActivityAt: thread.lastActivityAt,
            preview: preview
        )
    }

    /// Newest activity first — the order §2.3's list is specified in.
    ///
    /// The tiebreak on `id` is not decoration. Two threads can share a `lastActivityAt`
    /// (an empty thread minted in the same second as another's last turn, or a store
    /// whose rows all carry the same default — the situation MAX-048 was filed for), and
    /// a sort with no total order lets the list reshuffle between two reads of identical
    /// data.
    ///
    /// **The tie is broken the same way `mostRecentThread(for:)` breaks it — higher
    /// identifier first.** That is what makes the two agree: the thread the Ask button
    /// opens for a subject is the one that sorts highest among that subject's rows. A
    /// list whose top row was not the thread the button opened would be a small, durable
    /// lie, and it would only ever appear on the tie nobody tests by hand.
    ///
    /// Compared as `uuidString` rather than through `UUID: Comparable`: this package's
    /// tests run on Linux against swift-corelibs-foundation (CI's core job), and a
    /// conformance whose availability differs between that and Apple's Foundation is not
    /// worth depending on for a tiebreak. Any total order does the job, and the
    /// canonical uppercase-hex form is one on both.
    public static func sortedByActivity(_ summaries: [ChatThreadSummary]) -> [ChatThreadSummary] {
        summaries.sorted { left, right in
            if left.lastActivityAt != right.lastActivityAt {
                return left.lastActivityAt > right.lastActivityAt
            }
            return left.id.uuidString > right.id.uuidString
        }
    }
}

/// The one string `ChatThreadSummary.preview` being nil stands for (§2.3) — a thread
/// nobody has spoken in yet.
///
/// MAX-150: `ChatThreadListView`'s row wrote this sentence twice, by hand, in two
/// places that must always agree — the visible caption and the VoiceOver label built
/// beside it — which is exactly the kind of duplication CLAUDE.md's "one consistent
/// voice" exists to close: the two could not previously drift, because they were never
/// checked against each other, only against luck. One constant, read twice, closes it
/// for good rather than by convention.
public enum ChatThreadListCopy {
    public static let noMessagesYetPreview = "No messages yet"

    // MARK: - MAX-153: the list's own two states

    /// The empty list. Absence is a designed state, and this one is a fresh install as
    /// often as it is a store nobody has asked anything — the sentence names the way out
    /// rather than reporting the fact, matching
    /// `ChatConversationCopy.emptyTranscriptInvitation`'s register on the screen a row
    /// opens.
    ///
    /// Moved out of `ChatThreadListView` (MAX-153) for the reason MAX-150 moved
    /// `notYetScored` and `noVerdict` out of `ChatConversationView`: this is one arm of a
    /// state machine whose other arms already live in the core, and a switch with half
    /// its copy in a view is the shape that drifts.
    public static let noConversationsYet =
        "No conversations yet — ask about a run or your training to start one."

    /// The store could not be opened, or the read failed. A local-storage problem stated
    /// plainly, in the same voice as `ChatConversationCopy.failedToLoad`.
    public static let couldNotLoadConversations = "Conversations could not be loaded."

    /// The headline above each of those two sentences.
    ///
    /// Two parts rather than one because the app layer draws these with the platform's own
    /// empty-state component, which is built as headline-plus-explanation. The sentences
    /// above are unchanged from what MAX-150 settled; these are the short forms that sit
    /// over them, and they are deliberately nouns — the sentence is what does the
    /// explaining.
    public static let noConversationsTitle = "No conversations"
    public static let couldNotLoadConversationsTitle = "Conversations unavailable"

    /// The SF Symbol each of those two states wears. The core says which symbol; the app
    /// layer draws it — `ChatSubjectKind.glyphSystemImageName`'s own rule.
    public static let noConversationsGlyphSystemImageName = "bubble.left.and.bubble.right"
    public static let couldNotLoadConversationsGlyphSystemImageName = "exclamationmark.triangle"

    /// The heading above the list. Not "Chat history" and not "Threads": the leading
    /// toolbar button that pushes this screen is already labelled for the action, and the
    /// screen itself is the noun.
    public static let title = "Chats"

    /// A thread could not be deleted from storage (§2.5). The row stays on screen, and the
    /// athlete can try again — matching `ChatFailureNotice.couldNotSaveReply`'s voice for a
    /// storage failure: what happened, what will happen next, no retry button offered.
    public static let couldNotDeleteThread =
        "This conversation could not be deleted. It is still here, and you can try again."
}

    /// The delete-failure alert's title and its one dismissal. In the core beside the
    /// sentence they frame, for the reason `noConversationsYet` gives: a state whose
    /// message lives here and whose title lives in a view is the shape that drifts.
    public static let couldNotDeleteThreadTitle = "Could not delete"
    public static let couldNotDeleteThreadDismiss = "OK"

/// Turning a turn of a conversation into one line of a list row.
///
/// Internal: this is how `ChatThreadTitle` and `ChatThreadSummary` shorten text, not a
/// general-purpose string utility for the package to accumulate cases in.
enum SingleLineText {

    /// Every run of whitespace — including the newlines a multi-paragraph reply is full
    /// of — becomes one space, and the ends are trimmed.
    ///
    /// Done before truncation, not after: truncating first would spend a row's whole
    /// budget on the leading blank lines of a reply that happens to start with one.
    static func collapsed(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Shortens to `limit` characters on a word boundary, marking the cut with an
    /// ellipsis.
    ///
    /// A word boundary rather than a hard cut because the alternative reads as a typo:
    /// "Why did my heart rate cli…" looks broken in a way "Why did my heart rate…" does
    /// not. A word longer than the whole budget still has to be cut somewhere, so it is
    /// cut hard — the rule degrades rather than returning something over budget.
    ///
    /// The ellipsis is a single `…` character, so a truncated result is `limit + 1`
    /// characters at most.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }

        let head = text.prefix(limit)
        if let lastSpace = head.lastIndex(of: " ") {
            let word = head[head.startIndex..<lastSpace]
            if !word.isEmpty {
                return "\(word)…"
            }
        }
        return "\(head)…"
    }
}
