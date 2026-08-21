import Foundation

/// The single assembler of what Claude knows about one workout — a run or a lift (D3).
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
    ///   - audience: who this context will be shown to, and therefore how much of the
    ///     record it may carry (MAX-068). Defaults to `.scoring`, the smaller payload,
    ///     so a caller that has not thought about it does not widen what leaves the
    ///     device by omission. See `WorkoutContext.Audience`.
    ///   - existingScore: pass the assigned score when building context **for chat**;
    ///     pass nil when building it **for scoring**. See `WorkoutContext.existingScore`.
    ///     Kept as its own parameter rather than folded into `audience`: its absence is
    ///     also a real data state — an unscored run has no score to show anybody — so
    ///     it is a value the caller supplies, not a policy this builder applies.
    ///   - surroundingWeek: where this workout sits in the athlete's training week
    ///     (MAX-182). **Assembled by `ContextBuilder` and dropped here for any audience but
    ///     `.chat`**, whatever the caller passes. Nil is the default and the scorer's call
    ///     site does not mention it, so the scoring prompt is byte-identical to what it was
    ///     before this parameter existed. See `WorkoutContext.surroundingWeek` for why a
    ///     scorer shown the surrounding week would produce a score that depends on days
    ///     other than the one it is scoring.
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
        audience: WorkoutContext.Audience = .scoring,
        heartRateSeries: HeartRateSeries? = nil,
        existingScore: Score? = nil,
        surroundingWeek: WorkoutContext.SurroundingWeek? = nil
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
        // The block is titled "the week around this session", so a week the session does
        // not fall in is not a smaller truth — it is a false heading over real figures, and
        // the model has no way to notice. Checked before the audience gate so a caller that
        // assembled the wrong week is told regardless of who was going to be shown it.
        if let surroundingWeek, day < surroundingWeek.from || day > surroundingWeek.through {
            throw DomainError.inconsistent(
                reason: "WorkoutContext: the surrounding week \(surroundingWeek.from)…"
                    + "\(surroundingWeek.through) does not contain \(day), the day this "
                    + "workout falls on"
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
            audience: audience,
            day: day,
            workout: workout,
            metrics: metrics,
            classification: classification,
            plan: plan,
            planDay: planDay,
            heartRateShape: heartRateSeries.flatMap(HeartRateShape.init(downsampling:)),
            // MAX-068's whole decision, in one expression and in one place. The splits
            // are *selected* here rather than reached for by the renderer, so "does this
            // health data leave the device" is answered by the single assembler D3 names
            // and not by a branch somewhere downstream.
            //
            // MAX-136 adds the discipline half of the same question. A lift has no
            // per-kilometre pace breakdown to send, and the guard is not redundant: it
            // is the only thing standing between a lift's *stored* metrics from before
            // MAX-130 gated them — which really do carry a fabricated split series — and
            // a prompt describing a strength session in kilometres.
            //
            // Gated on the discipline rather than on `DerivedMetricKind.distanceSplits`,
            // whose requirement is the narrower `.runningActivity`. The fact sheet
            // branches on discipline (LIFTING-SPEC §10.1), so gating the data more
            // narrowly than the section would leave a hike's chat prompt printing "no
            // breakdown is on file for this run" over splits that are on file — an
            // absence stated about a record that has the thing, which is worse than
            // either sending or omitting it.
            paceBreakdown: audience == .chat && workout.activityType.discipline == .run
                ? metrics.distanceSplits?.series(in: WorkoutContext.paceBreakdownUnit)
                : nil,
            existingScore: existingScore,
            // MAX-182's whole decision, in the same expression shape and the same place as
            // MAX-068's above, so "does this health data leave the device" keeps being
            // answered by the single assembler D3 names rather than by a branch downstream.
            // The scorer's own call site passes nothing, so this is belt and braces — but
            // it is the belt that makes the guarantee structural: no audience but `.chat`
            // can hold a surrounding week, whatever a future caller hands in.
            surroundingWeek: audience == .chat ? surroundingWeek : nil
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
