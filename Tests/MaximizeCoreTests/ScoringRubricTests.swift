import Foundation
import XCTest
@testable import MaximizeCore

final class ScoringRubricTests: XCTestCase {
    func testRejectsAnEmptyRubric() throws {
        assertThrows(.empty, try ScoringRubric(effectiveThreshold: ScoreValue(70), bands: []))
    }

    func testRejectsDuplicateBandIdentifiers() throws {
        let band = try RubricBand(
            identifier: "easy.onCap",
            scoreRange: ScoreRange(lowest: 90, highest: 100),
            rationale: "Held the cap."
        )
        assertThrows(
            .duplicate,
            try ScoringRubric(effectiveThreshold: ScoreValue(70), bands: [band, band])
        )
    }

    func testBandsNeedAnIdentifierAndARationale() throws {
        assertThrows(
            .empty,
            try RubricBand(
                identifier: " ",
                scoreRange: ScoreRange(lowest: 0, highest: 10),
                rationale: "Skipped."
            )
        )
        assertThrows(
            .empty,
            try RubricBand(
                identifier: "skipped",
                scoreRange: ScoreRange(lowest: 0, highest: 10),
                rationale: ""
            )
        )
    }

    func testBandsFilterByScheduledSessionKind() throws {
        let rubric = try Fixture.rubric()
        let easyBands = rubric.bands(for: .easy)

        XCTAssertEqual(
            easyBands.map(\.identifier),
            ["easy.onCap.lowDrift", "easy.onCap.lateDrift", "easy.slightlyOverCap", "easy.ranHardInstead", "skipped"],
            "Rubric order is part of the rubric's meaning: first match wins"
        )
        // The catch-all band has no `appliesTo`, so it survives every filter.
        XCTAssertEqual(rubric.bands(for: .long).map(\.identifier), ["skipped"])
    }

    func testBandLookupByIdentifier() throws {
        let rubric = try Fixture.rubric()
        XCTAssertEqual(rubric.band(identifiedBy: "easy.slightlyOverCap")?.scoreRange.lowest.points, 55)
        XCTAssertNil(rubric.band(identifiedBy: "nope"))
    }

    /// D1 in one assertion: the whole rubric — thresholds, bands, the effective cut —
    /// survives a serialization round trip, because it is data a scorer reads and not
    /// a `switch` a scorer is.
    func testTheEntireRubricIsSerializableData() throws {
        let rubric = try Fixture.rubric()
        XCTAssertEqual(try roundTripped(rubric), rubric)
    }

    /// The thresholds a rubric compares against are expressed relative to the plan,
    /// so raising the HR cap in a new plan version moves every band with it — no
    /// rubric rewrite, no code change.
    func testMetricThresholdsAreResolvedThroughThePlan() throws {
        let rubric = try Fixture.rubric()
        let band = try XCTUnwrap(rubric.band(identifiedBy: "easy.slightlyOverCap"))
        let condition = try XCTUnwrap(band.conditions.first)

        guard case let .metric(metric, comparison, reference) = condition else {
            return XCTFail("Expected a metric condition, got \(condition)")
        }
        XCTAssertEqual(metric, .averageHeartRateBPM)
        XCTAssertEqual(comparison, .lessThanOrEqual)

        let capped150 = try Fixture.plan(version: 1, heartRateCapBPM: 150)
        let capped145 = try Fixture.plan(version: 2, heartRateCapBPM: 145)
        XCTAssertEqual(capped150.resolve(reference), 158)
        XCTAssertEqual(capped145.resolve(reference), 153)
    }

    func testComparisonsEvaluateAsNamed() {
        XCTAssertTrue(RubricComparison.lessThan.evaluate(1, 2))
        XCTAssertFalse(RubricComparison.lessThan.evaluate(2, 2))
        XCTAssertTrue(RubricComparison.lessThanOrEqual.evaluate(2, 2))
        XCTAssertTrue(RubricComparison.greaterThan.evaluate(3, 2))
        XCTAssertFalse(RubricComparison.greaterThanOrEqual.evaluate(1, 2))
    }

    func testEffectiveThresholdIsPartOfTheVersionedRubric() throws {
        let strict = try Fixture.rubric(effectiveThreshold: 85)
        XCTAssertEqual(strict.effectiveThreshold.points, 85)
        XCTAssertEqual(try Fixture.rubric().effectiveThreshold, ScoreValue.defaultEffectiveThreshold)
    }
}
