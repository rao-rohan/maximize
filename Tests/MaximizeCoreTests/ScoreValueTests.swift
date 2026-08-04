import Foundation
import XCTest
@testable import MaximizeCore

final class ScoreValueTests: XCTestCase {
    func testAcceptsTheWholePermittedRange() throws {
        XCTAssertEqual(try ScoreValue(0).points, 0)
        XCTAssertEqual(try ScoreValue(100).points, 100)
        XCTAssertEqual(try ScoreValue(70), ScoreValue.defaultEffectiveThreshold)
    }

    func testRejectsScoresOutsideZeroToOneHundred() {
        assertThrows(.outOfRange, try ScoreValue(101))
        assertThrows(.outOfRange, try ScoreValue(-1))
        assertThrows(.outOfRange, try ScoreValue(Int.max))
    }

    func testClampingSaturatesInsteadOfFailing() {
        XCTAssertEqual(ScoreValue.clamping(103), ScoreValue.maximum)
        XCTAssertEqual(ScoreValue.clamping(-8), ScoreValue.zero)
        XCTAssertEqual(ScoreValue.clamping(64).points, 64)
    }

    func testDecodingRejectsAnOutOfRangeScore() throws {
        struct Box: Decodable {
            let wrapped: ScoreValue
        }
        let data = try XCTUnwrap(#"{"wrapped":101}"#.data(using: .utf8))
        assertThrows(.outOfRange, try JSONDecoder().decode(Box.self, from: data))
    }

    func testScoreRangeMustNotBeInverted() {
        assertThrows(.inconsistent, try ScoreRange(lowest: 100, highest: 90))
    }

    func testScoreRangeMembershipAndMidpoint() throws {
        let band = try ScoreRange(lowest: 90, highest: 100)
        XCTAssertTrue(band.contains(try ScoreValue(90)))
        XCTAssertTrue(band.contains(try ScoreValue(100)))
        XCTAssertFalse(band.contains(try ScoreValue(89)))
        XCTAssertEqual(band.midpoint.points, 95)
    }
}
