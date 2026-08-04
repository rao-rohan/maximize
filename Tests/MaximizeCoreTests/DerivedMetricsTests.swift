import Foundation
import XCTest
@testable import MaximizeCore

final class DerivedMetricsTests: XCTestCase {
    private func metrics(
        averageHeartRateBPM: Double? = 142,
        maximumHeartRateBPM: Double? = 168,
        timeAboveCapSeconds: Double? = 240,
        heartRateDriftFraction: Double? = 0.042,
        averageCadenceStepsPerMinute: Double? = 167,
        gradeAdjustedPaceSecondsPerKilometer: Double? = 330,
        zoneSplits: ZoneSplits = .empty
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: timeAboveCapSeconds,
            heartRateDriftFraction: heartRateDriftFraction,
            averageCadenceStepsPerMinute: averageCadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
            zoneSplits: zoneSplits,
            planVersion: PlanVersion(1)
        )
    }

    func testRejectsAMaximumBelowTheAverage() throws {
        assertThrows(.inconsistent, try metrics(averageHeartRateBPM: 160, maximumHeartRateBPM: 140))
    }

    func testRejectsTimeAboveCapWithoutAHeartRateSeries() throws {
        assertThrows(
            .inconsistent,
            try metrics(averageHeartRateBPM: nil, maximumHeartRateBPM: nil, timeAboveCapSeconds: 120)
        )
    }

    func testRejectsNegativeAndNonFiniteQuantities() throws {
        assertThrows(.outOfRange, try metrics(timeAboveCapSeconds: -1))
        assertThrows(.outOfRange, try metrics(averageCadenceStepsPerMinute: -167))
        assertThrows(.outOfRange, try metrics(gradeAdjustedPaceSecondsPerKilometer: 0))
        assertThrows(.notFinite, try metrics(heartRateDriftFraction: .nan))
        assertThrows(.outOfRange, try metrics(averageHeartRateBPM: 500, maximumHeartRateBPM: 500))
    }

    /// Absence is meaningful: an indoor run has no grade-adjusted pace, and a hard
    /// session's drift is "near-meaningless" (§9) — both are nil, not zero.
    func testAbsentMetricsAreRepresentable() throws {
        let indoor = try metrics(
            heartRateDriftFraction: nil,
            gradeAdjustedPaceSecondsPerKilometer: nil
        )
        XCTAssertNil(indoor.heartRateDriftFraction)
        XCTAssertNil(indoor.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertTrue(indoor.hasHeartRateData)

        let noHeartRate = try metrics(
            averageHeartRateBPM: nil,
            maximumHeartRateBPM: nil,
            timeAboveCapSeconds: nil,
            heartRateDriftFraction: nil
        )
        XCTAssertFalse(noHeartRate.hasHeartRateData)
    }

    /// Zero seconds above the cap is a real, and good, answer — distinct from "we
    /// never measured".
    func testZeroTimeAboveCapIsDistinctFromUnmeasured() throws {
        XCTAssertEqual(try metrics(timeAboveCapSeconds: 0).timeAboveCapSeconds, 0)
        XCTAssertNil(try metrics(timeAboveCapSeconds: nil).timeAboveCapSeconds)
    }

    /// The rubric names a metric; the metrics record answers. This is the seam that
    /// lets the rubric stay data.
    func testMetricLookupBridgesRubricNamesToValues() throws {
        let workout = try Fixture.workout(durationSeconds: 3_600, distanceMeters: 10_000)
        let derived = try metrics()

        XCTAssertEqual(derived.value(for: .averageHeartRateBPM, workout: workout), 142)
        XCTAssertEqual(derived.value(for: .timeAboveCapSeconds, workout: workout), 240)
        XCTAssertEqual(derived.value(for: .heartRateDriftFraction, workout: workout), 0.042)
        XCTAssertEqual(derived.value(for: .distanceMeters, workout: workout), 10_000)
        XCTAssertEqual(derived.value(for: .durationSeconds, workout: workout), 3_600)
    }

    func testRoundTripsThroughJSON() throws {
        let derived = try metrics(zoneSplits: ZoneSplits(splits: [
            ZoneSplits.Split(zone: .two, seconds: 1_800),
            ZoneSplits.Split(zone: .three, seconds: 900),
        ]))
        XCTAssertEqual(try roundTripped(derived), derived)
    }
}

final class ZoneSplitsTests: XCTestCase {
    func testRejectsARepeatedZone() throws {
        let splits = [
            try ZoneSplits.Split(zone: .two, seconds: 600),
            try ZoneSplits.Split(zone: .two, seconds: 300),
        ]
        assertThrows(.duplicate, try ZoneSplits(splits: splits))
    }

    func testRejectsNegativeTime() {
        assertThrows(.outOfRange, try ZoneSplits.Split(zone: .one, seconds: -1))
    }

    func testAbsentZonesReadAsZeroSeconds() throws {
        let splits = try ZoneSplits(splits: [
            ZoneSplits.Split(zone: .three, seconds: 900),
        ])
        XCTAssertEqual(splits.seconds(in: .three), 900)
        XCTAssertEqual(splits.seconds(in: .five), 0)
        XCTAssertEqual(splits.totalSeconds, 900)
        XCTAssertEqual(ZoneSplits.empty.totalSeconds, 0)
    }

    func testSplitsAreStoredInZoneOrder() throws {
        let splits = try ZoneSplits(splits: [
            ZoneSplits.Split(zone: .four, seconds: 120),
            ZoneSplits.Split(zone: .one, seconds: 60),
            ZoneSplits.Split(zone: .three, seconds: 90),
        ])
        XCTAssertEqual(splits.splits.map(\.zone), [.one, .three, .four])
    }
}
