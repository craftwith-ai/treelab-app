public import SwiftUI
public import TreelabLanes

/// The counter at the top of the sidebar: the number of lanes waiting for the user in large,
/// then working, waiting and stopped; clicking it opens the Feed. Its figures are the sums of
/// the projects' indicators.
public struct LaneCounterCard: View {
    private let model: LanesModel
    private let palette = HUDPalette()
    private let text = LanesText()

    /// The card's height, reserved at the top of the sidebar.
    public static let height: CGFloat = 92

    /// Creates the card.
    /// - Parameter model: the lanes model.
    public init(model: LanesModel) {
        self.model = model
    }

    public var body: some View {
        let total = model.state.snapshot.total
        Button {
            model.openFeed()
        } label: {
            HStack(spacing: 12) {
                gauge(total)
                VStack(alignment: .leading, spacing: 3) {
                    line(.working, text.working(total.working))
                    line(.waitingForYou, text.waiting(total.waitingForYou))
                    line(.stopped, text.stopped(total.stopped))
                    if let problem = model.state.problem {
                        Text(text.problem(problem))
                            .font(.system(size: 9))
                            .foregroundStyle(palette.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(text.problem(problem))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Self.height - 12, maxHeight: Self.height - 12, alignment: .leading)
            .background(palette.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .overlay(HUDCorners(color: palette.lineBright))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text.openFeed)
        .accessibilityLabel(text.openFeed)
        .accessibilityValue([text.waiting(total.waitingForYou), text.working(total.working), text.stopped(total.stopped)].joined(separator: ", "))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func gauge(_ total: StatusCounts) -> some View {
        let counted = Double(max(total.counted, 1))
        let parts: [(LaneStatus, Int)] = [(.working, total.working), (.waitingForYou, total.waitingForYou), (.stopped, total.stopped)]
        var segments: [(status: LaneStatus, from: Double, to: Double)] = []
        var start = 0.0
        for (status, count) in parts where count > 0 {
            segments.append((status, start, start + Double(count) / counted))
            start += Double(count) / counted
        }
        return ZStack {
            Circle().stroke(palette.line, lineWidth: 4)
            ForEach(segments, id: \.status) { segment in
                Circle()
                    .trim(from: segment.from, to: segment.to)
                    .stroke(StatusGlyph.color(segment.status, palette), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(verbatim: "\(total.waitingForYou)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(total.waitingForYou > 0 ? palette.amber : palette.text)
                .monospacedDigit()
        }
        .frame(width: 52, height: 52)
    }

    private func line(_ status: LaneStatus, _ label: String) -> some View {
        HStack(spacing: 6) {
            StatusGlyph(status, size: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
    }
}

/// The four corner brackets of a HUD card.
struct HUDCorners: View {
    let color: Color
    var length: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height, l = length
            Path { path in
                path.move(to: CGPoint(x: 0, y: l)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: l, y: 0))
                path.move(to: CGPoint(x: w - l, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: l))
                path.move(to: CGPoint(x: w, y: h - l)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - l, y: h))
                path.move(to: CGPoint(x: l, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(color, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}
