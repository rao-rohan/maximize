import Foundation

/// Cuts one workout into per-unit pace splits (FR-1.5), once, at ingestion (D2).
///
/// ## What a split is measured against
///
/// **Distance comes from the workout; the *shape* of the run comes from the route.**
/// Neither source answers the question on its own:
///
/// - `Workout.distanceMeters` is the health store's own figure. It is the number the
///   distance tile shows, the number `WorkoutFactSheet` sends Claude, and the number
///   `GradeAdjustedPace` divides by. But it is a single scalar: it says how far the run
///   was and nothing about *when* each kilometre was reached, so it cannot be cut up.
/// - The GPS track carries the time-versus-distance relation, and only it does. But
///   summing haversine distances between consumer-GPS fixes yields a total that
///   disagrees with the health store's by a percent or two — so splits built on the raw
///   sum would add up to a distance that appears nowhere else in the app. That is the
///   second-source-of-truth disagreement D2 exists to prevent, and
///   `GradeAdjustedPace.secondsPerKilometer` already refuses it for the same reason.
///
/// So the track is used for shape and then **rescaled by a single factor** so its total
/// equals `Workout.distanceMeters` exactly. Where the athlete was fast and where they
/// were slow is GPS's answer; how far they went is the health store's, unchanged. The
/// splits therefore sum to the distance already on screen.
///
/// The correction is uniform because there is nothing to justify making it otherwise:
/// the discrepancy is accumulated fix-to-fix noise, spread over the whole track, not a
/// fault localised to one stretch that could be identified and repaired.
///
/// ## When there is no breakdown at all
///
/// Nil, meaning *this run has no split breakdown*, never an empty one (MAX-010's "absent,
/// not empty", the same rule MAX-042/043/044/045 follow):
///
/// - **An indoor run** (FR-0.6) has no route, so nothing says when each kilometre fell.
///   Splitting its distance evenly across its duration would emit a breakdown in which
///   every split is identical — indistinguishable on screen from a real one, and a
///   fabrication. A treadmill run is first-class here by having *no* splits, not by
///   having invented ones. (A distance-sample series would give a treadmill a real
///   breakdown; nothing fetches one today — see the PR.)
/// - **A workout with no recorded distance, or a route of fewer than two usable fixes.**
/// - **A route whose own length is implausibly far from the recorded distance.** A route
///   truncated by `RouteFetchRequest.maxPoints`, or one that dropped out through a tunnel,
///   describes less ground than the run covered; rescaling it would stretch every split
///   by the missing fraction and produce paces the athlete never ran. Beyond
///   `plausibleRouteScale` the honest answer is that this track cannot be cut up.
///
/// ## What the elapsed times do and do not include
///
/// A split's time is measured **between GPS fixes**, interpolating within the fix that
/// straddles each boundary. Two consequences, both stated rather than corrected:
///
/// - Time before the first fix — GPS acquisition lag at the start of a run — falls
///   outside every split. So the splits' total elapsed time is at or below
///   `Workout.durationSeconds` rather than equal to it, and the first split is not
///   penalised for the athlete standing still waiting for a signal.
/// - A pause lands inside whichever split straddles it, because `RoutePoint.offsetSeconds`
///   is measured from `Workout.start` and a paused stretch simply has no fixes in it.
///   That split reads slow. Correcting it would need the pause intervals, which nothing
///   in the domain captures today.
enum DistanceSplitCalculator {
    /// A trailing remainder shorter than this is dropped rather than emitted as a split.
    ///
    /// Ten metres is below the spacing of consecutive GPS fixes at any running pace, so a
    /// remainder that small is bounded entirely by interpolation *within* one fix
    /// interval: its pace is an artifact of the rescale, not a measurement. Dropping it
    /// means the splits can total up to ten metres less than the recorded distance, which
    /// is invisible at the two decimal places anything displays.
    static let minimumRemainderMeters = 10.0

    /// How far the route's own length may sit from the recorded distance and still be
    /// trusted to describe it.
    ///
    /// Ordinary consumer-GPS disagreement with HealthKit's fused distance is a couple of
    /// percent; this band is deliberately much wider than that, because it is guarding
    /// against a *structurally* wrong track — truncated, or with a long dropout — not
    /// against noise.
    static let plausibleRouteScale: ClosedRange<Double> = 0.8...1.25

    /// Slack allowed when deciding whether the run ended exactly on a unit boundary.
    ///
    /// A mile is 1 609.344 m, which no binary float divides exactly, so a run of exactly
    /// three miles can compute as 2.999999999999999 miles and leave a "remainder" of one
    /// whole mile marked incomplete. One millimetre of tolerance removes that entirely and
    /// cannot swallow a real remainder, which `minimumRemainderMeters` already floors at
    /// ten metres.
    static let boundaryToleranceMeters = 0.001

    /// The workout's pace breakdown at every unit the app can display, or nil when this
    /// run cannot have one. See the type documentation for each nil case.
    ///
    /// Every unit is cut in this one pass, on purpose: `DistanceSplits` explains why
    /// storing only the currently-selected display unit would bake a preference into the
    /// athlete's history. There is no parameter to cut fewer.
    static func splits(workout: Workout, route: Route?) -> DistanceSplits? {
        guard let route,
              let recordedDistanceMeters = workout.distanceMeters,
              recordedDistanceMeters > 0,
              let track = Track(route: route, recordedDistanceMeters: recordedDistanceMeters)
        else { return nil }

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

    /// The route's cumulative distance-versus-time curve, rescaled to the workout's
    /// recorded distance.
    private struct Track {
        /// Ascending, starting at 0, ending at exactly the recorded distance.
        let cumulativeMeters: [Double]
        /// `RoutePoint.offsetSeconds`, index-aligned with `cumulativeMeters`. Strictly
        /// ascending, because `Route` requires it.
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
            guard runningTotal > 0, runningTotal.isFinite else { return nil }

            let scale = recordedDistanceMeters / runningTotal
            guard DistanceSplitCalculator.plausibleRouteScale.contains(scale) else { return nil }

            self.cumulativeMeters = raw.map { $0 * scale }
            self.offsets = points.map(\.offsetSeconds)
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
