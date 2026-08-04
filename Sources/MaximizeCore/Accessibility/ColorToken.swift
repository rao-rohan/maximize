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
}
