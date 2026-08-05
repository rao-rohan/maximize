import Foundation

/// Everything one workout's metrics are computed from.
///
/// Bundled into a value rather than passed as five arguments so the cross-field
/// invariants — the series and the route belong to *this* workout — are checked once,
/// at the edge, instead of being assumed by each metric.
public struct DerivedMetricsInput: Hashable, Sendable {
    public let workout: Workout

    /// Absent when the capture source recorded no heart rate at all. Note the
    /// distinction `HeartRateSeries` already draws: a workout with no HR data has *no
    /// series*, never an empty one.
    public let heartRateSeries: HeartRateSeries?

    /// Absent for indoor runs (FR-0.6).
    public let route: Route?

    /// The workout's distance-sample series (MAX-066), or nil.
    ///
    /// Only ever populated for a workout with no route — `WorkoutSampleExtractor`
    /// fetches this exclusively when `route` is nil, and `DistanceSplitCalculator`
    /// prefers `route` over this whenever both happen to be present, so an outdoor
    /// run's splits are never at the mercy of a second, lower-fidelity source. See
    /// `DistanceSplitCalculator` for what it does with this.
    public let distanceSamples: DistanceSampleSeries?

    /// Steps recorded over the workout, from which average cadence is derived.
    ///
    /// It arrives as a parameter because `Workout` (MAX-010) carries no step count —
    /// see the note in `DerivedMetricsCalculator`. Nil means the source reported none,
    /// which is why average cadence comes back absent rather than zero.
    public let totalStepCount: Double?

    /// What the athlete actually did (§10.2), when it is already known. It gates drift
    /// only — see `DerivedMetricsCalculator.compute`.
    public let classification: WorkoutClassification?

    public init(
        workout: Workout,
        heartRateSeries: HeartRateSeries? = nil,
        route: Route? = nil,
        distanceSamples: DistanceSampleSeries? = nil,
        totalStepCount: Double? = nil,
        classification: WorkoutClassification? = nil
    ) throws {
        if let heartRateSeries, heartRateSeries.workoutID != workout.id {
            throw DomainError.inconsistent(
                reason: "DerivedMetricsInput.heartRateSeries belongs to a different workout"
            )
        }
        if let route {
            guard route.workoutID == workout.id else {
                throw DomainError.inconsistent(
                    reason: "DerivedMetricsInput.route belongs to a different workout"
                )
            }
            guard workout.hasRoute else {
                throw DomainError.inconsistent(
                    reason: "DerivedMetricsInput.route was supplied for a workout recorded without one"
                )
            }
        }
        if let distanceSamples, distanceSamples.workoutID != workout.id {
            throw DomainError.inconsistent(
                reason: "DerivedMetricsInput.distanceSamples belongs to a different workout"
            )
        }
        try Validate.optionalNonNegative(totalStepCount, "DerivedMetricsInput.totalStepCount")

        self.workout = workout
        self.heartRateSeries = heartRateSeries
        self.route = route
        self.distanceSamples = distanceSamples
        self.totalStepCount = totalStepCount
        self.classification = classification
    }
}

/// Computes the §9 derived metrics for one workout against the plan in force (D2).
///
/// ## Where the thresholds come from
///
/// Every threshold this reads — the HR cap, the zone boundaries anchored to it, the
/// cadence band a caller compares the result against — comes from the `Plan` passed in
/// (D1). Nothing here knows that today's cap is 150 bpm, and the returned
/// `DerivedMetrics` records the plan version it was computed against so a later version
/// cannot silently re-interpret an old number.
///
/// ## Absent is not zero
///
/// Each metric is optional, and nil means *this run does not have one*: no HR series,
/// an indoor run with no grade to correct for, drift on a session where §9 says drift is
/// near-meaningless. The distinction is load-bearing for the dashboard — a nil is left
/// out of a trend, whereas a zero is averaged into it and drags it down. Zero is
/// reserved for the cases where zero is the true answer, of which "no seconds above the
/// cap" is the important one: a perfectly disciplined easy run.
///
/// ## Purity, and the ordering question it settles
///
/// This is a pure function: same inputs, same outputs, always. That matters because
/// classification (MAX-013) reads a workout's HR profile while drift here reads the
/// classification. Ingestion is free to compute metrics, classify from them, and
/// compute once more with the classification supplied; running it twice cannot produce a
/// different answer, and only the final value is stored.
public enum DerivedMetricsCalculator {
    /// - Parameters:
    ///   - plan: the plan version in force on the workout's date (MAX-011 resolves it).
    ///   - zoneModel: defaults to the zones anchored on this plan's cap.
    ///   - gradeAdjustment: filter knobs for noisy GPS altitude; the defaults are what
    ///     production uses.
    public static func compute(
        _ input: DerivedMetricsInput,
        plan: Plan,
        zoneModel: HeartRateZoneModel? = nil,
        gradeAdjustment: GradeAdjustmentParameters = .default
    ) throws -> DerivedMetrics {
        let zones: HeartRateZoneModel
        if let zoneModel {
            zones = zoneModel
        } else {
            zones = try HeartRateZoneModel.capAnchored(heartRateCapBPM: plan.heartRateCapBPM)
        }

        var averageHeartRateBPM: Double?
        var maximumHeartRateBPM: Double?
        var timeAboveCapSeconds: Double?
        var heartRateDriftFraction: Double?
        var zoneSplits = ZoneSplits.empty

        if let series = input.heartRateSeries {
            let curve = HeartRateCurve(series)
            averageHeartRateBPM = curve.averageBPM
            maximumHeartRateBPM = curve.maximumBPM
            // A single-sample series covers no span, so it truthfully spent zero seconds
            // above the cap and has no zone splits. Zero rather than nil here because the
            // run does have heart-rate data — nil would be indistinguishable from a
            // workout the sensor never covered at all.
            timeAboveCapSeconds = curve.secondsAbove(plan.heartRateCapBPM)
            zoneSplits = try curve.zoneSplits(model: zones)

            // §9: drift is "most meaningful on easy and long runs; near-meaningless on
            // interval/hard runs, so surfaced conditionally". An unclassified workout is
            // not yet known to be one of the meaningful kinds, so it gets no drift
            // either — the alternative is emitting a number and hoping the view
            // remembers to hide it.
            if input.classification?.driftIsMeaningful == true {
                heartRateDriftFraction = curve.driftFraction
            }
        }

        return try DerivedMetrics(
            workoutID: input.workout.id,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: timeAboveCapSeconds,
            heartRateDriftFraction: heartRateDriftFraction,
            averageCadenceStepsPerMinute: averageCadence(
                totalStepCount: input.totalStepCount,
                durationSeconds: input.workout.durationSeconds
            ),
            gradeAdjustedPaceSecondsPerKilometer: GradeAdjustedPace.secondsPerKilometer(
                workout: input.workout,
                route: input.route,
                parameters: gradeAdjustment
            ),
            zoneSplits: zoneSplits,
            // FR-1.5, and D2's whole point: the pace breakdown is cut here, once, from
            // the route (or, for an indoor run, the distance-sample series — MAX-066)
            // and the recorded distance — not in a view, and not a second time for the
            // chat. `DistanceSplitCalculator` documents what it measures against, which
            // source wins when both are present, and every case in which it truthfully
            // returns nil.
            distanceSplits: DistanceSplitCalculator.splits(
                workout: input.workout,
                route: input.route,
                distanceSamples: input.distanceSamples
            ),
            planVersion: plan.version
        )
    }

    /// Steps per minute over the run (§9), against the workout's **active** duration —
    /// `Workout.durationSeconds`, not its wall-clock span, because paused time is time
    /// the athlete was not taking steps and would depress the average.
    ///
    /// Nil when no step count was captured, or when the workout has no duration to
    /// divide by. A zero-duration workout is a real ingestion case (a mis-started
    /// session) and its cadence is unknowable, not zero.
    ///
    /// Comparison against `Plan.cadenceTarget` is deliberately not made here: the band is
    /// plan data, `CadenceBand.contains` already answers the question, and baking a
    /// verdict into a stored metric would freeze one plan version's opinion into the
    /// record.
    static func averageCadence(totalStepCount: Double?, durationSeconds: Double) -> Double? {
        guard let totalStepCount, durationSeconds > 0 else { return nil }
        return totalStepCount / (durationSeconds / 60)
    }
}
