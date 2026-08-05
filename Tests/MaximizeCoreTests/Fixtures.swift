import Foundation
import XCTest
@testable import MaximizeCore

/// Shared, deliberately boring values so each test says only what it is about.
enum Fixture {
    static let workoutID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    static let otherWorkoutID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()

    /// A22's muscle-group entry has its own identity, not the workout's — a workout
    /// accumulates entries, so a fixture that reused `workoutID` would hide the
    /// difference.
    static let muscleGroupEntryID = UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID()

    static let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> CalendarDay {
        try CalendarDay(year: year, month: month, day: dayOfMonth)
    }

    /// `epoch` plus an offset, so a test can say when a turn happened in seconds.
    static func at(_ offsetSeconds: Double) -> Date {
        epoch.addingTimeInterval(offsetSeconds)
    }

    static func scope(
        from start: (Int, Int, Int),
        through end: (Int, Int, Int)
    ) throws -> TrainingScope {
        try TrainingScope(
            from: day(start.0, start.1, start.2),
            through: day(end.0, end.1, end.2)
        )
    }

    /// A thread, with `lastActivityAt` defaulted to the last turn (MAX-092).
    ///
    /// The default exists so tests that are about ordering, subjects or titles do not
    /// have to restate an invariant `ChatThread` already enforces. A test that is
    /// *about* `lastActivityAt` passes it.
    static func thread(
        id: UUID = UUID(),
        subject: ChatSubject = .workout(Fixture.workoutID),
        messages: [ChatMessage] = [],
        lastActivityAt: Date? = nil
    ) throws -> ChatThread {
        try ChatThread(
            id: id,
            subject: subject,
            messages: messages,
            lastActivityAt: lastActivityAt ?? messages.last?.timestamp ?? epoch
        )
    }

    static func message(
        _ role: ChatRole,
        _ content: String,
        at offsetSeconds: Double
    ) throws -> ChatMessage {
        try ChatMessage(id: UUID(), role: role, content: content, timestamp: at(offsetSeconds))
    }

    static func samples(_ pairs: [(Double, Double)]) throws -> [HeartRateSample] {
        try pairs.map { try HeartRateSample(offsetSeconds: $0.0, beatsPerMinute: $0.1) }
    }

    /// - Parameter lift: the lift slot. Defaults to empty — i.e. rest on every weekday,
    ///   which is what every plan authored before MAX-129 prescribes, so every existing
    ///   test keeps measuring exactly what it measured before.
    static func weeklyTemplate(lift: [Weekday: ScheduledSession] = [:]) throws -> WeeklyTemplate {
        try WeeklyTemplate(
            [
                .monday: .rest,
                .tuesday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
                .thursday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .friday: .rest,
                .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
                .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000),
            ],
            lift: lift
        )
    }

    /// A rubric shaped like PRD §10.3's worked example, written entirely as data.
    static func rubric(effectiveThreshold: Int = 70, marginalThreshold: Int = 45) throws -> ScoringRubric {
        try ScoringRubric(
            effectiveThreshold: ScoreValue(effectiveThreshold),
            marginalThreshold: ScoreValue(marginalThreshold),
            bands: [
                RubricBand(
                    identifier: "easy.onCap.lowDrift",
                    appliesTo: [.easy],
                    conditions: [
                        .actualClassification(oneOf: [.easy]),
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 0)
                        ),
                        .metric(
                            metric: .heartRateDriftFraction,
                            comparison: .lessThan,
                            reference: .constant(0.05)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 90, highest: 100),
                    rationale: "Held the cap with minimal drift."
                ),
                RubricBand(
                    identifier: "easy.onCap.lateDrift",
                    appliesTo: [.easy],
                    conditions: [
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 0)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 75, highest: 89),
                    rationale: "Under cap, but drifted late."
                ),
                RubricBand(
                    identifier: "easy.slightlyOverCap",
                    appliesTo: [.easy],
                    conditions: [
                        .metric(
                            metric: .averageHeartRateBPM,
                            comparison: .lessThanOrEqual,
                            reference: .heartRateCap(offsetBPM: 8)
                        ),
                    ],
                    scoreRange: ScoreRange(lowest: 55, highest: 74),
                    rationale: "Ran above the easy cap."
                ),
                RubricBand(
                    identifier: "easy.ranHardInstead",
                    appliesTo: [.easy],
                    conditions: [.actualClassification(oneOf: [.hard])],
                    scoreRange: ScoreRange(lowest: 20, highest: 45),
                    rationale: "Ran hard on an easy day."
                ),
                RubricBand(
                    identifier: "skipped",
                    conditions: [.noWorkoutRecorded],
                    scoreRange: ScoreRange(lowest: 0, highest: 15),
                    rationale: "No workout recorded for a scheduled session."
                ),
            ]
        )
    }

    static func plan(
        version: Int = 1,
        heartRateCapBPM: Double = 150,
        minimumSessionDurationSeconds: Double? = nil
    ) throws -> Plan {
        try Plan(
            version: PlanVersion(version),
            effectiveFrom: day(2026, 1, 1),
            weeklyTemplate: weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: heartRateCapBPM,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: rubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"], targetDay: day(2026, 4, 20)),
            minimumSessionDurationSeconds: minimumSessionDurationSeconds
        )
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

    /// The band is derived here only because this is test scaffolding standing in for
    /// a scorer. Production code must not turn a number into a `ScoreBand`; that
    /// decision belongs to MAX-015, reading the plan version's thresholds.
    /// - Parameters:
    ///   - scheduledKind/actualClassification: the plan-versus-execution pair the
    ///     scorer recorded. They agree by default, which is the ordinary case; pass
    ///     differing values to build a run that diverged from what was prescribed
    ///     (`ScoreCalendarTests`).
    static func score(
        points: Int,
        threshold: Int = 70,
        marginal: Int = 45,
        workoutID: UUID = Fixture.workoutID,
        scheduledKind: ScheduledSessionKind = .easy,
        actualClassification: WorkoutClassification = .easy
    ) throws -> Score {
        // `ScheduledSession` rejects a rest day carrying a distance; no caller passes
        // `.rest` today, and this keeps the fixture from becoming a trap if one does.
        let scheduledDistance: Double? = scheduledKind == .rest ? nil : 8_000
        let band: ScoreBand
        if points >= threshold {
            band = .effective
        } else if points >= marginal {
            band = .marginal
        } else {
            band = .ineffective
        }
        return try Score(
            workoutID: workoutID,
            planVersion: PlanVersion(1),
            scheduledSession: ScheduledSession(kind: scheduledKind, distanceMeters: scheduledDistance),
            actualClassification: actualClassification,
            value: ScoreValue(points),
            effectiveThreshold: ScoreValue(threshold),
            band: band,
            rubricBandIdentifier: "easy.onCap.lowDrift",
            rationale: "Held the cap with minimal drift.",
            scoredAt: epoch
        )
    }

    static func annotation(
        points: Int,
        at offsetSeconds: Double = 0,
        workoutID: UUID = Fixture.workoutID,
        id: UUID = UUID()
    ) throws -> ScoreAnnotation {
        try ScoreAnnotation(
            id: id,
            workoutID: workoutID,
            manualScore: ScoreValue(points),
            note: "Felt harder than it looked",
            createdAt: epoch.addingTimeInterval(offsetSeconds)
        )
    }
}
