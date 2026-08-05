import Foundation

/// Who said it.
public enum ChatRole: String, Hashable, Sendable, Codable, CaseIterable {
    /// The seed context assembled by the context builder (D3, FR-2.1) — not typed by
    /// the user and not shown as a bubble.
    case system
    case user
    case assistant
}

/// One turn in a conversation (PRD §8 `chat_thread`'s `{role, content, ts}`).
public struct ChatMessage: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let timestamp: Date

    public init(id: UUID, role: ChatRole, content: String, timestamp: Date) throws {
        try Validate.nonEmpty(content, "ChatMessage.content")
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            role: container.decode(ChatRole.self, forKey: .role),
            content: container.decode(String.self, forKey: .content),
            timestamp: container.decode(Date.self, forKey: .timestamp)
        )
    }
}

/// One conversation, keyed on its own identifier and carrying a `ChatSubject` (A11,
/// FR-2.3).
///
/// ## Identity moved, and that is the point (A11, superseding D6)
///
/// Until MAX-092 a thread *was* its workout: `workoutID` was the key, one thread per
/// run, and "which thread" was never a question anybody had to answer. A11 breaks that,
/// because a thread about "has my drift flattened this month" has no workout to be. So
/// the thread is keyed on `id`, and the workout link becomes one field of one case of
/// `subject`.
///
/// Two consequences fall out, and both are deliberate:
///
/// - **"The thread for this subject" is now a query, not a lookup**, so it has to be
///   ordered rather than left to whatever storage returns first. That is
///   `ChatThreadRepository.mostRecentThread(for:)`, and it is the direct successor to
///   MAX-048's duplicate-resolution rule — see that protocol for the ordering.
/// - **More than one thread per subject is now representable.** For a training subject
///   that is the product ("New chat" over a newer window — §3.4); for a workout subject
///   the spec still wants one (§12, question 3), and that stays a repository policy
///   rather than a shape this type forbids, exactly so reversing it is a repository
///   change and not a migration.
///
/// Messages are ordered by `timestamp`, non-strictly: two turns can share a second,
/// but a thread that goes backwards in time would render as nonsense and mislead the
/// model when replayed as context.
///
/// Streaming (D10) happens outside this type. A partially-received assistant turn is
/// transport state; only the completed turn is appended here.
public struct ChatThread: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID

    /// What this conversation is about, and therefore what data may enter its prompts
    /// (A12). Immutable for the life of the thread: re-subjecting a thread would change
    /// what the transcript above it was answered from.
    public let subject: ChatSubject

    public let messages: [ChatMessage]

    /// What the thread list sorts on (§2.3) and what resolves "which thread opens"
    /// (§2.2).
    ///
    /// Stored rather than derived from `messages.last`, for one reason: a thread the
    /// athlete just opened has no messages yet and still has to sort into the list
    /// above a conversation from last month. Deriving would make every empty thread
    /// share the same sort key, which is the bug and not the saving.
    ///
    /// Never earlier than the last message — a transcript whose newest turn postdates
    /// the thread's own "last activity" would sort a live conversation to the bottom.
    public let lastActivityAt: Date

    /// - Parameter lastActivityAt: for a new thread, the moment it was created; for a
    ///   thread that has been talked to, the last turn's timestamp. `appending(_:)`
    ///   maintains it, so callers only supply it at creation.
    public init(
        id: UUID,
        subject: ChatSubject,
        messages: [ChatMessage] = [],
        lastActivityAt: Date
    ) throws {
        if messages.count > 1 {
            for index in 1..<messages.count where messages[index].timestamp < messages[index - 1].timestamp {
                throw DomainError.outOfOrder(field: "ChatThread.messages", index: index)
            }
        }
        if let last = messages.last, lastActivityAt < last.timestamp {
            throw DomainError.inconsistent(
                reason: "ChatThread.lastActivityAt precedes the timestamp of the thread's last message"
            )
        }
        self.id = id
        self.subject = subject
        self.messages = messages
        self.lastActivityAt = lastActivityAt
    }

    /// Returns a new thread with the message appended. Rejects a message that would
    /// break time order, so callers cannot build a thread that replays incorrectly.
    ///
    /// `lastActivityAt` advances to the appended turn, never backwards: an empty thread
    /// created now and then seeded with a turn stamped earlier keeps the later of the
    /// two, so a thread's position in the list only ever moves up.
    public func appending(_ message: ChatMessage) throws -> ChatThread {
        try ChatThread(
            id: id,
            subject: subject,
            messages: messages + [message],
            lastActivityAt: max(lastActivityAt, message.timestamp)
        )
    }

    /// Turns the user actually sees — the seed context is not a bubble.
    public var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    public var isEmpty: Bool { visibleMessages.isEmpty }

    /// The athlete's opening question, which is a training thread's title (§2.4).
    ///
    /// `.user` specifically, not "the first visible message": the seed context is a
    /// `.system` turn and an assistant turn cannot come first, but saying which role is
    /// wanted keeps the title rule readable next to the thing it titles.
    public var firstUserMessage: ChatMessage? {
        messages.first { $0.role == .user }
    }

    /// What a list row previews (§2.3). Nil while the thread is empty.
    public var lastVisibleMessage: ChatMessage? {
        visibleMessages.last
    }

    private enum CodingKeys: String, CodingKey {
        case id, subject, messages, lastActivityAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            subject: container.decode(ChatSubject.self, forKey: .subject),
            messages: container.decode([ChatMessage].self, forKey: .messages),
            lastActivityAt: container.decode(Date.self, forKey: .lastActivityAt)
        )
    }
}
