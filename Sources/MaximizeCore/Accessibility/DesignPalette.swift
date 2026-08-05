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

    public static let surfaceElevated = Ink(
        dark: 0x16161C,
        light: 0xF5F5F7,
        darkHighContrast: 0x1C1C25,
        lightHighContrast: 0xEDEDF2
    )

    public static let surfaceInset = Ink(
        dark: 0x1F1F27,
        light: 0xEBEBEF,
        darkHighContrast: 0x26262F,
        lightHighContrast: 0xE0E0E6
    )

    public static let separator = Ink(
        dark: 0x2C2C36,
        light: 0xD5D5DC,
        darkHighContrast: 0x4A4A56,
        lightHighContrast: 0xA8A8B4
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

    /// MAX-084: was `dark: 0x2A2A33, light: 0xE2E2E8, darkHighContrast: 0x45454F,
    /// lightHighContrast: 0xC2C2CC`, measuring 1.15 / 1.09 / 1.58 / 1.86 against
    /// `surfaceInset` — the surface every chart in the app plots on. `ColorTokens`
    /// says a gridline "should be visible and never compete with the series"; at
    /// 1.09:1 in light the light value achieved only the second half. The four values
    /// below clear 1.4:1 in the standard appearances and 1.8:1 under Increase
    /// Contrast, which is present without being loud: the series they sit behind
    /// measures 13.42:1 and the threshold rule 9.96:1, so there is no danger of a
    /// gridline competing with either.
    public static let chartGridline = Ink(
        dark: 0x3C3C46,
        light: 0xC6C6D0,
        darkHighContrast: 0x4F4F59,
        lightHighContrast: 0xA5A5AF
    )

    public static let chartThreshold = Ink(
        dark: 0xC9C9D4,
        light: 0x3A3A44,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    )

    public static let chartSeriesPrimary = Ink(
        dark: 0xE8E8EF,
        light: 0x16161C,
        darkHighContrast: 0xFFFFFF,
        lightHighContrast: 0x000000
    )

    /// MAX-084: was `dark: 0x5A5A66, light: 0xA8A8B4, darkHighContrast: 0x81818D,
    /// lightHighContrast: 0x74747F` — 2.41 / 1.98 / 3.90 / 3.51 on `surfaceInset` at
    /// *full* strength, before the recency ramp fades it. The drift overlay then draws
    /// its oldest curve at `HeartRateDriftOverlayData.oldestContextOpacity`, which took
    /// the dark value to 1.25:1 on a 1pt stroke. FR-3.3 is about watching drift flatten
    /// across an interval, and the far end of the interval is the end that was
    /// disappearing. Raised so the base clears WCAG 1.4.11's 3:1 for a graphical object
    /// in the standard appearances (4.5:1 under Increase Contrast) and the whole ramp
    /// sits higher; the ramp's floor moved in the same change.
    public static let chartSeriesMuted = Ink(
        dark: 0x696975,
        light: 0x878793,
        darkHighContrast: 0x8C8C98,
        lightHighContrast: 0x63636F
    )

    /// The region of a chart where the athlete was outside the plan — currently the
    /// time above the HR cap (FR-1.2), which PRD §9 calls the primary easy-run
    /// discipline metric.
    ///
    /// New in MAX-084. It was `chartThreshold.opacity(0.2)` written at the call site,
    /// which composites to 1.62:1 on `surfaceInset` in dark and 1.40:1 in light — the
    /// faintest deliberate mark on a chart that exists to show it, fainter than the
    /// axis labels beside it at 4.80:1. A hierarchy inversion, and an opacity literal
    /// in a view, where no other colour value in this app is allowed to live.
    ///
    /// Two decisions worth recording:
    ///
    /// - **Opaque, not a tint.** A named opaque value is a value `WCAGContrastTests`
    ///   can measure. A call-site opacity is not, which is how 1.62:1 went unnoticed.
    /// - **Neutral, not warm.** The design review preferred a desaturated warm hue so
    ///   the shading would stop sharing its hue with the cap rule. At this lightness a
    ///   warm tilt reads as brown against a blue-black palette, and no one on this
    ///   project can look at it; FR-4.3's saturated budget is also already spent on the
    ///   accent and the three bands. The shading and the rule are separated instead by
    ///   strength and form — a solid region at ~2.1:1 under a dashed 1pt rule at
    ///   9.96:1. If a device check says the hue is worth having, this is one value.
    ///
    /// Bounded above as well as below: the cap line's "Cap N bpm" annotation is drawn
    /// in `chartThreshold` directly over this region, so the fill must stay light
    /// enough to keep that label at AA. It measures 4.78:1 in dark at these values.
    public static let chartExcursion = Ink(
        dark: 0x51515B,
        light: 0xA7A7B1,
        darkHighContrast: 0x65656F,
        lightHighContrast: 0x8A8A94
    )

    // MARK: Chrome

    public static let chromeOpaque = Ink(
        dark: 0x17171E,
        light: 0xF7F7FA,
        darkHighContrast: 0x000000,
        lightHighContrast: 0xFFFFFF
    )
}
