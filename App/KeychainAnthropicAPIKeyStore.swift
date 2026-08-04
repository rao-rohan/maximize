import Foundation
import Security
import MaximizeCore

/// Keychain-backed `AnthropicAPIKeyStoring`.
///
/// This is the thin, decision-free adapter described in CLAUDE.md — every decision
/// (validation, redaction, what happens when a key is/isn't present) lives in
/// `MaximizeCore` and is unit tested there against `FakeAnthropicAPIKeyStore`. This
/// file only translates protocol calls into `Security` framework calls and maps
/// `OSStatus` results into `AnthropicAPIKeyError`.
///
/// **Not exercised by CI.** This repo has no Swift toolchain locally, no simulator,
/// and no device; `swift test` runs `MaximizeCore`'s test target only, and the
/// `ios-app` CI job *builds* the app target but does not run it. Nothing in this
/// file has ever executed. It is reviewed, not verified — see the PR description's
/// "what CI does and doesn't prove" section.
struct KeychainAnthropicAPIKeyStore: AnthropicAPIKeyStoring {
    /// Keychain item identifiers. Deliberately not derived from the app's bundle ID
    /// (still a placeholder — see `project.yml`) so this doesn't silently change
    /// when the real bundle ID lands.
    private static let service = "com.maximize.anthropic-api-key"
    private static let account = "anthropic-api-key"

    func store(_ key: AnthropicAPIKey) throws {
        let data = Data(key.revealed().utf8)

        // Try updating an existing item first. `SecItemAdd` fails with
        // `errSecDuplicateItem` if one is already there, so "add, and update on
        // duplicate" would need the same two calls in the other order; updating
        // first also means the accessibility attribute set at creation (below) is
        // left untouched on a normal replace.
        let updateStatus = SecItemUpdate(
            query() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AnthropicAPIKeyError.storeFailed(Self.describe(updateStatus))
        }

        var addQuery = query()
        addQuery[kSecValueData as String] = data
        // kSecAttrAccessibleWhenUnlockedThisDeviceOnly, chosen deliberately:
        //   - "ThisDeviceOnly" excludes the item from iCloud Keychain sync and from
        //     device-to-device restore. Required by A5/CLAUDE.md: this key is a
        //     bounded, single-device accepted risk, not something that should
        //     reappear on a second device the app was never distributed to.
        //   - "WhenUnlocked" (over "Always") means the item is unreadable while the
        //     device is locked, including to a background process — the tightest
        //     class that still lets this single-user, foreground-only app read the
        //     key when the user is actually in Settings or a Claude call is made.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // Belt-and-suspenders: "ThisDeviceOnly" accessibility already excludes this
        // item from iCloud Keychain sync, but setting kSecAttrSynchronizable = false
        // explicitly makes the "must not sync" requirement (A5, CLAUDE.md) legible
        // at this call site rather than implicit in the accessibility constant.
        addQuery[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AnthropicAPIKeyError.storeFailed(Self.describe(addStatus))
        }
    }

    func retrieve() throws -> AnthropicAPIKey? {
        var lookupQuery = query()
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let raw = String(data: data, encoding: .utf8) else {
                throw AnthropicAPIKeyError.retrieveFailed("stored Keychain item was not UTF-8 text")
            }
            // Propagate rather than `try?`: if this ever fails, the stored item is
            // corrupt (empty/whitespace), which is worth surfacing, not swallowing.
            return try AnthropicAPIKey(raw)
        case errSecItemNotFound:
            return nil
        default:
            throw AnthropicAPIKeyError.retrieveFailed(Self.describe(status))
        }
    }

    func delete() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AnthropicAPIKeyError.deleteFailed(Self.describe(status))
        }
    }

    /// Search predicate shared by all three operations (add/update supply
    /// additional attributes on top of this — see `store`).
    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    /// Maps an `OSStatus` to a safe, static description for `AnthropicAPIKeyError`.
    /// `SecCopyErrorMessageString` returns a system-supplied string describing the
    /// status code — it cannot contain key material, since it never has access to
    /// the key in the first place.
    private static func describe(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }
}
