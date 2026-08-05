import Foundation

/// One run's stored heart-rate drift figure, plotted against the date it happened
/// (FR-3.3, D5) — the trendline half of the cross-run drift comparison that MAX-062
/// reported and deliberately did not build.
///
/// ## A second chart, over a different quantity
///
/// `HeartRateDriftOverlayData` draws heart rate against %-elapsed, one *curve* per run.
/// This type draws something else entirely: `DerivedMetrics.heartRateDriftFraction`
/// (D2), one *scalar* per run, against the run's calendar date. Fitting a line through
/// the normalised curves above would answer a related but different question — "what
/// does the average shape look like" rather than "how has the stored drift figure moved
/// over time" — and the resulting line could disagree with the number the overlay's own
/// legend prints beside each curve. Reading `driftFraction` verbatim, exactly as
/// `NormalizedHeartRateCurve` already does, keeps this chart and that legend describing
/// one number rather than two.
///
/// ## Same runs the overlay draws, by construction
///
/// This type is built from `HeartRateDriftOverlayData.curves` — the overlay's own
/// stacked, filtered output — not from `HeartRateDriftOverlayData.Candidate` or a
/// workout repository. That is deliberate: reimplementing the eligibility rules
/// (scored, drift-meaningful, has a curve, long enough to normalise, within the stack
/// limit) here would risk drifting from the overlay's own filter, and the two halves of
/// one chart would then silently describe different runs. Consuming `curves` directly
/// means this trendline can only ever cover exactly the runs whose shape is drawn above
/// it — there is no second filter to keep in sync.
///
/// MAX-083 added one further door, `init(points:)`, for the year span — the one place
/// where there is no overlay on screen for this line to disagree with, and where the
/// overlay's shape-drawing rules would exclude runs whose stored figure is perfectly
/// good. See that initializer and `DriftFigureSelection` for the full argument.
///
/// A curve with no stored drift figure (`driftFraction == nil`) contributes no point.
/// Never a zero — the same "absent, not zero" discipline `NormalizedHeartRateCurve`
/// documents for the number itself.
public struct HeartRateDriftTrendlineData: Hashable, Sendable {

    /// One run's stored drift figure, ready to plot.
    public struct Point: Hashable, Sendable, Identifiable {
        public var id: UUID { workoutID }
        public let workoutID: UUID

        /// The run's start — `NormalizedHeartRateCurve.start`, the same date the
        /// overlay's own legend labels this run with.
        public let date: Date

        /// `DerivedMetrics.heartRateDriftFraction`, verbatim (D2). Never derived from a
        /// curve, here or anywhere upstream of this initializer.
        public let driftFraction: Double

        public init(workoutID: UUID, date: Date, driftFraction: Double) {
            self.workoutID = workoutID
            self.date = date
            self.driftFraction = driftFraction
        }
    }

    /// A least-squares line through `points`, in date / drift-fraction space.
    ///
    /// ### Why time, not run index
    ///
    /// Runs in an interval are not evenly spaced — a taper week might carry one run, a
    /// build week five, three days apart or fourteen. Fitting against *index* (1st, 2nd,
    /// 3rd stacked run) would treat every gap as equal width, quietly answering "how
    /// does drift change per run" rather than "how does drift change over time" — a
    /// different question, with a different line. This fits against `Point.date`
    /// directly, so two runs a fortnight apart pull the line less per-day than two runs
    /// back to back.
    ///
    /// ### Why ordinary least squares
    ///
    /// One scalar per run — a dozen points behind the overlay at a week or a month, a
    /// couple of hundred at a year — and no claim beyond "the line minimising squared
    /// vertical distance to these points". The ordinary, legible choice for exactly this
    /// shape of data, and simple enough that a test can pin its arithmetic by hand rather
    /// than trusting a library. Centering on the first point (below) is what keeps it
    /// well-conditioned as the span grows.
    public struct Fit: Hashable, Sendable {
        /// The date the fit is centered on for evaluation — `points.first?.date` by
        /// construction. Not meant to be read directly: call `value(at:)`, which
        /// measures every date relative to this one internally.
        ///
        /// Centering matters for more than tidiness. `Date.timeIntervalSinceReferenceDate`
        /// is already on the order of 10^9 for any date in this app's lifetime, and the
        /// least-squares sums square that magnitude before combining it with a fraction
        /// on the order of 10^-2 — differencing two such sums back down to a slope would
        /// throw away precision a training-log-length interval should never have to
        /// spend. Working in offsets from the earliest plotted run keeps every quantity
        /// the arithmetic touches close to the scale of the answer.
        private let referenceDate: Date

        /// Change in drift fraction per second. Small and not meant to be read directly
        /// either — a per-second slope is not a unit anyone reasons in; `value(at:)` is
        /// the interface this type offers.
        private let slopePerSecond: Double

        private let driftFractionAtReferenceDate: Double

        init(referenceDate: Date, slopePerSecond: Double, driftFractionAtReferenceDate: Double) {
            self.referenceDate = referenceDate
            self.slopePerSecond = slopePerSecond
            self.driftFractionAtReferenceDate = driftFractionAtReferenceDate
        }

        /// The fitted drift fraction at any date, not only at a stored point. A chart
        /// draws the line by evaluating this at its first and last plotted dates.
        public func value(at date: Date) -> Double {
            driftFractionAtReferenceDate + slopePerSecond * date.timeIntervalSince(referenceDate)
        }
    }

    /// Ascending by date. One entry per run `HeartRateDriftOverlayData` stacked that
    /// also carries a stored drift figure.
    public let points: [Point]

    /// nil below two points — a line through zero or one point is not a trend, it is a
    /// single run's history so far, and drawing a flat line through it would claim a
    /// direction nothing supports. Also nil when every point shares one exact date: with
    /// no spread on the x-axis there is no slope to fit, only a division by zero to
    /// avoid.
    ///
    /// Zero or one qualifying run is an ordinary state — the athlete's first week, or an
    /// interval where only one stacked run happened to carry a stored drift figure —
    /// not an error. A view should render its absence as a sentence, the same "absent,
    /// not empty" discipline `HeartRateDriftOverlayData.exclusionNotes` established.
    public let fit: Fit?

    /// - Parameter curves: `HeartRateDriftOverlayData.curves` — the overlay's own
    ///   stacked output. Order does not matter; this initializer re-sorts by date. What
    ///   matters is passing that array unfiltered and untouched: passing anything else
    ///   (a raw candidate list, a hand-filtered subset) defeats the guarantee that this
    ///   trendline covers exactly the runs the overlay draws.
    public init(curves: [NormalizedHeartRateCurve]) {
        self.init(
            points: curves.compactMap { curve -> Point? in
                guard let driftFraction = curve.driftFraction else { return nil }
                return Point(workoutID: curve.workoutID, date: curve.start, driftFraction: driftFraction)
            }
        )
    }

    /// The trendline over points a caller has already selected.
    ///
    /// **The `curves:` initializer above remains the only correct door wherever the
    /// overlay is on screen**, and the reasoning in this type's documentation is
    /// unchanged: a legend built from the overlay's stack and a line built from a
    /// separately-filtered set would silently describe different runs.
    ///
    /// This door exists for the one span where there is no overlay to disagree with. At a
    /// year `DriftSectionRepresentation.trendlineOnly` draws this chart alone, over
    /// `DriftFigureSelection`'s wider set — every run whose stored drift figure is
    /// meaningful, not only those whose curve was long enough to resample — and that type
    /// owns the eligibility rules and states what it left out. Nothing else should call
    /// this: a caller assembling points by hand is exactly the second filter the
    /// `curves:` path exists to prevent.
    ///
    /// - Parameter points: in any order; this initializer sorts by date.
    public init(points: [Point]) {
        let ordered = points.sorted { $0.date < $1.date }
        self.points = ordered
        self.fit = Self.leastSquares(through: ordered)
    }

    private static func leastSquares(through points: [Point]) -> Fit? {
        guard points.count >= 2, let referenceDate = points.first?.date else { return nil }

        let xs = points.map { $0.date.timeIntervalSince(referenceDate) }
        let ys = points.map(\.driftFraction)
        let count = Double(points.count)
        let xMean = xs.reduce(0, +) / count
        let yMean = ys.reduce(0, +) / count

        var sumSquaredDeviationX = 0.0
        var sumCrossDeviation = 0.0
        for (x, y) in zip(xs, ys) {
            let dx = x - xMean
            sumSquaredDeviationX += dx * dx
            sumCrossDeviation += dx * (y - yMean)
        }
        // Every point at the same instant: no spread on the x-axis to fit against.
        guard sumSquaredDeviationX > 0 else { return nil }

        let slope = sumCrossDeviation / sumSquaredDeviationX
        // The fitted line passes through (xMean, yMean); shift that back to x = 0,
        // i.e. `referenceDate`, which is what `Fit.value(at:)` measures from.
        let driftFractionAtReferenceDate = yMean - slope * xMean
        return Fit(
            referenceDate: referenceDate,
            slopePerSecond: slope,
            driftFractionAtReferenceDate: driftFractionAtReferenceDate
        )
    }

    /// The y-axis a chart should use, in drift-*fraction* units (a view multiplies by
    /// 100 to display percent, matching `SummaryTileData`'s convention) — the plotted
    /// points' own range, padded so no point or line sits flush against the frame edge.
    /// Nil when there is nothing to plot.
    public var driftFractionAxisDomain: ClosedRange<Double>? {
        guard var lower = points.first?.driftFraction else { return nil }
        var upper = lower
        for point in points {
            lower = Swift.min(lower, point.driftFraction)
            upper = Swift.max(upper, point.driftFraction)
        }
        guard lower < upper else {
            // One point, or every point at the same value: give the axis a fixed, sane
            // width around it rather than a zero-width range a chart cannot scale
            // against. ±2 percentage points is comfortably wider than sensor noise on a
            // single reading.
            return (lower - 0.02)...(upper + 0.02)
        }
        let pad = (upper - lower) * 0.2
        return (lower - pad)...(upper + pad)
    }
}
