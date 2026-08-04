import XCTest
@testable import MaximizeCore

/// The two mapping rules the HealthKit adapter would otherwise have to make up on its
/// own, where CI could not see them.
final class CapturedWorkoutMappingTests: XCTestCase {
    func testAnIndoorRunIsATreadmillRun() {
        // FR-0.6: not a degraded run, a different kind of run — one that legitimately
        // has no route.
        XCTAssertEqual(ActivityType.captured(activityName: "running", isIndoor: true), .treadmillRunning)
    }

    func testAnOutdoorRunIsARun() {
        XCTAssertEqual(ActivityType.captured(activityName: "running", isIndoor: false), .running)
    }

    func testBothKindsOfRunAreScoredAsRuns() {
        XCTAssertTrue(ActivityType.captured(activityName: "running", isIndoor: true).isRun)
        XCTAssertTrue(ActivityType.captured(activityName: "running", isIndoor: false).isRun)
    }

    func testTheIndoorFlagOnlyChangesRunning() {
        // An indoor cycle is still cycling; there is no domain distinction to draw.
        XCTAssertEqual(ActivityType.captured(activityName: "cycling", isIndoor: true), .cycling)
    }

    func testAnUnrecognisedActivityPassesThrough() {
        // `ActivityType` is an open wrapper on purpose: a new activity must degrade, not
        // fail to record a workout the user actually did.
        XCTAssertEqual(
            ActivityType.captured(activityName: "pickleball", isIndoor: false),
            ActivityType(rawValue: "pickleball")
        )
    }

    func testAnEmptyActivityNameBecomesOther() {
        XCTAssertEqual(ActivityType.captured(activityName: "  ", isIndoor: false), .other)
    }

    func testProductTypesMapToSources() {
        XCTAssertEqual(WorkoutSource.captured(productType: "Watch6,1"), .appleWatch)
        XCTAssertEqual(WorkoutSource.captured(productType: "iPhone14,2"), .iPhone)
        XCTAssertEqual(WorkoutSource.captured(productType: "iPad13,1"), .unknown)
        XCTAssertEqual(WorkoutSource.captured(productType: nil), .unknown)
        XCTAssertEqual(WorkoutSource.captured(productType: ""), .unknown)
    }
}
