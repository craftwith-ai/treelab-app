public import SwiftUI
public import TreelabLanes

/// The shape of a status, readable without color: ● working, ◉ waiting for you, ○ stopped,
/// dashed circle outside the counter.
public struct StatusGlyph: View {
    private let status: LaneStatus
    private let size: CGFloat
    private let palette = HUDPalette()

    /// Creates the glyph.
    /// - Parameters:
    ///   - status: the status.
    ///   - size: the diameter in points, 8 by default.
    public init(_ status: LaneStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch status {
            case .working:
                Circle().fill(palette.cyan)
            case .waitingForYou:
                Circle().stroke(palette.amber, lineWidth: max(1, size / 6))
                Circle().fill(palette.amber).padding(size * 0.28)
            case .stopped:
                Circle().stroke(palette.steel, lineWidth: max(1, size / 7))
            case .offCounter:
                Circle().stroke(palette.steel.opacity(0.8), style: StrokeStyle(lineWidth: max(1, size / 7), dash: [2, 2]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The color of a status.
    public static func color(_ status: LaneStatus, _ palette: HUDPalette = HUDPalette()) -> Color {
        switch status {
        case .working: palette.cyan
        case .waitingForYou: palette.amber
        case .stopped, .offCounter: palette.steel
        }
    }
}
