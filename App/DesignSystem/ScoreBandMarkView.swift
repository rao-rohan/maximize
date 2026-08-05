import SwiftUI
import MaximizeCore

/// Draws `ScoreBand.mark` — the band's non-colour channel (MAX-084).
///
/// Everything about *which* mark a band gets is decided in `MaximizeCore`; this view
/// only knows how to draw a dot, a ring, or nothing. Both surfaces FR-4.3 admits the
/// band colours on — the calendar (D4/FR-3.2) and the verdict header (FR-1.1) — draw
/// the mark through this one view, so the two can never diverge on what a ring means.
///
/// ## Why the footprint is reserved even when there is no mark
///
/// `.unmarked` draws `Color.clear` at the full diameter rather than nothing at all, so
/// a cell's layout does not shift by a few points depending on how the run scored. The
/// grid stays a grid.
///
/// ## Ink
///
/// Always `textOnSaturatedFill`, because the mark is only ever drawn on a band fill,
/// and that pairing measures 5.77:1 at its worst (`scoreIneffective` in dark) and
/// 9.72:1 at its best — see `WCAGContrastTests`. The mark carries no hue of its own:
/// giving it one would put the meaning back in colour, which is the thing this exists
/// to stop doing.
struct ScoreBandMarkView: View {
    let band: ScoreBand

    /// Outside diameter. `LayoutMetrics.scoreBandMarkSize` in a calendar cell,
    /// `LayoutMetrics.prominentScoreBandMarkSize` in the verdict header.
    let diameter: CGFloat

    var body: some View {
        Group {
            switch band.mark {
            case .filledPip:
                Circle()
                    .fill(Color.textOnSaturatedFill)
            case .hollowPip:
                // A quarter of the diameter: at the calendar's 6pt that is a 1.5pt
                // stroke around a 3pt hole, which is the smallest ring that still reads
                // as a ring rather than as a slightly soft dot. Tied to the diameter so
                // it stays a ring when Dynamic Type grows the cell.
                Circle()
                    .strokeBorder(Color.textOnSaturatedFill, lineWidth: diameter / 4)
            case .unmarked:
                Color.clear
            }
        }
        .frame(width: diameter, height: diameter)
        // The band is already spoken in full by the calendar cell's own label
        // (`ScoreCalendarFormatting.accessibilityLabel`); this is the channel for people
        // who are looking, not listening.
        .accessibilityHidden(true)
    }
}

/// Draws a scored day's fill at `ScoreBand.heatmapMark`'s size (MAX-087) — the year
/// heatmap's non-colour channel, for the density at which `ScoreBandMarkView`'s corner
/// pip has nowhere to sit. Everything about *which* size a band gets is decided in
/// `MaximizeCore`; this only knows the fraction each case draws at, the same division
/// of labour `ScoreBandMarkView` uses above.
///
/// Fills at less than the full available size rather than drawing a fixed inset, so the
/// mark scales with whatever frame it is given — the calendar's true ~6pt heatmap cell,
/// or a magnified specimen in `DesignSystemGallery`.
struct ScoreBandHeatmapMarkView: View {
    let band: ScoreBand
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.scoreBand(band))
            // Scales about the shape's own centre, so the margin this leaves is even
            // on every side rather than pulling the mark toward one corner.
            .scaleEffect(scale)
    }

    private var scale: CGFloat {
        switch band.heatmapMark {
        case .fullBleed:
            return 1.0
        case .majorInset:
            return LayoutMetrics.heatmapMarkMajorInsetFraction
        case .minorInset:
            return LayoutMetrics.heatmapMarkMinorInsetFraction
        }
    }
}
