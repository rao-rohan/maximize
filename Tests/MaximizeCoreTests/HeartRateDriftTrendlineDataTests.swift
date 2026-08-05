import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-065: the drift trendline — `DerivedMetrics.heartRateDriftFraction` plotted
/// against run date, over exactly the runs `HeartRateDriftOverlayData` stacks.
///
/// Two things matter most here, and each gets its own section: that the runs behind
/// this chart never diverge from the runs behind the overlay above it (`MARK: - Same
/// runs as the overlay`), and that the fit is ordinary least squares against *date*,
/// hand-computed rather than read off the implementation (`MARK: - The fit`).
final class HeartRateDriftTrendlineDataTests: XCTestCase {

    // MARK: - Fixtures

    private func curve(
        daysAfterEpoch: Double,
        driftFraction: Double?,
        id: UUID = UUID()
    ) -> NormalizedHeartRateCurve {
        NormalizedHeartRateCurve(
            workoutID: id,
            start: Fixture.epoch.addingTimeInterval(daysAfterEpoch * 86_400),
            classification: .easy,
            points: [NormalizedHeartRateCurve.Point(percentElapsed: 50, beatsPerMinute: 140)],
            coveredSeconds: 1_800,
            driftFraction: driftFraction,
            recencyRank: 0
        )
    }

    // MARK: - Same runs as the overlay

    /// The guarantee the ticket is about: this type never re-derives the overlay's
    /// eligibility rules, because it never sees the candidates those rules run over —
    /// only `HeartRateDriftOverlayData.curves`, the overlay's own finished output. A
    /// hard session, an unscored run, and a too-short curve all fail the overlay's
    /// filter for reasons this type never has to know about, and none of them appear
    /// here either, simply because none of them reached `curves`.
    func testOnlyRunsTheOverlayActuallyStacksAppearInTheTrendline() throws {
        let stacked = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, driftFraction: 0.03)
        let hard = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, classification: .hard)
        let unscored = try makeCandidate(daysBeforeEpoch: 3, classification: nil)
        let tooShort = try makeCandidate(daysBeforeEpoch: 4, samples: [(0, 130), (400, 150)])

        let overlay = HeartRateDriftOverlayData(candidates: [stacked, hard, unscored, tooShort])
        XCTAssertEqual(overlay.curves.count, 1)

        let trendline = HeartRateDriftTrendlineData(curves: overlay.curves)

        XCTAssertEqual(trendline.points.map(\.workoutID), [Fixture.workoutID])
    }

    /// A run beyond the overlay's stack limit is not drawn as a curve, and MAX-065
    /// requires the trendline to cover the same runs the overlay draws — not every run
    /// that qualified. Consuming `curves` (post-limit) rather than the qualifying set
    /// (pre-limit) is what keeps that true.
    func testARunBeyondTheStackLimitIsAbsentFromTheTrendlineToo() throws {
        let candidates = try (0..<4).map { index in
            try makeCandidate(daysBeforeEpoch: Double(index), driftFraction: 0.01 * Double(index))
        }
        let overlay = HeartRateDriftOverlayData(candidates: candidates, stackLimit: 2)
        XCTAssertEqual(overlay.count(of: .beyondStackLimit), 2)

        let trendline = HeartRateDriftTrendlineData(curves: overlay.curves)

        XCTAssertEqual(trendline.points.count, 2)
        XCTAssertEqual(Set(trendline.points.map(\.workoutID)), Set(overlay.curves.map(\.workoutID)))
    }

    /// A stacked run with no stored drift figure draws a curve but contributes no point
    /// here — absent, never plotted as a zero.
    func testAStackedCurveWithNoStoredDriftContributesNoPoint() throws {
        let withDrift = try makeCandidate(id: Fixture.workoutID, daysBeforeEpoch: 1, driftFraction: 0.02)
        let withoutDrift = try makeCandidate(id: Fixture.otherWorkoutID, daysBeforeEpoch: 2, driftFraction: nil)

        let overlay = HeartRateDriftOverlayData(candidates: [withDrift, withoutDrift])
        XCTAssertEqual(overlay.curves.count, 2)

        let trendline = HeartRateDriftTrendlineData(curves: overlay.curves)

        XCTAssertEqual(trendline.points.map(\.workoutID), [Fixture.workoutID])
    }

    // MARK: - Points

    func testPointsAreOrderedByDateRegardlessOfCurveOrder() {
        let newest = curve(daysAfterEpoch: 5, driftFraction: 0.03, id: Fixture.workoutID)
        let oldest = curve(daysAfterEpoch: 0, driftFraction: 0.01, id: Fixture.otherWorkoutID)

        let trendline = HeartRateDriftTrendlineData(curves: [newest, oldest])

        XCTAssertEqual(trendline.points.map(\.workoutID), [Fixture.otherWorkoutID, Fixture.workoutID])
    }

    func testAnEmptyCurveListProducesNoPointsAndNoFit() {
        let trendline = HeartRateDriftTrendlineData(curves: [])

        XCTAssertTrue(trendline.points.isEmpty)
        XCTAssertNil(trendline.fit)
        XCTAssertNil(trendline.driftFractionAxisDomain)
    }

    // MARK: - Fewer than two points is not a trendline

    func testOneQualifyingRunProducesAPointButNoFit() {
        let trendline = HeartRateDriftTrendlineData(curves: [curve(daysAfterEpoch: 0, driftFraction: 0.05)])

        XCTAssertEqual(trendline.points.count, 1)
        XCTAssertNil(trendline.fit)
    }

    func testZeroQualifyingRunsAmongSeveralCurvesProducesNoFit() {
        let curves = [
            curve(daysAfterEpoch: 0, driftFraction: nil),
            curve(daysAfterEpoch: 1, driftFraction: nil),
        ]
        let trendline = HeartRateDriftTrendlineData(curves: curves)

        XCTAssertTrue(trendline.points.isEmpty)
        XCTAssertNil(trendline.fit)
    }

    /// Two runs recorded the same instant (e.g. two sessions logged on one calendar
    /// day with identical `start`s) leave no spread on the x-axis. A slope divided by
    /// zero would be a crash or a NaN silently drawn as a line; this is neither.
    func testPointsSharingOneExactDateProduceNoFit() {
        let curves = [
            curve(daysAfterEpoch: 3, driftFraction: 0.01, id: Fixture.workoutID),
            curve(daysAfterEpoch: 3, driftFraction: 0.09, id: Fixture.otherWorkoutID),
        ]
        let trendline = HeartRateDriftTrendlineData(curves: curves)

        XCTAssertEqual(trendline.points.count, 2)
        XCTAssertNil(trendline.fit)
    }

    // MARK: - The fit: least squares against date, hand-computed

    /// With exactly two points the least-squares line passes through both exactly —
    /// the simplest possible check that `value(at:)` reproduces the data it was fit to.
    func testTwoPointsFitALineThatPassesThroughBothExactly() throws {
        let firstDate = Fixture.epoch
        let secondDate = Fixture.epoch.addingTimeInterval(4 * 86_400)
        let curves = [
            curve(daysAfterEpoch: 0, driftFraction: -0.02, id: Fixture.workoutID),
            curve(daysAfterEpoch: 4, driftFraction: 0.06, id: Fixture.otherWorkoutID),
        ]
        let trendline = HeartRateDriftTrendlineData(curves: curves)
        let fit = try XCTUnwrap(trendline.fit)

        XCTAssertEqual(fit.value(at: firstDate), -0.02, accuracy: 1e-9)
        XCTAssertEqual(fit.value(at: secondDate), 0.06, accuracy: 1e-9)
        // Halfway between the two dates lands halfway between the two drift figures —
        // the defining property of a straight line through two points.
        let midpoint = firstDate.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(fit.value(at: midpoint), 0.02, accuracy: 1e-9)
    }

    /// Three points at x = 0, 1, 2 (arbitrary units) with y = 1, 2, 4 is a textbook OLS
    /// example, computed by hand:
    ///
    ///   xMean = 1, yMean = 7/3
    ///   Σ(x - xMean)²      = (-1)² + 0² + 1²                = 2
    ///   Σ(x - xMean)(y - yMean) = (-1)(-4/3) + 0(-1/3) + 1(5/3) = 3
    ///   slope = 3 / 2 = 1.5
    ///   intercept at x = 0: yMean - slope·xMean = 7/3 - 3/2 = 5/6
    ///
    /// so the fitted values at x = 0, 1, 2 are 5/6, 7/3, 23/6.
    func testThreePointsMatchAHandComputedLeastSquaresLine() throws {
        let curves = [
            curve(daysAfterEpoch: 0, driftFraction: 1, id: Fixture.workoutID),
            curve(daysAfterEpoch: 1, driftFraction: 2, id: Fixture.otherWorkoutID),
            curve(daysAfterEpoch: 2, driftFraction: 4, id: thirdWorkoutID),
        ]
        let trendline = HeartRateDriftTrendlineData(curves: curves)
        let fit = try XCTUnwrap(trendline.fit)

        let epoch = Fixture.epoch
        XCTAssertEqual(fit.value(at: epoch), 5.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(fit.value(at: epoch.addingTimeInterval(86_400)), 7.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(fit.value(at: epoch.addingTimeInterval(2 * 86_400)), 23.0 / 6.0, accuracy: 1e-9)
    }

    /// Runs unevenly spaced in time (three days apart, then eleven) must not fit the
    /// same line as the same three drift figures evenly spaced (one day apart each) —
    /// if they did, this type would be fitting against run *index* rather than *date*,
    /// exactly the substitution its own documentation warns against.
    func testUnevenlySpacedRunsFitADifferentLineThanEvenlySpacedOnesWithTheSameValues() throws {
        let values: [Double] = [0.00, 0.02, 0.10]

        let even = HeartRateDriftTrendlineData(curves: [
            curve(daysAfterEpoch: 0, driftFraction: values[0], id: Fixture.workoutID),
            curve(daysAfterEpoch: 1, driftFraction: values[1], id: Fixture.otherWorkoutID),
            curve(daysAfterEpoch: 2, driftFraction: values[2], id: thirdWorkoutID),
        ])
        let uneven = HeartRateDriftTrendlineData(curves: [
            curve(daysAfterEpoch: 0, driftFraction: values[0], id: Fixture.workoutID),
            curve(daysAfterEpoch: 3, driftFraction: values[1], id: Fixture.otherWorkoutID),
            curve(daysAfterEpoch: 14, driftFraction: values[2], id: thirdWorkoutID),
        ])

        let evenFit = try XCTUnwrap(even.fit)
        let unevenFit = try XCTUnwrap(uneven.fit)

        // Same three values, same first date — if x were run index instead of date,
        // both fits would agree everywhere. They must not.
        let aWeekOut = Fixture.epoch.addingTimeInterval(7 * 86_400)
        XCTAssertNotEqual(evenFit.value(at: aWeekOut), unevenFit.value(at: aWeekOut), accuracy: 1e-9)
    }

    // MARK: - Axis domain

    func testAxisDomainPadsAroundTheStoredRange() throws {
        let curves = [
            curve(daysAfterEpoch: 0, driftFraction: -0.01, id: Fixture.workoutID),
            curve(daysAfterEpoch: 1, driftFraction: 0.05, id: Fixture.otherWorkoutID),
        ]
        let trendline = HeartRateDriftTrendlineData(curves: curves)
        let domain = try XCTUnwrap(trendline.driftFractionAxisDomain)

        XCTAssertLessThan(domain.lowerBound, -0.01)
        XCTAssertGreaterThan(domain.upperBound, 0.05)
    }

    func testAxisDomainIsWellFormedForASinglePoint() throws {
        let trendline = HeartRateDriftTrendlineData(curves: [curve(daysAfterEpoch: 0, driftFraction: 0.04)])
        let domain = try XCTUnwrap(trendline.driftFractionAxisDomain)

        XCTAssertLessThan(domain.lowerBound, domain.upperBound)
    }

    // MARK: - Local candidate fixture (mirrors HeartRateDriftOverlayDataTests)

    private func makeWorkout(id: UUID, daysBeforeEpoch: Double, durationSeconds: Double) throws -> Workout {
        let start = Fixture.epoch.addingTimeInterval(-daysBeforeEpoch * 86_400)
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: 10_000,
            activeEnergyKilocalories: 700,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 120)
        )
    }

    private func makeMetrics(id: UUID, driftFraction: Double?) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: id,
            averageHeartRateBPM: 140,
            maximumHeartRateBPM: 170,
            heartRateDriftFraction: driftFraction,
            planVersion: PlanVersion(1)
        )
    }

    private func makeCandidate(
        id: UUID = UUID(),
        daysBeforeEpoch: Double,
        durationSeconds: Double = 3_600,
        samples: [(Double, Double)]? = [(0, 130), (1_800, 150)],
        classification: WorkoutClassification? = .easy,
        driftFraction: Double? = 0.04
    ) throws -> HeartRateDriftOverlayData.Candidate {
        HeartRateDriftOverlayData.Candidate(
            workout: try makeWorkout(id: id, daysBeforeEpoch: daysBeforeEpoch, durationSeconds: durationSeconds),
            series: try samples.map { try MetricsFixture.series($0, workoutID: id) },
            classification: classification,
            metrics: try makeMetrics(id: id, driftFraction: driftFraction)
        )
    }

    private let thirdWorkoutID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
}
