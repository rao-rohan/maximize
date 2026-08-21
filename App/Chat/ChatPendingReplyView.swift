import SwiftUI
import MaximizeCore

/// The row that stands where a reply will be, for as long as there is no complete reply
/// (MAX-152, FR-2.4).
///
/// Three rungs of `ChatReplyPhase` render here and no others: waiting, streaming,
/// stalled. **It decides nothing.** Which rung is showing is `ChatModel`'s answer, made
/// from stream events in `MaximizeCore` where CI checks it; this file chooses how each
/// one looks, which is the only part of the question a view is allowed to hold.
///
/// ## The waiting animation, and what it is copied from
///
/// Claude's own interface marks "thinking" with a **shimmer** — a bright band travelling
/// through the text — rather than with pulsing dots, and that choice is the one worth
/// taking. Three reasons, in the order they matter here:
///
/// 1. **It is drawn on words, not instead of them.** Three bouncing dots say "something
///    is happening" and nothing else. A shimmer needs a sentence underneath it to travel
///    across, so the state is carried by copy first (`ChatConversationCopy.pendingStatus`)
///    and by motion second. That is the same rule as "no information carried by hue
///    alone", one channel over: a state carried only by an animation disappears the
///    moment somebody turns animation off.
/// 2. **It is ambient rather than metronomic.** A pulse has a beat, and a beat in the
///    corner of the eye is what makes a loader nag. A slow linear sweep does not.
/// 3. **It degrades to something that still looks designed.** With the sweep withheld,
///    what is left is a legible line of secondary text in a reply-shaped bubble — a
///    calm, static waiting state, not a broken animated one.
///
/// **Where this deliberately differs from Claude's.** There is a live accessibility
/// complaint against that shimmer for being distracting (anthropics/claude-code#6038), so
/// this one is slower than the usual implementations of the technique
/// (`Motion.waitingSweep`), it is withheld entirely under **Reduce Motion** *and* under
/// **Reduce Transparency**, and it never carries information on its own. It also ends
/// harder: the moment the first token lands the whole indicator is gone, replaced by the
/// words. An indicator that keeps shimmering next to arriving text is an app talking over
/// its own answer.
///
/// **No third-party dependency.** `markiv/SwiftUI-Shimmer` is the reference
/// implementation of the technique and was read for it — a gradient, a mask, an offset
/// animated across the width — but this package has no dependencies and is not gaining
/// one for forty lines of `LinearGradient`.
struct ChatPendingReplyView: View {

    /// Which rung. Handed in whole rather than decomposed into flags, so this view cannot
    /// be asked to draw a combination the core says is impossible — "waiting" and
    /// "streaming" at once, most of all.
    let phase: ChatReplyPhase

    /// The reply so far. Empty for `.awaitingFirstToken` by construction: the first token
    /// is what moves the ladder off that rung.
    let text: String

    var body: some View {
        // Non-nil for exactly the three live rungs, which is exactly when this row exists.
        // Every terminal rung has already produced its own row — a reply bubble, its
        // truncated caption, or a `ChatFailureNotice` — and a second row describing one of
        // those would be the app restating a fact the surface already stated.
        if let announcement = ChatConversationCopy.pendingAccessibilityLabel(for: phase) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    bubble
                    stalledCaption
                }
                Spacer(minLength: Spacing.hero)
            }
            // `.contain` rather than `.combine`: the reply's text stays its own element,
            // so VoiceOver reads the answer as an answer instead of re-reading a growing
            // paragraph prefixed by a status every time a token lands.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(announcement)
        }
    }

    @ViewBuilder
    private var bubble: some View {
        switch phase {
        case .awaitingFirstToken:
            // The placeholder is a reply-shaped bubble in the reply's own position, so
            // the answer does not jump across the screen when it arrives.
            if let status = ChatConversationCopy.pendingStatus(for: phase) {
                bubbleSurface {
                    ShimmeringLabel(text: status)
                }
            }
        case .streaming, .stalled:
            bubbleSurface {
                // MAX-195: this text is always the model's own — nothing else streams
                // — so it takes the same Markdown treatment `WorkoutChatBubble` gives a
                // finished `.assistant` row, through the one decision in
                // `ChatMessageRendering` rather than a `true` written here. See
                // `ChatMarkdownText`'s own documentation for what a half-arrived
                // Markdown token does while this is still redrawing several times a
                // second.
                ChatMarkdownText.text(text, isMarkdown: ChatMessageRendering.isMarkdown(for: .assistant))
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .accessibleAnimation(Motion.streamingTextReveal, value: text)
            }
        case .idle, .complete, .truncated, .emptyReply, .stopped, .failed:
            // `.stopped` sits here with the rest of the terminal rungs (MAX-197): the
            // partial reply the athlete stopped has already become a row of its own in
            // the transcript, with its own caption, so this pending row has nothing left
            // to draw for it.
            EmptyView()
        }
    }

    /// The stalled rung's second channel.
    ///
    /// A caption underneath the partial reply, in the same weight and colour as the
    /// truncated and interrupted captions this transcript already uses — a stall is
    /// another thing that happened to a reply, and it should read like one rather than
    /// like an alert. Nothing about it moves, and nothing about it is coloured: the
    /// difference between "streaming" and "stalled" is a sentence, which is the only
    /// channel that survives every accessibility setting at once.
    @ViewBuilder
    private var stalledCaption: some View {
        if phase == .stalled, let status = ChatConversationCopy.pendingStatus(for: phase) {
            Text(status)
                .font(.microLabel)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func bubbleSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(Spacing.compact)
            .background(
                Color.surfaceInset,
                in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
            )
    }
}

/// A line of text with a bright band travelling through it (MAX-152).
///
/// The technique, in three parts: the words are drawn once in `Color.textSecondary` and
/// stay there; the same words are drawn again in `Color.textPrimary` on top; and that
/// second copy is masked by a gradient that slides across the width. What the eye sees is
/// a highlight moving through a legible sentence.
///
/// ## What happens when it is turned off
///
/// The animated copy is *omitted*, not slowed and not made instant, whenever **Reduce
/// Motion** or **Reduce Transparency** is on. What remains is the base text: full
/// contrast against the bubble it sits in, saying the same words. This is MAX-070's rule
/// —"a channel that vanishes under an accessibility setting was never a channel" — met by
/// making sure the animation was never a channel in the first place.
///
/// Reduce Transparency is included deliberately, though no glass is involved: a
/// brightness gradient sweeping over text is exactly the class of effect that setting is
/// reached for, and there is nothing here worth defending against somebody who has asked
/// the system to stop doing it.
private struct ShimmeringLabel: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Flipped once, on appear, to start the repeating sweep. A `repeatForever` animation
    /// needs a value change to attach to; this is that value and it never changes again.
    @State private var isSweeping = false

    private var sweeps: Bool { !reduceMotion && !reduceTransparency }

    var body: some View {
        label
            .foregroundStyle(Color.textSecondary)
            .overlay {
                if sweeps {
                    highlight
                }
            }
    }

    private var label: some View {
        Text(text)
            .font(.metricLabel)
    }

    private var highlight: some View {
        label
            .foregroundStyle(Color.textPrimary)
            .mask { sweep }
            // Purely decorative on top of text that is already there and already read.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// The travelling band, sized and moved in fractions of the label's own width, so it
    /// needs no fixed dimension and therefore nothing for Dynamic Type to break: a longer
    /// sentence at an accessibility text size gets a proportionally longer sweep.
    ///
    /// The gradient's stops are `Color.clear` and a palette token, like every other colour
    /// in this app — a gradient's stops are colours, and the design system's rule does not
    /// stop at solid fills.
    private var sweep: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.textPrimary, location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * Self.bandWidthFraction)
            .offset(x: isSweeping ? proxy.size.width : -proxy.size.width * Self.bandWidthFraction)
        }
        // Not `accessibleAnimation(_:value:)`, which substitutes a nil animation under
        // Reduce Motion: this layer is withheld entirely in that case (see `sweeps`), so
        // by the time this line runs the setting has already been honoured. The check is
        // repeated rather than assumed, because the cost of being wrong here is an
        // animation that runs forever for somebody who asked for none.
        .animation(reduceMotion ? nil : Motion.waitingSweep, value: isSweeping)
        .onAppear { isSweeping = true }
    }

    /// How wide the band is relative to the text it crosses. Under one, so there is always
    /// unhighlighted text on at least one side and the sweep reads as a highlight passing
    /// through rather than as the whole line brightening.
    private static let bandWidthFraction: CGFloat = 0.7
}
