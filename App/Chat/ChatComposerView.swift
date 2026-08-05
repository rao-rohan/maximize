import SwiftUI
import MaximizeCore

/// The chat composer (§2.2's composer row), rebuilt for MAX-153.
///
/// ## Where this is installed, and why it must stay there
///
/// As a bottom `safeAreaInset` on the conversation's own container — MAX-081's fix,
/// unchanged and load-bearing. `ChatConversationView`'s own documentation carries the
/// full argument: a chat needs a scroll view whose only job is the transcript and a
/// composer pinned *outside* it, so SwiftUI lifts the composer above the keyboard as a
/// unit and insets the transcript underneath rather than displacing it. Nothing in this
/// file re-solves keyboard avoidance, and nothing in it should — putting this view
/// inside a scroll view would re-open every symptom MAX-081 closed.
///
/// ```swift
/// .safeAreaInset(edge: .bottom, spacing: 0) {
///     ChatComposerView(
///         text: $model.composerText,
///         placeholder: ChatConversationCopy.composerPlaceholder(for: model.subject?.kind),
///         sendControl: .resolve(canSend: model.canSend, isStreaming: model.isStreaming),
///         isFocused: $isComposerFocused,
///         onActivate: send,
///         accessory: { draftPlanButton }
///     )
/// }
/// ```
///
/// ## Liquid Glass, from the system rather than from a stack of modifiers
///
/// The field and the send control are **two separate glass shapes inside one
/// `GlassEffectContainer`**, not one glassed bar with flat things inside it. That is the
/// iOS 26 shape: the container is what lets the system merge the two masses when they are
/// close, light them consistently, and morph rather than cross-fade when the field grows.
/// Hand-rolling that as a blurred rectangle is exactly the "most common way a screen dates
/// itself" `CLAUDE.md` names.
///
/// Both go through `glassChrome(_:)` rather than `.glassEffect` directly, which is what
/// keeps MAX-070's Reduce Transparency fallback and MAX-040's glass-over-data tripwire in
/// force. A composer floating over a scrolling transcript is chrome by every definition in
/// `Surfaces.swift`; the transcript underneath stays flat.
///
/// **The glass shapes are the platform's, not ours.** Both the field and the button take
/// `.floatingControl`, and the role brings the system's own capsule with it — so neither
/// call site names a shape, and no `CornerRadius` constant appears in this file, because
/// `CornerRadius`'s own doc comment says chrome radii do not come from there. (The one
/// `Capsule` written out below is a `contentShape` — a hit region, not a drawn radius.)
///
/// ## A deliberate departure: no `onSubmit`
///
/// Kept from before this ticket, and worth restating because it looks like an omission.
/// With `axis: .vertical` the return key inserts a newline and `onSubmit` is never called,
/// so wiring it would be unreachable code that reads like the field can be sent from the
/// keyboard. Sending is the button — which is also the only affordance that can be
/// correctly disabled, and the only one VoiceOver can describe.
struct ChatComposerView<Accessory: View>: View {

    @Binding private var text: String

    /// `ChatConversationCopy.composerPlaceholder(for:)`. Never composed here — which
    /// string a subject gets is that type's decision.
    private let placeholder: String

    /// What the trailing control currently is. Resolved in `MaximizeCore`
    /// (`ChatComposerSendControl.resolve`) and simply drawn here.
    ///
    /// **The seam MAX-152 fills.** Two of the four states are streaming states, which are
    /// that ticket's to own: `.awaitingReply` hands this view a box with no glyph in it and
    /// this view puts a `ProgressView` there. If MAX-152 has a waiting animation, it
    /// substitutes into `activityIndicator` below and neither this view's geometry nor the
    /// core type changes. When cancellation exists, the call site passes
    /// `cancellation: .available` and the same box becomes a stop button, already sized and
    /// already labelled.
    private let sendControl: ChatComposerSendControl

    @FocusState.Binding private var isFocused: Bool

    /// Tapping the trailing control. One closure, not two, because it is one control: the
    /// caller dispatches on `sendControl` if it ever needs to. Never called while
    /// `sendControl.isEnabled` is false.
    private let onActivate: () -> Void

    /// §4.7's "Draft a plan from this conversation" row, or nothing. Passed in rather than
    /// built here so this view knows about a text field and a button and not about plans.
    private let accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The send control's hit target. `@ScaledMetric` so it tracks Dynamic Type — a 44pt
    /// box beside text that has doubled is a control that has visibly shrunk, and one that
    /// a person at that text size is more likely to need, not less.
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = LayoutMetrics.minimumTapTarget

    /// The drawn glyph inside that box. Scales on the same curve, so the ratio of slack to
    /// glyph stays constant rather than the glyph swelling to fill its target.
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = LayoutMetrics.composerSendGlyphSize

    /// Written out rather than left to the synthesized memberwise initializer: this type's
    /// `@ScaledMetric` and `@Environment` properties are `private`, which makes the
    /// synthesized one private too and therefore unusable from the view that installs this.
    init(
        text: Binding<String>,
        placeholder: String,
        sendControl: ChatComposerSendControl,
        isFocused: FocusState<Bool>.Binding,
        onActivate: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self._text = text
        self.placeholder = placeholder
        self.sendControl = sendControl
        self._isFocused = isFocused
        self.onActivate = onActivate
        self.accessory = accessory
    }

    var body: some View {
        // The container is what makes these two shapes one piece of chrome to the system
        // rather than two unrelated pieces of glass that happen to be adjacent. Spacing is
        // the ramp's, and it is also about the distance at which the two masses read as
        // related without merging into one blob.
        GlassEffectContainer(spacing: Spacing.snug) {
            VStack(spacing: Spacing.snug) {
                accessory()
                inputRow
            }
        }
        // Floating rather than edge-to-edge, so the bar ends above the home indicator
        // instead of leaving a strip of transcript below a full-width bar's bottom edge.
        .padding(.horizontal, LayoutMetrics.screenMargin)
        .padding(.top, Spacing.snug)
    }

    /// The field and the control, bottom-aligned.
    ///
    /// **`.bottom` is the whole answer to "the send control must not move line to line."**
    /// The composer is pinned to the bottom of the screen, so a growing field grows
    /// *upward*; aligning the row to its bottom edge leaves the control's centre a fixed
    /// distance above the keyboard for one line and for six. Centre alignment — the
    /// obvious default — would walk the button up half a line for every line typed, which
    /// is the moving-target failure this ticket is a reaction to.
    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: Spacing.snug) {
            field
            sendButton
        }
    }

    private var field: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.bodyCopy)
            .foregroundStyle(Color.textPrimary)
            // Grows to the ceiling, then scrolls its own text. See
            // `LayoutMetrics.composerLineCeiling` for why there is a ceiling at all.
            .lineLimit(1...lineCeiling)
            .focused($isFocused)
            .textInputAutocapitalization(.sentences)
            // Padding sized so one line of `bodyCopy` fills the same height the send
            // control does: the two capsules sit level at rest rather than the field
            // reading as a shorter sibling. `minHeight` is the floor that guarantees it
            // rather than an assumption about the font's line height.
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, Spacing.snug)
            .frame(minHeight: controlSize)
            // `.floatingControl`, not `.toolbar`: this is a control floating over
            // scrolling content, and the role brings the system's own capsule with it —
            // so no shape is named here at all. `CornerRadius`'s doc comment says chrome
            // radii do not come from the design system, and this is what that looks like
            // at a call site.
            .glassChrome(.floatingControl)
    }

    /// The trailing control, in all four of its states.
    ///
    /// One `Button` for every state rather than a `Button` sometimes and a bare view
    /// others: the frame, the hit area and the accessibility element are then identical in
    /// each, which is what makes the target stable while a reply arrives. `.disabled` is
    /// what carries un-pressability, so the platform supplies its own dimming and its own
    /// VoiceOver trait rather than this view painting a "looks disabled" tint that nothing
    /// else can read.
    private var sendButton: some View {
        Button(action: activate) {
            controlContent
                .frame(width: controlSize, height: controlSize)
                // Everything inside the 44pt box responds, not only the 28pt glyph.
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!sendControl.isEnabled)
        .glassChrome(.floatingControl)
        .accessibilityLabel(sendControl.accessibilityLabel)
        // Empty for the states the core says carry neither — VoiceOver skips an empty
        // string, which is the same outcome as not applying the modifier and avoids two
        // branches of an otherwise identical control.
        .accessibilityValue(sendControl.accessibilityValue ?? "")
        .accessibilityHint(sendControl.accessibilityHint ?? "")
        // Content-driven transition between the four states rather than a cross-fade of
        // two whole controls. Reduce Motion is honoured by `accessibleAnimation`, which is
        // MAX-070's seam for exactly this and not something re-derived here.
        .accessibleAnimation(.easeOut(duration: 0.15), value: sendControl)
    }

    @ViewBuilder
    private var controlContent: some View {
        if let systemImageName = sendControl.systemImageName {
            Image(systemName: systemImageName)
                .font(.system(size: glyphSize))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(sendControl.isEnabled ? Color.accent : Color.textTertiary)
        } else {
            activityIndicator
        }
    }

    /// The hook MAX-152 owns. A reply is arriving and cannot be stopped; something has to
    /// occupy the control's box so the row does not reflow when the state changes, and this
    /// is the plainest honest thing that can. **MAX-152's waiting animation replaces the
    /// body of this property and nothing else** — the box is already the right size and the
    /// state is already resolved in the core.
    private var activityIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .tint(Color.textSecondary)
    }

    /// Below the ceiling at accessibility text sizes: six lines of AX5 body copy is most of
    /// a phone, and a composer that covers the conversation is the failure the ceiling
    /// exists to prevent, only worse. The field still scrolls past three, so nothing
    /// becomes unreachable — only the resting height changes.
    private var lineCeiling: Int {
        dynamicTypeSize.isAccessibilitySize
            ? LayoutMetrics.composerLineCeilingAtAccessibilitySizes
            : LayoutMetrics.composerLineCeiling
    }

    private func activate() {
        guard sendControl.isEnabled else { return }
        onActivate()
    }
}

extension ChatComposerView where Accessory == EmptyView {
    /// A composer with nothing above its input row — a workout thread, where §4.7's
    /// drafting action is absent by design (`ChatModel.canDraftPlan` is false there).
    init(
        text: Binding<String>,
        placeholder: String,
        sendControl: ChatComposerSendControl,
        isFocused: FocusState<Bool>.Binding,
        onActivate: @escaping () -> Void
    ) {
        self.init(
            text: text,
            placeholder: placeholder,
            sendControl: sendControl,
            isFocused: isFocused,
            onActivate: onActivate,
            accessory: { EmptyView() }
        )
    }
}

/// The way back to the newest turn, offered whenever the athlete has scrolled away from it
/// (MAX-153).
///
/// Sits over the transcript, above the composer. Its *behaviour* — when it appears, what it
/// says, whether arriving content moved anything — is `ChatTranscriptFollow`
/// (`MaximizeCore`) and is unit tested; this view draws a title and forwards a tap.
///
/// ## Words, not a coloured dot
///
/// The interesting distinction is "you scrolled up" versus "you scrolled up and then
/// something arrived", and the tempting way to draw the second is a tinted badge. That is
/// information by hue alone, which `CLAUDE.md` rules out for a badge exactly as it does for
/// a score band. `ChatTranscriptFollow.jumpToLatestTitle` carries the difference in the
/// label instead — "Jump to latest" against "New reply" — and the glyph stays the same in
/// both, so the control does not change shape underneath a returning eye either.
struct ChatJumpToLatestButton: View {
    let follow: ChatTranscriptFollow
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var minimumHeight: CGFloat = LayoutMetrics.minimumTapTarget

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.tight) {
                Image(systemName: "arrow.down")
                    .accessibilityHidden(true)
                Text(follow.jumpToLatestTitle)
                    .lineLimit(1)
            }
            .font(.metricLabel)
            .foregroundStyle(Color.accent)
            .padding(.horizontal, Spacing.compact)
            .frame(minHeight: minimumHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .glassChrome(.floatingControl)
        .accessibilityLabel(follow.jumpToLatestTitle)
        .accessibilityHint(follow.jumpToLatestAccessibilityHint)
    }
}
