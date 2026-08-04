import MaximizeCore

/// In-memory stand-in for `AnthropicAPIKeyStoring`, substitutable wherever the real
/// Keychain-backed store would be injected.
///
/// This is what makes MAX-022's logic — and MAX-023/MAX-024's, later — unit
/// testable at all: Keychain cannot be exercised in this repo's CI (see CLAUDE.md —
/// "What CI can and cannot prove"), so every decision that matters is written to be
/// verifiable against this fake instead, leaving the real adapter thin and
/// decision-free.
///
/// Never seeded with anything resembling a real credential — see CLAUDE.md's "no
/// secrets in the repo" rule, which applies to fixtures too.
public final class FakeAnthropicAPIKeyStore: AnthropicAPIKeyStoring {
    private var storedKey: AnthropicAPIKey?

    /// Number of times `store` has been called, for tests that assert on call
    /// counts rather than just end state.
    public private(set) var storeCallCount = 0

    /// Number of times `delete` has been called.
    public private(set) var deleteCallCount = 0

    /// If set, `store`/`retrieve`/`delete` throw this instead of acting, so callers
    /// can be tested against a failing Keychain without one.
    public var errorToThrow: AnthropicAPIKeyError?

    public init(initialKey: AnthropicAPIKey? = nil) {
        self.storedKey = initialKey
    }

    public func store(_ key: AnthropicAPIKey) throws {
        storeCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        storedKey = key
    }

    public func retrieve() throws -> AnthropicAPIKey? {
        if let errorToThrow {
            throw errorToThrow
        }
        return storedKey
    }

    public func delete() throws {
        deleteCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        storedKey = nil
    }
}
