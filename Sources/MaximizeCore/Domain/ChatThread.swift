import Foundation

/// Who said it.
public enum ChatRole: String, Hashable, Sendable, Codable, CaseIterable {
    /// The seed context assembled by the context builder (D3, FR-2.1) — not typed by
    /// the user and not shown as a bubble.
    case system
    case user
    case assistant
}

/// One turn in a per-workout conversation (PRD §8 `chat_thread`'s
/// `{role, content, ts}`).
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

/// The conversation attached to one workout (D6, FR-2.3).
///
/// Messages are ordered by `timestamp`, non-strictly: two turns can share a second,
/// but a thread that goes backwards in time would render as nonsense and mislead the
/// model when replayed as context.
///
/// Streaming (D10) happens outside this type. A partially-received assistant turn is
/// transport state; only the completed turn is appended here.
public struct ChatThread: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let workoutID: UUID
    public let messages: [ChatMessage]

    public init(id: UUID, workoutID: UUID, messages: [ChatMessage] = []) throws {
        if messages.count > 1 {
            for index in 1..<messages.count where messages[index].timestamp < messages[index - 1].timestamp {
                throw DomainError.outOfOrder(field: "ChatThread.messages", index: index)
            }
        }
        self.id = id
        self.workoutID = workoutID
        self.messages = messages
    }

    /// Returns a new thread with the message appended. Rejects a message that would
    /// break time order, so callers cannot build a thread that replays incorrectly.
    public func appending(_ message: ChatMessage) throws -> ChatThread {
        try ChatThread(id: id, workoutID: workoutID, messages: messages + [message])
    }

    /// Turns the user actually sees — the seed context is not a bubble.
    public var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    public var isEmpty: Bool { visibleMessages.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, workoutID, messages
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            messages: container.decode([ChatMessage].self, forKey: .messages)
        )
    }
}
