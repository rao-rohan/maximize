import XCTest
@testable import MaximizeCore

/// Covers the decisions that live in `AnthropicAPIKey` itself: validation and
/// redaction. Neither fixture below resembles a real credential — see CLAUDE.md's
/// "no secrets in the repo" rule.
final class AnthropicAPIKeyTests: XCTestCase {
    private let fixtureValue = "unit-test-fixture-value"

    func testInitRejectsEmptyString() {
        XCTAssertThrowsError(try AnthropicAPIKey("")) { error in
            XCTAssertEqual(error as? AnthropicAPIKeyError, .emptyKey)
        }
    }

    func testInitRejectsWhitespaceOnlyString() {
        XCTAssertThrowsError(try AnthropicAPIKey("   \n\t  ")) { error in
            XCTAssertEqual(error as? AnthropicAPIKeyError, .emptyKey)
        }
    }

    func testInitTrimsSurroundingWhitespace() throws {
        let key = try AnthropicAPIKey("  \(fixtureValue)  \n")
        XCTAssertEqual(key.revealed(), fixtureValue)
    }

    func testRevealedReturnsExactValue() throws {
        let key = try AnthropicAPIKey(fixtureValue)
        XCTAssertEqual(key.revealed(), fixtureValue)
    }

    func testDescriptionNeverContainsTheRawValue() throws {
        let key = try AnthropicAPIKey(fixtureValue)
        XCTAssertEqual(key.description, "AnthropicAPIKey(<redacted>)")
        XCTAssertFalse(key.description.contains(fixtureValue))
    }

    func testDebugDescriptionNeverContainsTheRawValue() throws {
        let key = try AnthropicAPIKey(fixtureValue)
        XCTAssertEqual(key.debugDescription, "AnthropicAPIKey(<redacted>)")
        XCTAssertFalse(key.debugDescription.contains(fixtureValue))
    }

    func testStringInterpolationNeverContainsTheRawValue() throws {
        let key = try AnthropicAPIKey(fixtureValue)
        // This is the exact failure mode CLAUDE.md warns about: a stray
        // `print("\(key)")` or log line. Assert the interpolated form is redacted,
        // not just the `.description` accessor in isolation.
        let interpolated = "\(key)"
        XCTAssertFalse(interpolated.contains(fixtureValue))
    }

    func testEqualityComparesUnderlyingValue() throws {
        let a = try AnthropicAPIKey(fixtureValue)
        let b = try AnthropicAPIKey(fixtureValue)
        let c = try AnthropicAPIKey("a-different-fixture-value")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
