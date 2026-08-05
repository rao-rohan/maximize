import Foundation

/// Whether stopping a reply in progress is something the athlete can actually do
/// (MAX-153, the seam MAX-152 fills).
///
/// ## Why this is a parameter rather than a fact this file knows
///
/// A composer that draws a stop button which does not stop anything is worse than one
/// that draws no stop button at all: it teaches a gesture that silently fails, and the
/// only way to discover that is to tap it during a reply you wanted to abandon.
/// `ChatModel` today has no cancellation — `send()` runs the stream to its terminal
/// event and nothing interrupts it — so the honest control during a stream is a progress
/// indicator, not a stop.
///
/// MAX-153 owns the composer's *shape*; MAX-152 owns the waiting and streaming *states*.
/// Rather than the shell guessing which of those two worlds it is in, the caller says.
/// When cancellation lands, one call site changes from `.unavailable` to `.available`
/// and the control becomes a stop button, already sized, already labelled, already
/// tested — see `ChatComposerSendControlTests`.
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
