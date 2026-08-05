import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-133 / A17: a workout is judged against **its own discipline's ask**.
///
/// `RubricEvaluator` used to resolve every workout against `planDay.scheduledSession` —
/// the run slot — whatever the workout was. It now resolves
/// `planDay.scheduledSession(for:)` on the workout's own discipline, which is the single
/// line LIFTING-SPEC §5 asks for and the one that makes MAX-132's lift bands reachable at
/// all: `RubricBand.appliesTo` filters on the *scheduled* kind, so a lift that is shown
/// the easy-run day's ask can only ever match easy-run bands.
///
/// ## What this file has to prove, in two directions
///
/// - **The new behaviour**: a lift on a day prescribing both takes the lift ask, the run
///   on that same day still takes the run ask, and an ask-relative reference resolves
///   against the same slot the bands were filtered by.
/// - **That nothing already scored moves.** Every plan on disk prescribes rest on every
///   lift slot and every workout already scored is a run, so the claim that matters is
///   that a single-discipline day is byte-identical. It is asserted the only way that is
///   honest: against the expression the pre-MAX-133 evaluator actually used
///   (`planDay.scheduledSession`), row by row, through to the encoded `Score`.
///
/// Every rubric here is authored by this file. `StandardPlanSeed` is MAX-132's, and a
/// regression suite that pinned the seed's band identifiers would break that ticket for
/// reasons that have nothing to do with routing.
final class DisciplineMatchedEvaluationTests: XCTestCase {

    // MARK: - A day that prescribes both

    /// The normal Tuesday: an easy 8 km *and* a 45-minute lift. The lift is judged
    /// against the lift ask.
    ///
    /// The heart rate is deliberately 162 — above this plan's cap + 8 — so that
    /// `easy.wellOverCap`, the A21 band that carries no condition on what was performed,
    /// *would* fire if the lift were still shown the run day's bands. It cannot be shown
    /// them, which is the whole ticket.
    func testALiftOnADayPrescribingBothIsJudgedAgainstTheLiftAsk() throws {
        let evaluation = try Self.evaluate(
            workout: Self.lift(durationSeconds: 2_700),
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 162)
        )

        XCTAssertEqual(evaluation.discipline, .lift)
        XCTAssertEqual(evaluation.scheduledSession.kind, .lift)
        XCTAssertEqual(evaluation.scheduledSession.durationSeconds, 2_700)
        XCTAssertEqual(evaluation.scheduledSession.muscleGroups, [.chest, .shoulders])
        XCTAssertEqual(evaluation.band.identifier, "lift.metTheAsk")
        XCTAssertNotEqual(
            evaluation.band.identifier,
            "easy.wellOverCap",
            "a lift must never be shown the run day's bands (A21)"
        )
    }

    /// The same day, the same plan version, the run: unchanged, and judged against the
    /// run ask.
    func testARunOnADayPrescribingBothIsJudgedAgainstTheRunAsk() throws {
        let evaluation = try Self.evaluate(
            workout: try Fixture.workout(),
            classification: .easy,
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142)
        )

        XCTAssertEqual(evaluation.discipline, .run)
        XCTAssertEqual(evaluation.scheduledSession.kind, .easy)
        XCTAssertEqual(evaluation.scheduledSession.distanceMeters, 8_000)
        XCTAssertEqual(evaluation.band.identifier, "easy.onCap")

        // And the two evaluations of the one day disagree about the ask, which is the
        // point: one day, two obligations, judged separately (A17/A19).
        let lift = try Self.evaluate(
            workout: Self.lift(durationSeconds: 2_700),
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 162)
        )
        XCTAssertNotEqual(evaluation.scheduledSession, lift.scheduledSession)
        XCTAssertEqual(evaluation.planDay, lift.planDay, "one resolved day, not two")
    }

    /// An ask-relative reference resolves against the **workout's own** slot.
    ///
    /// Band filtering and reference resolution are two separate reads of the day, and
    /// getting only the first right would leave a lift's "70% of the prescribed duration"
    /// measured against the run the day also wanted. Tuesday prescribes 60 minutes of
    /// running and 45 minutes of lifting here precisely so the two answers differ: a
    /// 33-minute lift clears 70% of the lift ask (31.5 min) and misses 70% of the run ask
    /// (42 min).
    func testAnAskRelativeReferenceResolvesAgainstTheWorkoutsOwnAsk() throws {
        let template = try Self.template(runDurationSeconds: 3_600, liftDurationSeconds: 2_700)

        let evaluation = try Self.evaluate(
            workout: Self.lift(durationSeconds: 2_000),
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 138),
            weeklyTemplate: template
        )

        XCTAssertEqual(
            evaluation.band.identifier,
            "lift.metTheAsk",
            "0.7 of the 45-minute lift ask, not of the 60-minute run ask"
        )

        // The same session against a longer lift ask falls short — so the assertion above
        // is about the resolved number, not about the band being reachable at all.
        let underALongerAsk = try Self.evaluate(
            workout: Self.lift(durationSeconds: 2_000),
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 138),
            weeklyTemplate: try Self.template(runDurationSeconds: 3_600, liftDurationSeconds: 5_400)
        )
        XCTAssertEqual(underALongerAsk.band.identifier, "lift.short")
    }

    // MARK: - A discipline the day prescribed nothing for

    /// Thursday asks for an easy 8 km and no lift. A lift that day resolves to
    /// `ScheduledSession.rest`.
    ///
    /// **The decision, stated:** there is no ask to be relative to, and `.rest` is how a
    /// plan says exactly that — `PlanDay.scheduledSession(for:)` is total, so this is the
    /// plan's answer rather than a missing one. The workout is then judged by whatever
    /// the rubric says about a rest day (`rest.ranAnyway`, LIFTING-SPEC §5), which is the
    /// same treatment a run on a scheduled rest day has always had. Two alternatives were
    /// rejected: falling back to the *other* discipline's ask, which is the
    /// cross-discipline judgement A17 exists to make impossible; and a new "unprescribed"
    /// error case, which would put in code a decision the rubric can already state as
    /// data (D1) — a plan that wants lifting on an off day to be worth nothing writes a
    /// band saying so.
    func testALiftOnADayPrescribingNoLiftIsJudgedAgainstRest() throws {
        let evaluation = try Self.evaluate(
            workout: Self.lift(durationSeconds: 2_700),
            on: Self.thursday,
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 162)
        )

        XCTAssertEqual(evaluation.discipline, .lift)
        XCTAssertTrue(evaluation.scheduledSession.isRest)
        XCTAssertEqual(evaluation.band.identifier, "rest.ranAnyway")

        // And the day's run ask, which this lift was *not* measured against, is still
        // right there on the resolved day — untouched, for the run to be judged by.
        XCTAssertEqual(evaluation.planDay.scheduledSession.kind, .easy)
        XCTAssertEqual(evaluation.planDay.scheduledSession.distanceMeters, 8_000)
    }

    /// `.rest` is what the ask resolves to, not a licence to score anyway. A rubric with
    /// nothing to say about a rest day refuses, exactly as it does for a run.
    func testARestAskWithNoBandIsRefusedRatherThanDefaulted() throws {
        assertThrowsScoring(
            .noBandMatched,
            try Self.evaluate(
                workout: Self.lift(durationSeconds: 2_700),
                on: Self.thursday,
                classification: .other,
                metrics: Self.liftMetrics(averageHeartRateBPM: 162),
                rubric: ScoringFixture.workedExampleRubric()
            )
        )
    }

    /// The state this ticket lands in, pinned so that removing MAX-111's ingestion gate
    /// early is a visible decision rather than an accident.
    ///
    /// Routing a lift correctly is not the same as having somewhere to route it *to*.
    /// Under a rubric with no band for a lift day — which is every plan on disk until
    /// MAX-132 seeds one — a lift on a day that prescribes one is **refused**, not
    /// mis-scored. That refusal is the right failure (D1: an incomplete rubric is repaired
    /// by a new plan version, never by a default in Swift), and it is why the pipeline
    /// still leaves a lift unscored rather than sending it to the model.
    func testUnderARubricWithNoLiftBandsALiftIsRefusedRatherThanMisScored() throws {
        assertThrowsScoring(
            .noBandMatched,
            try Self.evaluate(
                workout: Self.lift(durationSeconds: 2_700),
                classification: .other,
                metrics: Self.liftMetrics(averageHeartRateBPM: 162),
                rubric: ScoringFixture.workedExampleRubric()
            )
        )
    }

    // MARK: - The scorer's guard follows the routing

    /// A lift and a run on the same Tuesday share a date and a plan version, so the
    /// evaluation-versus-context checks that predate A17 both pass for a pairing that is
    /// nonetheless wrong. Without the discipline check the stored `Score` would carry the
    /// lift's prescription for a run — permanently, under D8.
    func testAnEvaluationOfTheOtherDisciplinesAskIsRefused() throws {
        let run = try Self.context(
            workout: try Fixture.workout(),
            classification: .easy,
            metrics: ScoringFixture.metrics(averageHeartRateBPM: 142)
        )
        let liftEvaluation = try RubricEvaluator.evaluate(
            try Self.context(
                workout: Self.lift(durationSeconds: 2_700),
                classification: .other,
                metrics: Self.liftMetrics(averageHeartRateBPM: 162)
            )
        )

        // The pairing this guard is new for: same day, same plan version, same workout id.
        XCTAssertEqual(liftEvaluation.planDay.date, run.day)
        XCTAssertEqual(liftEvaluation.plan.version, run.plan?.version)

        assertThrows(
            .inconsistent,
            try WorkoutScorer.score(
                context: run,
                evaluation: liftEvaluation,
                proposal: ScoreProposal(score: 80, rationale: "Met the ask."),
                scoredAt: ScoringFixture.scoredAt
            )
        )
        assertThrows(
            .inconsistent,
            try WorkoutScorer.instruction(for: run, evaluation: liftEvaluation)
        )
    }

    /// The prescription a `Score` records is the one its own discipline was judged
    /// against — LIFTING-SPEC §5's "`Score` gains nothing", made checkable.
    func testTheScoreRecordsThePrescriptionOfItsOwnDiscipline() throws {
        let liftContext = try Self.context(
            workout: Self.lift(durationSeconds: 2_700),
            classification: .other,
            metrics: Self.liftMetrics(averageHeartRateBPM: 138)
        )
        let evaluation = try RubricEvaluator.evaluate(liftContext)

        let score = try WorkoutScorer.score(
            context: liftContext,
            evaluation: evaluation,
            proposal: ScoreProposal(score: 88, rationale: "Lifted for the prescribed 45 minutes."),
            scoredAt: ScoringFixture.scoredAt
        )

        XCTAssertEqual(score.scheduledSession.kind, .lift)
        XCTAssertEqual(score.scheduledSession.muscleGroups, [.chest, .shoulders])
        XCTAssertEqual(score.rubricBandIdentifier, "lift.metTheAsk")
        XCTAssertNotEqual(
            score.scheduledSession,
            evaluation.planDay.scheduledSession,
            "the run ask must not reach a lift's permanent record"
        )
    }

    // MARK: - The regression set: no historical run's score moves

    /// One row per (day, execution) pair a historical, single-discipline plan can produce
    /// under this file's rubric — every scheduled kind the weekly template prescribes,
    /// and every band of §10.3's worked example.
    private struct HistoricalDay {
        let day: String
        let classification: WorkoutClassification
        let averageHeartRateBPM: Double
        let drift: Double?
        let distanceMeters: Double
        let expectedBand: String
        let proposedScore: Int
    }

    private static let historicalDays: [HistoricalDay] = [
        // Monday: the plan asked for rest and the athlete ran anyway.
        HistoricalDay(day: "2026-01-05", classification: .easy, averageHeartRateBPM: 142,
                      drift: 0.03, distanceMeters: 10_000,
                      expectedBand: "rest.ranAnyway", proposedScore: 60),
        // Tuesday, easy 8 km: every row of §10.3's easy-day ladder.
        HistoricalDay(day: "2026-01-06", classification: .easy, averageHeartRateBPM: 142,
                      drift: 0.03, distanceMeters: 10_000,
                      expectedBand: "easy.onCap.lowDrift", proposedScore: 95),
        HistoricalDay(day: "2026-01-06", classification: .easy, averageHeartRateBPM: 142,
                      drift: 0.081, distanceMeters: 10_000,
                      expectedBand: "easy.onCap.lateDrift", proposedScore: 80),
        HistoricalDay(day: "2026-01-06", classification: .easy, averageHeartRateBPM: 155,
                      drift: 0.02, distanceMeters: 10_000,
                      expectedBand: "easy.slightlyOverCap", proposedScore: 60),
        HistoricalDay(day: "2026-01-06", classification: .easy, averageHeartRateBPM: 160,
                      drift: 0.02, distanceMeters: 10_000,
                      expectedBand: "easy.wellOverCap", proposedScore: 30),
        HistoricalDay(day: "2026-01-06", classification: .hard, averageHeartRateBPM: 168,
                      drift: nil, distanceMeters: 10_000,
                      expectedBand: "easy.ranHardInstead", proposedScore: 30),
        // Wednesday, "6 × 800m": no prescribed distance, so the hard row's reference does
        // not resolve and the run falls to the catch-all.
        HistoricalDay(day: "2026-01-07", classification: .hard, averageHeartRateBPM: 168,
                      drift: nil, distanceMeters: 10_000,
                      expectedBand: "fallback.recorded", proposedScore: 50),
        HistoricalDay(day: "2026-01-08", classification: .easy, averageHeartRateBPM: 142,
                      drift: 0.03, distanceMeters: 10_000,
                      expectedBand: "easy.onCap.lowDrift", proposedScore: 95),
        HistoricalDay(day: "2026-01-10", classification: .easy, averageHeartRateBPM: 145,
                      drift: 0.04, distanceMeters: 6_500,
                      expectedBand: "easy.onCap.lowDrift", proposedScore: 95),
        // Sunday: the arc's week-2 long run.
        HistoricalDay(day: "2026-01-11", classification: .long, averageHeartRateBPM: 148,
                      drift: 0.04, distanceMeters: 18_000,
                      expectedBand: "long.completedTheDistance", proposedScore: 88),
    ]

    /// **The acceptance criterion: no existing run's score changes.**
    ///
    /// Every row is scored through the routing this ticket introduces and compared
    /// against the record the pre-MAX-133 evaluator would have written — which is not a
    /// guess: that evaluator read `planDay.scheduledSession` unconditionally, so
    /// substituting exactly that expression into the produced `Score` reconstructs it. The
    /// comparison is made on the encoded payload as well as on the value, because what a
    /// stored score *is* is its bytes.
    ///
    /// Band identifiers are pinned as literals alongside, so that "identical" cannot be
    /// satisfied by both sides drifting together: if band selection moved, the identifier
    /// assertion fails first.
    func testEverySingleDisciplineDayScoresIdenticallyToTheRunSlotRouting() throws {
        for row in Self.historicalDays {
            let context = try Self.context(
                workout: try Fixture.workout(distanceMeters: row.distanceMeters),
                on: row.day,
                classification: row.classification,
                metrics: try ScoringFixture.metrics(
                    averageHeartRateBPM: row.averageHeartRateBPM,
                    heartRateDriftFraction: row.drift
                ),
                weeklyTemplate: try Fixture.weeklyTemplate(),
                rubric: try Self.historicalRubric()
            )
            let planDay = try XCTUnwrap(context.planDay, "\(row.day) is governed by no plan")
            let evaluation = try RubricEvaluator.evaluate(context)

            XCTAssertEqual(evaluation.discipline, .run, "\(row.day) is a run")
            XCTAssertEqual(
                evaluation.band.identifier,
                row.expectedBand,
                "\(row.day) / \(row.classification.rawValue) / \(row.averageHeartRateBPM) bpm changed band"
            )
            XCTAssertEqual(
                evaluation.scheduledSession,
                planDay.scheduledSession,
                "\(row.day): the ask read is the run slot, exactly as before MAX-133"
            )

            let score = try WorkoutScorer.score(
                context: context,
                evaluation: evaluation,
                proposal: ScoreProposal(
                    score: row.proposedScore,
                    rationale: "Scored against the \(row.expectedBand) rule."
                ),
                scoredAt: ScoringFixture.scoredAt
            )
            // The identical record with the one field this ticket could have moved read
            // the way the previous build read it.
            let asWrittenBefore = try Score(
                workoutID: score.workoutID,
                planVersion: score.planVersion,
                scheduledSession: planDay.scheduledSession,
                actualClassification: score.actualClassification,
                value: score.value,
                effectiveThreshold: score.effectiveThreshold,
                band: score.band,
                rubricBandIdentifier: score.rubricBandIdentifier,
                rationale: score.rationale,
                scoredAt: score.scoredAt
            )
            XCTAssertEqual(score, asWrittenBefore, "\(row.day): the stored score moved")

            let bytes = try PersistencePayload.encode(score, field: "test.score")
            let bytesAsWrittenBefore = try PersistencePayload.encode(
                asWrittenBefore,
                field: "test.score"
            )
            XCTAssertEqual(bytes, bytesAsWrittenBefore, "\(row.day): the stored score's bytes moved")
        }
    }

    /// The same claim for a plan that *does* prescribe lifting: adding a lift slot must
    /// not disturb the run slot's judgement on the very same day. A day prescribing both
    /// is where a routing mistake would be invisible, because both asks resolve.
    func testAddingALiftSlotDoesNotMoveTheRunsBandOnTheSameDay() throws {
        func evaluateRun(under template: WeeklyTemplate) throws -> RubricEvaluation {
            try Self.evaluate(
                workout: try Fixture.workout(),
                classification: .easy,
                metrics: ScoringFixture.metrics(averageHeartRateBPM: 142),
                weeklyTemplate: template
            )
        }

        let withoutLifting = try evaluateRun(under: Fixture.weeklyTemplate())
        let withLifting = try evaluateRun(under: Self.template())

        XCTAssertEqual(withoutLifting.band.identifier, "easy.onCap")
        XCTAssertEqual(withoutLifting.band, withLifting.band)
        XCTAssertEqual(withoutLifting.scheduledSession, withLifting.scheduledSession)
        XCTAssertEqual(withoutLifting.permittedScores, withLifting.permittedScores)
        XCTAssertEqual(withoutLifting.discipline, withLifting.discipline)
    }

    // MARK: - Scaffolding

    /// Thursday of the fixture week: an easy 8 km, and no lift.
    private static let thursday = "2026-01-08"

    /// A strength workout, as HealthKit records one: no distance, no route.
    private static func lift(durationSeconds: Double) throws -> Workout {
        try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            durationSeconds: durationSeconds,
            distanceMeters: nil,
            hasRoute: false
        )
    }

    /// What MAX-130 leaves on a lift: average heart rate, maximum heart rate, zone
    /// splits. No cadence, no pace, no drift, no time above a running cap.
    private static func liftMetrics(averageHeartRateBPM: Double) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: averageHeartRateBPM + 16,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .three, seconds: 2_000)]),
            planVersion: PlanVersion(1)
        )
    }

    /// The fixture week, with Tuesday carrying a lift ask as well as its run ask — the
    /// normal case A17 describes, not an edge one.
    private static func template(
        runDurationSeconds: Double? = nil,
        liftDurationSeconds: Double? = 2_700
    ) throws -> WeeklyTemplate {
        try WeeklyTemplate(
            [
                .monday: .rest,
                .tuesday: ScheduledSession(
                    kind: .easy,
                    distanceMeters: 8_000,
                    durationSeconds: runDurationSeconds
                ),
                .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
                .thursday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .friday: .rest,
                .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
                .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000),
            ],
            lift: [
                .tuesday: ScheduledSession(
                    kind: .lift,
                    durationSeconds: liftDurationSeconds,
                    note: "45 minutes",
                    muscleGroups: [.chest, .shoulders]
                ),
            ]
        )
    }

    /// A rubric with rows for both disciplines — the shape `StandardPlanSeed` now has
    /// (MAX-132), authored here so this file tests routing rather than one plan's
    /// opinions. `LiftRubricVocabularyTests` is where the seed's own bands are pinned.
    ///
    /// `easy.wellOverCap` is reproduced verbatim from the seed, conditions and all: one
    /// clause about heart rate and nothing about what was performed (A21). It is the band
    /// a lift used to match, and it is here so that "a lift cannot match it" is asserted
    /// against the real shape rather than a defanged one.
    private static func rubric() throws -> ScoringRubric {
        try ScoringRubric(
            effectiveThreshold: ScoreValue(70),
            marginalThreshold: ScoreValue(45),
            bands: [
                RubricBand(
                    identifier: "lift.metTheAsk",
                    appliesTo: [.lift],
                    conditions: [
                        .actualDiscipline(oneOf: [.lift]),
                        .metric(
                            metric: .durationSeconds,
                            comparison: .greaterThanOrEqual,
                            reference: .scheduledDuration(fraction: 0.7)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 75, highest: 100),
                    rationale: "Lifted for the session the plan asked for."
                ),
                RubricBand(
                    identifier: "lift.short",
                    appliesTo: [.lift],
                    conditions: [.actualDiscipline(oneOf: [.lift])],
                    scoreRange: ScoreRange(lowest: 40, highest: 69),
                    rationale: "A lifting session happened, but a short one."
                ),
                RubricBand(
                    identifier: "easy.onCap",
                    appliesTo: [.easy],
                    conditions: [
                        .actualClassification(oneOf: [.easy]),
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 0)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 90, highest: 100),
                    rationale: "Held the cap."
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
                    identifier: "rest.ranAnyway",
                    appliesTo: [.rest],
                    scoreRange: ScoreRange(lowest: 50, highest: 75),
                    rationale: "Trained on a day the plan asked nothing of."
                ),
                RubricBand(
                    identifier: "fallback.recorded",
                    scoreRange: ScoreRange(lowest: 40, highest: 69),
                    rationale: "Recorded, but the plan has no specific rule for this session."
                ),
            ]
        )
    }

    /// §10.3's worked example plus the two rows a historical plan needs to cover every
    /// scheduled kind the fixture week prescribes. The worked example's own bands and
    /// their order are untouched — first match wins, so appending is the only edit that
    /// cannot change an existing row's answer.
    private static func historicalRubric() throws -> ScoringRubric {
        let workedExample = try ScoringFixture.workedExampleRubric()
        return try ScoringRubric(
            effectiveThreshold: workedExample.effectiveThreshold,
            marginalThreshold: workedExample.marginalThreshold,
            bands: workedExample.bands + [
                RubricBand(
                    identifier: "rest.ranAnyway",
                    appliesTo: [.rest],
                    scoreRange: ScoreRange(lowest: 50, highest: 75),
                    rationale: "Ran on a scheduled rest day."
                ),
                RubricBand(
                    identifier: "fallback.recorded",
                    scoreRange: ScoreRange(lowest: 40, highest: 69),
                    rationale: "Recorded, but the plan has no specific rule for this session."
                ),
            ]
        )
    }

    private static func plan(
        weeklyTemplate: WeeklyTemplate? = nil,
        rubric overrideRubric: ScoringRubric? = nil
    ) throws -> Plan {
        try Plan(
            version: PlanVersion(1),
            effectiveFrom: CalendarDay(iso8601: "2026-01-01"),
            weeklyTemplate: weeklyTemplate ?? template(),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: overrideRubric ?? rubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    /// Assembled through the real builder (D3), so these tests exercise the assembly the
    /// app will.
    ///
    /// Defaults to the week that prescribes both on Tuesday and to the discipline-aware
    /// rubric; the regression rows pass the historical week and `historicalRubric()`
    /// explicitly, because what they are about is what a plan looked like before lifting.
    private static func context(
        workout: Workout,
        on day: String = ScoringFixture.easyDay,
        classification: WorkoutClassification,
        metrics: DerivedMetrics,
        weeklyTemplate: WeeklyTemplate? = nil,
        rubric overrideRubric: ScoringRubric? = nil
    ) throws -> WorkoutContext {
        let resolvedRubric = try overrideRubric ?? rubric()
        return try WorkoutContextBuilder.build(
            workout: workout,
            on: CalendarDay(iso8601: day),
            metrics: metrics,
            classification: classification,
            planCalendar: PlanCalendar([
                plan(weeklyTemplate: weeklyTemplate, rubric: resolvedRubric),
            ]),
            audience: .scoring,
            existingScore: nil
        )
    }

    private static func evaluate(
        workout: Workout,
        on day: String = ScoringFixture.easyDay,
        classification: WorkoutClassification,
        metrics: DerivedMetrics,
        weeklyTemplate: WeeklyTemplate? = nil,
        rubric overrideRubric: ScoringRubric? = nil
    ) throws -> RubricEvaluation {
        try RubricEvaluator.evaluate(
            context(
                workout: workout,
                on: day,
                classification: classification,
                metrics: metrics,
                weeklyTemplate: weeklyTemplate,
                rubric: overrideRubric
            )
        )
    }
}
