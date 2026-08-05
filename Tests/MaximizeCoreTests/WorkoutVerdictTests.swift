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

    /// The prescription is still reported. A day that asked for an easy run and got a
    /// lift is a real thing the header should say plainly, and it can only say it if
    /// this state keeps carrying the ask.
    func testALiftOnAGovernedDayStillReportsWhatThePlanAsked() throws {
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000)
        )

        let verdict = WorkoutVerdict(
            workout: try Fixture.workout(activityType: .traditionalStrengthTraining),
            planDay: planDay,
            ledger: nil
        )

        XCTAssertEqual(verdict.scheduledSession, planDay.scheduledSession)
        XCTAssertEqual(verdict.scoring, .noVerdict)
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
}
