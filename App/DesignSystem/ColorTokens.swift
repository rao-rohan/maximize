import SwiftUI
import UIKit

// MARK: - The one place raw color values live

/// A color literal in four appearances.
///
/// Every token below is declared as one of these, which is what makes MAX-070
/// (Reduce Transparency / Increase Contrast) a small change rather than a rewrite:
/// **Increase Contrast is already wired**. `UIColor`'s dynamic provider re-resolves on
/// every trait change, so raising contrast is a matter of editing the
/// `…HighContrast` values in this file — no view, modifier, or call site changes.
///
/// Dark-first (FR-4.3): the dark value is the designed one and is also what an
/// `.unspecified` interface style resolves to. Light values exist so the app is not
/// unreadable if someone runs it in light mode; they have not been designed with the
/// same care and no screen has been reviewed in light appearance.
private struct Ink {
    let dark: UInt32
    let light: UInt32
    let darkHighContrast: UInt32
    let lightHighContrast: UInt32

    init(
        dark: UInt32,
        light: UInt32,
        darkHighContrast: UInt32? = nil,
        lightHighContrast: UInt32? = nil
    ) {
        self.dark = dark
        self.light = light
        self.darkHighContrast = darkHighContrast ?? dark
        self.lightHighContrast = lightHighContrast ?? light
    }

    var color: Color {
        Color(uiColor: UIColor { traits in
            let wantsHighContrast = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle, wantsHighContrast) {
            case (.light, true):
                return UIColor(rgb: lightHighContrast)
            case (.light, false):
                return UIColor(rgb: light)
            // `.dark` and `.unspecified` both land here — dark is the default appearance.
            case (_, true):
                return UIColor(rgb: darkHighContrast)
            case (_, false):
                return UIColor(rgb: dark)
            }
        })
    }
}

private extension UIColor {
    /// Total by construction: every `UInt32` names a valid opaque color, so there is
    /// no failable parse and therefore nothing to force-unwrap.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Semantic tokens

/// The app's color vocabulary.
///
/// Views name *meaning* (`Color.textSecondary`), never appearance. If a view ever needs
/// a color that is not here, the fix is to add a token with a semantic name — not to
/// reach for a literal. This file is the only place in the app where a color value is
/// written down.
extension Color {

    // MARK: Content surfaces (flat, opaque — FR-4.2)

    /// The screen background everything else sits on.
    static let surface = Ink(
        dark: 0x0B0B0F,
        light: 0xFFFFFF,
        darkHighContrast: 0x000000,
        lightHighContrast: 0xFFFFFF
    ).color

    /// A card or tile lifted off the screen background: summary tiles, chart
    /// containers, the calendar. Opaque, always.
    static let surfaceElevated = Ink(
        dark: 0x16161C,
        light: 0xF5F5F7,
        darkHighContrast: 0x1C1C25,
        lightHighContrast: 0xEDEDF2
    ).color

    /// A well *inside* a card: a chart's plot area, a segmented-control track, the
    /// shaded time-above-cap region's backdrop.
    static let surfaceInset = Ink(
        dark: 0x1F1F27,
        light: 0xEBEBEF,
        darkHighContrast: 0x26262F,
        lightHighContrast: 0xE0E0E6
    ).color

    /// Hairline rules between rows and sections.
    static let separator = Ink(
        dark: 0x2C2C36,
        light: 0xD5D5DC,
        darkHighContrast: 0x4A4A56,
        lightHighContrast: 0xA8A8B4
    ).color

    // MARK: Text

    /// Metrics that matter, headings, primary values.
    static let textPrimary = Ink(
        dark: 0xF5F5F7,
        light: 0x0B0B0F,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    ).color

    /// Quiet labels — the units, the captions, the "what this number is" text. FR-4.3
    /// wants typography and this contrast step doing the hierarchy work, not color.
    static let textSecondary = Ink(
        dark: 0xA0A0AC,
        light: 0x55555F,
        darkHighContrast: 0xC6C6D0,
        lightHighContrast: 0x2E2E38
    ).color

    /// Axis ticks, timestamps, disabled states. Deliberately recessive.
    static let textTertiary = Ink(
        dark: 0x70707C,
        light: 0x8A8A96,
        darkHighContrast: 0x9C9CA8,
        lightHighContrast: 0x55555F
    ).color

    /// Text or glyphs drawn *on top of* a saturated fill — the accent, or a score-band
    /// cell in the calendar. One token because it is one job: all four saturated
    /// colors are light in dark mode and dark in light mode, so the legible ink over
    /// them is the same in every case.
    static let textOnSaturatedFill = Ink(
        dark: 0x0B0B0F,
        light: 0xFFFFFF
    ).color

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
    /// once. `#8E7CFF` measures roughly 5.9:1 against `surface` in dark, so it is
    /// legible as text and not only as a fill.
    static let accent = Ink(
        dark: 0x8E7CFF,
        light: 0x5B3FE8,
        darkHighContrast: 0xB3A6FF,
        lightHighContrast: 0x3B22C4
    ).color

    // MARK: Score bands (FR-4.3 — the only other saturated colors in the app)

    // These are raw tokens. Views must not reach for them directly: use
    // `Color.scoreBand(_:)` in ScoreBandColors.swift, which takes a decided band and
    // cannot be handed a raw score.

    static let scoreEffective = Ink(
        dark: 0x30D158,
        light: 0x248A3D,
        darkHighContrast: 0x5CE07B,
        lightHighContrast: 0x146B2C
    ).color

    static let scoreMarginal = Ink(
        dark: 0xFF9F0A,
        light: 0xB25000,
        darkHighContrast: 0xFFB84D,
        lightHighContrast: 0x8C3D00
    ).color

    static let scoreIneffective = Ink(
        dark: 0xFF453A,
        light: 0xD70015,
        darkHighContrast: 0xFF7A72,
        lightHighContrast: 0xA80010
    ).color

    // MARK: Charts
    //
    // Chart tokens are content, not decoration: FR-4.2 protects exactly these marks
    // from translucency because a blurred cap line is a wrong cap line. Kept neutral
    // on purpose — the saturated budget is already spent on the accent and the bands.

    /// Gridlines behind a plot. Should be visible and never compete with the series.
    static let chartGridline = Ink(
        dark: 0x2A2A33,
        light: 0xE2E2E8,
        darkHighContrast: 0x45454F,
        lightHighContrast: 0xC2C2CC
    ).color

    /// A plan threshold drawn across a chart — the HR cap line (FR-1.2), the cadence
    /// target band edges (FR-1.3). Reads as "the rule", distinct from the data.
    static let chartThreshold = Ink(
        dark: 0xC9C9D4,
        light: 0x3A3A44,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    ).color

    /// The run being looked at — the foreground HR curve.
    static let chartSeriesPrimary = Ink(
        dark: 0xE8E8EF,
        light: 0x16161C,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    ).color

    /// Context curves behind the primary one: the other runs in the cross-run drift
    /// overlay (D5/FR-3.3), which stacks many curves and highlights one.
    static let chartSeriesMuted = Ink(
        dark: 0x5A5A66,
        light: 0xA8A8B4,
        darkHighContrast: 0x81818D,
        lightHighContrast: 0x74747F
    ).color

    // MARK: Chrome

    /// The opaque stand-in for Liquid Glass when Reduce Transparency is on (FR-4.5).
    ///
    /// Chrome degrades to this solid fill rather than to nothing, so the tab bar and
    /// floating controls keep their figure/ground separation from the content beneath.
    /// Applied by `View.glassChrome(_:)`; no view should need to name it.
    static let chromeOpaque = Ink(
        dark: 0x17171E,
        light: 0xF7F7FA,
        darkHighContrast: 0x000000,
        lightHighContrast: 0xFFFFFF
    ).color
}
