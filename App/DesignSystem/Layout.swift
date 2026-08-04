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
}
