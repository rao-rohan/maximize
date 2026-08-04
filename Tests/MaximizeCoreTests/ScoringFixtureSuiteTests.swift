import Foundation
import XCTest
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// MAX-071 — known-good runs, driven end to end through the real pipeline, to expected
/// rubric bands (R6, R7).
///
/// ## What this suite can prove, and what it cannot
///
/// R7 is blunt about the limit here: **Claude's judgment cannot be unit-tested, only
/// the rubric plumbing around it.** Every scenario below is therefore a *band* and
/// *verdict* assertion — which rule matched, and whether matching it already settles
/// effective/not-effective — never a "the model chose the right number" assertion. The
/// deterministic half of scoring (MAX-015's design note explains why it is deterministic
/// at all) is what gets pinned here. Where a `ScoreProposal` value appears below, it
/// exists only to drive `WorkoutScorer` through a complete round trip and is chosen to
/// sit unambiguously inside the settled part of its band — never to claim the number
/// itself is correct.
///
/// ## How this differs from `RubricEvaluationTests`
///
/// `RubricEvaluationTests` hand-feeds an already-computed `DerivedMetrics` and asks the
/// rubric which band it matches — the deterministic core, isolated from everything that
/// produces its input. This suite starts one layer further back: a synthetic **raw
/// capture** (a heart-rate sample series, a distance, a duration — the shape `MAX-032`'s
/// extraction actually hands ingestion) run through the real `DerivedMetricsCalculator`
/// (MAX-012) and `WorkoutClassifier` (MAX-013) before the rubric ever sees it, exactly
/// as `WorkoutIngestionPipeline` does. A "known-good run" here is defined the way
/// ingestion produces one; a break in the wiring between MAX-012/013/014/015 fails a
/// test here even if each piece's own unit tests still pass in isolation.
///
/// ## Margins, not edges
///
/// Every scenario is built well inside a zone boundary and well past a distance
/// threshold, deliberately, so a rounding change in `HeartRateCurve`'s interpolation
/// cannot flip a classification. The one exception is the scenario that is *about* a
/// narrow band ("slightly over cap" is only 8 bpm wide by the plan's own rubric) — there
/// the run is centered in the band instead, which is the most margin a narrow band can
/// offer on either side. Pinning exact arithmetic to the decimal is
/// `DerivedMetricsCalculatorTests`' job, not this suite's.
///
/// ## D1, made concrete
///
/// Every plan below is a `Plan` this file constructs; no rubric threshold is a literal
/// compared against in an assertion. `testTheSameRawRunLandsInDifferentBandsUnderTheVersionGoverningItsDay`
/// is the one that matters most here: it feeds the identical raw heart-rate profile
/// through two plan versions inside a single `PlanCalendar`, on two dates each version
/// governs, and shows the band — and therefore the verdict — differs because the plan
/// data differs, with nothing in `Sources/` deciding it.
final class ScoringFixtureSuiteTests: XCTestCase {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    // MARK: - Raw capture builders

    /// Midnight UTC on `iso`, offset a few hours so the workout falls unambiguously on
    /// that calendar day under `utc` — built from `Fixture.epoch` (2026-01-01T00:00:00Z)
    /// to keep this suite on the same fixed-epoch convention as the rest of the tests.
    private func startOfDay(_ iso: String, hour: Double = 8) throws -> Date {
        let target = try CalendarDay(iso8601: iso)
        let epochDay = try CalendarDay(iso8601: "2026-01-01")
        let offsetDays = try epochDay.days(until: target)
        return Fixture.epoch.addingTimeInterval(Double(offsetDays) * 86_400 + hour * 3_600)
    }

    /// A treadmill run — first-class per FR-0.6, and it sidesteps route fixtures this
    /// suite has no use for.
    private func rawWorkout(
        on day: String,
        durationSeconds: Double,
        distanceMeters: Double?
    ) throws -> Workout {
        let start = try startOfDay(day)
        return try Workout(
            id: Fixture.workoutID,
            activityType: .treadmillRunning,
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 650,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(durationSeconds + 120)
        )
    }

    /// Flat at `bpm` for the whole run — "held it perfectly", with zero drift by
    /// construction.
    private func flatSeries(_ bpm: Double, durationSeconds: Double) throws -> HeartRateSeries {
        try MetricsFixture.series([(0, bpm), (durationSeconds, bpm)])
    }

    /// Flat at `firstHalfBPM`, then an abrupt one-second step to flat at
    /// `secondHalfBPM` for the rest of the run. A late-drift shape with no ambiguity
    /// about which half any instant belongs to, so the expected direction of drift
    /// needs no decimal-level computation to reason about.
    private func steppedSeries(
        firstHalfBPM: Double,
        secondHalfBPM: Double,
        durationSeconds: Double
    ) throws -> HeartRateSeries {
        let midpoint = durationSeconds / 2
        return try MetricsFixture.series([
            (0, firstHalfBPM),
            (midpoint, firstHalfBPM),
            (midpoint + 1, secondHalfBPM),
            (durationSeconds, secondHalfBPM),
        ])
    }

    // MARK: - Plan builders (D1: every threshold below is plan data this file authors)

    /// A plan shaped like `ScoringFixture.plan()`, but with `effectiveFrom` and
    /// `version` exposed — needed to build the two-version `PlanCalendar` the D1 test
    /// resolves a single raw run against.
    private func plan(
        version: Int = 1,
        effectiveFrom: String = "2026-01-01",
        heartRateCapBPM: Double = 150,
        rubric: ScoringRubric? = nil
    ) throws -> Plan {
        try Plan(
            version: PlanVersion(version),
            effectiveFrom: CalendarDay(iso8601: effectiveFrom),
            weeklyTemplate: Fixture.weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: heartRateCapBPM,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: rubric ?? ScoringFixture.workedExampleRubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    // MARK: - The pipeline itself: MAX-012 → MAX-013 → MAX-014 → MAX-015

    /// Runs the real pipeline over a raw capture, exactly as ingestion does: compute
    /// metrics, classify from them, recompute once more with the classification
    /// supplied (so drift is gated on what the run turned out to be — see
    /// `DerivedMetricsCalculator`'s note on ordering), assemble the context, and
    /// evaluate the rubric. Nothing here hand-authors a `DerivedMetrics` or a
    /// `WorkoutClassification`.
    private func runPipeline(
        workout: Workout,
        heartRateSeries: HeartRateSeries?,
        totalStepCount: Double? = nil,
        planCalendar: PlanCalendar,
        on day: String
    ) throws -> (context: WorkoutContext, evaluation: RubricEvaluation) {
        let calendarDay = try CalendarDay(iso8601: day)
        guard let plan = planCalendar.plan(on: calendarDay) else {
            throw DomainError.inconsistent(
                reason: "ScoringFixtureSuiteTests: \(day) is not governed by any fixture plan version"
            )
        }

        let firstPass = try DerivedMetricsCalculator.compute(
            try DerivedMetricsInput(
                workout: workout, heartRateSeries: heartRateSeries, totalStepCount: totalStepCount
            ),
            plan: plan
        )
        let classification = try WorkoutClassifier.classify(
            workout, metrics: firstPass, plan: plan, timeZone: Self.utc
        )
        let finalMetrics = try DerivedMetricsCalculator.compute(
            try DerivedMetricsInput(
                workout: workout,
                heartRateSeries: heartRateSeries,
                totalStepCount: totalStepCount,
                classification: classification
            ),
            plan: plan
        )

        let context = try WorkoutContextBuilder.build(
            workout: workout,
            on: calendarDay,
            metrics: finalMetrics,
            classification: classification,
            planCalendar: planCalendar,
            heartRateSeries: heartRateSeries
        )
        return (context, try RubricEvaluator.evaluate(context))
    }

    // MARK: - Known-good runs

    /// A perfectly held easy run: flat, comfortably under the cap, zero drift. Every
    /// stage should agree it was easy and executed well.
    func testAPerfectlyHeldEasyRunIsClassifiedEasyAndSettledEffective() throws {
        let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
        let series = try flatSeries(140, durationSeconds: 2_700) // 10 bpm of headroom under a 150 cap.
        let calendar = try PlanCalendar([plan()])

        let (context, evaluation) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
        )

        XCTAssertEqual(context.classification, .easy)
        XCTAssertEqual(evaluation.band.identifier, "easy.onCap.lowDrift")
        XCTAssertTrue(evaluation.verdictIsSettledByRubric)
        XCTAssertEqual(evaluation.settledScoreBand, .effective)

        // The round trip through the model boundary: only the top of the matched band
        // is asserted as *reachable*, never as the "right" number.
        let score = try WorkoutScorer.score(
            context: context,
            evaluation: evaluation,
            proposal: ScoreProposal(
                score: evaluation.permittedScores.highest.points,
                rationale: "Held 140 bpm flat against a 150 cap with no measurable drift."
            ),
            scoredAt: ScoringFixture.scoredAt
        )
        XCTAssertEqual(score.band, .effective)
        XCTAssertTrue(score.isEffective)
        XCTAssertEqual(score.planVersion, evaluation.plan.version)
    }

    /// Under the cap the whole way, but the second half runs meaningfully hotter than
    /// the first — the "under cap, but drifted late" row. Still effective, but not the
    /// top band.
    func testAnEasyRunThatDriftsLateStaysUnderCapAndIsSettledEffectiveInTheSecondBand() throws {
        let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
        // 120 → 150: 25% drift, comfortably over the 5% cut; the time-weighted average
        // lands at 135 — 15 bpm under the 150 cap — and 150 stays out of zone 4 (>162
        // for this plan's cap), so this does not read as a hard effort.
        let series = try steppedSeries(firstHalfBPM: 120, secondHalfBPM: 150, durationSeconds: 2_700)
        let calendar = try PlanCalendar([plan()])

        let (context, evaluation) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
        )

        XCTAssertEqual(context.classification, .easy)
        let average = try XCTUnwrap(context.metrics.averageHeartRateBPM)
        XCTAssertLessThanOrEqual(average, 150)
        let drift = try XCTUnwrap(context.metrics.heartRateDriftFraction)
        XCTAssertGreaterThanOrEqual(drift, 0.05)

        XCTAssertEqual(evaluation.band.identifier, "easy.onCap.lateDrift")
        XCTAssertTrue(evaluation.verdictIsSettledByRubric)
        XCTAssertEqual(evaluation.settledScoreBand, .effective)
    }

    /// Over the cap, but not by much — the band PRD §10.3 writes as 55–74, straddling
    /// an effective threshold of 70. This is the *honest boundary* R7 describes: the
    /// rubric alone does not settle whether this run counted, and the model's exact
    /// number does. The suite proves the boundary is where the plan says it is; it does
    /// not — and must not appear to — prove which side of it this particular run
    /// belongs on.
    func testAnEasyRunSlightlyOverCapIsNotSettledByTheRubricAlone() async throws {
        let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
        let series = try flatSeries(154, durationSeconds: 2_700) // 4 over cap, 4 under cap+8.
        let calendar = try PlanCalendar([plan()])

        let (context, evaluation) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
        )

        XCTAssertEqual(context.classification, .easy)
        XCTAssertEqual(evaluation.band.identifier, "easy.slightlyOverCap")
        XCTAssertFalse(evaluation.verdictIsSettledByRubric)
        XCTAssertNil(evaluation.settledScoreBand)

        // Drive the full seam — instruction, fake transport, acceptance — for both
        // sides of the cut the rubric names but does not resolve.
        let effectiveReply = FakeScoringModelInvoking(
            outcome: .reply(#"{"score": 70, "rationale": "Ran 154 bpm, just over cap, but held it steady."}"#)
        )
        let marginalReply = FakeScoringModelInvoking(
            outcome: .reply(#"{"score": 69, "rationale": "Ran 154 bpm, over cap for most of the run."}"#)
        )

        let instruction = try WorkoutScorer.instruction(for: context, evaluation: evaluation)
        let effectiveReplyText = try await effectiveReply.reply(to: instruction)
        let marginalReplyText = try await marginalReply.reply(to: instruction)

        let effective = try WorkoutScorer.score(
            context: context,
            evaluation: evaluation,
            modelResponse: effectiveReplyText,
            scoredAt: ScoringFixture.scoredAt
        )
        let marginal = try WorkoutScorer.score(
            context: context,
            evaluation: evaluation,
            modelResponse: marginalReplyText,
            scoredAt: ScoringFixture.scoredAt
        )

        XCTAssertEqual(effective.band, .effective)
        XCTAssertEqual(marginal.band, .marginal)
    }

    /// A structured-hard effort on a day the plan asked to be easy. Classification, not
    /// heart rate against the cap, decides the band — the run is judged as the wrong
    /// session, not as a fast easy one.
    func testHardEffortOnAScheduledEasyDayIsClassifiedHardAndSettledNotEffective() throws {
        let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
        let series = try flatSeries(168, durationSeconds: 2_700) // deep in zone 4 the whole run.
        let calendar = try PlanCalendar([plan()])

        let (context, evaluation) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
        )

        XCTAssertEqual(context.classification, .hard)
        XCTAssertEqual(evaluation.band.identifier, "easy.ranHardInstead")
        // Settled as "not effective" (20–45 sits entirely under a threshold of 70), but
        // 20–45 itself straddles the marginal cut at 45 — so the amber/red distinction
        // still depends on the model's number, and this suite does not pretend to know
        // it.
        XCTAssertTrue(evaluation.verdictIsSettledByRubric)
        XCTAssertNil(evaluation.settledScoreBand)

        let score = try WorkoutScorer.score(
            context: context,
            evaluation: evaluation,
            proposal: ScoreProposal(
                score: evaluation.permittedScores.lowest.points,
                rationale: "Averaged 168 bpm, a structured-hard effort on a scheduled easy day."
            ),
            scoredAt: ScoringFixture.scoredAt
        )
        XCTAssertFalse(score.isEffective)
    }

    /// A long run that clears the week's prescribed distance by a wide margin.
    func testALongRunCoveringThePrescribedDistanceIsClassifiedLongAndSettledEffective() throws {
        let workout = try rawWorkout(on: ScoringFixture.longDay, durationSeconds: 6_300, distanceMeters: 19_000)
        let series = try flatSeries(145, durationSeconds: 6_300) // steady, well clear of zone 4.
        let calendar = try PlanCalendar([plan()])

        let (context, evaluation) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.longDay
        )

        XCTAssertEqual(context.classification, .long)
        XCTAssertEqual(evaluation.band.identifier, "long.completedTheDistance")
        XCTAssertTrue(evaluation.verdictIsSettledByRubric)
        XCTAssertEqual(evaluation.settledScoreBand, .effective)
    }

    // MARK: - D1: the governing plan version, not the code, decides the band

    /// The same raw heart-rate profile, unchanged, resolved against two different plan
    /// versions inside one `PlanCalendar` — a looser cap on the day the first version
    /// governs, a tighter one on the day the second does. Nothing about the run
    /// changes; only which plan version's `effectiveFrom` covers its date does. That is
    /// the whole of D1, exercised through the raw pipeline rather than asserted against
    /// a hand-fed `DerivedMetrics`.
    func testTheSameRawRunLandsInDifferentBandsUnderTheVersionGoverningItsDay() throws {
        let versionOne = try plan(version: 1, effectiveFrom: "2026-01-01", heartRateCapBPM: 150)
        // A stricter cap, taking effect four weeks later on another Tuesday so the
        // weekly template still asks for the same "easy, 8 km" session.
        let versionTwo = try plan(version: 2, effectiveFrom: "2026-02-02", heartRateCapBPM: 135)
        let calendar = try PlanCalendar([versionOne, versionTwo])

        let underVersionOne = try rawWorkout(
            on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500
        )
        let underVersionTwo = try rawWorkout(
            on: "2026-02-03", durationSeconds: 2_700, distanceMeters: 8_500
        )
        // Byte-for-byte the same heart-rate profile both times: 140 bpm, flat, the
        // entire run. Built twice, from the same literal call, rather than shared as
        // one value — nothing here should be able to mistake "the same `HeartRateSeries`
        // value" for "the same measured effort", which is the distinction this test is
        // actually about.
        let (earlyContext, earlyEvaluation) = try runPipeline(
            workout: underVersionOne,
            heartRateSeries: flatSeries(140, durationSeconds: 2_700),
            planCalendar: calendar,
            on: ScoringFixture.easyDay
        )
        let (laterContext, laterEvaluation) = try runPipeline(
            workout: underVersionTwo,
            heartRateSeries: flatSeries(140, durationSeconds: 2_700),
            planCalendar: calendar,
            on: "2026-02-03"
        )

        XCTAssertEqual(earlyContext.plan?.version, versionOne.version)
        XCTAssertEqual(laterContext.plan?.version, versionTwo.version)

        // 140 bpm is comfortably under version one's 150 cap and 5 bpm over version
        // two's 135 cap — the identical run, differently judged, purely because a
        // different plan version's cap applied.
        XCTAssertEqual(earlyEvaluation.band.identifier, "easy.onCap.lowDrift")
        XCTAssertEqual(laterEvaluation.band.identifier, "easy.slightlyOverCap")
        XCTAssertEqual(earlyEvaluation.settledScoreBand, .effective)
        XCTAssertNil(laterEvaluation.settledScoreBand)

        // Classification itself agrees across both versions — 140 bpm never reaches
        // either version's hard-zone floor — so the difference above is attributable
        // to the cap alone, not to a second variable moving at the same time.
        XCTAssertEqual(earlyContext.classification, .easy)
        XCTAssertEqual(laterContext.classification, .easy)
    }

    // MARK: - Determinism

    /// The same raw capture, run through the pipeline twice, must produce
    /// byte-identical results at every stage — the context, its rendered fact sheet,
    /// the rubric evaluation, and the stored score given the same model reply. If two
    /// runs of this test can diverge, so can two runs of the real ingestion pipeline
    /// against the same workout, and the divergence would be invisible until a
    /// historical score disagreed with itself.
    func testTheFullPipelineIsDeterministicForTheSameRawCapture() throws {
        let calendar = try PlanCalendar([plan()])

        func runOnce() throws -> (WorkoutContext, RubricEvaluation) {
            let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
            let series = try flatSeries(140, durationSeconds: 2_700)
            return try runPipeline(
                workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
            )
        }

        let (firstContext, firstEvaluation) = try runOnce()
        let (secondContext, secondEvaluation) = try runOnce()

        XCTAssertEqual(firstContext, secondContext)
        XCTAssertEqual(firstContext.factSheet(), secondContext.factSheet())
        XCTAssertEqual(firstEvaluation, secondEvaluation)

        let reply = #"{"score": 96, "rationale": "Held the cap with minimal drift."}"#
        let firstScore = try WorkoutScorer.score(
            context: firstContext, modelResponse: reply, scoredAt: ScoringFixture.scoredAt
        )
        let secondScore = try WorkoutScorer.score(
            context: secondContext, modelResponse: reply, scoredAt: ScoringFixture.scoredAt
        )
        XCTAssertEqual(firstScore, secondScore)
    }

    // MARK: - D3: the context handed to the scorer, produced by the real pipeline

    /// The fact sheet assembled from a raw pipeline run still obeys D3's omissions —
    /// no workout identifier, no coordinates — and still states the plan's cap and the
    /// classification the pipeline actually produced. `WorkoutContextTests` covers this
    /// exhaustively against hand-fed metrics; this is the one check that it continues
    /// to hold when the metrics come from a real capture instead.
    func testTheContextFromARawCaptureCarriesTheGoverningPlanAndNoIdentifiers() throws {
        let workout = try rawWorkout(on: ScoringFixture.easyDay, durationSeconds: 2_700, distanceMeters: 8_500)
        let series = try flatSeries(140, durationSeconds: 2_700)
        let calendar = try PlanCalendar([plan()])

        let (context, _) = try runPipeline(
            workout: workout, heartRateSeries: series, planCalendar: calendar, on: ScoringFixture.easyDay
        )
        let sheet = context.factSheet()

        XCTAssertTrue(sheet.contains("Classified as: easy"))
        XCTAssertTrue(sheet.contains("Heart-rate cap: 150 bpm"))
        XCTAssertFalse(sheet.contains(Fixture.workoutID.uuidString))
        XCTAssertFalse(sheet.lowercased().contains("latitude"))
    }
}
