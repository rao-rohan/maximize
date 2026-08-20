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

    // MARK: The calendar's cells against *each other* — the gap MAX-084 found

    /// The check this suite was missing, and the reason a 1.02:1 pair shipped.
    ///
    /// Every pairing above measures a token against a *surface*. Nothing measured the
    /// calendar's own cells against one another, so nothing noticed that `scoreEffective`
    /// and `scoreMarginal` are the same square in greyscale — or that in light appearance
    /// all three bands land within 1.04:1 of each other.
    ///
    /// The rule asserted here is the one FR-3.2's calendar actually needs: **no two cells
    /// may be left distinguishable by hue alone, at the size they are actually drawn.** A
    /// pair passes at a given representation if either its fills separate by WCAG 1.4.11's
    /// 3:1 non-text minimum — enough that luminance alone tells them apart — or the two
    /// carry different non-colour channels *for that representation*. A future edit that
    /// collapses two cells onto one mark, or that adds a state or a band without one,
    /// fails here rather than waiting for a reviewer with a colour-blindness filter.
    ///
    /// **Three representations, not one**, since MAX-087 and MAX-180: `ScoreBandMark`
    /// (MAX-084) is what `ScoreCalendarDayCell` actually draws in the day grid (week
    /// and month spans); `ScoreBandHeatmapMark` (MAX-087) is what
    /// `ScoreCalendarHeatmapCell` actually draws at year density, where there is no
    /// room for a corner pip. Testing only the day grid's mark — as this suite did
    /// before MAX-087 — would let the heatmap's channel silently disappear (or
    /// silently collapse two bands onto the same size) with nothing to catch it,
    /// exactly the gap that shipped in MAX-083.
    ///
    /// **The third is not a calendar at all.** `MuscleFatigueMark` (MAX-180) is what
    /// `MuscleMapView` draws for a muscle group's fatigue band, and the rule this test
    /// asserts — no two marks left apart by hue alone — is exactly the rule that
    /// screen needs too. Widening this test to cover it, rather than writing a second
    /// "no hue alone" suite next to it, is what CLAUDE.md asks for directly: the
    /// codebase has one hue-only defect on record (MAX-084's 1.02:1) and one place
    /// that checks for a second.
    ///
    /// **Cells, not bands, since MAX-135**, and that is a widening of the same rule
    /// rather than a second one. Three of the day grid's states draw on the *identical*
    /// red token — `.scored(.ineffective, _)`, `.missed`, and the mixed day — so they
    /// measure 1.00:1 against each other, further apart than nothing and closer than the
    /// 1.02:1 pair that made this test necessary. Their whole separation is the glyph,
    /// and while that mapping lived in the app target nothing could check it. Band-versus-
    /// band coverage is unchanged: the three `.scored` cells below carry the same activity
    /// glyph by construction, so their pairs still have to pass on the pip and the inset.
    private struct DrawnCalendarCell {
        let name: String

        /// The token the cell's reader actually sees behind its mark.
        let fill: DesignPalette.Ink

        /// Everything about the cell that is not a colour value, so it survives greyscale,
        /// every kind of colour vision, and Increase Contrast alike.
        let nonHueChannels: [String]
    }

    /// The fill each state draws on, mirroring `ScoreCalendarPalette` in
    /// `App/Dashboard/ScoreCalendarView.swift`. Restated here rather than read, because
    /// that mapping returns a SwiftUI `Color` and this target cannot import SwiftUI — the
    /// same reason `DesignPalette` exists at all. Exhaustive on purpose: a new
    /// `ScoreCalendarDayState` case fails to compile here until someone has said what it
    /// draws on.
    private func dayGridFill(for state: ScoreCalendarDayState) -> DesignPalette.Ink {
        switch state {
        case .scored(let band, _):
            return ink(for: band)
        // D9's red, shared. `.partiallyMet` takes it because §7.2 colours a mixed day by
        // its worse verdict, and takes *the same token* rather than a ninth one because
        // the budget for a new saturated colour is not there — which is precisely why the
        // pairs below have to pass on shape.
        // `.missedWithUnjudgedSession` (MAX-159) is the fourth on this token: the settled
        // half of the day is a miss, and the day it describes is red for the same reason a
        // whole miss is. Nothing new for this suite to hold, and everything therefore
        // riding on the glyph below.
        case .partiallyMet, .missed, .missedWithUnjudgedSession:
            return DesignPalette.scoreIneffective
        // Drawn with no fill at all in the day grid, so what a reader sees behind its
        // glyph is the calendar card (`isDrawnUnfilledInTheDayGrid`).
        case .forthcoming:
            return DesignPalette.surfaceElevated
        case .awaitingScore, .noVerdict, .convertedRest, .scheduledRest, .unplanned:
            return DesignPalette.surfaceInset
        }
    }

    /// The corner pip, with "no band" and `.unmarked` collapsed onto one value — because
    /// they draw the same nothing, and a test that treated them as different channels
    /// would certify a distinction the reader cannot see.
    private func pipChannel(for state: ScoreCalendarDayState) -> String {
        guard let mark = state.scoredBand?.mark, mark != .unmarked else { return "pip:none" }
        return "pip:\(mark.rawValue)"
    }

    /// One representative cell per state the day grid can draw. The payloads are the
    /// reachable ones: `.awaitingScore` only ever carries a run or a lift and `.noVerdict`
    /// only ever carries something else (`ActivityType.isScoreable` splits them in the
    /// core, MAX-168), which is the invariant that lets those two share a fill.
    private var dayGridCells: [DrawnCalendarCell] {
        let states: [ScoreCalendarDayState] = [
            .scored(band: .effective, activityType: .running),
            .scored(band: .marginal, activityType: .running),
            .scored(band: .ineffective, activityType: .running),
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ),
            .missed(scheduledKind: .easy),
            // MAX-159, one representative and deliberately not two. Its mark is the
            // *state's*, not the recorded activity's, so every payload draws the same cell
            // and a second entry would assert a distinction the design does not make —
            // which is also the point being made: a **run** recorded on a day the lift was
            // skipped draws this ringed "×", not `figure.run`, so it cannot collapse onto
            // `.scored(.ineffective, .running)` above. Which ask was missed, what was
            // recorded, and whether a score is still coming for it live in the spoken
            // sentence (`ScoreCalendarSettledMissCopyTests`).
            .missedWithUnjudgedSession(scheduledKind: .easy, recorded: .traditionalStrengthTraining),
            .awaitingScore(activityType: .running),
            .noVerdict(activityType: .cycling),
            .convertedRest(scheduledKind: .easy),
            .scheduledRest,
            .forthcoming(scheduledKind: .easy),
            .forthcoming(scheduledKind: .lift),
            .unplanned,
        ]
        return states.map { state in
            DrawnCalendarCell(
                name: "\(state)",
                fill: dayGridFill(for: state),
                nonHueChannels: [
                    "glyph:\(ScoreCalendarGlyph.symbolName(for: state))",
                    pipChannel(for: state),
                    state.isDrawnUnfilledInTheDayGrid ? "unfilled" : "filled",
                ]
            )
        }
    }

    /// The year heatmap's cells: no glyph at this size, so the channels are the hollow
    /// outline `.missed` draws and MAX-087's mark size.
    ///
    /// **`.partiallyMet` and `.missedWithUnjudgedSession` are deliberately absent.** Both
    /// draw exactly what `.missed` draws here — see
    /// `ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`, which argues why the collapse
    /// is the honest rendering at ~6pt with no glyph — so listing either would assert a
    /// distinction the design has decided not to make, rather than the rule this test is
    /// about. `ScoreCalendarMixedDayTests` and `ScoreCalendarSettledMissTests` pin the two
    /// collapses themselves.
    private var heatmapCells: [DrawnCalendarCell] {
        let states: [ScoreCalendarDayState] = [
            .scored(band: .effective, activityType: .running),
            .scored(band: .marginal, activityType: .running),
            .scored(band: .ineffective, activityType: .running),
            .missed(scheduledKind: .easy),
            .scheduledRest,
        ]
        return states.map { state in
            let size = state.scoredBand.map { "size:\($0.heatmapMark.rawValue)" } ?? "size:fullFootprint"
            return DrawnCalendarCell(
                name: "\(state)",
                // `.forthcoming` is the one state whose fill differs between the two
                // arrangements (neutral here, no fill in the day grid) and it is not in
                // this list, so the day grid's mapping serves unchanged.
                fill: dayGridFill(for: state),
                nonHueChannels: state.isDrawnHollowAtHeatmapDensity ? ["hollow"] : ["solid", size]
            )
        }
    }

    /// The fill each fatigue band draws behind its mark, mirroring `MuscleMapView`:
    /// `.notLogged` and `.fresh` both draw at `fillFraction == 0`, so what a reader
    /// actually sees is the region's own track (`surfaceInset`); `.light`/`.moderate`/
    /// `.high` show some real area of the fill ink (`chartSeriesPrimary`) and so are
    /// represented by it here. Restated rather than read for `dayGridFill`'s reason:
    /// this target cannot import SwiftUI, so `MuscleMapView`'s actual `Color` tokens
    /// are not reachable from here — this is the same two tokens, named directly from
    /// `DesignPalette`.
    private func muscleMapFill(for band: MuscleFatigueBand) -> DesignPalette.Ink {
        switch band {
        case .notLogged, .fresh:
            return DesignPalette.surfaceInset
        case .light, .moderate, .high:
            return DesignPalette.chartSeriesPrimary
        }
    }

    /// One representative reading per fatigue band, the same five `MuscleFatigueMark`
    /// itself is tested against in `MuscleFatigueMarkTests` — restated here rather than
    /// imported, since a test asserting against its own construction proves nothing:
    /// this is a second, independent statement of what each band draws.
    private func muscleMapCells() throws -> [DrawnCalendarCell] {
        let bands: [(name: String, mark: MuscleFatigueMark)] = [
            ("notLogged", .mark(for: .neverLogged)),
            ("fresh", .mark(for: .fresh(try fixture(fraction: 0.002)))),
            ("light", .mark(for: .fatigued(try fixture(fraction: 0.1)))),
            ("moderate", .mark(for: .fatigued(try fixture(fraction: 0.5)))),
            ("high", .mark(for: .fatigued(try fixture(fraction: 0.9)))),
        ]
        return bands.map { entry in
            DrawnCalendarCell(
                name: "muscleFatigue:\(entry.name)",
                fill: muscleMapFill(for: entry.mark.band),
                nonHueChannels: [
                    "outline:\(entry.mark.outlineIsDashed ? "dashed" : "solid")",
                    "fill:\(entry.mark.fillFraction)",
                    "glyph:\(entry.mark.hasGlyph)",
                ]
            )
        }
    }

    /// A `MuscleFatigue` with an arbitrary but valid payload — every fixture here only
    /// varies `fraction`, which is all `MuscleFatigueBand.of(_:)` reads.
    private func fixture(fraction: Double) throws -> MuscleFatigue {
        try MuscleFatigue(
            group: .chest,
            fraction: fraction,
            lastWorkedAt: Date(timeIntervalSince1970: 0),
            elapsedSeconds: 3_600,
            sessionWeight: 1.0
        )
    }

    func testNoTwoCalendarCellsAreDistinguishedByHueAlone() throws {
        let representations: [(name: String, cells: [DrawnCalendarCell])] = [
            ("day grid — glyph, corner pip (MAX-084), fill/no-fill", dayGridCells),
            ("year heatmap — hollow, inset size (MAX-087)", heatmapCells),
            ("muscle map — outline, fill fraction, glyph (MAX-180)", try muscleMapCells()),
        ]
        for representation in representations {
            for (indexA, cellA) in representation.cells.enumerated() {
                for cellB in representation.cells[(indexA + 1)...] {
                    for appearance in Appearance.allCases {
                        let ratio = WCAGContrast.contrastRatio(
                            appearance.token(cellA.fill),
                            appearance.token(cellB.fill)
                        )
                        let separatedByLuminance = WCAGContrast.meetsAA(ratio, .largeTextOrNonText)
                        let separatedByShape = cellA.nonHueChannels != cellB.nonHueChannels
                        XCTAssertTrue(
                            separatedByLuminance || separatedByShape,
                            """
                            \(cellA.name) and \(cellB.name) measure \
                            \(String(format: "%.2f", ratio)):1 against each other \
                            [\(appearance.rawValue), \(representation.name)] and draw the \
                            same marks \(cellA.nonHueChannels) — nothing but hue tells \
                            them apart.
                            """
                        )
                    }
                }
            }
        }
    }

    /// The four states that share D9's red, stated as its own measurement so a failure
    /// reads as what it is. They are not *nearly* the same colour, they are the same
    /// token — 1.00:1 — so every bit of "ran badly" versus "did not run" versus "did one
    /// of two" versus "missed it and trained anyway" is carried by the glyph, and this is
    /// the assertion that says so.
    ///
    /// **Four since MAX-159**, and the count is the point: each new red state spends none
    /// of the contrast budget and all of the shape budget, so the set of distinct marks
    /// has to grow exactly as fast as the set of red states does.
    func testTheFourRedCalendarStatesShareOneTokenAndAreSeparatedOnlyByGlyph() {
        let red: [ScoreCalendarDayState] = [
            .scored(band: .ineffective, activityType: .running),
            .missed(scheduledKind: .easy),
            .partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ),
            .missedWithUnjudgedSession(scheduledKind: .easy, recorded: .traditionalStrengthTraining),
        ]
        for appearance in Appearance.allCases {
            for state in red {
                XCTAssertEqual(
                    WCAGContrast.contrastRatio(
                        appearance.token(dayGridFill(for: state)),
                        appearance.token(DesignPalette.scoreIneffective)
                    ),
                    1.0,
                    accuracy: 0.001,
                    "\(state) is meant to draw on D9's own red [\(appearance.rawValue)]"
                )
            }
        }
        let glyphs = red.map { ScoreCalendarGlyph.symbolName(for: $0) }
        XCTAssertEqual(
            Set(glyphs).count, red.count,
            "two of the red states draw the same glyph, which leaves them on hue alone: \(glyphs)"
        )
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

    /// MAX-180's analogue, stated the same way: a mark is only a channel if every band
    /// it can take is actually different from every other. `MuscleFatigueMarkTests`
    /// covers this from the type's own side (`testEveryFatigueBandCarriesItsOwnDistinct-
    /// Mark`); this is the second, independent statement `muscleMapCells()` above
    /// already relies on `nonHueChannels` being pairwise distinct for.
    func testEveryFatigueBandCarriesItsOwnMark() throws {
        let signatures = try muscleMapCells().map { $0.nonHueChannels }
        XCTAssertEqual(
            Set(signatures.map { $0.joined(separator: ",") }).count,
            signatures.count,
            "Two fatigue bands share a mark: \(signatures)"
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

    /// MAX-127: the invariant the two tests above were missing. Both `chartGridline`
    /// and `chartExcursion` used to clear their floor by hundredths (1.43:1 against
    /// 1.4, 2.01:1 against 2.0) — a margin indistinguishable, in a diff, from sitting
    /// exactly on the line, and it took `surfaceInset` moving to prove it. This asserts
    /// a buffer above each floor, not just the floor, so a future edit that quietly
    /// walks either token back down cannot pass by accident the way the old ones did.
    /// 0.15 is chosen below every appearance's actual margin (chartGridline's tightest
    /// is 0.19:1 in dark; chartExcursion's is 0.25:1 in dark) with room to spare.
    func testChartGridlineAndExcursionClearTheirFloorsWithRealMargin() {
        let realMargin = 0.15
        assertAtLeast(1.4 + realMargin, DesignPalette.chartGridline, on: plotSurface, "chartGridline (margin)")
        assertAtLeast(2.0 + realMargin, DesignPalette.chartExcursion, on: plotSurface, "chartExcursion (margin)")
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

    // MARK: Surface elevation — MAX-085, widened by MAX-127

    /// The whole of the design review's §2.1 finding, as an invariant that outlives the
    /// particular fix.
    ///
    /// A card has to be *seen* as a card. It can earn that from its fill step, from its
    /// edge, or from both; what it may not do is neither. MAX-085 shipped with the fill
    /// step at 1.09:1 — the number the review measured — carried entirely by the edge.
    /// MAX-127 widened the fill step to ~1.16:1 in every appearance (see
    /// `DesignPalette.surfaceInset` for why that is real but not larger) and re-tuned
    /// `surfaceBorder`'s light value to keep pace, so today both terms clear the floor
    /// on their own and `max` has slack either way. This test is written as `max`
    /// rather than as two separate assertions on purpose: it is the invariant, not the
    /// mechanism, and a future ticket is free to move the mechanism again.
    func testACardSeparatesFromTheScreenBySomething() {
        for appearance in Appearance.allCases {
            let screen = appearance.token(DesignPalette.surface)
            let card = appearance.token(DesignPalette.surfaceElevated)
            let edge = appearance.token(DesignPalette.surfaceBorder)
            let fillStep = WCAGContrast.contrastRatio(card, screen)
            let edgeStep = WCAGContrast.contrastRatio(edge, card)
            XCTAssertGreaterThanOrEqual(
                max(fillStep, edgeStep), 1.4,
                """
                a card is invisible against the screen [\(appearance.rawValue)]: its fill \
                steps \(String(format: "%.2f", fillStep)):1 and its edge \
                \(String(format: "%.2f", edgeStep)):1 — neither reads as a boundary
                """
            )
        }
    }

    /// MAX-127: pins the fill step's own contribution, so `testACardSeparatesFromThe-
    /// ScreenBySomething` passing on `max(fillStep, edgeStep)` can't quietly mean the
    /// fill step drifted back toward MAX-085's 1.09:1 while the edge alone kept the
    /// invariant afloat — which is exactly the state this ticket was asked to leave
    /// behind. 1.12 sits below every appearance's actual value (dark and light both
    /// measure ~1.16:1; Increase Contrast measures higher still) with margin.
    func testTheFillStepAloneIsMeaningfullyWiderThanMAX085Shipped() {
        for appearance in Appearance.allCases {
            let ratio = WCAGContrast.contrastRatio(
                appearance.token(DesignPalette.surfaceElevated),
                appearance.token(DesignPalette.surface)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, 1.12,
                """
                surfaceElevated on surface measures \(String(format: "%.2f", ratio)):1 \
                [\(appearance.rawValue)] — back near MAX-085's 1.09:1, leaning on the \
                edge alone again
                """
            )
        }
    }

    /// The edge against both of the things it lies between. A hairline that reads on the
    /// card but vanishes into the screen behind it is half an edge.
    func testTheCardEdgeIsVisibleFromBothSides() {
        assertAtLeast(
            1.4, DesignPalette.surfaceBorder, on: DesignPalette.surfaceElevated,
            "surfaceBorder on the card"
        )
        assertAtLeast(
            1.4, DesignPalette.surfaceBorder, on: DesignPalette.surface,
            "surfaceBorder on the screen"
        )
    }

    /// A card's outer boundary outranks the rules drawn inside it. Stated as an ordering
    /// rather than as two numbers, for the same reason the chart ladder is: it is the
    /// relationship that matters, and it is what a future edit to either token breaks.
    func testTheCardEdgeOutranksTheSeparatorsInsideIt() {
        for appearance in Appearance.allCases {
            let card = appearance.token(DesignPalette.surfaceElevated)
            let edge = WCAGContrast.contrastRatio(appearance.token(DesignPalette.surfaceBorder), card)
            let rule = WCAGContrast.contrastRatio(appearance.token(DesignPalette.separator), card)
            XCTAssertGreaterThan(
                edge, rule,
                """
                the card edge (\(String(format: "%.2f", edge)):1) is quieter than the \
                separators inside the card (\(String(format: "%.2f", rule)):1) \
                [\(appearance.rawValue)] — the boundary should outrank its contents
                """
            )
        }
    }

    /// And the ceiling from the other side: the edge is structure, so it stays quieter
    /// than the quietest thing a card exists to hold. `textTertiary` is that floor —
    /// axis ticks and timestamps — and an edge louder than the type in the card is an
    /// outline, which is a different and worse design.
    func testTheCardEdgeStaysQuieterThanTheTypeItSurrounds() {
        for appearance in Appearance.allCases {
            let card = appearance.token(DesignPalette.surfaceElevated)
            let edge = WCAGContrast.contrastRatio(appearance.token(DesignPalette.surfaceBorder), card)
            let quietestText = WCAGContrast.contrastRatio(appearance.token(DesignPalette.textTertiary), card)
            XCTAssertLessThan(
                edge, quietestText,
                """
                the card edge (\(String(format: "%.2f", edge)):1) is louder than \
                textTertiary on the same card (\(String(format: "%.2f", quietestText)):1) \
                [\(appearance.rawValue)] — that is an outline, not an edge
                """
            )
        }
    }

    /// FR-4.5 / MAX-070: Increase Contrast must strengthen this app's cues, and the
    /// surface ramp is the one most easily flattened by accident, because its high
    /// contrast variants were written before there was an edge to keep in step with them.
    func testIncreaseContrastStrengthensTheCardEdge() {
        assertRaised(
            DesignPalette.surfaceBorder.darkHighContrast, on: DesignPalette.surfaceElevated.darkHighContrast,
            isAtLeast: DesignPalette.surfaceBorder.dark, on: DesignPalette.surfaceElevated.dark,
            "surfaceBorder on the card [dark]"
        )
        assertRaised(
            DesignPalette.surfaceBorder.lightHighContrast, on: DesignPalette.surfaceElevated.lightHighContrast,
            isAtLeast: DesignPalette.surfaceBorder.light, on: DesignPalette.surfaceElevated.light,
            "surfaceBorder on the card [light]"
        )
    }

    /// Under Increase Contrast the edge stops being a design flourish and becomes a
    /// genuine graphical object, so it is held to WCAG 1.4.11's 3:1 against the screen
    /// it separates the card from — which the standard appearances are not, deliberately.
    func testTheCardEdgeMeetsTheGraphicalObjectMinimumUnderIncreaseContrast() {
        assertAA(
            DesignPalette.surfaceBorder.darkHighContrast, DesignPalette.surface.darkHighContrast,
            .largeTextOrNonText, "surfaceBorder on the screen [dark, Increase Contrast]"
        )
        assertAA(
            DesignPalette.surfaceBorder.lightHighContrast, DesignPalette.surface.lightHighContrast,
            .largeTextOrNonText, "surfaceBorder on the screen [light, Increase Contrast]"
        )
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
