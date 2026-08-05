import XCTest
@testable import MaximizeCore

/// MAX-130's structural claim: there is exactly one place that decides which figures
/// describe which discipline, and a metric cannot be added without passing through it.
///
/// The claim has two halves and each needs its own guard. `DerivedMetricKind.requirement`
/// is an exhaustive `switch`, so a new *case* does not compile until someone answers the
/// question — the compiler holds that half. Nothing in the compiler stops a new *field*
/// being added to `DerivedMetrics` without a case, so this file holds the other half by
/// reflection.
final class DerivedMetricKindTests: XCTestCase {
    /// `DerivedMetrics` properties that are not figures: identity, provenance, and the
    /// backfill bookkeeping flag MAX-067 added. Anything else must be a metric that has
    /// chosen its disciplines.
    private static let bookkeepingProperties: Set<String> = [
        "workoutID",
        "distanceSplitsComputed",
        "planVersion",
    ]

    private func referenceMetrics() throws -> DerivedMetrics {
        try DerivedMetrics(workoutID: Fixture.workoutID, planVersion: PlanVersion(1))
    }

    // MARK: - The record and the vocabulary cover each other

    /// Add a figure to `DerivedMetrics` without giving it a `DerivedMetricKind` case and
    /// this fails — which is the whole point, because a figure with no case is a figure
    /// nobody was asked to place on a discipline, and it will be computed for every
    /// workout by default.
    func testEveryFigureOnTheRecordHasChosenItsDisciplines() throws {
        for child in Mirror(reflecting: try referenceMetrics()).children {
            let label = try XCTUnwrap(child.label, "an unlabelled stored property on DerivedMetrics")
            guard !Self.bookkeepingProperties.contains(label) else { continue }
            XCTAssertNotNil(
                DerivedMetricKind(rawValue: label),
                """
                DerivedMetrics.\(label) has no DerivedMetricKind case. Add one — the case \
                is where you say which disciplines this figure describes, and without it \
                the calculator will compute it for a lift.
                """
            )
        }
    }

    /// The converse: a case naming a property that no longer exists would silently stop
    /// gating anything.
    func testEveryKindNamesAFigureTheRecordActuallyCarries() throws {
        let properties = Set(Mirror(reflecting: try referenceMetrics()).children.compactMap(\.label))
        for kind in DerivedMetricKind.allCases {
            XCTAssertTrue(
                properties.contains(kind.rawValue),
                "DerivedMetricKind.\(kind.rawValue) names no property of DerivedMetrics"
            )
        }
        XCTAssertEqual(
            DerivedMetricKind.allCases.count,
            properties.count - Self.bookkeepingProperties.count
        )
    }

    // MARK: - The applicability rules themselves

    /// MAX-111's behaviour, restated against the new decision point rather than against
    /// `isRun` at three call sites. If any of these move, a run's stored metrics move.
    func testARunGetsEveryFigure() {
        for activityType in [ActivityType.running, .treadmillRunning] {
            XCTAssertEqual(
                DerivedMetricKind.applicable(to: activityType),
                DerivedMetricKind.allCases,
                "\(activityType)"
            )
        }
    }

    /// The gap between `Discipline.run` and `ActivityType.isRun`, and the reason
    /// `.runningActivity` is not spelled `discipline == .run`. A ride and a hike sit in
    /// the run slot — A17 is explicit that they are not disciplines of their own — and
    /// still get no running form, because they have none.
    func testARunSlotActivityThatIsNotARunGetsTheCapFiguresAndNoRunningForm() {
        for activityType in [ActivityType.hiking, .cycling, .walking, .other] {
            XCTAssertEqual(activityType.discipline, .run, "\(activityType)")

            XCTAssertTrue(DerivedMetricKind.timeAboveCapSeconds.applies(to: activityType), "\(activityType)")
            XCTAssertTrue(DerivedMetricKind.zoneSplits.applies(to: activityType), "\(activityType)")

            XCTAssertFalse(
                DerivedMetricKind.averageCadenceStepsPerMinute.applies(to: activityType), "\(activityType)"
            )
            XCTAssertFalse(
                DerivedMetricKind.gradeAdjustedPaceSecondsPerKilometer.applies(to: activityType),
                "\(activityType)"
            )
            XCTAssertFalse(DerivedMetricKind.distanceSplits.applies(to: activityType), "\(activityType)")
        }
    }

    /// MAX-111's answer for a lift, unchanged by the move: the running-shaped figures
    /// go, the heart-rate ones stay. What a lift's record *should* contain is a separate
    /// question from where the decision lives, and it is asked next.
    func testALiftGetsTheHeartRateFiguresAndNoRunningForm() {
        XCTAssertEqual(
            DerivedMetricKind.applicable(to: .traditionalStrengthTraining),
            [
                .averageHeartRateBPM,
                .maximumHeartRateBPM,
                .timeAboveCapSeconds,
                .heartRateDriftFraction,
                .zoneSplits,
            ]
        )
    }

    /// An activity type nobody has named yet is a run-slot activity that is not a run —
    /// the residual, per `Discipline`. It must therefore behave exactly like a hike, and
    /// in particular must not acquire a cadence.
    func testAnUnknownActivityTypeIsTreatedAsARunSlotNonRun() {
        let unknown = ActivityType(rawValue: "paddleboarding")
        XCTAssertEqual(
            DerivedMetricKind.applicable(to: unknown),
            DerivedMetricKind.applicable(to: .hiking)
        )
        XCTAssertFalse(DerivedMetricKind.averageCadenceStepsPerMinute.applies(to: unknown))
    }

    /// A figure a lift is entitled to must be one every workout is entitled to: nothing
    /// but `.anyDiscipline` can reach the lift slot, because `isRun` is defined through
    /// `Discipline` and excludes it (see `ActivityType.isRun`). Stated as a property so
    /// a requirement added later cannot quietly become a second route in.
    func testALiftOnlyEverGetsTheFiguresEveryWorkoutGets() {
        for kind in DerivedMetricKind.allCases where kind.applies(to: .traditionalStrengthTraining) {
            XCTAssertEqual(kind.requirement, .anyDiscipline, "\(kind.rawValue)")
        }
    }

    func testRawValuesAreTheFieldNames() {
        XCTAssertEqual(DerivedMetricKind.timeAboveCapSeconds.rawValue, "timeAboveCapSeconds")
        XCTAssertEqual(DerivedMetricKind.zoneSplits.rawValue, "zoneSplits")
    }
}
