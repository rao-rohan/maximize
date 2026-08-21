import Foundation

/// One side of a chat exchange, as the transport needs it: who spoke and what they
/// said, with nothing else attached.
///
/// Deliberately not `ChatMessage`. That type is the *stored* record (D6, FR-2.3) and
/// carries an id and a timestamp, neither of which belongs on the wire — see
/// `WorkoutContext`'s "what is deliberately absent": identifiers and provenance are
/// ours, and Claude has no use for them. Mapping a stored thread onto these turns is
/// the caller's job, and it is the only place the two representations meet.
public struct ChatTurn: Hashable, Sendable {
    /// User or assistant — and *not* system.
    ///
    /// `ChatRole` has a third case for the seed context (FR-2.1), and it is absent
    /// here on purpose: the seed context is not a conversational turn, it is the fact
    /// sheet, and it travels in `ChatInstruction.factSheet`. Encoding that in the type
    /// means a caller cannot accidentally send the context builder's output as a user
    /// message and quietly change what the model thinks it is reading.
    public enum Speaker: String, Hashable, Sendable, CaseIterable {
        case user
        case assistant
    }

    public let speaker: Speaker
    public let text: String

    public init(speaker: Speaker, text: String) throws {
        try Validate.nonEmpty(text, "ChatTurn.text")
        self.speaker = speaker
        self.text = text
    }
}

/// The text put in front of the model for one streaming chat turn, split by what it
/// contains.
///
/// The three-way split mirrors `ScoringInstruction`'s two-way one, for the same
/// reason and one more:
///
/// - `task` is identical for every chat turn in the app and holds no health data at
///   all, so it can be sent as a cacheable system block.
/// - `factSheet` is the thread's subject and is the only part that carries PII. It is
///   stable for the whole life of a thread — a workout does not change, and a training
///   scope is frozen (§3.4) — so it caches too, and every turn after the first reads it
///   rather than re-sending it at full price.
/// - `turns` is the conversation, and it is the only part that grows.
///
/// Keeping them apart means the sensitive text is a single, reviewable value rather
/// than something interleaved through a template, and CLAUDE.md's rule that only what
/// chat needs enters a prompt stays checkable by reading one property.
///
/// ## This type does not assemble anything (D3)
///
/// `factSheet` must be `PromptContext.factSheet()` **verbatim**. `ContextBuilder` is the
/// single assembler of what Claude knows about a subject (A12), and a transport that
/// composed, trimmed or re-rendered that text would be a second one — the exact drift D3
/// exists to prevent. Nothing in this file reads a `Workout`, a `DerivedMetrics`, a
/// `Score` or a `Tallies`; it takes two strings it did not write and a conversation it
/// did not have. Capping that conversation is the one thing it does to its inputs, and
/// it is deliberately mechanical: turns are dropped, never rewritten or summarised.
///
/// `task` is likewise the caller's. There is no default: a default would be this
/// ticket authoring prompt text, and what to ask Claude to do in a chat turn is a
/// product decision belonging with the chat feature (MAX-051), not with the code that
/// moves the bytes.
///
/// ## The transcript cap, and why it lives here (§8.2, A14)
///
/// `turns` is the only part of this type that grows without bound, so it is the only
/// part with a bound: **at most `maximumReplayedTurns` of the conversation are
/// replayed**, and older turns are dropped. That is a cost decision (A14: the transcript
/// is the one term that grows, since `task` and `factSheet` cache) and a privacy one (a
/// year-old thread should not re-send a year of the athlete's questions on every turn).
///
/// It is enforced **in this initializer rather than by the caller**, for the same reason
/// `ChatTurn` validates its own text: a bound a caller has to remember is a bound that is
/// eventually forgotten, and the failure is silent — a slightly larger request, not an
/// error. Every instruction the app can build is capped because there is no way to build
/// one that is not.
///
/// **When turns are dropped the model is told, in the transcript itself.** A14 states the
/// reason plainly: a model answering confidently as though it had seen the start of a
/// conversation it did not is worse than one that says it lost the thread. The notice is
/// a leading turn rather than a field the transport must remember to render, so what the
/// model actually receives is decided here, in the core, under test — and it is not a
/// second `task`: it says nothing about what to do with the run, only what this type did
/// to the conversation while assembling it, which is the one thing the caller cannot
/// know and this type can.
///
/// Rejected, per A14: summarising the dropped turns with a second model call. That is a
/// second assembler of context (A12) *and* it doubles the calls.
public struct ChatInstruction: Hashable, Sendable {

    /// The most recent turns replayed to the model — **40, or twenty exchanges**
    /// (CHAT-FIRST-SPEC.md §8.2).
    ///
    /// Chosen against how a thread is actually used rather than against a token budget,
    /// which no test in this repo can measure: twenty exchanges is far more than a
    /// conversation about one run ever reaches, and enough that a training thread stays
    /// coherent across a long sitting. Beyond it, the earliest turns are the least likely
    /// to bear on the question being asked, and the fact sheet — which is *not* capped —
    /// still carries every figure the answer needs.
    public static let maximumReplayedTurns = 40

    /// Stable across every chat turn of one thread kind. No health data, no plan data, no
    /// numbers — the same contract `ScoringInstruction.task` carries.
    public let task: String

    /// The subject, rendered by `PromptContext.factSheet()` and passed through unchanged.
    /// The only half of this type that carries PII.
    public let factSheet: String

    /// The conversation replayed to the model, oldest first, ending with the turn being
    /// answered.
    ///
    /// **Not necessarily what the caller passed in.** At most `maximumReplayedTurns` of
    /// the supplied conversation survive, and when any were dropped this begins with a
    /// notice turn saying so — see this type's "The transcript cap". `droppedTurnCount`
    /// tells the two cases apart without diffing the arrays.
    public let turns: [ChatTurn]

    /// How many of the supplied turns the cap dropped. Zero for every ordinary thread.
    public let droppedTurnCount: Int

    /// - Throws: `DomainError` when the pieces could not be a valid exchange.
    ///
    ///   The first turn must be the user's, because the Messages API requires it and
    ///   because a thread that opens with an assistant turn is nonsense to replay.
    ///   Rejecting it here — in the core, under test — is what keeps that rule out of
    ///   the app layer, where it would only be discovered as a 400 from a live server.
    ///
    /// - Parameter turns: the **whole** conversation, oldest first. Capping is this
    ///   initializer's job, not the caller's.
    public init(task: String, factSheet: String, turns: [ChatTurn]) throws {
        try Validate.nonEmpty(task, "ChatInstruction.task")
        try Validate.nonEmpty(factSheet, "ChatInstruction.factSheet")
        guard let first = turns.first else {
            throw DomainError.empty(field: "ChatInstruction.turns")
        }
        // Checked against the conversation as supplied, before the cap: the rule is about
        // the thread, and a window that happens to open on an assistant turn is the
        // ordinary result of dropping an odd number of turns, not a malformed thread.
        guard first.speaker == .user else {
            throw DomainError.inconsistent(
                reason: "ChatInstruction.turns must begin with a user turn; the assistant "
                    + "cannot speak first."
            )
        }

        let dropped = max(0, turns.count - Self.maximumReplayedTurns)
        let retained = Array(turns.suffix(Self.maximumReplayedTurns))
        if dropped > 0 {
            // A user turn, because the Messages API requires the first message to be the
            // user's and the notice has to come before the window it describes. Two
            // consecutive user messages are accepted and read as one turn, so this costs
            // the retained window nothing when it also opens on the athlete.
            self.turns = [try ChatTurn(speaker: .user, text: Self.droppedTurnsNotice(dropped))]
                + retained
        } else {
            self.turns = retained
        }
        self.droppedTurnCount = dropped
        self.task = task
        self.factSheet = factSheet
    }

    /// How many turns would be dropped from a conversation of the given size.
    ///
    /// One source of truth for the capping arithmetic, so two notions of "which turns
    /// are replayed" cannot drift apart. Used by both the instruction's initializer and
    /// by `ChatModel` to compute what would be sent if a message were added now.
    /// - Parameter turnCount: the total number of turns, including any that would be added.
    /// - Returns: how many of those would be dropped by the cap.
    public static func droppedCount(for turnCount: Int) -> Int {
        max(0, turnCount - Self.maximumReplayedTurns)
    }

    /// What the model is told when the cap bit.
    ///
    /// Bracketed so it cannot be mistaken for something the athlete typed, and explicit
    /// about the recovery: say the earlier part is gone rather than answer as if it were
    /// still there. Internal rather than private so a test can assert the model actually
    /// receives it, which is the whole point of deciding this in the core.
    static func droppedTurnsNotice(_ count: Int) -> String {
        "[Note from the app, not the athlete: this conversation is longer than what is "
            + "replayed to you. Its earliest \(count) \(count == 1 ? "turn is" : "turns are") "
            + "not included, and you cannot retrieve them. If a question depends on "
            + "something said before the part you can see, say that you no longer have "
            + "that stretch of the conversation instead of answering as though you do.]"
    }
}
