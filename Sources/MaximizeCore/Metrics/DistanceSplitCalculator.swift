import Foundation

/// Cuts one workout into per-unit pace splits (FR-1.5), once, at ingestion (D2).
///
/// ## What a split is measured against
///
/// **Distance comes from the workout; the *shape* of the run comes from a track.**
/// Neither source answers the question on its own:
///
/// - `Workout.distanceMeters` is the health store's own figure. It is the number the
///   distance tile shows, the number `WorkoutFactSheet` sends Claude, and the number
///   `GradeAdjustedPace` divides by. But it is a single scalar: it says how far the run
///   was and nothing about *when* each kilometre was reached, so it cannot be cut up.
/// - A track carries the time-versus-distance relation, and only a track does. Two
///   kinds exist, and at most one applies to a given run:
///   - **A GPS route**, for an outdoor run. Summing haversine distances between
///     consumer-GPS fixes yields a total that disagrees with the health store's by a
///     percent or two — so splits built on the raw sum would add up to a distance that
///     appears nowhere else in the app.
///   - **A `distanceWalkingRunning` sample series** (MAX-066), for an indoor run that
///     has no route to fall back on. Summing consecutive sample deltas has the same
///     shape of disagreement, for the same reason: it is a different measurement of
///     the same run.
///
///   Either way that is the second-source-of-truth disagreement D2 exists to prevent,
///   and `GradeAdjustedPace.secondsPerKilometer` already refuses it for the same
///   reason.
///
/// So the track — whichever kind supplied it — is used for shape and then **rescaled
/// by a single factor** so its total equals `Workout.distanceMeters` exactly. Where the
/// athlete was fast and where they were slow is the track's answer; how far they went
/// is the health store's, unchanged. The splits therefore sum to the distance already
/// on screen.
///
/// The correction is uniform because there is nothing to justify making it otherwise:
/// the discrepancy is accumulated noise, spread over the whole track, not a fault
/// localised to one stretch that could be identified and repaired.
///
/// ## Which source wins
///
/// **`route`, whenever it is non-nil, is the only source consulted — full stop.** Not
/// "whichever source produces a usable track": if `route` is supplied and it is too
/// sparse, too short, or too far from the recorded distance to become a `Track`, the
/// answer is *no breakdown*, exactly as MAX-046 shipped it, and `distanceSamples` is
/// never looked at as a fallback. `distanceSamples` is considered only when `route` is
/// `nil`.
///
/// This is enforced here, not only upstream: `WorkoutSampleExtractor` already fetches
/// distance samples exclusively for a workout with no route, so in practice the two
/// never arrive together — but an outdoor run's splits must never depend on whether a
/// second, lower-fidelity source happens to have been supplied, so the rule is pinned
/// in the one place a wrong answer would actually surface.
///
/// ## When there is no breakdown at all
///
/// Nil, meaning *this run has no split breakdown*, never an empty one (MAX-010's "absent,
/// not empty", the same rule MAX-042/043/044/045 follow):
///
/// - **A run with neither a route nor a distance-sample series** — an indoor run
///   captured before `distanceWalkingRunning` was read as a series (MAX-067's backfill
///   territory), or a source that genuinely recorded neither. Splitting its distance
///   evenly across its duration would emit a breakdown in which every split is
///   identical — indistinguishable on screen from a real one, and a fabrication.
/// - **A workout with no recorded distance, or a track of fewer than two usable
///   points.**
/// - **A track whose own length is implausibly far from the recorded distance.** A
///   route truncated by `RouteFetchRequest.maxPoints`, one that dropped out through a
///   tunnel, or a distance-sample fetch that failed partway, describes less ground than
///   the run covered; rescaling it would stretch every split by the missing fraction
///   and produce paces the athlete never ran. Beyond `plausibleTrackScale` the honest
///   answer is that this track cannot be cut up.
///
/// ## What the elapsed times do and do not include
///
/// A split's time is measured **between the track's own points** — GPS fixes, or
/// distance samples — interpolating within the one that straddles each boundary. Two
/// consequences, both stated rather than corrected:
///
/// - Time before the first point — GPS acquisition lag at the start of a run, or the
///   gap before the first distance sample — falls outside every split. So the splits'
///   total elapsed time is at or below `Workout.durationSeconds` rather than equal to
///   it, and the first split is not penalised for the athlete standing still waiting
///   for a signal.
/// - A pause lands inside whichever split straddles it, because both `RoutePoint.offsetSeconds`
///   and `DistanceSample.offsetSeconds` are measured from `Workout.start` and a paused
///   stretch simply has no points in it. That split reads slow. Correcting it would
///   need the pause intervals, which nothing in the domain captures today.
enum DistanceSplitCalculator {
    /// A trailing remainder shorter than this is dropped rather than emitted as a split.
    ///
    /// Ten metres is below the spacing of consecutive GPS fixes at any running pace, so a
    /// remainder that small is bounded entirely by interpolation *within* one fix
    /// interval: its pace is an artifact of the rescale, not a measurement. Dropping it
    /// means the splits can total up to ten metres less than the recorded distance, which
    /// is invisible at the two decimal places anything displays.
    static let minimumRemainderMeters = 10.0

    /// How far a track's own length — a route's or a distance-sample series' — may sit
    /// from the recorded distance and still be trusted to describe it.
    ///
    /// Ordinary consumer-GPS (or consumer-sensor) disagreement with HealthKit's fused
    /// distance is a couple of percent; this band is deliberately much wider than that,
    /// because it is guarding against a *structurally* wrong track — truncated, or with
    /// a long dropout — not against noise. One band for both track kinds: the failure
    /// mode it guards against (missing ground, not measurement jitter) is the same
    /// shape regardless of which sensor produced the track.
    static let plausibleTrackScale: ClosedRange<Double> = 0.8...1.25

    /// Slack allowed when deciding whether the run ended exactly on a unit boundary.
    ///
    /// A mile is 1 609.344 m, which no binary float divides exactly, so a run of exactly
    /// three miles can compute as 2.999999999999999 miles and leave a "remainder" of one
    /// whole mile marked incomplete. One millimetre of tolerance removes that entirely and
    /// cannot swallow a real remainder, which `minimumRemainderMeters` already floors at
    /// ten metres.
    static let boundaryToleranceMeters = 0.001

    /// The workout's pace breakdown at every unit the app can display, or nil when this
    /// run cannot have one. See the type documentation for each nil case and for which
    /// source — `route` or `distanceSamples` — wins when both are supplied.
    ///
    /// Every unit is cut in this one pass, on purpose: `DistanceSplits` explains why
    /// storing only the currently-selected display unit would bake a preference into the
    /// athlete's history. There is no parameter to cut fewer.
    static func splits(workout: Workout, route: Route?, distanceSamples: DistanceSampleSeries? = nil) -> DistanceSplits? {
        guard let recordedDistanceMeters = workout.distanceMeters, recordedDistanceMeters > 0 else {
            return nil
        }

        let track: Track?
        if let route {
            // A GPS track is authoritative whenever one exists, full stop — this is
            // exactly the guard MAX-046 shipped with, unchanged. `distanceSamples` is
            // never consulted here, even if this particular route is itself unusable
            // (too few points, or implausibly scaled against the recorded distance):
            // falling back to a lower-fidelity source in that case would make an
            // outdoor run's splits depend on which sensor happened to fail, instead of
            // being the one deterministic answer MAX-046 already committed to. See the
            // type documentation's "Which source wins".
            track = Track(route: route, recordedDistanceMeters: recordedDistanceMeters)
        } else {
            track = distanceSamples.flatMap { Track(distanceSamples: $0, recordedDistanceMeters: recordedDistanceMeters) }
        }
        guard let track else { return nil }

        var series: [DistanceSplitSeries] = []
        for unit in DistanceUnit.allCases {
            guard let cut = seriesForUnit(unit, track: track, totalMeters: recordedDistanceMeters) else {
                // A unit that cannot be cut means the track itself is pathological — a
                // boundary that resolves to no elapsed time — rather than something
                // specific to kilometres or miles. Reporting no breakdown at all is
                // truer than reporting one that happens to work in the other unit.
                return nil
            }
            series.append(cut)
        }
        return try? DistanceSplits(series: series)
    }

    private static func seriesForUnit(
        _ unit: DistanceUnit,
        track: Track,
        totalMeters: Double
    ) -> DistanceSplitSeries? {
        let unitMeters = unit.metersPerUnit
        let completeCount = Int(((totalMeters + boundaryToleranceMeters) / unitMeters).rounded(.down))
        let remainderMeters = Swift.max(0, totalMeters - Double(completeCount) * unitMeters)

        var splits: [DistanceSplit] = []
        var boundaryOffsetSeconds = track.offsetSeconds(atCumulativeMeters: 0)
        do {
            for ordinal in stride(from: 1, through: completeCount, by: 1) {
                let endOffsetSeconds = track.offsetSeconds(
                    atCumulativeMeters: Double(ordinal) * unitMeters
                )
                splits.append(
                    try DistanceSplit(
                        ordinal: ordinal,
                        distanceMeters: unitMeters,
                        elapsedSeconds: endOffsetSeconds - boundaryOffsetSeconds,
                        isComplete: true
                    )
                )
                boundaryOffsetSeconds = endOffsetSeconds
            }

            if remainderMeters >= minimumRemainderMeters {
                splits.append(
                    try DistanceSplit(
                        ordinal: completeCount + 1,
                        distanceMeters: remainderMeters,
                        // The run's last fix, not an interpolation: the rescale makes the
                        // track's cumulative total exactly `totalMeters`, so the final
                        // boundary *is* the end of the track.
                        elapsedSeconds: track.lastOffsetSeconds - boundaryOffsetSeconds,
                        isComplete: false
                    )
                )
            }
        } catch {
            // A non-positive distance or elapsed time — a boundary that resolved to no
            // time at all. `DistanceSplit` rejects it rather than emitting an infinite
            // pace, and there is nothing useful to substitute.
            return nil
        }

        // A run shorter than `minimumRemainderMeters` produces no splits at all, and
        // `DistanceSplitSeries` rejects an empty one — which is the right answer: it
        // becomes "no breakdown", never a breakdown containing nothing.
        return try? DistanceSplitSeries(unit: unit, splits: splits)
    }

    /// The track's cumulative distance-versus-time curve, rescaled to the workout's
    /// recorded distance.
    ///
    /// Built from either of two sources — a GPS `Route` or a `DistanceSampleSeries`
    /// (MAX-066) — through two dedicated initializers that share one private core. The
    /// only difference between them is *how* "distance between consecutive points" is
    /// obtained (haversine between coordinates, versus a sample's own reported delta);
    /// everything after that — the rescale, the plausibility check, the interpolation
    /// below — is one piece of arithmetic that does not care which kind of point
    /// produced it.
    private struct Track {
        /// Ascending, starting at 0, ending at exactly the recorded distance.
        let cumulativeMeters: [Double]
        /// Index-aligned with `cumulativeMeters`, strictly ascending — `RoutePoint.offsetSeconds`
        /// or `DistanceSample.offsetSeconds`, whichever source built this track.
        let offsets: [Double]

        /// Nil when the track cannot describe this workout's distance — see
        /// `DistanceSplitCalculator`'s documentation.
        init?(route: Route, recordedDistanceMeters: Double) {
            let points = route.points
            guard points.count >= 2 else { return nil }

            var raw: [Double] = [0]
            raw.reserveCapacity(points.count)
            var runningTotal = 0.0
            for index in 1..<points.count {
                // The same great-circle helper grade adjustment already measures its
                // stretches with (MAX-012). One notion of "how far apart two fixes are".
                runningTotal += GradeAdjustedPace.horizontalDistanceMeters(
                    from: points[index - 1],
                    to: points[index]
                )
                raw.append(runningTotal)
            }
            self.init(rawCumulativeMeters: raw, offsets: points.map(\.offsetSeconds), recordedDistanceMeters: recordedDistanceMeters)
        }

        /// Nil under the same conditions as the route initializer, read against a
        /// distance-sample series instead of GPS fixes (MAX-066).
        ///
        /// The first sample's own delta is excluded from the sum, exactly as the route
        /// initializer excludes the ground covered before the first GPS fix reports in
        /// — the parallel is deliberate: `cumulativeMeters[0] == 0` is anchored at
        /// `samples[0].offsetSeconds`, so whatever the sensor covered before its own
        /// first reading falls outside every split, the same "acquisition lag" the type
        /// documentation already describes for GPS.
        init?(distanceSamples: DistanceSampleSeries, recordedDistanceMeters: Double) {
            let samples = distanceSamples.samples
            guard samples.count >= 2 else { return nil }

            var raw: [Double] = [0]
            raw.reserveCapacity(samples.count)
            var runningTotal = 0.0
            for index in 1..<samples.count {
                runningTotal += samples[index].meters
                raw.append(runningTotal)
            }
            self.init(rawCumulativeMeters: raw, offsets: samples.map(\.offsetSeconds), recordedDistanceMeters: recordedDistanceMeters)
        }

        /// Shared core: rescales a raw cumulative-distance curve so its total matches
        /// the recorded distance exactly, or fails if the raw total is not a plausible
        /// description of it.
        private init?(rawCumulativeMeters raw: [Double], offsets: [Double], recordedDistanceMeters: Double) {
            guard let runningTotal = raw.last, runningTotal > 0, runningTotal.isFinite else { return nil }

            let scale = recordedDistanceMeters / runningTotal
            guard DistanceSplitCalculator.plausibleTrackScale.contains(scale) else { return nil }

            self.cumulativeMeters = raw.map { $0 * scale }
            self.offsets = offsets
        }

        var lastOffsetSeconds: Double { offsets[offsets.count - 1] }

        /// When the athlete reached a given cumulative distance, interpolating linearly
        /// within the fix interval that straddles it.
        ///
        /// Linear within an interval because that is the only assumption the data
        /// supports: between two fixes there is one distance and one time, and nothing
        /// says how the pace varied inside them. At a few seconds per fix the error this
        /// can introduce at a boundary is a fraction of a second.
        func offsetSeconds(atCumulativeMeters target: Double) -> Double {
            guard let firstOffset = offsets.first, let lastCumulative = cumulativeMeters.last else {
                // Unreachable: `init?` rejects a track with fewer than two points. Written
                // as a guard rather than a subscript so this stays total (CLAUDE.md's
                // no-force-unwrap rule).
                return 0
            }
            if target <= 0 { return firstOffset }
            if target >= lastCumulative { return lastOffsetSeconds }

            for index in 1..<cumulativeMeters.count where cumulativeMeters[index] >= target {
                let previousMeters = cumulativeMeters[index - 1]
                let spanMeters = cumulativeMeters[index] - previousMeters
                // A stationary fix pair covers no ground; the boundary is then reached at
                // the moment the athlete arrived, which is the earlier fix.
                guard spanMeters > 0 else { return offsets[index - 1] }
                let fraction = (target - previousMeters) / spanMeters
                return offsets[index - 1] + fraction * (offsets[index] - offsets[index - 1])
            }
            return lastOffsetSeconds
        }
    }
}
