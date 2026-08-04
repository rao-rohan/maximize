import SwiftUI
import UIKit
import MaximizeCore

// MARK: - Turning palette data into a live SwiftUI color

/// Adapts a `DesignPalette.Ink` (plain sRGB data, defined once in `MaximizeCore`) into
/// a `UIColor` that re-resolves on every trait change.
///
/// MAX-070: the raw color numbers used to live here, in a private `Ink` this file
/// owned. They now live in `DesignPalette` (MaximizeCore/Accessibility), which has no
/// UIKit dependency and therefore builds and runs on whatever host CI's `swift test`
/// uses — that's what makes `WCAGContrastTests` possible at all. This file's job
/// narrowed to exactly what only it can do: turn that data into a `UIColor`. **This
/// is still the only place in the app that constructs a `UIColor`/`Color` from raw
/// numbers** — that half of the contract (name meaning, not appearance, everywhere
/// else) is unchanged; only where the numbers themselves are declared moved.
///
/// Increase Contrast is wired end to end (MAX-040): `UIColor`'s dynamic provider
/// re-resolves on every trait change, so raising contrast is a matter of editing the
/// `…HighContrast` values in `DesignPalette` — no view, modifier, or call site changes.
///
/// Dark-first (FR-4.3): the dark value is the designed one and is also what an
/// `.unspecified` interface style resolves to. Light values exist so the app is not
/// unreadable if someone runs it in light mode; they have not been designed with the
/// same care and no screen has been reviewed in light appearance.
private extension DesignPalette.Ink {
    var color: Color {
        Color(uiColor: UIColor { traits in
            let wantsHighContrast = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle, wantsHighContrast) {
            case (.light, true):
                return UIColor(lightHighContrast)
            case (.light, false):
                return UIColor(light)
            // `.dark` and `.unspecified` both land here — dark is the default appearance.
            case (_, true):
                return UIColor(darkHighContrast)
            case (_, false):
                return UIColor(dark)
            }
        })
    }
}

private extension UIColor {
    convenience init(_ token: ColorToken) {
        self.init(
            red: CGFloat(token.red) / 255,
            green: CGFloat(token.green) / 255,
            blue: CGFloat(token.blue) / 255,
            alpha: 1
        )
    }
}

// MARK: - Semantic tokens

/// The app's color vocabulary.
///
/// Views name *meaning* (`Color.textSecondary`), never appearance. If a view ever needs
/// a color that is not here, the fix is to add a token with a semantic name — not to
/// reach for a literal. The values themselves live in `MaximizeCore`'s `DesignPalette`
/// (MAX-070); this file is the only place they are turned into a `Color`.
extension Color {

    // MARK: Content surfaces (flat, opaque — FR-4.2)

    /// The screen background everything else sits on.
    static let surface = DesignPalette.surface.color

    /// A card or tile lifted off the screen background: summary tiles, chart
    /// containers, the calendar. Opaque, always.
    static let surfaceElevated = DesignPalette.surfaceElevated.color

    /// A well *inside* a card: a chart's plot area, a segmented-control track, the
    /// shaded time-above-cap region's backdrop.
    static let surfaceInset = DesignPalette.surfaceInset.color

    /// Hairline rules between rows and sections.
    static let separator = DesignPalette.separator.color

    // MARK: Text

    /// Metrics that matter, headings, primary values.
    static let textPrimary = DesignPalette.textPrimary.color

    /// Quiet labels — the units, the captions, the "what this number is" text. FR-4.3
    /// wants typography and this contrast step doing the hierarchy work, not color.
    static let textSecondary = DesignPalette.textSecondary.color

    /// Axis ticks, timestamps, disabled states. Deliberately recessive — but still
    /// real text (MAX-070 raised it to clear WCAG AA's 4.5:1; see `DesignPalette`).
    static let textTertiary = DesignPalette.textTertiary.color

    /// Text or glyphs drawn *on top of* a saturated fill — the accent, or a score-band
    /// cell in the calendar. One token because it is one job: all four saturated
    /// colors are light in dark mode and dark in light mode, so the legible ink over
    /// them is the same in every case.
    static let textOnSaturatedFill = DesignPalette.textOnSaturatedFill.color

    // MARK: Accent

    /// **The accent. Change this one declaration to re-theme the app.**
    ///
    /// PRD §14.2 / amendment A7 leave the accent to the owner and mark it explicitly
    /// non-blocking, so this is a defensible default, not a decision. It is reserved
    /// for the on-plan / effective state and for interactive affordances, used
    /// sparingly (FR-4.3).
    ///
    /// Chosen as a violet rather than a green, a blue, or a warm hue, because it has
    /// to survive three separate collisions:
    /// - it must not be Robinhood's green (`#00C805`) — the PRD says so directly;
    /// - it must not read as any of the three score bands, or "accent" and "this run
    ///   scored well" collapse into one signal on the same screen;
    /// - it must not read as the untinted iOS system blue, which users parse as
    ///   "default app, no design applied", and which is also the color of a link.
    ///
    /// Violet is the only region of the wheel far from green, amber, *and* red at
    /// once. `#8E7CFF` measures **6.06:1** against `surface` in dark (verified,
    /// MAX-070 — `WCAGContrastTests`; MAX-040's original ~5.9:1 was an eyeball
    /// estimate), so it is legible as text and not only as a fill.
    static let accent = DesignPalette.accent.color

    // MARK: Score bands (FR-4.3 — the only other saturated colors in the app)

    // These are raw tokens. Views must not reach for them directly: use
    // `Color.scoreBand(_:)` in ScoreBandColors.swift, which takes a decided band and
    // cannot be handed a raw score.

    static let scoreEffective = DesignPalette.scoreEffective.color

    static let scoreMarginal = DesignPalette.scoreMarginal.color

    static let scoreIneffective = DesignPalette.scoreIneffective.color

    // MARK: Charts
    //
    // Chart tokens are content, not decoration: FR-4.2 protects exactly these marks
    // from translucency because a blurred cap line is a wrong cap line. Kept neutral
    // on purpose — the saturated budget is already spent on the accent and the bands.

    /// Gridlines behind a plot. Should be visible and never compete with the series.
    static let chartGridline = DesignPalette.chartGridline.color

    /// A plan threshold drawn across a chart — the HR cap line (FR-1.2), the cadence
    /// target band edges (FR-1.3). Reads as "the rule", distinct from the data.
    static let chartThreshold = DesignPalette.chartThreshold.color

    /// The run being looked at — the foreground HR curve.
    static let chartSeriesPrimary = DesignPalette.chartSeriesPrimary.color

    /// Context curves behind the primary one: the other runs in the cross-run drift
    /// overlay (D5/FR-3.3), which stacks many curves and highlights one.
    static let chartSeriesMuted = DesignPalette.chartSeriesMuted.color

    // MARK: Chrome

    /// The opaque stand-in for Liquid Glass when Reduce Transparency is on (FR-4.5).
    ///
    /// Chrome degrades to this solid fill rather than to nothing, so the tab bar and
    /// floating controls keep their figure/ground separation from the content beneath.
    /// Applied by `View.glassChrome(_:)`; no view should need to name it.
    static let chromeOpaque = DesignPalette.chromeOpaque.color
}
