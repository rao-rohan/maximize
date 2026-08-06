import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-173: a rubric fix can reach a plan that already exists — and only by authoring a
/// new version, which is what keeps it D1-legal and D8-safe.
///
/// ## The gap these tests are about
///
/// `StandardPlanSeed` supplies the bands a **first** plan starts from. Every revision was
/// built with `rubricBands: current.rubric.bands`, so a correction to a seed band could
/// never reach a device whose plan already existed. Two corrections were stranded that
/// way: MAX-132's three `lift.*` adherence bands, and MAX-146's
/// `.actualDiscipline(oneOf: [.run])` on `rest.ranAnyway`, without which a lift on a day
/// prescribing no lift is permanently stamped *"Ran on a scheduled rest day."*
///
/// So the fixture below is a plan carrying the bands as they were **before** those two
/// tickets: derived from today's seed by removing the lift rows and stripping the
/// discipline conditions, rather than transcribed, so it stays an accurate statement of
/// *the difference* as the seed goes on changing.
///
/// ## What is proved here
///
/// 1. The stranded plan really cannot reach the lift bands (the defect, reproduced).
/// 2. A revision adopts them, and the saved version carries both fixes.
/// 3. **A workout dated before the new version is judged identically** — the whole
///    `RubricEvaluation` compares equal with the new version present and absent. That is
///    D8, and it is what makes this a new version rather than a migration.
/// 4. A plan already carrying the current rules produces no notice, no control and no
///    change.
/// 5. Nothing this ticket adds reaches a stored payload.
final class RubricAdoptionTests: XCTestCase {

    // MARK: - The calendar these tests run on

    /// A Monday. `2026-01-01` is a Thursday, so this is the following Monday.
    private static let firstVersionStart = "2026-01-05"
    /// Also a Monday, eight weeks later — comfortably past `firstVersionStart + 1`, so
    /// MAX-011's no-back-dating rule is satisfied with room to spare.
    private static let secondVersionStart = "2026-03-02"
    /// A Tuesday under version 1: the seeded week prescribes an easy run and no lift.
    private static let tuesdayUnderFirstVersion = "2026-01-13"
    /// The Tuesday version 2 governs.
    private static let tuesdayUnderSecondVersion = "2026-03-03"
    /// A Thursday under version 2 — an easy run, and still no lift prescribed.
    private static let thursdayUnderSecondVersion = "2026-03-05"

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    // MARK: - Fixtures

    /// The bands a plan saved before MAX-132 and MAX-146 carries.
    ///
    /// Derived from the current seed by undoing exactly the two changes, rather than
    /// transcribed: what is under test is the *difference* between a stored rubric and the
    /// shipped one, and deriving it means this fixture keeps describing that difference as
    /// the seed acquires further rows.
    private static func strandedBands() throws -> [RubricBand] {
        var bands: [RubricBand] = []
        for band in try StandardPlanSeed.rubricBands() {
            switch band.identifier {
            case "lift.completed", "lift.short", "lift.happened":
                // MAX-132 added these three. A plan saved before it has no row for a lift
                // day at all.
                continue
            case "rest.ranAnyway", "easy.wellOverCap":
                // Both carried no discipline condition before MAX-132/MAX-146, which is
                // precisely what let a lift match them.
                bands.append(
                    try RubricBand(
                        identifier: band.identifier,
                        appliesTo: band.appliesTo,
                        conditions: band.conditions.filter { condition in
                            if case .actualDiscipline = condition { return false }
                            return true
                        },
                        scoreRange: band.scoreRange,
                        rationale: band.rationale
                    )
                )
            default:
                bands.append(band)
            }
        }
        return bands
    }

    /// Version 1 as it sits on an athlete's device: authored through the real seeding
    /// path, then given the pre-fix bands.
    private func strandedPlan() throws -> Plan {
        let start = try day(Self.firstVersionStart)
        let session = try PlanAuthoring.session(revising: nil, today: start)
        let seeded = try session.plan(from: session.draft, effectiveFrom: start)
        return try Plan(
            version: seeded.version,
            effectiveFrom: seeded.effectiveFrom,
            weeklyTemplate: seeded.weeklyTemplate,
            longRunArc: seeded.longRunArc,
            heartRateCapBPM: seeded.heartRateCapBPM,
            cadenceTarget: seeded.cadenceTarget,
            rubric: try ScoringRubric(
                effectiveThreshold: seeded.rubric.effectiveThreshold,
                marginalThreshold: seeded.rubric.marginalThreshold,
                bands: Self.strandedBands()
            ),
            goals: seeded.goals,
            minimumSessionDurationSeconds: seeded.minimumSessionDurationSeconds
        )
    }

    /// The session an athlete gets by opening the plan editor over that stored version.
    private func revisionSession() throws -> PlanAuthoringSession {
        try PlanAuthoring.session(
            revising: try PlanCalendar([try strandedPlan()]),
            today: try day(Self.secondVersionStart)
        )
    }

    /// The version they save: the stored week untouched, except that Tuesday now
    /// prescribes a 45-minute lift — so the adopted adherence bands have an ask to be a
    /// fraction of, which is the case MAX-132 wrote them for.
    private func revisedPlan(adoptingCurrentRubric adopt: Bool = true) throws -> Plan {
        let session = try revisionSession().adoptingCurrentRubric(adopt)
        var draft = session.draft
        draft.setLiftKind(.lift, on: .tuesday)
        draft.setLiftDurationSeconds(2_700, on: .tuesday)
        return try session.plan(from: draft, effectiveFrom: try day(Self.secondVersionStart))
    }

    /// A strength workout, as HealthKit records one: no distance, no route.
    private static func lift(durationSeconds: Double = 2_700) throws -> Workout {
        try Fixture.workout(
            activityType: .traditionalStrengthTraining,
            durationSeconds: durationSeconds,
            distanceMeters: nil,
            hasRoute: false
        )
    }

    /// Metrics tagged with the plan version that governs the day they will be presented
    /// on — `WorkoutContextBuilder` refuses a mismatch (D1's coherence check), which is
    /// exactly the guard that makes a two-version fixture worth building.
    private static func metrics(
        averageHeartRateBPM: Double = 142,
        heartRateDriftFraction: Double? = 0.03,
        planVersion: Int
    ) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: averageHeartRateBPM + 16,
            heartRateDriftFraction: heartRateDriftFraction,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .three, seconds: 2_000)]),
            planVersion: PlanVersion(planVersion)
        )
    }

    /// Evaluated through the real context builder (D3), so these tests exercise the
    /// assembly the app performs rather than a shortcut around it.
    private func evaluate(
        workout: Workout,
        on date: String,
        against calendar: PlanCalendar,
        governedByVersion version: Int,
        classification: WorkoutClassification = .other,
        averageHeartRateBPM: Double = 142
    ) throws -> RubricEvaluation {
        try RubricEvaluator.evaluate(
            WorkoutContextBuilder.build(
                workout: workout,
                on: try day(date),
                metrics: try Self.metrics(
                    averageHeartRateBPM: averageHeartRateBPM,
                    planVersion: version
                ),
                classification: classification,
                planCalendar: calendar,
                audience: .scoring,
                existingScore: nil
            )
        )
    }

    // MARK: - The gap, reproduced

    /// The defect this ticket exists for: a stored plan has no row a lift can reach, and
    /// its `rest.ranAnyway` is unconditional, so a lift matches it.
    func testAStoredPlanCannotReachTheLiftAdherenceBands() throws {
        let stored = try strandedPlan()

        XCTAssertEqual(
            stored.rubric.bands(for: .lift).map(\.identifier),
            ["skipped", "fallback.recorded"],
            "the two rows MAX-168 found: a catch-all and an unreachable one"
        )
        XCTAssertNil(stored.rubric.band(identifiedBy: "lift.completed"))
        XCTAssertEqual(
            try XCTUnwrap(stored.rubric.band(identifiedBy: "rest.ranAnyway")).conditions,
            [],
            "unconditional, so it matches a lift as readily as a run"
        )

        // And the consequence, through the evaluator rather than asserted about the data:
        // a lift on a day prescribing none is stamped as a run.
        let evaluation = try evaluate(
            workout: try Self.lift(),
            on: Self.tuesdayUnderFirstVersion,
            against: try PlanCalendar([stored]),
            governedByVersion: 1
        )
        XCTAssertTrue(evaluation.scheduledSession.isRest, "the plan's own answer: no lift asked")
        XCTAssertEqual(evaluation.band.identifier, "rest.ranAnyway")
        XCTAssertEqual(evaluation.band.rationale, "Ran on a scheduled rest day.")
    }

    // MARK: - What a revision adopts

    /// The deliverable, stated directly: saving a revision writes the bands this build
    /// ships, MAX-132's three lift rows and MAX-146's condition included.
    func testARevisionAdoptsTheLiftBandsAndTheRestDayCondition() throws {
        let plan = try revisedPlan()

        XCTAssertEqual(plan.rubric.bands, try StandardPlanSeed.rubricBands())
        XCTAssertEqual(
            plan.rubric.bands(for: .lift).map(\.identifier),
            ["lift.completed", "lift.short", "lift.happened", "skipped", "fallback.recorded"]
        )
        for identifier in ["lift.completed", "lift.short", "lift.happened"] {
            XCTAssertTrue(
                try XCTUnwrap(plan.rubric.band(identifiedBy: identifier))
                    .conditions.contains(.actualDiscipline(oneOf: [.lift])),
                "\(identifier) lost MAX-132's own guard"
            )
        }
        XCTAssertTrue(
            try XCTUnwrap(plan.rubric.band(identifiedBy: "rest.ranAnyway"))
                .conditions.contains(.actualDiscipline(oneOf: [.run])),
            "MAX-146's condition did not reach the saved version"
        )
    }

    /// Adoption is about the **bands** and nothing else. The two thresholds are the
    /// draft's, because they are numbers the athlete edits on the same screen; a revision
    /// that adopted those too would silently undo a tuning they had done.
    func testAdoptionDoesNotTouchTheThresholdsTheAthleteSet() throws {
        let session = try revisionSession()
        var draft = session.draft
        draft.effectiveThresholdPoints = 78
        draft.marginalThresholdPoints = 52

        let plan = try session.plan(from: draft, effectiveFrom: try day(Self.secondVersionStart))

        XCTAssertEqual(plan.rubric.effectiveThreshold, try ScoreValue(78))
        XCTAssertEqual(plan.rubric.marginalThreshold, try ScoreValue(52))
        XCTAssertEqual(plan.rubric.bands, try StandardPlanSeed.rubricBands())
    }

    /// The behavioural half: with the corrected bands in effect, a lift on a day that
    /// prescribes one is judged on adherence.
    func testALiftUnderTheNewVersionIsJudgedOnAdherence() throws {
        let calendar = try PlanCalendar([try strandedPlan(), try revisedPlan()])

        XCTAssertEqual(
            try evaluate(
                workout: try Self.lift(durationSeconds: 2_700),
                on: Self.tuesdayUnderSecondVersion,
                against: calendar,
                governedByVersion: 2
            ).band.identifier,
            "lift.completed"
        )
        XCTAssertEqual(
            try evaluate(
                workout: try Self.lift(durationSeconds: 900),
                on: Self.tuesdayUnderSecondVersion,
                against: calendar,
                governedByVersion: 2
            ).band.identifier,
            "lift.short"
        )
    }

    /// MAX-146's fix, arriving where it never could before: a lift on a day the plan asks
    /// no lift for falls to the honest catch-all instead of being called a run.
    func testALiftOnADayPrescribingNoLiftIsNoLongerCalledARun() throws {
        let calendar = try PlanCalendar([try strandedPlan(), try revisedPlan()])

        let evaluation = try evaluate(
            workout: try Self.lift(),
            on: Self.thursdayUnderSecondVersion,
            against: calendar,
            governedByVersion: 2
        )

        XCTAssertTrue(evaluation.scheduledSession.isRest)
        XCTAssertNotEqual(evaluation.band.identifier, "rest.ranAnyway")
        XCTAssertEqual(evaluation.band.identifier, "fallback.recorded")
    }

    // MARK: - D8: nothing before the new version moves

    /// The safety property, and the reason this is a new version rather than a migration.
    ///
    /// The same workout, on the same day, evaluated against a calendar **with** and
    /// **without** the adopting version — and the whole `RubricEvaluation` compares equal:
    /// same plan, same resolved day, same band, same permitted range. Scoring reads the
    /// version in effect on the workout's own date, so a later version is invisible to it.
    ///
    /// Two workouts, not one: the lift is the case the fix is about, and the easy run is
    /// there so the proof is not only about the defect.
    func testAWorkoutBeforeTheNewVersionIsJudgedIdentically() throws {
        let before = try PlanCalendar([try strandedPlan()])
        let after = try PlanCalendar([try strandedPlan(), try revisedPlan()])

        let liftBefore = try evaluate(
            workout: try Self.lift(),
            on: Self.tuesdayUnderFirstVersion,
            against: before,
            governedByVersion: 1
        )
        let liftAfter = try evaluate(
            workout: try Self.lift(),
            on: Self.tuesdayUnderFirstVersion,
            against: after,
            governedByVersion: 1
        )
        XCTAssertEqual(liftBefore, liftAfter, "a stored lift's judgement moved")
        XCTAssertEqual(liftAfter.plan.version, try PlanVersion(1))
        XCTAssertEqual(liftAfter.band.identifier, "rest.ranAnyway")
        XCTAssertEqual(liftAfter.permittedScores, try ScoreRange(lowest: 50, highest: 75))
        XCTAssertEqual(liftAfter.band.rationale, "Ran on a scheduled rest day.")

        let runBefore = try evaluate(
            workout: try Fixture.workout(),
            on: Self.tuesdayUnderFirstVersion,
            against: before,
            governedByVersion: 1,
            classification: .easy
        )
        let runAfter = try evaluate(
            workout: try Fixture.workout(),
            on: Self.tuesdayUnderFirstVersion,
            against: after,
            governedByVersion: 1,
            classification: .easy
        )
        XCTAssertEqual(runBefore, runAfter, "a stored run's judgement moved")
        XCTAssertEqual(runAfter.plan.version, try PlanVersion(1))
        XCTAssertEqual(runAfter.band.identifier, "easy.onCap.lowDrift")
    }

    /// MAX-011 is not weakened to let a corrected rubric reach further back. The rules
    /// arrive from the date the athlete picks, and never before the version they
    /// supersede.
    func testAnAdoptingVersionStillCannotBackDate() throws {
        let session = try revisionSession()
        let earliest = try day("2026-01-06")

        XCTAssertEqual(session.earliestEffectiveFrom, earliest)
        XCTAssertFalse(session.permitsEffectiveFrom(try day(Self.firstVersionStart)))
        XCTAssertThrowsError(
            try session.plan(from: session.draft, effectiveFrom: try day(Self.firstVersionStart))
        ) { error in
            XCTAssertEqual(
                error as? PlanAuthoringError,
                .effectiveFromTooEarly(earliestPermitted: earliest)
            )
        }
    }

    // MARK: - Declining

    /// The choice is real: declining writes the stored bands, exactly as every revision
    /// did before this ticket.
    func testDecliningWritesTheStoredBands() throws {
        let declined = try revisedPlan(adoptingCurrentRubric: false)

        XCTAssertEqual(declined.rubric.bands, try Self.strandedBands())
        XCTAssertNil(declined.rubric.band(identifiedBy: "lift.completed"))
    }

    /// A session adopts from the moment it is built. That direction is deliberate: a
    /// screen that had to remember to switch the fix on is one forgotten call away from
    /// the defect, which is R13's signature.
    func testASessionAdoptsByDefault() throws {
        XCTAssertTrue(try revisionSession().adoptsCurrentRubric)
        XCTAssertFalse(try revisionSession().adoptingCurrentRubric(false).adoptsCurrentRubric)
        XCTAssertTrue(try revisionSession().adoptingCurrentRubric(false).adoptingCurrentRubric().adoptsCurrentRubric)
    }

    // MARK: - Nothing to adopt

    /// A plan already carrying the current rules produces no update, no sentence and no
    /// difference — the ordinary case for anybody up to date, and it must not nag them.
    func testAPlanAlreadyCarryingTheCurrentRulesOffersNothing() throws {
        let start = try day(Self.firstVersionStart)
        let first = try PlanAuthoring.session(revising: nil, today: start)
        let upToDate = try first.plan(from: first.draft, effectiveFrom: start)

        let session = try PlanAuthoring.session(
            revising: try PlanCalendar([upToDate]),
            today: try day(Self.secondVersionStart)
        )

        XCTAssertTrue(session.rubricUpdate.isEmpty)
        XCTAssertNil(session.rubricUpdateNotice)
        XCTAssertNil(session.rubricUpdateDeclineNotice)

        let effectiveFrom = try day(Self.secondVersionStart)
        XCTAssertEqual(
            try session.plan(from: session.draft, effectiveFrom: effectiveFrom),
            try session.adoptingCurrentRubric(false)
                .plan(from: session.draft, effectiveFrom: effectiveFrom),
            "adopting and declining produced different plans with nothing to adopt"
        )
        XCTAssertEqual(
            try session.plan(from: session.draft, effectiveFrom: effectiveFrom).rubric,
            upToDate.rubric
        )
    }

    /// A first plan has nothing to have moved on from: its stored bands *are* the current
    /// ones, so the whole mechanism is inert and the screen shows no section.
    func testAFirstPlanHasNothingToAdopt() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try day(Self.firstVersionStart))

        XCTAssertEqual(session.mode, .firstPlan)
        XCTAssertTrue(session.rubricUpdate.isEmpty)
        XCTAssertNil(session.rubricUpdateNotice)
        XCTAssertNil(session.rubricUpdateDeclineNotice)
    }

    // MARK: - `PlanRubricUpdate` itself

    /// Emptiness is the safety property the whole surface rests on, so it is asserted
    /// directly: empty exactly when the two lists are the same rules in the same order.
    func testTheUpdateIsEmptyOnlyForTheSameRulesInTheSameOrder() throws {
        let bands = try StandardPlanSeed.rubricBands()

        XCTAssertTrue(PlanRubricUpdate(stored: bands, current: bands).isEmpty)

        // Order is part of a rubric's meaning — first match wins — so a reordering is a
        // change even though no band differs.
        let reversed = PlanRubricUpdate(stored: Array(bands.reversed()), current: bands)
        XCTAssertFalse(reversed.isEmpty)
        XCTAssertTrue(reversed.reordersExistingRules)
        XCTAssertTrue(reversed.addedRules.isEmpty)
        XCTAssertTrue(reversed.changedRules.isEmpty)
        XCTAssertTrue(reversed.removedRules.isEmpty)

        let lastRationale = try XCTUnwrap(bands.last).rationale
        let added = PlanRubricUpdate(stored: Array(bands.dropLast()), current: bands)
        XCTAssertEqual(added.addedRules, [lastRationale])
        XCTAssertEqual(added.ruleCount, 1)

        let removed = PlanRubricUpdate(stored: bands, current: Array(bands.dropLast()))
        XCTAssertEqual(removed.removedRules, [lastRationale])
    }

    /// A band that keeps its identifier and changes anything else is a *change*, reported
    /// in the words the verdict will use from here on.
    func testAChangedConditionIsReportedUnderTheCurrentWording() throws {
        let stored = try Self.strandedBands()
        let update = PlanRubricUpdate(stored: stored, current: try StandardPlanSeed.rubricBands())

        let storedIdentifiers = Set(stored.map(\.identifier))
        XCTAssertEqual(
            update.addedRules,
            try StandardPlanSeed.rubricBands()
                .filter { !storedIdentifiers.contains($0.identifier) }
                .map(\.rationale),
            "the added rules, in rubric order, as their own rationales"
        )
        XCTAssertEqual(
            Set(update.changedRules),
            ["Ran on a scheduled rest day.", "Well above the easy cap for the whole run."],
            "the two bands whose conditions MAX-132/MAX-146 narrowed"
        )
        XCTAssertTrue(update.removedRules.isEmpty)
        XCTAssertFalse(update.reordersExistingRules)
    }

    // MARK: - What the athlete is told

    /// The sentence names the version it is about and carries the figures, and says
    /// nothing an athlete cannot act on: no condition case names, no band identifiers.
    func testTheNoticeStatesTheFiguresWithoutSpeakingTheSchema() throws {
        let session = try revisionSession()
        let notice = try XCTUnwrap(session.rubricUpdateNotice)
        let update = session.rubricUpdate
        let superseded = try PlanVersion(1)

        XCTAssertTrue(notice.contains("plan \(superseded)"))
        XCTAssertTrue(notice.contains("\(update.addedRules.count) added"))
        XCTAssertTrue(notice.contains("\(update.changedRules.count) changed"))

        for band in try StandardPlanSeed.rubricBands() {
            XCTAssertFalse(notice.contains(band.identifier), "the notice speaks band identifiers")
        }
        XCTAssertFalse(notice.contains("actualDiscipline"))
        XCTAssertFalse(notice.contains("RubricBand"))

        // And the decline sentence exists whenever the offer does, so the control is never
        // shown without saying what turning it off means.
        XCTAssertNotNil(session.rubricUpdateDeclineNotice)
    }

    /// The permanence sentence is the one that makes the control readable as safe, so it
    /// states D8 rather than alluding to it.
    func testThePermanenceSentenceStatesWhatDoesNotChange() throws {
        XCTAssertTrue(PlanCopy.rubricUpdatePermanence.contains("already recorded"))
        XCTAssertTrue(PlanCopy.rubricUpdatePermanence.contains("version in effect"))
    }

    // MARK: - Nothing stored moves, on the wire either

    /// This ticket persists nothing. `adoptsCurrentRubric` and `PlanRubricUpdate` live on
    /// `PlanAuthoringSession`, which is never written to disk, so no stored payload gains
    /// a key and no migration exists to get wrong.
    func testAdoptionAddsNothingToAnyStoredPayload() throws {
        let stored = try strandedPlan()
        let data = try PersistencePayload.encode(stored, field: "test.plan")
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("adopts"))
        XCTAssertFalse(json.contains("rubricUpdate"))
        XCTAssertEqual(
            try PersistencePayload.decode(Plan.self, from: data, field: "test.plan"),
            stored
        )

        // The version an adopting revision writes is an ordinary `Plan` too: it round
        // trips, bands and order intact, with nothing new alongside them.
        let revised = try revisedPlan()
        let revisedData = try PersistencePayload.encode(revised, field: "test.plan")
        let revisedJSON = try XCTUnwrap(String(data: revisedData, encoding: .utf8))
        XCTAssertFalse(revisedJSON.contains("adopts"))
        XCTAssertEqual(
            try PersistencePayload.decode(Plan.self, from: revisedData, field: "test.plan"),
            revised
        )
    }

    /// The stored version itself is untouched by any of this — adoption is a property of
    /// the version being *authored*. There is no code path that rewrites a rubric in
    /// place, and this is the assertion that fails if one appears.
    func testAuthoringAnAdoptingRevisionLeavesTheStoredVersionAlone() throws {
        let stored = try strandedPlan()
        let calendar = try PlanCalendar([stored])
        let session = try PlanAuthoring.session(
            revising: calendar,
            today: try day(Self.secondVersionStart)
        )

        _ = try session.plan(from: session.draft, effectiveFrom: try day(Self.secondVersionStart))

        XCTAssertEqual(calendar.versions, [stored])
        XCTAssertEqual(calendar.versions.first?.rubric.bands, try Self.strandedBands())
    }
}
