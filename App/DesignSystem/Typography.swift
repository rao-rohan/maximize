import SwiftUI

/// The typographic scale.
///
/// FR-4.3 assigns hierarchy to type, not to color: the palette is near-monochrome by
/// design, so the difference between "the number that matters" and "the label telling
/// you what it is" has to be carried by size and weight. That is the whole job of this
/// file. It defines a scale; it does not decorate.
///
/// Three rules the scale encodes:
///
/// 1. **Numbers are rounded and monospaced-digit.** Rounded because the metrics are
///    the display face of the app; monospaced digits because a value that re-flows
///    while a chart scrubs or a timer ticks reads as jitter.
/// 2. **Labels are quiet.** They step down in size *and* are expected to be drawn in
///    `Color.textSecondary`. Nothing is bolded to get attention.
/// 3. **Structural text uses system text styles**, so it inherits Dynamic Type
///    behavior for free.
extension Font {

    // MARK: Metrics — the numbers the product exists to show

    /// The one number on a screen: the 0–100 effectiveness score in the verdict
    /// header (FR-1.1). Never more than one of these visible at a time.
    ///
    /// Fixed point size rather than a text style because no built-in style is this
    /// large. **Dynamic Type behavior at accessibility sizes is unverified** — see the
    /// device checklist on the MAX-040 PR; if it does not scale, MAX-070 should switch
    /// this to `@ScaledMetric`.
    static let metricHero = Font
        .system(size: 56, weight: .semibold, design: .rounded)
        .monospacedDigit()

    /// The headline value in a summary tile: distance, average HR, drift %
    /// (FR-1.5, FR-3.4).
    static let metricPrimary = Font
        .system(size: 32, weight: .semibold, design: .rounded)
        .monospacedDigit()

    /// A value inline in a row — a split's pace, a cadence readout.
    static let metricSecondary = Font
        .system(size: 20, weight: .medium, design: .rounded)
        .monospacedDigit()

    // MARK: Structure

    /// Screen-level title.
    static let screenTitle = Font.system(.largeTitle, weight: .bold)

    /// Section header above a chart or a group of tiles.
    static let sectionHeading = Font.system(.headline, weight: .semibold)

    /// Running prose: the scorer's one-line rationale, chat messages.
    static let bodyCopy = Font.system(.body)

    // MARK: Labels — quiet by construction

    /// The caption under a metric saying what it is ("avg HR", "time above cap").
    /// Pair with `Color.textSecondary`.
    static let metricLabel = Font.system(.subheadline)

    /// Axis ticks, timestamps, calendar day numbers. Pair with `Color.textTertiary`.
    static let microLabel = Font
        .system(.caption2, weight: .medium)
        .monospacedDigit()
}
