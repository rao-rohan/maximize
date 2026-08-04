import SwiftUI
import UIKit

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
    /// Scales with Dynamic Type (MAX-070) — see `scaledMetricFont(size:weight:relativeTo:)`
    /// below. Anchored to `.largeTitle`, the built-in style closest to this weight of
    /// emphasis, so the hero numeral scales on the same curve `screenTitle` does.
    static let metricHero = scaledMetricFont(size: 56, weight: .semibold, relativeTo: .largeTitle)
        .monospacedDigit()

    /// The headline value in a summary tile: distance, average HR, drift %
    /// (FR-1.5, FR-3.4). Anchored to `.title1` (28pt default — the closest built-in
    /// size to 32pt).
    static let metricPrimary = scaledMetricFont(size: 32, weight: .semibold, relativeTo: .title1)
        .monospacedDigit()

    /// A value inline in a row — a split's pace, a cadence readout. Anchored to
    /// `.title3` (20pt default — matches this token's base size exactly).
    static let metricSecondary = scaledMetricFont(size: 20, weight: .medium, relativeTo: .title3)
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

// MARK: - Dynamic Type for a fixed point size

/// Builds a `.rounded` system font at exactly `size`/`weight`, then scales it against
/// the user's preferred text size the same way a built-in text style would (MAX-070).
///
/// `Font.system(size:weight:design:)` — what the metric fonts used before this ticket
/// — takes a fixed point size that Dynamic Type cannot touch at all: turn on an
/// accessibility text size and the 0–100 effectiveness score, the single most
/// important number on the screen (FR-1.1), stayed exactly 56pt while every label
/// around it grew. `UIFontMetrics` is Apple's supported bridge for exactly this case:
/// it scales a custom-size font by the same ratio the OS would apply to `relativeTo`,
/// so the numeral grows under Larger Text precisely as that text style does, while
/// still starting from the exact point size the visual hierarchy was designed at.
///
/// At the default (non-accessibility) content size category this returns the font at
/// its designed size unchanged — `UIFontMetrics` scaling is 1.0 there — so
/// `metricHero`/`metricPrimary`/`metricSecondary` render at exactly 56/32/20pt as
/// before and the hierarchy at default size is untouched.
private func scaledMetricFont(size: CGFloat, weight: UIFont.Weight, relativeTo textStyle: UIFont.TextStyle) -> Font {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    // `withDesign` is documented to return nil only when the requested design isn't
    // available for this descriptor; falling back to the non-rounded descriptor keeps
    // this total rather than introducing a force-unwrap for a case that, on every
    // iOS 26 target this app ships to, does not happen.
    let roundedDescriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    let rounded = UIFont(descriptor: roundedDescriptor, size: size)
    let scaled = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: rounded)
    return Font(scaled)
}
