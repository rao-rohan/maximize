import Foundation

/// Chart-ready presentation of one workout's HR curve with the plan's cap overlaid
/// (FR-1.2) — everything the detail view needs to draw the curve, precomputed here so
/// CI, not a device, is what verifies it.
///
/// ## Two numbers that must never be allowed to disagree
///
/// "Time above cap" only has one legitimate source: `DerivedMetrics.timeAboveCapSeconds`,
/// computed once at ingestion and stored (D2). `timeAboveCapSeconds` below is a plain
/// pass-through of that value — this initializer never derives it, sums it, or checks
/// it against anything else it computes.
///
/// `aboveCapExcursions` is a different kind of thing entirely: a set of polygons in
/// (offset, bpm) space, built from `HeartRateCurve.excursionsAbove(_:)`, whose only job
/// is telling a chart *where* to shade. Nothing on this type turns those polygons back
/// into a duration — there is no `aboveCapExcursions.reduce(0) { … }` anywhere near this
/// file, and a view has no way to read a second "time above cap" out of it, because
/// there isn't one to read. The stored figure is *stated*; the excursions are *shaded*.
/// They are computed from the same curve and the same cap, so they agree on *where* the
/// line crosses — that is what "shade from the curve" in the ticket means — but they are
/// never derived from one another, which is what keeps them from silently drifting apart
/// the way a recomputed metric would (D2's whole concern).
///
/// ## `HeartRateCurve` stays internal
///
/// This type is the module's only public door onto a curve for display purposes.
/// `HeartRateCurve` itself is deliberately not exported — see its own documentation —
/// because a public curve type would let a view re-derive `averageBPM` or `secondsAbove`
/// for itself, which is exactly the second-source-of-truth problem D2 exists to prevent.
public struct HeartRateChartData: Hashable, Sendable {
    /// One point on the curve, in the (elapsed seconds, bpm) space a chart plots.
    public struct Point: Hashable, Sendable {
        public let offsetSeconds: Double
        public let beatsPerMinute: Double

        public init(offsetSeconds: Double, beatsPerMinute: Double) {
            self.offsetSeconds = offsetSeconds
            self.beatsPerMinute = beatsPerMinute
        }
    }

    /// One point per stored sample — the line itself. A straight pass-through of what
    /// was captured; no resampling or bucketing happens here.
    public let points: [Point]

    /// The governing plan's `Plan.heartRateCapBPM` (D1), or nil when no plan governs the
    /// workout's day. Nil means there is nothing to draw as a threshold — never a
    /// fallback constant.
    public let capBPM: Double?

    /// `DerivedMetrics.timeAboveCapSeconds`, unchanged. State this in the view; never
    /// derive a competing number from `aboveCapExcursions` — see the type documentation.
    public let timeAboveCapSeconds: Double?

    /// Above-cap excursions as closed polygons, each beginning and ending exactly at the
    /// curve's interpolated cap crossing, for a view to fill against `capBPM`. Shape
    /// only. Empty when there is no cap or the curve never exceeds it — a perfectly held
    /// easy run reads as an empty array here, not as an error.
    public let aboveCapExcursions: [[Point]]

    public let minimumBPM: Double
    public let maximumBPM: Double

    /// The span the curve actually covers, padded slightly so a flat or single-sample
    /// curve still has a usable width to plot against.
    public let offsetSecondsDomain: ClosedRange<Double>

    /// - Parameters:
    ///   - series: the stored curve (`WorkoutRepository.heartRateSeries(forWorkout:)`).
    ///   - capBPM: `Plan.heartRateCapBPM` for the plan governing this workout's day
    ///     (`PlanCalendar.plan(on:)`), or nil if none does.
    ///   - timeAboveCapSeconds: `DerivedMetrics.timeAboveCapSeconds`, passed straight
    ///     through. This initializer never computes it.
    public init(series: HeartRateSeries, capBPM: Double?, timeAboveCapSeconds: Double?) {
        let curve = HeartRateCurve(series)

        self.points = series.samples.map { Point(offsetSeconds: $0.offsetSeconds, beatsPerMinute: $0.beatsPerMinute) }
        self.capBPM = capBPM
        self.timeAboveCapSeconds = timeAboveCapSeconds
        self.aboveCapExcursions = capBPM.map(curve.excursionsAbove) ?? []
        self.minimumBPM = series.samples.reduce(series.samples[0].beatsPerMinute) { Swift.min($0, $1.beatsPerMinute) }
        self.maximumBPM = curve.maximumBPM

        let start = series.firstSample.offsetSeconds
        let end = series.lastSample.offsetSeconds
        self.offsetSecondsDomain = start < end ? start...end : (start - 30)...(end + 30)
    }

    /// The y-axis range a chart should use: the curve's own bounds, expanded to include
    /// the cap line when there is one, padded so the threshold and the curve's peak are
    /// never drawn flush against the frame edge. FR-1.2's "cap drawn as a horizontal
    /// line" only holds if the line is inside the plotted area.
    public var bpmAxisDomain: ClosedRange<Double> {
        let lower = capBPM.map { Swift.min($0, minimumBPM) } ?? minimumBPM
        let upper = capBPM.map { Swift.max($0, maximumBPM) } ?? maximumBPM
        guard lower < upper else {
            return (lower - 5)...(upper + 5)
        }
        let pad = (upper - lower) * 0.08
        return (lower - pad)...(upper + pad)
    }

    /// A UI-facing duration string ("45s", "12m 34s", "1h 02m 03s") for stating
    /// `timeAboveCapSeconds` in the detail view. The hours/minutes/seconds bucketing is
    /// a calculation, so it lives here where CI exercises it, rather than in the view.
    public static func formattedDuration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        if hours > 0 { return String(format: "%dh %02dm %02ds", locale: nil, hours, minutes, remainder) }
        if minutes > 0 { return String(format: "%dm %02ds", locale: nil, minutes, remainder) }
        return "\(remainder)s"
    }
}
