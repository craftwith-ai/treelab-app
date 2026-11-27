public import SwiftUI
public import TreelabLanes

/// A thin banner above a workspace showing the lane its folder belongs to: name, status,
/// batch and lab's reason. Nothing outside lab's lanes. « Open the Feed » asks the banner's own
/// window to show it (`treelabFeedRequested`).
public struct LaneBanner: View {
    private let model: LanesModel
    private let directory: String?
    @State private var host = HostWindow()
    private let palette = HUDPalette()
    private let text = LanesText()

    /// The banner's height when shown.
    public static let height: CGFloat = 30

    /// Creates the banner.
    /// - Parameters:
    ///   - model: the lanes model.
    ///   - directory: the workspace's current folder.
    public init(model: LanesModel, directory: String?) {
        self.model = model
        self.directory = directory
    }

    public var body: some View {
        if let directory, let location = model.location(forDirectory: directory), let lane = location.lane {
            HStack(spacing: 8) {
                StatusGlyph(lane.status, size: 9)
                Text(verbatim: lane.record.lane)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(text.status(lane.status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StatusGlyph.color(lane.status, palette))
                if !lane.record.batch.isEmpty {
                    Text(verbatim: "· \(lane.record.batch)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                if !lane.record.reason.isEmpty {
                    Text(verbatim: lane.record.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if lane.status == .waitingForYou {
                    Button(text.openFeed) {
                        model.select(lane.id)
                        host.requestFeed()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.amber)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .background(palette.bar)
            .background(HostWindowReader(host: host))
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
    }
}
