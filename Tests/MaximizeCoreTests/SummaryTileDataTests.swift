import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-045: the tile-ready presentation FR-1.5's summary tiles are built from.
///
/// Mirrors `CadenceChartDataTests` (MAX-043) and `HeartRateChartDataTests` (MAX-042):
/// pins that every figure is read verbatim from `Workout`/`DerivedMetrics`, never
/// derived from anything else, that absence stays absence rather than becoming a
/// fabricated zero, and that the formatting helpers are correct at their edges.
final class SummaryTileDataTests: XCTestCase {
    private func metrics(
        averageHeartRateBPM: Double? = 150,
        maximumHeartRateBPM: Double? = 180,
        heartRateDriftFraction: Double? = 0.05,
        gradeAdjustedPaceSecondsPerKilometer: Double? = 312,
        workoutID: UUID = Fixture.workoutID
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: averageHeartRateBPM == nil ? nil : 120,
            heartRateDriftFraction: heartRateDriftFraction,
            gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
            planVersion: PlanVersion(1)
        )
    }

    // MARK: - Pass-through, never derived

    func testDistanceIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout(distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: nil)

        XCTAssertEqual(data.distance?.value, "8.42")
        XCTAssertEqual(data.distance?.caption, "km")
    }

    func testDurationIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout(durationSeconds: 462)
        let data = SummaryTileData(workout: workout, metrics: nil)

        XCTAssertEqual(data.duration.value, "7:42")
    }

    func testAverageAndMaximumHeartRateAreReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(averageHeartRateBPM: 152, maximumHeartRateBPM: 179)
        )

        XCTAssertEqual(data.averageHeartRate?.value, "152")
        XCTAssertEqual(data.maximumHeartRate?.value, "179")
    }

    func testActiveEnergyIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: nil)

        // Fixture.workout hardcodes 700 kcal.
        XCTAssertEqual(data.activeEnergy?.value, "700")
        XCTAssertEqual(data.activeEnergy?.caption, "kcal")
    }

    func testHeartRateDriftIsReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: try metrics(heartRateDriftFraction: -0.024))

        XCTAssertEqual(data.heartRateDrift?.value, "-2.4")
    }

    func testGradeAdjustedPaceIsReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(gradeAdjustedPaceSecondsPerKilometer: 312)
        )

        XCTAssertEqual(data.gradeAdjustedPace?.value, "5:12")
    }

    // MARK: - Absent is not zero

    func testNoDistanceStaysAbsentRatherThanBecomingZero() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil)

        XCTAssertNil(data.distance)
    }

    func testNilMetricsLeavesEveryMetricsDerivedTileAbsent() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: nil)

        XCTAssertNil(data.averageHeartRate)
        XCTAssertNil(data.maximumHeartRate)
        XCTAssertNil(data.heartRateDrift)
        XCTAssertNil(data.gradeAdjustedPace)
        // Duration and (when recorded) distance/energy are not gated on metrics.
        XCTAssertEqual(data.duration.value, SummaryTileData.formattedDuration(seconds: workout.durationSeconds))
    }

    func testNoHeartRateSeriesLeavesHeartRateTilesAbsentWithoutFabricatingZero() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(averageHeartRateBPM: nil, maximumHeartRateBPM: nil)
        )

        XCTAssertNil(data.averageHeartRate)
        XCTAssertNil(data.maximumHeartRate)
    }

    func testDriftWithheldAsNotMeaningfulStaysAbsentNotZero() throws {
        // §9: drift withheld for a hard/interval session is nil, not 0%. This type has
        // no way to tell that apart from "no HR data at all" and does not try to —
        // both simply omit the tile.
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: try metrics(heartRateDriftFraction: nil))

        XCTAssertNil(data.heartRateDrift)
    }

    func testNoRouteLeavesGradeAdjustedPaceAbsent() throws {
        let workout = try Fixture.workout(hasRoute: false)
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(gradeAdjustedPaceSecondsPerKilometer: nil)
        )

        XCTAssertNil(data.gradeAdjustedPace)
    }

    func testDurationIsNeverAbsentEvenWithNoOtherData() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil)

        // Duration is never optional on `Workout`, so its tile is never optional here.
        XCTAssertFalse(data.duration.value.isEmpty)
    }

    // MARK: - `tiles` — FR-1.5's order, absent figures simply missing

    func testTilesOmitsAbsentFiguresRatherThanPaddingWithPlaceholders() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil)

        // Only duration and active energy (Fixture.workout always sets energy) survive.
        XCTAssertEqual(data.tiles.count, 2)
    }

    func testTilesFollowsFR15sStatedOrderWhenEveryFigureIsPresent() throws {
        let workout = try Fixture.workout(durationSeconds: 462, distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: try metrics())

        XCTAssertEqual(data.tiles.count, 7)
        XCTAssertEqual(data.tiles[0].caption, "km")
        XCTAssertEqual(data.tiles[1].caption, "duration")
        XCTAssertEqual(data.tiles[2].caption, "avg bpm")
        XCTAssertEqual(data.tiles[3].caption, "max bpm")
        XCTAssertEqual(data.tiles[4].caption, "kcal")
        XCTAssertEqual(data.tiles[5].caption, "% drift")
        XCTAssertEqual(data.tiles[6].caption, "grade-adj. pace")
    }

    // MARK: - Duration formatting

    func testFormattedDurationUnderAMinute() {
        XCTAssertEqual(SummaryTileData.formattedDuration(seconds: 45), "0:45")
    }

    func testFormattedDurationUnderAnHour() {
        XCTAssertEqual(SummaryTileData.formattedDuration(seconds: 462), "7:42")
    }

    func testFormattedDurationOverAnHour() {
        XCTAssertEqual(SummaryTileData.formattedDuration(seconds: 3_723), "1:02:03")
    }

    func testFormattedDurationOfZero() {
        XCTAssertEqual(SummaryTileData.formattedDuration(seconds: 0), "0:00")
    }

    func testFormattedDurationRoundsToTheNearestSecond() {
        XCTAssertEqual(SummaryTileData.formattedDuration(seconds: 461.6), "7:42")
    }

    // MARK: - Drift formatting: sign is never dropped

    func testFormattedSignedPercentPositive() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: try metrics(heartRateDriftFraction: 0.031))
        XCTAssertEqual(data.heartRateDrift?.value, "+3.1")
    }

    func testFormattedSignedPercentZeroStillShowsPlusSign() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: try metrics(heartRateDriftFraction: 0))
        XCTAssertEqual(data.heartRateDrift?.value, "+0.0")
    }
}
