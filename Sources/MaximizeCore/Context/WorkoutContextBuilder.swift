import Foundation

/// The single assembler of what Claude knows about a run (D3).
///
/// Both the scorer (MAX-015) and the per-workout chat consume `build`'s output and
/// render it with `WorkoutContext.factSheet()`. Nothing else in the system may
/// assemble prompt context — CLAUDE.md makes that a rule rather than a preference,
/// because a second assembler drifts from this one and the drift is invisible until a
/// number on screen disagrees with a sentence in the chat.
public enum WorkoutContextBuilder {
    /// - Parameters:
    ///   - day: the calendar day the workout belongs to, in the athlete's time zone.
    ///     Required rather than derived: `Workout.calendarDay(in:)` needs a zone, and
    ///     guessing one here would silently move late-evening runs onto the next day.
    ///   - planCalendar: resolves which plan version governs `day` (MAX-011, D1).
    ///   - existingScore: pass the assigned score when building context **for chat**;
    ///     pass nil when building it **for scoring**. See `WorkoutContext.existingScore`.
    ///
    /// - Throws: when the pieces do not describe the same workout under the same plan.
    ///   These are assembly errors, not data errors, and they are worth failing on:
    ///   a context that quietly mixes one run's metrics with another's plan would
    ///   produce a confident, wrong, and permanently stored score (D8).
    public static func build(
        workout: Workout,
        on day: CalendarDay,
        metrics: DerivedMetrics,
        classification: WorkoutClassification,
        planCalendar: PlanCalendar,
        heartRateSeries: HeartRateSeries? = nil,
        existingScore: Score? = nil
    ) throws -> WorkoutContext {
        guard metrics.workoutID == workout.id else {
            throw DomainError.inconsistent(
                reason: "WorkoutContext: metrics belong to a different workout"
            )
        }
        if let heartRateSeries, heartRateSeries.workoutID != workout.id {
            throw DomainError.inconsistent(
                reason: "WorkoutContext: heart-rate series belongs to a different workout"
            )
        }
        if let existingScore, existingScore.workoutID != workout.id {
            throw DomainError.inconsistent(
                reason: "WorkoutContext: score belongs to a different workout"
            )
        }

        let plan = planCalendar.plan(on: day)
        let planDay = try planCalendar.planDay(on: day)

        // D1's coherence check, and the reason this is worth a throw. `DerivedMetrics`
        // records the plan version its thresholds came from (MAX-012). If that is not
        // the version governing the day, then "time above cap" was measured against a
        // cap the plan did not have — the number would look ordinary and be wrong.
        if let plan, metrics.planVersion != plan.version {
            throw DomainError.inconsistent(
                reason: "WorkoutContext: metrics were computed against plan \(metrics.planVersion) "
                    + "but \(plan.version) governs \(day). Recompute the metrics against the "
                    + "governing version rather than presenting them together."
            )
        }

        return WorkoutContext(
            day: day,
            workout: workout,
            metrics: metrics,
            classification: classification,
            plan: plan,
            planDay: planDay,
            heartRateShape: heartRateSeries.flatMap(HeartRateShape.init(downsampling:)),
            existingScore: existingScore
        )
    }
}

extension HeartRateShape {
    /// Reduces a series to `bucketCount` equal-elapsed-time buckets.
    ///
    /// Nil when the series covers no time at all — a single sample has a heart rate but
    /// no shape, and an "average over 0 seconds" is not a thing to tell Claude.
    ///
    /// Buckets with no samples are dropped rather than interpolated. A gap in the
    /// record is a fact about the run; filling it in would be inventing data, and the
    /// resulting curve would be indistinguishable from a measured one.
    init?(downsampling series: HeartRateSeries) {
        let start = series.firstSample.offsetSeconds
        let span = series.coveredSeconds
        guard span > 0 else { return nil }

        var totals = [Double](repeating: 0, count: Self.bucketCount)
        var counts = [Int](repeating: 0, count: Self.bucketCount)

        for sample in series.samples {
            let fraction = (sample.offsetSeconds - start) / span
            // The final sample lands exactly on 1.0 and belongs in the last bucket, not
            // in a nonexistent eleventh one.
            let index = min(Int(fraction * Double(Self.bucketCount)), Self.bucketCount - 1)
            totals[index] += sample.beatsPerMinute
            counts[index] += 1
        }

        let buckets = (0..<Self.bucketCount).compactMap { index -> Bucket? in
            guard counts[index] > 0 else { return nil }
            return Bucket(
                startFraction: Double(index) / Double(Self.bucketCount),
                averageBeatsPerMinute: totals[index] / Double(counts[index])
            )
        }

        guard !buckets.isEmpty else { return nil }
        self.init(buckets: buckets)
    }
}
