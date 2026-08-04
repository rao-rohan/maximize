import Foundation

/// Knobs for the grade-adjustment filter.
///
/// These are **numerical filter parameters, not training thresholds** — they describe
/// how much a consumer-GPS altitude trace can be trusted, not what the plan asks of the
/// athlete. That is why they live here with defaults rather than in the versioned plan
/// record (D1 governs the second kind, not the first). They are exposed so tests can
/// disable the filtering and pin the raw arithmetic.
public struct GradeAdjustmentParameters: Hashable, Sendable {
    /// Half-width, in samples, of the centred moving average applied to altitude.
    /// Zero disables smoothing.
    public let altitudeSmoothingRadius: Int

    /// Minimum horizontal run, in metres, over which a single grade is measured.
    /// Shorter stretches are accumulated into the next one.
    public let minimumSegmentMeters: Double

    /// Grades beyond this magnitude are clamped, in both directions. 0.45 is the outer
    /// edge of the data the cost model below was fitted on; beyond it the polynomial is
    /// extrapolation dressed up as measurement.
    public let maximumGradeMagnitude: Double

    /// Values are clamped rather than rejected: these are tuning knobs on a filter, and
    /// a caller passing a nonsense radius should get a duller filter, not a thrown error
    /// in the middle of ingesting a workout.
    public init(
        altitudeSmoothingRadius: Int = 2,
        minimumSegmentMeters: Double = 30,
        maximumGradeMagnitude: Double = 0.45
    ) {
        self.altitudeSmoothingRadius = Swift.max(0, altitudeSmoothingRadius)
        self.minimumSegmentMeters = minimumSegmentMeters.isFinite ? Swift.max(0, minimumSegmentMeters) : 0
        let magnitude = maximumGradeMagnitude.isFinite ? Swift.max(0, maximumGradeMagnitude) : 0
        self.maximumGradeMagnitude = Swift.min(magnitude, 0.45)
    }

    public static let `default` = GradeAdjustmentParameters()
}

/// Grade-adjusted pace: the flat pace that would have cost the same effort as the run
/// actually run (§9, "pace corrected for route grade … so HR-vs-effort is interpretable
/// on hilly runs").
///
/// **Outdoor only.** A treadmill run has no route, and FR-0.6 makes indoor runs
/// first-class rather than degraded — so the answer there is *absent*, never zero and
/// never the flat pace relabelled.
enum GradeAdjustedPace {
    /// IUGG mean Earth radius, in metres.
    static let earthRadiusMeters = 6_371_008.8

    /// Metabolic cost of running in J·kg⁻¹·m⁻¹ at a given gradient, from Minetti et al.
    /// (2002), *Energy cost of walking and running at extreme uphill and downhill
    /// slopes*: `155.4i⁵ − 30.4i⁴ − 43.3i³ + 46.3i² + 19.5i + 3.6`, fitted over
    /// gradients of ±45%.
    ///
    /// Two properties of the curve matter for reading the output: cost is minimised at
    /// roughly −20% rather than on the flat, and it rises again on steep descents — so a
    /// rolling out-and-back with zero net climb is genuinely harder than the same
    /// distance on the flat, and its adjusted pace is correctly faster than its actual
    /// pace.
    ///
    /// Evaluated by Horner's method: algebraically identical, and it keeps the fifth
    /// power from being computed as such.
    static func costOfRunning(gradient: Double) -> Double {
        ((((155.4 * gradient - 30.4) * gradient - 43.3) * gradient + 46.3) * gradient + 19.5)
            * gradient + 3.6
    }

    /// Cost on the flat, the denominator that turns cost into a relative factor.
    static let flatCostOfRunning = costOfRunning(gradient: 0)

    /// How many times more costly a metre at this gradient is than a metre on the flat.
    static func adjustmentFactor(gradient: Double, parameters: GradeAdjustmentParameters) -> Double {
        let clamped = Swift.min(
            Swift.max(gradient, -parameters.maximumGradeMagnitude),
            parameters.maximumGradeMagnitude
        )
        return costOfRunning(gradient: clamped) / flatCostOfRunning
    }

    /// Centred moving average over the altitude trace.
    ///
    /// ## Why this exists
    ///
    /// GPS altitude is the noisiest thing a phone reports: several metres of jitter
    /// between consecutive fixes is normal. Point-to-point grade divides that jitter by
    /// a horizontal distance of a few metres, so a naive grade on a flat road swings
    /// through ±50% and the adjustment becomes noise amplification. Smoothing first, and
    /// then measuring grade over a stretch long enough to dwarf the residual jitter
    /// (`minimumSegmentMeters`), is what makes the number mean anything.
    ///
    /// ## Why the window shrinks at the ends
    ///
    /// The window's half-width at each point is reduced to fit inside the array
    /// *symmetrically*. A one-sided window at the ends would drag the first and last
    /// altitudes inward and quietly eat real elevation change: on a steady climb, an
    /// asymmetric window at the start reports a height the runner never stood at, and
    /// the run's total ascent shrinks. Symmetric truncation leaves any straight ramp
    /// exactly as it was — smoothing a hill must not flatten it.
    static func smoothedAltitudes(_ altitudes: [Double], radius: Int) -> [Double] {
        guard radius > 0, altitudes.count > 2 else { return altitudes }
        let lastIndex = altitudes.count - 1
        var smoothed = altitudes
        for index in altitudes.indices {
            let halfWidth = Swift.min(radius, index, lastIndex - index)
            guard halfWidth > 0 else { continue }
            var sum = 0.0
            for offset in (index - halfWidth)...(index + halfWidth) {
                sum += altitudes[offset]
            }
            smoothed[index] = sum / Double(2 * halfWidth + 1)
        }
        return smoothed
    }

    /// Great-circle distance between two fixes, ignoring the vertical component — this
    /// is the *run* of the grade, and altitude is its *rise*.
    static func horizontalDistanceMeters(from origin: RoutePoint, to destination: RoutePoint) -> Double {
        let radiansPerDegree = Double.pi / 180
        let originLatitude = origin.latitudeDegrees * radiansPerDegree
        let destinationLatitude = destination.latitudeDegrees * radiansPerDegree
        let deltaLatitude = destinationLatitude - originLatitude
        let deltaLongitude = (destination.longitudeDegrees - origin.longitudeDegrees) * radiansPerDegree

        let haversine = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(originLatitude) * cos(destinationLatitude)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * earthRadiusMeters * asin(Swift.min(1, sqrt(Swift.max(0, haversine))))
    }

    /// The route's cost factor: a distance-weighted mean of each stretch's factor.
    ///
    /// Weighting by horizontal distance rather than by time is deliberate — a metre
    /// climbed costs what it costs regardless of how long the athlete took over it, and
    /// time-weighting would count the slow uphill metres twice, once in the weight and
    /// again in the pace it is about to adjust.
    ///
    /// Nil when the route carries fewer than two altitudes, or when no stretch has any
    /// horizontal extent at all (a fix repeated while standing still).
    static func weightedAdjustmentFactor(route: Route, parameters: GradeAdjustmentParameters) -> Double? {
        var located: [(point: RoutePoint, altitudeMeters: Double)] = []
        for point in route.points {
            guard let altitudeMeters = point.altitudeMeters else { continue }
            located.append((point, altitudeMeters))
        }
        guard located.count >= 2 else { return nil }

        let altitudes = smoothedAltitudes(
            located.map(\.altitudeMeters),
            radius: parameters.altitudeSmoothingRadius
        )
        guard altitudes.count == located.count else { return nil }

        // Accumulate consecutive fixes until the stretch is long enough to measure a
        // grade over. A leftover tail is folded into the previous stretch rather than
        // measured on its own, where the jitter would dominate.
        var stretches: [(meters: Double, riseMeters: Double)] = []
        var pendingMeters = 0.0
        var pendingRise = 0.0
        for index in 1..<located.count {
            pendingMeters += horizontalDistanceMeters(
                from: located[index - 1].point,
                to: located[index].point
            )
            pendingRise += altitudes[index] - altitudes[index - 1]
            if pendingMeters >= parameters.minimumSegmentMeters {
                stretches.append((pendingMeters, pendingRise))
                pendingMeters = 0
                pendingRise = 0
            }
        }
        if pendingMeters > 0 {
            if let last = stretches.popLast() {
                stretches.append((last.meters + pendingMeters, last.riseMeters + pendingRise))
            } else {
                stretches.append((pendingMeters, pendingRise))
            }
        }

        var weightedTotal = 0.0
        var meters = 0.0
        for stretch in stretches where stretch.meters > 0 {
            // A rise with no run is not a grade; those metres are dropped above by the
            // `where`, taking their vertical jitter with them.
            let factor = adjustmentFactor(
                gradient: stretch.riseMeters / stretch.meters,
                parameters: parameters
            )
            guard factor.isFinite, factor > 0 else { continue }
            weightedTotal += factor * stretch.meters
            meters += stretch.meters
        }
        guard meters > 0 else { return nil }
        return weightedTotal / meters
    }

    /// Grade-adjusted pace in seconds per kilometre, or nil when the run cannot have one.
    ///
    /// Distance comes from the workout, not from summing GPS fixes: the health store's
    /// distance is the one shown everywhere else in the app, and summing noisy fixes
    /// would produce a second, slightly longer notion of how far the run was — the exact
    /// disagreement D2 exists to avoid. The route's only job here is the shape of the
    /// ground.
    ///
    /// Nil, meaning *not applicable*, for: an indoor run (no route), a route with no
    /// usable altitude, a workout with no distance, and a zero distance or duration.
    /// Never zero — a zero would be read as an infinitely fast run by anything that
    /// averages these.
    static func secondsPerKilometer(
        workout: Workout,
        route: Route?,
        parameters: GradeAdjustmentParameters
    ) -> Double? {
        guard let route,
              let distanceMeters = workout.distanceMeters,
              distanceMeters > 0,
              workout.durationSeconds > 0,
              let factor = weightedAdjustmentFactor(route: route, parameters: parameters),
              factor > 0
        else { return nil }

        let flatPaceSecondsPerKilometer = workout.durationSeconds / (distanceMeters / 1_000)
        // Divide, not multiply: a climb that costs 1.66× as much energy per metre means
        // the same effort would have covered 1.66× the distance on the flat, so the
        // equivalent flat pace is *faster* than the pace actually run.
        return flatPaceSecondsPerKilometer / factor
    }
}
