import Foundation

/// One workout's heart-rate curve resampled onto the shared **0–100% elapsed** axis
/// (D5, FR-3.3) — the whole reason D7 keeps entire curves as a blob.
///
/// ## What 100% means, and why it is the curve's span rather than the workout's
///
/// `percentElapsed` is measured across the span the *heart-rate curve* covers — first
/// sample to last — not across `Workout.durationSeconds`. The two differ whenever the
/// sensor started late or dropped out at the end, and the difference is not cosmetic:
/// `DerivedMetrics.heartRateDriftFraction`, the number this overlay exists to make
/// visible, is defined by `HeartRateCurve.driftFraction` as first-half mean versus
/// second-half mean **of the covered span**. Normalising against the workout's duration
/// instead would put the 50% gridline somewhere other than the split the stored drift
/// figure was computed at, so the shape on screen and the number printed beside it would
/// be describing different windows. That is the D2 disagreement, drawn.
///
/// It also means this type never extrapolates. `HeartRateCurve` attributes nothing
/// outside its samples, and inventing the missing minute at either end to reach a
/// workout-duration axis would be inventing data.
///
/// ## Absent, not zero
///
/// `driftFraction` is `DerivedMetrics.heartRateDriftFraction` passed straight through
/// (D2, computed once at ingestion by MAX-012). Nothing here derives a drift figure from
/// `points` — the overlay may *state* the stored number, and if it also computed one the
/// two would sit on the same screen disagreeing. Nil means the run carries no stored
/// drift, which is a real state, never a zero.
public struct NormalizedHeartRateCurve: Hashable, Sendable, Identifiable {

    /// One resampled point: a percentage of the run elapsed, and the heart rate the
    /// modelled curve averaged over the bucket centred there.
    public struct Point: Hashable, Sendable {
        /// 0...100. Bucket midpoints, so the first point sits just after 0 and the last
        /// just before 100 — see `HeartRateDriftOverlayData.bucketCount`.
        public let percentElapsed: Double
        public let beatsPerMinute: Double

        public init(percentElapsed: Double, beatsPerMinute: Double) {
            self.percentElapsed = percentElapsed
            self.beatsPerMinute = beatsPerMinute
        }
    }

    public var id: UUID { workoutID }

    public let workoutID: UUID

    /// When the run started — what orders the stack and labels the legend.
    public let start: Date

    /// The classification the scorer stored on the immutable auto-score
    /// (`Score.actualClassification`, D8). Read, never re-derived: a second classifier
    /// here could disagree with the one the score was computed under.
    public let classification: WorkoutClassification

    /// `HeartRateDriftOverlayData.bucketCount` points, ascending by `percentElapsed`.
    public let points: [Point]

    /// Seconds the source curve covered — what 100% is worth for *this* run, and the
    /// figure that keeps "these two runs were 28 and 94 minutes long" recoverable from a
    /// chart that has deliberately erased the difference.
    public let coveredSeconds: Double

    /// `DerivedMetrics.heartRateDriftFraction`, verbatim. Never computed here.
    public let driftFraction: Double?

    /// 0 for the most recent run in the stack, 1 for the one before it, and so on. Drives
    /// the legibility ramp — see
    /// `HeartRateDriftOverlayData.contextOpacity(recencyRank:stackedCount:)`.
    public let recencyRank: Int

    public init(
        workoutID: UUID,
        start: Date,
        classification: WorkoutClassification,
        points: [Point],
        coveredSeconds: Double,
        driftFraction: Double?,
        recencyRank: Int
    ) {
        self.workoutID = workoutID
        self.start = start
        self.classification = classification
        self.points = points
        self.coveredSeconds = coveredSeconds
        self.driftFraction = driftFraction
        self.recencyRank = recencyRank
    }

    /// Zero for a curve with no points, which `HeartRateDriftOverlayData` never produces
    /// — every stacked curve covers a positive span by construction.
    public var minimumBPM: Double {
        points.reduce(points.first?.beatsPerMinute ?? 0) { Swift.min($0, $1.beatsPerMinute) }
    }

    public var maximumBPM: Double {
        points.reduce(points.first?.beatsPerMinute ?? 0) { Swift.max($0, $1.beatsPerMinute) }
    }

    /// The run that reads as "the one you are looking at" — the most recent stacked
    /// curve. Everything older is context behind it (see `contextOpacity`).
    public var isMostRecent: Bool { recencyRank == 0 }

    /// `driftFraction` as a signed percentage ("+3.1", "-2.4"), or nil when the run
    /// carries no stored drift. The same formatter the summary tiles use, so the number
    /// in this legend and the number on the detail screen are rounded identically.
    public var formattedDriftPercent: String? {
        driftFraction.map(SummaryTileData.formattedSignedPercent)
    }
}

/// The cross-run HR-drift overlay (FR-3.3, D5): several runs' heart-rate curves on one
/// chart, each normalised onto a 0–100% elapsed axis so a 28-minute run and a 94-minute
/// run can be compared by *shape*.
///
/// PRD §1 names this as the view no other app draws, and nearly all of it is resampling
/// decisions. Those decisions are made here, in `MaximizeCore`, where CI runs them; the
/// SwiftUI view receives normalised series and draws them.
///
/// ## The four normalisation decisions, stated
///
/// 1. **How many points a normalised curve has.** `bucketCount` (100 by default), the
///    same for every run in the stack. A shared point count is what makes the curves
///    comparable at all: two runs sampled at different densities become two curves in the
///    same shape vocabulary. It also bounds what the chart draws — thirty runs is 3,000
///    marks, not thirty raw series of wildly different lengths.
///
/// 2. **What happens between samples.** Nothing new: `HeartRateCurve` already states the
///    interpolation assumption once — the heart moved linearly between two samples — and
///    every seconds-valued metric in §9 rests on it. This type resamples *through*
///    `HeartRateCurve`, so the overlay cannot develop a second opinion about what the
///    curve did between two beats.
///
/// 3. **What happens when a series is sparse or irregular.** Each bucket carries the
///    **time-weighted mean** over its slice (`HeartRateCurve.timeWeightedMeanBPM`), not
///    the value sampled at a grid point. HealthKit sampling is not uniform, and point
///    sampling would make the drawn curve a function of when the sensor happened to fire:
///    a dense minute would pull the line toward that minute, and a spike falling between
///    two grid points would vanish entirely. Averaging by time makes each plotted value a
///    property of the run. It is also the averaging `driftFraction` itself uses, so the
///    shape and the stated figure rest on one notion of "the mean heart rate over this
///    stretch."
///
///    The known limitation is inherited rather than introduced: a sensor dropout is
///    modelled as a straight line across the gap, exactly as `HeartRateCurve` documents.
///    A bucket falling entirely inside a dropout therefore reports that interpolated
///    line, not an absence. If dropouts turn out to distort real runs, the fix is to
///    record them as gaps at ingestion — not to guess differently here.
///
/// 4. **What happens to a run far shorter than the others.** It is excluded, and said so.
///    Stretching a six-minute jog across the same width as a 94-minute long run does not
///    make the two comparable; it makes the short one *look* like a long one. At that
///    length a single bucket spans a couple of seconds, which is inside sensor noise, so
///    the "shape" being compared is noise magnified to full width. The floor is derived
///    from the resolution rather than picked separately: a curve must cover at least
///    `minimumBucketSeconds` (5 s, roughly the wrist sensor's own cadence during a
///    workout) per bucket, so 100 buckets require 500 s — 8m 20s — of heart-rate data.
///    Below that this type declines to resample finer than the sensor sampled.
///
/// ## Curves may be missing, and that is ordinary
///
/// A run captured before MAX-034 has no stored series at all; a run ingested minutes ago
/// has no stored classification yet; a treadmill run has no route but does have HR and is
/// as first-class here as any outdoor run (FR-0.6 — nothing in this type reads
/// `Workout.hasRoute`). Every run the interval contains and the overlay does not draw
/// appears in `excluded` with a reason, and `exclusionNotes` turns those into sentences.
/// None of them is drawn as a flat line at zero.
public struct HeartRateDriftOverlayData: Hashable, Sendable {

    // MARK: - Resolution

    /// Points per normalised curve, unless a caller says otherwise. See decision 1.
    ///
    /// 100 buckets puts each plotted value across 1% of the run: ~17 s on a 28-minute run,
    /// ~56 s on a 94-minute one. Fine enough that a warm-up, a climb and a fade stay
    /// legible; coarse enough that the line reads as a trend rather than beat-to-beat
    /// jitter, which is what a *drift-shape* comparison wants. The single-run chart
    /// (`HeartRateChartData`, FR-1.2) remains where a curve is seen unresampled.
    public static let defaultBucketCount = 100

    /// The shortest slice this type will average over. See decision 4.
    public static let minimumBucketSeconds: Double = 5

    /// How many curves are stacked before legibility, rather than data, becomes the
    /// binding constraint.
    ///
    /// Twelve is a judgement, and it is the one most worth arguing with: past roughly a
    /// dozen lines in one plot area the eye stops reading individual curves and starts
    /// reading a texture. The overlay therefore stacks the twelve most recent qualifying
    /// runs and *states* how many it left out, rather than drawing thirty and calling the
    /// result a chart. FR-3.3's "selectable which runs are stacked" is what reaches the
    /// rest: hiding a recent run promotes the next-oldest into the stack.
    public static let defaultStackLimit = 12

    /// The x-axis every normalised curve shares. Fixed, not derived from the data — a
    /// percentage axis ranging over "whatever these particular runs covered" would stop
    /// being a percentage axis.
    public static let percentElapsedDomain: ClosedRange<Double> = 0...100

    // MARK: - Input

    /// One run offered to the overlay, with everything the inclusion decision needs.
    ///
    /// Assembled by the caller from records that already exist — nothing here is computed.
    /// The overlay decides what to do with each candidate; the caller does not pre-filter,
    /// so *why* a run is missing from the chart stays visible instead of being dropped
    /// silently one layer up.
    public struct Candidate: Hashable, Sendable {
        public let workout: Workout

        /// `WorkoutRepository.heartRateSeries(forWorkout:)`. Nil is ordinary — see the
        /// type documentation.
        public let series: HeartRateSeries?

        /// `Score.actualClassification` from the stored auto-score (D8). Nil for a run
        /// that has not been scored yet, which is a different state from "was not an easy
        /// or long run" and is reported as one.
        public let classification: WorkoutClassification?

        /// The run's `DerivedMetrics` (D2 — read, never recomputed). Only
        /// `heartRateDriftFraction` is read from it.
        public let metrics: DerivedMetrics?

        public init(
            workout: Workout,
            series: HeartRateSeries?,
            classification: WorkoutClassification?,
            metrics: DerivedMetrics?
        ) {
            self.workout = workout
            self.series = series
            self.classification = classification
            self.metrics = metrics
        }
    }

    // MARK: - Exclusions

    /// Why a run in the selected interval is not one of the curves on screen.
    ///
    /// Ordered as the checks are applied. Every case is a state a real athlete's history
    /// contains; none of them is an error.
    public enum ExclusionReason: String, Hashable, Sendable, CaseIterable {
        /// The athlete un-stacked it (FR-3.3's "selectable which runs are stacked").
        case hiddenByAthlete

        /// No auto-score yet, so nothing has decided what this run was. Classifying it
        /// here would be a second classifier, free to disagree with the one the score is
        /// eventually computed under.
        case notYetScored

        /// A hard or other session. §9 calls drift "near-meaningless" on those, and D5
        /// filters the overlay to easy and long runs for exactly that reason.
        case driftNotMeaningfulForThisSession

        /// No stored heart-rate curve — a run captured before MAX-034, or one the sensor
        /// produced nothing for.
        case noHeartRateSeries

        /// The curve covers less than `minimumCoveredSeconds`. See decision 4.
        case curveTooShortToNormalize

        /// Qualified in every respect, but older than the `stackLimit` most recent runs.
        case beyondStackLimit
    }

    /// A run the interval contains and the chart does not draw.
    public struct ExcludedRun: Hashable, Sendable, Identifiable {
        public var id: UUID { workoutID }
        public let workoutID: UUID
        public let start: Date
        public let reason: ExclusionReason

        public init(workoutID: UUID, start: Date, reason: ExclusionReason) {
            self.workoutID = workoutID
            self.start = start
            self.reason = reason
        }
    }

    // MARK: - Output

    /// The stacked curves, **oldest first** so a chart drawing them in order paints the
    /// most recent one last, and therefore on top. `recencyRank` carries the other
    /// ordering.
    public let curves: [NormalizedHeartRateCurve]

    /// Every run not drawn, most recent first.
    public let excluded: [ExcludedRun]

    /// How many runs the interval contained in total — the denominator for "12 of 30".
    public let candidateCount: Int

    /// Points per normalised curve in *this* overlay.
    public let bucketCount: Int

    /// The y-axis range a chart should use: the stacked curves' own bounds, padded so no
    /// line is drawn flush against the frame edge. Nil when nothing is stacked — the
    /// state with no chart to draw at all, rather than an empty one.
    public let bpmAxisDomain: ClosedRange<Double>?

    /// - Parameters:
    ///   - candidates: every workout that started in the selected interval, in any order.
    ///   - hiddenWorkoutIDs: runs the athlete has un-stacked (FR-3.3).
    ///   - stackLimit: how many curves to draw at most. Defaults to `defaultStackLimit`.
    ///   - bucketCount: points per normalised curve. Defaults to `defaultBucketCount`; a
    ///     parameter so tests can pin the arithmetic at a hand-checkable resolution.
    public init(
        candidates: [Candidate],
        hiddenWorkoutIDs: Set<UUID> = [],
        stackLimit: Int = HeartRateDriftOverlayData.defaultStackLimit,
        bucketCount: Int = HeartRateDriftOverlayData.defaultBucketCount
    ) {
        let buckets = Swift.max(bucketCount, 1)
        let limit = Swift.max(stackLimit, 0)
        let floorSeconds = Double(buckets) * Self.minimumBucketSeconds

        self.candidateCount = candidates.count
        self.bucketCount = buckets

        // Most recent first throughout. Ties on `start` break on the identifier so two
        // runs recorded at the same instant always stack in the same order — a chart that
        // reshuffled itself between two reads of one interval would be its own bug.
        let ordered = candidates.sorted {
            $0.workout.start == $1.workout.start
                ? $0.workout.id.uuidString > $1.workout.id.uuidString
                : $0.workout.start > $1.workout.start
        }

        var qualifying: [Resampled] = []
        var excluded: [ExcludedRun] = []

        for candidate in ordered {
            let workout = candidate.workout

            func exclude(_ reason: ExclusionReason) {
                excluded.append(ExcludedRun(workoutID: workout.id, start: workout.start, reason: reason))
            }

            guard !hiddenWorkoutIDs.contains(workout.id) else {
                exclude(.hiddenByAthlete)
                continue
            }
            guard let classification = candidate.classification else {
                exclude(.notYetScored)
                continue
            }
            // D5's filter, expressed through the rule §9 already encodes once rather than
            // through a fresh list of cases here.
            guard classification.driftIsMeaningful else {
                exclude(.driftNotMeaningfulForThisSession)
                continue
            }
            guard let series = candidate.series else {
                exclude(.noHeartRateSeries)
                continue
            }
            let curve = HeartRateCurve(series)
            // A single-sample series covers zero seconds and lands here too, which is the
            // right answer: there is no shape to normalise.
            guard curve.coveredSeconds >= floorSeconds else {
                exclude(.curveTooShortToNormalize)
                continue
            }

            qualifying.append(
                Resampled(
                    workout: workout,
                    classification: classification,
                    driftFraction: candidate.metrics?.heartRateDriftFraction,
                    points: curve.resampledOntoPercentElapsed(bucketCount: buckets),
                    coveredSeconds: curve.coveredSeconds
                )
            )
        }

        for entry in qualifying.dropFirst(limit) {
            excluded.append(
                ExcludedRun(workoutID: entry.workout.id, start: entry.workout.start, reason: .beyondStackLimit)
            )
        }

        // Ranks are assigned newest-first; the array is then reversed so drawing it in
        // order paints the most recent curve on top of its own history.
        var ranked: [NormalizedHeartRateCurve] = []
        for (rank, entry) in qualifying.prefix(limit).enumerated() {
            ranked.append(
                NormalizedHeartRateCurve(
                    workoutID: entry.workout.id,
                    start: entry.workout.start,
                    classification: entry.classification,
                    points: entry.points,
                    coveredSeconds: entry.coveredSeconds,
                    driftFraction: entry.driftFraction,
                    recencyRank: rank
                )
            )
        }

        self.curves = Array(ranked.reversed())
        self.excluded = excluded.sorted { $0.start > $1.start }
        self.bpmAxisDomain = Self.bpmAxisDomain(for: ranked)
    }

    /// A qualifying run, resampled but not yet ranked. Local to the initializer's
    /// two-pass shape: rank depends on how many runs qualify, which is not known until
    /// every candidate has been examined.
    private struct Resampled {
        let workout: Workout
        let classification: WorkoutClassification
        let driftFraction: Double?
        let points: [NormalizedHeartRateCurve.Point]
        let coveredSeconds: Double
    }

    /// True when there is nothing to draw — every run in the interval was excluded, or
    /// the interval held no runs at all.
    public var isEmpty: Bool { curves.isEmpty }

    /// The floor decision 4 applies, at this overlay's resolution.
    public var minimumCoveredSeconds: Double {
        Double(bucketCount) * Self.minimumBucketSeconds
    }

    /// "9 of 14 runs stacked" — the caption under the chart. Here rather than in the view
    /// for the same reason `exclusionNotes` is: it is counting and agreement, and CI is
    /// what exercises those.
    public var stackSummary: String {
        "\(curves.count) of \(candidateCount) \(candidateCount == 1 ? "run" : "runs") stacked"
    }

    /// How many runs were excluded for this reason.
    public func count(of reason: ExclusionReason) -> Int {
        excluded.reduce(0) { $0 + ($1.reason == reason ? 1 : 0) }
    }

    private static func bpmAxisDomain(for curves: [NormalizedHeartRateCurve]) -> ClosedRange<Double>? {
        guard let first = curves.first?.points.first?.beatsPerMinute else { return nil }
        var lower = first
        var upper = first
        for curve in curves {
            lower = Swift.min(lower, curve.minimumBPM)
            upper = Swift.max(upper, curve.maximumBPM)
        }
        guard lower < upper else {
            // Every stacked curve is one flat value: give the axis a usable width rather
            // than a zero-height range a chart cannot scale against.
            return (lower - 5)...(upper + 5)
        }
        let pad = (upper - lower) * 0.08
        return (lower - pad)...(upper + pad)
    }

    // MARK: - Legibility with N curves

    /// How strongly a context curve should be drawn, given how far back it sits in the
    /// stack. 1 is full strength; the ramp floors well above invisible.
    ///
    /// **This is half the answer to "what happens with thirty curves"** — the stack limit
    /// is the other half. This ramp keeps the curves that are drawn from reading as an
    /// undifferentiated tangle by making recency the visual axis: the most recent run is
    /// drawn at full strength, and its history recedes behind it.
    ///
    /// The alternative — N distinguishable hues — was rejected deliberately. FR-4.3
    /// spends this app's entire saturated-colour budget on the accent and the three score
    /// bands, and `ScoreBandColors.swift` reserves those three for the calendar and the
    /// verdict header; a twelve-colour categorical palette here would break that and
    /// would be unreadable at twelve anyway.
    ///
    /// Arithmetic rather than a view detail because it *is* arithmetic, and arithmetic is
    /// what CI verifies in this repo.
    ///
    /// - Parameters:
    ///   - recencyRank: 0 for the most recent stacked curve.
    ///   - stackedCount: how many curves are in the stack.
    public static func contextOpacity(recencyRank: Int, stackedCount: Int) -> Double {
        guard recencyRank > 0 else { return 1 }
        let oldestRank = Swift.max(stackedCount - 1, 1)
        guard oldestRank > 1 else { return newestContextOpacity }
        let position = Double(Swift.min(recencyRank, oldestRank) - 1) / Double(oldestRank - 1)
        return newestContextOpacity + position * (oldestContextOpacity - newestContextOpacity)
    }

    /// The run immediately before the most recent one. Close to full strength: with two
    /// curves stacked, that comparison *is* the chart.
    public static let newestContextOpacity = 0.75

    /// The oldest curve in a full stack. Faint, but deliberately not near-invisible — it
    /// is the "before" in a before-and-after, and FR-3.3 is about watching drift flatten
    /// across an interval, which needs the far end of the interval to stay legible.
    ///
    /// **MAX-084: was 0.28, and the comment above was not true of it.** Composited over
    /// `surfaceInset` that measured 1.25:1 in dark, on a 1pt stroke — near-invisible by
    /// any reading. 0.45 against the raised `chartSeriesMuted` takes it to 1.60:1, and
    /// the whole ramp with it.
    ///
    /// Not raised further, for two reasons worth stating. The ramp spans
    /// `newestContextOpacity` down to here, so every point spent on the floor is a
    /// point of recency encoding given up — 0.75→0.45 is already a narrower span than
    /// 0.75→0.28 was, and recency is the only axis separating twelve otherwise
    /// identical lines. And **the residual problem is the 1pt stroke, not the colour**:
    /// `DriftOverlayView` draws context curves at 1pt against the primary's 2pt, and at
    /// 1.60:1 a hairline is still a hairline. Thickening it is the change that would
    /// help most and the one arithmetic cannot adjudicate — twelve overlapping strokes
    /// behave differently from one, and only a device can say whether the result reads
    /// as history or as a tangle. Left for a ticket that can look at it.
    public static let oldestContextOpacity = 0.45

    // MARK: - Saying what is missing

    /// One sentence per kind of omission, for a view to print under the chart.
    ///
    /// Built here rather than in the view for the reason every other formatter in this
    /// module is: it is counting and pluralisation, and CI exercises it. Runs the athlete
    /// hid themselves are deliberately not narrated — the legend already shows them
    /// switched off, and a note explaining the athlete's own tap is noise.
    public var exclusionNotes: [String] {
        var notes: [String] = []

        let unscored = count(of: .notYetScored)
        if unscored > 0 {
            notes.append(
                unscored == 1
                    ? "1 run isn't scored yet, so nothing has decided whether it was an easy or long run."
                    : "\(unscored) runs aren't scored yet, so nothing has decided whether they were easy or long runs."
            )
        }

        let notMeaningful = count(of: .driftNotMeaningfulForThisSession)
        if notMeaningful > 0 {
            notes.append(
                notMeaningful == 1
                    ? "1 hard or other session isn't stacked — drift is near-meaningless on those."
                    : "\(notMeaningful) hard or other sessions aren't stacked — drift is near-meaningless on those."
            )
        }

        let noSeries = count(of: .noHeartRateSeries)
        if noSeries > 0 {
            notes.append(
                noSeries == 1
                    ? "1 run has no stored heart-rate curve."
                    : "\(noSeries) runs have no stored heart-rate curve."
            )
        }

        let tooShort = count(of: .curveTooShortToNormalize)
        if tooShort > 0 {
            let span = HeartRateChartData.formattedDuration(seconds: minimumCoveredSeconds)
            notes.append(
                tooShort == 1
                    ? "1 run has too little heart-rate data to normalise (under \(span))."
                    : "\(tooShort) runs have too little heart-rate data to normalise (under \(span))."
            )
        }

        let beyondLimit = count(of: .beyondStackLimit)
        if beyondLimit > 0 {
            notes.append(
                beyondLimit == 1
                    ? "1 older qualifying run isn't stacked, for legibility. Un-stack a recent run to bring it forward."
                    : "\(beyondLimit) older qualifying runs aren't stacked, for legibility. "
                        + "Un-stack a recent run to bring one forward."
            )
        }

        return notes
    }
}

// MARK: - The resampling itself

extension HeartRateCurve {
    /// The curve as `bucketCount` time-weighted means, laid out on a 0–100% axis.
    ///
    /// Each bucket is `coveredSeconds / bucketCount` long and carries the mean heart rate
    /// **over that slice**, plotted at the slice's midpoint. See
    /// `HeartRateDriftOverlayData`'s decisions 1–3 for why a mean rather than a sample,
    /// and why the span is the curve's own rather than the workout's.
    ///
    /// A curve with no span has no shape to resample and yields no points, rather than a
    /// fabricated flat line.
    func resampledOntoPercentElapsed(bucketCount: Int) -> [NormalizedHeartRateCurve.Point] {
        guard bucketCount > 0, coveredSeconds > 0 else { return [] }

        var points: [NormalizedHeartRateCurve.Point] = []
        points.reserveCapacity(bucketCount)
        for index in 0..<bucketCount {
            let lower = startOffsetSeconds + coveredSeconds * Double(index) / Double(bucketCount)
            let upper = startOffsetSeconds + coveredSeconds * Double(index + 1) / Double(bucketCount)
            // Nil only for a bucket with no duration, which a positive span and a positive
            // bucket count rule out. Skipped rather than filled with a fabricated value if
            // floating-point arithmetic ever produces one anyway.
            guard let mean = timeWeightedMeanBPM(from: lower, to: upper) else { continue }
            let midpoint = (Double(index) + 0.5) / Double(bucketCount) * 100
            points.append(NormalizedHeartRateCurve.Point(percentElapsed: midpoint, beatsPerMinute: mean))
        }
        return points
    }
}
