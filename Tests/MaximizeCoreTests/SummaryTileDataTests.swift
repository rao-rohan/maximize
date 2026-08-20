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
        strain: WorkoutStrain? = nil,
        workoutID: UUID = Fixture.workoutID
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: averageHeartRateBPM == nil ? nil : 120,
            heartRateDriftFraction: heartRateDriftFraction,
            gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
            strain: strain,
            planVersion: PlanVersion(1)
        )
    }

    // MARK: - Pass-through, never derived

    func testDistanceIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout(distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertEqual(data.distance?.value, "8.42")
        XCTAssertEqual(data.distance?.caption, "km")
    }

    func testDurationIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout(durationSeconds: 462)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertEqual(data.duration.value, "7:42")
    }

    func testAverageAndMaximumHeartRateAreReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(averageHeartRateBPM: 152, maximumHeartRateBPM: 179),
            distanceUnit: .kilometers
        )

        XCTAssertEqual(data.averageHeartRate?.value, "152")
        XCTAssertEqual(data.maximumHeartRate?.value, "179")
    }

    func testActiveEnergyIsReadFromTheWorkoutVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        // Fixture.workout hardcodes 700 kcal.
        XCTAssertEqual(data.activeEnergy?.value, "700")
        XCTAssertEqual(data.activeEnergy?.caption, "kcal")
    }

    func testHeartRateDriftIsReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout, metrics: try metrics(heartRateDriftFraction: -0.024), distanceUnit: .kilometers
        )

        XCTAssertEqual(data.heartRateDrift?.value, "-2.4")
    }

    func testGradeAdjustedPaceIsReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(gradeAdjustedPaceSecondsPerKilometer: 312),
            distanceUnit: .kilometers
        )

        XCTAssertEqual(data.gradeAdjustedPace?.value, "5:12")
        XCTAssertEqual(data.gradeAdjustedPace?.caption, "grade-adj. pace /km")
    }

    /// MAX-047: the stored figure is always seconds-per-kilometre (D2); a mile is
    /// longer than a kilometre, so the per-mile pace is proportionally slower — this
    /// pins the conversion factor, not just that a number changes.
    func testGradeAdjustedPaceConvertsToSecondsPerMileWhenUnitIsMiles() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(gradeAdjustedPaceSecondsPerKilometer: 312),
            distanceUnit: .miles
        )

        // 312 s/km * 1.609344 = 502.1... s/mi = 8:22.
        XCTAssertEqual(data.gradeAdjustedPace?.value, "8:22")
        XCTAssertEqual(data.gradeAdjustedPace?.caption, "grade-adj. pace /mi")
    }

    // MARK: - Absent is not zero

    func testNoDistanceStaysAbsentRatherThanBecomingZero() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertNil(data.distance)
    }

    func testNilMetricsLeavesEveryMetricsDerivedTileAbsent() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

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
            metrics: try metrics(averageHeartRateBPM: nil, maximumHeartRateBPM: nil),
            distanceUnit: .kilometers
        )

        XCTAssertNil(data.averageHeartRate)
        XCTAssertNil(data.maximumHeartRate)
    }

    func testDriftWithheldAsNotMeaningfulStaysAbsentNotZero() throws {
        // §9: drift withheld for a hard/interval session is nil, not 0%. This type has
        // no way to tell that apart from "no HR data at all" and does not try to —
        // both simply omit the tile.
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout, metrics: try metrics(heartRateDriftFraction: nil), distanceUnit: .kilometers
        )

        XCTAssertNil(data.heartRateDrift)
    }

    func testNoRouteLeavesGradeAdjustedPaceAbsent() throws {
        let workout = try Fixture.workout(hasRoute: false)
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(gradeAdjustedPaceSecondsPerKilometer: nil),
            distanceUnit: .kilometers
        )

        XCTAssertNil(data.gradeAdjustedPace)
    }

    func testDurationIsNeverAbsentEvenWithNoOtherData() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        // Duration is never optional on `Workout`, so its tile is never optional here.
        XCTAssertFalse(data.duration.value.isEmpty)
    }

    // MARK: - `tiles` — FR-1.5's order, absent figures simply missing

    func testTilesOmitsAbsentFiguresRatherThanPaddingWithPlaceholders() throws {
        let workout = try Fixture.workout(distanceMeters: nil, hasRoute: false)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        // Only duration and active energy (Fixture.workout always sets energy) survive.
        XCTAssertEqual(data.tiles.count, 2)
    }

    func testTilesFollowsFR15sStatedOrderWhenEveryFigureIsPresent() throws {
        let workout = try Fixture.workout(durationSeconds: 462, distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: try metrics(), distanceUnit: .kilometers)

        XCTAssertEqual(data.tiles.count, 7)
        XCTAssertEqual(data.tiles[0].caption, "km")
        XCTAssertEqual(data.tiles[1].caption, "duration")
        XCTAssertEqual(data.tiles[2].caption, "avg bpm")
        XCTAssertEqual(data.tiles[3].caption, "max bpm")
        XCTAssertEqual(data.tiles[4].caption, "kcal")
        XCTAssertEqual(data.tiles[5].caption, "% drift")
        XCTAssertEqual(data.tiles[6].caption, "grade-adj. pace /km")
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
        let data = SummaryTileData(
            workout: workout, metrics: try metrics(heartRateDriftFraction: 0.031), distanceUnit: .kilometers
        )
        XCTAssertEqual(data.heartRateDrift?.value, "+3.1")
    }

    func testFormattedSignedPercentZeroStillShowsPlusSign() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(
            workout: workout, metrics: try metrics(heartRateDriftFraction: 0), distanceUnit: .kilometers
        )
        XCTAssertEqual(data.heartRateDrift?.value, "+0.0")
    }

    // MARK: - Distance formatting, unit-aware (MAX-047)

    func testDistanceConvertsToMilesWhenUnitIsMiles() throws {
        // 8,420 m / 1,609.344 m per mile = 5.23...
        let workout = try Fixture.workout(distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .miles)

        XCTAssertEqual(data.distance?.value, "5.23")
        XCTAssertEqual(data.distance?.caption, "mi")
    }

    func testDistanceStaysInKilometersWhenUnitIsKilometers() throws {
        let workout = try Fixture.workout(distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertEqual(data.distance?.value, "8.42")
        XCTAssertEqual(data.distance?.caption, "km")
    }

    // MARK: - MAX-139: a lift's tiles, discipline-gated explicitly

    /// Which tiles a lift gets: duration, avg/max heart rate and active energy, never
    /// distance, drift or grade-adjusted pace — even when every one of the run-only
    /// figures is fully populated in the inputs, which pins that the exclusion is a
    /// decision this type makes rather than an accident of what happened to be nil.
    func testALiftShowsOnlyTheFiguresThatDescribeALift() throws {
        let workout = try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            distanceMeters: 500,
            hasRoute: false
        )
        let data = SummaryTileData(
            workout: workout,
            metrics: try metrics(),
            distanceUnit: .kilometers
        )

        XCTAssertNil(data.distance, "A lift's distance is not a training figure (A20)")
        XCTAssertNil(data.heartRateDrift, "Drift measures a held aerobic effort a lift does not hold")
        XCTAssertNil(data.gradeAdjustedPace, "Grade-adjusted pace models the cost of running")
        XCTAssertNotNil(data.averageHeartRate, "A heart rate measured during a lift is still a heart rate")
        XCTAssertNotNil(data.maximumHeartRate)
        XCTAssertNotNil(data.activeEnergy)
        XCTAssertFalse(data.duration.value.isEmpty)
    }

    /// The defensive half of the guard: even a lift whose *stored* metrics still carry
    /// drift and grade-adjusted pace — the shape a workout ingested before MAX-130
    /// gated the calculator would have — must not show them. `SummaryTileData` does not
    /// trust the metric to already be nil; it gates on discipline itself.
    func testALiftsStaleDriftAndPaceFromBeforeMAX130StayHidden() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)
        let staleMetrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 140,
            maximumHeartRateBPM: 165,
            heartRateDriftFraction: 0.08,
            gradeAdjustedPaceSecondsPerKilometer: 300,
            planVersion: PlanVersion(1)
        )
        let data = SummaryTileData(workout: workout, metrics: staleMetrics, distanceUnit: .kilometers)

        XCTAssertNil(data.heartRateDrift)
        XCTAssertNil(data.gradeAdjustedPace)
    }

    func testALiftsTilesCountOnlyTheFiguresThatApply() throws {
        let workout = try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            distanceMeters: nil,
            hasRoute: false
        )
        let data = SummaryTileData(workout: workout, metrics: try metrics(), distanceUnit: .kilometers)

        // duration, avg bpm, max bpm, kcal — no distance, no drift, no pace.
        XCTAssertEqual(data.tiles.count, 4)
    }

    func testARunsTilesAreUnaffectedByTheLiftGuard() throws {
        let workout = try Fixture.workout(activityType: .running, distanceMeters: 8_420)
        let data = SummaryTileData(workout: workout, metrics: try metrics(), distanceUnit: .kilometers)

        XCTAssertEqual(data.tiles.count, 7, "Every figure MAX-045 originally shipped, unaffected by MAX-139")
    }

    // MARK: - MAX-139: `discipline`, `showsRunOnlySections`, `disciplineNote`

    func testDisciplineIsReadFromTheWorkoutsActivityType() throws {
        let run = try SummaryTileData(
            workout: Fixture.workout(activityType: .running), metrics: nil, distanceUnit: .kilometers
        )
        let lift = try SummaryTileData(
            workout: Fixture.workout(activityType: .traditionalStrengthTraining),
            metrics: nil,
            distanceUnit: .kilometers
        )

        XCTAssertEqual(run.discipline, .run)
        XCTAssertEqual(lift.discipline, .lift)
    }

    /// Every named `ActivityType` that is not a strength type stays `.run` by slot
    /// (A17) — a ride and a hike show the run-only sections exactly as a run does.
    func testNonLiftActivityTypesAllShowTheRunOnlySections() throws {
        for activityType: ActivityType in [.running, .treadmillRunning, .walking, .hiking, .cycling] {
            let data = SummaryTileData(
                workout: try Fixture.workout(activityType: activityType), metrics: nil, distanceUnit: .kilometers
            )
            XCTAssertTrue(data.showsRunOnlySections, "\(activityType)")
            XCTAssertNil(data.disciplineNote, "\(activityType)")
        }
    }

    func testALiftDoesNotShowTheRunOnlySections() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertFalse(data.showsRunOnlySections)
    }

    /// The absence copy for the four removed sections (cadence, route, splits, cap
    /// line): present only for a lift, and worded apart from the fact sheet's and the
    /// route section's own absence strings, per CLAUDE.md's "different statements must
    /// not share copy".
    func testALiftCarriesADisciplineNoteDistinctFromOtherAbsenceCopy() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        let note = try XCTUnwrap(data.disciplineNote)
        XCTAssertTrue(note.contains("lift"))
        XCTAssertFalse(note.contains("indoor"), "Must not read as `RouteMapView`'s indoor-run absence")
        XCTAssertNotEqual(note, "This was a lift, not a run. The figures a run is measured by are absent below "
            + "rather than empty: they do not describe this session and were never computed "
            + "for it, so read nothing into their absence and do not judge the session by them.")
    }

    func testARunCarriesNoDisciplineNote() throws {
        let workout = try Fixture.workout(activityType: .running)
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertNil(data.disciplineNote)
    }

    // MARK: - MAX-177: strain

    func testStrainIsReadFromMetricsVerbatim() throws {
        let workout = try Fixture.workout()
        let strain = try WorkoutStrain(points: 142)
        let data = SummaryTileData(workout: workout, metrics: try metrics(strain: strain), distanceUnit: .kilometers)

        XCTAssertEqual(data.strain?.value, "142")
        // The unit lives in the caption on purpose — see the type's doc comment on why
        // a bare "strain" caption would misread as a bounded 0–21-style rating.
        XCTAssertEqual(data.strain?.caption, "strain pts")
    }

    func testNoStrainStaysAbsentRatherThanBecomingZero() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: try metrics(strain: nil), distanceUnit: .kilometers)

        XCTAssertNil(data.strain)
    }

    func testNilMetricsLeavesStrainAbsentToo() throws {
        let workout = try Fixture.workout()
        let data = SummaryTileData(workout: workout, metrics: nil, distanceUnit: .kilometers)

        XCTAssertNil(data.strain)
    }

    /// A zero-span curve (`WorkoutStrain(points: 0)`, MAX-176's single-sample case) is a
    /// real recorded measurement, not an absence — the tile must show "0", never omit
    /// the tile the way it does for a genuinely missing strain.
    func testAZeroStrainRendersAsARealMeasurementNotAnAbsence() throws {
        let workout = try Fixture.workout()
        let strain = try WorkoutStrain(points: 0)
        let data = SummaryTileData(workout: workout, metrics: try metrics(strain: strain), distanceUnit: .kilometers)

        XCTAssertEqual(data.strain?.value, "0")
    }

    /// MAX-176: a lift's strain is heart-rate only, but it is still shown — unlike
    /// distance, drift and grade-adjusted pace, it is not gated to nil by discipline,
    /// because `DerivedMetricKind.strain` is `.anyDiscipline` (a heart rate measured
    /// during a lift is still a heart rate).
    func testALiftsStrainIsNotGatedAwayLikeTheRunOnlyFigures() throws {
        let workout = try Fixture.workout(
            activityType: .traditionalStrengthTraining, distanceMeters: 500, hasRoute: false
        )
        let strain = try WorkoutStrain(points: 96)
        let data = SummaryTileData(workout: workout, metrics: try metrics(strain: strain), distanceUnit: .kilometers)

        XCTAssertEqual(data.strain?.value, "96")
    }

    /// FR-1.5's own six tiles keep their stated order; strain is a MAX-176 figure that
    /// postdates the spec, so it is appended rather than interleaved.
    func testStrainAppearsLastInTilesRatherThanReorderingFR15sList() throws {
        let workout = try Fixture.workout(durationSeconds: 462, distanceMeters: 8_420)
        let strain = try WorkoutStrain(points: 118)
        let data = SummaryTileData(workout: workout, metrics: try metrics(strain: strain), distanceUnit: .kilometers)

        XCTAssertEqual(data.tiles.count, 8)
        XCTAssertEqual(data.tiles[7].caption, "strain pts")
        XCTAssertEqual(data.tiles[7].value, "118")
    }

    func testFormattedStrainRoundsToTheNearestWholePoint() {
        XCTAssertEqual(SummaryTileData.formattedStrain(141.6), "142")
    }
}
