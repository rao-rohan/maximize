import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-176 — the per-workout strain figure: what the session cost, as against what the
/// rest of the record measures, which is whether the athlete did what was asked.
///
/// **Every expected number here is computed by hand in the comment above it**, from the
/// zone boundaries and the interpolated crossings, never read off the implementation.
/// That is the only way a test of an integral is worth anything: an expectation captured
/// from the code under test asserts that the code does what it does.
///
/// The boundaries throughout are `Fixture.plan()`'s: a 150 bpm cap, so under
/// `HeartRateZoneModel.capAnchoredMultipliers` the inclusive upper bounds are **135, 150,
/// 162, 174**, and anything above 174 is zone 5.
final class WorkoutStrainTests: XCTestCase {
    private static let capBPM = 150.0

    private func zones() throws -> HeartRateZoneModel {
        try HeartRateZoneModel.capAnchored(heartRateCapBPM: Self.capBPM)
    }

    /// Metrics as the ingestion path computes them, for a workout of the given
    /// discipline over the given curve. Nothing here recomputes strain — the point of
    /// D2 is that the figure is produced once, here, and read everywhere else.
    private func computeMetrics(
        _ samples: [(Double, Double)]?,
        activityType: ActivityType = .running,
        durationSeconds: Double = 3_600
    ) throws -> DerivedMetrics {
        try DerivedMetricsCalculator.compute(
            DerivedMetricsInput(
                workout: try Fixture.workout(
                    activityType: activityType,
                    durationSeconds: durationSeconds,
                    hasRoute: false
                ),
                heartRateSeries: try samples.map { try MetricsFixture.series($0) },
                classification: .easy
            ),
            plan: try Fixture.plan()
        )
    }

    private func splits(_ pairs: [(HeartRateZone, Double)]) throws -> ZoneSplits {
        try ZoneSplits(splits: pairs.map { try ZoneSplits.Split(zone: $0.0, seconds: $0.1) })
    }

    // MARK: - The weighting itself

    /// Edwards' model, and the whole of the modelling choice: a zone counts for its own
    /// ordinal. Pinned as a value rather than left implicit in the totals below, because
    /// a change to it silently re-scales every stored number and must be a deliberate act.
    func testEachZoneWeighsItsOwnOrdinal() {
        XCTAssertEqual(HeartRateZone.allCases.map(WorkoutStrain.weight(for:)), [1, 2, 3, 4, 5])
    }

    /// `Σ weight(zone) · seconds(zone) / 60`, with nothing else in the way.
    ///
    /// 600 s in zone 1 (×1) + 300 s in zone 3 (×3) = 600 + 900 = 1_500 weighted seconds,
    /// which is 25 zone-weighted minutes.
    func testStrainIsTheZoneWeightedSumOfTheTimeInEachZone() throws {
        let strain = try WorkoutStrain(zoneSplits: splits([(.one, 600), (.three, 300)]))
        XCTAssertEqual(strain.points, 25, accuracy: 1e-9)
    }

    /// The anchor sentence for the unit, and the one worth remembering: **an hour held
    /// just under the cap is 120 points**, because the cap is the top of zone 2 and zone 2
    /// counts twice. 60 min × 2 = 120.
    func testAnHourHeldJustUnderTheCapIsOneHundredAndTwentyPoints() throws {
        // 145 bpm is inside zone 2 under a 150 bpm cap (135 < 145 ≤ 150).
        let metrics = try computeMetrics([(0, 145), (3_600, 145)])

        XCTAssertEqual(metrics.zoneSplits.seconds(in: .two), 3_600, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, 120, accuracy: 1e-9)
    }

    // MARK: - Over a real curve, against arithmetic done by hand

    /// A curve climbing 120 → 180 bpm evenly over an hour, under a 150 bpm cap. The
    /// slope is 60 bpm over 3_600 s, i.e. 1 bpm per minute, so every boundary crossing
    /// falls on a round number:
    ///
    /// | boundary | crossed at | zone | seconds | weight | weighted |
    /// |---|---|---|---|---|---|
    /// | 135 |  900 s | 1 |  900 | ×1 |   900 |
    /// | 150 | 1800 s | 2 |  900 | ×2 | 1_800 |
    /// | 162 | 2520 s | 3 |  720 | ×3 | 2_160 |
    /// | 174 | 3240 s | 4 |  720 | ×4 | 2_880 |
    /// | —   |    —   | 5 |  360 | ×5 | 1_800 |
    ///
    /// 900 + 1_800 + 2_160 + 2_880 + 1_800 = **9_540 weighted seconds = 159 points**.
    func testStrainOverAKnownCurveIsTheHandComputedZoneWeightedIntegral() throws {
        let metrics = try computeMetrics([(0, 120), (3_600, 180)])

        XCTAssertEqual(metrics.zoneSplits.seconds(in: .one), 900, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .two), 900, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .three), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .four), 720, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .five), 360, accuracy: 1e-9)

        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, 159, accuracy: 1e-9)
    }

    /// A curve that is flat, then climbs through three boundaries, then is flat again —
    /// so the crossings land off the sample grid and the interpolation is doing real work.
    ///
    /// Samples: 120 bpm at 0 s and 900 s, 168 bpm at 1_200 s and 1_500 s. The climbing
    /// segment runs 900 → 1_200 s at 48 bpm over 300 s = 0.16 bpm/s, so:
    ///
    /// - 135 bpm at 900 + 15/0.16 = 993.75 s
    /// - 150 bpm at 900 + 30/0.16 = 1_087.5 s
    /// - 162 bpm at 900 + 42/0.16 = 1_162.5 s
    /// - 174 bpm is never reached (the curve tops out at 168).
    ///
    /// | zone | seconds | weight | weighted |
    /// |---|---|---|---|
    /// | 1 | 993.75 (0 → 993.75)                | ×1 |   993.75 |
    /// | 2 |  93.75 (993.75 → 1_087.5)          | ×2 |   187.5  |
    /// | 3 |  75    (1_087.5 → 1_162.5)         | ×3 |   225    |
    /// | 4 | 337.5  (1_162.5 → 1_200, + 300 flat) | ×4 | 1_350   |
    ///
    /// 993.75 + 187.5 + 225 + 1_350 = **2_756.25 weighted seconds = 45.9375 points**,
    /// over a curve covering 1_500 s in total.
    func testStrainOverACurveWhoseCrossingsFallBetweenSamplesIsHandComputable() throws {
        let metrics = try computeMetrics(
            [(0, 120), (900, 120), (1_200, 168), (1_500, 168)],
            durationSeconds: 1_500
        )

        XCTAssertEqual(metrics.zoneSplits.totalSeconds, 1_500, accuracy: 1e-9)
        XCTAssertEqual(metrics.zoneSplits.seconds(in: .four), 337.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, 45.9375, accuracy: 1e-9)
    }

    /// D2's half of the design, as a property rather than as a number: strain is a total
    /// of the distribution the record already carries, so the two can never tell
    /// different stories about the same run. If a later change walked the curve a second
    /// time to produce this figure, this is the test that would catch the drift.
    func testStrainTotalsTheVeryZoneSplitsTheRecordCarries() throws {
        let metrics = try computeMetrics([(0, 118), (600, 155), (1_800, 141), (3_600, 179)])
        let byHand = metrics.zoneSplits.splits.reduce(0.0) { total, split in
            total + WorkoutStrain.weight(for: split.zone) * split.seconds
        } / 60

        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, byHand, accuracy: 1e-9)
    }

    // MARK: - Ordering, which is what the figure is actually for

    /// Twice the session at the same intensity is twice the cost: 30 min in zone 2 is 60
    /// points, 60 min in zone 2 is 120. The comparison is the whole point of storing a
    /// scalar, so it is asserted as an ordering and not only as two values.
    func testALongerSessionAtTheSameIntensityOutranksAShorterOne() throws {
        let short = try XCTUnwrap(try computeMetrics([(0, 145), (1_800, 145)], durationSeconds: 1_800).strain)
        let long = try XCTUnwrap(try computeMetrics([(0, 145), (3_600, 145)]).strain)

        XCTAssertEqual(short.points, 60, accuracy: 1e-9)
        XCTAssertEqual(long.points, 120, accuracy: 1e-9)
        XCTAssertLessThan(short, long)
    }

    /// And the other axis: the same half-hour spent harder costs more. 30 min at 168 bpm
    /// is zone 4 — 30 × 4 = 120 points — against 60 for the same half-hour at 145 bpm.
    ///
    /// Note what this pair shows about the unit, and why the type says a big number means
    /// "long, or hard, or both": the hard half-hour and the easy hour both come to 120.
    /// Strain deliberately cannot tell them apart, and `zoneSplits` is what can.
    func testAHarderSessionOfTheSameLengthOutranksAnEasierOne() throws {
        let easy = try XCTUnwrap(try computeMetrics([(0, 145), (1_800, 145)], durationSeconds: 1_800).strain)
        let hard = try XCTUnwrap(try computeMetrics([(0, 168), (1_800, 168)], durationSeconds: 1_800).strain)

        XCTAssertEqual(easy.points, 60, accuracy: 1e-9)
        XCTAssertEqual(hard.points, 120, accuracy: 1e-9)
        XCTAssertLessThan(easy, hard)
    }

    // MARK: - Absence (A18, and MAX-175's invariant)

    /// The load-bearing one, also stated from the rule's side in
    /// `NoJudgementWithoutDataTests`: no curve, no strain. Not a zero — a zero is a
    /// measurement saying the session cost nothing, and it would be averaged into
    /// MAX-178's rolling sums as a real day.
    func testAWorkoutWithNoHeartRateCurveHasNoStrainAtAll() throws {
        let metrics = try computeMetrics(nil)

        XCTAssertNil(metrics.strain)
        XCTAssertFalse(metrics.isRecorded(.strain))
        XCTAssertFalse(metrics.hasHeartRateData)
    }

    /// The other side of the same distinction, and the reading `timeAboveCapSeconds`
    /// already takes of this case: a single sample *is* a curve, it truthfully covers
    /// zero seconds, and the integral over zero seconds is zero. There is a measurement
    /// here; there is just nothing in it.
    func testACurveCoveringNoSpanHasAStrainOfZeroRatherThanNone() throws {
        let metrics = try computeMetrics([(0, 145)])

        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, 0)
        XCTAssertTrue(metrics.isRecorded(.strain))
        XCTAssertTrue(metrics.hasHeartRateData)
    }

    /// The invariant made unrepresentable rather than merely observed: a record cannot be
    /// constructed stating a strain while stating no heart rate, whatever assembles it.
    func testARecordCannotStateAStrainWithoutAHeartRateSeries() throws {
        assertThrows(
            .inconsistent,
            try DerivedMetrics(
                workoutID: Fixture.workoutID,
                strain: WorkoutStrain(points: 120),
                planVersion: PlanVersion(1)
            )
        )
    }

    /// Strain is a cost, and a cost is never negative. NaN and infinity are rejected for
    /// the reason `Validate.finite` exists: they poison every sum computed downstream,
    /// and MAX-178 will be summing these across a month.
    func testStrainRejectsNegativeAndNonFinitePoints() {
        assertThrows(.outOfRange, try WorkoutStrain(points: -1))
        assertThrows(.notFinite, try WorkoutStrain(points: .nan))
        assertThrows(.notFinite, try WorkoutStrain(points: .infinity))
    }

    // MARK: - The lift

    /// A lift has a heart rate, so it has a strain — the one figure of this kind the
    /// record can honestly carry for a session under a barbell (§3.3, A20).
    ///
    /// What the assertions below say together is the limit `WorkoutStrain` documents: the
    /// figure exists, and everything that would tell you *what was lifted* does not.
    /// A later ticket reading this number as "how hard the lift was" in the lifting sense
    /// is reading something the record does not contain.
    func testALiftHasAStrainAndItIsHeartRateOnly() throws {
        let metrics = try computeMetrics(
            [(0, 120), (900, 120), (1_200, 168), (1_500, 168)],
            activityType: .traditionalStrengthTraining,
            durationSeconds: 1_500
        )

        XCTAssertEqual(try XCTUnwrap(metrics.strain).points, 45.9375, accuracy: 1e-9)
        XCTAssertTrue(DerivedMetricKind.strain.applies(to: .traditionalStrengthTraining))
        XCTAssertEqual(DerivedMetricKind.strain.requirement, .anyDiscipline)

        // Nothing about load, because nothing about load was ever captured (A20).
        XCTAssertNil(metrics.averageCadenceStepsPerMinute)
        XCTAssertNil(metrics.timeAboveCapSeconds)
        XCTAssertNil(metrics.distanceSplits)
    }

    // MARK: - Nothing already stored moves

    /// A `DerivedMetrics` payload exactly as a pre-MAX-176 build encoded it: every key the
    /// record carried before this ticket, and no `strain` key anywhere.
    ///
    /// Written out by hand rather than derived from today's encoder, because deriving it
    /// would let a bug in the encoder cancel out a matching bug in the decoder and the
    /// test would still pass — the pattern MAX-129, MAX-131, MAX-133, MAX-149 and MAX-165
    /// each established. The values are `ScoringFixture.metrics()`'s, so the assertion can
    /// be against a record this build builds rather than against a second literal.
    private static let preChangeMetricsJSON = """
        {"averageCadenceStepsPerMinute":167,\
        "averageHeartRateBPM":142,\
        "distanceSplitsComputed":true,\
        "gradeAdjustedPaceSecondsPerKilometer":308,\
        "heartRateDriftFraction":0.03,\
        "maximumHeartRateBPM":158,\
        "planVersion":1,\
        "timeAboveCapSeconds":0,\
        "workoutID":"11111111-1111-1111-1111-111111111111",\
        "zoneSplits":{"splits":[{"seconds":3400,"zone":2}]}}
        """

    /// The `zoneSplitsJSON` column's bytes as a pre-MAX-176 build wrote them. This ticket
    /// adds a column beside this blob and nothing inside it, and that is the claim.
    private static let preChangeZoneSplitsJSON = #"{"splits":[{"seconds":3400,"zone":2}]}"#

    /// The acceptance criterion, stated directly: a record written before this ticket
    /// decodes to a record carrying no strain — which is what "no such field existed"
    /// already meant — and is otherwise identical to what this build produces.
    func testAPreChangeMetricsPayloadDecodesUnchangedWithNoStrain() throws {
        let data = try XCTUnwrap(Self.preChangeMetricsJSON.data(using: .utf8))
        let decoded = try PersistencePayload.decode(DerivedMetrics.self, from: data, field: "test.metrics")

        XCTAssertNil(decoded.strain)
        XCTAssertFalse(decoded.isRecorded(.strain))
        XCTAssertEqual(decoded, try ScoringFixture.metrics())
    }

    /// The encode direction: a record with no strain writes no key this ticket added, so
    /// what goes back to disk for every workout already on the device is what was already
    /// there.
    ///
    /// Key absence rather than a byte-for-byte match against the literal above — CI is
    /// Linux and swift-corelibs-foundation is entitled to render a `Double` differently
    /// from Darwin, so pinning the text would pin the JSON writer, not this ticket.
    func testARecordWithNoStrainEncodesWithoutTheKey() throws {
        let encoded = try PersistencePayload.encode(try ScoringFixture.metrics(), field: "test.metrics")
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(text.contains("strain"))
    }

    /// The stored row, which is where derived metrics actually live: a column per figure
    /// plus two JSON blobs. A row written before this build has the new column as NULL —
    /// SwiftData's lightweight migration adds a nullable attribute exactly that way — and
    /// it must read back as *no strain*, with every other figure untouched.
    func testAPreChangeStoredRowReadsBackUnchangedWithNoStrain() throws {
        let zoneSplitsJSON = try XCTUnwrap(Self.preChangeZoneSplitsJSON.data(using: .utf8))
        let stored = StoredDerivedMetrics(
            workoutUUID: Fixture.workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 158,
            timeAboveCapSeconds: 0,
            heartRateDriftFraction: 0.03,
            averageCadenceStepsPerMinute: 167,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplitsJSON: zoneSplitsJSON,
            strainPoints: nil,
            distanceSplitsJSON: nil,
            distanceSplitsComputed: true,
            planVersionNumber: 1
        )

        let restored = try stored.toDomain()

        XCTAssertNil(restored.strain)
        XCTAssertEqual(restored, try ScoringFixture.metrics())
    }

    /// And the blob is untouched in the other direction: this ticket adds a column beside
    /// the zone-splits payload and nothing inside it, so what this build writes for a
    /// record whose splits have not changed still says exactly what the bytes already on
    /// disk say. A figure that had quietly moved *into* the blob would fail here.
    ///
    /// Compared as decoded values plus the absence of the key, not byte-for-byte: CI is
    /// Linux and swift-corelibs-foundation is entitled to render a `Double` differently
    /// from Darwin, so pinning the text would pin the JSON writer rather than this ticket.
    func testTheZoneSplitsBlobIsUntouchedByThisTicket() throws {
        let stored = try StoredDerivedMetrics(try ScoringFixture.metrics())
        let text = try XCTUnwrap(String(data: stored.zoneSplitsJSON, encoding: .utf8))

        let onDisk = try XCTUnwrap(Self.preChangeZoneSplitsJSON.data(using: .utf8))

        XCTAssertFalse(text.contains("strain"))
        XCTAssertEqual(
            try PersistencePayload.decode(ZoneSplits.self, from: stored.zoneSplitsJSON, field: "test.zones"),
            try PersistencePayload.decode(ZoneSplits.self, from: onDisk, field: "test.zones")
        )
        XCTAssertNil(stored.strainPoints, "a record with no strain stores a NULL column, not a zero")
    }

    /// The ordinary post-MAX-176 case: a computed strain survives the trip to the store
    /// and back as the same number.
    func testAComputedStrainRoundTripsThroughStorage() throws {
        let metrics = try computeMetrics([(0, 120), (3_600, 180)])
        let restored = try StoredDerivedMetrics(metrics).toDomain()

        XCTAssertEqual(restored, metrics)
        XCTAssertEqual(try XCTUnwrap(restored.strain).points, 159, accuracy: 1e-9)
    }

    /// A strain that could not have been produced by any curve is refused on the way out
    /// of the store rather than reaching a tile, the same way an invalid plan version is.
    func testAStoredRowWithAnImpossibleStrainIsRejected() throws {
        var stored = try StoredDerivedMetrics(try ScoringFixture.metrics())
        stored.strainPoints = -1

        assertThrows(.outOfRange, try stored.toDomain())
    }

    // MARK: - The zone model is the one already in the record

    /// D1, restated for this figure: the boundaries strain is cut against are the plan's,
    /// through `HeartRateZoneModel.capAnchored`, and the record says which plan version
    /// produced them. Two caps therefore give the same curve two different strains — as
    /// they must, since "zone 3" means something different under each — and neither is
    /// re-interpreted later.
    func testStrainIsCutAgainstThePlansCapAndSaysWhichVersionItUsed() throws {
        let curve = [(0.0, 120.0), (3_600.0, 180.0)]
        let input = try DerivedMetricsInput(
            workout: try Fixture.workout(hasRoute: false),
            heartRateSeries: try MetricsFixture.series(curve),
            classification: .easy
        )

        let underStandardCap = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan())
        let underHigherCap = try DerivedMetricsCalculator.compute(
            input, plan: try Fixture.plan(version: 4, heartRateCapBPM: 165)
        )

        XCTAssertEqual(underStandardCap.planVersion, try PlanVersion(1))
        XCTAssertEqual(underHigherCap.planVersion, try PlanVersion(4))
        XCTAssertLessThan(
            try XCTUnwrap(underHigherCap.strain),
            try XCTUnwrap(underStandardCap.strain),
            "the same curve is easier work under a higher cap, so it costs fewer zone-weighted minutes"
        )
    }

    /// The zone model is a parameter, not a constant this figure reaches for on its own:
    /// a caller supplying boundaries directly gets strain cut against those.
    func testStrainHonoursAnExplicitlySuppliedZoneModel() throws {
        let input = try DerivedMetricsInput(
            workout: try Fixture.workout(hasRoute: false),
            heartRateSeries: try MetricsFixture.series([(0, 145), (3_600, 145)]),
            classification: .easy
        )

        // 145 bpm sits in zone 2 under the default cap-anchored model and in zone 1 under
        // one whose first boundary is above it: 60 min × 2 = 120 against 60 min × 1 = 60.
        let underPlanZones = try DerivedMetricsCalculator.compute(input, plan: try Fixture.plan())
        let underGivenZones = try DerivedMetricsCalculator.compute(
            input,
            plan: try Fixture.plan(),
            zoneModel: try HeartRateZoneModel(upperBoundsBPM: [150, 160, 170, 180])
        )

        XCTAssertEqual(try XCTUnwrap(underPlanZones.strain).points, 120, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(underGivenZones.strain).points, 60, accuracy: 1e-9)
        XCTAssertEqual(try zones().zone(for: 145), .two)
    }
}
