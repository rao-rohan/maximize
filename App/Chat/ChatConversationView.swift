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
/// **MAX-153 did the same to the two things left in this file that were still decisions.**
/// The composer's trailing control is `ChatComposerSendControl`, resolved from `canSend`
/// and `replyPhase` — not a tint computed inline from a boolean. Whether an arriving token
/// is allowed to move the viewport is `ChatTranscriptFollow`, and the answer is usually
/// *no*: this screen used to scroll to the bottom on every change, including when the
/// athlete had scrolled up to re-read something. Both types are in `MaximizeCore` with
/// tests; what is left here is classifying an `onChange` and obeying the directive.
///
/// ## A day separator, decided in the core (§6.8, MAX-201)
///
/// The one addition this ticket makes to the transcript loop: `daySeparatorLabels`
/// below asks `ChatTranscriptDaySeparators` (`MaximizeCore`) which rows start a new
/// calendar day, and `ForEach` draws `ChatDaySeparatorView` before any row it names.
/// Nothing about *which* rows those are, or what the label says, is decided in this
/// file — a conversation resumed the next morning is a `CalendarDay` comparison over
/// stored timestamps, and that is exactly the kind of date arithmetic CLAUDE.md's
/// "thin shell" rule keeps out of a view.
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
/// MAX-153 replaced what sits *in* that inset — `ChatComposerView` now — and changed
/// nothing about the arrangement itself, which is the part that was load-bearing.
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
/// ## Three initializers, mirroring `ChatModel`'s three entry points (MAX-097 review,
/// MAX-185)
///
/// `init(subject:...)` is the Ask button and the scope-mismatch banner's own action —
/// the subject is what they are asking for, and `ChatModel` resolves *the* thread for
/// it. `init(startingNewThreadFor:...)` is **New chat**: the same subject, but
/// `ChatModel.init(startingNewThreadFor:...)` mints a fresh thread rather than
/// resolving one — see that initializer's own documentation for why "New chat" cannot
/// share `init(subject:...)`'s resolve behaviour, even when the scope has not changed.
/// `init(threadID:...)` is the thread list (§2.3) — a specific row was tapped, and
/// `ChatModel.init(threadID:...)` is what reads its subject off the *stored* thread
/// rather than trusting whatever this view might have been told, which is what keeps a
/// row tap from ever opening a different thread than the one shown (subjects are not
/// unique: two training threads can legitimately share an identical frozen window, and
/// **New chat** is exactly what makes that a routine occurrence rather than a race).
/// All three funnel into the same private initializer, which is the one place that owns
/// wiring the closures and `currentInterval`.
///
/// `init(subject:...)` also carries `continuityNote` (MAX-194, defaulted nil) — the one
/// line `PlanConversationDoor` composed when this call is the far side of that door
/// rather than the Ask button. See that parameter's own documentation.
struct ChatConversationView: View {
    // `@State`, matching `WorkoutDetailView`'s own pattern: this view creates and owns
    // the model, and `@State` derives `$model.composerText` — the binding
    // `ChatComposerView` writes through — directly for an `@Observable` class, with no
    // `@Bindable` needed for a model the view owns rather than receives.
    @State private var model: ChatModel

    /// §3.6(b)'s note, when this thread's frozen scope no longer matches the window the
    /// dashboard is showing right now. Nil for a workout subject unconditionally
    /// (`ChatScopeNotice`'s own rule) and nil for a training subject in the common case
    /// where nothing has drifted.
    let currentInterval: TrendInterval?

    /// MAX-194: the one line of continuity `PlanConversationDoor` composed, when this
    /// thread was opened by walking through that door from a run's conversation. Nil on
    /// every other path in — the Ask button, the scope-mismatch banner, **New chat**,
    /// and the thread list all pass nothing, because none of them carried the athlete
    /// over from somewhere else. Rendered as a screen-only caption (`continuityBanner`
    /// below) and never read by anything that builds a prompt — see
    /// `PlanConversationDoor`'s own "How much continuity is honest".
    let continuityNote: String?

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

    /// Forwarded from `ChatSheet`: MAX-194's door, tapped. Pushing a training thread is
    /// a reassignment of `ChatSheet`'s own `opening`, which only the sheet's owner can
    /// do — this view only ever hands up the `PlanConversationDoor.Offer` it rendered,
    /// exactly as `onAcceptProposal` hands up a `PlanProposal` rather than acting on it
    /// itself.
    let onOpenPlanConversation: (PlanConversationDoor.Offer) -> Void

    /// Forwarded from `ChatSheet`, whose `\.dismiss` this view does not have — it was
    /// not presented, `ChatSheet` was.
    let onDone: () -> Void

    /// Owned here rather than by the presenting view so that dismissing the screen and
    /// releasing the keyboard are the same action — see the Done button below.
    @FocusState private var isComposerFocused: Bool

    /// Whether arriving content is allowed to move the viewport (MAX-153).
    ///
    /// State rather than a computed property because it is a small machine with a memory:
    /// "the reader left the bottom" and "something arrived while they were gone" are facts
    /// about a sequence of events, not about the current frame. The machine itself is
    /// `ChatTranscriptFollow` in `MaximizeCore`, where its three rules are unit tested;
    /// this view feeds it events and carries out the directive it returns.
    @State private var follow = ChatTranscriptFollow()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The transcript's trailing anchor. Scrolling to a fixed empty view is stable in a
    /// way scrolling to "the last message" is not: the last message's identity changes
    /// as a reply streams, and its own height changes underneath the scroll.
    private static let transcriptBottomAnchor = "transcript-bottom"

    /// §2.2: the Ask button and the scope-mismatch banner's own action, both of which
    /// already know the subject and want *the* thread for it. **New chat** is
    /// `init(startingNewThreadFor:...)` below, not this one (MAX-185).
    ///
    /// `continuityNote` defaults to nil — the ordinary case for this initializer. Only
    /// MAX-194's door passes one, when `ChatSheet` reassigns `opening` to the training
    /// thread it resolved.
    init(
        subject: ChatSubject,
        currentInterval: TrendInterval?,
        continuityNote: String? = nil,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onOpenPlanConversation: @escaping (PlanConversationDoor.Offer) -> Void,
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
            continuityNote: continuityNote,
            onOpenThreadList: onOpenThreadList,
            onStartNewChatForCurrentWindow: onStartNewChatForCurrentWindow,
            onAcceptProposal: onAcceptProposal,
            onSelectRun: onSelectRun,
            onOpenPlanConversation: onOpenPlanConversation,
            onDone: onDone
        )
    }

    /// **New chat** (MAX-185): a fresh thread on this subject, distinct from any
    /// already open. See `ChatModel.init(startingNewThreadFor:...)` for why this is a
    /// separate initializer rather than a flag on `init(subject:...)`.
    init(
        startingNewThreadFor subject: ChatSubject,
        currentInterval: TrendInterval?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onOpenPlanConversation: @escaping (PlanConversationDoor.Offer) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            model: ChatModel(
                startingNewThreadFor: subject,
                workoutRepository: PersistenceComposition.store,
                scoreRepository: PersistenceComposition.store,
                planRepository: PersistenceComposition.store,
                settingsRepository: PersistenceComposition.store,
                chatThreadRepository: PersistenceComposition.store,
                chatClient: AnthropicStreamingChatClient(keyStore: KeychainAnthropicAPIKeyStore()),
                planProposalClient: AnthropicPlanProposalClient(keyStore: KeychainAnthropicAPIKeyStore())
            ),
            currentInterval: currentInterval,
            continuityNote: nil,
            onOpenThreadList: onOpenThreadList,
            onStartNewChatForCurrentWindow: onStartNewChatForCurrentWindow,
            onAcceptProposal: onAcceptProposal,
            onSelectRun: onSelectRun,
            onOpenPlanConversation: onOpenPlanConversation,
            onDone: onDone
        )
    }

    /// §2.3: a row tapped in the thread list. See this type's own "Three initializers"
    /// note for why the subject is never a parameter here.
    init(
        threadID: UUID,
        currentInterval: TrendInterval?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onOpenPlanConversation: @escaping (PlanConversationDoor.Offer) -> Void,
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
            continuityNote: nil,
            onOpenThreadList: onOpenThreadList,
            onStartNewChatForCurrentWindow: onStartNewChatForCurrentWindow,
            onAcceptProposal: onAcceptProposal,
            onSelectRun: onSelectRun,
            onOpenPlanConversation: onOpenPlanConversation,
            onDone: onDone
        )
    }

    private init(
        model: ChatModel,
        currentInterval: TrendInterval?,
        continuityNote: String?,
        onOpenThreadList: @escaping () -> Void,
        onStartNewChatForCurrentWindow: @escaping () -> Void,
        onAcceptProposal: @escaping (PlanProposal) -> Void,
        onSelectRun: @escaping (UUID) -> Void,
        onOpenPlanConversation: @escaping (PlanConversationDoor.Offer) -> Void,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.currentInterval = currentInterval
        self.continuityNote = continuityNote
        self.onOpenThreadList = onOpenThreadList
        self.onStartNewChatForCurrentWindow = onStartNewChatForCurrentWindow
        self.onAcceptProposal = onAcceptProposal
        self.onSelectRun = onSelectRun
        self.onOpenPlanConversation = onOpenPlanConversation
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
            // MAX-187: `.task` above does not re-run when this screen is merely
            // *revealed* again — popping `PlanAuthoringView` off the stack after a save
            // uncovers this view rather than recreating it, so the load above never
            // fires a second time (nor should it: a reload would start the conversation
            // over). `.onAppear` does fire on that reveal, and
            // `endProposalIfAlreadyStored()` is a no-op unless a proposal is actually on
            // screen and the plan it describes has actually been stored since.
            .onAppear {
                Task { await model.endProposalIfAlreadyStored() }
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
            // would be a promise here: no band in the plan's rubric describes a ride, a
            // hike or a walk, so this workout will never have the score chat is seeded
            // from. Said once, plainly, in the same voice the verdict header uses on the
            // screen behind this sheet. (A lift left this branch in MAX-168.)
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
                // MAX-194: shown once, above everything else that can appear here — it
                // is a fact about how this conversation started, not something either
                // party said, the same reasoning `scopeMismatchBanner` gives its own
                // placement. Order relative to that banner does not matter in practice:
                // this thread was just resolved by `PlanConversationDoor.offer`'s own
                // scope, so a mismatch against `currentInterval` is no more or less
                // likely here than on any other freshly opened training thread.
                if let continuityNote {
                    continuityBanner(continuityNote)
                }
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

    /// MAX-194: the one line of continuity `PlanConversationDoor` composed. A caption,
    /// not a button — unlike `scopeMismatchBanner` above, there is nothing to do about
    /// this fact, only something to know, so it carries no action and no tap target.
    /// Screen only: this string never reaches `ChatInstruction` or the stored thread —
    /// see `PlanConversationDoor`'s own "How much continuity is honest".
    private func continuityBanner(_ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
            Image(systemName: "arrow.turn.down.right")
                .font(.microLabel)
            Text(note)
                .font(.microLabel)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenMargins()
        .padding(.vertical, Spacing.snug)
        .contentSurface(.inset)
        .padding(.horizontal, LayoutMetrics.screenMargin)
        .padding(.top, Spacing.snug)
        .accessibilityElement(children: .combine)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    if model.messages.isEmpty && !model.isStreaming {
                        secondaryText(ChatConversationCopy.emptyTranscriptInvitation(for: model.subject?.kind))
                    }

                    ForEach(model.messages) { message in
                        // §6.8, MAX-201: which turns start a new calendar day, and what
                        // that day is called, is `ChatTranscriptDaySeparators`' decision
                        // (`MaximizeCore`) — this reads the answer for this row's id and
                        // draws it, nothing more. Nil for a row `MaximizeCore` has no
                        // stored timestamp for (a notice, or a reply still arriving);
                        // see that type's own note on why that is the correct answer,
                        // not a gap.
                        if let day = daySeparatorLabels[message.id] {
                            ChatDaySeparatorView(label: day)
                        }
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

                    // The scroll target, and — since MAX-153 — the sentinel that answers
                    // "is the reader at the newest turn?". `onScrollVisibilityChange` is
                    // the iOS 18 way to ask that, and it beats arithmetic on
                    // `ScrollGeometry`: the composer is a `safeAreaInset`, so any
                    // hand-rolled offset comparison would have to know how far the
                    // content is inset, and this asks the scroll view instead.
                    //
                    // Four points rather than a hairline for the same reason: a half-point
                    // view's visible *fraction* is a sub-pixel question, and this signal
                    // should not turn on rounding. It sits inside the stack's existing
                    // bottom padding, so nothing moves.
                    Color.clear
                        .frame(height: Spacing.tight)
                        .id(Self.transcriptBottomAnchor)
                        .onScrollVisibilityChange(threshold: 0.01) { isAtLatest in
                            if isAtLatest {
                                follow.readerReachedLatest()
                            } else {
                                follow.readerScrolledAway()
                            }
                        }
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
            // Open at the newest turn (MAX-153). A thread with history used to lay out at
            // its top and be dragged to the bottom by the first `onChange` that fired
            // after `load()` — which worked only because nothing could suppress that
            // scroll. Something can now: the sentinel below reports "not at the latest"
            // as soon as it lays out off screen, and if that lands first the athlete opens
            // a conversation at its beginning with a "Jump to latest" pill over it.
            //
            // `for: .initialOffset` deliberately, not the whole-hog overload: this fixes
            // where the scroll view *starts* and says nothing about what it does when the
            // content grows, because that question is `ChatTranscriptFollow`'s and a
            // platform anchor quietly answering it too is two mechanisms for one
            // behaviour.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // MAX-153: every one of these used to scroll to the bottom unconditionally.
            // `ChatTranscriptFollow` (`MaximizeCore`) is what decides now, and it is the
            // decision, not the scrolling, that is worth having under test — see that
            // type's three rules. This view classifies the change and applies the answer.
            .onChange(of: model.messages.count) {
                apply(follow.transcriptChanged(latestMessageChange), proxy)
            }
            // The phase rather than a streaming flag (MAX-152): the placeholder giving
            // way to the first tokens, and a stall growing a caption underneath the
            // partial reply, both change the transcript's height without changing the
            // message count. Classified as `.reflow` — it moves content, but nothing was
            // said, so it must not tell a reader who scrolled up that a reply arrived.
            .onChange(of: model.replyPhase) {
                apply(follow.transcriptChanged(.reflow), proxy)
            }
            // Tokens, on the other hand, *are* the reply arriving.
            .onChange(of: model.streamingText) {
                apply(follow.transcriptChanged(.incoming), proxy)
            }
            .onChange(of: model.planDrafting) {
                apply(follow.transcriptChanged(.reflow), proxy)
            }
            // The deliberate departure (MAX-153): this used to scroll to the bottom on
            // focus unconditionally. A reader who scrolled up to look at a split, then
            // tapped the field to ask about *that split*, was taken away from it. A reader
            // already at the bottom still stays there when the keyboard rises, which is
            // the case the old behaviour was written for.
            .onChange(of: isComposerFocused) {
                apply(follow.composerFocusChanged(isFocused: isComposerFocused), proxy)
            }
            .overlay(alignment: .bottom) {
                if follow.showsJumpToLatest {
                    ChatJumpToLatestButton(follow: follow) {
                        apply(follow.jumpToLatestRequested(), proxy)
                    }
                    .padding(.bottom, Spacing.snug)
                    .transition(.opacity)
                }
            }
            .accessibleAnimation(Motion.stateChange, value: follow.showsJumpToLatest)
        }
    }

    /// §6.8, MAX-201: message id → the day separator that precedes it, read fresh at
    /// render time from `model.thread?.visibleMessages` — the thread's own stored
    /// turns, each with a real timestamp — rather than from `model.messages`, which can
    /// hold a row (a notice, an in-flight reply) `MaximizeCore` has no stored timestamp
    /// for. See `ChatTranscriptDaySeparators`' own note on why that is the intended
    /// degradation and not a gap: such a row cannot itself need a separator relative to
    /// the turn immediately before it, which is at most seconds old in the same session.
    private var daySeparatorLabels: [UUID: String] {
        ChatTranscriptDaySeparators.labels(
            for: model.thread?.visibleMessages ?? [],
            now: Date(),
            timeZone: .current
        )
    }

    /// Whether the newest row is something the athlete just wrote.
    ///
    /// The one classification this view makes, and it is a read rather than a judgement:
    /// `send()` appends the user's turn locally the instant it runs, so a message count
    /// that grew with a `.user` row last is the athlete's own send. Everything else —
    /// a completed reply, a notice — arrived without them asking for it now.
    private var latestMessageChange: ChatTranscriptChange {
        model.messages.last?.kind == .user ? .ownMessage : .incoming
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
    ///
    /// The "is this a training thread" test used to be here and is now in `composer`
    /// (MAX-153), because that is where it has consequences: a workout thread takes
    /// `ChatComposerView`'s `EmptyView` overload and gets no accessory row at all, rather
    /// than an accessory that renders nothing but still occupies a `VStack` slot.
    private var draftPlanButton: some View {
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

    private func draftPlan() {
        guard model.canDraftPlan else { return }
        Task { await model.draftPlan() }
    }

    /// The bottom bar (MAX-153).
    ///
    /// The hand-rolled row this used to be — a `TextField` in a `.contentSurface(.inset)`
    /// well, a bare `Image` for a send button, and one `.glassChrome(.toolbar)` wrapped
    /// round both — is now `ChatComposerView`, which carries its own
    /// `GlassEffectContainer` and takes its capsules from `.floatingControl`. **There is
    /// deliberately no glass modifier left here**: a second one round a view that already
    /// glasses itself is chrome over chrome, which is exactly what `CLAUDE.md`'s "let the
    /// platform supply its chrome" rules out, and it would also put the container's
    /// merge-and-morph behaviour inside an opaque rectangle where it cannot be seen.
    ///
    /// **The control reads MAX-152's reply ladder, not a boolean.** `replyPhase` is the
    /// one authority on "is a reply in flight" now that `isStreaming` is derived from it;
    /// `ChatComposerSendControl.resolve(canSend:replyPhase:)` is where those two facts
    /// become one of four controls, in the core, under test. `cancellation` is left at its
    /// default — `ChatModel` cannot stop a stream, so the honest control mid-reply is a
    /// progress indicator, not a stop button that does nothing.
    ///
    /// **Retry is not here.** MAX-152 put "Try again" in the transcript, beside the
    /// failure notice that explains what went wrong, which is the right place for it: two
    /// retry affordances, or one in each of two registers, is worse than either alone.
    ///
    /// §4.7's drafting action, and MAX-194's door, both ride above the input row as the
    /// composer's `accessory`, so each is one piece of chrome rather than a second
    /// floating bar over the transcript — both are things you do *to* this
    /// conversation, one training-only and one workout-only, and the two can never
    /// appear together because a thread has exactly one subject. The subject branch
    /// lives here rather than inside either button, so "which subject offers what" is
    /// decided once: any thread that offers neither gets the `EmptyView` overload and
    /// no empty row.
    @ViewBuilder
    private var composer: some View {
        if model.subject?.kind == .training {
            ChatComposerView(
                text: $model.composerText,
                placeholder: ChatConversationCopy.composerPlaceholder(for: model.subject?.kind),
                sendControl: .resolve(canSend: model.canSend, replyPhase: model.replyPhase),
                isFocused: $isComposerFocused,
                onActivate: send,
                accessory: { draftPlanButton }
            )
        } else if let doorOffer = model.planConversationDoor {
            ChatComposerView(
                text: $model.composerText,
                placeholder: ChatConversationCopy.composerPlaceholder(for: model.subject?.kind),
                sendControl: .resolve(canSend: model.canSend, replyPhase: model.replyPhase),
                isFocused: $isComposerFocused,
                onActivate: send,
                accessory: { planConversationDoorButton(doorOffer) }
            )
        } else {
            ChatComposerView(
                text: $model.composerText,
                placeholder: ChatConversationCopy.composerPlaceholder(for: model.subject?.kind),
                sendControl: .resolve(canSend: model.canSend, replyPhase: model.replyPhase),
                isFocused: $isComposerFocused,
                onActivate: send
            )
        }
    }

    // MARK: - MAX-194: the door to the plan's conversation

    /// The composer accessory offered on a workout thread — the mirror of
    /// `draftPlanButton` on a training one. `offer` is `PlanConversationDoor`'s decision
    /// (`MaximizeCore`, under test); this only lays out the label and hint it already
    /// chose. Tapping hands the offer up to `ChatSheet`, which is the only thing that
    /// can reassign what this sheet has open (`onOpenPlanConversation`'s own doc
    /// comment).
    private func planConversationDoorButton(_ offer: PlanConversationDoor.Offer) -> some View {
        Button {
            onOpenPlanConversation(offer)
        } label: {
            Label(offer.buttonLabel, systemImage: ChatSubjectKind.training.glyphSystemImageName)
                .font(.metricLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.accent)
        .accessibilityHint(offer.accessibilityHint)
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

    /// Carries out whatever `ChatTranscriptFollow` decided. `.stay` is the common answer
    /// while somebody is reading, and it is a no-op on purpose — the whole point of the
    /// type is that not scrolling is a first-class outcome rather than a missing call.
    ///
    /// `Motion.scrollSettle` rather than a duration written here (MAX-152): the ramp names
    /// the job, and a second call site that wanted "about the same speed" is how a design
    /// system ends up with three of them.
    private func apply(_ directive: ChatTranscriptScrollDirective, _ proxy: ScrollViewProxy) {
        guard directive == .scrollToLatest else { return }
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

/// §6.8, MAX-201: a day separator between turns — the label `ChatTranscriptDaySeparators`
/// decided, drawn centered and quiet. Never a bubble and never `.notice`'s styling: a
/// separator states a fact about the transcript itself, not something either party said,
/// and CLAUDE.md's "a separator must not read as a message" is the reason it takes the
/// smallest type in the file rather than borrowing the notice row's.
private struct ChatDaySeparatorView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.microLabel)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)
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
