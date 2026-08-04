import Foundation
import XCTest
@testable import MaximizeCore

final class WorkoutTests: XCTestCase {
    func testValidWorkoutExposesElapsedTime() throws {
        let workout = try Fixture.workout(durationSeconds: 3_600)
        XCTAssertEqual(workout.elapsedSeconds, 3_600, accuracy: 0.001)
        XCTAssertEqual(workout.id, Fixture.workoutID)
        XCTAssertTrue(workout.activityType.isRun)
    }

    func testRejectsEndBeforeStart() {
        assertThrows(
            .inconsistent,
            try Workout(
                id: Fixture.workoutID,
                activityType: .running,
                start: Fixture.epoch,
                end: Fixture.epoch.addingTimeInterval(-60),
                durationSeconds: 0,
                hasRoute: false,
                source: .appleWatch,
                ingestedAt: Fixture.epoch
            )
        )
    }

    /// A duration longer than the wall-clock span means the two fields describe
    /// different workouts — the sort of mismatch that silently halves a pace.
    func testRejectsDurationLongerThanElapsedSpan() {
        assertThrows(
            .inconsistent,
            try Workout(
                id: Fixture.workoutID,
                activityType: .running,
                start: Fixture.epoch,
                end: Fixture.epoch.addingTimeInterval(600),
                durationSeconds: 900,
                hasRoute: false,
                source: .appleWatch,
                ingestedAt: Fixture.epoch
            )
        )
    }

    /// Paused workouts are legitimate: duration shorter than elapsed must pass.
    func testAcceptsPausedWorkoutWhereDurationIsShorterThanElapsed() throws {
        let workout = try Workout(
            id: Fixture.workoutID,
            activityType: .running,
            start: Fixture.epoch,
            end: Fixture.epoch.addingTimeInterval(3_900),
            durationSeconds: 3_600,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: Fixture.epoch
        )
        XCTAssertEqual(workout.elapsedSeconds - workout.durationSeconds, 300, accuracy: 0.001)
    }

    func testRejectsNegativeAndNonFiniteQuantities() {
        assertThrows(.outOfRange, try Fixture.workout(distanceMeters: -1))
        assertThrows(.notFinite, try Fixture.workout(distanceMeters: Double.nan))
        assertThrows(.notFinite, try Fixture.workout(distanceMeters: Double.infinity))
        assertThrows(
            .outOfRange,
            try Workout(
                id: Fixture.workoutID,
                activityType: .running,
                start: Fixture.epoch,
                end: Fixture.epoch.addingTimeInterval(600),
                durationSeconds: -60,
                hasRoute: false,
                source: .appleWatch,
                ingestedAt: Fixture.epoch
            )
        )
    }

    func testIndoorRunIsFirstClassWithNoRoute() throws {
        let treadmill = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        XCTAssertTrue(treadmill.activityType.isRun)
        XCTAssertFalse(treadmill.activityType.isOutdoorByNature)
        XCTAssertFalse(treadmill.hasRoute)
    }

    func testUnknownActivityTypeSurvivesDecoding() throws {
        let exotic = ActivityType(rawValue: "underwaterHockey")
        XCTAssertFalse(exotic.isRun)
        XCTAssertEqual(try roundTripped(exotic), exotic)
    }

    func testCalendarDayUsesTheStartInstant() throws {
        let lateNight = try Workout(
            id: Fixture.workoutID,
            activityType: .running,
            // 2026-01-01T23:50:00Z, finishing after midnight UTC.
            start: Date(timeIntervalSince1970: 1_767_311_400),
            end: Date(timeIntervalSince1970: 1_767_313_200),
            durationSeconds: 1_800,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: Fixture.epoch
        )
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(try lateNight.calendarDay(in: utc), try Fixture.day(2026, 1, 1))
    }

    func testRoundTripsThroughJSON() throws {
        let workout = try Fixture.workout()
        XCTAssertEqual(try roundTripped(workout), workout)
    }

    /// Decoding must run the same validation as construction; otherwise a corrupt
    /// store re-introduces states the initializers exist to forbid.
    func testDecodingRejectsAWorkoutThatEndsBeforeItStarts() throws {
        let json = """
        {"wrapped":{"id":"11111111-1111-1111-1111-111111111111","activityType":"running",\
        "start":100,"end":0,"durationSeconds":0,"hasRoute":false,"source":"appleWatch","ingestedAt":0}}
        """
        struct Box: Decodable {
            let wrapped: Workout
        }
        let data = try XCTUnwrap(json.data(using: .utf8))
        assertThrows(.inconsistent, try JSONDecoder().decode(Box.self, from: data))
    }
}
