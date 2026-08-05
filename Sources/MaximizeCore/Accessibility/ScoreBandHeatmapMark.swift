/// The band channel that survives at year-heatmap density (MAX-087).
///
/// ## Why `ScoreBandMark` isn't enough here
///
/// `ScoreBandMark` (MAX-084) puts a pip in a cell's corner — a device that needs a
/// corner to sit in. The year heatmap draws each day at roughly
/// `LayoutMetrics.heatmapCellSpacing` apart, in a mark that is itself only a few points
/// across (`ScoreCalendarRepresentation.weekColumnHeatmap`); there is no corner left
/// once the whole mark is the size a corner pip would have been. So at that density the
/// day grid's channel silently stops applying, and `.effective` / `.marginal` /
/// `.ineffective` are back to hue alone — the exact defect MAX-084 closed everywhere
/// else. `docs/DESIGN-REVIEW.md` §8.1 and `ScoreCalendarRepresentation
/// .weekColumnHeatmap` both named this gap and left it for a later ticket; this is that
/// ticket.
///
/// ## The channel: how much of the mark's footprint a band fills
///
/// Every mark in the heatmap already occupies the cell's full aspect-fit footprint
/// (`ScoreCalendarHeatmapCell`). Drawing a scored day's fill smaller than that footprint
/// — centred, with a visible margin of the calendar card's own background around it —
/// is a geometric difference, not a colour one. It survives greyscale and every kind of
/// colour vision, and unlike a lightness or opacity change it is not itself a colour
/// value, so it cannot be quietly weakened by Increase Contrast or Reduce Transparency
/// the way an opacity-based channel could be: there is nothing for either setting to
/// override. The cost is honest, too — a smaller mark is less ink, which is some of the
/// density the year view exists for, which is why this is reserved for telling bands
/// apart rather than reached for everywhere.
///
/// ## Why not shape
///
/// A rounded square and a circle are nearly the same mark once both are ~6pt with a
/// ~1.5pt gap to the next one (`LayoutMetrics.heatmapCellSpacing`) — anti-aliasing at
/// that scale erodes a corner-radius difference faster than it erodes an area
/// difference. Size was chosen over shape for that reason, but nobody working this
/// ticket has a device to confirm it on: **needs device verification**, first thing on
/// the list — see the MAX-087 PR.
public enum ScoreBandHeatmapMark: String, Hashable, Sendable, CaseIterable {
    /// Fills the mark's full footprint, edge to edge.
    case fullBleed

    /// A smaller, centred square — visibly inset from the full footprint.
    case majorInset

    /// Smaller still.
    case minorInset
}

extension ScoreBand {

    /// The non-colour channel `ScoreCalendarHeatmapCell` reads at year density.
    ///
    /// Distinct per band for the same reason `mark` is: `WCAGContrastTests` asserts
    /// that no two bands share a heatmap mark, so a future edit that collapses two
    /// bands onto the same size fails CI instead of quietly shipping hue-only.
    ///
    /// `.effective` gets the full mark: the day the athlete fully executed reads as a
    /// solid, complete block, which is also the reading a heatmap's "more ink, more
    /// activity" convention already trains a viewer to expect. `.ineffective` gets the
    /// smallest — and that pairing (`.effective` vs `.ineffective`) is also the widest
    /// gap on the luminance axis of the three (0.4693 vs 0.2582 in dark, an actual
    /// though sub-AA difference), so it is the pairing that can best afford the least
    /// legible size. `.marginal` sits in the middle, which is exactly where it needs a
    /// channel most: it is the band that measures 1.02:1 against `.effective` and
    /// 1.66:1 against `.ineffective` in dark — the two ratios this ticket exists to fix.
    public var heatmapMark: ScoreBandHeatmapMark {
        switch self {
        case .effective:
            return .fullBleed
        case .marginal:
            return .majorInset
        case .ineffective:
            return .minorInset
        }
    }
}
