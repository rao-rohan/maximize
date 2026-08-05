import XCTest
@testable import MaximizeCore

/// MAX-046. The arithmetic here is hand-derived and written out beside each assertion.
///
/// Every fixture route walks due north in **equal** steps. Along a meridian the haversine
/// formula collapses to `R · Δφ` exactly (`GradeAdjustedPaceTests` pins that
/// independently), so a route built from a chosen total length has that length, and after
/// `DistanceSplitCalculator` rescales the track to the workout's recorded distance the
/// cumulative distance is exactly proportional to the fix index. The boundary of split *k*
/// therefore falls a fraction `k · unit / total` along the track and its time is read
/// straight off the fix offsets — no calculator required to check any expectation below.
///
/// Comparisons are to an accuracy rather than exact: the fixtures are built through a
/// great-circle formula and then rescaled, so a boundary that lands "exactly" on a fix
/// lands within a few parts in 10¹¹ of it.
final class DistanceSplitsTests: XCTestCase {
    private static let tolerance = 0.000_1

    // MARK: - Fixtures

    /// A route of `offsets.count` evenly spaced fixes along a meridian, `gpsTotalMeters`
    /// long end to end, reaching each fix at the given offset from the workout's start.
    private func evenRoute(offsets: [Double], gpsTotalMeters: Double) throws -> Route {
        let stepDegrees = (gpsTotalMeters / Double(offsets.count - 1)) / MetricsFixture.metersPerLatitudeDegree
        var points: [RoutePoint] = []
        for (index, offset) in offsets.enumerated() {
            points.append(
                try RoutePoint(
                    offsetSeconds: offset,
                    latitudeDegrees: Double(index) * stepDegrees,
                    longitudeDegrees: 0
                )
            )
        }
        return try Route(workoutID: Fixture.workoutID, points: points)
    }

    /// - Parameter gpsTotalMeters: how long the *track* is. Defaults to the recorded
    ///   distance, i.e. a track and a health store that agree exactly; the tests about
    ///   rescaling set it deliberately apart.
    private func splits(
        distanceMeters: Double?,
        durationSeconds: Double,
        offsets: [Double],
        gpsTotalMeters: Double? = nil
    ) throws -> DistanceSplits? {
        let workout = try Fixture.workout(
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
        )
        let route = try evenRoute(
            offsets: offsets,
            gpsTotalMeters: gpsTotalMeters ?? distanceMeters ?? 1_000
        )
        return DistanceSplitCalculator.splits(workout: workout, route: route)
    }

    private func kilometers(_ splits: DistanceSplits?) throws -> DistanceSplitSeries {
        try XCTUnwrap(splits?.series(in: .kilometers))
    }

    private func assertElapsed(
        _ series: DistanceSplitSeries,
        equals expected: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(series.splits.count, expected.count, file: file, line: line)
        for (split, seconds) in zip(series.splits, expected) {
            XCTAssertEqual(split.elapsedSeconds, seconds, accuracy: Self.tolerance, file: file, line: line)
        }
    }

    // MARK: - What a split is measured against

    /// Eleven fixes 100 s apart over a 5 000 m run: each fix is 500 m along, so every
    /// kilometre boundary lands on an even-numbered fix and each split takes 200 s.
    /// 5 000 m is a whole number of kilometres, so there is no remainder.
    func testEvenRunCutsIntoWholeKilometresOfEqualPace() throws {
        let series = try kilometers(
            splits(distanceMeters: 5_000, durationSeconds: 1_000, offsets: (0...10).map { Double($0) * 100 })
        )

        assertElapsed(series, equals: [200, 200, 200, 200, 200])
        for split in series.splits {
            XCTAssertTrue(split.isComplete)
            XCTAssertEqual(split.distanceMeters, 1_000, accuracy: Self.tolerance)
            XCTAssertEqual(split.paceSeconds(per: .kilometers), 200, accuracy: Self.tolerance)
        }
    }

    /// The splits total the workout's **recorded** distance, not the sum of the haversine
    /// distances between GPS fixes. That is the whole reason the track is rescaled: two
    /// notions of how far one run was is exactly the disagreement D2 exists to prevent,
    /// and `GradeAdjustedPace` already refuses the same thing for the same reason.
    func testSplitsTotalTheRecordedDistanceRatherThanTheGPSSum() throws {
        let series = try kilometers(
            splits(
                distanceMeters: 10_000,
                durationSeconds: 1_000,
                offsets: (0...10).map { Double($0) * 100 },
                // A 2% GPS overshoot — the ordinary consumer-GPS case.
                gpsTotalMeters: 10_200
            )
        )

        XCTAssertEqual(series.splits.count, 10)
        XCTAssertEqual(series.totalDistanceMeters, 10_000, accuracy: Self.tolerance)
    }

    /// Pace varies across the run, and the splits show it. Five fixes, 1 000 m apart, at
    /// 0 / 100 / 200 / 400 / 600 s: two fast kilometres, then two slow ones.
    func testSplitPaceFollowsWhereTheAthleteWasFastAndSlow() throws {
        let series = try kilometers(
            splits(distanceMeters: 4_000, durationSeconds: 600, offsets: [0, 100, 200, 400, 600])
        )

        assertElapsed(series, equals: [100, 100, 200, 200])
    }

    /// Time before the first fix belongs to no split. Here GPS took 60 s to acquire, so
    /// the first kilometre is timed from the first fix — not from `Workout.start` — and
    /// the splits account for less time than the workout's duration. The alternative,
    /// charging the lead-in to split one, would report a first kilometre the athlete
    /// spent partly standing still.
    func testAcquisitionLagBeforeTheFirstFixFallsOutsideEverySplit() throws {
        let series = try kilometers(
            splits(distanceMeters: 2_000, durationSeconds: 260, offsets: [60, 160, 260])
        )

        assertElapsed(series, equals: [100, 100])
        XCTAssertEqual(series.totalElapsedSeconds, 200, accuracy: Self.tolerance)
    }

    // MARK: - The final partial split

    /// A 3 400 m run has three complete kilometres and a 400 m remainder. The remainder is
    /// shown — it is a real stretch the athlete ran — and marked incomplete, because its
    /// pace is extrapolated from 400 m and is not a like-for-like number.
    func testTrailingRemainderIsEmittedAndMarkedIncomplete() throws {
        let series = try kilometers(
            splits(distanceMeters: 3_400, durationSeconds: 400, offsets: [0, 100, 200, 300, 400])
        )

        XCTAssertEqual(series.splits.count, 4)
        XCTAssertEqual(series.splits.prefix(3).map(\.isComplete), [true, true, true])

        let remainder = try XCTUnwrap(series.splits.last)
        XCTAssertFalse(remainder.isComplete)
        XCTAssertEqual(remainder.ordinal, 4)
        XCTAssertEqual(remainder.distanceMeters, 400, accuracy: Self.tolerance)
        // The run held a constant 117.647 s/km (400 s over 3 400 m), so the remainder's
        // extrapolated pace matches the complete splits exactly. That the two agree is
        // what makes the extrapolation legitimate arithmetic; the flag beside it, not the
        // number, is what stops a short finishing kick reading as the fastest kilometre.
        XCTAssertEqual(remainder.paceSeconds(per: .kilometers), 400_000 / 3_400, accuracy: Self.tolerance)
        XCTAssertEqual(series.totalDistanceMeters, 3_400, accuracy: Self.tolerance)
    }

    /// A remainder shorter than one GPS fix's spacing is not a stretch of running, it is a
    /// rounding artifact of the rescale whose "pace" is pure interpolation. Dropped, which
    /// is why the splits can total up to ten metres less than the recorded distance.
    func testRemainderBelowTheFloorIsDroppedRatherThanShown() throws {
        let series = try kilometers(
            splits(distanceMeters: 3_005, durationSeconds: 300, offsets: [0, 100, 200, 300])
        )

        XCTAssertEqual(series.splits.count, 3)
        XCTAssertTrue(series.splits.allSatisfy(\.isComplete))
        XCTAssertEqual(series.totalDistanceMeters, 3_000, accuracy: Self.tolerance)
    }

    /// A run shorter than the unit is one incomplete split — not zero splits, and not a
    /// complete one. 800 m is a real run and reporting nothing for it would be wrong.
    func testRunShorterThanOneUnitIsASingleIncompleteSplit() throws {
        let series = try kilometers(
            splits(distanceMeters: 800, durationSeconds: 200, offsets: [0, 100, 200])
        )

        XCTAssertEqual(series.splits.count, 1)
        XCTAssertEqual(series.splits.first?.ordinal, 1)
        XCTAssertEqual(series.splits.first?.isComplete, false)
    }

    /// A mile is 1 609.344 m, which no binary float divides exactly, so a run of exactly
    /// three miles can compute as 2.999… and leave a whole mile marked "partial".
    /// `boundaryToleranceMeters` is what stops that.
    func testRunEndingExactlyOnAUnitBoundaryHasNoPartialSplit() throws {
        let threeMiles = 3 * DistanceUnit.miles.metersPerUnit
        let miles = try XCTUnwrap(
            splits(distanceMeters: threeMiles, durationSeconds: 300, offsets: [0, 100, 200, 300])?
                .series(in: .miles)
        )

        XCTAssertEqual(miles.splits.count, 3)
        XCTAssertTrue(miles.splits.allSatisfy(\.isComplete))
    }

    // MARK: - Both units, stored together

    /// The stored record carries every unit the app can display, because
    /// `AppSettings.distanceUnit` is a display preference the athlete may change long
    /// after a run was ingested. Kilometre and mile boundaries do not align, so one series
    /// cannot be re-cut into the other without going back to the track — which is the
    /// display-time recomputation D2 forbids.
    func testEveryDisplayUnitIsCutAtIngestion() throws {
        let breakdown = try XCTUnwrap(
            splits(distanceMeters: 5_000, durationSeconds: 1_000, offsets: (0...10).map { Double($0) * 100 })
        )

        XCTAssertEqual(breakdown.series.count, DistanceUnit.allCases.count)
        for unit in DistanceUnit.allCases {
            XCTAssertNotNil(breakdown.series(in: unit), "no series stored for \(unit)")
        }

        // 5 000 m is three complete miles (4 828.032 m) plus a 171.968 m remainder,
        // against five complete kilometres and none. Two different cuts of one run.
        let miles = try XCTUnwrap(breakdown.series(in: .miles))
        XCTAssertEqual(miles.splits.count, 4)
        XCTAssertEqual(miles.splits.last?.isComplete, false)
        XCTAssertEqual(miles.totalDistanceMeters, 5_000, accuracy: Self.tolerance)
    }

    /// The run held one constant pace, so both cuts of it report that same pace in their
    /// own units. This is the property that makes storing two series safe: they are two
    /// views of one measurement, not two measurements.
    func testTheTwoUnitSeriesDescribeTheSameRun() throws {
        let breakdown = try XCTUnwrap(
            splits(distanceMeters: 5_000, durationSeconds: 1_000, offsets: (0...10).map { Double($0) * 100 })
        )

        // 1 000 s over 5 000 m is 0.2 s/m, whichever unit anyone prefers to read it in.
        for series in breakdown.series {
            for split in series.splits {
                XCTAssertEqual(split.paceSecondsPerMeter, 0.2, accuracy: 0.000_001)
            }
        }
    }

    // MARK: - Absent, not empty

    /// An indoor run (FR-0.6) has no route, so nothing says when each kilometre fell.
    /// Splitting its distance evenly by its duration would emit a breakdown in which every
    /// split is identical — indistinguishable on screen from a measured one.
    func testIndoorRunHasNoSplitsRatherThanFabricatedOnes() throws {
        let treadmill = try Fixture.workout(
            activityType: .treadmillRunning,
            durationSeconds: 1_800,
            distanceMeters: 5_000,
            hasRoute: false
        )
        XCTAssertNil(DistanceSplitCalculator.splits(workout: treadmill, route: nil))
    }

    func testWorkoutWithNoRecordedDistanceHasNoSplits() throws {
        XCTAssertNil(
            try splits(distanceMeters: nil, durationSeconds: 200, offsets: [0, 100, 200], gpsTotalMeters: 2_000)
        )
        XCTAssertNil(
            try splits(distanceMeters: 0, durationSeconds: 200, offsets: [0, 100, 200], gpsTotalMeters: 2_000)
        )
    }

    /// A single fix carries no distance-versus-time relation at all.
    func testSingleFixRouteHasNoSplits() throws {
        let route = try Route(
            workoutID: Fixture.workoutID,
            points: [try RoutePoint(offsetSeconds: 0, latitudeDegrees: 0, longitudeDegrees: 0)]
        )
        XCTAssertNil(
            DistanceSplitCalculator.splits(
                workout: try Fixture.workout(distanceMeters: 5_000),
                route: route
            )
        )
    }

    /// A route truncated by `RouteFetchRequest.maxPoints`, or one that dropped out through
    /// a tunnel, describes less ground than the run covered. Rescaling it would stretch
    /// every split by the missing fraction and report paces the athlete never ran, so the
    /// honest answer is that this track cannot be cut up.
    func testTrackTooShortForTheRecordedDistanceIsRefusedRatherThanStretched() throws {
        XCTAssertNil(
            try splits(
                distanceMeters: 10_000,
                durationSeconds: 1_000,
                offsets: [0, 100, 200],
                gpsTotalMeters: 5_000
            )
        )
    }

    /// The other direction: a track much longer than the recorded distance is equally
    /// untrustworthy.
    func testTrackTooLongForTheRecordedDistanceIsRefused() throws {
        XCTAssertNil(
            try splits(
                distanceMeters: 5_000,
                durationSeconds: 1_000,
                offsets: [0, 100, 200],
                gpsTotalMeters: 10_000
            )
        )
    }

    /// Ordinary disagreement is corrected, not refused — the guard is against a
    /// structurally wrong track, not against noise.
    func testOrdinaryGPSDisagreementIsCorrectedRatherThanRefused() throws {
        let series = try kilometers(
            splits(
                distanceMeters: 11_000,
                durationSeconds: 1_000,
                offsets: (0...10).map { Double($0) * 100 },
                gpsTotalMeters: 11_120
            )
        )

        XCTAssertEqual(series.splits.count, 11)
        XCTAssertEqual(series.totalDistanceMeters, 11_000, accuracy: Self.tolerance)
    }

    // MARK: - Value-type invariants

    func testSplitRejectsANonPositiveDistanceOrdinalOrElapsedTime() {
        assertThrows(
            .outOfRange,
            try DistanceSplit(ordinal: 1, distanceMeters: 0, elapsedSeconds: 300, isComplete: true)
        )
        assertThrows(
            .outOfRange,
            try DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 0, isComplete: true)
        )
        assertThrows(
            .outOfRange,
            try DistanceSplit(ordinal: 0, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true)
        )
    }

    func testSeriesRejectsGappedOrdinals() {
        assertThrows(
            .outOfOrder,
            try DistanceSplitSeries(
                unit: .kilometers,
                splits: [
                    DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true),
                    DistanceSplit(ordinal: 3, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true),
                ]
            )
        )
    }

    /// Only the *last* split may be incomplete. An incomplete split in the middle would
    /// mean the run had a hole in it — not a state the calculator can produce, and not one
    /// a view should have to handle.
    func testSeriesRejectsAnIncompleteSplitThatIsNotLast() {
        assertThrows(
            .inconsistent,
            try DistanceSplitSeries(
                unit: .kilometers,
                splits: [
                    DistanceSplit(ordinal: 1, distanceMeters: 400, elapsedSeconds: 120, isComplete: false),
                    DistanceSplit(ordinal: 2, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true),
                ]
            )
        )
    }

    /// Absence is `DerivedMetrics.distanceSplits == nil`; these types cannot represent an
    /// empty breakdown, so the two states can never be confused.
    func testEmptySeriesAndEmptyBreakdownAreRejected() {
        assertThrows(.empty, try DistanceSplitSeries(unit: .kilometers, splits: []))
        assertThrows(.empty, try DistanceSplits(series: []))
    }

    func testDuplicateUnitsAreRejected() throws {
        let series = try DistanceSplitSeries(
            unit: .kilometers,
            splits: [DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 300, isComplete: true)]
        )
        assertThrows(.duplicate, try DistanceSplits(series: [series, series]))
    }

    func testSplitsRoundTripThroughCodable() throws {
        let breakdown = try XCTUnwrap(
            splits(distanceMeters: 5_000, durationSeconds: 1_000, offsets: (0...10).map { Double($0) * 100 })
        )
        XCTAssertEqual(try roundTripped(breakdown), breakdown)
    }

    /// Decoding goes through the validating initializer, so a blob mangled on disk or by a
    /// bad migration is rejected at the boundary rather than flowing into a view as a
    /// plausible-looking wrong number.
    func testDecodingRejectsAnInvalidSplit() {
        let json = Data(
            """
            {"wrapped":{"series":[{"unit":"kilometers","splits":[\
            {"ordinal":1,"distanceMeters":1000,"elapsedSeconds":0,"isComplete":true}]}]}}
            """.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(CodableBox<DistanceSplits>.self, from: json))
    }
}
