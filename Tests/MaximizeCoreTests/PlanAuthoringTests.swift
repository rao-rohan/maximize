import XCTest
@testable import MaximizeCore

/// MAX-080. The half of plan authoring that CI can prove: version derivation, the
/// no-back-dating rule, draft round-tripping, and that a saved revision never
/// re-seeds a rubric the athlete had already tuned.
final class PlanAuthoringTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// A Wednesday, so "the Monday of this week" is a distinct day worth asserting on.
    private var today: CalendarDay {
        get throws { try day("2026-08-05") }
    }

    // MARK: - The first plan

    func testFirstPlanSessionIsVersionOneAndSeeded() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)

        XCTAssertEqual(session.mode, .firstPlan)
        XCTAssertEqual(session.version, try PlanVersion(1))
        XCTAssertEqual(session.draft.heartRateCapBPM, StandardPlanSeed.heartRateCapBPM)
        XCTAssertEqual(session.draft.cadenceLowStepsPerMinute, StandardPlanSeed.cadenceLowStepsPerMinute)
        XCTAssertEqual(session.draft.cadenceHighStepsPerMinute, StandardPlanSeed.cadenceHighStepsPerMinute)
        XCTAssertEqual(session.draft.effectiveThresholdPoints, StandardPlanSeed.effectiveThresholdPoints)
        XCTAssertEqual(session.draft.longRunArc.count, StandardPlanSeed.arcWeekCount)
        // MAX-151: the seed now states a floor, closing tracker gap P3's authoring half.
        XCTAssertEqual(
            session.draft.minimumSessionDurationSeconds,
            StandardPlanSeed.minimumSessionDurationSeconds
        )
    }

    /// The suggested start is the Monday of the current training week, not today —
    /// arc weeks are Monday-anchored, and starting mid-week gives a stub week 1.
    func testFirstPlanSuggestsTheMondayOfThisWeek() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-08-03"))
    }

    /// The one case where reaching backwards is legal: there is no earlier version to
    /// re-govern, and it is what brings already-captured `.noPlanAuthored` runs under
    /// a plan.
    func testFirstPlanMayBeBackDatedArbitrarily() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        XCTAssertNil(session.earliestEffectiveFrom)
        XCTAssertTrue(session.permitsEffectiveFrom(try day("2020-01-01")))

        let plan = try session.plan(from: session.draft, effectiveFrom: try day("2026-01-05"))
        XCTAssertEqual(plan.effectiveFrom, try day("2026-01-05"))
    }

    func testSeededPlanCarriesThePRDsStatedValues() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        let plan = try session.plan(from: session.draft, effectiveFrom: try day("2026-08-03"))

        XCTAssertEqual(plan.heartRateCapBPM, 150)
        XCTAssertEqual(plan.cadenceTarget.lowStepsPerMinute, 165)
        XCTAssertEqual(plan.cadenceTarget.highStepsPerMinute, 170)
        XCTAssertEqual(plan.rubric.effectiveThreshold, try ScoreValue(70))
        XCTAssertEqual(plan.version, try PlanVersion(1))
    }

    /// MAX-151's own acceptance criterion: a *saved* first plan actually carries the
    /// seeded floor, not only the draft it was authored from.
    func testASavedFirstPlanCarriesTheSeededDurationFloor() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        let plan = try session.plan(from: session.draft, effectiveFrom: try day("2026-08-03"))

        XCTAssertEqual(plan.minimumSessionDurationSeconds, StandardPlanSeed.minimumSessionDurationSeconds)
        XCTAssertNotNil(plan.minimumSessionDurationSeconds)
    }

    /// The seeded rubric must have something to say about every scheduled kind, or a
    /// workout on that day throws `noBandMatched` and ends up unscored — which means
    /// no calendar colour and no chat.
    func testSeededRubricHasABandForEveryScheduledKind() throws {
        let rubric = try ScoringRubric(
            effectiveThreshold: ScoreValue(StandardPlanSeed.effectiveThresholdPoints),
            marginalThreshold: ScoreValue(StandardPlanSeed.marginalThresholdPoints),
            bands: StandardPlanSeed.rubricBands()
        )
        for kind in ScheduledSessionKind.allCases {
            let applicable = rubric.bands(for: kind)
            XCTAssertFalse(applicable.isEmpty, "no band applies to \(kind)")
            XCTAssertTrue(
                applicable.contains { $0.conditions.isEmpty },
                "no unconditional band for \(kind), so a workout can still match nothing"
            )
        }
    }

    // MARK: - Revising

    /// A store holding exactly the version an athlete would get by saving the seeded
    /// draft on `effectiveFrom` — built through the authoring path rather than by hand,
    /// so a revision is tested against a plan the app could really have produced.
    private func storedCalendar(effectiveFrom: String = "2026-06-01") throws -> PlanCalendar {
        let start = try day(effectiveFrom)
        let session = try PlanAuthoring.session(revising: nil, today: start)
        return try PlanCalendar([session.plan(from: session.draft, effectiveFrom: start)])
    }

    func testRevisionTakesTheNextVersionNumber() throws {
        let session = try PlanAuthoring.session(revising: try storedCalendar(), today: try today)
        XCTAssertEqual(session.version, try PlanVersion(2))
        XCTAssertEqual(session.mode, .revision(supersedes: try PlanVersion(1), inEffectSince: try day("2026-06-01")))
    }

    func testRevisionCannotStartOnOrBeforeTheCurrentVersion() throws {
        let session = try PlanAuthoring.session(revising: try storedCalendar(), today: try today)
        XCTAssertEqual(session.earliestEffectiveFrom, try day("2026-06-02"))

        XCTAssertFalse(session.permitsEffectiveFrom(try day("2026-06-01")))
        XCTAssertFalse(session.permitsEffectiveFrom(try day("2026-05-31")))
        XCTAssertTrue(session.permitsEffectiveFrom(try day("2026-06-02")))

        let expected = PlanAuthoringError.effectiveFromTooEarly(earliestPermitted: try day("2026-06-02"))
        for rejected in ["2026-06-01", "2026-05-31", "2020-01-01"] {
            XCTAssertThrowsError(
                try session.plan(from: session.draft, effectiveFrom: try day(rejected))
            ) { error in
                XCTAssertEqual(error as? PlanAuthoringError, expected)
            }
        }
    }

    /// The rejection has to read as a reason, not as a field name — an athlete sees
    /// this string.
    func testBackDatingErrorNamesTheEarliestPermittedDay() throws {
        let error = PlanAuthoringError.effectiveFromTooEarly(earliestPermitted: try day("2026-06-02"))
        XCTAssertTrue(error.description.contains("2026-06-02"))
        XCTAssertFalse(error.description.contains("PlanCalendar"))
    }

    func testRevisionSuggestsTodayWhenTodayIsPermitted() throws {
        let session = try PlanAuthoring.session(revising: try storedCalendar(), today: try today)
        XCTAssertEqual(session.suggestedEffectiveFrom, try today)
    }

    /// When the current version began today, today is no longer available and the
    /// suggestion has to move forward rather than offer a date that will be refused.
    func testRevisionSuggestsTomorrowWhenTheCurrentVersionStartedToday() throws {
        let calendar = try storedCalendar(effectiveFrom: "2026-08-05")
        let session = try PlanAuthoring.session(revising: calendar, today: try today)
        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-08-06"))
        XCTAssertTrue(session.permitsEffectiveFrom(session.suggestedEffectiveFrom))
    }

    /// A revision starts from the stored version, field for field. Anything this
    /// dropped would silently reset the next time the athlete moved the HR cap.
    func testRevisionDraftReproducesTheStoredPlanExactly() throws {
        let calendar = try storedCalendar()
        guard let stored = calendar.versions.first else { return XCTFail("no stored plan") }
        let session = try PlanAuthoring.session(revising: calendar, today: try today)

        let rebuilt = try session.plan(from: session.draft, effectiveFrom: try day("2026-07-01"))
        XCTAssertEqual(rebuilt.weeklyTemplate, stored.weeklyTemplate)
        XCTAssertEqual(rebuilt.longRunArc, stored.longRunArc)
        XCTAssertEqual(rebuilt.heartRateCapBPM, stored.heartRateCapBPM)
        XCTAssertEqual(rebuilt.cadenceTarget, stored.cadenceTarget)
        XCTAssertEqual(rebuilt.rubric, stored.rubric)
        XCTAssertEqual(rebuilt.goals, stored.goals)
        // MAX-151: the floor is carried forward on a revision exactly like the cap is.
        XCTAssertEqual(rebuilt.minimumSessionDurationSeconds, stored.minimumSessionDurationSeconds)
        // Everything but the two fields a new version exists to change.
        XCTAssertNotEqual(rebuilt.version, stored.version)
        XCTAssertNotEqual(rebuilt.effectiveFrom, stored.effectiveFrom)
    }

    /// The seed must not leak into a revision. If it did, editing `StandardPlanSeed`
    /// would reach through and change a rubric the athlete had already settled.
    func testRevisionCarriesTheStoredRubricBandsRatherThanReseeding() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.effectiveThresholdPoints = 65
        var firstPlan = try session.plan(from: draft, effectiveFrom: try day("2026-06-01"))

        // A plan whose rubric has been tuned to a single band, as an athlete's own
        // rubric edit (a future ticket) would leave it.
        let ownRubric = try ScoringRubric(
            effectiveThreshold: firstPlan.rubric.effectiveThreshold,
            marginalThreshold: firstPlan.rubric.marginalThreshold,
            bands: [
                RubricBand(
                    identifier: "athletes.own.rule",
                    scoreRange: ScoreRange(lowest: 10, highest: 20),
                    rationale: "Mine."
                ),
            ]
        )
        firstPlan = try Plan(
            version: firstPlan.version,
            effectiveFrom: firstPlan.effectiveFrom,
            weeklyTemplate: firstPlan.weeklyTemplate,
            longRunArc: firstPlan.longRunArc,
            heartRateCapBPM: firstPlan.heartRateCapBPM,
            cadenceTarget: firstPlan.cadenceTarget,
            rubric: ownRubric,
            goals: firstPlan.goals
        )

        let revision = try PlanAuthoring.session(
            revising: try PlanCalendar([firstPlan]),
            today: try today
        )
        let second = try revision.plan(from: revision.draft, effectiveFrom: try day("2026-08-05"))
        XCTAssertEqual(second.rubric.bands.map(\.identifier), ["athletes.own.rule"])
    }

    /// A plan built here has to be one the store will accept — the store validates by
    /// constructing the very same calendar.
    func testARevisionSlotsIntoTheExistingCalendar() throws {
        let calendar = try storedCalendar()
        let session = try PlanAuthoring.session(revising: calendar, today: try today)
        var draft = session.draft
        draft.heartRateCapBPM = 148

        let revised = try session.plan(from: draft, effectiveFrom: try today)
        let updated = try PlanCalendar(calendar.versions + [revised])

        XCTAssertEqual(updated.plan(on: try day("2026-07-01"))?.version, try PlanVersion(1))
        XCTAssertEqual(updated.plan(on: try today)?.version, try PlanVersion(2))
        XCTAssertEqual(updated.plan(on: try today)?.heartRateCapBPM, 148)
        // D1: the earlier version's days still resolve to the earlier cap.
        XCTAssertEqual(updated.plan(on: try day("2026-07-01"))?.heartRateCapBPM, 150)
    }

    // MARK: - Field validation, translated

    func testImplausibleHeartRateCapIsRefusedWithAReadableReason() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.heartRateCapBPM = 400

        XCTAssertThrowsError(try session.plan(from: draft, effectiveFrom: try today)) { error in
            XCTAssertEqual(
                error as? PlanAuthoringError,
                .heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)
            )
        }
    }

    func testInvertedCadenceBandIsRefused() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.cadenceLowStepsPerMinute = 180
        draft.cadenceHighStepsPerMinute = 170

        XCTAssertThrowsError(try session.plan(from: draft, effectiveFrom: try today)) { error in
            XCTAssertEqual(error as? PlanAuthoringError, .cadenceBandInverted)
        }
    }

    func testInvertedScoreThresholdsAreRefused() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.effectiveThresholdPoints = 40
        draft.marginalThresholdPoints = 60

        XCTAssertThrowsError(try session.plan(from: draft, effectiveFrom: try today)) { error in
            XCTAssertEqual(error as? PlanAuthoringError, .thresholdsInverted)
        }
    }

    func testOutOfRangeScoreThresholdIsRefused() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.effectiveThresholdPoints = 140

        XCTAssertThrowsError(try session.plan(from: draft, effectiveFrom: try today)) { error in
            XCTAssertEqual(
                error as? PlanAuthoringError,
                .scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange)
            )
        }
    }

    func testZeroScheduledDistanceIsRefusedAndNamesTheDay() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.setDistanceMeters(0, on: .tuesday)

        XCTAssertThrowsError(try session.plan(from: draft, effectiveFrom: try today)) { error in
            XCTAssertEqual(
                error as? PlanAuthoringError,
                .scheduledDistanceNotPositive(weekday: .tuesday)
            )
        }
    }

    /// MAX-151: the floor is validated the same way every other plan-level number is,
    /// but nil — "no opinion" — is itself a legal answer, unlike a zero or negative one.
    func testTheDurationFloorMustBePositiveWhenStated() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)

        var zero = session.draft
        zero.minimumSessionDurationSeconds = 0
        XCTAssertThrowsError(try session.plan(from: zero, effectiveFrom: try today)) { error in
            XCTAssertEqual(error as? PlanAuthoringError, .minimumSessionDurationNotPositive)
        }

        var negative = session.draft
        negative.minimumSessionDurationSeconds = -60
        XCTAssertThrowsError(try session.plan(from: negative, effectiveFrom: try today)) { error in
            XCTAssertEqual(error as? PlanAuthoringError, .minimumSessionDurationNotPositive)
        }
    }

    /// The floor can be cleared back to "no opinion" — an athlete who decides the seed's
    /// number was wrong for them is not stuck choosing a different positive one.
    func testTheDurationFloorCanBeClearedToNoOpinion() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        XCTAssertNotNil(draft.minimumSessionDurationSeconds)

        draft.minimumSessionDurationSeconds = nil
        let plan = try session.plan(from: draft, effectiveFrom: try today)
        XCTAssertNil(plan.minimumSessionDurationSeconds)
    }

    /// And it can be set to a different positive value, which reaches the saved plan —
    /// the authoring screen's own acceptance criterion.
    func testADifferentDurationFloorReachesTheSavedPlan() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.minimumSessionDurationSeconds = 900

        let plan = try session.plan(from: draft, effectiveFrom: try today)
        XCTAssertEqual(plan.minimumSessionDurationSeconds, 900)
    }

    // MARK: - Editing the draft

    func testChoosingRestClearsTheDistanceSoTheDraftStaysConvertible() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        XCTAssertNotNil(draft[.tuesday].distanceMeters)

        draft.setKind(.rest, on: .tuesday)
        XCTAssertNil(draft[.tuesday].distanceMeters)
        XCTAssertNil(draft[.tuesday].note)

        // And a distance set afterwards is ignored rather than parked in a state that
        // only fails at save time.
        draft.setDistanceMeters(5_000, on: .tuesday)
        XCTAssertNil(draft[.tuesday].distanceMeters)

        XCTAssertNoThrow(try session.plan(from: draft, effectiveFrom: try today))
    }

    func testTheWeekAlwaysHasSevenDaysMondayFirst() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        XCTAssertEqual(session.draft.week.map(\.weekday), Weekday.allCases.sorted())
    }

    func testArcWeeksAreAppendedAndRemovedFromTheEnd() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        let originalCount = draft.longRunArc.count

        draft.appendLongRunWeek()
        XCTAssertEqual(draft.longRunArc.count, originalCount + 1)
        XCTAssertEqual(draft.longRunArc.last?.index, originalCount + 1)
        XCTAssertEqual(draft.longRunArc.last?.distanceMeters, draft.longRunArc[originalCount - 1].distanceMeters)

        draft.removeLastLongRunWeek()
        XCTAssertEqual(draft.longRunArc.count, originalCount)
    }

    /// `LongRunArc` rejects an empty arc, so the last week must not be removable —
    /// otherwise the draft becomes unconvertible with no obvious way back.
    func testTheFinalArcWeekCannotBeRemoved() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        for _ in 0..<(StandardPlanSeed.arcWeekCount + 5) {
            draft.removeLastLongRunWeek()
        }
        XCTAssertEqual(draft.longRunArc.count, 1)
        XCTAssertNoThrow(try session.plan(from: draft, effectiveFrom: try today))
    }

    func testRampedArcIsAscendingAndHitsBothEnds() throws {
        let weeks = try PlanDraft.rampedArc(
            firstWeekDistanceMeters: 14_000,
            peakWeekDistanceMeters: 32_000,
            weekCount: 16
        )
        XCTAssertEqual(weeks.count, 16)
        XCTAssertEqual(weeks.map(\.index), Array(1...16))
        XCTAssertEqual(weeks.first?.distanceMeters, 14_000)
        XCTAssertEqual(weeks.last?.distanceMeters, 32_000)
        for position in weeks.indices.dropFirst() {
            XCTAssertGreaterThan(weeks[position].distanceMeters, weeks[position - 1].distanceMeters)
        }
    }

    func testRampedArcOfOneWeekIsThePeak() throws {
        let weeks = try PlanDraft.rampedArc(
            firstWeekDistanceMeters: 14_000,
            peakWeekDistanceMeters: 32_000,
            weekCount: 1
        )
        XCTAssertEqual(weeks.map(\.distanceMeters), [32_000])
    }

    func testGoalStatementsDropBlankLines() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        var draft = session.draft
        draft.goalStatements = "Sub-4:00 marathon\n\n  Hold 150 on easy days  \n"
        draft.goalTargetDay = try day("2026-11-01")

        let plan = try session.plan(from: draft, effectiveFrom: try today)
        XCTAssertEqual(plan.goals.statements, ["Sub-4:00 marathon", "Hold 150 on easy days"])
        XCTAssertEqual(plan.goals.targetDay, try day("2026-11-01"))
    }

    // MARK: - What the version would govern

    func testGovernedDaysResolveTheWeekTheVersionPrescribes() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        let start = try day("2026-08-03") // a Monday
        let days = try session.governedDays(from: session.draft, effectiveFrom: start)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, start)
        XCTAssertEqual(days.map(\.planVersion), Array(repeating: try PlanVersion(1), count: 7))
        XCTAssertEqual(days.first?.scheduledSession.kind, .rest)
    }

    /// The long run in the preview must carry the *arc's* distance for its week, not
    /// the template's placeholder — that substitution is the only way to notice an arc
    /// that starts on the wrong week before saving.
    func testGovernedDaysSubstituteTheArcDistanceIntoTheLongRun() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        let start = try day("2026-08-03")
        let days = try session.governedDays(from: session.draft, effectiveFrom: start)

        guard let sunday = days.first(where: { $0.scheduledSession.kind == .long }) else {
            return XCTFail("the seeded week has no long run")
        }
        XCTAssertEqual(sunday.scheduledSession.distanceMeters, session.draft.longRunArc[0].distanceMeters)
    }

    func testGovernedDaysRefuseABackDatedRevision() throws {
        let session = try PlanAuthoring.session(revising: try storedCalendar(), today: try today)
        XCTAssertThrowsError(
            try session.governedDays(from: session.draft, effectiveFrom: try day("2026-05-01"))
        )
    }
}
