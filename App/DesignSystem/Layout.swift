import CoreGraphics

/// The spacing ramp.
///
/// Robinhood's density is the reference (FR-4.3/§7.4): generous negative space, few
/// elements per screen, nothing crowding a chart. The ramp is deliberately coarse —
/// eight steps, roughly geometric — because a fine-grained ramp is one where every
/// value is defensible and the layout still drifts. If a gap needs a value that is not
/// here, the gap is probably wrong.
enum Spacing {
    /// Between a glyph and its adjacent text.
    static let hairspace: CGFloat = 2
    /// Between a metric and its label.
    static let tight: CGFloat = 4
    /// Between tightly related rows.
    static let snug: CGFloat = 8
    /// Default gap inside a component.
    static let compact: CGFloat = 12
    /// Default gap between components.
    static let regular: CGFloat = 16
    /// Between distinct groups within a section.
    static let roomy: CGFloat = 24
    /// Between sections of a screen.
    static let section: CGFloat = 32
    /// Above and below a screen's single most important element.
    static let hero: CGFloat = 48
}

/// Corner radii for content surfaces.
///
/// Chrome does not appear here: Liquid Glass shapes come from the system (a capsule
/// for floating controls, the platform's own shape for bars), and hard-coding a radius
/// for them is how chrome stops looking like the OS.
enum CornerRadius {
    /// Small controls and chips.
    static let control: CGFloat = 10
    /// Summary tiles and calendar cells.
    static let tile: CGFloat = 12
    /// A single day's mark in the year heatmap (FR-3.2 at the year span). Small enough
    /// to read as a square at ~6pt — `tile`'s 12pt on a 6pt mark is a circle, and a grid
    /// of circles reads as dots rather than as a filled calendar.
    static let heatmapMark: CGFloat = 1.5
    /// Chart containers and cards.
    static let card: CGFloat = 16
}

/// Screen-level layout constants.
enum LayoutMetrics {
    /// Horizontal inset from the screen edge to content. Wide on purpose.
    static let screenMargin: CGFloat = 20

    /// Padding inside a card or tile, between its border and its content.
    static let surfacePadding: CGFloat = 16

    /// Vertical rhythm between top-level sections of a scrolling screen.
    static let sectionSpacing: CGFloat = Spacing.section

    /// A rule that reads as a line rather than a bar. Roughly one device pixel at 2x.
    static let hairline: CGFloat = 0.5

    /// Minimum height of a chart before its detail stops being readable. FR-1.2 and
    /// FR-3.3 both plot fine lines against a threshold; squeezing them is how the cap
    /// line becomes decoration.
    static let minimumChartHeight: CGFloat = 220

    /// Height of a single-value chart plotted on one axis only — the cadence band
    /// track (FR-1.3). Shorter than `minimumChartHeight` on purpose: there is no
    /// vertical dimension of data to protect here, only a horizontal position, so the
    /// full chart height would just be empty space above and below the marker.
    static let compactChartHeight: CGFloat = 96

    /// The box a calendar cell's state glyph is drawn in (FR-3.2, D4).
    ///
    /// Fixed rather than intrinsic because SF Symbols do not share a size: the day
    /// states resolve to marks as different as `minus` and
    /// `figure.run.square.stack`, and letting each one size itself made the grid
    /// ragged — a rest day drew visibly smaller than a run. Squaring the box also
    /// keeps a wide glyph from shifting the date above it off-centre.
    static let calendarGlyphSize: CGFloat = 12

    /// Gap between marks in the year heatmap, in both axes.
    ///
    /// Not on the `Spacing` ramp, and deliberately below its smallest step: 53 columns
    /// across a phone's content column leaves roughly six points per mark, so `tight`'s
    /// 4pt would spend two thirds of the width on gaps. The ramp's own doc comment says a
    /// gap needing a value that is not on it is probably wrong — this is the exception it
    /// admits, because the constraint here is a fixed 53 columns rather than a judgement
    /// about density. The gap still has to exist: without it, adjacent days of the same
    /// band merge into one block and the week structure disappears.
    static let heatmapCellSpacing: CGFloat = 1.5

    /// Stroke width for a hollow heatmap mark — a missed day. Heavier than `hairline`,
    /// which would vanish against a mark this small.
    static let heatmapMarkStroke: CGFloat = 1

    /// Outside diameter of the score-band mark in a calendar cell (MAX-084).
    ///
    /// Small on purpose. A cell is roughly 42pt on a 390pt-wide phone and already holds
    /// a date and a state glyph; the mark has to sit in a corner without crowding
    /// either. Six points is about the floor at which a ring still reads as a ring —
    /// see `ScoreBandMarkView` — and is the value a device check should scrutinise
    /// first if the channel turns out not to read.
    static let scoreBandMarkSize: CGFloat = 6

    /// The same mark on the verdict header's band chip, which has room for it.
    static let prominentScoreBandMarkSize: CGFloat = 10

    /// Visible-edge fraction of a year-heatmap mark's full footprint, for
    /// `ScoreBandHeatmapMark.majorInset` and `.minorInset` (MAX-087). `.fullBleed`
    /// needs no constant of its own — by definition it draws at the full footprint,
    /// fraction 1.
    ///
    /// Chosen so the smallest tier — `.minorInset`, `.ineffective`'s mark — still
    /// clears roughly a point across at the heatmap's own ~6pt mark size
    /// (`LayoutMetrics.heatmapCellSpacing`'s doc comment). Below that this channel
    /// stops reading as "a smaller mark" and starts reading as a rendering artifact.
    /// Needs device verification: see `ScoreBandHeatmapMark`.
    static let heatmapMarkMajorInsetFraction: CGFloat = 0.64
    static let heatmapMarkMinorInsetFraction: CGFloat = 0.4
}
