import Foundation
import XCTest
@testable import MaximizeCore

final class WorkoutVerdictTests: XCTestCase {

    // MARK: Unscored — the state every workout is in today (MAX-015/MAX-023 in flight)

    func testUnscoredWorkoutOnAGovernedDayShowsTheScheduledSessionAndTheRawActivityType() throws {
        let workout = try Fixture.workout(activityType: .running)
        let planDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000)
        )

        let verdict = WorkoutVerdict(workout: workout, planDay: planDay, ledger: nil)

        XCTAssertEqual(verdict.scheduledSession, planDay.scheduledSession)
        XCTAssertEqual(verdict.actual, .unclassified(.running))
        XCTAssertEqual(verdict.scoring, .unscored)
    }

    /// A run predating the plan (`PlanCalendar.planDay(on:)` returns nil) is a real
    /// state distinct from "the plan asked for rest" — `scheduledSession` must stay
    /// nil, not fall back to some default session.
    func testUnscoredWorkoutOnAnUngovernedDayHasNoScheduledSession() throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning)

        let verdict = WorkoutVerdict(workout: workout, planDay: nil, ledger: nil)

        XCTAssertNil(verdict.scheduledSession)
        XCTAssertEqual(verdict.actual, .unclassified(.treadmillRunning))
        XCTAssertEqual(verdict.scoring, .unscored)
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
