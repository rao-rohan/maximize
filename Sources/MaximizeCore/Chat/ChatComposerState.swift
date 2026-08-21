import Foundation

/// Where an unsent composer draft lives between one appearance of a thread's sheet and
/// the next (MAX-198, §6.5).
///
/// ## Why a draft cannot live on `ChatModel` alone
///
/// `ChatSheet` gives `ChatConversationView` a fresh identity — `.id(opening)` — every
/// time the athlete opens a different thread, and the sheet itself is torn down and
/// rebuilt by `RootTabView` on every dismiss and re-present. `ChatModel.composerText`
/// dies with whichever `ChatModel` held it. A draft that has to survive both of those
/// has to live somewhere neither one owns — this type, held once per process and read
/// by whichever `ChatModel` is current.
///
/// ## Keyed by subject, not by thread id (the audit's own recommendation, §6.5)
///
/// The obvious key would be the thread's own identity, but an unstored thread does not
/// have a stable one: `ChatThreadRepository.thread(for:newThreadID:at:)` mints a fresh
/// random id on *every* resolve until a turn is actually completed and stored (see its
/// own doc comment — "used only if nothing exists yet"). A draft typed into a thread
/// that has never sent a message would therefore be keyed to a UUID that changes the
/// next time the sheet opens, which is exactly the bug this ticket exists to fix,
/// wearing a UUID instead of nothing. `ChatSubject` is known immediately for two of
/// `ChatModel`'s three ways in, and is what stays constant while the thread underneath
/// it is still being minted.
///
/// **The accepted gap**: `ChatThreadRepository`'s own contract allows two distinct,
/// already-stored threads to share one subject (MAX-185's **New chat**, used twice on
/// an unchanged window). Opening either one through the thread list would read the same
/// draft slot. This store does not distinguish that case — see the ticket's own note on
/// why per-subject rather than per-row is the smaller, defensible claim: it is right for
/// every ordinary case (a different run, a different week), it is the one key that is
/// actually stable before a thread's first turn lands, and it is what the audit that
/// raised this ticket asked for in these words.
///
/// ## Why this is in-memory only, and why that is the privacy argument
///
/// CLAUDE.md: "Health data is PII... do not copy workout data into logs, analytics,
/// crash reports, or plaintext scratch files." A draft is exactly that kind of text —
/// free-form, health-adjacent, and, unlike a sent turn, never reviewed by the athlete
/// before it exists. `ChatModel`'s own "Only completed turns are persisted" note says
/// disk gets nothing that was not actually said; a draft was never said. Writing it
/// anywhere durable — `UserDefaults`, a plist, a file this app invented — would be a
/// second, weaker-protected copy of the same category of text `ChatThreadRecord`
/// already keeps under SwiftData's file protection, and an unreviewed one at that: an
/// athlete who types something raw and deletes it before sending would still find it on
/// disk. Keeping this in memory for the process's lifetime is the smaller claim: a
/// draft outlives the sheet, and does not outlive the app.
///
/// ## `@MainActor`, matching `ChatModel`
///
/// Every reader and writer is `ChatModel`, which is itself `@MainActor` — there is no
/// concurrent access to guard against, so this adds isolation rather than a lock.
@MainActor
public final class ChatComposerDraftStore {

    /// The store every `ChatModel` reads and writes unless a caller overrides it (tests
    /// do, for isolation between cases). One instance per running app is the entire
    /// point: a `ChatModel` constructed fresh for a reopened sheet must see what a
    /// `ChatModel` already discarded left behind.
    public static let shared = ChatComposerDraftStore()

    private var draftsBySubject: [ChatSubject: String] = [:]

    public init() {}

    /// The unsent text for this subject, or `""` when there is none — the same default
    /// `ChatModel.composerText` already starts from, so a caller never has to branch on
    /// whether a draft exists.
    public func draft(for subject: ChatSubject) -> String {
        draftsBySubject[subject] ?? ""
    }

    /// Replaces the draft for this subject. An empty string removes the entry rather
    /// than storing one — both because there is nothing worth keeping and because it is
    /// what lets `clear(for:)` below and an ordinary "typed it all back out" converge on
    /// the same state rather than one leaving a stale empty record behind.
    public func setDraft(_ text: String, for subject: ChatSubject) {
        if text.isEmpty {
            draftsBySubject.removeValue(forKey: subject)
        } else {
            draftsBySubject[subject] = text
        }
    }

    /// Sending clears it (`ChatModel.send()`), and so does this — named for the call
    /// site that means it that way rather than making every caller spell out
    /// `setDraft("", for:)`.
    public func clear(for subject: ChatSubject) {
        setDraft("", for: subject)
    }
}

/// Whether stopping a reply in progress is something the athlete can actually do
/// (MAX-153, the seam MAX-152 fills).
///
/// ## Why this is a parameter rather than a fact this file knows
///
/// A composer that draws a stop button which does not stop anything is worse than one
/// that draws no stop button at all: it teaches a gesture that silently fails, and the
/// only way to discover that is to tap it during a reply you wanted to abandon. So this
/// is a parameter: MAX-153 owns the composer's *shape*, MAX-152 owns the waiting and
/// streaming *states*, and rather than the shell guessing which world it is in, the
/// caller says.
///
/// **MAX-197 filled it.** `ChatModel.stop()` cancels the task reading the reply, and
/// `ChatModel.replyCancellation` is the answer this type is handed — `.available`
/// whenever there is a request open with a task to cancel. The default stays
/// `.unavailable` so that a caller which has *not* answered the question cannot get a
/// stop button by omission; that is the same "no affordance is better than a false one"
/// rule stated from the other end.
public enum ChatComposerCancellation: Hashable, Sendable {
    /// The stream can be stopped, and the control offers it.
    case available
    /// The stream cannot be stopped. The control shows progress instead.
    case unavailable
}

/// What the composer's trailing control is, right now (§2.2's composer row).
///
/// Four states, one control. The view draws whichever it is handed and forwards a tap;
/// which one it *is* — including the two that are not a send affordance at all — is
/// decided here, where CI checks it on every commit rather than a human checking it in
/// a screenshot.
///
/// ## The shape does not change between enabled and disabled
///
/// `.send` and `.unavailable` deliberately return the same `systemImageName`. A control
/// that swaps glyph the instant the field stops being empty is a control that flickers
/// under every keystroke that lands on a whitespace boundary, and a person aiming for it
/// is aiming at something that moved. Enabled-ness is carried by tint and by the
/// platform's own disabled treatment; the target stays put.
///
/// ## Every state is spoken differently
///
/// CLAUDE.md's "no information carried by hue alone" is usually read as a rule about
/// charts. It applies exactly as hard here: the difference between a send button you can
/// press and one you cannot is, visually, a colour change on an identical glyph. So each
/// state carries its own `accessibilityLabel`/`accessibilityValue`, and the view adds the
/// platform's disabled trait on top — three channels, none of them hue.
public enum ChatComposerSendControl: Hashable, Sendable, CaseIterable {

    /// There is something to send and the thread is ready to send it.
    case send

    /// The control is on screen and dimmed — the field is empty, or the thread has not
    /// finished loading. Present rather than hidden: a send affordance that appears only
    /// once you have typed is one you cannot find before you have.
    case unavailable

    /// A reply is arriving and cannot be stopped. The control's box becomes the seam
    /// MAX-152's waiting indicator occupies — see `showsActivity`.
    case awaitingReply

    /// A reply is arriving and stopping it is offered.
    case stop

    /// The one place the composer's control is decided.
    ///
    /// - Parameters:
    ///   - canSend: `ChatModel.canSend` — ready, not streaming, and something non-blank
    ///     in the field.
    ///   - isStreaming: `ChatModel.isStreaming`.
    ///   - cancellation: see `ChatComposerCancellation`. Defaults to `.unavailable`,
    ///     which is what the app can honestly offer today.
    ///
    /// Streaming wins over `canSend` unconditionally, and that ordering is the point:
    /// `canSend` is already false mid-stream, but a future edit that loosened it must not
    /// be able to put a live send button next to an arriving reply.
    public static func resolve(
        canSend: Bool,
        isStreaming: Bool,
        cancellation: ChatComposerCancellation = .unavailable
    ) -> ChatComposerSendControl {
        if isStreaming {
            return cancellation == .available ? .stop : .awaitingReply
        }
        return canSend ? .send : .unavailable
    }

    /// The same decision, taken from MAX-152's reply ladder rather than from a boolean.
    ///
    /// **This is the overload call sites should use.** `ChatModel.isStreaming` is itself
    /// defined as `replyPhase.isLive`, so the two agree today — but "is a reply in flight"
    /// now has exactly one authority, and reading it directly means a composer cannot be
    /// handed a flag that has drifted from the phase the transcript is drawing.
    ///
    /// The composer does **not** distinguish the three live rungs. Waiting, streaming and
    /// stalled are different things to say *in the transcript*, which is where
    /// `ChatPendingReplyView` says them; to the send control they are one fact — a request
    /// is open, so this is not a send affordance. Splitting the control three ways would
    /// be the app narrating the same state twice, in two places, six inches apart.
    public static func resolve(
        canSend: Bool,
        replyPhase: ChatReplyPhase,
        cancellation: ChatComposerCancellation = .unavailable
    ) -> ChatComposerSendControl {
        resolve(canSend: canSend, isStreaming: replyPhase.isLive, cancellation: cancellation)
    }

    /// Whether a tap does anything. The view pairs this with `.disabled(!isEnabled)` so
    /// the platform supplies its own dimming and its own VoiceOver trait.
    public var isEnabled: Bool {
        switch self {
        case .send, .stop: return true
        case .unavailable, .awaitingReply: return false
        }
    }

    /// True for the one state that is not a button at all. The view draws a progress
    /// indicator in the control's box instead of a glyph — MAX-152 may substitute its own
    /// waiting animation there without this file, or the composer's geometry, changing.
    public var showsActivity: Bool {
        self == .awaitingReply
    }

    /// The SF Symbol, or nil when `showsActivity` says there is an indicator in its place.
    ///
    /// A plain string, matching `ChatSubjectKind.glyphSystemImageName`'s own note: the
    /// core says which symbol, the app layer draws it.
    public var systemImageName: String? {
        switch self {
        case .send, .unavailable: return "arrow.up.circle.fill"
        case .stop: return "stop.circle.fill"
        case .awaitingReply: return nil
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .send, .unavailable: return "Send"
        case .stop: return "Stop generating"
        case .awaitingReply: return "Reply in progress"
        }
    }

    /// The state, in words, for the two cases whose only visual difference from `.send`
    /// is a tint.
    public var accessibilityValue: String? {
        switch self {
        case .send, .stop: return nil
        case .unavailable: return "Nothing to send"
        case .awaitingReply: return "Waiting for the reply to finish"
        }
    }

    public var accessibilityHint: String? {
        switch self {
        case .send: return "Sends your question and starts the reply."
        case .stop: return "Stops the reply where it is. What has already arrived is kept."
        case .unavailable, .awaitingReply: return nil
        }
    }
}
