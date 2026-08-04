import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// Exercises `AnthropicAPIKeyStoring` through the fake — this is the substitutability
/// the protocol exists for (see MAX-022). The real Keychain adapter is not covered
/// here; it is untestable in this repo's CI (see CLAUDE.md) and is exercised only by
/// this same set of calls, structurally, at review time.
final class AnthropicAPIKeyStoringTests: XCTestCase {
    private let fixtureValue = "unit-test-fixture-value"

    func testRetrieveReturnsNilWhenNothingStored() throws {
        let store = FakeAnthropicAPIKeyStore()
        XCTAssertNil(try store.retrieve())
    }

    func testStoreThenRetrieveRoundTrips() throws {
        let store = FakeAnthropicAPIKeyStore()
        let key = try AnthropicAPIKey(fixtureValue)

        try store.store(key)

        XCTAssertEqual(try store.retrieve(), key)
        XCTAssertEqual(store.storeCallCount, 1)
    }

    func testStoreReplacesAnExistingKey() throws {
        let original = try AnthropicAPIKey(fixtureValue)
        let store = FakeAnthropicAPIKeyStore(initialKey: original)
        let replacement = try AnthropicAPIKey("a-different-fixture-value")

        try store.store(replacement)

        XCTAssertEqual(try store.retrieve(), replacement)
    }

    func testDeleteRemovesTheStoredKey() throws {
        let key = try AnthropicAPIKey(fixtureValue)
        let store = FakeAnthropicAPIKeyStore(initialKey: key)

        try store.delete()

        XCTAssertNil(try store.retrieve())
        XCTAssertEqual(store.deleteCallCount, 1)
    }

    func testDeleteWhenNothingStoredIsANoOpNotAnError() throws {
        let store = FakeAnthropicAPIKeyStore()
        XCTAssertNoThrow(try store.delete())
    }

    func testConsumersDependOnlyOnTheProtocol() throws {
        // Mirrors how Settings (and later MAX-023/024) will be written: against
        // `AnthropicAPIKeyStoring`, never against a concrete store.
        func hasStoredKey(_ store: AnthropicAPIKeyStoring) throws -> Bool {
            try store.retrieve() != nil
        }

        let empty = FakeAnthropicAPIKeyStore()
        XCTAssertFalse(try hasStoredKey(empty))

        let seeded = FakeAnthropicAPIKeyStore(initialKey: try AnthropicAPIKey(fixtureValue))
        XCTAssertTrue(try hasStoredKey(seeded))
    }

    func testStoreSurfacesUnderlyingFailuresRatherThanSwallowingThem() throws {
        let store = FakeAnthropicAPIKeyStore()
        store.errorToThrow = .storeFailed("simulated Keychain failure")

        XCTAssertThrowsError(try store.store(try AnthropicAPIKey(fixtureValue))) { error in
            XCTAssertEqual(error as? AnthropicAPIKeyError, .storeFailed("simulated Keychain failure"))
        }
    }
}
