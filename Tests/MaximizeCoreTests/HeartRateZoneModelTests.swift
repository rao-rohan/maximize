import XCTest
@testable import MaximizeCore

final class HeartRateZoneModelTests: XCTestCase {
    // MARK: - Cap-anchored boundaries

    /// Hand-computed from the documented multipliers [0.90, 1.00, 1.08, 1.16]:
    /// 0.90 × 150 = 135, 1.00 × 150 = 150, 1.08 × 150 = 162, 1.16 × 150 = 174.
    func testCapAnchoredBoundsAreMultiplesOfTheCap() throws {
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)

        XCTAssertEqual(model.upperBoundsBPM.count, 4)
        XCTAssertEqual(model.upperBoundsBPM[0], 135, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[1], 150, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[2], 162, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[3], 174, accuracy: 1e-9)
    }

    /// D1: the boundaries move with the plan's cap. 0.90 × 160 = 144, 1.08 × 160 = 172.8,
    /// 1.16 × 160 = 185.6. If a zone edge were ever written as a literal, this is the
    /// test that would fail.
    func testBoundsFollowADifferentPlansCap() throws {
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 160)

        XCTAssertEqual(model.upperBoundsBPM[0], 144, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[1], 160, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[2], 172.8, accuracy: 1e-9)
        XCTAssertEqual(model.upperBoundsBPM[3], 185.6, accuracy: 1e-9)
    }

    // MARK: - Zone lookup

    func testZoneLookupTreatsUpperBoundsAsInclusive() throws {
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)

        XCTAssertEqual(model.zone(for: 90), .one)
        XCTAssertEqual(model.zone(for: 135), .one)
        XCTAssertEqual(model.zone(for: 135.001), .two)
        // The cap itself is still easy running: time-above-cap counts only HR strictly
        // above the cap, and the zone split must not disagree with it.
        XCTAssertEqual(model.zone(for: 150), .two)
        XCTAssertEqual(model.zone(for: 150.001), .three)
        XCTAssertEqual(model.zone(for: 162), .three)
        XCTAssertEqual(model.zone(for: 162.001), .four)
        XCTAssertEqual(model.zone(for: 174), .four)
        XCTAssertEqual(model.zone(for: 174.001), .five)
        XCTAssertEqual(model.zone(for: 210), .five)
    }

    // MARK: - Validation

    func testRejectsTheWrongNumberOfBounds() {
        assertThrows(.inconsistent, try HeartRateZoneModel(upperBoundsBPM: [135, 150, 162]))
        assertThrows(.inconsistent, try HeartRateZoneModel(upperBoundsBPM: [135, 150, 162, 174, 186]))
    }

    func testRejectsBoundsThatDoNotAscend() {
        assertThrows(.outOfOrder, try HeartRateZoneModel(upperBoundsBPM: [135, 162, 150, 174]))
        assertThrows(.outOfOrder, try HeartRateZoneModel(upperBoundsBPM: [135, 135, 162, 174]))
    }

    func testRejectsNonPositiveBounds() {
        assertThrows(.outOfRange, try HeartRateZoneModel(upperBoundsBPM: [0, 150, 162, 174]))
        assertThrows(.outOfRange, try HeartRateZoneModel(upperBoundsBPM: [-1, 150, 162, 174]))
    }

    func testRoundTripsThroughCoding() throws {
        let model = try HeartRateZoneModel.capAnchored(heartRateCapBPM: 150)
        XCTAssertEqual(try roundTripped(model), model)
    }
}
