import Foundation
import Observation

/// The chat surface's whole state machine, for **either** subject a thread can have
/// (FR-2.1–2.4, D10, MAX-051, A11): what the thread looks like, what has streamed in so
/// far, and what actually gets persisted.
///
/// ## Why this is the view model, not a helper the view model calls
///
/// CLAUDE.md's "thin shell, fat core" usually puts *decisions* in `MaximizeCore` and
/// leaves state-holding to an `@Observable` class in `App/` (`WorkoutDetailModel`,
/// `TrendTilesModel`, `SettingsModel`). Chat cannot be split that way, because nearly
/// everything about it is a decision the ticket names directly: when a turn is
/// complete, what is shown versus what is stored, and how a stored `ChatThread` maps
/// onto `ChatInstruction.turns`. A thin App-layer wrapper around a "streaming helper"
/// in the core would just relocate those decisions into the one place CI cannot see —
/// exactly the mistake CLAUDE.md warns against. So this type *is* the view model:
/// `@Observable`, driven end-to-end by `load()`/`send()`, and read directly by a
/// SwiftUI view exactly the way `WorkoutDetailModel` is (`Sources/MaximizeCore` may not
/// import `SwiftUI`, `UIKit` or `SwiftData` — CI greps for it — but `Observation` is
/// none of those; it is the same cross-platform standard-library module this file
/// needs to be observable at all).
///
/// `ChatModelTests` drives this against `InMemoryWorkoutStore`,
/// `FakeChatThreadRepository` and `FakeStreamingChatModelInvoking` — no SwiftData, no
/// simulator, no device (CLAUDE.md, "What CI can and cannot prove").
///
/// ## Subject-driven, not workout-driven (MAX-096, A11)
///
/// Until this ticket the model was `WorkoutChatModel` and took a workout id, because a
/// thread *was* its workout. A11 breaks that, so this takes a `ChatSubject` and asks
/// `ContextBuilder` for whichever `PromptContext` that subject calls for. Everything
/// downstream — the thread lookup, the streaming, what is persisted — is written once
/// and does not branch on the subject at all; the two places that do are `load()`, which
/// gathers different stored records for each, and `task`, which is different prompt text
/// for a different question (§3.5).
///
/// **The workout path is deliberately unchanged in behaviour.** Its guards run in the
/// same order and produce the same states as before, and `ContextBuilder` delegates to
/// `WorkoutContextBuilder` byte for byte, so the fact sheet a workout thread sends is
/// the same string it sent yesterday.
///
/// ## Three ways in: resolve a subject, mint one fresh, or open an exact thread
/// (MAX-097, MAX-185)
///
/// `init(subject:...)` is "open *the* thread for this subject" — the Ask button, and
/// the scope-mismatch banner's own action (`ChatScopeNotice`) — and `load()` resolves
/// it (`ChatThreadRepository.thread(for:...)`, newest activity wins, minting only when
/// nothing exists yet). `init(startingNewThreadFor:...)` is **New chat** (MAX-185): it
/// shares `init(subject:...)`'s subject but never resolves to what is already
/// there — `load()` mints a fresh, empty thread every time, because
/// `ChatThreadRepository`'s own contract deliberately allows several threads per
/// training subject and a button named "New chat" that silently reopens the one
/// already on screen is the defect this exists to fix. `init(threadID:...)` is "open
/// exactly this thread" — the thread list (§2.3) knows a specific conversation, not a
/// subject, and the subject is read off the stored thread once `load()` fetches it by
/// id, never supplied by the caller. The distinction between resolving and minting
/// matters because subjects are not unique: two training threads can legitimately
/// share an identical frozen window, so resolving "the" thread for a subject after a
/// specific row was tapped — or after **New chat** was — could silently open a
/// different one than the athlete meant. `Opening` (below) is the closed, private
/// choice between the three — `load()` is exhaustive over it the same way it is
/// exhaustive over `ChatSubject`.
///
/// All three paths converge before `.ready`: however the thread was found or minted,
/// `subject` ends up holding the same value, and every subject-driven read
/// `load()`/`send()` do afterward is subject-driven once more.
///
/// ## D3 — the fact sheet is never re-assembled
///
/// `load()` builds exactly one `PromptContext` (`ContextBuilder.build(for:from:)`, the
/// only assembler in the app — A12) and keeps it. Every `ChatInstruction` sent afterward
/// reads `context.factSheet()` again — a pure, deterministic render of that same
/// context — rather than reconstructing prompt text from the stored thread. Nothing here
/// composes, trims or summarises it.
///
/// ## Chat writes nothing (§2.5)
///
/// Every repository below is read from except one. `ChatThreadRepository.store(_:)` is
/// the only write this type performs, and it appends a completed turn to this thread and
/// nothing else. No annotation, no rest-day conversion, no plan version, no setting —
/// §9 makes that an invariant rather than a scoping choice, because chat proposes and
/// the athlete taps.
///
/// **`draftPlan()` does not weaken that** (MAX-101, A13). It reads `planRepository` to
/// find out which version a proposal would supersede, and stops there: the outcome is a
/// `PlanProposalReview` held in memory. There is no call to `PlanRepository.store(_:)`
/// anywhere in this file, no `Plan` is constructed here, and the only way the proposal
/// becomes a stored version is the athlete tapping through to `PlanAuthoringView` and
/// saving it — `PlanAuthoringSession.plan(from:effectiveFrom:)` is still the single
/// door. `ChatPlanDraftingTests` asserts the negative directly rather than trusting this
/// paragraph.
///
/// ## Why a workout thread requires an existing score
///
/// FR-2.1 seeds the thread with "the score already assigned," and `WorkoutContext`
/// needs a `WorkoutClassification` to render at all. That classification is a stored
/// decision (`Score.actualClassification`), made once by the scorer during ingestion —
/// D2's "computed once, stored" applies to it exactly as it does to a metric.
/// Re-deriving it here from `WorkoutClassifier` would be a second place that decision
/// gets made, which is the drift D2/D3 exist to prevent. So a workout with no
/// `ScoreLedger` yet has no chat yet either: `.notYetScored` is an ordinary, honest
/// state — not a failure — mirroring how `WorkoutDetailModel` already treats
/// "unscored" and how `ChatStreamError.noAPIKeyStored` is treated below. In the common
/// case this is a short wait: `WorkoutDetailView` already calls
/// `IngestionComposition.completeIngestion(forWorkout:)` (R8's lazy path) before this
/// screen's chat entry point ever renders.
///
/// **For a workout no rubric describes it is not a wait at all** (MAX-126). A ride, a
/// hike and a walk are never scored, so the lazy path above re-reaches the same
/// conclusion every time and no ledger ever appears. `.noVerdict` is that case, split out
/// from `.notYetScored` for the same reason `WorkoutVerdict.Scoring` splits it: the two
/// states are identical in what they lack and opposite in what happens next, and only one
/// of them can honestly tell the athlete to come back later. **A lift is on the waiting
/// side as of MAX-168** — its score arrives once the athlete has said what it worked (A22)
/// and a plan version prescribes and can judge a lift day.
///
/// A training thread has neither state: it describes a window, and a window with no
/// scored runs in it is still a window the roll-up can describe truthfully.
///
/// ## Only completed turns are persisted
///
/// A user question and its assistant reply are written to the thread as one pair, and
/// only once the stream ends with `.completed` (MAX-024, MAX-050: "a partially-received
/// assistant turn is transport state; only the completed turn is appended"). A
/// `.failed` stream never calls `ChatThreadRepository.store(_:)` — the question the
/// athlete typed is kept on screen (so it is not lost mid-retry) but is not written to
/// disk, and neither is whatever partial reply arrived. `.completed(.truncated)` still
/// persists: `ChatTurnCompletion`'s own documentation says a reply cut off by the token
/// cap is "four usable paragraphs," and that this view is what should say it was cut
/// short — `DisplayMessage.wasTruncated` is that flag.
///
/// ## Partial text survives a failure, on screen
///
/// `streamingText` accumulates every `.text` event as it arrives; if the stream ends in
/// `.failed`, whatever had accumulated becomes a `DisplayMessage` with
/// `wasInterruptedByFailure` set, appended right alongside a notice describing what
/// happened. Nothing here ever clears a bubble because the connection dropped.
///
/// ## MAX-152 — the surface knows which waiting it is doing
///
/// `replyPhase` is the whole ladder between "sent" and "answered": waiting with nothing
/// back, streaming, stalled with the connection open, and the four ways a turn stops.
/// The decision of which rung is showing is made here, by `ChatReplyProgress`, from
/// stream events only — a view renders the rung it is handed and inspects no timings and
/// no stream internals, which is the whole of CLAUDE.md's thin-shell rule applied to a
/// loading state. Every failure's words come from `ChatFailureNotice`, the one place a
/// `ChatStreamError` becomes a sentence, and `retry()` is the only path back to the
/// model after one — one call per tap, never automatic.
///
/// ## A14 — nothing here calls the model unattended
///
/// `send()` and `retry()` are the only paths to `StreamingChatModelInvoking`, and
/// `draftPlan()` the only path to `PlanProposalModelInvoking`; all three are reached only
/// from a view forwarding a tap. `load()` reads storage and returns; it never streams and
/// never drafts. There is no timer, no on-appear call, and no background wake anywhere in
/// this file; nothing pre-drafts a proposal in case one is wanted, and **no failure ever
/// re-asks itself** — MAX-152's retry is a button, and `ChatFailureNotice` carries the
/// argument for why it is not a policy.
@MainActor
@Observable
public final class ChatModel {

    public enum LoadState: Equatable, Sendable {
        case loading
        /// A repository was unavailable, the subject's records could not be read, or a
        /// context could not be assembled from them. Mirrors every sibling screen's
        /// `.failed` (`WorkoutDetailModel`, `TrendTilesModel`, `SettingsModel`).
        case failed
        /// See this type's "Why a workout thread requires an existing score." Ordinary,
        /// not an error — a run's state between capture and scoring. **Workout subjects
        /// only.**
        case notYetScored
        /// The workout is not a run, so no score will ever be stored for it and chat
        /// cannot open (MAX-126). Distinct from `.notYetScored` because a view must not
        /// tell the athlete to wait for something that is not coming. **Workout subjects
        /// only.**
        case noVerdict
        /// Opened by a specific thread id (`init(threadID:...)`, §2.3's thread list)
        /// that no longer resolves to a stored thread. The state a delete on another
        /// screen leaves behind, not a failure — nothing is broken, the conversation
        /// this id named is simply gone. **Only reachable when opened by thread id.**
        case threadNotFound
        case ready
    }

    /// One row the view draws: a real turn, or an app-generated notice that is
    /// deliberately never written to the thread (a stream failure, "no key stored").
    public struct DisplayMessage: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case user
            case assistant
            /// Not from Claude, not typed by the athlete, and never persisted — "add a
            /// key in Settings," "the connection dropped." Kept out of `ChatRole`
            /// entirely so the view cannot mistake one for a real turn.
            case notice
        }

        public let id: UUID
        public let kind: Kind
        public let text: String
        /// `.completed(.truncated)` on a persisted assistant reply (see this type's
        /// "Only completed turns are persisted").
        public let wasTruncated: Bool
        /// An assistant reply that stopped because the stream `.failed`, not because it
        /// finished — always paired with a `.notice` describing why, and never true for
        /// anything actually written to the thread.
        public let wasInterruptedByFailure: Bool

        init(
            id: UUID = UUID(),
            kind: Kind,
            text: String,
            wasTruncated: Bool = false,
            wasInterruptedByFailure: Bool = false
        ) {
            self.id = id
            self.kind = kind
            self.text = text
            self.wasTruncated = wasTruncated
            self.wasInterruptedByFailure = wasInterruptedByFailure
        }
    }

    /// Where the "draft a plan from this conversation" action stands (§4, MAX-101).
    ///
    /// A separate axis from `messages` on purpose: a proposal is **not a turn**. It is
    /// not something either party said, it is never written to the thread, and it does
    /// not survive the sheet closing. Modelling it as a `DisplayMessage` would have put a
    /// value the athlete has not accepted into the same list as the ones already on disk.
    public enum PlanDraftingState: Hashable, Sendable {
        /// No proposal is being asked for and none is waiting to be reviewed.
        case idle
        /// One call is in flight, possibly the one retry §4.5 permits.
        case drafting
        /// A proposal came back and is on screen awaiting the athlete's decision.
        /// **Nothing has been stored** — see this type's note on §2.5.
        case proposed(PlanProposalReview)
    }

    public private(set) var loadState: LoadState = .loading

    /// Every row the view draws, oldest first — persisted turns and app-generated
    /// notices interleaved in the order they actually happened.
    public private(set) var messages: [DisplayMessage] = []

    /// Where the reply in flight stands, or how the last one ended (MAX-152).
    ///
    /// The whole ladder — waiting, streaming, stalled, and the four ways a turn stops —
    /// decided here and rendered without re-decision by the view. See `ChatReplyPhase`
    /// for why it is an enum in the core rather than a bit and a timer in a view.
    public var replyPhase: ChatReplyPhase { progress.phase }

    /// True from the moment a request opens until its terminal event, always — the
    /// `ChatStreamEvent` contract guarantees exactly one terminal event, so this can
    /// never get stuck true (FR-2.4's reveal is real progress, not a spinner that never
    /// resolves).
    ///
    /// Computed from `replyPhase` rather than stored alongside it (MAX-152). Two flags
    /// describing one request are two flags that can disagree, and this one is read by
    /// `canSend`: a phase that said "finished" while this said "still going" would leave
    /// the composer disabled with nothing in flight.
    public var isStreaming: Bool { replyPhase.isLive }

    /// The reply as it arrives, token by token. Cleared the moment the stream ends,
    /// whichever way — by then its contents have become a `DisplayMessage`.
    public private(set) var streamingText = ""

    /// Bound directly to the composer's text field.
    public var composerText = ""

    public var canSend: Bool {
        loadState == .ready && !isStreaming
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The ladder itself. Private because the only legal way to move it is through the
    /// stream this type is consuming — a caller that could `apply(.textArrived)` could
    /// make the surface claim a reply is arriving when none is.
    private var progress = ChatReplyProgress()

    /// The question whose answer has not landed, kept in memory so `retry()` can ask it
    /// again without the athlete retyping it (MAX-152).
    ///
    /// **Not persistence, and not a queue.** It holds exactly one turn — the last one
    /// sent — is cleared the moment a reply is stored, and never reaches disk: a question
    /// whose reply failed is deliberately not written to the thread (see "Only completed
    /// turns are persisted"), and this does not smuggle it there. It exists because the
    /// alternative for a dropped connection is retyping a question that is still visible
    /// on screen.
    private var pendingTurn: PendingTurn?

    /// One question, and the exact request that was built from it.
    ///
    /// The instruction is kept rather than rebuilt, so a retry asks the identical
    /// question with the identical history: the failed turn was never persisted, so the
    /// thread has not moved underneath it, and rebuilding would be a second assembly of
    /// something D3 says is assembled once.
    private struct PendingTurn {
        let message: ChatMessage
        let instruction: ChatInstruction
    }

    /// Whether "Try again" is offered (MAX-152).
    ///
    /// Four conditions, all of them necessary: the surface is loaded, nothing is in
    /// flight, there is a question to ask again, and the failure is one where asking
    /// again could plausibly help (`ChatReplyPhase.offersRetry`, which reads
    /// `ChatStreamError.isWorthRetrying`). A missing key, a rejected key, a refusal and
    /// an unreadable response all fail that last test, and offering a button that
    /// re-runs a call guaranteed to fail identically would spend the owner's credit to
    /// tell the athlete the same thing twice.
    public var canRetry: Bool {
        loadState == .ready && !isStreaming && pendingTurn != nil && replyPhase.offersRetry
    }

    /// §4, MAX-101. Nothing here ever sets this to anything but `.idle` on its own.
    public private(set) var planDrafting: PlanDraftingState = .idle

    /// Whether "draft a plan from this conversation" is offered at all.
    ///
    /// **Training threads only.** §4.2 puts plan authoring in "an ordinary streaming
    /// training thread", and a workout thread has nothing a plan can be drafted from: its
    /// context is one run, and a plan written from one run would be a plan written from
    /// almost nothing. Keeping the action off that surface is also what makes MAX-096's
    /// regression promise hold — a workout thread behaves exactly as it did.
    ///
    /// It also requires something to have been said, and specifically something the
    /// *thread* holds rather than something merely on screen: a question whose reply
    /// never arrived is kept in `messages` but was deliberately not persisted (see "only
    /// completed turns are persisted"), and it is `thread.visibleMessages` that
    /// `draftPlan()` actually replays. Reading the same list the call will send is what
    /// keeps an enabled button from producing "there is nothing to draft from".
    public var canDraftPlan: Bool {
        guard planProposalClient != nil, subject?.kind == .training else { return false }
        guard loadState == .ready, !isStreaming else { return false }
        if case .drafting = planDrafting { return false }
        return thread?.visibleMessages.contains(where: { $0.role == .user }) ?? false
    }

    /// How this model was asked to open (MAX-097, MAX-185, §2.2 vs §2.3).
    ///
    /// Three entry points, one loader. A caller either already knows the subject and
    /// wants *the* thread for it — the Ask button and the scope-mismatch banner — or
    /// already knows the subject and wants a *fresh* thread regardless of what already
    /// exists for it — **New chat** (MAX-185) — or already knows which thread — the
    /// thread list does, because the athlete tapped a specific row. None of the three
    /// are conflatable: a caller that could supply both a thread id and a subject could
    /// hand this type a context for the wrong window, which is §3.6's disagreement in
    /// its most direct form, and a caller that could ask to both resolve and mint would
    /// leave `load()` guessing which the athlete meant. So opening by id never takes a
    /// subject from the caller at all — see `subject`'s own documentation for where it
    /// comes from instead — and resolving versus minting is a different `Opening` case,
    /// not a flag on one.
    private enum Opening {
        case subject(ChatSubject)
        /// MAX-185: **New chat**. `load()` never asks `ChatThreadRepository` to resolve
        /// an existing thread for this case — it mints one, unconditionally, every
        /// time. See this type's "Three ways in" for why that has to be a distinct case
        /// rather than a parameter on `.subject`.
        case newThread(ChatSubject)
        case threadID(UUID)
    }

    private let opening: Opening

    /// What this conversation is about, and therefore which pile of stored data `load()`
    /// gathers and which `task` `send()` uses.
    ///
    /// Known immediately when constructed with a subject (`init(subject:...)`) — the
    /// caller already knows it, because the subject is what it asked for. `nil` until
    /// `load()` resolves it when constructed with a thread id instead
    /// (`init(threadID:...)`, §2.3): the thread list knows a specific conversation, not
    /// what it is about, and reading the subject off the *stored thread* rather than a
    /// caller-supplied one is what keeps this type from ever building a context for the
    /// wrong window. Immutable once resolved: re-subjecting a live model would leave a
    /// transcript answered from something it no longer describes.
    public private(set) var subject: ChatSubject?

    /// The sheet's title (§2.2, §2.4) — this thread's derived title, calling
    /// `ChatThreadTitle.derive(for:workoutFacts:)`, the one place titling is decided
    /// (MAX-092). "Chat" is a neutral placeholder for every state before `thread` is
    /// set — loading, `.failed`, `.notYetScored`, `.noVerdict`, `.threadNotFound` —
    /// matching what this screen's navigation title always read before this ticket
    /// generalised it.
    public var title: String {
        guard let thread else { return "Chat" }
        return ChatThreadTitle.derive(for: thread, workoutFacts: workoutFacts)
    }

    /// The sheet's subtitle (§2.2, §3.6(b)) — this thread's scope, stated. Known the
    /// instant `subject` is, so for a subject-opened model it does not wait on `load()`
    /// at all; for a thread-id-opened model it is empty until the lookup resolves one.
    public var subtitle: String {
        guard let subject else { return "" }
        return ChatThreadSubtitle.text(for: subject)
    }

    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?
    private let chatThreadRepository: (any ChatThreadRepository)?
    private let chatClient: any StreamingChatModelInvoking
    /// MAX-100's transport, for §4.7's separate one-shot call. Optional in the way the
    /// repositories are and `chatClient` is not: a caller with no plan-drafting transport
    /// (a workout-only preview, a test about streaming) is a real situation, and the
    /// honest response is to not offer the action rather than to offer one that fails.
    private let planProposalClient: (any PlanProposalModelInvoking)?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    /// Built once by `load()`, from stored data only, and read again — never rebuilt —
    /// by every `send()` afterward (see this type's "D3" note).
    private var context: PromptContext?

    /// The resolved thread, once `load()` has reached `.ready`. Exposed read-only
    /// (MAX-097) — `title` above is what actually reads it; it is public in its own
    /// right because a future consumer of "which thread is this, exactly" (MAX-103's
    /// runs strip is the likely one) should not have to re-derive that from `subject`.
    public private(set) var thread: ChatThread?

    /// The run's date and activity type, resolved by `workoutContext()` for a workout
    /// subject only (MAX-097). `nil` for a training subject, and `nil` for a workout
    /// subject until `load()` has fetched the workout — `title` below already accounts
    /// for both by falling back until `thread` itself is set.
    public private(set) var workoutFacts: WorkoutThreadFacts?

    /// §2.2, §6.2, MAX-103: the "Runs in this conversation" strip's data.
    ///
    /// Read straight off `context` — never a second fetch of stored records — so the
    /// strip can never show a session the prompt did not (`RunsStripData`'s own "built
    /// from the thread's own context"). `nil` for a workout subject (there is nothing to
    /// strip: the sheet already sits on top of that run's own screen, §6.1) and `nil`
    /// before `load()` has built a context, exactly as `title`/`subtitle` degrade before
    /// their own inputs exist.
    public var runsStripData: RunsStripData? {
        guard case let .training(trainingContext) = context else { return nil }
        return RunsStripData.build(from: trainingContext)
    }

    /// - Parameters:
    ///   - subject: what this thread is about (A11). The set is closed, which is what
    ///     lets `load()` stay exhaustive: a third subject cannot be added without the
    ///     compiler demanding the records it needs here.
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository/chatThreadRepository:
    ///     **required, with no default.** Every sibling screen defaults these to
    ///     `PersistenceComposition.store` — but that composition root lives in `App/`
    ///     and this type may not import it (`MaximizeCore` stays platform-free), so the
    ///     caller must supply it explicitly. MAX-049 was a defaulted parameter silently
    ///     resolving to a no-op stub in two files; a required parameter here cannot
    ///     repeat that mistake by omission. A caller that has nothing to pass should
    ///     pass `nil`, which `load()` turns into `.failed` — never into a store that
    ///     looks empty.
    ///   - chatClient: MAX-024's transport (`AnthropicStreamingChatClient` in `App/`,
    ///     or `FakeStreamingChatModelInvoking` in tests). Not optional: unlike the
    ///     repositories, there is no legitimate "unavailable" state for it — failure to
    ///     reach the model arrives as a `ChatStreamEvent.failed` value instead.
    ///   - planProposalClient: MAX-100's transport for §4.7's one-shot plan-drafting
    ///     call, or nil where the caller has none. Nil is a real state — a workout-only
    ///     surface, a test about streaming — and it turns `canDraftPlan` off rather than
    ///     offering an action that cannot work. Defaulted to nil, unlike the
    ///     repositories, because the mistake MAX-049 warns about is the opposite one
    ///     here: a defaulted *repository* silently looked empty, whereas a defaulted nil
    ///     transport visibly removes a button.
    ///   - timeZone: the zone the athlete's calendar days are resolved in, matching
    ///     `WorkoutDetailModel`'s and `TrendTilesModel`'s own default and reasoning.
    ///   - now: injected rather than read from the clock so a sent turn's timestamps —
    ///     and the civil day a training roll-up is measured against — are reproducible in
    ///     a test, matching `WorkoutIngestionPipeline`'s `now`.
    public init(
        subject: ChatSubject,
        workoutRepository: (any WorkoutRepository)?,
        scoreRepository: (any ScoreRepository)?,
        planRepository: (any PlanRepository)?,
        settingsRepository: (any SettingsRepository)?,
        chatThreadRepository: (any ChatThreadRepository)?,
        chatClient: any StreamingChatModelInvoking,
        planProposalClient: (any PlanProposalModelInvoking)? = nil,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.opening = .subject(subject)
        self.subject = subject
        self.workoutRepository = workoutRepository
        self.scoreRepository = scoreRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.chatThreadRepository = chatThreadRepository
        self.chatClient = chatClient
        self.planProposalClient = planProposalClient
        self.timeZone = timeZone
        self.now = now
    }

    /// Opens a genuinely new, empty thread on this subject — **New chat** (MAX-185).
    ///
    /// Unlike `init(subject:...)`, `load()` never resolves this to a thread that
    /// already exists, even when the subject is unchanged from the one already open:
    /// `ChatThreadRepository`'s own contract deliberately allows several threads per
    /// training subject ("one thread per workout is a policy this method keeps, not a
    /// shape the type forbids"), and **New chat** silently reopening the thread already
    /// on screen — because its scope had not changed — was the shipped defect this
    /// initializer exists to fix. The minted thread is unstored until a turn completes,
    /// exactly as `init(subject:...)`'s fallback thread is (`ChatThreadRepository`'s
    /// "create-or-fetch" — "reaches disk only when a completed turn is appended" — A14
    /// still holds: nothing here calls the model).
    ///
    /// - Parameters and everything else: identical in meaning to `init(subject:...)`.
    public init(
        startingNewThreadFor subject: ChatSubject,
        workoutRepository: (any WorkoutRepository)?,
        scoreRepository: (any ScoreRepository)?,
        planRepository: (any PlanRepository)?,
        settingsRepository: (any SettingsRepository)?,
        chatThreadRepository: (any ChatThreadRepository)?,
        chatClient: any StreamingChatModelInvoking,
        planProposalClient: (any PlanProposalModelInvoking)? = nil,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.opening = .newThread(subject)
        self.subject = subject
        self.workoutRepository = workoutRepository
        self.scoreRepository = scoreRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.chatThreadRepository = chatThreadRepository
        self.chatClient = chatClient
        self.planProposalClient = planProposalClient
        self.timeZone = timeZone
        self.now = now
    }

    /// Opens a specific, already-existing thread by identity rather than resolving
    /// "the" thread for a subject (§2.3: the thread list). `subject` starts `nil` and
    /// is set only once `load()` has read it off the stored thread — see `subject`'s
    /// own documentation for why a caller cannot supply one alongside a thread id.
    ///
    /// A thread id that no longer resolves to a stored thread is a real, ordinary
    /// state (`LoadState.threadNotFound`) — the shape a delete on another screen
    /// leaves behind — never a crash and never silently reinterpreted as some other
    /// thread.
    ///
    /// - Parameters and everything else: identical in meaning to `init(subject:...)`.
    public init(
        threadID: UUID,
        workoutRepository: (any WorkoutRepository)?,
        scoreRepository: (any ScoreRepository)?,
        planRepository: (any PlanRepository)?,
        settingsRepository: (any SettingsRepository)?,
        chatThreadRepository: (any ChatThreadRepository)?,
        chatClient: any StreamingChatModelInvoking,
        planProposalClient: (any PlanProposalModelInvoking)? = nil,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.opening = .threadID(threadID)
        self.subject = nil
        self.workoutRepository = workoutRepository
        self.scoreRepository = scoreRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.chatThreadRepository = chatThreadRepository
        self.chatClient = chatClient
        self.planProposalClient = planProposalClient
        self.timeZone = timeZone
        self.now = now
    }

    // MARK: - Loading

    public func load() async {
        loadState = .loading
        messages = []
        context = nil
        thread = nil
        workoutFacts = nil
        // A proposal describes the conversation it was drafted from. A reload starts
        // that conversation over, so a card left on screen would be a diff against a
        // transcript that is no longer there.
        planDrafting = .idle
        // Same reasoning one axis over (MAX-152): a phase describes a request, and a
        // reload has abandoned the request it described. Leaving `.failed` set would
        // offer a retry for a question that is no longer in the transcript.
        progress.reset()
        pendingTurn = nil
        streamingText = ""
        if case .threadID = opening {
            // A subject-opened model's `subject` never changes (set once, at init).
            // A thread-id-opened one clears it here so a second `load()` — after the
            // thread this id named was deleted elsewhere, say — does not keep showing
            // the previous subject while this attempt resolves.
            subject = nil
        }

        guard let workoutRepository, let scoreRepository, let planRepository,
              let settingsRepository, let chatThreadRepository
        else {
            loadState = .failed
            return
        }
        do {
            let resolvedSubject: ChatSubject
            let resolvedThread: ChatThread

            switch opening {
            case let .subject(openingSubject):
                resolvedSubject = openingSubject
                guard let resolvedContext = try await buildContext(
                    for: resolvedSubject,
                    workoutRepository: workoutRepository,
                    scoreRepository: scoreRepository,
                    planRepository: planRepository,
                    settingsRepository: settingsRepository
                ) else { return }
                self.context = resolvedContext
                // MAX-092: the thread is resolved from its subject rather than looked
                // up by workout. A minted thread is not written here — it reaches disk
                // on the first completed turn, per this type's "Only completed turns
                // are persisted".
                resolvedThread = try await chatThreadRepository.thread(
                    for: resolvedSubject,
                    newThreadID: UUID(),
                    at: now()
                )

            case let .newThread(openingSubject):
                resolvedSubject = openingSubject
                guard let resolvedContext = try await buildContext(
                    for: resolvedSubject,
                    workoutRepository: workoutRepository,
                    scoreRepository: scoreRepository,
                    planRepository: planRepository,
                    settingsRepository: settingsRepository
                ) else { return }
                self.context = resolvedContext
                // MAX-185: mint, never resolve. `ChatThreadRepository.thread(for:...)`
                // is deliberately not called here — it would return
                // `mostRecentThread(for:)` when one exists, which is exactly the no-op
                // **New chat** exists to not be. A fresh, unstored thread every time is
                // the point; it reaches disk the same way any other minted thread does,
                // on the first completed turn.
                resolvedThread = try ChatThread(id: UUID(), subject: resolvedSubject, lastActivityAt: now())

            case let .threadID(threadID):
                // §2.3: the thread list knows a specific conversation, not a subject.
                // Reading `resolvedSubject` off the *stored thread* — never supplying
                // one — is what keeps this model from ever building a context for a
                // window that disagrees with the thread it actually opened (§3.6). A
                // thread that no longer resolves is what a delete on another screen
                // leaves behind: an ordinary state, not a failure.
                guard let existing = try await chatThreadRepository.thread(id: threadID) else {
                    loadState = .threadNotFound
                    return
                }
                resolvedSubject = existing.subject
                resolvedThread = existing
                // Set before `buildContext`, not after, so a state that returns early
                // from inside it — `.notYetScored`, `.noVerdict`, `.failed` — still
                // knows what this thread is about; `title`/`subtitle` read `subject`
                // regardless of `loadState`.
                self.subject = resolvedSubject
                guard let resolvedContext = try await buildContext(
                    for: resolvedSubject,
                    workoutRepository: workoutRepository,
                    scoreRepository: scoreRepository,
                    planRepository: planRepository,
                    settingsRepository: settingsRepository
                ) else { return }
                self.context = resolvedContext
            }

            self.subject = resolvedSubject
            self.thread = resolvedThread
            self.messages = resolvedThread.visibleMessages.map(Self.displayMessage)
            self.loadState = .ready
        } catch {
            loadState = .failed
        }
    }

    /// Exhaustive over `ChatSubject`. Each branch gathers the stored records its
    /// subject needs and hands them to the one assembler; neither composes prompt text
    /// of its own (A12 rule 1).
    ///
    /// - Returns: nil when a terminal state other than `.ready` has already been set —
    ///   an unscored run is not a failure and must not be overwritten by one.
    private func buildContext(
        for subject: ChatSubject,
        workoutRepository: any WorkoutRepository,
        scoreRepository: any ScoreRepository,
        planRepository: any PlanRepository,
        settingsRepository: any SettingsRepository
    ) async throws -> PromptContext? {
        switch subject {
        case let .workout(workoutID):
            return try await workoutContext(
                for: workoutID,
                subject: subject,
                workoutRepository: workoutRepository,
                scoreRepository: scoreRepository,
                planRepository: planRepository,
                settingsRepository: settingsRepository
            )
        case let .training(scope):
            return try await trainingContext(
                for: scope,
                subject: subject,
                workoutRepository: workoutRepository,
                scoreRepository: scoreRepository,
                planRepository: planRepository,
                settingsRepository: settingsRepository
            )
        }
    }

    /// The stored records for one run, gathered in the order that keeps this ticket's
    /// regression promise: the same guards as before MAX-096, in the same sequence,
    /// producing the same states.
    ///
    /// `ContextBuilder` throws on all four of these conditions rather than distinguishing
    /// them, so the guards stay here — `.notYetScored` and `.noVerdict` are product
    /// states a thrown error cannot carry.
    ///
    /// **The fetch is widened to the subject's own Monday-first training week** (MAX-182) —
    /// C1, restated by `ContextInputs`' own documentation, now binding this subject too. The
    /// week around the run is part of a workout context, its tallies come from
    /// `TalliesCalculator`, and that calculator cannot widen the workouts it was handed: a
    /// caller passing only the subject's record would have every other prescribed day in the
    /// week reported as a miss. `ContextBuilder` narrows the extra records back out itself.
    ///
    /// - Returns: nil when a terminal state other than `.ready` has already been set.
    private func workoutContext(
        for workoutID: UUID,
        subject: ChatSubject,
        workoutRepository: any WorkoutRepository,
        scoreRepository: any ScoreRepository,
        planRepository: any PlanRepository,
        settingsRepository: any SettingsRepository
    ) async throws -> PromptContext? {
        guard let workout = try await workoutRepository.workout(id: workoutID) else {
            loadState = .failed
            return nil
        }
        // MAX-097: resolved as soon as the workout is, regardless of which state this
        // method exits through afterward, so `title` can name the run even while chat
        // itself is `.notYetScored` or `.noVerdict`.
        workoutFacts = WorkoutThreadFacts(day: try workout.calendarDay(in: timeZone), activityType: workout.activityType)
        // See "Why a workout thread requires an existing score": no ledger means no
        // stored classification, and this type does not derive one of its own.
        guard let ledger = try await scoreRepository.ledger(forWorkout: workoutID) else {
            // The same `isScoreable` split `WorkoutVerdict` and `ScoreCalendar` make, for
            // the same reason: without it, a ride is told a score is on its way. It was
            // `isRun` until MAX-168 opened the gate for a lift, at which point telling a
            // lift no score is coming became the wrong half of the same mistake.
            loadState = workout.activityType.isScoreable ? .notYetScored : .noVerdict
            return nil
        }
        guard let metrics = try await workoutRepository.derivedMetrics(forWorkout: workoutID) else {
            // A scored workout always has metrics — scoring reads them. Treated as a load
            // failure rather than silently building a context without them.
            loadState = .failed
            return nil
        }
        guard let planCalendar = try await planRepository.planCalendar() else {
            loadState = .failed
            return nil
        }

        // The only place in the app that asks for the wider per-run payload (MAX-068): a
        // thread the athlete opened, to answer a question they typed. `ContextBuilder`
        // pins the `.chat` audience itself; the scoring path reaches
        // `WorkoutContextBuilder` directly and is shown strictly less.
        let heartRateSeries = try await workoutRepository.heartRateSeries(forWorkout: workoutID)
        var records = [
            try ContextInputs.WorkoutRecord(
                workout: workout,
                metrics: metrics,
                ledger: ledger,
                heartRateSeries: heartRateSeries
            ),
        ]

        let day = try workout.calendarDay(in: timeZone)
        let weekStart = try day.startOfTrainingWeek()
        let week = try DateInterval.covering(
            from: weekStart,
            through: weekStart.adding(days: 6),
            in: timeZone
        )
        for other in try await workoutRepository.workouts(startingIn: week) where other.id != workoutID {
            records.append(try ContextInputs.WorkoutRecord(
                workout: other,
                // The week block carries no metric for any session but the subject's — see
                // `WorkoutContext.SurroundingWeek` for the list it leaves behind and why. The
                // cheapest way not to send a drift figure is not to load one.
                metrics: nil,
                // Read, because the week's verdicts and its tallies are both built from the
                // ledger the scorer wrote (D8), never from a judgement made here.
                ledger: try await scoreRepository.ledger(forWorkout: other.id),
                heartRateSeries: nil
            ))
        }

        // Read by `TalliesCalculator`, which a workout subject now does reach: the week's
        // effective-sessions figure applies D9's weekly rest allowance, and computing it
        // against `.standard` for an athlete who set something else would make a figure in
        // this thread disagree with the identical figure on the dashboard. That is a new way
        // for a workout thread to fail — the settings store can refuse to open — and it is
        // the price of the two surfaces being unable to contradict each other (§3.6(a)).
        let settings = try await settingsRepository.settings()
        let currentDay = try today()
        return try ContextBuilder.build(
            for: subject,
            from: try ContextInputs(
                timeZone: timeZone,
                today: currentDay,
                planCalendar: planCalendar,
                restDayBudget: settings.restDayBudget,
                records: records
            )
        )
    }

    /// The stored records for a frozen window.
    ///
    /// **The fetch is widened to whole Monday-first training weeks** — C1, restated by
    /// `ContextInputs`' own documentation. `TalliesCalculator` ranks a missed day against
    /// the other misses in its week and cannot widen the workouts it was handed, so a
    /// scope that does not start on a Monday would misjudge its edges and the roll-up
    /// would disagree with the dashboard — the failure §3.6 exists to make impossible.
    /// `ContextBuilder` narrows the extra days back out of the session list itself.
    private func trainingContext(
        for scope: TrainingScope,
        subject: ChatSubject,
        workoutRepository: any WorkoutRepository,
        scoreRepository: any ScoreRepository,
        planRepository: any PlanRepository,
        settingsRepository: any SettingsRepository
    ) async throws -> PromptContext? {
        // Nil is a real state here, unlike the workout path: an athlete who has authored
        // no plan still has a window worth describing, and `TrainingContext` says so
        // rather than refusing to open.
        let planCalendar = try await planRepository.planCalendar()
        let settings = try await settingsRepository.settings()

        let widened = try DateInterval.covering(
            from: scope.from.startOfTrainingWeek(),
            through: scope.through.startOfTrainingWeek().adding(days: 6),
            in: timeZone
        )
        var records: [ContextInputs.WorkoutRecord] = []
        for workout in try await workoutRepository.workouts(startingIn: widened) {
            records.append(try ContextInputs.WorkoutRecord(
                workout: workout,
                metrics: try await workoutRepository.derivedMetrics(forWorkout: workout.id),
                ledger: try await scoreRepository.ledger(forWorkout: workout.id),
                // §3.3: a roll-up carries no heart-rate curve for any session, so the
                // read is skipped rather than made and discarded. The cheapest way not to
                // send a curve is not to load one.
                heartRateSeries: nil
            ))
        }

        let currentDay = try today()
        return try ContextBuilder.build(
            for: subject,
            from: try ContextInputs(
                timeZone: timeZone,
                today: currentDay,
                planCalendar: planCalendar,
                restDayBudget: settings.restDayBudget,
                records: records
            )
        )
    }

    /// The athlete's current civil day, from the injected clock.
    ///
    /// `TalliesCalculator` withholds days whose outcome is not yet known from both sides
    /// of the effective-day ratio, so it has to be told what day it is (MAX-110) — and it
    /// must be the same day the dashboard resolved, or chat and a tile disagree about
    /// whether today counts. Derived from `now` rather than taken as a separate parameter
    /// so this type has exactly one notion of the present.
    private func today() throws -> CalendarDay {
        try CalendarDay(now(), in: timeZone)
    }

    // MARK: - Sending

    /// Sends `composerText` as the next user turn and streams the reply.
    ///
    /// A no-op when `canSend` is false, so a view may call this unconditionally from a
    /// disabled button's action without a second guard.
    public func send() async {
        let question = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, let context, let thread, let chatThreadRepository else { return }

        let pending: PendingTurn
        do {
            let userMessage = try ChatMessage(id: UUID(), role: .user, content: question, timestamp: now())
            let priorTurns = try thread.visibleMessages.map(Self.turn(for:))
            let turns = priorTurns + [try Self.turn(for: userMessage)]
            // The whole conversation goes in; `ChatInstruction` applies §8.2's cap and
            // says so inside the transcript when it bites. Nothing is trimmed here, so
            // there is exactly one place that bound lives.
            pending = PendingTurn(
                message: userMessage,
                instruction: try ChatInstruction(
                    task: Self.task(for: context.subjectKind),
                    factSheet: context.factSheet(),
                    turns: turns
                )
            )
        } catch {
            // Unreachable in practice — `question` is non-empty (the `canSend` guard
            // above), and every stored `ChatMessage` already satisfies `ChatTurn`'s
            // own non-empty rule. Handled rather than force-unwrapped so a genuinely
            // surprising input becomes a visible notice, not a crash mid-conversation.
            note(ChatFailureNotice.couldNotSendMessage)
            return
        }

        composerText = ""
        messages.append(Self.displayMessage(for: pending.message))
        pendingTurn = pending

        await stream(pending, thread: thread, chatThreadRepository: chatThreadRepository)
    }

    /// Asks the same question again, after a failure that is worth asking again
    /// (MAX-152, `canRetry`).
    ///
    /// A no-op when `canRetry` is false, so a view may call this unconditionally from a
    /// button's action — the same shape `send()` and `draftPlan()` have.
    ///
    /// **One call per tap, and never a call this app decided to make.** There is no
    /// timer here, no automatic second attempt and no loop: A14's rule that nothing
    /// reaches the model unattended holds for retries exactly as it holds for the first
    /// send, and `ChatFailureNotice`'s retry note carries the argument for why this
    /// deliberately does not follow `PlanProposalDrafting`'s one-automatic-retry policy.
    ///
    /// **Nothing is erased.** The failed attempt's partial reply and its notice stay in
    /// the transcript above the new answer, because they happened — this is the additive
    /// treatment D8 gives a correction, one surface over. Neither was ever persisted, so
    /// a reload shows the question and the reply that finally arrived, and nothing else.
    public func retry() async {
        guard canRetry, let pending = pendingTurn, let thread, let chatThreadRepository else { return }
        await stream(pending, thread: thread, chatThreadRepository: chatThreadRepository)
    }

    /// Opens one request and consumes it to its terminal event.
    ///
    /// The one place events reach the ladder. Every `progress.apply` in this type is
    /// here or in `resolve`, which is what keeps "which state is showing" a single
    /// derivation rather than something reconstructed at each call site.
    private func stream(
        _ pending: PendingTurn,
        thread: ChatThread,
        chatThreadRepository: any ChatThreadRepository
    ) async {
        progress.apply(.requestOpened)
        streamingText = ""
        var accumulated = ""
        var outcome: StreamOutcome?
        for await event in chatClient.stream(pending.instruction) {
            switch event {
            case let .text(delta):
                // Contract #1 (`ChatStreamEvent`): text only ever appends.
                accumulated += delta
                streamingText = accumulated
                // The ladder's second rung, and the reason the waiting indicator cannot
                // linger beside the words: the first token is what ends waiting.
                progress.apply(.textArrived)
            case .heartbeat:
                // The connection is open and nothing is being said. How many of these
                // amount to a stall is `ChatReplyProgress`'s decision (MAX-152).
                progress.apply(.heartbeat)
            case let .completed(completion):
                outcome = .completed(completion)
            case let .failed(streamError):
                outcome = .failed(streamError)
            }
        }

        // The assistant's message is built once, here, and both the phase and the
        // transcript read that one attempt. Deciding "was there a usable reply" twice —
        // once for the phase and once for the row — is the drift D2 warns about in
        // miniature: the surface would say the reply completed while the transcript said
        // nothing arrived.
        let assistantMessage: ChatMessage? = accumulated.isEmpty
            ? nil
            : try? ChatMessage(id: UUID(), role: .assistant, content: accumulated, timestamp: now())

        switch outcome {
        case let .completed(completion):
            progress.apply(assistantMessage == nil ? .producedNoUsableText : .completed(completion))
        case let .failed(streamError):
            progress.apply(.failed(streamError))
        case nil:
            progress.apply(.endedWithoutTerminalEvent)
        }
        // Cleared only once the phase is terminal. The other order would leave the view
        // rendering a `.streaming` bubble with no text in it for however long the store
        // write below takes — the "streaming" rung showing exactly what the "waiting"
        // rung is for.
        streamingText = ""

        await resolve(
            outcome,
            accumulated: accumulated,
            assistantMessage: assistantMessage,
            pending: pending,
            thread: thread,
            chatThreadRepository: chatThreadRepository
        )
    }

    private enum StreamOutcome {
        case completed(ChatTurnCompletion)
        case failed(ChatStreamError)
    }

    private func resolve(
        _ outcome: StreamOutcome?,
        accumulated: String,
        assistantMessage: ChatMessage?,
        pending: PendingTurn,
        thread: ChatThread,
        chatThreadRepository: any ChatThreadRepository
    ) async {
        switch outcome {
        case let .completed(completion):
            guard let assistantMessage else {
                // The decoder only ever emits `.text` for non-empty deltas, so an
                // entirely empty completed reply is not expected — handled rather than
                // assumed impossible, and said as the distinct thing it is: the request
                // worked and produced nothing, which is neither a dropped connection nor
                // an answer.
                note(.emptyReply)
                return
            }
            do {
                var updated = try thread.appending(pending.message)
                updated = try updated.appending(assistantMessage)
                // The only write this type performs (§2.5), and only a completed turn
                // reaches it — see "Only completed turns are persisted."
                try await chatThreadRepository.store(updated)
                self.thread = updated
                messages.append(DisplayMessage(
                    kind: .assistant,
                    text: accumulated,
                    wasTruncated: completion == .truncated
                ))
                // The question has an answer on disk; there is nothing left to ask again.
                pendingTurn = nil
            } catch {
                // The reply is real and already read; only the write failed. Keeping it
                // on screen follows the same reasoning as a stream failure — a local
                // storage problem is not a reason to erase an answer the athlete
                // already has — but it does mean the transcript and the store now
                // disagree, so that is said plainly rather than hidden.
                messages.append(DisplayMessage(
                    kind: .assistant,
                    text: accumulated,
                    wasTruncated: completion == .truncated
                ))
                note(.couldNotSaveReply)
                // Deliberately keeps `pendingTurn`, and deliberately does not offer a
                // retry: `.complete`/`.truncated` do not (`ChatReplyPhase.offersRetry`),
                // because asking Claude again cannot fix a failed local write and would
                // spend a call on a problem that is not Claude's.
            }

        case .failed, nil:
            // Constraint: partial text survives a failure, on screen — never persisted.
            // `pendingTurn` is kept, which is what makes "Try again" possible for the
            // failures worth asking again.
            if !accumulated.isEmpty {
                messages.append(DisplayMessage(kind: .assistant, text: accumulated, wasInterruptedByFailure: true))
            }
            // Read off the phase rather than off `outcome`, so the words and the state
            // the surface is in cannot describe different failures. A stream that ended
            // with no terminal event at all — forbidden by `ChatStreamEvent`'s contract,
            // handled anyway — has already been folded into `.interrupted` above, which
            // is the same thing said in the vocabulary the athlete reads.
            if case let .failed(streamError) = replyPhase {
                note(ChatFailureNotice.notice(for: streamError, subject: subject?.kind))
            }
        }
    }

    /// Appends a failure's sentence to the transcript as a `.notice` — never a turn,
    /// never persisted (see `DisplayMessage.Kind.notice`).
    private func note(_ notice: ChatFailureNotice) {
        messages.append(DisplayMessage(kind: .notice, text: notice.message))
    }

    // MARK: - Drafting a plan from this conversation (MAX-101, §4)

    /// Asks the model for a `PlanProposal` built from this conversation, and prepares
    /// the review card for it.
    ///
    /// A no-op when `canDraftPlan` is false, so a view may call this unconditionally
    /// from a disabled button's action without a second guard — the same shape `send()`
    /// has.
    ///
    /// ## What this does and does not touch
    ///
    /// It reads: the context `load()` already built (never a second assembly — D3), the
    /// thread's visible turns, the stored plan calendar, and the athlete's distance unit.
    /// It writes: `planDrafting`, and a `.notice` in the transcript when it fails.
    ///
    /// **It stores nothing.** The plan calendar is read to work out which version a
    /// proposal would supersede — that is what makes the card a diff rather than a
    /// restatement (§4.6) — and no write of any kind follows. See A13, and this type's
    /// note on §2.5.
    ///
    /// ## The proposal is not appended to the thread
    ///
    /// §2.5 and this type's "only completed turns are persisted" both apply: a proposal
    /// is neither a question the athlete asked nor a reply Claude gave, so it is not one
    /// of the thread's turns and is never written. It lives on `planDrafting` until the
    /// athlete accepts it, discards it, or closes the sheet.
    public func draftPlan() async {
        guard canDraftPlan,
              let planProposalClient,
              let planRepository,
              let context,
              let thread
        else { return }

        let turns: [ChatTurn]
        do {
            turns = try thread.visibleMessages.map(Self.turn(for:))
        } catch {
            // Unreachable — every stored `ChatMessage` already satisfies `ChatTurn`'s
            // non-empty rule. Said plainly rather than force-unwrapped.
            noteDraftingFailure(.nothingToDraftFrom)
            return
        }

        planDrafting = .drafting
        // One call per tap, with at most §4.5's one correction inside it. The policy is
        // `PlanProposalDrafting`'s and is tested there; this only reports the outcome.
        let outcome = await PlanProposalDrafting.proposal(
            from: planProposalClient,
            factSheet: context.factSheet(),
            turns: turns
        )

        switch outcome {
        case let .failed(failure):
            noteDraftingFailure(failure)
        case let .proposed(proposal):
            await presentReview(of: proposal, planRepository: planRepository)
        }
    }

    /// Builds the card against the athlete's stored plans, and shows it.
    ///
    /// The session built here is the same one `PlanAuthoringView` will build when the
    /// handoff opens it — same function, same inputs — which is what keeps the card's
    /// "changed from" from describing a comparison the form will not make.
    private func presentReview(
        of proposal: PlanProposal,
        planRepository: any PlanRepository
    ) async {
        do {
            let session = try PlanAuthoring.session(
                revising: try await planRepository.planCalendar(),
                today: try today()
            )
            planDrafting = .proposed(
                try PlanProposalReview.build(
                    applying: proposal,
                    to: session,
                    distanceUnit: await draftingDistanceUnit()
                )
            )
        } catch {
            // The proposal parsed but the card could not be prepared — a plan store that
            // could not be read, essentially. Reported as the failure it is rather than
            // shown as a card with half its rows missing, and the plan in force is
            // untouched either way.
            noteDraftingFailure(.transport(.requestFailed))
        }
    }

    /// A settings read that fails is not a reason to refuse to show a proposal — the
    /// unit is a display preference, and `AppSettings.standard`'s is a defensible
    /// answer. The same call `PlanAuthoringModel` makes, for the same reason.
    private func draftingDistanceUnit() async -> DistanceUnit {
        guard let settingsRepository,
              let settings = try? await settingsRepository.settings()
        else { return AppSettings.standard.distanceUnit }
        return settings.distanceUnit
    }

    /// §4.5 step 2, and the ticket's "failure is a state": every way this can fail gets
    /// one honest sentence in the transcript, as a notice — never written to the thread,
    /// exactly like a dropped stream's.
    ///
    /// Reads `PlanDraftingNotice`, not `PlanDraftingFailure.description` (MAX-155):
    /// `description` is a developer diagnostic — it carries `PlanProposalModelError`'s
    /// bare HTTP status number — and `PlanDraftingNotice` is the type that turns the
    /// failure into words safe for this transcript, the same split `ChatFailureNotice`
    /// keeps for a dropped stream.
    private func noteDraftingFailure(_ failure: PlanDraftingFailure) {
        planDrafting = .idle
        messages.append(DisplayMessage(kind: .notice, text: PlanDraftingNotice.notice(for: failure).message))
    }

    /// Rejecting a proposal. Leaves the plan in force **completely** untouched, which
    /// costs nothing to guarantee because nothing was ever written: this drops a value
    /// held in memory.
    ///
    /// A notice is appended rather than the card vanishing silently, because a card that
    /// disappears on tap leaves an athlete unsure whether they just changed something.
    public func discardProposal() {
        guard case .proposed = planDrafting else { return }
        planDrafting = .idle
        messages.append(DisplayMessage(
            kind: .notice,
            text: "Proposal discarded. Your plan is unchanged."
        ))
    }

    /// The proposal awaiting review, if there is one — what the accept action hands to
    /// `PlanAuthoringView`.
    ///
    /// Note what this returns: a `PlanProposal`, not a `Plan` and not a `PlanDraft`. The
    /// handoff carries the model's proposal to the authoring screen, which builds its own
    /// session against storage as it always has and applies the proposal to *that* draft.
    /// Handing over a finished draft would let a stale session — one built before a plan
    /// was saved on another screen — reach the form.
    public var proposalAwaitingReview: PlanProposal? {
        guard case let .proposed(review) = planDrafting else { return nil }
        return review.proposal
    }

    // MARK: - Mapping

    private static func turn(for message: ChatMessage) throws -> ChatTurn {
        try ChatTurn(speaker: message.role == .user ? .user : .assistant, text: message.content)
    }

    private static func displayMessage(for message: ChatMessage) -> DisplayMessage {
        DisplayMessage(id: message.id, kind: message.role == .user ? .user : .assistant, text: message.content)
    }

    // MARK: - What Claude is asked to do

    /// The instruction for a thread of this kind.
    ///
    /// Stable across every chat turn of that kind and free of health data — the same
    /// contract `ScoringInstruction.task` carries (`ChatInstruction.task`'s own
    /// documentation), which is also what lets it travel as a cacheable system block.
    /// Written here because "what to ask Claude to do in a chat turn" is this feature's
    /// product decision, not the transport's.
    static func task(for kind: ChatSubjectKind) -> String {
        switch kind {
        case .workout: return workoutTask
        case .training: return trainingTask
        }
    }

    /// Unchanged by MAX-096, deliberately: a workout thread's answers should not shift
    /// because a second subject was added beside it.
    static let workoutTask = """
        You are the in-app assistant for Maximize, a running-training app. The athlete \
        is looking at one specific workout on screen; a fact sheet describing it — the \
        plan in force, what was measured, and the score already assigned — is provided \
        alongside this instruction, and every question below is about that run.

        Answer using only the fact sheet and the conversation so far. Never invent a \
        number, split, or detail the fact sheet does not state; when something was not \
        measured, or the fact sheet says it does not apply, say so rather than \
        guessing. If a question strays outside this one workout — a future training \
        plan, another run, medical advice — say that is outside what you can see here \
        rather than answering from general knowledge as if it were a fact about this \
        athlete.

        Keep answers conversational and short — a sentence or a brief paragraph, not a \
        report. The athlete already has the numbers on screen; they are asking you to \
        interpret them, not repeat them.
        """

    /// §3.5's five requirements, written as prose a person would say.
    ///
    /// Two of them are load-bearing beyond the obvious. **Naming the window** is
    /// §3.6(b)'s mechanism: the thread's scope is frozen and the dashboard's is not, so
    /// one figure over two windows is two correct answers that read as a contradiction —
    /// saying which window a number came from turns an ambush into a labelled
    /// difference. **Not re-scoring** is D8 from the other side: a model invited to offer
    /// a second opinion in prose produces exactly the correction that is recorded
    /// nowhere, which is the opposite of the auto-versus-manual divergence PRD §2 exists
    /// to measure.
    static let trainingTask = """
        You are the in-app assistant for Maximize, a running-training app. The athlete \
        is asking about a stretch of their training rather than about one workout, and a \
        summary of that stretch — the plan in force, the tallies over it, and one line \
        per session — is provided alongside this instruction. The window it covers is \
        fixed for this conversation and is stated at the top of the summary.

        Answer using only that summary and the conversation so far. Never invent a \
        figure it does not state; when something is not in it, say so plainly rather \
        than estimating. Whenever you quote a total, an average, a streak, or any other \
        figure measured across the window, name the window you measured it over in the \
        same sentence — the athlete may be looking at a different date range on screen, \
        and a number without its window is the one thing here that can quietly \
        contradict what they can already see.

        The per-session lines are a summary and only that. There are no kilometre \
        splits here, and no heart-rate curve for any single run, so a question that \
        needs either is one to answer by saying it is not in front of you and pointing \
        the athlete at that run's own conversation, where it is.

        The scores in the summary have already been assigned, and they are not up for \
        revision. Explain what one means or what drove it, but never re-score a session, \
        offer a score of your own, or say what a run should have scored instead. If the \
        athlete disagrees with one, tell them a correction is something they record on \
        the run itself.

        No medical advice. If a question turns on pain, injury, illness, medication or \
        anything else clinical, say plainly that it is outside what this app should \
        answer, and leave it there.

        Otherwise keep answers conversational and short — a sentence or a brief \
        paragraph, not a report. The athlete has the same figures on screen; they are \
        asking you to read them, not recite them.
        """
}
