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
/// **For a workout that is not a run it is not a wait at all** (MAX-126). MAX-111 stopped
/// non-runs being scored, so the lazy path above re-reaches the same conclusion every
/// time and no ledger ever appears. `.noVerdict` is that case, split out from
/// `.notYetScored` for the same reason `WorkoutVerdict.Scoring` splits it: the two states
/// are identical in what they lack and opposite in what happens next, and only one of
/// them can honestly tell the athlete to come back later.
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
/// ## A14 — nothing here calls the model unattended
///
/// `send()` is the only path to `StreamingChatModelInvoking`, and it is reached only from
/// a view forwarding a tap. `load()` reads storage and returns; it never streams. There
/// is no timer, no on-appear call, and no background wake anywhere in this file.
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

    public private(set) var loadState: LoadState = .loading

    /// Every row the view draws, oldest first — persisted turns and app-generated
    /// notices interleaved in the order they actually happened.
    public private(set) var messages: [DisplayMessage] = []

    /// True from the moment `send()` opens the stream until its terminal event, always
    /// — the `ChatStreamEvent` contract guarantees exactly one terminal event, so this
    /// can never get stuck true (FR-2.4's reveal is real progress, not a spinner that
    /// never resolves).
    public private(set) var isStreaming = false

    /// The reply as it arrives, token by token. Cleared the moment the stream ends,
    /// whichever way — by then its contents have become a `DisplayMessage`.
    public private(set) var streamingText = ""

    /// Bound directly to the composer's text field.
    public var composerText = ""

    public var canSend: Bool {
        loadState == .ready && !isStreaming
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What this conversation is about, and therefore which pile of stored data `load()`
    /// gathers and which `task` `send()` uses. Immutable: re-subjecting a live model
    /// would leave a transcript answered from something it no longer describes.
    public let subject: ChatSubject

    /// The sheet's title (§2.2, §2.4) — this thread's derived title, calling
    /// `ChatThreadTitle.derive(for:workoutFacts:)`, the one place titling is decided
    /// (MAX-092). "Chat" is a neutral placeholder for every state before `thread` is
    /// set — loading, `.failed`, `.notYetScored`, `.noVerdict` — matching what this
    /// screen's navigation title always read before this ticket generalised it.
    public var title: String {
        guard let thread else { return "Chat" }
        return ChatThreadTitle.derive(for: thread, workoutFacts: workoutFacts)
    }

    /// The sheet's subtitle (§2.2, §3.6(b)) — this thread's scope, stated. Known from
    /// `subject` alone, so unlike `title` it does not wait on `load()`.
    public var subtitle: String {
        ChatThreadSubtitle.text(for: subject)
    }

    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?
    private let chatThreadRepository: (any ChatThreadRepository)?
    private let chatClient: any StreamingChatModelInvoking
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
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.subject = subject
        self.workoutRepository = workoutRepository
        self.scoreRepository = scoreRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.chatThreadRepository = chatThreadRepository
        self.chatClient = chatClient
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

        guard let workoutRepository, let scoreRepository, let planRepository,
              let settingsRepository, let chatThreadRepository
        else {
            loadState = .failed
            return
        }
        do {
            // Exhaustive over `ChatSubject`. Each branch gathers the stored records its
            // subject needs and hands them to the one assembler; neither composes prompt
            // text of its own (A12 rule 1).
            let resolved: PromptContext?
            switch subject {
            case let .workout(workoutID):
                resolved = try await workoutContext(
                    for: workoutID,
                    workoutRepository: workoutRepository,
                    scoreRepository: scoreRepository,
                    planRepository: planRepository
                )
            case let .training(scope):
                resolved = try await trainingContext(
                    for: scope,
                    workoutRepository: workoutRepository,
                    scoreRepository: scoreRepository,
                    planRepository: planRepository,
                    settingsRepository: settingsRepository
                )
            }
            // Nil means the branch already set a terminal state of its own — an unscored
            // run is not a failure and must not be overwritten by one.
            guard let resolved else { return }

            // MAX-092: the thread is resolved from its subject rather than looked up by
            // workout. A minted thread is not written here — it reaches disk on the
            // first completed turn, per this type's "Only completed turns are
            // persisted".
            let thread = try await chatThreadRepository.thread(
                for: subject,
                newThreadID: UUID(),
                at: now()
            )

            self.context = resolved
            self.thread = thread
            self.messages = thread.visibleMessages.map(Self.displayMessage)
            self.loadState = .ready
        } catch {
            loadState = .failed
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
    /// - Returns: nil when a terminal state other than `.ready` has already been set.
    private func workoutContext(
        for workoutID: UUID,
        workoutRepository: any WorkoutRepository,
        scoreRepository: any ScoreRepository,
        planRepository: any PlanRepository
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
            // The same `isRun` split `WorkoutVerdict` and `ScoreCalendar` make, for the
            // same reason: without it, a lift is told a score is on its way.
            loadState = workout.activityType.isRun ? .notYetScored : .noVerdict
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
        let record = try ContextInputs.WorkoutRecord(
            workout: workout,
            metrics: metrics,
            ledger: ledger,
            heartRateSeries: heartRateSeries
        )
        let currentDay = try today()
        return try ContextBuilder.build(
            for: subject,
            from: try ContextInputs(
                timeZone: timeZone,
                today: currentDay,
                planCalendar: planCalendar,
                // Read by `TalliesCalculator` only, which no workout subject reaches, so
                // this path deliberately does not open the settings store: a read a
                // subject does not need is a new way for this thread to fail that it did
                // not have before MAX-096.
                restDayBudget: .standard,
                records: [record]
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

        let userMessage: ChatMessage
        let instruction: ChatInstruction
        do {
            userMessage = try ChatMessage(id: UUID(), role: .user, content: question, timestamp: now())
            let priorTurns = try thread.visibleMessages.map(Self.turn(for:))
            let turns = priorTurns + [try Self.turn(for: userMessage)]
            // The whole conversation goes in; `ChatInstruction` applies §8.2's cap and
            // says so inside the transcript when it bites. Nothing is trimmed here, so
            // there is exactly one place that bound lives.
            instruction = try ChatInstruction(
                task: Self.task(for: context.subjectKind),
                factSheet: context.factSheet(),
                turns: turns
            )
        } catch {
            // Unreachable in practice — `question` is non-empty (the `canSend` guard
            // above), and every stored `ChatMessage` already satisfies `ChatTurn`'s
            // own non-empty rule. Handled rather than force-unwrapped so a genuinely
            // surprising input becomes a visible notice, not a crash mid-conversation.
            messages.append(DisplayMessage(kind: .notice, text: "That message could not be sent."))
            return
        }

        composerText = ""
        messages.append(Self.displayMessage(for: userMessage))

        isStreaming = true
        streamingText = ""
        var accumulated = ""
        var outcome: StreamOutcome?
        for await event in chatClient.stream(instruction) {
            switch event {
            case let .text(delta):
                // Contract #1 (`ChatStreamEvent`): text only ever appends.
                accumulated += delta
                streamingText = accumulated
            case let .completed(completion):
                outcome = .completed(completion)
            case let .failed(streamError):
                outcome = .failed(streamError)
            }
        }
        isStreaming = false
        streamingText = ""

        await resolve(outcome, accumulated: accumulated, userMessage: userMessage, thread: thread, chatThreadRepository: chatThreadRepository)
    }

    private enum StreamOutcome {
        case completed(ChatTurnCompletion)
        case failed(ChatStreamError)
    }

    private func resolve(
        _ outcome: StreamOutcome?,
        accumulated: String,
        userMessage: ChatMessage,
        thread: ChatThread,
        chatThreadRepository: any ChatThreadRepository
    ) async {
        switch outcome {
        case let .completed(completion):
            guard !accumulated.isEmpty,
                  let assistantMessage = try? ChatMessage(id: UUID(), role: .assistant, content: accumulated, timestamp: now())
            else {
                // The decoder only ever emits `.text` for non-empty deltas, so an
                // entirely empty completed reply is not expected — handled rather than
                // assumed impossible.
                messages.append(DisplayMessage(kind: .notice, text: "Claude did not return a reply."))
                return
            }
            do {
                var updated = try thread.appending(userMessage)
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
                messages.append(DisplayMessage(kind: .notice, text: "This reply could not be saved."))
            }

        case let .failed(streamError):
            // Constraint: partial text survives a failure, on screen — never persisted.
            if !accumulated.isEmpty {
                messages.append(DisplayMessage(kind: .assistant, text: accumulated, wasInterruptedByFailure: true))
            }
            messages.append(DisplayMessage(kind: .notice, text: userFacingMessage(for: streamError)))

        case nil:
            // Unreachable per `ChatStreamEvent`'s "exactly one terminal event" contract
            // — handled rather than trusted, since nothing in the type system enforces
            // it on this side of the seam.
            messages.append(DisplayMessage(kind: .notice, text: "The reply stream ended unexpectedly."))
        }
    }

    // MARK: - Mapping

    private static func turn(for message: ChatMessage) throws -> ChatTurn {
        try ChatTurn(speaker: message.role == .user ? .user : .assistant, text: message.content)
    }

    private static func displayMessage(for message: ChatMessage) -> DisplayMessage {
        DisplayMessage(id: message.id, kind: message.role == .user ? .user : .assistant, text: message.content)
    }

    /// FR-2.4's "no key stored" ordinary state, pointed at the fix rather than left as
    /// a diagnostic string. Every other case reads `ChatStreamError.description`
    /// (`AnthropicStreamingChatClient`'s doc: it "never carries a response body," so
    /// this is always safe to show).
    private func userFacingMessage(for error: ChatStreamError) -> String {
        switch error {
        case .noAPIKeyStored:
            // Worded from the subject, because "this workout" is a lie on a thread about
            // a month. The two strings differ only in their last few words, and saying
            // the right one is the whole reason they are two.
            switch subject.kind {
            case .workout:
                return "Add an Anthropic API key in Settings to chat about this workout."
            case .training:
                return "Add an Anthropic API key in Settings to chat about your training."
            }
        default:
            return error.description
        }
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
