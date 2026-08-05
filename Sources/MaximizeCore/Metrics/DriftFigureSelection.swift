import Foundation

/// Every run in a long interval whose **stored** drift figure belongs on a trendline
/// (MAX-083, FR-3.3, D5) — the year span's drift section, where no curve is drawn.
///
/// ## Why this exists rather than reusing the overlay's filter
///
/// `HeartRateDriftOverlayData` answers "which runs can I draw the *shape* of, side by
/// side", and `HeartRateDriftTrendlineData` is deliberately built from its output so the
/// two halves of the week and month view cover exactly the same runs (see that type's own
/// documentation — reimplementing the filter would let a legend and a line describe
/// different sets).
///
/// At a year there is no shape to draw, and the overlay's filter would be answering the
/// wrong question:
///
/// - **"Is the curve long enough to resample onto 100 buckets?"** is a rule about drawing
///   a shape at a readable resolution. A 7-minute easy run carries a perfectly good
///   stored drift figure, computed once at ingestion by MAX-012 under its own rules; it
///   contributes one honest point to a trendline. Excluding it here would drop real data
///   to satisfy a constraint that only exists for a chart this span does not show.
/// - **The stack limit of 12** exists so a dozen lines do not become a texture. A
///   trendline over 200 points is not a texture; it is the case the fit was waiting for.
///
/// So the eligibility rules here are the ones that are genuinely about the *number*:
/// something must have classified the run (D8's stored auto-score, never a second
/// classifier), that classification must be one drift means anything on (§9), and the run
/// must actually carry a stored figure. Two of those three are shared verbatim with the
/// overlay, through the same `WorkoutClassification.driftIsMeaningful` rule rather than a
/// fresh list of cases.
///
/// **This does not reintroduce the disagreement MAX-065 avoided**, because the two never
/// appear together: `DriftSectionRepresentation` shows the overlay-led section at a week
/// and a month, and this one at a year. There is no screen on which a legend built from
/// one and a line built from the other could contradict each other.
///
/// ## What it costs to load
///
/// A `Candidate` here carries no `HeartRateSeries`. That is the point: the overlay-led
/// path reads one stored heart-rate blob per run in the interval (by design — it does not
/// pre-filter, so exclusion reasons stay in one tested place), which at a year is ~200
/// multi-kilobyte reads for a chart that will not be shown. This path reads one small
/// scalar per run instead. See `DriftSectionRepresentation.loadsStoredHeartRateCurves`.
public struct DriftFigureSelection: Hashable, Sendable {

    /// One run offered to the trendline, with everything the inclusion decision needs and
    /// nothing else. Assembled by the caller from records that already exist; nothing here
    /// is computed.
    public struct Candidate: Hashable, Sendable {
        public let workoutID: UUID

        /// The run's start — what the point is plotted against, and how the selection is
        /// ordered.
        public let start: Date

        /// `Score.actualClassification` from the stored auto-score (D8). Nil for a run
        /// that has not been scored yet, which is a different state from "was not an easy
        /// or long run" and is reported as one.
        public let classification: WorkoutClassification?

        /// `DerivedMetrics.heartRateDriftFraction`, verbatim (D2). Never derived here or
        /// anywhere upstream of this type.
        public let driftFraction: Double?

        public init(
            workoutID: UUID,
            start: Date,
            classification: WorkoutClassification?,
            driftFraction: Double?
        ) {
            self.workoutID = workoutID
            self.start = start
            self.classification = classification
            self.driftFraction = driftFraction
        }
    }

    /// Why a run in the interval contributes no point. Ordered as the checks are applied;
    /// every case is an ordinary state, none is an error.
    public enum ExclusionReason: String, Hashable, Sendable, CaseIterable {
        /// No auto-score yet, so nothing has decided what this run was. Classifying it
        /// here would be a second classifier, free to disagree with the one the score is
        /// eventually computed under.
        case notYetScored

        /// A hard or other session. §9 calls drift "near-meaningless" on those, and D5
        /// filters the drift comparison to easy and long runs for exactly that reason.
        case driftNotMeaningfulForThisSession

        /// Qualifies in every other respect but carries no stored
        /// `heartRateDriftFraction` — a run with no heart-rate series, or one ingested
        /// before MAX-012 computed the figure. Never plotted as a zero.
        case noStoredDriftFigure
    }

    /// How many runs the interval contained in total — the denominator for "184 of 212".
    public let candidateCount: Int

    /// How many runs each reason accounts for. Absent keys are zero.
    public let exclusionCounts: [ExclusionReason: Int]

    /// The trendline over the qualifying runs, ascending by date. Built through
    /// `HeartRateDriftTrendlineData` rather than fitting a second line here, so the year
    /// span and the shorter spans share one notion of what a drift trend is.
    public let trendline: HeartRateDriftTrendlineData

    /// - Parameter candidates: every workout that started in the selected interval, in any
    ///   order. The caller does not pre-filter — the reason a run is missing is decided
    ///   here, in one tested place, rather than half here and half in a repository query.
    public init(candidates: [Candidate]) {
        var points: [HeartRateDriftTrendlineData.Point] = []
        var counts: [ExclusionReason: Int] = [:]

        for candidate in candidates {
            guard let classification = candidate.classification else {
                counts[.notYetScored, default: 0] += 1
                continue
            }
            guard classification.driftIsMeaningful else {
                counts[.driftNotMeaningfulForThisSession, default: 0] += 1
                continue
            }
            guard let driftFraction = candidate.driftFraction else {
                counts[.noStoredDriftFigure, default: 0] += 1
                continue
            }
            points.append(
                HeartRateDriftTrendlineData.Point(
                    workoutID: candidate.workoutID,
                    date: candidate.start,
                    driftFraction: driftFraction
                )
            )
        }

        self.candidateCount = candidates.count
        self.exclusionCounts = counts
        self.trendline = HeartRateDriftTrendlineData(points: points)
    }

    /// How many runs were excluded for this reason.
    public func count(of reason: ExclusionReason) -> Int {
        exclusionCounts[reason] ?? 0
    }

    /// True when no run in the interval contributes a point — the state with no chart to
    /// draw at all, rather than an empty one.
    public var isEmpty: Bool { trendline.points.isEmpty }

    /// "184 of 212 runs plotted" — the caption under the chart. Here rather than in the
    /// view for the reason `HeartRateDriftOverlayData.stackSummary` is: it is counting and
    /// pluralisation, and CI is what exercises those.
    public var summary: String {
        let plotted = trendline.points.count
        return "\(plotted) of \(candidateCount) \(candidateCount == 1 ? "run" : "runs") plotted"
    }

    /// What the view prints in place of a chart when nothing qualified — the year span's
    /// own version of `HeartRateDriftOverlayData.emptyStateText`, worded for what this
    /// type actually withholds (a stored figure, not a curve to normalise).
    ///
    /// Moved here from `DriftOverlayView` (MAX-150) for the same reason
    /// `HeartRateDriftOverlayData.emptyStateText` was: a data-dependent branch that used
    /// to be hand-typed in the view, beside an identical-looking sentence for a
    /// different type a few lines away.
    public var emptyStateText: String {
        candidateCount == 0
            ? "No runs in this interval."
            : "No run in this interval carries a stored drift figure."
    }

    /// One sentence per kind of omission, for a view to print under the chart. Mirrors
    /// `HeartRateDriftOverlayData.exclusionNotes`, minus the reasons that only exist
    /// because a shape is being drawn.
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
                    ? "1 hard or other session isn't plotted — drift is near-meaningless on those."
                    : "\(notMeaningful) hard or other sessions aren't plotted — drift is near-meaningless on those."
            )
        }

        let noFigure = count(of: .noStoredDriftFigure)
        if noFigure > 0 {
            notes.append(
                noFigure == 1
                    ? "1 run carries no stored drift figure."
                    : "\(noFigure) runs carry no stored drift figure."
            )
        }

        return notes
    }
}
