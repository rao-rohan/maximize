import Foundation
import XCTest
@testable import MaximizeCore

/// Shared, deliberately boring values so each test says only what it is about.
enum Fixture {
    static let workoutID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    static let otherWorkoutID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()

    static let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> CalendarDay {
        try CalendarDay(year: year, month: month, day: dayOfMonth)
    }

    static func samples(_ pairs: [(Double, Double)]) throws -> [HeartRateSample] {
        try pairs.map { try HeartRateSample(offsetSeconds: $0.0, beatsPerMinute: $0.1) }
    }

    static func workout(
        id: UUID = Fixture.workoutID,
        activityType: ActivityType = .running,
        durationSeconds: Double = 3_600,
        distanceMeters: Double? = 10_000,
        hasRoute: Bool = true
    ) throws -> Workout {
        try Workout(
            id: id,
            activityType: activityType,
            start: epoch,
            end: epoch.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: 700,
            hasRoute: hasRoute,
            source: .appleWatch,
            ingestedAt: epoch.addingTimeInterval(durationSeconds + 120)
        )
    }
}
