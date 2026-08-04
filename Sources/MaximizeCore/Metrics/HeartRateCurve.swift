import Foundation

/// A workout's heart-rate samples read as a **piecewise-linear function of time**.
///
/// ## The interpolation assumption, stated once
///
/// Samples arrive irregularly — a wrist sensor emits when it emits, and gaps of one
/// second and of ninety seconds sit in the same series. Every metric in §9 that has a
/// unit of *seconds* therefore rests on an assumption about what the heart was doing
/// between two samples, and the assumption is: **it moved linearly**. A gap between a
/// 148 bpm sample and a 155 bpm sample, with a 150 bpm cap, is not "one sample above
/// the cap" and not "no time above the cap" — it is 5/7 of that gap above the cap,
/// because the modelled curve crosses 150 two sevenths of the way through.
///
/// The alternatives were considered and rejected: counting samples above the cap makes
/// the number depend on sampling density rather than on the run, and step interpolation
/// ("hold the last value") biases every crossing by a full sample interval in whichever
/// direction the sensor happened to fire. Linear interpolation is the minimal
/// assumption that makes the metric a property of the run.
///
/// Two consequences worth knowing:
///
/// - **No extrapolation.** Time is attributed only between the first and last sample.
///   A series that starts 60 s into a workout contributes nothing for those 60 s, and
///   `zoneSplits` therefore sums to `coveredSeconds`, not to the workout's duration.
///   Inventing the missing minute would be inventing data.
/// - **Dropouts are interpolated like any other gap.** If the sensor loses contact for
///   ten minutes, that span is modelled as a straight line between the samples either
///   side. This is a known limitation rather than a considered position; if dropouts
///   turn out to distort real runs, the fix is to record them as gaps at ingestion, not
///   to guess here.
///
/// Deliberately internal. Making it public would invite a view to re-derive a metric at
/// display time, which is precisely the D2 drift that storing `DerivedMetrics` once
/// exists to prevent.
struct HeartRateCurve {
    /// Non-empty and strictly ascending by offset — guaranteed by `HeartRateSeries`.
    let samples: [HeartRateSample]

    init(_ series: HeartRateSeries) {
        self.samples = series.samples
    }

    var startOffsetSeconds: Double { samples[0].offsetSeconds }

    var endOffsetSeconds: Double { samples[samples.count - 1].offsetSeconds }

    /// Span the curve actually covers. Zero for a single-sample series.
    var coveredSeconds: Double { endOffsetSeconds - startOffsetSeconds }

    /// The peak is a sample value: linear interpolation never rises above the endpoints
    /// of the segment it spans, so there is nothing between samples to find.
    var maximumBPM: Double {
        samples.reduce(samples[0].beatsPerMinute) { Swift.max($0, $1.beatsPerMinute) }
    }

    /// Mean heart rate, weighted by time rather than by sample.
    ///
    /// Time-weighted because sampling is irregular: a minute of dense sampling during a
    /// climb would otherwise outvote five quiet minutes, and the "average HR" tile would
    /// report the sensor's behaviour rather than the athlete's. A single-sample series
    /// has no span to weight by, so it reports its one value.
    var averageBPM: Double {
        timeWeightedMeanBPM(from: startOffsetSeconds, to: endOffsetSeconds)
            ?? samples[0].beatsPerMinute
    }

    /// Seconds where the modelled curve is **strictly above** `thresholdBPM` (§9 defines
    /// time above cap as `HR > hr_cap`, so a beat exactly at the cap is not above it).
    func secondsAbove(_ thresholdBPM: Double) -> Double {
        var total = 0.0
        forEachSubInterval(from: startOffsetSeconds, to: endOffsetSeconds) { start, end, startBPM, endBPM in
            let duration = end - start
            if startBPM > thresholdBPM && endBPM > thresholdBPM {
                total += duration
            } else if startBPM <= thresholdBPM && endBPM <= thresholdBPM {
                return
            } else {
                // Exactly one end is above, so the values differ and the crossing is
                // well defined.
                let crossing = start + (thresholdBPM - startBPM) / (endBPM - startBPM) * duration
                total += startBPM > thresholdBPM ? (crossing - start) : (end - crossing)
            }
        }
        return total
    }

    /// Time in each zone, splitting every segment at each boundary it crosses.
    ///
    /// Zones with no time are omitted rather than recorded as zero — `ZoneSplits` reads
    /// an absent zone as zero seconds, and a run that never left zone 2 should not carry
    /// four empty rows.
    func zoneSplits(model: HeartRateZoneModel) throws -> ZoneSplits {
        var secondsByZone: [HeartRateZone: Double] = [:]
        forEachSubInterval(from: startOffsetSeconds, to: endOffsetSeconds) { start, end, startBPM, endBPM in
            let duration = end - start
            var cuts: [Double] = [start, end]
            if endBPM != startBPM {
                let lower = Swift.min(startBPM, endBPM)
                let upper = Swift.max(startBPM, endBPM)
                for bound in model.upperBoundsBPM where bound > lower && bound < upper {
                    cuts.append(start + (bound - startBPM) / (endBPM - startBPM) * duration)
                }
            }
            cuts.sort()
            for index in 1..<cuts.count {
                let sliceStart = cuts[index - 1]
                let sliceEnd = cuts[index]
                guard sliceEnd > sliceStart else { continue }
                // The segment is linear and the slice lies between two crossings, so the
                // midpoint's zone is the whole slice's zone.
                let midpoint = (sliceStart + sliceEnd) / 2
                let midpointBPM = startBPM + (endBPM - startBPM) * ((midpoint - start) / duration)
                secondsByZone[model.zone(for: midpointBPM), default: 0] += sliceEnd - sliceStart
            }
        }

        var splits: [ZoneSplits.Split] = []
        for zone in HeartRateZone.allCases {
            guard let seconds = secondsByZone[zone], seconds > 0 else { continue }
            splits.append(try ZoneSplits.Split(zone: zone, seconds: seconds))
        }
        return try ZoneSplits(splits: splits)
    }

    /// Aerobic decoupling: `(avg HR 2nd half / avg HR 1st half) − 1` (§9), as a fraction.
    ///
    /// ## Halves are split by elapsed time, not by sample count
    ///
    /// The two disagree whenever sampling is irregular, and irregular is the normal
    /// case. Splitting by count puts the midpoint wherever the sensor happened to be
    /// chatty — a minute of dense samples early in a run drags the "midpoint" toward the
    /// start, so the second half absorbs part of the first and the drift number shrinks
    /// for a reason that has nothing to do with the athlete. Splitting at the midpoint
    /// *offset* makes drift a property of the run: the same run resampled at a different
    /// rate yields the same number.
    ///
    /// The value at the midpoint is interpolated and used as the closing point of the
    /// first half and the opening point of the second, so no span is dropped or counted
    /// twice, and an odd sample count needs no tie-break rule at all.
    ///
    /// Nil when the curve covers no span (a single sample). Applicability — drift is
    /// "near-meaningless on interval/hard runs" (§9) — is decided by the caller, which
    /// knows the classification; see `DerivedMetricsCalculator`.
    var driftFraction: Double? {
        guard coveredSeconds > 0 else { return nil }
        let midpoint = startOffsetSeconds + coveredSeconds / 2
        guard let firstHalf = timeWeightedMeanBPM(from: startOffsetSeconds, to: midpoint),
              let secondHalf = timeWeightedMeanBPM(from: midpoint, to: endOffsetSeconds),
              firstHalf > 0
        else { return nil }
        return secondHalf / firstHalf - 1
    }

    /// Time-weighted mean over `[from, to]`, clipped to the covered span. Nil when the
    /// clipped window has no duration — there is no meaningful average of an instant.
    func timeWeightedMeanBPM(from: Double, to: Double) -> Double? {
        let lower = Swift.max(from, startOffsetSeconds)
        let upper = Swift.min(to, endOffsetSeconds)
        guard upper > lower else { return nil }
        return integral(from: lower, to: upper) / (upper - lower)
    }

    /// ∫ bpm dt over `[from, to]`, by trapezoid — exact for a piecewise-linear curve.
    func integral(from: Double, to: Double) -> Double {
        var total = 0.0
        forEachSubInterval(from: from, to: to) { start, end, startBPM, endBPM in
            total += (startBPM + endBPM) / 2 * (end - start)
        }
        return total
    }

    /// The curve's shape where it is strictly above `thresholdBPM`, split into separate
    /// excursions and closed exactly at the interpolated threshold crossing at each end
    /// — the polygon a chart fills to shade "time above cap" (FR-1.2).
    ///
    /// **This exists to draw a shape, not to measure one.** It shares the same crossing
    /// formula `secondsAbove(_:)` uses, so the region a view shades and the duration §9
    /// defines are never in tension about *where* the curve crosses the cap — but
    /// nothing here sums an excursion's width back into seconds, and nothing calling
    /// this may do so either. The stated figure (`DerivedMetrics.timeAboveCapSeconds`,
    /// computed once at ingestion, D2) is what gets displayed as text; this is only
    /// consulted for *where to fill*. `HeartRateChartData.init` is the one caller, and
    /// it keeps the two values structurally apart — see its type documentation.
    ///
    /// Empty when the curve never exceeds `thresholdBPM`, which is a real state (a
    /// perfectly held easy run), not a bug.
    func excursionsAbove(_ thresholdBPM: Double) -> [[HeartRateChartData.Point]] {
        var excursions: [[HeartRateChartData.Point]] = []
        var current: [HeartRateChartData.Point] = []

        forEachSubInterval(from: startOffsetSeconds, to: endOffsetSeconds) { start, end, startBPM, endBPM in
            let startAbove = startBPM > thresholdBPM
            let endAbove = endBPM > thresholdBPM

            if startAbove && endAbove {
                if current.isEmpty {
                    current.append(HeartRateChartData.Point(offsetSeconds: start, beatsPerMinute: startBPM))
                }
                current.append(HeartRateChartData.Point(offsetSeconds: end, beatsPerMinute: endBPM))
            } else if !startAbove && !endAbove {
                if !current.isEmpty {
                    excursions.append(current)
                    current = []
                }
            } else {
                // Exactly one end is above, so the values differ and the crossing is
                // well defined — the same formula `secondsAbove(_:)` uses.
                let duration = end - start
                let crossing = start + (thresholdBPM - startBPM) / (endBPM - startBPM) * duration
                let crossingPoint = HeartRateChartData.Point(offsetSeconds: crossing, beatsPerMinute: thresholdBPM)
                if startAbove {
                    // Descending through the threshold: close the excursion here.
                    if current.isEmpty {
                        current.append(HeartRateChartData.Point(offsetSeconds: start, beatsPerMinute: startBPM))
                    }
                    current.append(crossingPoint)
                    excursions.append(current)
                    current = []
                } else {
                    // Ascending through the threshold: begin a new excursion.
                    current = [crossingPoint, HeartRateChartData.Point(offsetSeconds: end, beatsPerMinute: endBPM)]
                }
            }
        }

        if !current.isEmpty {
            excursions.append(current)
        }

        return excursions
    }

    /// Walks the parts of `[from, to]` that lie inside the covered span, one
    /// sample-to-sample segment at a time, handing each piece its interpolated end
    /// values. Every seconds-valued metric here is built on this so they cannot drift
    /// apart in how they treat a partial segment.
    private func forEachSubInterval(
        from: Double,
        to: Double,
        _ body: (_ start: Double, _ end: Double, _ startBPM: Double, _ endBPM: Double) -> Void
    ) {
        guard samples.count > 1 else { return }
        let lower = Swift.max(from, startOffsetSeconds)
        let upper = Swift.min(to, endOffsetSeconds)
        guard upper > lower else { return }

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let start = Swift.max(previous.offsetSeconds, lower)
            let end = Swift.min(current.offsetSeconds, upper)
            guard end > start else { continue }

            let span = current.offsetSeconds - previous.offsetSeconds
            // Strictly ascending offsets make `span` positive; the guard keeps the
            // division honest rather than relying on that invariant from a distance.
            guard span > 0 else { continue }
            let slope = (current.beatsPerMinute - previous.beatsPerMinute) / span
            let startBPM = previous.beatsPerMinute + slope * (start - previous.offsetSeconds)
            let endBPM = previous.beatsPerMinute + slope * (end - previous.offsetSeconds)
            body(start, end, startBPM, endBPM)
        }
    }
}
