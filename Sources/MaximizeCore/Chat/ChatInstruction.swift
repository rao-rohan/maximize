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
/// - `factSheet` is one run and is the only part that carries PII. It is stable for
///   the whole life of a thread, so it caches too — every turn after the first reads
///   it rather than re-sending it at full price.
/// - `turns` is the conversation, and it is the only part that grows.
///
/// Keeping them apart means the sensitive text is a single, reviewable value rather
/// than something interleaved through a template, and CLAUDE.md's rule that only what
/// chat needs enters a prompt stays checkable by reading one property.
///
/// ## This type does not assemble anything (D3)
///
/// `factSheet` must be `WorkoutContext.factSheet()` **verbatim**. MAX-014 is the
/// single assembler of what Claude knows about a run, and a transport that composed,
/// trimmed or re-rendered that text would be a second one — the exact drift D3 exists
/// to prevent. Nothing in this file reads a `Workout`, a `DerivedMetrics` or a
/// `Score`; it takes two strings it did not write and a conversation it did not have.
///
/// `task` is likewise the caller's. There is no default: a default would be this
/// ticket authoring prompt text, and what to ask Claude to do in a chat turn is a
/// product decision belonging with the chat feature (MAX-051), not with the code that
/// moves the bytes.
public struct ChatInstruction: Hashable, Sendable {
    /// Stable across every chat turn in the app. No health data, no plan data, no
    /// numbers — the same contract `ScoringInstruction.task` carries.
    public let task: String

    /// This run, rendered by `WorkoutContext.factSheet()` and passed through
    /// unchanged. The only half of this type that carries PII.
    public let factSheet: String

    /// The conversation so far, oldest first, ending with the turn being answered.
    public let turns: [ChatTurn]

    /// - Throws: `DomainError` when the pieces could not be a valid exchange.
    ///
    ///   The first turn must be the user's, because the Messages API requires it and
    ///   because a thread that opens with an assistant turn is nonsense to replay.
    ///   Rejecting it here — in the core, under test — is what keeps that rule out of
    ///   the app layer, where it would only be discovered as a 400 from a live server.
    public init(task: String, factSheet: String, turns: [ChatTurn]) throws {
        try Validate.nonEmpty(task, "ChatInstruction.task")
        try Validate.nonEmpty(factSheet, "ChatInstruction.factSheet")
        guard let first = turns.first else {
            throw DomainError.empty(field: "ChatInstruction.turns")
        }
        guard first.speaker == .user else {
            throw DomainError.inconsistent(
                reason: "ChatInstruction.turns must begin with a user turn; the assistant "
                    + "cannot speak first."
            )
        }
        self.task = task
        self.factSheet = factSheet
        self.turns = turns
    }
}
