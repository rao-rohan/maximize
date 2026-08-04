import Foundation

/// Chart-ready — tile-ready — presentation of one workout's summary figures (FR-1.5):
/// distance, duration, avg/max HR, energy, drift %, grade-adjusted pace. Precomputed
/// here, mirroring `HeartRateChartData` (MAX-042) and `CadenceChartData` (MAX-043), so
/// CI verifies the formatting instead of a device.
///
/// ## Thin by design
///
/// FR-1.5 calls this section out explicitly as "thin — displayed because cheap, not
/// lovingly built." Every figure below is a straight read of an already-stored number
/// (`Workout` or `DerivedMetrics`, D2) run through a formatter; nothing here classifies,
/// judges, or compares against a threshold. There is deliberately no in-band/out-of-band
/// verdict, no color, no "good/bad" — `CadenceBandView` and `HRCurveView` already own
/// that kind of judgment for the figures that need it, and duplicating it here would be
/// exactly the second-source-of-truth problem D2 exists to prevent.
///
/// ## What "splits" does not mean here
///
/// FR-1.5's requirement is written as "**Splits** and summary tiles (distance,
/// duration, avg/max HR, energy, drift %, grade-adjusted pace)." The parenthetical
/// names summary-tile figures only — a per-kilometre or per-mile pace breakdown is a
/// different, unstored figure: `DerivedMetrics` has no such array (its only per-segment
/// figure is `zoneSplits`, time spent in each *heart-rate zone*, not a distance split),
/// and nothing computes pace splits at ingestion. Per D2, this type does not recompute
/// one from the HR series or route to paper over that gap — doing so would create a
/// number nothing else in the app agrees with. Only the summary tiles are built here;
/// the per-distance splits half of FR-1.5 is left unbuilt and reported rather than
/// invented (see the PR description).
///
/// ## Absent is not zero
///
/// Every tile but `duration` is optional, and nil means *this workout does not have
/// this figure* — no distance recorded, no heart-rate series to average, drift withheld
/// because this session's classification is not one drift is meaningful for (§9).
/// `SummaryTilesView` renders a nil by omitting the tile, never by printing a
/// fabricated zero. `duration` is the one figure `Workout` always carries, so it is
/// the one non-optional tile.
public struct SummaryTileData: Hashable, Sendable {
    /// One rendered figure: a bare value and the caption that gives it meaning ("8.42"
    /// / "km"). Both are already formatted; `SummaryTilesView` only lays them out.
    public struct Tile: Hashable, Sendable {
        public let value: String
        public let caption: String

        public init(value: String, caption: String) {
            self.value = value
            self.caption = caption
        }
    }

    /// `Workout.distanceMeters`, formatted in kilometres. Nil when the workout recorded
    /// no distance at all (common for an indoor session with no GPS and no manually
    /// entered distance).
    public let distance: Tile?

    /// `Workout.durationSeconds`, formatted `H:MM:SS`/`M:SS`. Always present — a
    /// workout's duration is never optional in the domain model, so zero here is a real
    /// recorded duration, not an absence.
    public let duration: Tile

    /// `DerivedMetrics.averageHeartRateBPM`, unchanged. Nil when this run has no
    /// heart-rate series (MAX-010's "absent, not empty"), or when metrics have not been
    /// computed for this workout yet.
    public let averageHeartRate: Tile?

    /// `DerivedMetrics.maximumHeartRateBPM`, unchanged. Same absence rule as above.
    public let maximumHeartRate: Tile?

    /// `Workout.activeEnergyKilocalories`, unchanged. Nil when the capture source
    /// reported none.
    public let activeEnergy: Tile?

    /// `DerivedMetrics.heartRateDriftFraction`, unchanged, shown as a signed percentage.
    /// Nil both when there is no HR data and when drift was withheld as not meaningful
    /// for this session's classification (§9) — `SummaryTilesView` cannot and does not
    /// distinguish the two reasons from this type alone; it simply omits the tile.
    public let heartRateDrift: Tile?

    /// `DerivedMetrics.gradeAdjustedPaceSecondsPerKilometer`, unchanged, formatted as a
    /// per-kilometre pace. Nil for indoor runs, a route with no usable altitude, or
    /// metrics not yet computed.
    public let gradeAdjustedPace: Tile?

    /// - Parameters:
    ///   - workout: supplies `distance`, `duration`, `activeEnergy` directly. This
    ///     initializer never derives any of the three from the others.
    ///   - metrics: `DerivedMetrics` for this workout (D2 — read, never recomputed),
    ///     or nil if metrics have not been computed yet. Supplies `averageHeartRate`,
    ///     `maximumHeartRate`, `heartRateDrift`, `gradeAdjustedPace`.
    public init(workout: Workout, metrics: DerivedMetrics?) {
        self.distance = workout.distanceMeters.map {
            Tile(value: Self.formattedDistanceKilometers($0), caption: "km")
        }
        self.duration = Tile(value: Self.formattedDuration(seconds: workout.durationSeconds), caption: "duration")
        self.averageHeartRate = metrics?.averageHeartRateBPM.map {
            Tile(value: Self.formattedBPM($0), caption: "avg bpm")
        }
        self.maximumHeartRate = metrics?.maximumHeartRateBPM.map {
            Tile(value: Self.formattedBPM($0), caption: "max bpm")
        }
        self.activeEnergy = workout.activeEnergyKilocalories.map {
            Tile(value: Self.formattedKilocalories($0), caption: "kcal")
        }
        self.heartRateDrift = metrics?.heartRateDriftFraction.map {
            Tile(value: Self.formattedSignedPercent($0), caption: "% drift")
        }
        self.gradeAdjustedPace = metrics?.gradeAdjustedPaceSecondsPerKilometer.map {
            Tile(value: Self.formattedPacePerKilometer($0), caption: "grade-adj. pace")
        }
    }

    /// Every present tile, in FR-1.5's own order: distance, duration, avg/max HR,
    /// energy, drift %, grade-adjusted pace. `SummaryTilesView` reads only this — it
    /// never has to know which figures can be absent or reorder them itself.
    public var tiles: [Tile] {
        let all: [Tile?] = [
            distance, duration, averageHeartRate, maximumHeartRate, activeEnergy, heartRateDrift, gradeAdjustedPace,
        ]
        return all.compactMap { $0 }
    }

    // MARK: - Formatting
    //
    // Locale pinned to nil (POSIX) throughout, matching `WorkoutFactSheet` — a device
    // set to a comma-decimal locale must not render a different number here than one
    // set to a point-decimal locale.

    /// "7:42" under an hour, "1:02:03" at or beyond one hour. Deliberately a different
    /// shape from `HeartRateChartData.formattedDuration`'s "12m 34s": that format reads
    /// as prose inside a sentence ("12m 34s above cap"); this one is the headline value
    /// of a tile, and a stopwatch-style reading is the conventional shape for that.
    public static func formattedDuration(seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainderSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", locale: nil, hours, minutes, remainderSeconds)
        }
        return String(format: "%d:%02d", locale: nil, minutes, remainderSeconds)
    }

    /// "5:12" for a pace of 5 minutes 12 seconds per kilometre. The caption supplies
    /// the "/km" and "grade-adjusted" context, so the value stays a bare stopwatch
    /// reading, consistent with `formattedDuration`.
    static func formattedPacePerKilometer(_ secondsPerKilometer: Double) -> String {
        let totalSeconds = Int(secondsPerKilometer.rounded())
        let minutes = totalSeconds / 60
        let remainderSeconds = totalSeconds % 60
        return String(format: "%d:%02d", locale: nil, minutes, remainderSeconds)
    }

    /// Two decimal places, matching the precision `WorkoutFactSheet` already sends
    /// Claude — so a number a user reads on this tile and a number Claude was told
    /// about the same run are never rounded differently.
    static func formattedDistanceKilometers(_ meters: Double) -> String {
        String(format: "%.2f", locale: nil, meters / 1_000)
    }

    static func formattedBPM(_ beatsPerMinute: Double) -> String {
        String(format: "%.0f", locale: nil, beatsPerMinute)
    }

    static func formattedKilocalories(_ kilocalories: Double) -> String {
        String(format: "%.0f", locale: nil, kilocalories)
    }

    /// "+3.1" or "-2.4" — the sign always shown, since an unsigned drift percentage
    /// would silently discard the direction (whether HR rose or fell across the run),
    /// which is the entire point of the figure (§9's "aerobic decoupling").
    static func formattedSignedPercent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: nil, fraction * 100))"
    }
}
