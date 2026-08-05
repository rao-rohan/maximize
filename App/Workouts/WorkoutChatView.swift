import SwiftUI
import MaximizeCore

/// FR-2.1–2.4: the per-workout chat surface — the chat entry point
/// `WorkoutDetailView.body` marks as MAX-051's landing spot.
///
/// This view is thinner than any other section on the detail screen, and that is the
/// point: every decision — when a turn is complete, what streams versus what is shown
/// versus what is persisted, what "no key stored" or a dropped connection should say —
/// lives in `WorkoutChatModel` (`MaximizeCore`) and is unit tested there. This file
/// only renders `model.loadState`/`model.messages`/`model.streamingText` and forwards
/// `send()`, the same "observe, render, forward intent" shape every other view in this
/// app follows.
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
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Chat")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            content
        }
        .contentSurface(.card)
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.regular)
        case .failed:
            Text("Chat could not be loaded for this workout.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
        case .notYetScored:
            // Ordinary, not an error (constraint #5's sibling state): chat needs the
            // score already assigned (FR-2.1), and that arrives moments after capture
            // in the common case — see `WorkoutChatModel`'s own "why chat requires an
            // existing score."
            Text("This run hasn't been scored yet — chat opens once it has a score.")
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)
        case .ready:
            readyContent
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            if model.messages.isEmpty && !model.isStreaming {
                Text("Ask about this run — pacing, drift, whether it matched the plan.")
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
            }

            ForEach(model.messages) { message in
                WorkoutChatBubble(message: message)
            }

            if model.isStreaming {
                WorkoutChatStreamingBubble(text: model.streamingText)
            }

            composer
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.snug) {
            TextField("Ask about this run…", text: $model.composerText, axis: .vertical)
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1...4)
                .padding(Spacing.snug)
                .contentSurface(.inset)
                .onSubmit(send)
                .disabled(model.isStreaming)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(model.canSend ? Color.accent : Color.textTertiary)
            }
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        }
        .padding(.top, Spacing.tight)
    }

    private func send() {
        guard model.canSend else { return }
        Task { await model.send() }
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
