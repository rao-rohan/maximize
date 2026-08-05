import Foundation

/// What just changed in the transcript (MAX-153).
///
/// Two cases, because there are exactly two answers to the only question that matters
/// here — *did the athlete cause this?*
public enum ChatTranscriptChange: Hashable, Sendable {
    /// The athlete's own message was appended. They pressed send a moment ago.
    case ownMessage

    /// Anything that arrived without them asking for it *now*: a token of a streaming
    /// reply, a completed turn, a notice, the plan proposal card.
    case incoming
}

/// What the transcript's scroll view should do about it.
public enum ChatTranscriptScrollDirective: Hashable, Sendable {
    case scrollToLatest
    case stay
}

/// Whether new transcript content moves the scroll view, and what the athlete is offered
/// when it does not (MAX-153).
///
/// ## The failure this type exists to prevent
///
/// The common chat defect — and the one this app had — is scrolling to the bottom
/// whenever anything arrives. Two hundred tokens of a reply land over a few seconds; if
/// each one drags the viewport down, an athlete who scrolled up to re-read the split
/// they were asking about cannot finish the sentence. They are not "behind"; they are
/// reading. Yanking them to the bottom is the app deciding their attention belongs
/// somewhere other than where they put it.
///
/// The inverse defect is just as real: *never* following means the reply to the question
/// you just asked arrives off screen, and you have to chase it. So the rule is not "never
/// scroll" — it is **follow while the reader is at the bottom, hold the moment they leave,
/// and give them one obvious way back**. That is what Messages, Mail and every well-made
/// transcript do, and it is a state machine rather than a modifier, which is why it lives
/// here under test rather than in a view.
///
/// ## The three rules, stated
///
/// 1. **Your own message always scrolls.** You pressed send; seeing it land is the
///    confirmation that it went. `.ownMessage` re-enters following unconditionally —
///    sending is also how a reader says "I am done re-reading."
/// 2. **Incoming content scrolls only if you were already at the bottom.** Otherwise it
///    is remembered (`hasUnseenActivity`) and nothing moves.
/// 3. **Focusing the composer does not move a reader who scrolled away.** This is a
///    deliberate departure from what this app did before MAX-153, which scrolled to the
///    bottom on focus. The case it was written for is real — the keyboard rising should
///    not leave you staring at the middle of the transcript when you were at its end —
///    but it is handled by rule 2's own condition: a reader at the bottom stays at the
///    bottom. A reader who scrolled up, then tapped the field to type a follow-up about
///    what they are looking at, gets to keep looking at it.
///
/// ## Why a flag and not a count
///
/// "3 new messages" is the obvious badge and it is wrong here, because the unit of
/// arrival in a streaming transcript is a token, not a message. A counter driven by the
/// view's `onChange` would read "New (417)". The honest signal is binary — something
/// arrived while you were away — and the copy says exactly that.
public struct ChatTranscriptFollow: Hashable, Sendable {

    /// True while the scroll view is at (or effectively at) the newest content, which is
    /// the only condition under which incoming content is allowed to move it.
    public private(set) var isFollowing: Bool

    /// True when something arrived while `isFollowing` was false. Cleared by returning to
    /// the bottom, by sending, and by taking the offer.
    public private(set) var hasUnseenActivity: Bool

    /// A fresh transcript follows: opening a thread lands you at its newest turn.
    public init() {
        self.isFollowing = true
        self.hasUnseenActivity = false
    }

    /// Whether the "jump to latest" control is on screen.
    ///
    /// Shown whenever the reader is away from the bottom, not only when something new
    /// arrived: scrolling back down through a long conversation by hand is the tedium the
    /// control exists to remove, and a control that appears only sometimes is one nobody
    /// learns to expect.
    public var showsJumpToLatest: Bool {
        !isFollowing
    }

    /// The control's visible text.
    ///
    /// The two cases differ in *words*, not in tint or in glyph — CLAUDE.md's rule about
    /// hue applies to a badge exactly as it does to a score band. "New reply" is the
    /// state worth distinguishing; "Jump to latest" is the plain offer.
    public var jumpToLatestTitle: String {
        hasUnseenActivity ? "New reply" : "Jump to latest"
    }

    public var jumpToLatestAccessibilityHint: String {
        "Scrolls to the newest message in this conversation."
    }

    /// The scroll view reached the newest content — by the athlete's own scroll, or as
    /// the end of a directive this type issued.
    public mutating func readerReachedLatest() {
        isFollowing = true
        hasUnseenActivity = false
    }

    /// The athlete scrolled away from the newest content.
    ///
    /// Idempotent on purpose: a scroll view reports position continuously, so this is
    /// called many times per drag, and only the first one is a state change. Re-running
    /// the body would wipe `hasUnseenActivity` on every subsequent frame — the flag would
    /// be set by an arriving token and cleared by the next scroll event, which is a badge
    /// that flickers rather than one that means something.
    public mutating func readerScrolledAway() {
        guard isFollowing else { return }
        isFollowing = false
        hasUnseenActivity = false
    }

    /// Something was appended to the transcript. See this type's "three rules".
    public mutating func transcriptChanged(_ change: ChatTranscriptChange) -> ChatTranscriptScrollDirective {
        switch change {
        case .ownMessage:
            readerReachedLatest()
            return .scrollToLatest
        case .incoming:
            guard isFollowing else {
                hasUnseenActivity = true
                return .stay
            }
            return .scrollToLatest
        }
    }

    /// The composer gained or lost focus.
    ///
    /// Rule 3. Returns `.scrollToLatest` only for a reader who was already at the bottom,
    /// so the keyboard rising does not leave the newest turn behind it.
    public mutating func composerFocusChanged(isFocused: Bool) -> ChatTranscriptScrollDirective {
        guard isFocused, isFollowing else { return .stay }
        return .scrollToLatest
    }

    /// The athlete took the offer.
    public mutating func jumpToLatestRequested() -> ChatTranscriptScrollDirective {
        readerReachedLatest()
        return .scrollToLatest
    }
}
