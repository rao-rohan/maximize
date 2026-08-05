import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-131 / A20: the rubric gains the two words it needs to judge a lift, and nothing
/// else.
///
/// A20 scores a lift on **adherence, not volume** — whether the session the plan asked
/// for happened, on the day, for roughly the prescribed length. Two of those three were
/// already expressible: the day is the day the band is evaluated on, and "it happened"
/// is a band with no metric condition. The two that were not are *which discipline it
/// was* (`RubricCondition.actualDiscipline`) and *how long the plan asked for*
/// (`RubricReference.scheduledDuration`, plus the `ScheduledSession.durationSeconds` it
/// is a fraction of, which is tracker gap **P3**).
///
/// Under D1 a rubric lives inside a versioned plan record, so the first half of this
/// file is the obligation that comes with that: **every rubric already stored decodes to
/// exactly the bands it decoded to before, and `RubricEvaluator` matches the identical
/// band for the identical run.** Hand-written pre-change payloads, in the shape MAX-129
/// used, rather than a round trip that could let an encoder bug cancel a decoder bug.
final class LiftRubricVocabularyTests: XCTestCase {

    // MARK: - Nothing already stored moves

    /// `ScoringFixture.workedExampleRubric()` exactly as a pre-MAX-131 build wrote it:
    /// PRD §10.3's worked example, every band, every condition, every reference.
    ///
    /// These are the bytes inside a `StoredPlan.payloadJSON` on the device. Written out
    /// by hand — deriving it from today's encoder would prove only that the encoder and
    /// the decoder agree with each other.
    private static let preLiftingRubricJSON = """
        {"bands":[\
        {"appliesTo":["easy"],\
        "conditions":[{"actualClassification":{"oneOf":["hard"]}}],\
        "identifier":"easy.ranHardInstead",\
        "rationale":"Ran hard on an easy day.",\
        "scoreRange":{"highest":45,"lowest":20}},\
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
        "conditions":[{"actualClassification":{"oneOf":["easy"]}},\
        {"metric":{"comparison":"lessThanOrEqual","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":0}}}}],\
        "identifier":"easy.onCap.lateDrift",\
        "rationale":"Under cap, but drifted late.",\
        "scoreRange":{"highest":89,"lowest":75}},\
        {"appliesTo":["easy"],\
        "conditions":[{"actualClassification":{"oneOf":["easy"]}},\
        {"metric":{"comparison":"lessThanOrEqual","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":8}}}}],\
        "identifier":"easy.slightlyOverCap",\
        "rationale":"Ran above the easy cap.",\
        "scoreRange":{"highest":74,"lowest":55}},\
        {"appliesTo":["easy"],\
        "conditions":[{"metric":{"comparison":"greaterThan","metric":"averageHeartRateBPM",\
        "reference":{"heartRateCap":{"offsetBPM":8}}}}],\
        "identifier":"easy.wellOverCap",\
        "rationale":"Well above the easy cap for the whole run.",\
        "scoreRange":{"highest":45,"lowest":20}},\
        {"appliesTo":["long"],\
        "conditions":[{"metric":{"comparison":"greaterThanOrEqual","metric":"distanceMeters",\
        "reference":{"scheduledDistance":{"fraction":0.8}}}}],\
        "identifier":"long.completedTheDistance",\
        "rationale":"Covered the prescribed long-run distance.",\
        "scoreRange":{"highest":100,"lowest":75}},\
        {"appliesTo":["hard"],\
        "conditions":[{"metric":{"comparison":"greaterThanOrEqual","metric":"distanceMeters",\
        "reference":{"scheduledDistance":{"fraction":0.8}}}}],\
        "identifier":"hard.executed",\
        "rationale":"Executed the prescribed session.",\
        "scoreRange":{"highest":100,"lowest":75}},\
        {"appliesTo":[],\
        "conditions":[{"noWorkoutRecorded":{}}],\
        "identifier":"skipped",\
        "rationale":"No workout recorded for a scheduled session.",\
        "scoreRange":{"highest":15,"lowest":0}}],\
        "effectiveThreshold":70,"marginalThreshold":45}
        """

    /// The acceptance criterion, stated directly: a rubric written before this ticket
    /// decodes to **exactly** the same bands with exactly the same conditions.
    ///
    /// Asserted with a whole-value `XCTAssertEqual` rather than a spot check on
    /// identifiers, because the thing at risk is a *condition* silently changing shape,
    /// which an identifier comparison would sail straight past.
    func testAPreLiftingRubricPayloadDecodesToIdenticalBands() throws {
        let data = try XCTUnwrap(Self.preLiftingRubricJSON.data(using: .utf8))
        let decoded = try PersistencePayload.decode(
            ScoringRubric.self,
            from: data,
            field: "test.rubric"
        )

        XCTAssertEqual(decoded, try ScoringFixture.workedExampleRubric())

        // Order is part of a rubric's meaning (first match wins), so it is worth saying
        // separately rather than trusting the value comparison to have covered it.
        XCTAssertEqual(
            decoded.bands.map(\.identifier),
            try ScoringFixture.workedExampleRubric().bands.map(\.identifier)
        )
    }

    /// D1, restated as a test: the same run under a rubric decoded from pre-change bytes
    /// and under the same rubric this build authored matches the same band, with the
    /// same permitted range — for every row of §10.3, not one of them.
    func testTheSameRunMatchesTheSameBandUnderAPreLiftingRubric() throws {
        let data = try XCTUnwrap(Self.preLiftingRubricJSON.data(using: .utf8))
        let reloaded = try PersistencePayload.decode(
            ScoringRubric.self,
            from: data,
            field: "test.rubric"
        )
        let authored = try ScoringFixture.workedExampleRubric()

        // One row of §10.3 per case: the day it falls on, what it was classified as, the
        // heart rate that decides which side of the cap it lands on, and the distance
        // the long-run row is judged against.
        let runs: [(
            day: String,
            classification: WorkoutClassification,
            averageBPM: Double,
            drift: Double,
            distanceMeters: Double
        )] = [
            (ScoringFixture.easyDay, .easy, 142, 0.03, 10_000),
            (ScoringFixture.easyDay, .easy, 142, 0.081, 10_000),
            (ScoringFixture.easyDay, .easy, 155, 0.02, 10_000),
            (ScoringFixture.easyDay, .easy, 160, 0.02, 10_000),
            (ScoringFixture.easyDay, .hard, 168, 0.02, 10_000),
            (ScoringFixture.longDay, .long, 148, 0.04, 18_000),
        ]

        for run in runs {
            let metrics = try ScoringFixture.metrics(
                averageHeartRateBPM: run.averageBPM,
                heartRateDriftFraction: run.drift
            )
            func band(under rubric: ScoringRubric) throws -> RubricEvaluation {
                try RubricEvaluator.evaluate(
                    ScoringFixture.context(
                        on: run.day,
                        classification: run.classification,
                        metrics: metrics,
                        distanceMeters: run.distanceMeters,
                        rubric: rubric
                    )
                )
            }
            let before = try band(under: reloaded)
            let after = try band(under: authored)
            XCTAssertEqual(
                before.band,
                after.band,
                "\(run.day) / \(run.classification) / \(run.averageBPM) bpm changed band"
            )
        }
    }

    /// `.scheduledDistance` is the reference MAX-131 came closest to disturbing, so it
    /// gets its own assertion rather than riding on the band-identity test above.
    ///
    /// The ticket removed `Plan.resolve`'s `scheduledDistanceMeters:` **parameter** — a
    /// Swift argument label, which has never appeared on the wire — and left the stored
    /// `RubricReference.scheduledDistance(fraction:)` and its multiplication untouched.
    /// This pins the consequence that matters: a band decoded from a **pre-change
    /// payload** resolves to the identical concrete threshold, so a fractional
    /// prescription still means the metres it always meant and no historical score moves
    /// (D1).
    ///
    /// It also pins the arc case, which is where a fraction is least obviously
    /// replaceable by a stored absolute: the distance resolved for the day comes from
    /// `PlanCalendar`'s arc substitution, and 0.8 of it is what the band tests.
    func testAStoredFractionalDistanceStillResolvesToTheSameMetres() throws {
        let data = try XCTUnwrap(Self.preLiftingRubricJSON.data(using: .utf8))
        let reloaded = try PersistencePayload.decode(
            ScoringRubric.self,
            from: data,
            field: "test.rubric"
        )
        let band = try XCTUnwrap(reloaded.band(identifiedBy: "long.completedTheDistance"))
        guard case let .metric(_, _, reference) = try XCTUnwrap(band.conditions.first) else {
            return XCTFail("the stored long-run band no longer carries a metric condition")
        }
        XCTAssertEqual(reference, .scheduledDistance(fraction: 0.8), "the stored reference itself")

        // Resolved against the day's ask as the evaluator resolves it. Deliberately the
        // week-1 Sunday: the arc prescribes 16 km there while the template's own
        // fallback says 18 km, so this asserts the *arc-derived* distance rather than a
        // number that would look right either way.
        let plan = try ScoringFixture.plan(rubric: reloaded)
        let sunday = try XCTUnwrap(
            try PlanCalendar([plan]).planDay(on: try CalendarDay(iso8601: "2026-01-04"))
        )
        XCTAssertEqual(sunday.scheduledSession.kind, .long)
        XCTAssertEqual(sunday.scheduledSession.distanceMeters, 16_000, "the arc's week 1, not 18 km")
        XCTAssertEqual(
            try XCTUnwrap(plan.resolve(reference, against: sunday.scheduledSession)),
            12_800,
            accuracy: 0.000_001,
            "0.8 of the arc-derived 16 km, exactly as before MAX-131"
        )
    }

    /// The other half of "nothing stored moves": a `ScheduledSession` written before
    /// this ticket decodes to a session prescribing no duration — which is what it
    /// always meant — and one carrying no duration writes no key for it, so the bytes of
    /// every stored plan and of every stored `Score`'s prescription (immutable under D8)
    /// stay exactly as they are.
    func testAPreLiftingScheduledSessionPayloadIsUnchangedInBothDirections() throws {
        let json = #"{"distanceMeters":8000,"kind":"easy"}"#
        let decoded = try PersistencePayload.decode(
            ScheduledSession.self,
            from: try XCTUnwrap(json.data(using: .utf8)),
            field: "test.session"
        )
        XCTAssertEqual(decoded, try ScheduledSession(kind: .easy, distanceMeters: 8_000))
        XCTAssertNil(decoded.durationSeconds)

        // Key absence rather than a byte-for-byte match, for MAX-129's reason: CI is
        // Linux and swift-corelibs-foundation is entitled to render a `Double`
        // differently from Darwin, so pinning the text would pin the JSON writer.
        let reEncoded = try XCTUnwrap(
            String(
                data: try PersistencePayload.encode(decoded, field: "test.session"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(reEncoded.contains("durationSeconds"))

        // And a plan that prescribes no duration anywhere — which is every plan on disk.
        let plan = try XCTUnwrap(
            String(
                data: try PersistencePayload.encode(try ScoringFixture.plan(), field: "test.plan"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(plan.contains("durationSeconds"))
    }

    // MARK: - The new vocabulary, on the wire

    func testTheNewConditionAndReferenceSurviveARoundTrip() throws {
        let conditions: [RubricCondition] = [
            .actualDiscipline(oneOf: [.lift]),
            .actualDiscipline(oneOf: [.run, .lift]),
            .actualDiscipline(oneOf: []),
        ]
        for condition in conditions {
            let encoded = try PersistencePayload.encode(condition, field: "test.condition")
            XCTAssertEqual(
                try PersistencePayload.decode(
                    RubricCondition.self,
                    from: encoded,
                    field: "test.condition"
                ),
                condition
            )
        }

        let reference = RubricReference.scheduledDuration(fraction: 0.7)
        let encoded = try PersistencePayload.encode(reference, field: "test.reference")
        XCTAssertEqual(
            try PersistencePayload.decode(RubricReference.self, from: encoded, field: "test.reference"),
            reference
        )
    }

    // MARK: - `.actualDiscipline`

    /// The condition reads the workout's activity type, not the classifier's answer.
    ///
    /// This is the whole reason the case exists rather than
    /// `.actualClassification(oneOf: [.lift])`: `WorkoutClassifier` short-circuits every
    /// non-run to `.other`, so the lift below is classified `.other` — exactly as
    /// production classifies it today — and the band still matches.
    func testActualDisciplineMatchesTheWorkoutsDisciplineNotItsClassification() throws {
        let rubric = try Self.rubric(
            named: "lift.happened",
            conditions: [.actualDiscipline(oneOf: [.lift])]
        )

        let onALift = try Self.evaluate(rubric: rubric, workout: Self.lift(), classification: .other)
        XCTAssertEqual(onALift.band.identifier, "lift.happened")

        let onARun = try Self.evaluate(rubric: rubric, workout: try Fixture.workout())
        XCTAssertEqual(onARun.band.identifier, "fallback.recorded")
    }

    /// "One of []" is not a statement any workout satisfies — the same rule
    /// `.actualClassification` already follows, said again because a band meant to apply
    /// unconditionally says so by carrying no conditions at all.
    func testAnEmptyDisciplineListMatchesNothing() throws {
        let rubric = try Self.rubric(named: "never", conditions: [.actualDiscipline(oneOf: [])])

        XCTAssertEqual(
            try Self.evaluate(rubric: rubric, workout: try Fixture.workout()).band.identifier,
            "fallback.recorded"
        )
        XCTAssertEqual(
            try Self.evaluate(rubric: rubric, workout: Self.lift(), classification: .other)
                .band.identifier,
            "fallback.recorded"
        )
    }

    /// The `easy.wellOverCap` shadow, and the point of the whole ticket.
    ///
    /// The seed's band carries one condition — average HR above cap + 8 — and nothing
    /// about what was actually done, which is how a hard lifting session on an easy-run
    /// Tuesday came to be permanently recorded as 20–45, *"Well above the easy cap for
    /// the whole run."* (A21). The first half of this test reproduces that. The second
    /// half shows the vocabulary makes it avoidable: the identical band, plus
    /// `.actualDiscipline(oneOf: [.run])`, cannot fire on a lift.
    ///
    /// **This changes no behaviour.** MAX-132 is the ticket that writes the condition
    /// into `StandardPlanSeed`; both rubrics here are authored by this test.
    func testADisciplineConditionMakesTheWellOverCapShadowUnwritable() throws {
        let liftWithAHighHeartRate = try Self.lift()
        let metrics = try Self.liftMetrics(averageHeartRateBPM: 162)

        let asSeeded = try ScoringFixture.workedExampleRubric()
        let shadowed = try Self.evaluate(
            rubric: asSeeded,
            workout: liftWithAHighHeartRate,
            classification: .other,
            metrics: metrics
        )
        XCTAssertEqual(
            shadowed.band.identifier,
            "easy.wellOverCap",
            "the defect A21 records: a lift matching an easy-run band"
        )

        var guardedBands: [RubricBand] = try asSeeded.bands.map { band in
            guard band.identifier == "easy.wellOverCap" else { return band }
            return try RubricBand(
                identifier: band.identifier,
                appliesTo: band.appliesTo,
                conditions: [.actualDiscipline(oneOf: [.run])] + band.conditions,
                scoreRange: band.scoreRange,
                rationale: band.rationale
            )
        }
        guardedBands.append(try Self.fallbackBand())
        let guarded = try ScoringRubric(
            effectiveThreshold: asSeeded.effectiveThreshold,
            marginalThreshold: asSeeded.marginalThreshold,
            bands: guardedBands
        )
        XCTAssertNotEqual(
            try Self.evaluate(
                rubric: guarded,
                workout: liftWithAHighHeartRate,
                classification: .other,
                metrics: metrics
            ).band.identifier,
            "easy.wellOverCap"
        )

        // And the run the band was written about is judged exactly as before.
        XCTAssertEqual(
            try Self.evaluate(
                rubric: guarded,
                workout: try Fixture.workout(),
                metrics: try ScoringFixture.metrics(averageHeartRateBPM: 160)
            ).band.identifier,
            "easy.wellOverCap"
        )
    }

    // MARK: - `.scheduledDuration` and the plan's first duration

    func testScheduledDurationResolvesAsAFractionOfTheAsk() throws {
        let plan = try ScoringFixture.plan()
        let ask = try ScheduledSession(kind: .lift, durationSeconds: 2_700)

        XCTAssertEqual(
            try XCTUnwrap(plan.resolve(.scheduledDuration(fraction: 0.7), against: ask)),
            1_890,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(plan.resolve(.scheduledDuration(fraction: 1), against: ask)),
            2_700,
            accuracy: 0.000_001
        )

        // No duration in the ask is an unresolvable right-hand side, exactly as a
        // `.scheduledDistance` is on a day with no prescribed distance.
        XCTAssertNil(
            plan.resolve(.scheduledDuration(fraction: 0.7), against: try ScheduledSession(kind: .lift))
        )
        XCTAssertNil(plan.resolve(.scheduledDuration(fraction: 0.7)))

        // The reference the duration one is modelled on still means what it meant.
        XCTAssertEqual(
            try XCTUnwrap(
                plan.resolve(
                    .scheduledDistance(fraction: 0.8),
                    against: try ScheduledSession(kind: .long, distanceMeters: 10_000)
                )
            ),
            8_000,
            accuracy: 0.000_001
        )
    }

    /// A20's adherence judgement, end to end through the evaluator: a session of at
    /// least 70% of the prescribed length takes the band, a short one falls past it.
    ///
    /// Written on the **run** slot, because `RubricEvaluator` still reads
    /// `planDay.scheduledSession` for every workout — MAX-133 is the ticket that matches
    /// a workout to its own discipline's ask, and nothing here pretends otherwise. What
    /// is being pinned is the vocabulary, which is discipline-agnostic.
    func testABandCanRequireAFractionOfThePrescribedDuration() throws {
        let rubric = try Self.rubric(
            named: "session.longEnough",
            conditions: [
                .metric(
                    metric: .durationSeconds,
                    comparison: .greaterThanOrEqual,
                    reference: .scheduledDuration(fraction: 0.7)
                ),
            ]
        )
        // Tuesday's ask, with a prescribed 45 minutes on it.
        let template = try WeeklyTemplate([
            .monday: .rest,
            .tuesday: ScheduledSession(kind: .easy, distanceMeters: 8_000, durationSeconds: 2_700),
            .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
            .thursday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .friday: .rest,
            .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
            .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000),
        ])

        // 40 minutes against a 45-minute ask: 0.89 of it, over the 0.7 floor.
        XCTAssertEqual(
            try Self.evaluate(
                rubric: rubric,
                weeklyTemplate: template,
                workout: try Fixture.workout(durationSeconds: 2_400)
            ).band.identifier,
            "session.longEnough"
        )

        // 20 minutes: 0.44 of it, under the floor.
        XCTAssertEqual(
            try Self.evaluate(
                rubric: rubric,
                weeklyTemplate: template,
                workout: try Fixture.workout(durationSeconds: 1_200)
            ).band.identifier,
            "fallback.recorded"
        )

        // And a day whose ask states no duration: unresolvable, so no match, rather than
        // a band firing on a comparison against a number nobody prescribed.
        XCTAssertEqual(
            try Self.evaluate(
                rubric: rubric,
                workout: try Fixture.workout(durationSeconds: 2_400)
            ).band.identifier,
            "fallback.recorded"
        )
    }

    // MARK: - `ScheduledSession.durationSeconds`

    func testARestDayCannotCarryADurationAndADurationMustBePositive() throws {
        assertThrows(.inconsistent, try ScheduledSession(kind: .rest, durationSeconds: 2_700))
        assertThrows(.outOfRange, try ScheduledSession(kind: .lift, durationSeconds: 0))
        assertThrows(.outOfRange, try ScheduledSession(kind: .lift, durationSeconds: -60))

        // Legal on any prescribed kind: the field is about what a plan may *say*, and
        // "45 minutes easy" is a sentence a plan says.
        XCTAssertNoThrow(try ScheduledSession(kind: .lift, durationSeconds: 2_700))
        XCTAssertNoThrow(try ScheduledSession(kind: .easy, durationSeconds: 2_700))

        // And unstated stays expressible on a lift, which is a different statement from
        // `.rest` — see the field's note.
        XCTAssertNil(try ScheduledSession(kind: .lift).durationSeconds)
    }

    /// `PlanDraft.init(_:)` is documented as lossless, and the run slot is the half that
    /// gets decomposed into parts and reassembled — so a duration on it must survive a
    /// revision. Without the carry-forward, changing the HR cap would silently delete it.
    func testARevisionCarriesAPrescribedDurationForward() throws {
        let template = try WeeklyTemplate([
            .monday: .rest,
            .tuesday: ScheduledSession(kind: .easy, distanceMeters: 8_000, durationSeconds: 2_700),
            .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
            .thursday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .friday: .rest,
            .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
            .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000),
        ], lift: [.tuesday: ScheduledSession(kind: .lift, durationSeconds: 3_600)])
        let draft = try PlanDraft(try Self.plan(weeklyTemplate: template))

        let tuesday = try XCTUnwrap(draft.week.first { $0.weekday == .tuesday })
        XCTAssertEqual(tuesday.durationSeconds, 2_700)
        XCTAssertEqual(try tuesday.session().durationSeconds, 2_700)
        XCTAssertEqual(try tuesday.liftSession().durationSeconds, 3_600)
    }

    /// The arc rebuilds a long-run session to substitute its distance. Everything else
    /// on that session is the template's and has to be carried across; `durationSeconds`
    /// is the first field the rebuild could have dropped.
    func testTheArcSubstitutionKeepsAPrescribedDuration() throws {
        let template = try WeeklyTemplate([
            .monday: .rest,
            .tuesday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
            .thursday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .friday: .rest,
            .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
            .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000, durationSeconds: 7_200),
        ])
        let calendar = try PlanCalendar([try Self.plan(weeklyTemplate: template)])
        let sunday = try XCTUnwrap(
            try calendar.planDay(on: try CalendarDay(iso8601: ScoringFixture.longDay))
        )

        XCTAssertEqual(sunday.scheduledSession.distanceMeters, 18_000, "the arc's week 2")
        XCTAssertEqual(sunday.scheduledSession.durationSeconds, 7_200)
    }

    // MARK: - Scaffolding

    /// A strength workout, as HealthKit records one: no distance, no route.
    private static func lift() throws -> Workout {
        try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            durationSeconds: 2_700,
            distanceMeters: nil,
            hasRoute: false
        )
    }

    /// What MAX-130 leaves on a lift: average heart rate, maximum heart rate, zone
    /// splits. Nothing else — no cadence, no cap figure, no drift, no pace.
    private static func liftMetrics(averageHeartRateBPM: Double) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: averageHeartRateBPM + 16,
            zoneSplits: ZoneSplits(splits: [
                ZoneSplits.Split(zone: .three, seconds: 2_000),
            ]),
            planVersion: PlanVersion(1)
        )
    }

    /// One band under test, followed by an unconditional catch-all — so "did not match"
    /// is a readable band identifier rather than a thrown `noBandMatched`.
    private static func rubric(
        named identifier: String,
        conditions: [RubricCondition]
    ) throws -> ScoringRubric {
        try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: identifier,
                    conditions: conditions,
                    scoreRange: ScoreRange(lowest: 75, highest: 100),
                    rationale: "Met the ask."
                ),
                fallbackBand(),
            ]
        )
    }

    /// `StandardPlanSeed`'s shape of last row: unconditional, so it always matches.
    private static func fallbackBand() throws -> RubricBand {
        try RubricBand(
            identifier: "fallback.recorded",
            scoreRange: ScoreRange(lowest: 40, highest: 69),
            rationale: "A session was recorded."
        )
    }

    private static func plan(
        weeklyTemplate: WeeklyTemplate,
        rubric: ScoringRubric? = nil
    ) throws -> Plan {
        let resolvedRubric = try rubric ?? ScoringFixture.workedExampleRubric()
        return try Plan(
            version: PlanVersion(1),
            effectiveFrom: CalendarDay(iso8601: "2026-01-01"),
            weeklyTemplate: weeklyTemplate,
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: resolvedRubric,
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    /// Evaluated through the real context builder (D3), on `easyDay` unless a caller
    /// says otherwise, so these tests exercise the assembly the app will.
    private static func evaluate(
        rubric: ScoringRubric,
        weeklyTemplate: WeeklyTemplate? = nil,
        workout: Workout,
        classification: WorkoutClassification = .easy,
        metrics: DerivedMetrics? = nil,
        on day: String = ScoringFixture.easyDay
    ) throws -> RubricEvaluation {
        let template = try weeklyTemplate ?? Fixture.weeklyTemplate()
        let resolvedMetrics = try metrics ?? ScoringFixture.metrics()
        return try RubricEvaluator.evaluate(
            WorkoutContextBuilder.build(
                workout: workout,
                on: CalendarDay(iso8601: day),
                metrics: resolvedMetrics,
                classification: classification,
                planCalendar: PlanCalendar([plan(weeklyTemplate: template, rubric: rubric)]),
                audience: .scoring,
                existingScore: nil
            )
        )
    }
}
