/// The qualitative band a workout's effectiveness score falls into.
///
/// **This type deliberately cannot compute itself from a score.** There is no
/// `init(score:)` and there never should be. PRD D1 makes the effective threshold
/// (currently ≥ 70) *versioned plan data*, so the score→band decision depends on the
/// plan version in effect on the workout's date. Baking `score >= 70` into a type — or
/// worse, into a view — would make historical scores irreproducible the first time the
/// plan changes, which is the exact failure D1 exists to prevent.
///
/// The scorer resolves the band once, against the plan version it scored under, and
/// stores it. Everything downstream — the calendar (D4), the verdict header (FR-1.1),
/// the design system's color mapping — consumes the stored band. That is also D2's
/// rule ("compute once at ingestion, never recompute at display time") applied to a
/// classification rather than a metric.
///
/// Why this lives in the core rather than the app layer: the band is domain
/// vocabulary, not a display bucket. Scoring (MAX-015) produces it, tallies (MAX-017)
/// aggregate it, and it will be persisted alongside the immutable auto-score (D8). If
/// it lived in `App/DesignSystem`, the core would have to invent a parallel type and
/// the two would drift — the same divergence D3 forbids for prompt context. It carries
/// no UI dependency, so it costs the core nothing.
public enum ScoreBand: String, Codable, Hashable, Sendable, CaseIterable {
    /// The session met the plan's effectiveness bar. Rendered green.
    case effective

    /// The session fell short but not badly — a near miss worth distinguishing from a
    /// failure. Rendered amber.
    case marginal

    /// The session missed the plan, or the scheduled session did not happen at all
    /// (D9). Rendered red.
    case ineffective
}
