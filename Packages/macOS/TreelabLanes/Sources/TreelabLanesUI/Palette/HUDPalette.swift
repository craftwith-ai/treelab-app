public import SwiftUI

/// The HUD palette of the accepted mock-up (batch 08, tokens of the v3), dark only.
///
/// Contrasts were measured on the mock-up: text ≥ 14.4:1, secondary text 7.2:1, cyan 9.9:1,
/// amber 9.1:1, field and button borders 3.6:1 against ``background``.
public struct HUDPalette: Sendable {
    /// Window background `#03080e`.
    public let background = Color(hudHex: 0x03080E)
    /// Sidebar background `#061019`.
    public let bar = Color(hudHex: 0x061019)
    /// Card background `#0a1826`.
    public let card = Color(hudHex: 0x0A1826)
    /// Raised card `#0f2335`.
    public let cardRaised = Color(hudHex: 0x0F2335)
    /// Button background `#0d2b3d`.
    public let buttonFill = Color(hudHex: 0x0D2B3D)
    /// Thin line `#1b3f55`.
    public let line = Color(hudHex: 0x1B3F55)
    /// Bright line, field and button borders `#3d7fa0`.
    public let lineBright = Color(hudHex: 0x3D7FA0)
    /// Text `#e4f6ff`.
    public let text = Color(hudHex: 0xE4F6FF)
    /// Secondary text `#8fb3c7`.
    public let textSecondary = Color(hudHex: 0x8FB3C7)
    /// Working, links, focus `#4fdcff`.
    public let cyan = Color(hudHex: 0x4FDCFF)
    /// Waiting for you `#ffb547`.
    public let amber = Color(hudHex: 0xFFB547)
    /// Stopped `#7f9cb0`.
    public let steel = Color(hudHex: 0x7F9CB0)
    /// Refusals and errors `#ff8080`.
    public let red = Color(hudHex: 0xFF8080)

    /// Creates the palette.
    public init() {}
}

extension Color {
    /// A color from a `0xRRGGBB` value.
    init(hudHex value: UInt32) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
