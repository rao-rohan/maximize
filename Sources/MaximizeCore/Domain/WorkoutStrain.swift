import Foundation

/// What one workout **cost**: a zone-weighted integral of its heart-rate curve
/// (HELIX-COMPETITIVE-READ §9, MAX-176).
///
/// ## Why this exists beside the score
///
/// Everything else the app measures answers *did you execute the ask* — time above the
/// cap, drift, cadence against the band, and the score that reads them. None of them
/// answers *what did it take out of you*, and the two questions come apart constantly: a
/// disciplined easy hour and a disciplined easy three hours score the same and cost
/// wildly different amounts. This is the second question, and only that one. It is not a
/// verdict, it is not compared against a prescription, and no rubric band references it —
/// deliberately, because a plan that scored strain would be scoring the athlete for how
/// hard their heart worked rather than for doing what was asked.
///
/// ## The weighting: Edwards' summated heart-rate zone score
///
/// Each zone's weight is its own ordinal — zone 1 counts once, zone 5 counts five times —
/// and the figure is the time in each zone multiplied by that weight. That is Edwards'
/// model (*The Heart Rate Monitor Book*, 1993), the summated-zone score that most
/// consumer "training load" figures descend from. It is chosen over the alternatives for
/// reasons stated here rather than left as a curve someone picked:
///
/// - **It uses the distribution the record already carries.** `DerivedMetrics.zoneSplits`
///   is produced by splitting the piecewise-linear curve at every boundary it crosses, so
///   `Σ weight(z) · seconds(z)` *is* `∫ weight(HR(t)) dt` exactly — not an approximation
///   of it. Reading the same value the zone chart draws means the tile and the chart
///   cannot disagree about what the run was, which is the drift D2 exists to prevent.
/// - **The weights are ordinals, so there is no third opinion to version.** The one
///   modelling choice is where the zones sit, and that is already made once, in
///   `HeartRateZoneModel`, anchored to the plan's HR cap (D1). Strain inherits it rather
///   than introducing a second set of thresholds.
/// - **Linear weights are not as blunt as they look**, because the bands are not equally
///   wide. Cap-anchored, they are ≤0.90×, ≤1.00×, ≤1.08×, ≤1.16× of the cap and then
///   open: 15 bpm buys the step from weight 2 to weight 3, then 12 bpm each for the next
///   two. The response to *heart rate* is therefore already convex above the cap, which
///   is the shape a steeper weighting would have been reaching for.
///
/// **What was rejected.** A bounded 0–21 scale (Whoop's, and Helix's copy of it) needs a
/// personal ceiling to anchor the top: a rolling maximum, or a heart-rate reserve
/// computed from resting and maximum HR. This app ingests no daily health data — that is
/// a second ingestion path the competitive read declined (proposed A27) — and holds
/// neither the athlete's age nor their resting HR, so the ceiling would be an arbitrary
/// constant, permanently invisible inside every stored number. Banister's TRIMP
/// (`duration · ΔHR-fraction · e^(b·ΔHR-fraction)`) is rejected for the same missing
/// inputs plus a sex-specific constant. A continuous weighting of `HR / cap` was rejected
/// as a curve this repository would be inventing, and as a *second* reading of the curve
/// that could disagree with the zone splits beside it.
///
/// ## The unit, which is permanent once stored
///
/// **Points, where one point is one minute spent in zone 1** — equivalently,
/// zone-weighted minutes. **Unbounded above**, and the scale has no ceiling to be near:
/// a bigger number is a longer session, a harder one, or both, and it deliberately
/// cannot tell those apart. `zoneSplits` is what says which it was, and any surface
/// showing strain should be able to reach that.
///
/// Two anchors worth carrying in the head, both exact under the cap-anchored zones:
///
/// - an hour held just under the cap — a textbook easy run — is **120 points**;
/// - an hour of the same curve rising 120 → 180 bpm under a 150 bpm cap is **159 points**.
///
/// ## What a lift's strain is, and is not
///
/// **A lift's strain is heart-rate only.** HealthKit carries no load: no sets, no reps,
/// no weight, for a strength workout (A20, which decided not to ask the athlete to type
/// them). So a lifting session's strain is the cardiovascular cost of the hour, and
/// nothing else — it does not know whether the athlete moved a heavy bar four times or a
/// light one forty, and two sessions with the same heart-rate curve have the same strain
/// whatever was on the bar. It is comparable with a run's strain only to the extent that
/// heart rate is comparable between the two, and the zone boundaries it is cut against
/// are anchored to the plan's *run* cap (tracker gap P2, already true of `zoneSplits`
/// and made no worse here). **A later ticket must not read this figure as a measure of
/// how hard a lift was in the lifting sense. It cannot be one.**
///
/// ## Absence
///
/// A workout with no heart-rate curve has **no strain** — nil, never zero — because the
/// integral has nothing to integrate and a zero would read as "this cost nothing" (A18,
/// and MAX-175's invariant). `DerivedMetrics` enforces that as a cross-field check.
///
/// A curve that exists but covers no span — a single sample — is a different fact and
/// gets `0`: there is a measurement, it truthfully covers zero seconds, and that is the
/// same reading `timeAboveCapSeconds` already takes of the same case. **Note the pairing
/// it produces, because a surface showing both figures will meet it**: such a workout has
/// a strain of `0` and *empty* zone splits, so `isRecorded(.strain)` is true while
/// `isRecorded(.zoneSplits)` is false. Those are not two answers in tension — they are one
/// fact, "measured, and containing nothing" — and a view must not draw them as a
/// contradiction.
///
/// ## What the span is, and what it therefore includes
///
/// Time is attributed only between the first and last sample (`HeartRateCurve` documents
/// why it never extrapolates), so a strap that joined a run late contributes strain for
/// the stretch it saw and nothing for the stretch it did not.
///
/// Within that span, **everything counts, including time the athlete was not training**: a
/// pause at a level crossing, a long stop mid-run, and a sensor dropout are all
/// interpolated across and weighted like any other stretch. So forty minutes of running
/// either side of a twenty-minute stop costs about what a clean easy hour costs. This is a
/// stated limitation rather than an oversight, and it is deliberate on two grounds: it is
/// the same reading every other seconds-valued figure in the record already takes —
/// `timeAboveCapSeconds` and `zoneSplits` are cut over exactly this span — and correcting
/// for it would mean scaling the integral by `durationSeconds / coveredSeconds`, which
/// invents a distribution the curve does not contain and breaks the exact identity with
/// `zoneSplits` that keeps the two figures from ever disagreeing. (`averageCadence`
/// divides by active duration instead, and can, because it is a rate rather than an
/// integral.) If paused sessions turn out to distort real numbers, the fix is to record
/// the pauses as gaps at ingestion — the same fix `HeartRateCurve` names for dropouts —
/// not to rescale here.
public struct WorkoutStrain: Hashable, Sendable, Codable, Comparable {
    /// Zone-weighted minutes. Non-negative and finite; unbounded above.
    public let points: Double

    public init(points: Double) throws {
        try Validate.nonNegative(points, "WorkoutStrain.points")
        self.points = points
    }

    /// Edwards' weight for a zone: the zone's own ordinal.
    ///
    /// Derived from `rawValue` rather than written as a table because the two would be
    /// the same five numbers, and a table is a thing that can fall out of step with the
    /// zone it names. If a future weighting is ever *not* the ordinal, it stops being
    /// Edwards' model and belongs in a plan version (D1), not here.
    public static func weight(for zone: HeartRateZone) -> Double {
        Double(zone.rawValue)
    }

    /// The integral, taken over the distribution the record already carries.
    ///
    /// `ZoneSplits` reads an absent zone as zero seconds, so a run that never left zone 2
    /// contributes exactly what it should. Empty splits give zero points — see the type
    /// documentation for why that is a real answer for a curve with no span and why it is
    /// *not* the answer for a workout with no curve, which never reaches this initializer.
    public init(zoneSplits: ZoneSplits) throws {
        let weightedSeconds = zoneSplits.splits.reduce(0.0) { total, split in
            total + WorkoutStrain.weight(for: split.zone) * split.seconds
        }
        try self.init(points: weightedSeconds / 60)
    }

    public static func < (lhs: WorkoutStrain, rhs: WorkoutStrain) -> Bool {
        lhs.points < rhs.points
    }

    /// Encoded as a bare number rather than as `{"points": …}`: it is one figure, it is
    /// stored as one column (`StoredDerivedMetrics.strainPoints`), and a wrapper object
    /// in the JSON would be a second shape for the same value. Same choice, for the same
    /// reason, as `ScoreValue`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(points: container.decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }
}
