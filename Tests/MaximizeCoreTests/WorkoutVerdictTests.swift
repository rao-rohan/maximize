import Foundation
import XCTest
@testable import MaximizeCore

final class WorkoutVerdictTests: XCTestCase {

    // MARK: Awaiting a score — a run whose verdict has not landed yet

    func testUnscoredRunOnAGovernedDayShowsTheScheduledSessionAndTheRawActivityType() throws {
        let workout = try Fixture.workout(activityType: .running)
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000)
        )

        let verdict = WorkoutVerdict(workout: workout, planDay: planDay, ledger: nil)

        XCTAssertEqual(verdict.scheduledSession, planDay.scheduledSession)
        XCTAssertEqual(verdict.actual, .unclassified(.running))
        XCTAssertEqual(verdict.scoring, .awaitingScore)
    }

    /// A run predating the plan (`PlanCalendar.planDay(on:)` returns nil) is a real
    /// state distinct from "the plan asked for rest" — `scheduledSession` must stay
    /// nil, not fall back to some default session.
    func testUnscoredRunOnAnUngovernedDayHasNoScheduledSession() throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: nil)

        XCTAssertNil(verdict.scheduledSession)
        XCTAssertEqual(verdict.actual, .unclassified(.treadmillRunning))
        XCTAssertEqual(verdict.scoring, .awaitingScore)
    }

    // MARK: No verdict — a workout the plan has no rubric for (MAX-126)

    /// The defect. Before MAX-126 this returned `.awaitingScore`, and the header
    /// rendered that as a spinner over "Scoring runs automatically once the run is
    /// captured" — a promise that, since MAX-111 stopped non-runs being scored, the app
    /// was never going to keep.
    func testAnUnscoredLiftHasNoVerdictRatherThanAwaitingOne() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: nil)

        XCTAssertEqual(verdict.actual, .unclassified(.traditionalStrengthTraining))
        XCTAssertEqual(verdict.scoring, .noVerdict)
    }

    /// The split is `ActivityType.isRun`, the same predicate the ingestion pipeline
    /// declines to score on — so every non-run is in this state, not only the lift
    /// MAX-109 is about.
    func testEveryUnscoredNonRunHasNoVerdict() throws {
        for activityType: ActivityType in [.cycling, .hiking, .walking, .other] {
            let verdict = WorkoutVerdict(
                workout: try Fixture.workout(activityType: activityType),
                planDay: nil,
                ledger: nil
            )
            XCTAssertEqual(verdict.scoring, .noVerdict, "\(activityType)")
        }
    }

    /// The prescription is still reported — but as of MAX-139, it is the **lift** slot's
    /// ask, never the run slot's, whatever the run slot happens to say. A day prescribing
    /// only a run and no lift is a day whose lift ask is `.rest` (`PlanDay`'s default),
    /// and that is what a lift's header must show — not the easy run it did not do.
    func testALiftOnAGovernedDayReportsTheLiftAskNotTheRunAsk() throws {
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000)
            // liftSession defaults to `.rest` — this plan prescribes no lifting.
        )

        let verdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            planDay: planDay,
            ledger: nil
        )

        XCTAssertEqual(verdict.scheduledSession, .rest, "Not planDay.scheduledSession, which is the run ask")
        XCTAssertNotEqual(verdict.scheduledSession, planDay.scheduledSession)
        XCTAssertEqual(verdict.scoring, .noVerdict)
    }

    /// The mirror case: a day that prescribes both a run and a lift. A lift workout must
    /// report the lift ask, and a run workout the run ask — each discipline reads only
    /// its own slot (A17, MAX-133/MAX-139).
    func testADayPrescribingBothDisciplinesReportsEachWorkoutsOwnAsk() throws {
        let liftAsk = try ScheduledSession(kind: .lift, durationSeconds: 2_700, muscleGroups: [.chest, .back])
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000),
            liftSession: liftAsk
        )

        let liftVerdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            planDay: planDay,
            ledger: nil
        )
        let runVerdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .running),
            planDay: planDay,
            ledger: nil
        )

        XCTAssertEqual(liftVerdict.scheduledSession, liftAsk)
        XCTAssertEqual(runVerdict.scheduledSession, planDay.scheduledSession)
    }

    // MARK: `discipline` (MAX-139)

    func testDisciplineIsReadFromTheWorkoutsActivityType() throws {
        let run = WorkoutVerdict(workout: try Fixture.workout(activityType: .running), planDay: nil, ledger: nil)
        let lift = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining), planDay: nil, ledger: nil
        )

        XCTAssertEqual(run.discipline, .run)
        XCTAssertEqual(lift.discipline, .lift)
    }

    func testEveryNonLiftActivityTypeReportsTheRunDiscipline() throws {
        for activityType: ActivityType in [.running, .treadmillRunning, .cycling, .hiking, .walking, .other] {
            let verdict = WorkoutVerdict(
                workout: try Fixture.workout(activityType: activityType), planDay: nil, ledger: nil
            )
            XCTAssertEqual(verdict.discipline, .run, "\(activityType)")
        }
    }

    /// D8. A lift ingested before MAX-111 carries an immutable auto-score from the
    /// running rubric, and this ticket does not reach back and hide it — `.noVerdict` is
    /// about the *absence* of a stored score, never about overriding one that exists.
    /// Whether those historical scores should be relabelled is A21/MAX-125, and that is
    /// the owner's decision.
    func testAnAlreadyScoredLiftStillReportsItsStoredScore() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)
        let automatic = try Fixture.score(points: 30)

        let verdict = WorkoutVerdict(
            workout: workout,
            planDay: nil,
            ledger: try ScoreLedger(automatic: automatic)
        )

        XCTAssertEqual(verdict.scoring, .scored(automatic: automatic, annotation: nil))
        XCTAssertEqual(verdict.actual, .classified(automatic.actualClassification))
    }

    // MARK: Awaiting the athlete — a lift nobody has described yet (A22, MAX-145)

    private func log(
        _ groups: Set<MuscleGroup>? = nil,
        workoutID: UUID = Fixture.workoutID
    ) throws -> MuscleGroupLog {
        guard let groups else { return try MuscleGroupLog(workoutID: workoutID) }
        return try MuscleGroupLog(
            workoutID: workoutID,
            entries: [
                try MuscleGroupEntry(
                    id: Fixture.muscleGroupEntryID,
                    workoutID: workoutID,
                    groups: groups,
                    recordedAt: Fixture.at(60)
                )
            ]
        )
    }

    /// The state A22 forces into existence. A lift cannot be scored at ingestion because
    /// the groups arrive later (D2 computes once, D8 forbids revising), so the app waits
    /// — on the athlete, not on a model.
    func testALiftWithAnEmptyMuscleGroupLogIsAwaitingTheAthlete() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)

        let verdict = WorkoutVerdict(
            workout: workout,
            planDay: nil,
            ledger: nil,
            muscleGroups: try log()
        )

        XCTAssertEqual(verdict.scoring, .awaitingMuscleGroups)
        XCTAssertNil(verdict.muscleGroupEntry)
        XCTAssertEqual(verdict.actual, .unclassified(.traditionalStrengthTraining))
    }

    /// Once the athlete has answered, the prompt stops. Nothing scores a lift yet — the
    /// rubric is MAX-131/132 — so the honest state is the one that says no verdict is
    /// coming, not a spinner.
    func testALiftTheAthleteHasDescribedNoLongerPrompts() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)

        let verdict = WorkoutVerdict(
            workout: workout,
            planDay: nil,
            ledger: nil,
            muscleGroups: try log([.chest, .shoulders])
        )

        XCTAssertEqual(verdict.scoring, .noVerdict)
        XCTAssertEqual(verdict.muscleGroupEntry?.groups, [.chest, .shoulders])
    }

    /// **A run is untouched by all of this.** No run is ever asked what muscles it
    /// worked, so a log passed for one cannot change its state — not even an empty one.
    func testARunIsUnaffectedByTheMuscleGroupLog() throws {
        for activityType: ActivityType in [.running, .treadmillRunning] {
            let verdict = WorkoutVerdict(
                workout: try Fixture.workout(activityType: activityType),
                planDay: nil,
                ledger: nil,
                muscleGroups: try log()
            )
            XCTAssertEqual(verdict.scoring, .awaitingScore, "\(activityType)")
        }
    }

    /// A ride, a hike and a walk are not lifts, so they are not asked either — their
    /// absence of a score is permanent (MAX-126), not a question waiting for an answer.
    func testANonRunThatIsNotALiftIsNeverAwaitingTheAthlete() throws {
        for activityType: ActivityType in [.cycling, .hiking, .walking, .other] {
            let verdict = WorkoutVerdict(
                workout: try Fixture.workout(activityType: activityType),
                planDay: nil,
                ledger: nil,
                muscleGroups: try log()
            )
            XCTAssertEqual(verdict.scoring, .noVerdict, "\(activityType)")
        }
    }

    /// Nil is "this caller did not look", not "the athlete has not said". A call site
    /// with no muscle-group log to hand — `ContextBuilder`, today — must resolve exactly
    /// as it did before A22 rather than assert a state it never read.
    func testACallerThatSuppliesNoLogResolvesExactlyAsBeforeA22() throws {
        let verdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            planDay: nil,
            ledger: nil
        )
        XCTAssertEqual(verdict.scoring, .noVerdict)
        XCTAssertNil(verdict.muscleGroupEntry)
    }

    /// D8, restated for this ticket: a lift already carrying an immutable auto-score
    /// (A21/MAX-143's history) keeps reporting it, whatever the athlete has or has not
    /// said about muscle groups. The entry is additive information, never a reason to
    /// revisit a verdict.
    func testAnAlreadyScoredLiftIsNotMovedIntoTheWaitingState() throws {
        let automatic = try Fixture.score(points: 30)

        let verdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            planDay: nil,
            ledger: try ScoreLedger(automatic: automatic),
            muscleGroups: try log()
        )

        XCTAssertEqual(verdict.scoring, .scored(automatic: automatic, annotation: nil))
    }

    // MARK: Scored

    /// Once a ledger exists, "actual" switches to the stored classification rather
    /// than the raw capture type — the classification the scorer already resolved
    /// against the plan (D2: never recompute what was already decided).
    func testScoredWorkoutUsesTheStoredClassificationNotTheRawActivityType() throws {
        let workout = try Fixture.workout(activityType: .running)
        let automatic = try Fixture.score(points: 88)
        let ledger = try ScoreLedger(automatic: automatic)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: ledger)

        XCTAssertEqual(verdict.actual, .classified(automatic.actualClassification))
        XCTAssertEqual(verdict.scoring, .scored(automatic: automatic, annotation: nil))
    }

    /// D8: the auto-score stays on the record unchanged, and the correction rides
    /// alongside it rather than replacing anything this type reports.
    func testScoredWorkoutWithAnAnnotationSurfacesBothTheAutoScoreAndTheCorrection() throws {
        let workout = try Fixture.workout()
        let automatic = try Fixture.score(points: 45)
        let annotation = try Fixture.annotation(points: 80, at: 60)
        let ledger = try ScoreLedger(automatic: automatic).annotated(with: annotation)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: ledger)

        guard case let .scored(reportedAutomatic, reportedAnnotation) = verdict.scoring else {
            return XCTFail("Expected .scored")
        }
        XCTAssertEqual(reportedAutomatic, automatic)
        XCTAssertEqual(reportedAutomatic.value.points, 45, "The immutable auto-score is untouched by the correction")
        XCTAssertEqual(reportedAnnotation, annotation)
    }

    /// Only the *latest* correction is surfaced — this header is not a history view.
    func testScoredWorkoutWithMultipleAnnotationsSurfacesOnlyTheLatest() throws {
        let workout = try Fixture.workout()
        let ledger = try ScoreLedger(automatic: try Fixture.score(points: 45))
            .annotated(with: try Fixture.annotation(points: 80, at: 60))
            .annotated(with: try Fixture.annotation(points: 55, at: 120))

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: ledger)

        guard case let .scored(_, reportedAnnotation) = verdict.scoring else {
            return XCTFail("Expected .scored")
        }
        XCTAssertEqual(reportedAnnotation?.manualScore.points, 55)
    }

    func testScheduledSessionIsReportedRegardlessOfScoringState() throws {
        let workout = try Fixture.workout()
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 8),
            planVersion: try PlanVersion(1),
            scheduledSession: .rest
        )
        let ledger = try ScoreLedger(automatic: try Fixture.score(points: 10))

        let verdict = WorkoutVerdict(workout: workout, planDay: planDay, ledger: ledger)

        XCTAssertEqual(verdict.scheduledSession, .rest)
    }

    // MARK: `miscategorisationLabel` (A21/MAX-143)

    func testAnOrdinaryScoredWorkoutReportsNoMiscategorisationLabel() throws {
        let workout = try Fixture.workout(activityType: .running)
        let automatic = try Fixture.score(points: 88)
        let ledger = try ScoreLedger(automatic: automatic)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: ledger)

        XCTAssertNil(verdict.miscategorisationLabel)
    }

    func testAnUnscoredWorkoutReportsNoMiscategorisationLabel() throws {
        let verdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining), planDay: nil, ledger: nil
        )

        XCTAssertNil(verdict.miscategorisationLabel)
    }

    /// A lift scored before MAX-133 taught the scorer to resolve a workout's own
    /// discipline carries a label (A21/MAX-143), and the header reads it straight off
    /// the ledger — the same fact `ScoreLedger.miscategorisationLabel` already carries,
    /// never re-derived. The score itself is untouched (D8): same value, same band.
    func testAMiscategorisedLiftReportsItsLabel() throws {
        let workout = try Fixture.workout(activityType: .traditionalStrengthTraining)
        let automatic = try Fixture.score(points: 30, scheduledKind: .easy, actualClassification: .easy)
        let label = try XCTUnwrap(MiscategorisedScoreLabel.labelling(
            automatic,
            workoutDiscipline: .lift,
            id: UUID(),
            recordedAt: Fixture.at(120)
        ))
        let ledger = try ScoreLedger(automatic: automatic).labelled(with: label)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: ledger)

        XCTAssertEqual(verdict.miscategorisationLabel, label)
        XCTAssertEqual(verdict.scoring, .scored(automatic: automatic, annotation: nil))
    }
}
