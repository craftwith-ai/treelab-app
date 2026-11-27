public import SwiftUI
public import TreelabLanes

/// A project's indicators on its sidebar row: `● 1  ◉ 2  ○ 1`, statuses with no lane left out.
public struct StatusIndicators: View {
    private let counts: StatusCounts
    private let palette = HUDPalette()
    private let text = LanesText()

    /// Creates the indicators.
    /// - Parameter counts: the project's lanes per status.
    public init(counts: StatusCounts) {
        self.counts = counts
    }

    public var body: some View {
        HStack(spacing: 6) {
            item(.working, counts.working)
            item(.waitingForYou, counts.waitingForYou)
            item(.stopped, counts.stopped)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.working(counts.working), text.waiting(counts.waitingForYou), text.stopped(counts.stopped)].joined(separator: ", "))
    }

    @ViewBuilder
    private func item(_ status: LaneStatus, _ count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                StatusGlyph(status, size: 7)
                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StatusGlyph.color(status, palette))
            }
        }
    }
}

/// The indicators of the project a folder belongs to; nothing outside lab's projects.
public struct ProjectIndicators: View {
    private let model: LanesModel
    private let directory: String?
    private let palette = HUDPalette()

    /// Creates the view.
    /// - Parameters:
    ///   - model: the lanes model.
    ///   - directory: the workspace's folder.
    public init(model: LanesModel, directory: String?) {
        self.model = model
        self.directory = directory
    }

    public var body: some View {
        if let directory, let location = model.location(forDirectory: directory),
           location.project.counts.counted > 0 {
            // On a dark pill: readable on any row, the selected one (light accent) included.
            StatusIndicators(counts: location.project.counts)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.background.opacity(0.92)))
        }
    }
}
