import Foundation
import XCTest
@testable import MaximizeCore

/// WCAG 2.x math, verified against the actual design palette (MAX-070).
///
/// Two jobs, kept separate. `WCAGContrastMathTests` checks the arithmetic itself
/// against reference values from outside this app's palette — known black/white and
/// mid-gray cases — so a bug in `WCAGContrast` cannot hide behind a palette that
/// happens to pass anyway. `DesignPaletteContrastTests` then points that verified
/// arithmetic at `DesignPalette`'s real token values and asserts the WCAG AA minimum
/// each pairing actually needs. This is not a tautology: the thresholds are fixed
/// constants from the spec (4.5 / 3.0), the palette values come from `DesignPalette`
/// (not restated here), and a future edit to either one that drops a ratio below its
/// threshold fails this suite — in CI, with no device or simulator required.
final class WCAGContrastMathTests: XCTestCase {

    func testBlackOnWhiteIsMaximumContrast() {
        let ratio = WCAGContrast.contrastRatio(ColorToken(hex: 0x000000), ColorToken(hex: 0xFFFFFF))
        XCTAssertEqual(ratio, 21.0, accuracy: 0.001)
    }

    func testIdenticalColorsHaveNoContrast() {
        let gray = ColorToken(hex: 0x808080)
        XCTAssertEqual(WCAGContrast.contrastRatio(gray, gray), 1.0, accuracy: 0.001)
    }

    func testContrastRatioIsSymmetric() {
        let a = ColorToken(hex: 0x30D158)
        let b = ColorToken(hex: 0x0B0B0F)
        XCTAssertEqual(
            WCAGContrast.contrastRatio(a, b),
            WCAGContrast.contrastRatio(b, a),
            accuracy: 0.0001
        )
    }

    /// `#767676` on white is a widely-cited worked example (it is, deliberately, the
    /// darkest gray that still clears 4.5:1 on white) — a reference point independent
    /// of this app's palette that pins the formula itself, not just its internal
    /// self-consistency.
    func testKnownReferencePair_MidGrayOnWhiteIsRightAtAA() {
        let ratio = WCAGContrast.contrastRatio(ColorToken(hex: 0x767676), ColorToken(hex: 0xFFFFFF))
        XCTAssertEqual(ratio, 4.54, accuracy: 0.02)
    }

    func testMeetsAARespectsTheThresholdBoundary() {
        XCTAssertTrue(WCAGContrast.meetsAA(4.5, .normalText))
        XCTAssertFalse(WCAGContrast.meetsAA(4.49, .normalText))
        XCTAssertTrue(WCAGContrast.meetsAA(3.0, .largeTextOrNonText))
        XCTAssertFalse(WCAGContrast.meetsAA(2.99, .largeTextOrNonText))
    }
}

/// Contrast ratios for every token pairing MAX-070 was asked to check: text on each
/// surface level, the accent as text, and the three score bands. Each case names the
/// real usage it stands in for and the threshold that usage requires, so a failure
/// reads as "X no longer meets the bar Y needs" rather than an opaque number mismatch.
final class DesignPaletteContrastTests: XCTestCase {

    // MARK: Text on surface — normal text everywhere in the type scale (4.5:1)

    private let surfaces: [(name: String, ink: DesignPalette.Ink)] = [
        ("surface", DesignPalette.surface),
        ("surfaceElevated", DesignPalette.surfaceElevated),
        ("surfaceInset", DesignPalette.surfaceInset),
    ]

    private let textLevels: [(name: String, ink: DesignPalette.Ink)] = [
        ("textPrimary", DesignPalette.textPrimary),
        ("textSecondary", DesignPalette.textSecondary),
        ("textTertiary", DesignPalette.textTertiary),
    ]

    /// Every text level, on every surface, in both appearances, in both standard and
    /// Increase Contrast mode — 36 pairings, all held to the 4.5:1 normal-text
    /// minimum. `textTertiary` is the one MAX-070 found failing here (see
    /// `DesignPalette` for what changed and why); everything else was already clear.
    func testTextOnSurfaceMeetsNormalTextAA() {
        for text in textLevels {
            for surface in surfaces {
                assertAA(text.ink.dark, surface.ink.dark, .normalText, "\(text.name) on \(surface.name) [dark]")
                assertAA(text.ink.light, surface.ink.light, .normalText, "\(text.name) on \(surface.name) [light]")
                assertAA(
                    text.ink.darkHighContrast, surface.ink.darkHighContrast, .normalText,
                    "\(text.name) on \(surface.name) [dark, Increase Contrast]"
                )
                assertAA(
                    text.ink.lightHighContrast, surface.ink.lightHighContrast, .normalText,
                    "\(text.name) on \(surface.name) [light, Increase Contrast]"
                )
            }
        }
    }

    // MARK: Accent, as text (the comment in ColorTokens.swift claims it is legible as text)

    func testAccentOnSurfaceMatchesTheDocumentedClaim() {
        // MAX-040's comment estimated ~5.9:1 in dark. Verified value, held in place so
        // a future palette edit that quietly drifts the accent gets caught here rather
        // than by the next person reading the comment and trusting it.
        let ratio = WCAGContrast.contrastRatio(DesignPalette.accent.dark, DesignPalette.surface.dark)
        XCTAssertEqual(ratio, 6.06, accuracy: 0.01)
        XCTAssertTrue(WCAGContrast.meetsAA(ratio, .normalText))
    }

    func testAccentAsTextMeetsNormalTextAA() {
        for surface in [DesignPalette.surface, DesignPalette.surfaceElevated] {
            assertAA(DesignPalette.accent.dark, surface.dark, .normalText, "accent on surface [dark]")
            assertAA(DesignPalette.accent.light, surface.light, .normalText, "accent on surface [light]")
            assertAA(
                DesignPalette.accent.darkHighContrast, surface.darkHighContrast, .normalText,
                "accent on surface [dark, Increase Contrast]"
            )
            assertAA(
                DesignPalette.accent.lightHighContrast, surface.lightHighContrast, .normalText,
                "accent on surface [light, Increase Contrast]"
            )
        }
    }

    // MARK: Score bands — text drawn on the fill, and the fill against its surroundings

    private let scoreBands: [(name: String, ink: DesignPalette.Ink)] = [
        ("scoreEffective", DesignPalette.scoreEffective),
        ("scoreMarginal", DesignPalette.scoreMarginal),
        ("scoreIneffective", DesignPalette.scoreIneffective),
    ]

    /// `textOnSaturatedFill` drawn on a band fill — the pairing `DesignSystemGallery`
    /// actually renders (`ScoreBand.rawValue` at `microLabel`/caption2, i.e. normal
    /// text). `scoreEffective` in light was the one that failed here (4.40:1); see
    /// `DesignPalette` for the fix.
    func testTextOnScoreBandMeetsNormalTextAA() {
        for band in scoreBands {
            assertAA(
                DesignPalette.textOnSaturatedFill.dark, band.ink.dark, .normalText,
                "textOnSaturatedFill on \(band.name) [dark]"
            )
            assertAA(
                DesignPalette.textOnSaturatedFill.light, band.ink.light, .normalText,
                "textOnSaturatedFill on \(band.name) [light]"
            )
        }
    }

    /// The band swatch itself against the surface it sits on — a non-text UI
    /// component that must still read as distinct from its background (3:1).
    func testScoreBandAgainstSurroundingSurfaceMeetsNonTextAA() {
        for band in scoreBands {
            for surface in [DesignPalette.surface, DesignPalette.surfaceElevated] {
                assertAA(
                    band.ink.dark, surface.dark, .largeTextOrNonText,
                    "\(band.name) on surface [dark]"
                )
                assertAA(
                    band.ink.light, surface.light, .largeTextOrNonText,
                    "\(band.name) on surface [light]"
                )
            }
        }
    }

    // MARK: Helper

    private func assertAA(
        _ foreground: ColorToken,
        _ background: ColorToken,
        _ threshold: WCAGContrast.AAThreshold,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = WCAGContrast.contrastRatio(foreground, background)
        XCTAssertTrue(
            WCAGContrast.meetsAA(ratio, threshold),
            "\(label) measures \(String(format: "%.2f", ratio)):1, below the \(threshold.rawValue):1 AA minimum",
            file: file,
            line: line
        )
    }
}
