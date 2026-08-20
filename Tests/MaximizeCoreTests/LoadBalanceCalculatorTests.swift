import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-178 — rolling 7-day (acute) and 28-day (chronic) strain sums, and their ratio,
/// over `DerivedMetrics.strain` as `DerivedMetricsRecord` already stores it.
///
/// **Every expected number here is computed by hand in the comment above it**, from the
/// figures the fixture states, never read off the implementation — the same discipline
/// `WorkoutStrainTests` holds itself to for the same reason: a test of a sum is only
/// worth something if its expectation was not captured from the code under test.
final class LoadBalanceCalculatorTests: XCTestCase {
    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func workout(on dayText: String, id: UUID = UUID()) throws -> Workout {
        let start = try day(dayText).civilAnchor()
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 300,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(1_860)
        )
    }

    /// `DerivedMetrics` carrying only what this file reads: a strain figure, with the
    /// heart-rate field the type's own invariant requires alongside one.
    private func metrics(workoutID: UUID, points: Double) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: 140,
            strain: try WorkoutStrain(points: points),
            planVersion: PlanVersion(1)
        )
    }

    // MARK: - The windows, and the hand-worked sums over them

    /// Five workouts across a full 28-day chronic window ending 2026-01-28, three of
    /// them carrying strain and two carrying none:
    ///
    /// | day | in acute (Jan 22–28)? | strain |
    /// |---|---|---|
    /// | Jan 05 | no  | 40 |
    /// | Jan 10 | no  | — (no entry) |
    /// | Jan 23 | yes | 100 |
    /// | Jan 25 | yes | — (no entry) |
    /// | Jan 28 (anchor) | yes | 20 |
    ///
    /// **Chronic sum**: 40 + 100 + 20 = **160**, over 2 workouts with no strain.
    /// **Acute sum**: 100 + 20 = **120** (the Jan 05 and Jan 10 workouts fall outside the
    /// 7-day window; Jan 25's entry is absent, not zero), over 1 workout with no strain.
    /// **Chronic weekly average**: 160 / 28 × 7 = 160 / 4 = **40**.
    /// **Ratio**: 120 / 40 = **3.0**.
    func testTheAcuteAndChronicSumsAndTheirRatioMatchHandWorkedArithmetic() throws {
        let jan05 = UUID()
        let jan10 = UUID()
        let jan23 = UUID()
        let jan25 = UUID()
        let jan28 = UUID()

        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                historyStart: try day("2026-01-01"), // exactly 28 days of history
                workouts: [
                    try workout(on: "2026-01-05", id: jan05),
                    try workout(on: "2026-01-10", id: jan10),
                    try workout(on: "2026-01-23", id: jan23),
                    try workout(on: "2026-01-25", id: jan25),
                    try workout(on: "2026-01-28", id: jan28),
                ],
                derivedMetricsByWorkoutID: [
                    jan05: try metrics(workoutID: jan05, points: 40),
                    jan23: try metrics(workoutID: jan23, points: 100),
                    jan28: try metrics(workoutID: jan28, points: 20),
                    // jan10 and jan25 carry no entry at all.
                ]
            )
        )

        guard case let .available(balance) = reading else {
            return XCTFail("28 days of history should already be enough for a reading")
        }
        XCTAssertEqual(balance.chronicStrainPoints, 160, accuracy: 1e-9)
        XCTAssertEqual(balance.acuteStrainPoints, 120, accuracy: 1e-9)
        XCTAssertEqual(balance.chronicWeeklyAveragePoints, 40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(balance.ratio), 3.0, accuracy: 1e-9)
        XCTAssertEqual(balance.chronicWorkoutsWithoutStrain, 2)
        XCTAssertEqual(balance.acuteWorkoutsWithoutStrain, 1)
    }

    /// `anchor` itself is inside both windows — unlike `TalliesInput.today`, which
    /// `TalliesCalculator` excludes because an obligation cannot be judged before the day
    /// ends. This calculator judges nothing; a strain figure already computed this
    /// morning is a known cost the moment it exists, and the fixture above already
    /// exercises this (the Jan 28 workout, on `anchor` itself, is counted in both sums).
    /// This test isolates the claim on its own: a lone workout on `anchor`, with no other
    /// workout in either window, must still be summed.
    func testTheAnchorDayItselfIsIncludedInBothWindows() throws {
        let id = UUID()
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                historyStart: try day("2026-01-01"),
                workouts: [try workout(on: "2026-01-28", id: id)],
                derivedMetricsByWorkoutID: [id: try metrics(workoutID: id, points: 55)]
            )
        )

        guard case let .available(balance) = reading else {
            return XCTFail("28 days of history should already be enough for a reading")
        }
        XCTAssertEqual(balance.acuteStrainPoints, 55, accuracy: 1e-9)
        XCTAssertEqual(balance.chronicStrainPoints, 55, accuracy: 1e-9)
    }

    /// A workout outside the chronic window — one day before it starts — never reaches
    /// either sum, even though it was handed to the calculator. The window narrows its
    /// own input rather than trusting the caller to have pre-filtered it, the same
    /// defensive narrowing `TalliesCalculator` and `TrendTileData` both apply to their
    /// own wider inputs.
    func testAWorkoutOneDayBeforeTheChronicWindowIsExcluded() throws {
        let outside = UUID()
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                historyStart: try day("2025-12-01"),
                // The chronic window starts 2026-01-01; this workout is on 2025-12-31.
                workouts: [try workout(on: "2025-12-31", id: outside)],
                derivedMetricsByWorkoutID: [outside: try metrics(workoutID: outside, points: 999)]
            )
        )

        guard case let .available(balance) = reading else {
            return XCTFail("historyStart is well before the window; a reading is expected")
        }
        XCTAssertEqual(balance.chronicStrainPoints, 0, accuracy: 1e-9)
        XCTAssertEqual(
            balance.chronicWorkoutsWithoutStrain, 0,
            "the workout was excluded, not counted as strainless"
        )
    }

    // MARK: - Partial history is a designed absence state, not a truncated sum

    /// One day short of the chronic window's length: `.buildingHistory`, regardless of
    /// how much strain the short history it does have contains.
    func testFewerThanTwentyEightDaysOfHistoryYieldsTheBuildingHistoryState() throws {
        let id = UUID()
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                // 2026-01-02 through 2026-01-28 inclusive is 27 days — one short.
                historyStart: try day("2026-01-02"),
                workouts: [try workout(on: "2026-01-28", id: id)],
                derivedMetricsByWorkoutID: [id: try metrics(workoutID: id, points: 500)]
            )
        )

        XCTAssertEqual(reading, .buildingHistory(daysRecorded: 27, daysNeeded: 28))
    }

    /// Exactly `chronicWindowDays` days of history is enough — the boundary is
    /// inclusive, not "more than 28".
    func testExactlyTwentyEightDaysOfHistoryIsEnoughForAReading() throws {
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                historyStart: try day("2026-01-01"), // 28 days inclusive
                workouts: [],
                derivedMetricsByWorkoutID: [:]
            )
        )

        guard case .available = reading else {
            return XCTFail("exactly 28 days of history should already be enough")
        }
    }

    /// No history at all: `historyStart == anchor` reads as one day recorded, still far
    /// short of 28.
    func testNoHistoryAtAllReadsAsOneDayRecorded() throws {
        let anchor = try day("2026-01-28")
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: anchor,
                timeZone: .gmt,
                historyStart: anchor,
                workouts: [],
                derivedMetricsByWorkoutID: [:]
            )
        )

        XCTAssertEqual(reading, .buildingHistory(daysRecorded: 1, daysNeeded: 28))
    }

    /// `historyStart` after `anchor` is a caller bug, not a state to render.
    func testHistoryStartAfterAnchorIsRejected() throws {
        XCTAssertThrowsError(
            try LoadBalanceInput(
                anchor: try day("2026-01-01"),
                timeZone: .gmt,
                historyStart: try day("2026-01-02"),
                workouts: [],
                derivedMetricsByWorkoutID: [:]
            )
        ) { error in
            guard let domainError = error as? DomainError, case .inconsistent = domainError else {
                XCTFail("Expected DomainError.inconsistent, got \(error)")
                return
            }
        }
    }

    // MARK: - No chronic baseline

    /// Twenty-eight full days of history, and not one workout in the window carries a
    /// strain figure: the ratio is nil rather than a division by zero, but the acute sum
    /// — genuinely zero here — is still a real, reportable number.
    func testARatioIsNilWhenTheChronicWindowCarriesNoStrainAtAll() throws {
        let id = UUID()
        let reading = try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: try day("2026-01-28"),
                timeZone: .gmt,
                historyStart: try day("2026-01-01"),
                workouts: [try workout(on: "2026-01-10", id: id)],
                // No entry for `id` — the only workout in the window has no strain.
                derivedMetricsByWorkoutID: [:]
            )
        )

        guard case let .available(balance) = reading else {
            return XCTFail("28 days of history should already be enough for a reading")
        }
        XCTAssertNil(
            balance.ratio,
            "chronicWeeklyAveragePoints is 0 — a ratio here would be a division by zero"
        )
        XCTAssertEqual(balance.acuteStrainPoints, 0, accuracy: 1e-9)
        XCTAssertEqual(balance.chronicWorkoutsWithoutStrain, 1)
    }

    // MARK: - The windows themselves

    func testTheWindowLengthsAreSevenAndTwentyEightDays() {
        XCTAssertEqual(LoadBalanceCalculator.acuteWindowDays, 7)
        XCTAssertEqual(LoadBalanceCalculator.chronicWindowDays, 28)
    }
}
