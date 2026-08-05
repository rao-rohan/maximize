/// A single opaque sRGB color, as its three 8-bit channels.
///
/// This is the platform-free half of a color token: no `UIColor`, no `Color`, just the
/// numbers. `App/DesignSystem/ColorTokens.swift` turns a `ColorToken` into a `UIColor`
/// dynamic provider; `WCAGContrastTests` turns the same `ColorToken` into a contrast
/// ratio. Neither has to agree with a second copy of the palette to do it — see
/// `DesignPalette` for why that matters.
public struct ColorToken: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Total by construction: every `UInt32` names a valid opaque color (the top byte
    /// is simply discarded), so there is no failable parse and therefore nothing to
    /// force-unwrap. Mirrors the convenience the app layer wants when writing a design
    /// value as `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(
            red: UInt8((hex >> 16) & 0xFF),
            green: UInt8((hex >> 8) & 0xFF),
            blue: UInt8(hex & 0xFF)
        )
    }

    /// This colour drawn at `opacity` over `background`, as the opaque colour that
    /// results.
    ///
    /// MAX-084. Contrast is only defined between opaque colours, so a mark drawn at
    /// partial opacity — the drift overlay's recency ramp, most of all — has no
    /// measurable ratio until it is composited. Without this, the faded end of that
    /// ramp is exactly the part of the palette the contrast suite could not see, which
    /// is where its worst value was hiding.
    ///
    /// Straight source-over in sRGB, which is what Core Animation does for an opaque
    /// backdrop. Deliberately *not* done in linear light: the point is to predict what
    /// the framework will actually put on the screen, not what a colour scientist would
    /// prefer it put there.
    public func composited(over background: ColorToken, opacity: Double) -> ColorToken {
        let alpha = Swift.min(Swift.max(opacity, 0), 1)
        func blend(_ foreground: UInt8, _ backdrop: UInt8) -> UInt8 {
            let value = (Double(foreground) * alpha + Double(backdrop) * (1 - alpha)).rounded()
            return UInt8(Swift.min(Swift.max(value, 0), 255))
        }
        return ColorToken(
            red: blend(red, background.red),
            green: blend(green, background.green),
            blue: blend(blue, background.blue)
        )
    }
}
