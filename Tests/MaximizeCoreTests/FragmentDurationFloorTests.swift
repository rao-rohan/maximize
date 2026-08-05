import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-149 / LIFTING-SPEC §9.2: closes the classifier half of tracker gap **P3**.
///
/// `WorkoutClassifier.isFragment` tested distance only, so a mis-started or
/// accidentally split treadmill run — heart-rate data, no distance sample — passed the
/// fragment test and reached the scorer as a real session. `Plan.minimumSessionDurationSeconds`
/// is the duration floor for exactly that case: a workout with no distance to test is
/// now tested on duration instead. A workout that *does* carry a distance is judged on
/// distance only, unchanged from before this ticket.
///
/// Under D1 the floor is data on the plan version, not a code constant — see the doc
/// comment on `Plan.minimumSessionDurationSeconds` for the argument against filing it
/// into `WorkoutClassificationPolicy` instead. The first half of this file is the
/// obligation that comes with adding a field to `Plan`: **every plan already stored
/// decodes to a plan that states no floor**, which is what it already meant, and a plan
/// that states no floor re-encodes to the bytes it already wrote. Hand-written, in the
/// shape MAX-129 and MAX-131 used, rather than a round trip that could let an encoder
/// bug cancel out a matching decoder bug.
final class FragmentDurationFloorTests: XCTestCase {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    // MARK: - Nothing already stored moves

    /// `Fixture.plan()` exactly as a pre-MAX-149 build wrote it: every key `Plan`
    /// carried before this ticket, and no `minimumSessionDurationSeconds` key anywhere.
    ///
    /// These are the bytes inside a `StoredPlan.payloadJSON` on the device. Written out
    /// by hand rather than derived from today's encoder, because deriving it would let a
    /// bug in the encoder cancel out a matching bug in the decoder and the test would
    /// still pass.
    private static let preChangePlanJSON = """
        {"version":1,\
        "effectiveFrom":"2026-01-01",\
        "weeklyTemplate":{"entries":[\
        {"session":{"kind":"rest"},"weekday":1},\
        {"session":{"distanceMeters":8000,"kind":"easy"},"weekday":2},\
        {"session":{"kind":"hard","note":"6 × 800m"},"weekday":3},\
        {"session":{"distanceMeters":8000,"kind":"easy"},"weekday":4},\
        {"session":{"kind":"rest"},"weekday":5},\
        {"session":{"distanceMeters":6000,"kind":"easy"},"weekday":6},\
        {"session":{"distanceMeters":18000,"kind":"long"},"weekday":7}\
        ]},\
        "longRunArc":{"weeks":[\
        {"distanceMeters":16000,"index":1},\
        {"distanceMeters":18000,"index":2},\
        {"distanceMeters":20000,"index":3}\
        ]},\
        "heartRateCapBPM":150,\
        "cadenceTarget":{"highStepsPerMinute":170,"lowStepsPerMinute":165},\
        "rubric":{"bands":[\
        {"appliesTo":["easy"],\
        "conditions":[{"actualClassification":{"oneOf":["easy"]}},\
        {"metric":{"comparison":"lessThanOrEqual","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":0}}}},\
        {"metric":{"comparison":"lessThan","metric":"heartRateDriftFraction",\
        "reference":{"constant":{"_0":0.05}}}}],\
        "identifier":"easy.onCap.lowDrift",\
        "rationale":"Held the cap with minimal drift.",\
        "scoreRange":{"highest":100,"lowest":90}},\
        {"appliesTo":["easy"],\
        "conditions":[{"metric":{"comparison":"lessThanOrEqual","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":0}}}}],\
        "identifier":"easy.onCap.lateDrift",\
        "rationale":"Under cap, but drifted late.",\
        "scoreRange":{"highest":89,"lowest":75}},\
        {"appliesTo":["easy"],\
        "conditions":[{"metric":{"comparison":"lessThanOrEqual","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":8}}}}],\
        "identifier":"easy.slightlyOverCap",\
        "rationale":"Ran above the easy cap.",\
        "scoreRange":{"highest":74,"lowest":55}},\
        {"appliesTo":["easy"],\
        "conditions":[{"actualClassification":{"oneOf":["hard"]}}],\
        "identifier":"easy.ranHardInstead",\
        "rationale":"Ran hard on an easy day.",\
        "scoreRange":{"highest":45,"lowest":20}},\
        {"appliesTo":[],\
        "conditions":[{"noWorkoutRecorded":{}}],\
        "identifier":"skipped",\
        "rationale":"No workout recorded for a scheduled session.",\
        "scoreRange":{"highest":15,"lowest":0}}\
        ],"effectiveThreshold":70,"marginalThreshold":45},\
        "goals":{"statements":["Run a sub-4:00 marathon"],"targetDay":"2026-04-20"}}
        """

    /// The acceptance criterion, stated directly: a plan written before this ticket
    /// decodes to a plan carrying no floor — which is what "no such field existed"
    /// already meant — and is otherwise byte-for-byte the plan this build authors.
    func testAPreChangePlanPayloadDecodesToAnIdenticalPlanWithNoFloor() throws {
        let data = try XCTUnwrap(Self.preChangePlanJSON.data(using: .utf8))
        let decoded = try PersistencePayload.decode(Plan.self, from: data, field: "test.plan")

        XCTAssertNil(decoded.minimumSessionDurationSeconds)
        XCTAssertEqual(decoded, try Fixture.plan())
    }

    /// The encode direction: a plan that states no floor writes no key this ticket
    /// added, so what goes back to disk for every plan already on the device is what
    /// was already there.
    ///
    /// Key absence rather than a byte-for-byte match against the literal above — CI is
    /// Linux and swift-corelibs-foundation is entitled to render a `Double` differently
    /// from Darwin, so pinning the text would pin the JSON writer, not this ticket.
    func testAPlanWithNoFloorEncodesWithoutTheKey() throws {
        let encoded = try PersistencePayload.encode(try Fixture.plan(), field: "test.plan")
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("minimumSessionDurationSeconds"))
    }

    /// D1, restated as a test: the same distance-based fragment call reads the same
    /// answer under a plan decoded from pre-change bytes and under the plan this build
    /// authors — the floor this ticket adds plays no part in a workout that already had
    /// a distance to be tested against.
    func testTheSameFragmentCallMatchesUnderAPreChangePlan() throws {
        let data = try XCTUnwrap(Self.preChangePlanJSON.data(using: .utf8))
        let reloaded = try PersistencePayload.decode(Plan.self, from: data, field: "test.plan")

        let workout = try runWorkout(durationSeconds: 240, distanceMeters: 900)
        let metrics = try metrics(zones: [(.one, 120), (.two, 120)])

        let before = try WorkoutClassifier.classify(
            workout, metrics: metrics, plan: reloaded, timeZone: Self.utc
        )
        let after = try WorkoutClassifier.classify(
            workout, metrics: metrics, plan: try Fixture.plan(), timeZone: Self.utc
        )
        XCTAssertEqual(before, after)
        XCTAssertEqual(before, .other)
    }

    // MARK: - The floor itself is validated plan data

    func testAFloorMustBePositive() throws {
        assertThrows(.outOfRange, try Fixture.plan(minimumSessionDurationSeconds: 0))
        assertThrows(.outOfRange, try Fixture.plan(minimumSessionDurationSeconds: -60))
    }

    func testAFloorSurvivesARoundTrip() throws {
        let plan = try Fixture.plan(minimumSessionDurationSeconds: 600)
        let encoded = try PersistencePayload.encode(plan, field: "test.plan")
        let decoded = try PersistencePayload.decode(Plan.self, from: encoded, field: "test.plan")
        XCTAssertEqual(decoded.minimumSessionDurationSeconds, 600)
    }

    // MARK: - The classifier gap this ticket closes

    /// The ticket's central case: a mis-started or accidentally split treadmill run —
    /// heart-rate data, no distance sample, well under the plan's floor. Before this
    /// ticket it reached the scorer as a real session; now it does not.
    func testAnHROnlyNoDistanceShortWorkoutIsAFragmentWhenThePlanStatesAFloor() throws {
        let plan = try Fixture.plan(minimumSessionDurationSeconds: 600)
        let workout = try runWorkout(durationSeconds: 240, distanceMeters: nil)
        let classification = try WorkoutClassifier.classify(
            workout,
            metrics: try metrics(zones: [(.one, 120), (.two, 120)]),
            plan: plan,
            timeZone: Self.utc
        )
        XCTAssertEqual(classification, .other)
    }

    /// A real short run recorded with no distance — an indoor track with no GPS lock,
    /// say — that clears the floor is still a run, not a fragment.
    func testARealShortRunWithNoDistanceAboveTheFloorIsNotAFragment() throws {
        let plan = try Fixture.plan(minimumSessionDurationSeconds: 600)
        let workout = try runWorkout(durationSeconds: 900, distanceMeters: nil)
        let classification = try WorkoutClassifier.classify(
            workout,
            metrics: try metrics(zones: [(.one, 300), (.two, 600)]),
            plan: plan,
            timeZone: Self.utc
        )
        XCTAssertEqual(classification, .easy)
    }

    /// A plan that states no opinion on the floor asks no duration question at all — the
    /// same "no guessed threshold" rule `isFragment`'s distance test already followed
    /// for a plan whose template prescribed no distance. The same thirty-second,
    /// no-distance workout that `testAnHROnlyNoDistanceShortWorkoutIsAFragmentWhenThePlanStatesAFloor`
    /// rejects is read normally here — the floor is a plan opting in, not an implicit
    /// default this ticket switched on for every plan on disk.
    func testADistancelessShortWorkoutGetsNoFragmentTestWhenThePlanStatesNoFloor() throws {
        let workout = try runWorkout(durationSeconds: 30, distanceMeters: nil)
        let classification = try WorkoutClassifier.classify(
            workout,
            metrics: try metrics(zones: [(.one, 15), (.two, 15)]),
            plan: try Fixture.plan(),
            timeZone: Self.utc
        )
        XCTAssertEqual(classification, .easy)
    }

    /// A run that carries a distance is judged on distance only. A duration floor
    /// calibrated for "did this session happen at all" does not get to overrule a run
    /// whose recorded distance already answered that question — even one set high
    /// enough that the same workout's *duration* would have failed it.
    func testADistanceCarryingRunIsUnaffectedByAFloorThatWouldAlsoCatchItOnDuration() throws {
        // 900 s / 2 500 m clears the fragment *distance* line (1 500 m, per
        // `WorkoutClassifierTests`' header) but would fail a 3 000 s duration floor.
        let plan = try Fixture.plan(minimumSessionDurationSeconds: 3_000)
        let workout = try runWorkout(durationSeconds: 900, distanceMeters: 2_500)
        let classification = try WorkoutClassifier.classify(
            workout,
            metrics: try metrics(zones: [(.two, 900)]),
            plan: plan,
            timeZone: Self.utc
        )
        XCTAssertEqual(classification, .easy)
    }

    /// A lift has no distance by definition, and the floor must not read that as
    /// "untestable, fall back to duration" and flag every strength session as a
    /// fragment. It does not reach `isFragment` at all — `WorkoutClassifier.classify`
    /// answers `.other` for any non-run before the fragment test runs — and this pins
    /// that a floor aggressive enough to catch a 45-minute lift changes nothing about
    /// the answer.
    func testALiftIsNeverClassifiedAsAFragmentByTheDurationFloor() throws {
        let plan = try Fixture.plan(minimumSessionDurationSeconds: 3_600)
        let workout = try runWorkout(
            activityType: .traditionalStrengthTraining,
            durationSeconds: 2_700,
            distanceMeters: nil
        )
        let classification = try WorkoutClassifier.classify(
            workout,
            metrics: try metrics(zones: [(.two, 1_800)]),
            plan: plan,
            timeZone: Self.utc
        )
        XCTAssertEqual(classification, .other)
    }

    // MARK: - Fixtures local to this file

    private func runWorkout(
        activityType: ActivityType = .running,
        durationSeconds: Double,
        distanceMeters: Double?
    ) throws -> Workout {
        try Workout(
            id: Fixture.workoutID,
            activityType: activityType,
            start: Fixture.epoch,
            end: Fixture.epoch.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 400,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: Fixture.epoch.addingTimeInterval(durationSeconds + 60)
        )
    }

    private func metrics(zones: [(HeartRateZone, Double)]) throws -> DerivedMetrics {
        var splits: [ZoneSplits.Split] = []
        for (zone, seconds) in zones {
            splits.append(try ZoneSplits.Split(zone: zone, seconds: seconds))
        }
        let aboveCap = zones.filter { $0.0 >= .three }.reduce(0) { $0 + $1.1 }
        return try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 140,
            maximumHeartRateBPM: 155,
            timeAboveCapSeconds: aboveCap,
            zoneSplits: ZoneSplits(splits: splits),
            planVersion: PlanVersion(1)
        )
    }
}
