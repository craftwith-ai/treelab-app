public import SwiftUI
public import TreelabGinkgo
public import TreelabLanes

/// "Ginkgo" at the bottom of the sidebar: its state on a second line and a red dot while the
/// microphone is open, even after the voice screen is left. A click asks the entry's own window
/// to show the voice screen and opens the conversation (`treelabGinkgoRequested`).
public struct GinkgoBarEntry: View {
    private let model: GinkgoModel
    private let lanes: LanesModel
    @State private var host = HostWindow()
    private let palette = HUDPalette()
    private let text = GinkgoText()

    /// The entry's height, reserved at the bottom of the sidebar.
    public static let height: CGFloat = 50

    /// Creates the entry.
    /// - Parameters:
    ///   - model: Ginkgo's model.
    ///   - lanes: the lanes model, whose projects let a waiting background start go.
    public init(model: GinkgoModel, lanes: LanesModel) {
        self.model = model
        self.lanes = lanes
    }

    public var body: some View {
        let mic = model.isMicrophoneOpen
        let status = text.bar(model.presence, state: model.session.state, mic: model.session.mic)
        Button {
            host.requestGinkgo()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "leaf")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.cyan)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Ginkgo").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.text)
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(mic ? palette.red : palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if mic {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.red)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Self.height - 12, maxHeight: Self.height - 12, alignment: .leading)
            .background(palette.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(mic ? palette.red : palette.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text.openGinkgo)
        .background(HostWindowReader(host: host))
        .accessibilityLabel(text.openGinkgo)
        .accessibilityValue(status)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onChange(of: lanes.state.snapshot.projects.count, initial: true) { model.projectsChanged() }
    }
}
