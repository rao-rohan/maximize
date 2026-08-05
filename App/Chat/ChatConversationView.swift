import SwiftUI
import MaximizeCore

/// FR-2.1–2.4: the transcript and composer for one thread, of either subject (MAX-097,
/// A11).
///
/// This is `WorkoutChatView` before this ticket, generalised: the transcript, the
/// composer, and every one of `ChatModel`'s states still render exactly as they did
/// (the workout path is a deliberate regression test — see `ChatModel`'s own MAX-096
/// documentation). What is new is the toolbar (§2.2) — title, subtitle, the leading
/// history button, **New chat**, and Done — which lives here rather than on `ChatSheet`,
/// because `model.title`/`model.subtitle` only exist where `model` does. `ChatSheet`
/// owns the `NavigationStack` these attach to and forwards three intents this view
/// cannot itself fulfil: opening the thread list is a push only the stack's owner can
/// do, and Done needs `\.dismiss` from the sheet's own presentation.
///
/// This view is thinner than any other section on the detail screen, and that is the
/// point: every decision — when a turn is complete, what streams versus what is shown
/// versus what is persisted, what "no key stored" or a dropped connection should say —
/// lives in `ChatModel` (`MaximizeCore`) and is unit tested there. This file only
/// renders `model.loadState`/`model.messages`/`model.replyPhase`/`model.streamingText`
/// and forwards `send()` and `retry()`, the same "observe, render, forward intent" shape
/// every other view in this app follows.
///
/// **`model.replyPhase` is the newest instance of that (MAX-152).** Waiting, streaming
/// and stalled are three states of one request and used to be one boolean here, which is
/// why all three drew the same ellipsis. Which one is showing is now decided by
/// `ChatReplyProgress` in the core, from stream events, under test; this view branches on
/// the answer and inspects nothing about the stream itself.
///
/// ## Subject-dependent copy, never re-decided here
///
/// The empty-transcript invitation, the composer's placeholder and the "could not load"
/// notice all differ by subject — "this run" is a lie on a thread about a month. Which
/// string to show is `ChatConversationCopy`'s decision (`MaximizeCore`); this view only
/// asks for the one that matches `model.subject?.kind` — nil exactly when a thread-id-
/// opened model has not yet resolved a subject, which each of the three degrades for
/// on its own rather than this view guessing at a fallback.
///
/// ## Why chat is its own screen (MAX-081)
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
/// ## Construction, not a default
///
/// Every repository is named explicitly here, the same way `SettingsModel`'s own
/// documentation insists on — `ChatModel`'s initializer has no default for any
/// of them (`MaximizeCore` cannot see `PersistenceComposition`), so this call site is
/// the one place that supplies it. MAX-049 was a defaulted parameter silently
/// resolving to a no-op stub in two files; there is nothing here for a future edit to
/// default away by accident.
///
/// ## Two initializers, mirroring `ChatModel`'s two entry points (MAX-097 review)
///
/// `init(subject:...)` is the Ask button and **New chat** — the subject is what they
/// are asking for. `init(threadID:...)` is the thread list (§2.3) — a specific row was
/// tapped, and `ChatModel.init(threadID:...)` is what reads its subject off the *stored*
/// thread rather than trusting whatever this view might have been told, which is what
/// keeps a row tap from ever opening a different thread than the one shown (subjects are
/// not unique: two training threads can legitimately share an identical frozen window).
/// Both funnel into the same private initializer, which is the one place that owns
/// wiring the closures and `currentInterval`.
struct ChatConversationView: View {
    // `@State`, matching `WorkoutDetailView`'s own pattern: this view creates and owns
    // the model, and `@State` derives `$model.composerText` for the composer's
    // `TextField` directly for an `@Observable` class — no `@Bindable` needed for a
    // model the view owns rather than receives.
    @State private var model: ChatModel

    /// §3.6(b)'s note, when this thread's frozen scope no longer matches the window the
    /// dashboard is showing right now. Nil for a workout subject unconditionally
    /// (`ChatScopeNotice`'s own rule) and nil for a training subject in the common case
    /// where nothing has drifted.
    let currentInterval: TrendInterval?

    /// Forwarded from `ChatSheet`: pushes the thread list (§2.3) onto the sheet's own
    /// navigation stack. This view has no path to append to — only the stack's owner
    /// does — so it only ever asks.
    let onOpenThreadList: () -> Void

    /// Forwarded from `ChatSheet`: what **New chat** does. The banner above offers the
    /// same action as the toolbar button, worded around the mismatch rather than
    /// generically, so tapping either one always starts a thread on the window actually
    /// on screen.
    let onStartNewChatForCurrentWindow: () -> Void

    /// Forwarded from `ChatSheet`: what accepting a plan proposal does (MAX-101, §4.6).
    /// Pushing `PlanAuthoringView` is something only the stack's owner can do, so this
    /// view hands the proposal up and `ChatSheet` opens the screen prefilled.
    ///
    /// The proposal travels rather than a draft or a plan: the authoring screen builds
    /// its own session against storage, as it always has. See `ChatModel`'s own note on
    /// `proposalAwaitingReview`.
    let onAcceptProposal: (PlanProposal) -> Void

    /// Forwarded from `ChatSheet`: §6.2's chip tap, on the runs strip below the
    /// transcript (MAX-103). Pushing that run's detail screen is something only the
    /// stack's owner can do, exactly like `onOpenThreadList` and `onAcceptProposal`
    /// above — this view only ever names which run was tapped.
    let onSelectRun: (UUID) -> Void

    /// Forwarded from `ChatSheet`, whose `\.dismiss` this view does not have — it was
    /// not presented, `ChatSheet` was.
    let onDone: () -> Void

    /// Owned here rather than by the presenting view so that dismissing the screen and
    /// releasing the keyboard are the same action — see the Done button below.
    @FocusState private var isComposerFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The transcript's trailing anchor. Scrolling to a fixed empty view is stable in a
    /// way scrolling to "the last message" is not: the last message's identity changes
    /// as a reply streams, and its own height changes underneath the scroll.
    private static let transcriptBottomAnchor = "transcript-bottom"

    /// §2.2: the Ask button and **New chat**, both of which already know the subject.
    init(
        subject: ChatSubject,
        currentInterval: TrendInterval?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            model: ChatModel(
                subject: subject,
                workoutRepository: PersistenceComposition.store,
                scoreRepository: PersistenceComposition.store,
                planRepository: PersistenceComposition.store,
                settingsRepository: PersistenceComposition.store,
                chatThreadRepository: PersistenceComposition.store,
                chatClient: AnthropicStreamingChatClient(keyStore: KeychainAnthropicAPIKeyStore()),
                planProposalClient: AnthropicPlanProposalClient(keyStore: KeychainAnthropicAPIKeyStore())
            ),
            currentInterval: currentInterval,
            onOpenThreadList: onOpenThreadList,
            onStartNewChatForCurrentWindow: onStartNewChatForCurrentWindow,
            onAcceptProposal: onAcceptProposal,
            onSelectRun: onSelectRun,
            onDone: onDone
        )
    }

    /// §2.3: a row tapped in the thread list. See this type's own "Two initializers"
    /// note for why the subject is never a parameter here.
    init(
        threadID: UUID,
        currentInterval: TrendInterval?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            model: ChatModel(
                threadID: threadID,
                workoutRepository: PersistenceComposition.store,
                scoreRepository: PersistenceComposition.store,
                planRepository: PersistenceComposition.store,
                settingsRepository: PersistenceComposition.store,
                chatThreadRepository: PersistenceComposition.store,
                chatClient: AnthropicStreamingChatClient(keyStore: KeychainAnthropicAPIKeyStore()),
                planProposalClient: AnthropicPlanProposalClient(keyStore: KeychainAnthropicAPIKeyStore())
            ),
            currentInterval: currentInterval,
            onOpenThreadList: onOpenThreadList,
            onStartNewChatForCurrentWindow: onStartNewChatForCurrentWindow,
            onAcceptProposal: onAcceptProposal,
            onSelectRun: onSelectRun,
            onDone: onDone
        )
    }

    private init(
        model: ChatModel,
        currentInterval: TrendInterval?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.currentInterval = currentInterval
        self.onOpenThreadList = onOpenThreadList
        self.onStartNewChatForCurrentWindow = onStartNewChatForCurrentWindow
        self.onAcceptProposal = onAcceptProposal
        self.onSelectRun = onSelectRun
        self.onDone = onDone
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentSurface(.screen)
            // §2.2: the thread's derived title, inline, and its scope as a subtitle
            // (§2.4, §3.6(b)) — both read straight off `model`, never re-derived here.
            .navigationTitle(model.title)
            .navigationSubtitle(model.subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                await model.load()
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onOpenThreadList) {
                Label("Chat history", systemImage: "list.bullet")
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Chat history")
        }
        // §2.2: "New chat — training subjects only; absent for a workout subject." A
        // workout thread is one thread per run (§12, question 3 of the spec) and has
        // nothing for a second thread to be about. `subject` is nil only while a
        // thread-id-opened model is still resolving, or after it failed to — either
        // way, the honest answer is "not yet known to be training", so the button
        // stays hidden rather than guessing.
        if model.subject?.kind == .training {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat", action: onStartNewChatForCurrentWindow)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                // Release focus before dismissing so the keyboard leaves with the sheet
                // rather than after it.
                isComposerFocused = false
                onDone()
            }
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
                secondaryText(ChatConversationCopy.failedToLoad(for: model.subject?.kind))
            }
        case .threadNotFound:
            // §2.3: reached by a thread id (a row tapped in the list, or resumed from
            // one) that no longer resolves to a stored thread — most often because it,
            // or the workout it belonged to, was deleted from another screen. Ordinary,
            // not a failure: `ChatConversationCopy.threadNotFound` says so plainly
            // rather than this screen guessing at a subject it never learned.
            centered {
                secondaryText(ChatConversationCopy.threadNotFound)
            }
        case .notYetScored:
            // Ordinary, not an error (constraint #5's sibling state): chat needs the
            // score already assigned (FR-2.1), and that arrives moments after capture
            // in the common case — see `ChatModel`'s own "why chat requires an
            // existing score." Workout subjects only — `ChatModel` never reaches this
            // state for a training thread.
            centered {
                secondaryText(ChatConversationCopy.notYetScored)
            }
        case .noVerdict:
            // The same absence, and the opposite tense (MAX-126). The sentence above
            // would be a promise here: the plan scores runs, so this workout will never
            // have the score chat is seeded from. Said once, plainly, in the same voice
            // the verdict header uses on the screen behind this sheet.
            centered {
                secondaryText(ChatConversationCopy.noVerdict)
            }
        case .ready:
            VStack(spacing: 0) {
                // `model.subject` is always non-nil by `.ready` (`ChatModel.load()`
                // only reaches it after resolving one) — unwrapped rather than
                // force-unwrapped so that invariant stays enforced by a guard, not by
                // trust. `currentInterval` is nil only for the one caller today that
                // has no live dashboard selection to hand in (the workout entry
                // point) — and `ChatScopeNotice` only ever has something to say about
                // a training subject in the first place, so a nil interval here just
                // means the banner has nothing to compare against, not that the
                // comparison failed.
                if let subject = model.subject, let currentInterval,
                   let notice = ChatScopeNotice.text(for: subject, currentInterval: currentInterval) {
                    scopeMismatchBanner(notice)
                }
                transcript
                // §2.2's "Runs strip" row, below the transcript and above the composer.
                // `nil` for a workout subject — `RunsStripView` renders nothing then.
                RunsStripView(data: model.runsStripData, onSelectRun: onSelectRun)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
    }

    /// §3.6(b): "a quiet one-line note offering a new chat on the current interval."
    /// Placed above the transcript rather than interleaved with it, so it reads as a
    /// property of the conversation rather than as something either party said.
    private func scopeMismatchBanner(_ notice: String) -> some View {
        Button(action: onStartNewChatForCurrentWindow) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.microLabel)
                Text(notice)
                    .font(.microLabel)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenMargins()
            .padding(.vertical, Spacing.snug)
        }
        .buttonStyle(.plain)
        .contentSurface(.inset)
        .padding(.horizontal, LayoutMetrics.screenMargin)
        .padding(.top, Spacing.snug)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    if model.messages.isEmpty && !model.isStreaming {
                        secondaryText(ChatConversationCopy.emptyTranscriptInvitation(for: model.subject?.kind))
                    }

                    ForEach(model.messages) { message in
                        WorkoutChatBubble(message: message)
                    }

                    // MAX-152: waiting, streaming and stalled are three rungs of one
                    // ladder, and which one is showing was decided in `MaximizeCore`.
                    // This view hands the phase over and draws what comes back — it
                    // reads no timings, counts no tokens and branches on nothing about
                    // the stream.
                    ChatPendingReplyView(phase: model.replyPhase, text: model.streamingText)

                    retryButton

                    // §4.6: the proposal appears *in the transcript*, as a card, at the
                    // end — it is the most recent thing that happened. It is not a
                    // bubble, because it is not something either party said, and
                    // `ChatModel` never writes it to the thread.
                    planDraftingContent

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
            // The phase rather than a streaming flag (MAX-152): the placeholder giving
            // way to the first tokens, and a stall growing a caption underneath the
            // partial reply, both change the transcript's height without changing the
            // message count.
            .onChange(of: model.replyPhase) { scrollToBottom(proxy) }
            .onChange(of: model.planDrafting) { scrollToBottom(proxy) }
            .onChange(of: isComposerFocused) {
                guard isComposerFocused else { return }
                scrollToBottom(proxy)
            }
        }
    }

    /// MAX-152: "Try again", offered for exactly the failures where asking again could
    /// help.
    ///
    /// `model.canRetry` is the whole condition, and it is `ChatModel`'s — a missing key,
    /// a rejected key, a refusal and a reply this app could not read all answer false,
    /// because a button that re-runs a call guaranteed to fail identically is worse than
    /// no button. The failure's own notice, immediately above, says what to do instead in
    /// each of those cases.
    ///
    /// One tap, one call. Nothing here retries on a timer or on appearance (A14).
    @ViewBuilder
    private var retryButton: some View {
        if model.canRetry {
            Button(ChatConversationCopy.retryAction) {
                Task { await model.retry() }
            }
            .buttonStyle(.bordered)
            .tint(Color.accent)
            .font(.metricLabel)
            .accessibilityHint(ChatConversationCopy.retryActionHint)
        }
    }

    // MARK: - Drafting a plan from the conversation (MAX-101, §4)

    /// What the transcript shows for the plan-drafting action: nothing, a progress line,
    /// or the card.
    ///
    /// Every branch reads `model.planDrafting` — this view never infers a state from the
    /// presence of a value, and never calls `draftPlan()` from `onAppear` or a timer. A14
    /// is an invariant, not a default.
    @ViewBuilder
    private var planDraftingContent: some View {
        switch model.planDrafting {
        case .idle:
            EmptyView()
        case .drafting:
            HStack(spacing: Spacing.snug) {
                ProgressView()
                Text("Drafting a plan from this conversation…")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case let .proposed(review):
            PlanProposalCardView(
                review: review,
                onAccept: { onAcceptProposal(review.proposal) },
                onDiscard: { model.discardProposal() }
            )
        }
    }

    /// §4.7's "Draft a plan from this conversation", as a separate action rather than
    /// something the model emits mid-stream.
    ///
    /// Pinned above the composer rather than buried in the toolbar: it is the one action
    /// this screen exists to make possible, it costs exactly one call per tap (A14), and
    /// a training thread's toolbar already carries **New chat**. Absent entirely on a
    /// workout thread — `canDraftPlan` is false there and there is nothing for a disabled
    /// button to teach.
    @ViewBuilder
    private var draftPlanButton: some View {
        if model.subject?.kind == .training {
            Button(action: draftPlan) {
                Label("Draft a plan from this conversation", systemImage: "list.clipboard")
                    .font(.metricLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.accent)
            .disabled(!model.canDraftPlan)
            .accessibilityHint(
                "Asks Claude for a plan built from this conversation. You review it before anything is saved."
            )
        }
    }

    private func draftPlan() {
        guard model.canDraftPlan else { return }
        Task { await model.draftPlan() }
    }

    /// The bottom bar: §4.7's drafting action above the input row, in one glass
    /// container.
    ///
    /// One container rather than two stacked bars, because two floating glass surfaces
    /// over the same transcript is chrome competing with itself — and because the two
    /// belong together: both are things you do *to* this conversation.
    private var composer: some View {
        VStack(spacing: Spacing.snug) {
            draftPlanButton
            inputRow
        }
        // A bar pinned over scrolling content is chrome, not a data surface, so glass
        // is the correct treatment (FR-4.2). `.contentSurface(.inset)` below marks only
        // the text field's own subtree, which sits under this modifier — the misuse
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

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: Spacing.snug) {
            // No `onSubmit` and no `submitLabel`. With `axis: .vertical` the return key
            // inserts a newline and `onSubmit` is never called, so the previous
            // `.onSubmit(send)` here was unreachable code that read like the field
            // could be sent from the keyboard. Sending is the button, which is also
            // the only affordance that can be correctly disabled by `canSend`.
            TextField(
                ChatConversationCopy.composerPlaceholder(for: model.subject?.kind),
                text: $model.composerText,
                axis: .vertical
            )
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
        // `Motion.scrollSettle` rather than a duration written here (MAX-152): the ramp
        // names the job, and a second call site that wanted "about the same speed" is how
        // a design system ends up with three of them.
        let animation: Animation? = reduceMotion ? nil : Motion.scrollSettle
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

/// One row of the transcript. Purely a rendering of `ChatModel.DisplayMessage`
/// — every one of its flags (`wasTruncated`, `wasInterruptedByFailure`) is something
/// the model already decided, not something this view infers.
private struct WorkoutChatBubble: View {
    let message: ChatModel.DisplayMessage

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
                        caption(ChatConversationCopy.truncatedCaption)
                    }
                    // Constraint #4: partial text survives a failure, on screen.
                    if message.wasInterruptedByFailure {
                        caption(ChatConversationCopy.interruptedByFailureCaption)
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

// The reply-in-flight bubble used to live here as `WorkoutChatStreamingBubble`, drawing
// an ellipsis whenever there was no text yet. MAX-152 replaced it with
// `ChatPendingReplyView`, because that ellipsis was three different states wearing one
// face: a request with nothing back, a reply arriving, and a reply that had stopped
// arriving all rendered identically. The states are `ChatReplyPhase`'s now, and the
// drawing is that file's.
