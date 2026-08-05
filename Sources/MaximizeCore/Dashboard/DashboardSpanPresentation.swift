import Foundation

/// **What each dashboard surface becomes at each span** (MAX-083).
///
/// This file is the whole answer to "a year is not a month with more cells", and it is
/// deliberately one table rather than three `if interval.kind == .year` branches spread
/// across three views. Each decision below is logic — it changes what is measured and
/// how it is arranged — so it lives in `MaximizeCore` where CI runs it, per CLAUDE.md.
/// The views read these values and render; they choose nothing.
///
/// | surface | week | month | year |
/// |---|---|---|---|
/// | calendar (FR-3.2) | dated day grid | dated day grid | weekday × week heatmap |
/// | HR drift (FR-3.3) | curve overlay, trendline beneath | curve overlay, trendline beneath | trendline alone |
/// | tiles (FR-3.4) | mileage vs arc, effective days, streak, avg | + days run | totals and rates, no arc |
///
/// The reasoning for each row sits on the enum it produces. Two properties are shared
/// by all three and worth stating once here:
///
/// **Density stays roughly constant as the span grows.** A week draws 7 marks, a month
/// 28–31, a year 365 — but the year's marks are an order of magnitude smaller and carry
/// no text, so the ink per screen is comparable. What changes is what a mark *is for*:
/// at a week you read individual days, at a year you read the texture and the gaps.
///
/// **What gets loaded changes with the span, not just what gets drawn.** The year is the
/// only span where that matters, and it matters a lot: see
/// `DriftSectionRepresentation.loadsStoredHeartRateCurves`.
extension TrendIntervalKind {
    /// How the score-coloured calendar is arranged at this span.
    public var scoreCalendarRepresentation: ScoreCalendarRepresentation {
        switch self {
        case .week, .month: return .dayGrid
        case .year: return .weekColumnHeatmap
        }
    }

    /// What the HR-drift section is at this span.
    public var driftSectionRepresentation: DriftSectionRepresentation {
        switch self {
        case .week, .month: return .curveOverlayLed
        case .year: return .trendlineOnly
        }
    }

    /// Which figures the summary tiles measure at this span.
    public var trendTileSet: TrendTileSet {
        switch self {
        case .week: return .weekly
        case .month: return .monthly
        case .year: return .annual
        }
    }
}

/// How the score-coloured calendar (FR-3.2, D4) is arranged for a span.
///
/// See `ScoreCalendarLayout` for the arrangement itself; this names the choice.
public enum ScoreCalendarRepresentation: Hashable, Sendable, CaseIterable {
    /// One cell per day in a Monday-first, seven-column grid, each cell carrying its
    /// date, its state glyph and its band fill. 7 cells at a week, 28–31 at a month.
    ///
    /// This is MAX-061's calendar unchanged, and it is right for both spans: at a month
    /// a cell is large enough to hold a two-digit date and an SF Symbol, which is what
    /// keeps colour from being the only channel (a `.missed` day and an
    /// `.ineffective` day share a fill and never a glyph).
    case dayGrid

    /// One small mark per day, laid out as **seven weekday rows by ~53 training-week
    /// columns** — the contribution-graph arrangement, Monday-first.
    ///
    /// A year in a seven-column day grid would be 53 rows tall: several screens of
    /// scrolling for a view whose entire purpose is to be taken in at once (§7.4 asks
    /// for dense and quantitative). Transposing it puts the whole year in one block
    /// roughly as tall as a month grid.
    ///
    /// **Why weekday rows rather than twelve month rows.** Both are defensible and the
    /// choice is not aesthetic. This plan is a *Monday-first weekly template* with a
    /// long-run arc indexed by week (D1, MAX-011); the week is the unit the athlete's
    /// training is actually written in. Weekday rows therefore put every Monday on one
    /// line, so "my Wednesday easy runs are consistently ineffective" and "week 31 was a
    /// hole" are both directly readable. Month rows would align cells by day-of-month,
    /// which corresponds to nothing in this plan at all — the 14th of a month is not a
    /// recurring anything.
    ///
    /// **The cost, stated.** At this size a cell holds no date and no glyph, so the shape
    /// channel MAX-061 relies on is gone. The mitigation is partial: a `.missed` day is
    /// drawn hollow rather than filled (`ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`),
    /// which separates it from `.ineffective` without hue, and every cell keeps its
    /// full-sentence VoiceOver label, dated with its month.
    ///
    /// `.effective` versus `.marginal` was carried by hue alone here — `docs/DESIGN-
    /// REVIEW.md` §8.1 measured the same gap in the *day grid*, where those two fills
    /// contrast at 1.02:1 and the glyph encodes activity rather than band, so this was a
    /// pre-existing gap the heatmap inherited rather than one it introduced. MAX-087
    /// (the review's T6) closed it: `ScoreBand.heatmapMark` sizes a scored day's fill
    /// within the mark's footprint instead of always drawing it edge to edge, and that
    /// mapping is asserted alongside the day grid's corner-pip mapping in
    /// `WCAGContrastTests`. Whether the resulting marks are legible at six points on an
    /// actual phone is the one thing about that fix that only a device can answer.
    case weekColumnHeatmap
}

/// What the HR-drift section (FR-3.3, D5) is at a span.
public enum DriftSectionRepresentation: Hashable, Sendable, CaseIterable {
    /// `HeartRateDriftOverlayData`'s normalised curve stack leads, with the per-run
    /// drift trendline beneath it — MAX-062 and MAX-065 as they shipped.
    ///
    /// The overlay's value is a *shape* comparison across a handful of runs, and its
    /// stack limit of 12 is sized for exactly that. A week holds 3–6 qualifying runs and
    /// a month 12–25, so at these two spans the limit is either slack or mildly binding,
    /// and the caption says how many were held back.
    case curveOverlayLed

    /// The trendline alone, over every run in the interval carrying a stored drift
    /// figure. No curve stack.
    ///
    /// **Why the overlay is dropped rather than shrunk.** At a year the stack limit
    /// stops being a legibility cap and becomes a lie: stacking the 12 most recent
    /// qualifying runs out of ~200 draws the last three weeks and labels it a year. The
    /// honest options were to raise the limit — MAX-062 already argued that past a dozen
    /// curves the eye reads texture, not lines — or to drop the chart at this span. The
    /// second is right, because the trendline is the chart that *improves* with a year of
    /// points: 200 scalars over 12 months is where a least-squares fit finally has
    /// something to say, and "is my drift flattening" is the question FR-3.3 names.
    ///
    /// So at a year the section is the trendline, promoted to headline, over a wider set
    /// of runs than the overlay would ever have stacked — every run whose classification
    /// makes drift meaningful and which carries a stored figure, not merely those whose
    /// curve was long enough to *resample*. See `DriftFigureSelection` for why that
    /// widening does not reintroduce the disagreement MAX-065 was careful to avoid.
    case trendlineOnly

    /// Whether building this representation requires reading every run's stored
    /// heart-rate curve.
    ///
    /// This is a performance decision, not a cosmetic one, and it is the reason the
    /// choice above lives in the core rather than in the view. `DriftOverlayModel`
    /// deliberately does not pre-filter candidates — it hands the overlay every run,
    /// curve included, so exclusion reasons are decided in one tested place — which
    /// means the curve-led representation reads one `.externalStorage` HR blob per run
    /// in the interval. That is fine at 6 runs and acceptable at 25. At a year it is
    /// ~200 multi-kilobyte blob reads to draw twelve lines, on a phone, for a screen
    /// that will not show them.
    ///
    /// The trendline-only representation reads no curves at all. It needs one stored
    /// scalar per run (`DerivedMetrics.heartRateDriftFraction`, D2) and the run's stored
    /// classification, both small rows.
    public var loadsStoredHeartRateCurves: Bool {
        switch self {
        case .curveOverlayLed: return true
        case .trendlineOnly: return false
        }
    }

    /// The section's heading. Here rather than in the view for the reason
    /// `HeartRateDriftOverlayData.stackSummary` and `exclusionNotes` are: the two spans
    /// show different charts, and a heading that said "HR drift across runs" above a
    /// chart with no curves on it would be describing the other representation.
    public var title: String {
        switch self {
        case .curveOverlayLed: return "HR drift across runs"
        case .trendlineOnly: return "HR drift trend"
        }
    }
}

/// Which figures the summary tiles (FR-3.4) measure at a span.
///
/// The tiles are the surface where "a year is not a month with more cells" is least
/// obvious and most true: the *same* four figures are all computable over a year, and
/// two of them stop meaning anything useful.
public enum TrendTileSet: Hashable, Sendable, CaseIterable {
    /// FR-3.4 as written: mileage vs. the plan's arc target, effective days, streak,
    /// average score.
    ///
    /// "Mileage vs arc" is at its most literal here — the arc prescribes a weekly
    /// distance (D1, `LongRunArc.Week`), so at a week the tile compares one ask to one
    /// week's execution.
    case weekly

    /// The weekly set plus **days run**.
    ///
    /// Mileage vs. arc survives: summing the month's plan days against the month's
    /// workouts is four or five weekly asks against four or five weeks of execution,
    /// which is still a comparison the athlete can act on.
    ///
    /// Days run is added because consistency is the figure a month answers and a week
    /// cannot: 18 days out of a month is a fact about a training block, whereas 4 days
    /// out of a week is already legible in the calendar row directly above it.
    case monthly

    /// **Totals and rates, with the arc comparison dropped:** total distance,
    /// effective-day *rate*, days run, streak, average score.
    ///
    /// Two changes, each for a stated reason:
    ///
    /// - **No mileage-vs-arc.** Summing a year of daily plan targets produces a number
    ///   built from ~52 different weekly asks, against which "1,284 / 1,410" is a
    ///   comparison of two aggregates nobody has intuition for. Worse, it is *biased* in
    ///   a way the shorter spans mostly escape: a year almost always reaches back past
    ///   the athlete's first plan version, so the actual distance covers twelve months
    ///   while the target covers however many the plan governs, and the tile silently
    ///   reports beating a plan that did not exist yet. Total distance alone carries no
    ///   such claim.
    /// - **Effective days as a percentage.** At a week, "4/5" is the readable form and
    ///   the denominator is the point. At a year, "211/310" is two numbers to divide in
    ///   your head; the rate is the signal. The denominator does not disappear — it
    ///   moves into the caption, because `EffectiveDayTally`'s own documentation is
    ///   right that a bare percentage hiding its denominator is how a training log
    ///   lies.
    case annual
}
