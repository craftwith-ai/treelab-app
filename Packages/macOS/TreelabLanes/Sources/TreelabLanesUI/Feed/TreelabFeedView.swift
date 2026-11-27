public import SwiftUI
public import TreelabLanes

/// The Feed, "File" track of the accepted mock-up: the queue of requests (oldest first) on the
/// left, the current request in large in the middle with what the lane asks and the answers,
/// stopped lanes with "Relaunch", working lanes and lanes outside the counter on the right.
/// Escape or "‹ Lanes" closes it.
public struct TreelabFeedView: View {
    @Bindable private var model: LanesModel
    private let onClose: () -> Void
    private let palette = HUDPalette()
    private let text = LanesText()

    /// Creates the Feed.
    /// - Parameters:
    ///   - model: the lanes model.
    ///   - onClose: closes the Feed (the window also calls ``LanesModel/closeFeed()``).
    public init(model: LanesModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            FeedHeader(model: model, onClose: close)
            Rectangle().fill(palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                FeedQueueColumn(model: model)
                    .frame(width: 250)
                Rectangle().fill(palette.line).frame(width: 1)
                FeedRequestDetail(model: model)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(palette.line).frame(width: 1)
                FeedSideColumn(model: model)
                    .frame(width: 260)
            }
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: close)
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
    }

    private func close() {
        model.closeFeed()
        onClose()
    }
}

/// The Feed's top line: back, title, figures, "Relaunch all · N".
struct FeedHeader: View {
    let model: LanesModel
    let onClose: () -> Void
    private let palette = HUDPalette()
    private let text = LanesText()

    var body: some View {
        let snapshot = model.state.snapshot
        let laneCount = snapshot.projects.reduce(0) { $0 + $1.lanes.count }
        HStack(spacing: 14) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Text(verbatim: "‹ \(text.back)").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.cyan)
                    KeyCap("esc")
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(text.back)
            Text(verbatim: "FEED").font(.system(size: 15, weight: .bold)).tracking(2.5)
            Text(verbatim: "\(text.lanes(laneCount)) · \(text.projects(snapshot.projects.count))")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Spacer()
            figure(.working, text.working(snapshot.total.working))
            figure(.waitingForYou, text.waiting(snapshot.total.waitingForYou))
            figure(.stopped, text.stopped(snapshot.total.stopped))
            let stopped = snapshot.total.stopped
            Button {
                Task { await model.relaunchAll() }
            } label: {
                Text(verbatim: "\(text.relaunchAll) · \(stopped)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(stopped > 0 ? palette.cyan : palette.textSecondary)
                    .background(palette.buttonFill, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.lineBright))
            }
            .buttonStyle(.plain)
            .disabled(stopped == 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(palette.bar)
    }

    private func figure(_ status: LaneStatus, _ label: String) -> some View {
        HStack(spacing: 5) {
            StatusGlyph(status, size: 9)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.textSecondary)
        }
    }
}

/// A key label such as `esc`, `1`, `↵`.
struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(HUDPalette().textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(HUDPalette().lineBright))
    }
}
