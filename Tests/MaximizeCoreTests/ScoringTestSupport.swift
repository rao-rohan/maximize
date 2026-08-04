import Foundation
import XCTest
@testable import MaximizeCore

/// The kind of a `ScoringError`, without its payload — so a test asserts on *why* a
/// score was refused rather than on a message that will be reworded.
enum ScoringErrorKind: String {
    case noPlanInEffect
    case contextAlreadyScored
    case noBandMatched
    case malformedResponse
    case scoreOutOfPermittedRange
    case scoreOutsideBand
    case rationaleRejected
}

extension ScoringError {
    var kind: ScoringErrorKind {
        switch self {
        case .noPlanInEffect: return .noPlanInEffect
        case .contextAlreadyScored: return .contextAlreadyScored
        case .noBandMatched: return .noBandMatched
        case .malformedResponse: return .malformedResponse
        case .scoreOutOfPermittedRange: return .scoreOutOfPermittedRange
        case .scoreOutsideBand: return .scoreOutsideBand
        case .rationaleRejected: return .rationaleRejected
        }
    }
}

func assertThrowsScoring<T>(
    _ expected: ScoringErrorKind,
    _ expression: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
        guard let scoringError = error as? ScoringError else {
            XCTFail("Expected ScoringError.\(expected.rawValue), got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(
            scoringError.kind,
            expected,
            "Expected ScoringError.\(expected.rawValue), got \(scoringError)",
            file: file,
            line: line
        )
    }
}

/// Plans, rubrics and contexts for the scoring suite.
///
/// The rubric here is PRD §10.3's worked example written out **in full**, as plan data.
/// `Fixture.rubric()` deliberately stays as MAX-010 left it and is used only where a
/// test is about an incomplete rubric.
enum ScoringFixture {
    static let scoredAt = Date(timeIntervalSince1970: 1_767_312_000)

    // Days under `Fixture.weeklyTemplate()`: Monday rest, Tuesday easy 8 km,
    // Wednesday hard (6 × 800m, no distance), Sunday long.
    static let easyDay = "2026-01-06"
    static let hardDay = "2026-01-07"
    static let longDay = "2026-01-11"
    static let beforeAnyPlan = "2025-12-30"

    /// §10.3, complete: every row of the worked example, including the "avg ≥ 159" half
    /// of its final disjunction that `Fixture.rubric()` omits.
    ///
    /// Thresholds appear here because this is plan *data* authored by a test. The point
    /// of D1 is that no number below ever appears in `Sources/`.
    static func workedExampleRubric(
        effectiveThreshold: Int = 70,
        marginalThreshold: Int = 45
    ) throws -> ScoringRubric {
        try ScoringRubric(
            effectiveThreshold: ScoreValue(effectiveThreshold),
            marginalThreshold: ScoreValue(marginalThreshold),
            bands: [
                // Ordered first so a run that was hard when easy was asked for is judged
                // on what it was, not on where its heart rate landed.
                RubricBand(
                    identifier: "easy.ranHardInstead",
                    appliesTo: [.easy],
                    conditions: [.actualClassification(oneOf: [.hard])],
                    scoreRange: ScoreRange(lowest: 20, highest: 45),
                    rationale: "Ran hard on an easy day."
                ),
                RubricBand(
                    identifier: "easy.onCap.lowDrift",
                    appliesTo: [.easy],
                    conditions: [
                        .actualClassification(oneOf: [.easy]),
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 0)
                        ),
                        .metric(
                            metric: .heartRateDriftFraction,
                            comparison: .lessThan,
                            reference: .constant(0.05)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 90, highest: 100),
                    rationale: "Held the cap with minimal drift."
                ),
                RubricBand(
                    identifier: "easy.onCap.lateDrift",
                    appliesTo: [.easy],
                    conditions: [
                        .actualClassification(oneOf: [.easy]),
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 0)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 75, highest: 89),
                    rationale: "Under cap, but drifted late."
                ),
                RubricBand(
                    identifier: "easy.slightlyOverCap",
                    appliesTo: [.easy],
                    conditions: [
                        .actualClassification(oneOf: [.easy]),
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 8)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 55, highest: 74),
                    rationale: "Ran above the easy cap."
                ),
                RubricBand(
                    identifier: "easy.wellOverCap",
                    appliesTo: [.easy],
                    conditions: [
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .greaterThan,
                            reference: .heartRateCap(offsetBPM: 8)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 20, highest: 45),
                    rationale: "Well above the easy cap for the whole run."
                ),
                RubricBand(
                    identifier: "long.completedTheDistance",
                    appliesTo: [.long],
                    conditions: [
                        .metric(
                            metric: .distanceMeters,
                            comparison: .greaterThanOrEqual,
                            reference: .scheduledDistance(fraction: 0.8)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 75, highest: 100),
                    rationale: "Covered the prescribed long-run distance."
                ),
                RubricBand(
                    identifier: "hard.executed",
                    appliesTo: [.hard],
                    conditions: [
                        .metric(
                            metric: .distanceMeters,
                            comparison: .greaterThanOrEqual,
                            reference: .scheduledDistance(fraction: 0.8)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 75, highest: 100),
                    rationale: "Executed the prescribed session."
                ),
                RubricBand(
                    identifier: "skipped",
                    conditions: [.noWorkoutRecorded],
                    scoreRange: ScoreRange(lowest: 0, highest: 15),
                    rationale: "No workout recorded for a scheduled session."
                ),
            ]
        )
    }

    static func plan(rubric: ScoringRubric? = nil, heartRateCapBPM: Double = 150) throws -> Plan {
        let resolvedRubric: ScoringRubric
        if let rubric {
            resolvedRubric = rubric
        } else {
            resolvedRubric = try workedExampleRubric()
        }
        return try Plan(
            version: PlanVersion(1),
            effectiveFrom: CalendarDay(iso8601: "2026-01-01"),
            weeklyTemplate: Fixture.weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: heartRateCapBPM,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: resolvedRubric,
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    static func metrics(
        averageHeartRateBPM: Double? = 142,
        maximumHeartRateBPM: Double? = 158,
        heartRateDriftFraction: Double? = 0.03,
        timeAboveCapSeconds: Double? = 0,
        averageCadenceStepsPerMinute: Double? = 167
    ) throws -> DerivedMetrics {
        // A maximum below the average is rejected by `DerivedMetrics`; lift it rather
        // than make every caller restate it when they only care about the average.
        var maximum = maximumHeartRateBPM
        if let average = averageHeartRateBPM, let ceiling = maximumHeartRateBPM, ceiling < average {
            maximum = average
        }
        return try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximum,
            timeAboveCapSeconds: averageHeartRateBPM == nil ? nil : timeAboveCapSeconds,
            heartRateDriftFraction: heartRateDriftFraction,
            averageCadenceStepsPerMinute: averageCadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 3_400)]),
            planVersion: PlanVersion(1)
        )
    }

    /// A context assembled through the real builder (D3), so these tests exercise the
    /// same assembly the app will.
    static func context(
        on day: String = easyDay,
        classification: WorkoutClassification = .easy,
        metrics overrideMetrics: DerivedMetrics? = nil,
        distanceMeters: Double? = 10_000,
        rubric: ScoringRubric? = nil,
        existingScore: Score? = nil
    ) throws -> WorkoutContext {
        try WorkoutContextBuilder.build(
            workout: Fixture.workout(distanceMeters: distanceMeters),
            on: CalendarDay(iso8601: day),
            metrics: overrideMetrics ?? metrics(),
            classification: classification,
            planCalendar: PlanCalendar([plan(rubric: rubric)]),
            existingScore: existingScore
        )
    }
}
