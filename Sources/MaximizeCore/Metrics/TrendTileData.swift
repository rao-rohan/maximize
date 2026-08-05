import Foundation

/// Presentation-ready summary tiles for a selected `TrendInterval` (FR-3.4): mileage
/// against the plan's arc, effective days, current streak, average score.
///
/// ## What this reads versus what it computes
///
/// Three of the four figures are **read, not recomputed**: `effectiveDays`, `streak`
/// and `averageScore` come straight off a `Tallies` MAX-017 already computed (D2) —
/// this type never re-derives a streak or an effective-day count itself, for the same
/// reason `SummaryTileData` never re-derives a metric `DerivedMetrics` already stored.
///
/// `mileage` is different: it is not one of MAX-017's five rollups, and FR-3.4 asks for
/// it against the plan's arc specifically, so it is computed here from two things nothing
/// else already assembles together — the plan's per-day distance ask
/// (`PlanCalendar.planDays(from:through:)`, D1: never a hardcoded target) and the
/// workouts actually recorded in the interval. Both are read from stored records, the
/// same rule `Tallies` itself follows; nothing here recomputes a metric that already
/// lives in `DerivedMetrics` or `Tallies`.
///
/// ## Absent is not zero (rule 3)
///
/// - `mileage` is nil when no plan governs *any* day in the interval — "no arc to
///   measure against" is a different fact from "the arc asked for 0 km", and a nil tile
///   is how that absence is rendered (omitted, never printed as "0.00 / 0.00").
/// - `effectiveDays` is nil exactly when `EffectiveDayTally.rate` is nil — nothing in
///   the interval was eligible to be effective at (see that type's own documentation).
/// - `streak` is never nil. Zero is a real, measured streak — the day after a miss —
///   and omitting the tile would hide exactly the number a streak screen exists to show.
/// - `averageScore` is nil when `Tallies.averageScore` is nil — nothing in the interval
///   has been scored yet, an honest "no data" rather than a fabricated zero.
public struct TrendTileData: Hashable, Sendable {
    /// Reusing `SummaryTileData.Tile` rather than a near-identical duplicate: both
    /// screens want the same bare value/caption shape, and `SummaryTilesView` (MAX-045)
    /// already knows how to render one, so this type and that view can share a renderer
    /// without a second tile shape needing to exist.
    public typealias Tile = SummaryTileData.Tile

    /// Actual distance covered vs. the plan's arc target for the interval, as
    /// `"<actual> / <target>"` in the athlete's chosen `DistanceUnit` (MAX-047). Nil
    /// when no plan governs any day in the interval — see the type's own documentation
    /// for why that is not the same as a zero target.
    public let mileage: Tile?

    /// `Tallies.effectiveDays`, as `"<effective>/<eligible>"` — the numerator/denominator
    /// pair `EffectiveDayTally` itself prefers over a bare percentage, so the tile never
    /// hides "out of how many chances". Nil when nothing was eligible.
    public let effectiveDays: Tile?

    /// `Tallies.currentStreak`. Always present — see the type's own documentation for
    /// why zero is a measurement here, not an absence.
    public let streak: Tile

    /// `Tallies.averageScore`, to one decimal place. Nil when nothing has been scored.
    public let averageScore: Tile?

    /// - Parameters:
    ///   - tallies: MAX-017's rollup for this exact interval (`tallies.from`...
    ///     `tallies.through` is treated as the interval's own bounds — the caller is
    ///     expected to have built it from the same `TrendInterval` this displays).
    ///   - workouts: every workout available to the caller for the interval. This may
    ///     be wider than `tallies.from...tallies.through` — `TalliesInput` requires the
    ///     whole Monday-first weeks touching the interval (C1) — so this initializer
    ///     filters to `tallies.from...tallies.through` itself rather than trusting the
    ///     caller to have narrowed it, the same defensive filtering `TalliesCalculator`
    ///     does internally against its own wider input.
    ///   - timeZone: the athlete's zone, not the device's — matches `Workout.calendarDay(in:)`,
    ///     `TalliesInput` and `TrendInterval.dateInterval(in:)`'s own requirement.
    ///   - planCalendar: nil before the first plan version is authored — a real state,
    ///     not "no data" (see `mileage`'s documentation).
    ///   - distanceUnit: MAX-047 — a display decision only. `Workout.distanceMeters` and
    ///     `ScheduledSession.distanceMeters` stay in metres regardless; this initializer
    ///     is the one place that converts for the tile. No default, matching
    ///     `SummaryTileData`'s initializer: every call site must say explicitly which
    ///     unit it means.
    public init(
        tallies: Tallies,
        workouts: [Workout],
        timeZone: TimeZone,
        planCalendar: PlanCalendar?,
        distanceUnit: DistanceUnit
    ) throws {
        var planDays: [PlanDay] = []
        if let planCalendar {
            planDays = try planCalendar.planDays(from: tallies.from, through: tallies.through)
        }
        if planDays.isEmpty {
            mileage = nil
        } else {
            let targetMeters = planDays.reduce(into: 0.0) { total, planDay in
                total += planDay.scheduledSession.distanceMeters ?? 0
            }
            var actualMeters = 0.0
            for workout in workouts {
                let day = try workout.calendarDay(in: timeZone)
                guard day >= tallies.from, day <= tallies.through else { continue }
                actualMeters += workout.distanceMeters ?? 0
            }
            mileage = Tile(
                value: "\(Self.formattedDistance(actualMeters, unit: distanceUnit)) / "
                    + "\(Self.formattedDistance(targetMeters, unit: distanceUnit))",
                caption: "\(distanceUnit.abbreviation) vs. arc"
            )
        }

        if tallies.effectiveDays.eligibleCount > 0 {
            effectiveDays = Tile(
                value: "\(tallies.effectiveDays.effectiveCount)/\(tallies.effectiveDays.eligibleCount)",
                caption: "effective days"
            )
        } else {
            effectiveDays = nil
        }

        streak = Tile(value: "\(tallies.currentStreak)", caption: "day streak")

        averageScore = tallies.averageScore.map {
            Tile(value: Self.formattedAverageScore($0), caption: "avg score")
        }
    }

    /// Every present tile, in FR-3.4's own order: mileage vs. arc, effective days,
    /// streak, average score.
    public var tiles: [Tile] {
        [mileage, effectiveDays, streak, averageScore].compactMap { $0 }
    }

    // MARK: - Formatting
    //
    // Locale pinned to nil (POSIX), matching `SummaryTileData` — a comma-decimal
    // locale must not render a different number here than a point-decimal one.

    /// Two decimal places, matching `SummaryTileData.formattedDistance` — a distance
    /// printed here and one printed on the per-workout tiles must never round
    /// differently, and must convert to the same unit the same way. Delegated rather
    /// than duplicated (both live in `MaximizeCore`, so the internal helper is directly
    /// reachable).
    private static func formattedDistance(_ meters: Double, unit: DistanceUnit) -> String {
        SummaryTileData.formattedDistance(meters, unit: unit)
    }

    private static func formattedAverageScore(_ score: Double) -> String {
        String(format: "%.1f", locale: nil, score)
    }
}
