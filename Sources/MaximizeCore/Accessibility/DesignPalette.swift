/// The app's color palette, as plain data.
///
/// **This is the single source of truth for every token value in the design system.**
/// `App/DesignSystem/ColorTokens.swift` reads these constants to build its `UIColor`
/// dynamic providers; `WCAGContrastTests` reads the exact same constants to compute
/// real contrast ratios. Before MAX-070 the palette lived only in `ColorTokens.swift`,
/// which imports `UIKit` and so cannot compile on whatever host runs `swift test` —
/// there was no way to check a color value without a UIKit-capable machine. Moving the
/// numbers here (plain `UInt32`s, no platform import) is what makes contrast
/// verifiable at all: `MaximizeCore` already builds and tests everywhere CI does.
///
/// Do not hand-copy a value from here into `ColorTokens.swift` or anywhere else. If a
/// token needs to change, change it here — `ColorTokens.swift` has nothing left to
/// keep in sync.
public enum DesignPalette {

    /// A color literal in four appearances: the shipped dark and light values, and
    /// their Increase Contrast counterparts. Mirrors `ColorTokens.swift`'s private
    /// `Ink` exactly; that type now just adapts one of these to a `UIColor`.
    public struct Ink: Hashable, Sendable {
        public let dark: ColorToken
        public let light: ColorToken
        public let darkHighContrast: ColorToken
        public let lightHighContrast: ColorToken

        public init(
            dark: UInt32,
            light: UInt32,
            darkHighContrast: UInt32? = nil,
            lightHighContrast: UInt32? = nil
        ) {
            self.dark = ColorToken(hex: dark)
            self.light = ColorToken(hex: light)
            self.darkHighContrast = ColorToken(hex: darkHighContrast ?? dark)
            self.lightHighContrast = ColorToken(hex: lightHighContrast ?? light)
        }
    }

    // MARK: Content surfaces (flat, opaque — FR-4.2)

    public static let surface = Ink(
        dark: 0x0B0B0F,
        light: 0xFFFFFF,
        darkHighContrast: 0x000000,
        lightHighContrast: 0xFFFFFF
    )

    /// MAX-127: was `dark: 0x16161C, light: 0xF5F5F7` (1.09:1 on `surface` in both
    /// appearances — the design review's headline finding). See `surfaceInset` below
    /// for why this token, not that one, absorbs most of each appearance's widen, and
    /// for the accent/`textTertiary` ceiling that bounds both.
    public static let surfaceElevated = Ink(
        dark: 0x1C1C22,
        light: 0xEEEEF0,
        darkHighContrast: 0x26262C,
        lightHighContrast: 0xDEDEE0
    )

    /// MAX-127: widens the ramp MAX-085 deliberately left alone (see `surfaceBorder`
    /// below for why it was left alone, and why this ticket is the one allowed to
    /// touch it). Was `dark: 0x1F1F27, light: 0xEBEBEF` (1.10:1 / 1.09:1 on
    /// `surfaceElevated`).
    ///
    /// ## Why the widen is smaller than it looks like it should be
    ///
    /// This token is two things at once: the well inside a card, *and* the surface
    /// every chart in the app plots on. Both `Color.accent` and `Color.textTertiary`
    /// are drawn directly on it — the plan ring's neighbouring copy, every
    /// axis-adjacent label — and `DesignPaletteContrastTests` holds both to 4.5:1
    /// against it. Neither moved in this ticket: the accent is settled (A7, MAX-084)
    /// and retuning `textTertiary` belongs to a different ticket. That sets a hard
    /// ceiling on how light this surface can get in dark mode, and how dark it can get
    /// in light mode, before one of those two tokens drops below AA against it.
    ///
    /// The ceiling turned out to be much tighter in dark than the design review
    /// guessed. §2.1(a) expected "most of the movement" to be available in dark
    /// because `surface` is already white in light; what it did not account for is
    /// that MAX-070 had already tuned `textTertiary` against *this exact surface* to
    /// clear AA with only a small margin, in dark specifically. The room this ticket
    /// actually had, holding both `accent` and `textTertiary` at ≥4.5:1 with a real
    /// (not hundredths) buffer: **dark `0x1F`→`0x25`, light `0xEB`→`0xE1`** — dark's
    /// window is under half the size light's is, the opposite of the review's guess.
    /// This ticket used most of dark's window (`0x1F`→`0x22`) and about a third of
    /// light's (`0xEB`→`0xE4`), leaving margin (≥0.08:1) on both rather than
    /// re-creating the "hundredths" problem one token over.
    ///
    /// `surfaceElevated` above has no downstream plot surface pinning it — only the
    /// same accent/`textTertiary` floor, cleared more easily from a starting point
    /// already closer to `surface` — so it absorbs the rest of each appearance's
    /// widen.
    public static let surfaceInset = Ink(
        dark: 0x22222A,
        light: 0xE4E4E8,
        darkHighContrast: 0x303038,
        lightHighContrast: 0xD6D6DA
    )

    public static let separator = Ink(
        dark: 0x2C2C36,
        light: 0xD5D5DC,
        darkHighContrast: 0x4A4A56,
        lightHighContrast: 0xA8A8B4
    )

    /// The edge of a card (MAX-085). Drawn as a hairline around `ContentSurface.card`
    /// and nothing else.
    ///
    /// ## Why this token still exists after MAX-127 widened the ramp
    ///
    /// The design review (MAX-082 §2.1) measured `surfaceElevated` on `surface` at
    /// **1.09:1** and offered two fixes: widen the fills, or give cards a border.
    /// MAX-085 shipped the border alone, because `surfaceInset` — the surface every
    /// chart plots on — was tuned to within hundredths of its own floor and widening
    /// it would have re-opened the whole chart palette (see that ticket's history for
    /// the numbers). MAX-127 is the ticket that reopened it on purpose: `surfaceInset`
    /// and `surfaceElevated` are both wider now, and `chartGridline`/`chartExcursion`/
    /// `chartSeriesMuted`/`chartThreshold` are re-tuned to hold real headroom against
    /// the new value rather than hundredths (see `surfaceInset` and the chart tokens
    /// below).
    ///
    /// That widen turned out to be real but modest — `surfaceInset` is boxed in by
    /// `accent` and `textTertiary`'s existing AA margins against it, neither of which
    /// this ticket was free to move (see `surfaceInset`'s comment for the exact
    /// numbers). The fill step alone (`surfaceElevated` on `surface`) reaches
    /// **1.16:1** in both appearances — better than the 1.09:1 the review measured,
    /// still short of Apple's own ~1.23:1 dark step. **The edge is therefore still
    /// doing real work, not redundant load-bearing decoration**: `surfaceElevated` on
    /// `surface` alone would leave a card readable but quiet; the edge is what pushes
    /// the invariant below well past its floor in both appearances rather than resting
    /// on it.
    ///
    /// ## The values
    ///
    /// Dark is unchanged (MAX-085's `0x3A3A45` already cleared the new, lighter
    /// `surfaceElevated` with margin). Light is retuned darker — was `0xC9C9D3` — because
    /// the wider `surfaceElevated` (now closer to white) had pulled the old value's
    /// margin down to 1.43:1, the same "hundredths above the floor" problem this ticket
    /// exists to fix everywhere else. The new light value restores a comparable margin
    /// to dark's.
    ///
    /// **1.51:1 against the card fill in dark, 1.59:1 in light** — both comfortably past
    /// the 1.4:1 the invariant below asks of them, both still stronger than `separator`
    /// (1.23:1 / 1.26:1, so the card's outer boundary still outranks the rules drawn
    /// *inside* it) and weaker than any chart mark or `textTertiary` (4.97:1 / 5.13:1 on
    /// the card), because it is structure rather than data. Against the screen behind
    /// the card it measures 1.75:1 / 1.84:1 — real separation on both sides of the edge,
    /// not just the one the invariant tests.
    ///
    /// Increase Contrast **raises** it rather than flattening it — 2.22:1 and 2.41:1 on
    /// the card, and 3.10:1 / 3.24:1 against the screen behind it, which clears WCAG
    /// 1.4.11's 3:1 for a graphical object. That is the setting's whole point here: the
    /// one surface cue this palette has room for gets stronger, not weaker, for the
    /// people who asked for stronger cues.
    public static let surfaceBorder = Ink(
        dark: 0x3A3A45,
        light: 0xBEBEC8,
        darkHighContrast: 0x5A5A68,
        lightHighContrast: 0x8E8E9A
    )

    // MARK: Text

    public static let textPrimary = Ink(
        dark: 0xF5F5F7,
        light: 0x0B0B0F,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    )

    public static let textSecondary = Ink(
        dark: 0xA0A0AC,
        light: 0x55555F,
        darkHighContrast: 0xC6C6D0,
        lightHighContrast: 0x2E2E38
    )

    /// MAX-070: was `dark: 0x70707C, light: 0x8A8A96`. Both measured below WCAG AA's
    /// 4.5:1 normal-text minimum against every surface level (worst case 3.35:1 dark,
    /// 2.87:1 light, on `surfaceInset`) — see `WCAGContrastTests`. `microLabel`
    /// (axis ticks, timestamps, calendar day numbers) is real informational text at
    /// caption2 size, not large text or decoration, so it doesn't get the looser 3:1
    /// bar. The two values below swap toward each other's territory: `dark` reuses the
    /// old `light` value and `light` is a new, symmetrically darker gray, both chosen
    /// to clear 4.5:1 against `surfaceInset` (the most demanding of the three
    /// surfaces) with a small margin rather than exactly at the line. Increase
    /// Contrast was never affected — `darkHighContrast`/`lightHighContrast` already
    /// cleared AA comfortably (5.5:1+) and are unchanged.
    public static let textTertiary = Ink(
        dark: 0x8A8A96,
        light: 0x63636D,
        darkHighContrast: 0x9C9CA8,
        lightHighContrast: 0x55555F
    )

    public static let textOnSaturatedFill = Ink(
        dark: 0x0B0B0F,
        light: 0xFFFFFF
    )

    // MARK: Accent

    /// Verified (MAX-070): `accent.dark` on `surface.dark` measures **6.06:1**, not
    /// the ~5.9:1 the original MAX-040 comment estimated by eye. Close enough that
    /// nothing needed to change, but it was a guess, not a check — see
    /// `WCAGContrastTests.testAccentOnSurfaceMatchesTheDocumentedClaim`.
    public static let accent = Ink(
        dark: 0x8E7CFF,
        light: 0x5B3FE8,
        darkHighContrast: 0xB3A6FF,
        lightHighContrast: 0x3B22C4
    )

    // MARK: Score bands (FR-4.3)

    /// MAX-070: `light` was `0x248A3D`, measuring 4.40:1 against
    /// `textOnSaturatedFill.light` (white) — just under the 4.5:1 AA minimum for the
    /// text drawn on it (`ScoreBand.rawValue` at `microLabel`/caption2 size in
    /// `DesignSystemGallery`, and wherever the calendar/verdict header draw a band
    /// label per FR-3.2/FR-1.1). Darkened to clear 4.5:1 with margin (5.40:1); still
    /// unambiguously the green band, and the non-text ratio against `surface`/
    /// `surfaceElevated` (also relevant — the band swatch itself must read as
    /// distinct from its background at 3:1) only improved by darkening.
    public static let scoreEffective = Ink(
        dark: 0x30D158,
        light: 0x1E7A35,
        darkHighContrast: 0x5CE07B,
        lightHighContrast: 0x146B2C
    )

    public static let scoreMarginal = Ink(
        dark: 0xFF9F0A,
        light: 0xB25000,
        darkHighContrast: 0xFFB84D,
        lightHighContrast: 0x8C3D00
    )

    public static let scoreIneffective = Ink(
        dark: 0xFF453A,
        light: 0xD70015,
        darkHighContrast: 0xFF7A72,
        lightHighContrast: 0xA80010
    )

    // MARK: Charts

    /// MAX-127: was `dark: 0x3C3C46, light: 0xC6C6D0, darkHighContrast: 0x4F4F59,
    /// lightHighContrast: 0xA5A5AF` — MAX-084's fix, which cleared its own 1.4:1 floor
    /// by **1.43:1 in light**, hundredths rather than headroom. `surfaceInset` moving
    /// under MAX-127 would have sent that value back under water on its own, so this
    /// re-tune is required, not optional, and it goes further than "still passes":
    /// the four values below clear the 1.4:1 floor by **at least 0.19:1 in every
    /// appearance** (1.59:1 dark, 1.60:1 light, 1.89:1 / 1.90:1 under Increase
    /// Contrast) — real margin against a plot surface that can move again in a future
    /// ticket, not a value re-pinned to the line. `ColorTokens` says a gridline
    /// "should be visible and never compete with the series"; the series behind it
    /// still measures 12.9–14.5:1 and the threshold rule 10.9–14.5:1 (`surfaceInset`
    /// varies slightly by appearance now, see that token), so there is no danger of a
    /// gridline competing with either.
    public static let chartGridline = Ink(
        dark: 0x42424C,
        light: 0xB5B5BF,
        darkHighContrast: 0x595963,
        lightHighContrast: 0x9B9BA5
    )

    /// MAX-127: was `dark: 0xC9C9D4, light: 0x3A3A44` (darkHighContrast/
    /// lightHighContrast unchanged — already the appearance's pure white/black, with
    /// nowhere further to go). Retuned outward (lighter in dark, darker in light) so
    /// `chartExcursion`'s cap-label legibility test still clears 4.5:1 with real margin
    /// against the wider `surfaceInset` — see `chartExcursion`'s comment for why the
    /// two tokens had to move together. Still clears the hierarchy ladder under
    /// `chartSeriesPrimary` in every appearance (`DesignPaletteContrastTests`).
    public static let chartThreshold = Ink(
        dark: 0xD6D6E1,
        light: 0x2A2A34,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    )

    public static let chartSeriesPrimary = Ink(
        dark: 0xE8E8EF,
        light: 0x16161C,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    )

    /// MAX-127: was `dark: 0x696975, light: 0x848490, darkHighContrast: 0x8C8C98,
    /// lightHighContrast: 0x63636F` — 2.41:1 at full strength in dark against the old,
    /// narrower `surfaceInset`. Against MAX-127's wider one that fell under the 3:1
    /// graphical-object floor (2.45:1), so this needed to move regardless of headroom;
    /// the four values below clear 3.0:1 by at least 0.28:1 in every appearance (3.28
    /// dark / 3.44 light / 4.47 dark-HC / 4.03 light-HC), and the faded end of the
    /// recency ramp — `chartSeriesMuted` at
    /// `HeartRateDriftOverlayData.oldestContextOpacity` — clears its own 1.5:1 floor by
    /// at least 0.14:1 in every appearance rather than sitting on it.
    public static let chartSeriesMuted = Ink(
        dark: 0x71717D,
        light: 0x787884,
        darkHighContrast: 0x9696A2,
        lightHighContrast: 0x646470
    )

    /// The region of a chart where the athlete was outside the plan — currently the
    /// time above the HR cap (FR-1.2), which PRD §9 calls the primary easy-run
    /// discipline metric.
    ///
    /// MAX-127: was `dark: 0x51515B, light: 0xA7A7B1, darkHighContrast: 0x65656F,
    /// lightHighContrast: 0x8A8A94` — MAX-084's fix, which cleared its own 2.0:1 floor
    /// by **2.09:1 in dark, 2.01:1 in light**: the same "hundredths, not headroom"
    /// problem `chartGridline` had. Re-tuned against the wider `surfaceInset` to clear
    /// 2.0:1 by at least 0.24:1 in every appearance (2.25 dark / 2.31 light / 2.52
    /// dark-HC / 2.42 light-HC).
    ///
    /// **This token and `chartThreshold` had to move together, not independently.**
    /// The cap label ("Cap N bpm") is drawn in `chartThreshold` directly over this
    /// fill, and needs 4.5:1 against it (`testTheCapLabelStaysLegibleOverTheShading`).
    /// With `surfaceInset` wider, pushing `chartExcursion` far enough from it to clear
    /// 2.0:1 with margin pulls it close enough to the old `chartThreshold` that the
    /// label's contrast collapses — at the values that gave `chartExcursion` real
    /// floor headroom, the label fell to ~3.5:1 in both appearances. There is no value
    /// of `chartExcursion` alone that clears both constraints against a stationary
    /// `chartThreshold`; the fill and the rule share the space between `surfaceInset`
    /// and `chartSeriesPrimary`, and widening the plot surface narrows it for both.
    /// `chartThreshold` moved outward instead (see its own comment) to reopen room for
    /// both floors to clear with margin at once — 4.88:1 dark / 4.85:1 light for the
    /// label, still inside `chartSeriesPrimary`'s hierarchy slot in every appearance.
    ///
    /// Two decisions from MAX-084 still hold and were not revisited here:
    ///
    /// - **Opaque, not a tint.** A named opaque value is a value `WCAGContrastTests`
    ///   can measure. A call-site opacity is not — see `CadenceBandView`'s band
    ///   shading, which still writes `Color.chartThreshold.opacity(0.2)` at the call
    ///   site and was out of this ticket's scope to fix; reported separately.
    /// - **Neutral, not warm.** FR-4.3's saturated budget is already spent on the
    ///   accent and the three bands; see MAX-084's history for the full argument.
    public static let chartExcursion = Ink(
        dark: 0x585862,
        light: 0x9696A0,
        darkHighContrast: 0x6C6C76,
        lightHighContrast: 0x888892
    )

    // MARK: Chrome

    public static let chromeOpaque = Ink(
        dark: 0x17171E,
        light: 0xF7F7FA,
        darkHighContrast: 0x000000,
        lightHighContrast: 0xFFFFFF
    )
}
