import Foundation

/// WCAG 2.x relative luminance and contrast ratio — the arithmetic half of
/// accessibility, and the only half CI can actually check (MAX-070). Nothing in this
/// pipeline can render a screen and look at it; this is what it can do instead.
///
/// Formulas are WCAG 2.1 §1.4.3 / Appendix G, verbatim:
/// <https://www.w3.org/WAI/GL/wiki/Relative_luminance>
public enum WCAGContrast {

    /// Relative luminance of a color, on a 0 (black) – 1 (white) scale.
    public static func relativeLuminance(of token: ColorToken) -> Double {
        func linearize(_ channel: UInt8) -> Double {
            let s = Double(channel) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(token.red)
            + 0.7152 * linearize(token.green)
            + 0.0722 * linearize(token.blue)
    }

    /// The contrast ratio between two colors, from 1:1 (identical) to 21:1
    /// (black on white). Symmetric in its two arguments — WCAG defines the ratio
    /// between "lighter" and "darker", not "foreground" and "background".
    public static func contrastRatio(_ a: ColorToken, _ b: ColorToken) -> Double {
        let luminanceA = relativeLuminance(of: a)
        let luminanceB = relativeLuminance(of: b)
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG 2.1 AA minimums (§1.4.3, §1.4.11). "Large text" is 18pt+ regular or
    /// 14pt+ bold; everything else — including every label in this design system's
    /// type scale below `screenTitle` — is normal text.
    public enum AAThreshold: Double {
        case normalText = 4.5
        case largeTextOrNonText = 3.0
    }

    /// Whether `ratio` clears the given AA threshold.
    public static func meetsAA(_ ratio: Double, _ threshold: AAThreshold) -> Bool {
        ratio >= threshold.rawValue
    }
}
