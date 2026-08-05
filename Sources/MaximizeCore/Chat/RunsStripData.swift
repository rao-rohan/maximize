import Foundation

/// The "Runs in this conversation" strip (CHAT-FIRST-SPEC.md §2.2, §6.2, MAX-103).
///
/// ## What this is for
///
/// §6.2 names the property this exists to give: a training thread's sheet renders a strip
/// of the sessions whose figures are in *this exact thread's* `TrainingContext`, "which
/// makes the scope visible, [and] is a privacy affordance as much as a navigation one" —
/// part of §3.6(b)'s answer to a frozen thread quietly disagreeing with a screen. Tapping a
/// chip pushes that session's own detail screen; nothing here parses a model's reply or
/// invents an identifier — every chip's `workoutID` is a stored fact already sitting in
/// `TrainingContext.Session`.
///
/// ## Why this is a core type and not a view computing a label
///
/// CLAUDE.md's thin-shell rule names exactly this shape of thing: "the chip's content —
/// its label, its ordering, how many are shown, what the strip says when the context is
/// empty — is a display-data computation," so it belongs where CI can see it, the same
/// split `PlanDisplayData` and `ChatThreadSummary` already draw. A view that formatted a
/// date or decided how many chips fit is exactly the defect this file exists to not be.
///
/// ## Built from the thread's own context, never a second read
///
/// `build(from:)` takes the exact `TrainingContext` `ChatModel.load()` already assembled
/// for this thread's prompt (`ChatModel.runsStripData` reads it off `context`, never
/// re-fetches storage) — so the strip cannot show a session the prompt did not, or the
/// reverse. That agreement is the whole point: a strip that could drift from the context
/// would be showing the athlete a *different* notion of "what this conversation can see"
/// than the one actually sent.
///
/// ## What this deliberately does not carry
///
/// A chip carries a label and an id to push with — nothing measured about the session
/// (no distance, no score, no band). §6.3 is the reason for the second half: "no chat
/// surface renders a chart, a calendar, or a metric tile," and a coloured band pip on a
/// chip would be exactly that, on top of directly conflicting with FR-4.3's confinement of
/// the three score-band colours to the calendar and the verdict header —
/// `Color.scoreBand(_:)`'s own documentation is explicit that "using them anywhere else
/// dilutes the one signal the product exists to give." The strip's job is *which* sessions
/// are in scope, not *how they went*; a tap already leads to the one screen that answers
/// the second question in full.
public enum RunsStripData: Hashable, Sendable {

    /// One session, named for a chip.
    public struct Chip: Hashable, Sendable, Identifiable {
        public var id: UUID { workoutID }

        /// What tapping this chip pushes to (§6.2). Never rendered as text — the same
        /// convention `TrainingContext.Session.workoutID`'s own documentation states.
        public let workoutID: UUID

        /// "3 Aug 2026 · Running" — the same two facts, in the same order and with the
        /// same separator, `ChatThreadTitle.workout` already names a run's own thread by.
        /// A run named in its own thread's title and the same run named as a chip here
        /// are one spelling of one fact, not two formatters that happen to agree today.
        public let label: String

        init(workoutID: UUID, label: String) {
            self.workoutID = workoutID
            self.label = label
        }
    }

    /// Why there is nothing to show — CLAUDE.md's "absence is a designed state," applied
    /// to two different facts that must not read as one blank.
    public enum EmptyReason: Hashable, Sendable {
        /// The window genuinely holds no sessions: an athlete who has not trained inside
        /// it yet, or a thread opened before anything was captured.
        case noSessionsInWindow

        /// `TrainingContext.sessionsWereWithheldByTheCap` — the window's own session count
        /// crossed `TrainingContext.maximumRenderedSessions` before this type ever saw it,
        /// so the fact sheet itself named none of them. The strip inherits the same
        /// withholding rather than naming sessions the prompt never did; the carried count
        /// is `TrainingContext.sessionCountInScope`, the number the fact sheet itself states.
        case withheldByCap(sessionCount: Int)
    }

    case empty(EmptyReason)

    /// `omittedCount` is how many sessions this type's own `maximumChips` left off the
    /// end of an otherwise-listed window — zero in the ordinary case (a week, a month).
    ///
    /// Distinct from `EmptyReason.withheldByCap`: that is `TrainingContext`'s own bound
    /// biting before a single chip exists; this is the strip's smaller, separate bound
    /// biting after they do, for a reason that is about a horizontal scroll rather than
    /// about a prompt.
    case chips([Chip], omittedCount: Int)

    /// The most chips a strip lays out before folding the remainder into a count.
    ///
    /// Sized the way `TrainingContext.maximumRenderedSessions` is — against the windows
    /// the app can actually produce, not a guess at screen width. `TrainingContext`'s own
    /// documentation puts a week at "at most ~14 sessions" and a month at "at most ~62"
    /// for an athlete who runs and lifts; this is set at the month figure so neither of
    /// the app's two smallest, most common windows is ever folded. A quarter or a year
    /// *can* cross it, and a strip of hundreds of chips would be exactly the "athlete's
    /// whole [window] of movement" shape §3.1 already rejects for the prompt itself — a
    /// scroll nobody is going to finish is not the affordance this strip exists to be.
    public static let maximumChips = 62

    /// Builds the strip from the thread's own `TrainingContext` — see this type's "Built
    /// from the thread's own context, never a second read."
    ///
    /// **No arithmetic over more than one session.** Every chip's label is read off one
    /// `TrainingContext.Session`; the only number this function derives is how many
    /// sessions its own `maximumChips` left off the list, which counts chips rather than
    /// measuring the athlete — the same distinction `TrainingContext.sessionCountInScope`
    /// draws for itself.
    public static func build(from context: TrainingContext) -> RunsStripData {
        guard !context.sessions.isEmpty else {
            if context.sessionsWereWithheldByTheCap {
                return .empty(.withheldByCap(sessionCount: context.sessionCountInScope))
            }
            return .empty(.noSessionsInWindow)
        }

        // Chronological, oldest first — `TrainingContext.sessions`' own order, which is
        // the order the fact sheet lists them in. Reordering here would make the strip a
        // second, silently different notion of "the runs in this conversation" from the
        // one Claude was actually shown, which is exactly the drift §3.6(a) exists to
        // close for a number and this type closes for an ordering.
        let visible = context.sessions.prefix(maximumChips)
        let chips = visible.map { session in
            Chip(workoutID: session.workoutID, label: label(for: session))
        }
        return .chips(chips, omittedCount: context.sessions.count - chips.count)
    }

    private static func label(for session: TrainingContext.Session) -> String {
        "\(CalendarDayLabel.full(session.day)) · \(session.activityType.displayName)"
    }
}

/// Copy for the strip itself — the header a training thread's sheet always shows is a
/// fixed string with no data dependency (`RunsStripView`'s own "Runs in this conversation"),
/// so it stays in the view exactly as `WorkoutChatSectionView`'s "Chat" heading does; what
/// belongs here is the copy that *depends on `RunsStripData`*, mirroring
/// `ChatConversationCopy`'s own split between fixed and subject-dependent strings.
public enum RunsStripCopy {

    /// The strip's one line of prose for `RunsStripData.EmptyReason`.
    public static func text(for reason: RunsStripData.EmptyReason) -> String {
        switch reason {
        case .noSessionsInWindow:
            return "No runs recorded in this window yet."
        case let .withheldByCap(sessionCount):
            return "This window holds \(sessionCount) sessions — too many to list individually."
        }
    }

    /// The trailing label for however many chips `RunsStripData.maximumChips` left off
    /// the end of an otherwise-listed strip.
    public static func omittedCountLabel(_ omittedCount: Int) -> String {
        "+\(omittedCount) more"
    }
}
