import Foundation
import Observation

/// The per-workout chat surface's whole state machine (FR-2.1–2.4, D10, MAX-051): what
/// the thread looks like, what has streamed in so far, and what actually gets
/// persisted.
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
/// `WorkoutChatModelTests` drives this against `InMemoryWorkoutStore`,
/// `FakeChatThreadRepository` and `FakeStreamingChatModelInvoking` — no SwiftData, no
/// simulator, no device (CLAUDE.md, "What CI can and cannot prove").
///
/// ## D3 — the fact sheet is never re-assembled
///
/// `load()` builds exactly one `WorkoutContext` (`WorkoutContextBuilder.build`, the
/// same call the scorer makes) and keeps it. Every `ChatInstruction` sent afterward
/// reads `context.factSheet()` again — a pure, deterministic render of that same
/// context — rather than reconstructing prompt text from the stored thread. Nothing
/// here composes, trims or summarises it.
///
/// ## Why chat requires an existing score
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
@MainActor
@Observable
public final class WorkoutChatModel {

    public enum LoadState: Equatable, Sendable {
        case loading
        /// A repository was unavailable, the workout does not exist, or a read failed.
        /// Mirrors every sibling screen's `.failed` (`WorkoutDetailModel`,
        /// `TrendTilesModel`, `SettingsModel`).
        case failed
        /// See this type's "Why chat requires an existing score." Ordinary, not an
        /// error — the app's state for every workout between capture and scoring.
        case notYetScored
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

    private let workoutID: UUID
    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let chatThreadRepository: (any ChatThreadRepository)?
    private let chatClient: any StreamingChatModelInvoking
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    /// Built once by `load()`, from stored data only, and read again — never rebuilt —
    /// by every `send()` afterward (see this type's "D3" note).
    private var context: WorkoutContext?
    private var thread: ChatThread?

    /// - Parameters:
    ///   - workoutRepository/scoreRepository/planRepository/chatThreadRepository:
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
    ///   - timeZone: the zone the workout's calendar day is resolved in, matching
    ///     `WorkoutDetailModel`'s own default and reasoning.
    ///   - now: injected rather than read from the clock so a sent turn's timestamps
    ///     are reproducible in a test, matching `WorkoutIngestionPipeline`'s `now`.
    public init(
        workoutID: UUID,
        workoutRepository: (any WorkoutRepository)?,
        scoreRepository: (any ScoreRepository)?,
        planRepository: (any PlanRepository)?,
        chatThreadRepository: (any ChatThreadRepository)?,
        chatClient: any StreamingChatModelInvoking,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workoutID = workoutID
        self.workoutRepository = workoutRepository
        self.scoreRepository = scoreRepository
        self.planRepository = planRepository
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

        guard let workoutRepository, let scoreRepository, let planRepository, let chatThreadRepository else {
            loadState = .failed
            return
        }
        do {
            guard let workout = try await workoutRepository.workout(id: workoutID) else {
                loadState = .failed
                return
            }
            // See "Why chat requires an existing score": no ledger means no stored
            // classification, and this type does not derive one of its own.
            guard let ledger = try await scoreRepository.ledger(forWorkout: workoutID) else {
                loadState = .notYetScored
                return
            }
            guard let metrics = try await workoutRepository.derivedMetrics(forWorkout: workoutID) else {
                // A scored workout always has metrics — scoring reads them. Treated as
                // a load failure rather than silently building a context without them.
                loadState = .failed
                return
            }
            guard let planCalendar = try await planRepository.planCalendar() else {
                loadState = .failed
                return
            }

            let day = try workout.calendarDay(in: timeZone)
            let heartRateSeries = try await workoutRepository.heartRateSeries(forWorkout: workoutID)
            let context = try WorkoutContextBuilder.build(
                workout: workout,
                on: day,
                metrics: metrics,
                classification: ledger.automatic.actualClassification,
                planCalendar: planCalendar,
                // The only place in the app that asks for the wider payload (MAX-068):
                // a thread the athlete opened, to answer a question they typed. The
                // scoring path leaves this defaulted and is shown strictly less.
                audience: .chat,
                heartRateSeries: heartRateSeries,
                // FR-2.1: chat is seeded with the score already assigned. Never nil
                // here, unlike the scorer's own build — see `WorkoutContext.existingScore`.
                existingScore: ledger.automatic
            )

            let storedThread = try await chatThreadRepository.thread(forWorkout: workoutID)
            let thread = try storedThread ?? ChatThread(id: UUID(), workoutID: workoutID)

            self.context = context
            self.thread = thread
            self.messages = thread.visibleMessages.map(Self.displayMessage)
            self.loadState = .ready
        } catch {
            loadState = .failed
        }
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
            instruction = try ChatInstruction(task: Self.task, factSheet: context.factSheet(), turns: turns)
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
                // Only a completed turn reaches here — see this type's "Only completed
                // turns are persisted."
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
            messages.append(DisplayMessage(kind: .notice, text: Self.userFacingMessage(for: streamError)))

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
    private static func userFacingMessage(for error: ChatStreamError) -> String {
        switch error {
        case .noAPIKeyStored:
            return "Add an Anthropic API key in Settings to chat about this workout."
        default:
            return error.description
        }
    }

    /// Stable across every chat turn in the app and free of health data — the same
    /// contract `ScoringInstruction.task` carries (`ChatInstruction.task`'s own
    /// documentation). Written here because "what to ask Claude to do in a chat turn"
    /// is this ticket's product decision, not the transport's.
    static let task = """
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
}
