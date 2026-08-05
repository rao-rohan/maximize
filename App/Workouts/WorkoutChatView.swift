import SwiftUI
import MaximizeCore

/// FR-2.1–2.4: the per-workout chat surface, reached from `WorkoutChatSectionView` on
/// the detail screen.
///
/// This view is thinner than any other section on the detail screen, and that is the
/// point: every decision — when a turn is complete, what streams versus what is shown
/// versus what is persisted, what "no key stored" or a dropped connection should say —
/// lives in `WorkoutChatModel` (`MaximizeCore`) and is unit tested there. This file
/// only renders `model.loadState`/`model.messages`/`model.streamingText` and forwards
/// `send()`, the same "observe, render, forward intent" shape every other view in this
/// app follows. MAX-081 changed where it is presented and how the keyboard behaves; it
/// changed nothing the model does.
///
/// ## Why chat is its own screen now (MAX-081)
///
/// It used to be a card inside `WorkoutDetailView`'s outer `ScrollView`, with a growing
/// `TextField(axis: .vertical)` at the bottom of that card. That arrangement cannot be
/// made to behave, because three things fight over the same scroll offset:
///
/// 1. **Keyboard avoidance** insets the *outer* scroll view — the one holding the HR
///    curve, the map and the splits — to reveal a field nested several containers down.
///    The screen jumps by however far that is, which is most of its height.
/// 2. **The field grows** as you type. Each new line re-lays-out the card, which
///    re-triggers avoidance against a target that has just moved.
/// 3. **The reply streams in above the composer.** Content is being appended to the
///    same scroll view whose offset avoidance is trying to hold, so the composer walks
///    down under the keyboard while the answer arrives.
///
/// None of that is fixable with a modifier. A chat needs a scroll view whose *only*
/// job is the transcript and a composer pinned outside it, which is what this screen
/// is: the composer is a bottom `safeAreaInset`, so SwiftUI lifts it above the keyboard
/// as a unit and the transcript insets underneath it rather than being displaced.
///
/// The cost is honest and worth naming: the transcript is now behind a tap instead of
/// visible when you scroll to the bottom of a workout. Given that reading a reply
/// previously meant scrolling a screen that moved while you read it, that trade is
/// clearly right.
///
/// ## Construction, not a default
///
/// Every repository is named explicitly here, the same way `SettingsModel`'s own
/// documentation insists on — `WorkoutChatModel`'s initializer has no default for any
/// of them (`MaximizeCore` cannot see `PersistenceComposition`), so this call site is
/// the one place that supplies it. MAX-049 was a defaulted parameter silently
/// resolving to a no-op stub in two files; there is nothing here for a future edit to
/// default away by accident.
struct WorkoutChatView: View {
    // `@State`, matching `WorkoutDetailView`'s own pattern: this view creates and owns
    // the model, and `@State` derives `$model.composerText` for the composer's
    // `TextField` directly for an `@Observable` class — no `@Bindable` needed for a
    // model the view owns rather than receives.
    @State private var model: WorkoutChatModel

    /// Owned here rather than by the presenting view so that dismissing the screen and
    /// releasing the keyboard are the same action — see the `Done` button below.
    @FocusState private var isComposerFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The transcript's trailing anchor. Scrolling to a fixed empty view is stable in a
    /// way scrolling to "the last message" is not: the last message's identity changes
    /// as a reply streams, and its own height changes underneath the scroll.
    private static let transcriptBottomAnchor = "transcript-bottom"

    init(workoutID: UUID) {
        _model = State(
            initialValue: WorkoutChatModel(
                workoutID: workoutID,
                workoutRepository: PersistenceComposition.store,
                scoreRepository: PersistenceComposition.store,
                planRepository: PersistenceComposition.store,
                chatThreadRepository: PersistenceComposition.store,
                chatClient: AnthropicStreamingChatClient(keyStore: KeychainAnthropicAPIKeyStore())
            )
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentSurface(.screen)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Release focus before dismissing so the keyboard leaves with
                        // the sheet rather than after it.
                        isComposerFocused = false
                        dismiss()
                    }
                }
            }
            .task {
                await model.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            centered {
                ProgressView()
            }
        case .failed:
            centered {
                secondaryText("Chat could not be loaded for this workout.")
            }
        case .notYetScored:
            // Ordinary, not an error (constraint #5's sibling state): chat needs the
            // score already assigned (FR-2.1), and that arrives moments after capture
            // in the common case — see `WorkoutChatModel`'s own "why chat requires an
            // existing score."
            centered {
                secondaryText("This run hasn't been scored yet — chat opens once it has a score.")
            }
        case .noVerdict:
            // The same absence, and the opposite tense (MAX-126). The sentence above
            // would be a promise here: the plan scores runs, so this workout will never
            // have the score chat is seeded from. Said once, plainly, in the same voice
            // the verdict header uses on the screen behind this sheet.
            centered {
                secondaryText(
                    "The plan scores runs, so there's no score for this workout — "
                        + "and chat starts from one."
                )
            }
        case .ready:
            transcript
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    if model.messages.isEmpty && !model.isStreaming {
                        secondaryText("Ask about this run — pacing, drift, whether it matched the plan.")
                    }

                    ForEach(model.messages) { message in
                        WorkoutChatBubble(message: message)
                    }

                    if model.isStreaming {
                        WorkoutChatStreamingBubble(text: model.streamingText)
                    }

                    Color.clear
                        .frame(height: LayoutMetrics.hairline)
                        .id(Self.transcriptBottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .screenMargins()
                .padding(.vertical, Spacing.regular)
            }
            // The transcript is the only thing scrolling here, so a drag toward the
            // keyboard can dismiss it without disturbing anything else — the affordance
            // that was impossible while this lived inside the detail screen's scroll
            // view, where the same gesture was how you read the rest of the workout.
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { scrollToBottom(proxy) }
            .onChange(of: model.isStreaming) { scrollToBottom(proxy) }
            .onChange(of: isComposerFocused) {
                guard isComposerFocused else { return }
                scrollToBottom(proxy)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.snug) {
            // No `onSubmit` and no `submitLabel`. With `axis: .vertical` the return key
            // inserts a newline and `onSubmit` is never called, so the previous
            // `.onSubmit(send)` here was unreachable code that read like the field
            // could be sent from the keyboard. Sending is the button, which is also
            // the only affordance that can be correctly disabled by `canSend`.
            TextField("Ask about this run…", text: $model.composerText, axis: .vertical)
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .padding(Spacing.snug)
                .contentSurface(.inset)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(model.canSend ? Color.accent : Color.textTertiary)
            }
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        }
        // A bar pinned over scrolling content is chrome, not a data surface, so glass
        // is the correct treatment (FR-4.2). `.contentSurface(.inset)` above marks only
        // the text field's own subtree, which sits below this modifier — the misuse
        // assertion reads the environment where `glassChrome` is applied, and that is
        // outside it.
        //
        // Floating rather than edge-to-edge, so the bar ends above the home indicator
        // instead of leaving a strip of transcript below a full-width bar's bottom edge.
        .padding(Spacing.snug)
        .glassChrome(.toolbar)
        .padding(.horizontal, LayoutMetrics.screenMargin)
        .padding(.top, Spacing.snug)
    }

    /// Note what is deliberately **not** here: the field is no longer disabled while a
    /// reply streams. Disabling a focused `TextField` makes SwiftUI resign its focus,
    /// so the keyboard dropped the moment you hit send and did not come back when the
    /// reply finished — one of the "keyboard is buggy" symptoms, and an unforced one.
    /// `canSend` still gates sending, on both the button and this guard, so nothing can
    /// be submitted mid-stream; you can simply keep typing the next question.
    private func send() {
        guard model.canSend else { return }
        Task { await model.send() }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.2)
        withAnimation(animation) {
            proxy.scrollTo(Self.transcriptBottomAnchor, anchor: .bottom)
        }
    }

    private func secondaryText(_ text: String) -> some View {
        Text(text)
            .font(.bodyCopy)
            .foregroundStyle(Color.textSecondary)
    }

    private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .screenMargins()
            .padding(.top, Spacing.hero)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One row of the transcript. Purely a rendering of `WorkoutChatModel.DisplayMessage`
/// — every one of its flags (`wasTruncated`, `wasInterruptedByFailure`) is something
/// the model already decided, not something this view infers.
private struct WorkoutChatBubble: View {
    let message: WorkoutChatModel.DisplayMessage

    var body: some View {
        switch message.kind {
        case .user:
            bubbleRow(alignment: .trailing) {
                bubble(fill: Color.accent, textColor: Color.textOnSaturatedFill)
            }
        case .assistant:
            bubbleRow(alignment: .leading) {
                VStack(alignment: .leading, spacing: Spacing.hairspace) {
                    bubble(fill: Color.surfaceInset, textColor: Color.textPrimary)
                    // FR-2.4: `.completed(.truncated)` is a real, storable reply that
                    // simply ran out of room — `ChatTurnCompletion`'s own documentation
                    // says the UI is what should say so.
                    if message.wasTruncated {
                        caption("Cut short — hit the reply length limit.")
                    }
                    // Constraint #4: partial text survives a failure, on screen.
                    if message.wasInterruptedByFailure {
                        caption("Connection dropped before this reply finished.")
                    }
                }
            }
        case .notice:
            Text(message.text)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func bubble(fill: Color, textColor: Color) -> some View {
        Text(message.text)
            .font(.bodyCopy)
            .foregroundStyle(textColor)
            .padding(Spacing.compact)
            .background(fill, in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.microLabel)
            .foregroundStyle(Color.textTertiary)
    }

    @ViewBuilder
    private func bubbleRow<Content: View>(
        alignment: HorizontalAlignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if alignment == .trailing { Spacer(minLength: Spacing.hero) }
            content()
            if alignment == .leading { Spacer(minLength: Spacing.hero) }
        }
    }
}

/// The reply as it arrives. FR-4.4 names "streaming-text reveal" directly as the kind
/// of motion this app wants; `accessibleAnimation` is MAX-070's seam for it, so this is
/// the first call site to use it rather than the first to reinvent Reduce Motion
/// handling.
private struct WorkoutChatStreamingBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(text.isEmpty ? "…" : text)
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)
                .padding(Spacing.compact)
                .background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous))
                .accessibleAnimation(.easeOut(duration: 0.15), value: text)
            Spacer(minLength: Spacing.hero)
        }
    }
}
