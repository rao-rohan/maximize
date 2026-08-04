/// Capability for persisting the user's Anthropic API key, independent of the
/// storage mechanism.
///
/// Consumers (Settings, and later MAX-023/MAX-024's Claude clients) depend on this
/// protocol, not on Keychain — matching CLAUDE.md's "thin shell, fat core" rule:
/// platform frameworks are reached through protocols defined in the core and
/// implemented in the app layer. The app layer supplies
/// `KeychainAnthropicAPIKeyStore`; tests supply `FakeAnthropicAPIKeyStore`
/// (MaximizeCoreTestSupport).
///
/// Keychain access cannot be exercised in this repo's CI (see CLAUDE.md — "What CI
/// can and cannot prove"), which is exactly why this boundary exists: everything on
/// this protocol's *calling* side is regular Swift, testable with a fake, and the
/// only code CI cannot verify is the thin adapter that implements it.
public protocol AnthropicAPIKeyStoring {
    /// Persists `key`, replacing any previously stored key.
    func store(_ key: AnthropicAPIKey) throws

    /// Returns the stored key, or `nil` if none is stored.
    func retrieve() throws -> AnthropicAPIKey?

    /// Removes any stored key. A no-op (not an error) if none is stored.
    func delete() throws
}
