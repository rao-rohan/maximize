import XCTest
@testable import MaximizeCore

/// `ScoreBand` has no logic to test — that is the point of it. What these tests pin
/// down instead is its *contract*: the set of cases, and the raw values, which become
/// part of the persisted representation once scores are stored (D8 — the auto-score is
/// immutable, so its stored band must stay readable forever).
final class ScoreBandTests: XCTestCase {
    func testCasesAreExactlyTheThreeBands() {
        XCTAssertEqual(ScoreBand.allCases, [.effective, .marginal, .ineffective])
    }

    /// Raw values are a storage format, not a display string. Changing one silently
    /// re-labels every historical score, so a change here should have to break a test.
    func testRawValuesAreStable() {
        XCTAssertEqual(ScoreBand.effective.rawValue, "effective")
        XCTAssertEqual(ScoreBand.marginal.rawValue, "marginal")
        XCTAssertEqual(ScoreBand.ineffective.rawValue, "ineffective")
    }

    func testRoundTripsThroughCoding() throws {
        for band in ScoreBand.allCases {
            let data = try JSONEncoder().encode(band)
            let decoded = try JSONDecoder().decode(ScoreBand.self, from: data)
            XCTAssertEqual(decoded, band)
        }
    }
}
