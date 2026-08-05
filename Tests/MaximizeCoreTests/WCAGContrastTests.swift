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

    /// All three surface levels, not two: MAX-084 resolved A7 by publishing a contrast
    /// table for the accent that includes `surfaceInset`, and a table in a document is
    /// worth what the test under it is worth.
    func testAccentAsTextMeetsNormalTextAA() {
        for surface in [DesignPalette.surface, DesignPalette.surfaceElevated, DesignPalette.surfaceInset] {
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

    // MARK: The plan layer's ring (MAX-105)

    /// The plan ring is a graphical object carrying meaning, so WCAG 1.4.11's 3:1 is
    /// the bar it has to clear — against the calendar card, which is the *only* ground
    /// it is ever drawn on.
    ///
    /// That "only" is the design decision this test pins. The ring sits at the cell's
    /// edge with the state fill inset inside it (`LayoutMetrics.planRingGutter`), so it
    /// never touches a score-band fill. That matters because no ink in this palette
    /// survives both grounds: a near-white stroke measures ~1.2:1 on `scoreEffective`
    /// and a near-black one ~1.2:1 on `surfaceInset`, so a ring drawn *on* the fill
    /// would have been invisible on one state or another whatever colour it was given.
    /// Keeping it on the card is what makes one token — and one measurement — enough.
    func testThePlanRingIsLegibleOnTheCalendarCard() {
        assertAA(
            DesignPalette.accent.dark, DesignPalette.surfaceElevated.dark,
            .largeTextOrNonText, "plan ring on the calendar card [dark]"
        )
        assertAA(
            DesignPalette.accent.light, DesignPalette.surfaceElevated.light,
            .largeTextOrNonText, "plan ring on the calendar card [light]"
        )
        assertAA(
            DesignPalette.accent.darkHighContrast, DesignPalette.surfaceElevated.darkHighContrast,
            .largeTextOrNonText, "plan ring on the calendar card [dark, Increase Contrast]"
        )
        assertAA(
            DesignPalette.accent.lightHighContrast, DesignPalette.surfaceElevated.lightHighContrast,
            .largeTextOrNonText, "plan ring on the calendar card [light, Increase Contrast]"
        )
    }

    /// Increase Contrast must never make the ring *harder* to see — the same property
    /// `testIncreaseContrastNeverLowersAChartMarksContrast` asserts for chart marks.
    /// The ring also thickens under that setting
    /// (`LayoutMetrics.planRingWidthIncreasedContrast`), which is the half of contrast
    /// this suite cannot measure.
    func testIncreaseContrastNeverLowersThePlanRingsContrast() {
        assertRaised(
            DesignPalette.accent.darkHighContrast, on: DesignPalette.surfaceElevated.darkHighContrast,
            isAtLeast: DesignPalette.accent.dark, on: DesignPalette.surfaceElevated.dark,
            "plan ring [dark]"
        )
        assertRaised(
            DesignPalette.accent.lightHighContrast, on: DesignPalette.surfaceElevated.lightHighContrast,
            isAtLeast: DesignPalette.accent.light, on: DesignPalette.surfaceElevated.light,
            "plan ring [light]"
        )
    }

    // MARK: Score bands against *each other* — the gap MAX-084 found

    /// The check this suite was missing, and the reason a 1.02:1 pair shipped.
    ///
    /// Every pairing above measures a token against a *surface*. Nothing measured the
    /// three bands against one another, so nothing noticed that `scoreEffective` and
    /// `scoreMarginal` are the same square in greyscale — or that in light appearance
    /// all three bands land within 1.04:1 of each other.
    ///
    /// The rule asserted here is the one FR-3.2's calendar actually needs: **no two
    /// bands may be left distinguishable by hue alone, at the size they are actually
    /// drawn.** A pair passes at a given representation if either its fills separate by
    /// WCAG 1.4.11's 3:1 non-text minimum — enough that luminance alone tells them apart
    /// — or the two carry different non-colour marks *for that representation*. Today
    /// every pair passes on its mark, in every representation and every appearance;
    /// that is precisely the point of the mark. A future edit that collapses two bands
    /// onto one mark, or that adds a fourth band without one, fails here rather than
    /// waiting for a reviewer with a colour-blindness filter.
    ///
    /// **Two representations, not one**, since MAX-087: `ScoreBandMark` (MAX-084) is
    /// what `ScoreCalendarDayCell` actually draws in the day grid (week and month
    /// spans); `ScoreBandHeatmapMark` (MAX-087) is what `ScoreCalendarHeatmapCell`
    /// actually draws at year density, where there is no room for a corner pip. Testing
    /// only the day grid's mark here — as this suite did before MAX-087 — would let the
    /// heatmap's channel silently disappear (or silently collapse two bands onto the
    /// same size) with nothing to catch it, exactly the gap that shipped in MAX-083 and
    /// this ticket exists to close.
    private var representations: [(name: String, marksDiffer: (ScoreBand, ScoreBand) -> Bool)] {
        [
            ("day grid, corner pip (MAX-084)", { $0.mark != $1.mark }),
            ("year heatmap, inset size (MAX-087)", { $0.heatmapMark != $1.heatmapMark }),
        ]
    }

    func testNoTwoScoreBandsAreDistinguishedByHueAlone() {
        let bands = ScoreBand.allCases
        for representation in representations {
            for (indexA, bandA) in bands.enumerated() {
                for bandB in bands[(indexA + 1)...] {
                    let inkA = ink(for: bandA)
                    let inkB = ink(for: bandB)
                    for appearance in Appearance.allCases {
                        let ratio = WCAGContrast.contrastRatio(
                            appearance.token(inkA),
                            appearance.token(inkB)
                        )
                        let separatedByLuminance = WCAGContrast.meetsAA(ratio, .largeTextOrNonText)
                        let separatedByShape = representation.marksDiffer(bandA, bandB)
                        XCTAssertTrue(
                            separatedByLuminance || separatedByShape,
                            """
                            \(bandA.rawValue) and \(bandB.rawValue) measure \
                            \(String(format: "%.2f", ratio)):1 against each other \
                            [\(appearance.rawValue), \(representation.name)] — \
                            nothing but hue tells them apart.
                            """
                        )
                    }
                }
            }
        }
    }

    /// A mark is only a channel if the three values it can take are actually
    /// different — stated separately from the rule above, for both representations, so
    /// a regression reads as "two bands share a mark" rather than as a contrast
    /// failure.
    func testEveryScoreBandCarriesItsOwnMark() {
        let marks = ScoreBand.allCases.map(\.mark)
        XCTAssertEqual(
            Set(marks).count,
            ScoreBand.allCases.count,
            "Two bands share a corner-pip mark: \(marks.map(\.rawValue))"
        )

        let heatmapMarks = ScoreBand.allCases.map(\.heatmapMark)
        XCTAssertEqual(
            Set(heatmapMarks).count,
            ScoreBand.allCases.count,
            "Two bands share a heatmap mark: \(heatmapMarks.map(\.rawValue))"
        )
    }

    /// The mark is drawn in `textOnSaturatedFill` on the band fill, at pip scale — a
    /// small graphical object, so WCAG 1.4.11's 3:1 applies to it rather than 4.5:1.
    /// It clears the text bar anyway in every appearance; asserted at the bar it
    /// actually has to meet, with the real one recorded in the message.
    func testScoreBandMarkIsLegibleOnItsOwnFill() {
        for band in scoreBands {
            assertAA(
                DesignPalette.textOnSaturatedFill.dark, band.ink.dark, .largeTextOrNonText,
                "band mark on \(band.name) [dark]"
            )
            assertAA(
                DesignPalette.textOnSaturatedFill.light, band.ink.light, .largeTextOrNonText,
                "band mark on \(band.name) [light]"
            )
            assertAA(
                DesignPalette.textOnSaturatedFill.dark, band.ink.darkHighContrast, .largeTextOrNonText,
                "band mark on \(band.name) [dark, Increase Contrast]"
            )
            assertAA(
                DesignPalette.textOnSaturatedFill.light, band.ink.lightHighContrast, .largeTextOrNonText,
                "band mark on \(band.name) [light, Increase Contrast]"
            )
        }
    }

    // MARK: Chart marks — the other half of MAX-084

    /// Every chart in the app plots inside `.contentSurface(.inset)`, so this is the
    /// ground every mark below is measured against.
    private let plotSurface = DesignPalette.surfaceInset

    /// WCAG has no criterion for a gridline, so this asserts the bar the design system
    /// set for itself: `ColorTokens` says a gridline "should be visible and never
    /// compete with the series". 1.4:1 is the floor for the first half. The second half
    /// is asserted by the ladder test below, not by a ceiling here.
    func testChartGridlinesAreVisibleOnThePlotSurface() {
        assertAtLeast(1.4, DesignPalette.chartGridline, on: plotSurface, "chartGridline")
    }

    /// The time-above-cap shading (FR-1.2). A large filled region, so it does not need
    /// 3:1 — the review that found this put the right range at 2.0–2.5:1, loud enough to
    /// read as a mark rather than as background, quiet enough not to shout over a whole
    /// region of the plot.
    func testTimeAboveCapShadingReadsAsAMarkNotABackground() {
        assertAtLeast(2.0, DesignPalette.chartExcursion, on: plotSurface, "chartExcursion")
    }

    /// The constraint from the other direction, and the one that stops a future edit
    /// from simply making the shading darker until it wins: `HRCurveView` annotates the
    /// cap rule with "Cap N bpm" in `chartThreshold`, positioned directly above the cap
    /// line — which is inside the shaded region. That label is normal text and has to
    /// stay at AA where it crosses the fill.
    func testTheCapLabelStaysLegibleOverTheShading() {
        for appearance in Appearance.allCases {
            assertAA(
                appearance.token(DesignPalette.chartThreshold),
                appearance.token(DesignPalette.chartExcursion),
                .normalText,
                "cap label over the time-above-cap shading [\(appearance.rawValue)]"
            )
        }
    }

    /// A drift context curve is a graphical object conveying information, so WCAG
    /// 1.4.11's 3:1 is the right bar for it at full strength.
    func testContextCurvesClearTheGraphicalObjectMinimum() {
        assertAtLeast(3.0, DesignPalette.chartSeriesMuted, on: plotSurface, "chartSeriesMuted")
    }

    /// The value MAX-084 was pointed at: the *faded* end of the recency ramp, which is
    /// where the palette's worst number was hiding because nothing composited it.
    ///
    /// 1.5:1 rather than 3:1, deliberately. The ramp exists to make recency the visual
    /// axis (`HeartRateDriftOverlayData.contextOpacity`), and a floor high enough to
    /// satisfy 1.4.11 would flatten it into twelve identical lines — trading one
    /// legibility problem for a worse one. This asserts the curve is present, and the
    /// constant's own documentation records that the residual problem is its 1pt
    /// stroke, which no colour value can fix.
    func testTheOldestDriftCurveClearsTheVisibilityFloor() {
        for appearance in Appearance.allCases {
            let surface = appearance.token(plotSurface)
            let composited = appearance.token(DesignPalette.chartSeriesMuted)
                .composited(over: surface, opacity: HeartRateDriftOverlayData.oldestContextOpacity)
            let ratio = WCAGContrast.contrastRatio(composited, surface)
            XCTAssertGreaterThanOrEqual(
                ratio, 1.5,
                """
                the oldest stacked drift curve measures \(String(format: "%.2f", ratio)):1 \
                on the plot surface [\(appearance.rawValue)] — below the floor its own \
                documentation claims for it
                """
            )
        }
    }

    /// The hierarchy the chart tokens are supposed to encode, asserted as an ordering
    /// rather than as five separate numbers: background structure, then the region
    /// marks, then the context series, then the rule, then the run being looked at.
    ///
    /// This is what "never compete with the series" means operationally, and it is the
    /// check that would have caught the time-above-cap shading being drawn more faintly
    /// than the gridlines' near neighbours. Non-strict at the top because under
    /// Increase Contrast `chartThreshold` and `chartSeriesPrimary` both resolve to pure
    /// black or pure white — at that point the appearance has run out of headroom, and
    /// that is the correct behaviour rather than a violation.
    func testTheChartTokensFormAHierarchyInEveryAppearance() {
        let ladder: [(name: String, ink: DesignPalette.Ink)] = [
            ("chartGridline", DesignPalette.chartGridline),
            ("chartExcursion", DesignPalette.chartExcursion),
            ("chartSeriesMuted", DesignPalette.chartSeriesMuted),
            ("chartThreshold", DesignPalette.chartThreshold),
            ("chartSeriesPrimary", DesignPalette.chartSeriesPrimary),
        ]
        for appearance in Appearance.allCases {
            let surface = appearance.token(plotSurface)
            let ratios = ladder.map {
                WCAGContrast.contrastRatio(appearance.token($0.ink), surface)
            }
            for index in 1..<ratios.count {
                XCTAssertGreaterThanOrEqual(
                    ratios[index], ratios[index - 1],
                    """
                    \(ladder[index].name) (\(String(format: "%.2f", ratios[index])):1) is \
                    quieter than \(ladder[index - 1].name) \
                    (\(String(format: "%.2f", ratios[index - 1])):1) on the plot surface \
                    [\(appearance.rawValue)]
                    """
                )
            }
        }
    }

    /// Increase Contrast must never *reduce* contrast. Cheap to assert, and it is the
    /// invariant most easily broken by editing one variant of a token and not the
    /// other three.
    func testIncreaseContrastNeverLowersAChartMarksContrast() {
        let marks: [(name: String, ink: DesignPalette.Ink)] = [
            ("chartGridline", DesignPalette.chartGridline),
            ("chartExcursion", DesignPalette.chartExcursion),
            ("chartSeriesMuted", DesignPalette.chartSeriesMuted),
            ("chartThreshold", DesignPalette.chartThreshold),
            ("chartSeriesPrimary", DesignPalette.chartSeriesPrimary),
        ]
        for mark in marks {
            assertRaised(
                mark.ink.darkHighContrast, on: plotSurface.darkHighContrast,
                isAtLeast: mark.ink.dark, on: plotSurface.dark,
                "\(mark.name) [dark]"
            )
            assertRaised(
                mark.ink.lightHighContrast, on: plotSurface.lightHighContrast,
                isAtLeast: mark.ink.light, on: plotSurface.light,
                "\(mark.name) [light]"
            )
        }
    }

    private func ink(for band: ScoreBand) -> DesignPalette.Ink {
        switch band {
        case .effective: return DesignPalette.scoreEffective
        case .marginal: return DesignPalette.scoreMarginal
        case .ineffective: return DesignPalette.scoreIneffective
        }
    }

    // MARK: Helper

    /// The four resolutions of every `Ink`, so a check can be written once and run
    /// against all of them — CLAUDE.md's rule that a fix which works in dark and breaks
    /// light is not a fix.
    enum Appearance: String, CaseIterable {
        case dark
        case light
        case darkHighContrast
        case lightHighContrast

        func token(_ ink: DesignPalette.Ink) -> ColorToken {
            switch self {
            case .dark: return ink.dark
            case .light: return ink.light
            case .darkHighContrast: return ink.darkHighContrast
            case .lightHighContrast: return ink.lightHighContrast
            }
        }
    }

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

    /// A floor that is this design system's own, not WCAG's — gridlines and large
    /// filled regions have no criterion in the spec, and pretending 3:1 or 4.5:1 is the
    /// bar for them would mean either an unmeetable test or a very loud chart. Asserted
    /// in all four appearances at once, since the failure mode being guarded against is
    /// a token edited in one variant only.
    private func assertAtLeast(
        _ floor: Double,
        _ ink: DesignPalette.Ink,
        on background: DesignPalette.Ink,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for appearance in Appearance.allCases {
            let ratio = WCAGContrast.contrastRatio(
                appearance.token(ink),
                appearance.token(background)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, floor,
                """
                \(label) measures \(String(format: "%.2f", ratio)):1 \
                [\(appearance.rawValue)], below the \(floor):1 this design system \
                requires of it
                """,
                file: file,
                line: line
            )
        }
    }

    private func assertRaised(
        _ highContrast: ColorToken,
        on highContrastBackground: ColorToken,
        isAtLeast standard: ColorToken,
        on standardBackground: ColorToken,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let raised = WCAGContrast.contrastRatio(highContrast, highContrastBackground)
        let base = WCAGContrast.contrastRatio(standard, standardBackground)
        XCTAssertGreaterThanOrEqual(
            raised, base,
            """
            \(label) drops from \(String(format: "%.2f", base)):1 to \
            \(String(format: "%.2f", raised)):1 under Increase Contrast
            """,
            file: file,
            line: line
        )
    }
}
