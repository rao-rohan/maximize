import Foundation
import XCTest
@testable import MaximizeCore

final class ScoreTests: XCTestCase {
    /// §10.4: effective at or above the threshold. The boundary is the interesting
    /// case because it decides a calendar colour (D4).
    func testEffectivenessIsDecidedAtTheThreshold() throws {
        XCTAssertFalse(try Fixture.score(points: 69, threshold: 70).isEffective)
        XCTAssertTrue(try Fixture.score(points: 70, threshold: 70).isEffective)
        XCTAssertTrue(try Fixture.score(points: 71, threshold: 70).isEffective)
    }

    /// The threshold travels with the score, so re-reading an old score under a newer
    /// plan cannot silently reclassify it.
    func testEffectivenessUsesTheThresholdThatWasInForce() throws {
        let lenient = try Fixture.score(points: 65, threshold: 60)
        let strict = try Fixture.score(points: 65, threshold: 80)
        XCTAssertTrue(lenient.isEffective)
        XCTAssertFalse(strict.isEffective)
    }

    func testRationaleMustBeOneNonEmptyLine() throws {
        assertThrows(
            .empty,
            try Score(
                workoutID: Fixture.workoutID,
                planVersion: PlanVersion(1),
                scheduledSession: .rest,
                actualClassification: .easy,
                value: ScoreValue(80),
                effectiveThreshold: ScoreValue(70),
                band: .effective,
                rationale: "   ",
                scoredAt: Fixture.epoch
            )
        )
        assertThrows(
            .inconsistent,
            try Score(
                workoutID: Fixture.workoutID,
                planVersion: PlanVersion(1),
                scheduledSession: .rest,
                actualClassification: .easy,
                value: ScoreValue(80),
                effectiveThreshold: ScoreValue(70),
                band: .effective,
                rationale: "Held the cap.\nDrifted late.",
                scoredAt: Fixture.epoch
            )
        )
    }

    /// The band is stored, not computed — `ScoreBand` has no `init(score:)` and this
    /// type does not add one. What it will not accept is a band that contradicts the
    /// threshold it was scored against.
    func testStoredBandCannotContradictTheThreshold() throws {
        assertThrows(
            .inconsistent,
            try Score(
                workoutID: Fixture.workoutID,
                planVersion: PlanVersion(1),
                scheduledSession: .rest,
                actualClassification: .easy,
                value: ScoreValue(40),
                effectiveThreshold: ScoreValue(70),
                band: .effective,
                rationale: "Claims effective at 40 against a threshold of 70.",
                scoredAt: Fixture.epoch
            )
        )
        assertThrows(
            .inconsistent,
            try Score(
                workoutID: Fixture.workoutID,
                planVersion: PlanVersion(1),
                scheduledSession: .rest,
                actualClassification: .easy,
                value: ScoreValue(90),
                effectiveThreshold: ScoreValue(70),
                band: .marginal,
                rationale: "Claims marginal at 90 against a threshold of 70.",
                scoredAt: Fixture.epoch
            )
        )
    }

    /// Both sub-threshold bands are accepted: the marginal/ineffective split is the
    /// scorer's call against the rubric's marginalThreshold, not this type's.
    func testEitherSubThresholdBandIsAccepted() throws {
        XCTAssertEqual(try Fixture.score(points: 55, threshold: 70, marginal: 45).band, .marginal)
        XCTAssertEqual(try Fixture.score(points: 20, threshold: 70, marginal: 45).band, .ineffective)
        XCTAssertEqual(try Fixture.score(points: 88, threshold: 70).band, .effective)
    }

    func testRoundTripsThroughJSON() throws {
        let score = try Fixture.score(points: 88)
        XCTAssertEqual(try roundTripped(score), score)
    }
}

final class ScoreLedgerTests: XCTestCase {
    /// D8, stated as a test: annotating never touches the auto-score.
    func testAnnotatingLeavesTheAutomaticScoreIntact() throws {
        let automatic = try Fixture.score(points: 45)
        let ledger = try ScoreLedger(automatic: automatic)
        let corrected = try ledger.annotated(with: Fixture.annotation(points: 80, at: 60))

        XCTAssertEqual(corrected.automatic, automatic)
        XCTAssertEqual(corrected.automatic.value.points, 45)
        XCTAssertEqual(ledger.annotations.count, 0, "The original ledger is a value and is unchanged")
        XCTAssertEqual(corrected.annotations.count, 1)
    }

    func testTalliesUseTheCorrectionWhereOneExists() throws {
        let ledger = try ScoreLedger(automatic: Fixture.score(points: 45, threshold: 70))
        XCTAssertEqual(ledger.effectiveValue.points, 45)
        XCTAssertFalse(ledger.isEffective)
        XCTAssertFalse(ledger.wasCorrected)
        XCTAssertNil(ledger.divergence)

        let corrected = try ledger.annotated(with: Fixture.annotation(points: 80, at: 60))
        XCTAssertEqual(corrected.effectiveValue.points, 80)
        XCTAssertTrue(corrected.isEffective)
        XCTAssertTrue(corrected.wasCorrected)
    }

    /// The gap between auto and manual is the scorer-quality metric in PRD §2; it
    /// only exists because both numbers are still on the record.
    func testDivergenceIsSignedAndMeasuredAgainstTheAutoScore() throws {
        let harsh = try ScoreLedger(automatic: Fixture.score(points: 45))
            .annotated(with: Fixture.annotation(points: 80, at: 60))
        XCTAssertEqual(harsh.divergence, 35)

        let generous = try ScoreLedger(automatic: Fixture.score(points: 95))
            .annotated(with: Fixture.annotation(points: 60, at: 60))
        XCTAssertEqual(generous.divergence, -35)
    }

    func testTheLatestCorrectionWins() throws {
        let ledger = try ScoreLedger(automatic: Fixture.score(points: 45))
            .annotated(with: Fixture.annotation(points: 80, at: 60))
            .annotated(with: Fixture.annotation(points: 55, at: 120))
        XCTAssertEqual(ledger.annotations.count, 2, "Corrections accumulate; they do not replace")
        XCTAssertEqual(ledger.effectiveValue.points, 55)
        XCTAssertEqual(ledger.divergence, 10)
    }

    func testRejectsAnnotationsThatGoBackwardsInTime() throws {
        let ledger = try ScoreLedger(automatic: Fixture.score(points: 45))
            .annotated(with: Fixture.annotation(points: 80, at: 120))
        assertThrows(.outOfOrder, try ledger.annotated(with: Fixture.annotation(points: 55, at: 60)))
    }

    func testRejectsAnAnnotationForADifferentWorkout() throws {
        let ledger = try ScoreLedger(automatic: Fixture.score(points: 45))
        assertThrows(
            .inconsistent,
            try ledger.annotated(with: Fixture.annotation(points: 80, workoutID: Fixture.otherWorkoutID))
        )
    }

    func testAnnotationNoteMustSaySomethingIfPresent() {
        assertThrows(
            .empty,
            try ScoreAnnotation(
                id: UUID(),
                workoutID: Fixture.workoutID,
                manualScore: ScoreValue(80),
                note: "",
                createdAt: Fixture.epoch
            )
        )
    }

    func testRoundTripsThroughJSON() throws {
        let ledger = try ScoreLedger(automatic: Fixture.score(points: 45))
            .annotated(with: Fixture.annotation(points: 80, at: 60))
        XCTAssertEqual(try roundTripped(ledger), ledger)
    }
}
