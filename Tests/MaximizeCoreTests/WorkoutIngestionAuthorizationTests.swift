import XCTest
@testable import MaximizeCore

/// Guards the *scope* of the HealthKit permission request.
///
/// The request itself needs a device, but which types it covers is plain data and is
/// checked here on every commit — see CLAUDE.md, "push the logic down until the
/// untestable part is a thin adapter with no decisions in it."
final class WorkoutIngestionAuthorizationTests: XCTestCase {
    func testNoWriteScopesAreRequested() {
        // PRD §3 names writing to HealthKit an explicit non-goal. This is the
        // mechanical enforcement of that: the app layer builds its `toShare:` set by
        // mapping this collection, so a non-empty set here would be the only way a
        // write scope could ever reach the permission sheet.
        XCTAssertTrue(WorkoutIngestionAuthorization.writeTypes.isEmpty)
    }

    func testReadScopeCoversWorkoutsAndTheSamplesTheMetricsNeed() {
        // FR-0.3: type, start/end, duration, distance, active energy, full HR series,
        // GPS route. Cadence (PRD §9) is derived from step count.
        let expected: Set<HealthDataType> = [
            .workout,
            .heartRate,
            .distanceWalkingRunning,
            .activeEnergyBurned,
            .stepCount,
            .workoutRoute,
        ]
        XCTAssertEqual(WorkoutIngestionAuthorization.readTypes, expected)
    }

    func testEveryDeclaredHealthDataTypeIsActuallyRequested() {
        // A case added to `HealthDataType` but never added to `readTypes` would be a
        // type the pipeline believes it can read and silently cannot. Fail loudly at
        // the point the case is introduced instead.
        XCTAssertEqual(WorkoutIngestionAuthorization.readTypes, Set(HealthDataType.allCases))
    }

    func testWorkoutIsInTheReadScopeBecauseTheObserverWatchesIt() {
        // FR-0.1's observer query runs against the workout type; without read
        // authorization for it the query returns nothing and the wake path is inert.
        XCTAssertTrue(WorkoutIngestionAuthorization.readTypes.contains(.workout))
    }
}
