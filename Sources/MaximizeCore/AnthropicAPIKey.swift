import Foundation

/// A validated Anthropic API key, wrapped so it cannot leak through an accidental
/// `print`, string interpolation, or default struct description.
///
/// See CLAUDE.md — "Health and privacy": the key must never be logged, printed,
/// included in an error message, or written anywhere but Keychain. Swift's default
/// textual representation of a struct reflects its stored properties (including
/// private ones), so both `CustomStringConvertible` and `CustomDebugStringConvertible`
/// are overridden below — without that, `"\(key)"` or a debugger's `po` would print
/// the raw value.
public struct AnthropicAPIKey: Equatable {
    private let rawValue: String

    /// Fails on an empty or whitespace-only key. This is the one validation rule that
    /// belongs here rather than in a Keychain adapter: it is a decision, not
    /// plumbing, and CI can verify it without Keychain or a device.
    public init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnthropicAPIKeyError.emptyKey
        }
        self.rawValue = trimmed
    }

    /// The only way back to the raw string. Call sites that must put the key on the
    /// wire (MAX-023, MAX-024) call this explicitly and deliberately — nothing on
    /// this type hands the raw value out implicitly.
    public func revealed() -> String {
        rawValue
    }
}

extension AnthropicAPIKey: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "AnthropicAPIKey(<redacted>)" }
    public var debugDescription: String { "AnthropicAPIKey(<redacted>)" }
}

/// Errors from storing, retrieving, or deleting an `AnthropicAPIKey`.
///
/// `storeFailed`/`retrieveFailed`/`deleteFailed` carry an adapter-supplied message —
/// callers (the Keychain adapter in the app layer) must only ever put a static,
/// system-supplied status description in there (e.g. `SecCopyErrorMessageString`
/// output), never key material. There is no code path in this type that could embed
/// the key itself, since it never holds an `AnthropicAPIKey` or raw string in any
/// case's payload.
public enum AnthropicAPIKeyError: Error, Equatable {
    case emptyKey
    case storeFailed(String)
    case retrieveFailed(String)
    case deleteFailed(String)
}
