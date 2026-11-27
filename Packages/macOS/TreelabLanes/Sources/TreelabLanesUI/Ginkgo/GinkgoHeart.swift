import AppKit
import SwiftUI
import TreelabGinkgo

/// Ginkgo's heart, drawn with Core Animation layers that only change when a voice level arrives:
/// no timer and no continuous animation, so a silent heart costs nothing. Its movements follow the
/// voice: the 64 bars around the core grow with the person's voice, the waves and the glow of the
/// core with Ginkgo's, and both rings turn by the amount of voice heard. Levels are observed here,
/// outside SwiftUI, so they never redraw the rest of the screen.
struct GinkgoHeart: NSViewRepresentable {
    let levels: GinkgoLevels
    let state: GinkgoVoiceState

    func makeNSView(context: Context) -> GinkgoHeartView {
        let view = GinkgoHeartView()
        context.coordinator.token = levels.observe { [weak view] input, output in view?.show(input: input, output: output) }
        view.show(input: levels.input, output: levels.output)
        return view
    }

    func updateNSView(_ view: GinkgoHeartView, context: Context) {
        view.state = state
    }

    static func dismantleNSView(_ view: GinkgoHeartView, coordinator: Coordinator) {
        if let token = coordinator.token { coordinator.levels.stopObserving(token) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(levels: levels) }

    final class Coordinator {
        let levels: GinkgoLevels
        var token: Int?
        init(levels: GinkgoLevels) { self.levels = levels }
    }
}

/// The layers of the heart, in the mock-up's 400-point box scaled to the view.
final class GinkgoHeartView: NSView {
    private let palette = GinkgoHeartView.colors
    private let box = CALayer()
    private let outerRing = CALayer()
    private let ticks = CALayer()
    private var bars: [CALayer] = []
    private var waves: [CAShapeLayer] = []
    private let thinking = CAShapeLayer()
    private let core = CALayer()
    private let coreDisc = CAShapeLayer()
    private var turn: CGFloat = 0
    /// Bars' rest height, as a fraction of their full height.
    private static let rest: CGFloat = 0.22
    private static let pattern: [CGFloat] = [0.62, 0.9, 0.45, 1, 0.7, 0.38, 0.85, 0.55]

    var state: GinkgoVoiceState = .closed {
        didSet { if state != oldValue { applyState() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(box)
        box.isGeometryFlipped = true
        box.bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        buildOuterRing()
        buildTicks()
        buildBars()
        buildWaves()
        buildCore()
        applyState()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        box.position = CGPoint(x: bounds.midX, y: bounds.midY)
        box.setAffineTransform(CGAffineTransform(scaleX: side / 400, y: side / 400))
        CATransaction.commit()
    }

    /// Shows a new level: the only moment the heart changes.
    func show(input: Double, output: Double) {
        let input = CGFloat(input), output = CGFloat(output)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.07)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (index, bar) in bars.enumerated() {
            let shape = Self.pattern[index % Self.pattern.count]
            bar.transform = CATransform3DMakeScale(1, Self.rest + (1 - Self.rest) * min(1, input * (0.55 + 0.6 * shape)), 1)
        }
        for (index, wave) in waves.enumerated() {
            let scale = 1 + output * (0.25 + 0.25 * CGFloat(index))
            wave.transform = CATransform3DMakeScale(scale, scale, 1)
            wave.opacity = Float(output * (0.8 - 0.22 * CGFloat(index)))
        }
        core.shadowRadius = 6 + 16 * output
        core.shadowOpacity = Float(0.35 + 0.5 * output)
        turn += (input + output) * 0.035
        outerRing.transform = CATransform3DMakeRotation(turn, 0, 0, 1)
        ticks.transform = CATransform3DMakeRotation(-turn * 0.6, 0, 0, 1)
        CATransaction.commit()
    }

    private func applyState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let closed = !state.isConversation
        core.opacity = closed ? 0.5 : 1
        bars.forEach { $0.opacity = closed ? 0.4 : 1 }
        thinking.opacity = state == .thinking ? 1 : 0
        CATransaction.commit()
    }

    // MARK: Building

    private func circle(_ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: 200 - radius, y: 200 - radius, width: 2 * radius, height: 2 * radius), transform: nil)
    }

    private func shape(_ path: CGPath, stroke: NSColor?, width: CGFloat = 1, fill: NSColor? = nil) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        layer.path = path
        layer.strokeColor = stroke?.cgColor
        layer.fillColor = fill?.cgColor ?? NSColor.clear.cgColor
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func centered(_ layer: CALayer) {
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        layer.position = CGPoint(x: 200, y: 200)
    }

    private func buildOuterRing() {
        centered(outerRing)
        let dashed = shape(circle(192), stroke: palette.lineBright, width: 1.2)
        dashed.lineDashPattern = [2, 7]
        outerRing.addSublayer(dashed)
        let arcs = CGMutablePath()
        arcs.addArc(center: CGPoint(x: 200, y: 200), radius: 196, startAngle: -.pi / 2, endAngle: -.pi / 2 + 0.78, clockwise: false)
        arcs.move(to: CGPoint(x: 200, y: 396))
        arcs.addArc(center: CGPoint(x: 200, y: 200), radius: 196, startAngle: .pi / 2, endAngle: .pi / 2 + 0.78, clockwise: false)
        outerRing.addSublayer(shape(arcs, stroke: palette.cyan, width: 2.4))
        box.addSublayer(outerRing)
    }

    private func buildTicks() {
        centered(ticks)
        let short = CGMutablePath(), long = CGMutablePath()
        for index in 0..<72 {
            let angle = CGFloat(index) * 5 * .pi / 180
            let isLong = index % 6 == 0
            let inner: CGFloat = isLong ? 160 : 168
            let path = isLong ? long : short
            path.move(to: CGPoint(x: 200 + inner * sin(angle), y: 200 - inner * cos(angle)))
            path.addLine(to: CGPoint(x: 200 + 176 * sin(angle), y: 200 - 176 * cos(angle)))
        }
        ticks.addSublayer(shape(short, stroke: palette.line, width: 1))
        ticks.addSublayer(shape(long, stroke: palette.lineBright, width: 2))
        box.addSublayer(ticks)
    }

    private func buildBars() {
        for index in 0..<64 {
            let height = (16 + 30 * Self.pattern[index % 8] * (0.7 + 0.3 * abs(sin(CGFloat(index) * 1.7)))).rounded()
            let holder = CALayer()
            centered(holder)
            holder.transform = CATransform3DMakeRotation(CGFloat(index) * 2 * .pi / 64, 0, 0, 1)
            let bar = CALayer()
            bar.backgroundColor = palette.cyan.cgColor
            bar.cornerRadius = 1.2
            // Anchored at its foot, on the circle of radius 116, growing outwards.
            bar.anchorPoint = CGPoint(x: 0.5, y: 1)
            bar.bounds = CGRect(x: 0, y: 0, width: 2.4, height: height)
            bar.position = CGPoint(x: 200, y: 200 - 116)
            bar.transform = CATransform3DMakeScale(1, Self.rest, 1)
            holder.addSublayer(bar)
            box.addSublayer(holder)
            bars.append(bar)
        }
    }

    private func buildWaves() {
        for _ in 0..<3 {
            let wave = shape(circle(86), stroke: palette.cyan, width: 1.6)
            centered(wave)
            wave.opacity = 0
            box.addSublayer(wave)
            waves.append(wave)
        }
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 200, y: 200), radius: 104, startAngle: -.pi / 2, endAngle: -.pi / 2 + 0.67, clockwise: false)
        thinking.addSublayer(shape(arc, stroke: palette.cyan, width: 3))
        centered(thinking)
        box.addSublayer(thinking)
    }

    private func buildCore() {
        centered(core)
        core.shadowColor = palette.cyan.cgColor
        core.shadowOffset = .zero
        core.shadowRadius = 6
        core.shadowOpacity = 0.35
        coreDisc.path = circle(86)
        coreDisc.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        coreDisc.fillColor = palette.card.cgColor
        coreDisc.strokeColor = palette.cyan.cgColor
        coreDisc.lineWidth = 2
        core.addSublayer(coreDisc)
        core.addSublayer(shape(circle(74), stroke: palette.line, width: 1))
        // The provisional ginkgo leaf of the mock-up (64-point box, moved to the centre).
        let place = CGAffineTransform(translationX: 140, y: 136).scaledBy(x: 1.875, y: 1.875)
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 32, y: 44))
        leaf.addCurve(to: CGPoint(x: 10, y: 25), control1: CGPoint(x: 24, y: 42), control2: CGPoint(x: 13, y: 36))
        leaf.addCurve(to: CGPoint(x: 30, y: 21), control1: CGPoint(x: 17, y: 18), control2: CGPoint(x: 26, y: 16))
        leaf.addLine(to: CGPoint(x: 32, y: 28))
        leaf.addLine(to: CGPoint(x: 34, y: 21))
        leaf.addCurve(to: CGPoint(x: 54, y: 25), control1: CGPoint(x: 38, y: 16), control2: CGPoint(x: 47, y: 18))
        leaf.addCurve(to: CGPoint(x: 32, y: 44), control1: CGPoint(x: 51, y: 36), control2: CGPoint(x: 40, y: 42))
        leaf.closeSubpath()
        for end in [CGPoint(x: 19, y: 25), CGPoint(x: 26, y: 21), CGPoint(x: 38, y: 21), CGPoint(x: 45, y: 25)] {
            leaf.move(to: CGPoint(x: 32, y: 44))
            leaf.addLine(to: end)
        }
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 32, y: 44))
        stem.addLine(to: CGPoint(x: 32, y: 56))
        core.addSublayer(shape(leaf.copy(using: [place]) ?? leaf, stroke: palette.cyan, width: 3))
        core.addSublayer(shape(stem.copy(using: [place]) ?? stem, stroke: palette.text, width: 3))
        box.addSublayer(core)
    }

    /// The HUD colors as AppKit colors (same tokens as ``HUDPalette``).
    static let colors = (
        cyan: NSColor(srgbRed: 0x4F / 255, green: 0xDC / 255, blue: 0xFF / 255, alpha: 1),
        card: NSColor(srgbRed: 0x0A / 255, green: 0x18 / 255, blue: 0x26 / 255, alpha: 1),
        line: NSColor(srgbRed: 0x1B / 255, green: 0x3F / 255, blue: 0x55 / 255, alpha: 1),
        lineBright: NSColor(srgbRed: 0x3D / 255, green: 0x7F / 255, blue: 0xA0 / 255, alpha: 1),
        text: NSColor(srgbRed: 0xE4 / 255, green: 0xF6 / 255, blue: 0xFF / 255, alpha: 1)
    )
}

/// The voice line under the heart: the last 48 levels, newest in the middle-right, drawn only
/// when a level arrives.
struct GinkgoVoiceLine: NSViewRepresentable {
    let levels: GinkgoLevels

    func makeNSView(context: Context) -> GinkgoVoiceLineView {
        let view = GinkgoVoiceLineView()
        context.coordinator.token = levels.observe { [weak view] input, output in view?.push(max(input, output)) }
        return view
    }

    func updateNSView(_ view: GinkgoVoiceLineView, context: Context) {}

    static func dismantleNSView(_ view: GinkgoVoiceLineView, coordinator: GinkgoHeart.Coordinator) {
        if let token = coordinator.token { coordinator.levels.stopObserving(token) }
    }

    func makeCoordinator() -> GinkgoHeart.Coordinator { GinkgoHeart.Coordinator(levels: levels) }
}

final class GinkgoVoiceLineView: NSView {
    private var bars: [CALayer] = []
    private var history = [CGFloat](repeating: 0, count: 48)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<48 {
            let bar = CALayer()
            bar.backgroundColor = GinkgoHeartView.colors.cyan.cgColor
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draw()
        CATransaction.commit()
    }

    /// The levels stopped (microphone closed, screen hidden): back to the thin line at rest.
    func rest() {}

    func push(_ level: Double) {
        history.removeFirst()
        history.append(CGFloat(level))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.07)
        draw()
        CATransaction.commit()
    }

    private func draw() {
        let step = bounds.width / 48
        for (index, bar) in bars.enumerated() {
            // An envelope that is high in the middle, as on the mock-up; at rest a thin dotted line.
            let envelope = sin(.pi * (CGFloat(index) + 0.5) / 48)
            let height = max(3, bounds.height * envelope * history[index])
            bar.frame = CGRect(x: CGFloat(index) * step, y: (bounds.height - height) / 2, width: max(1, step - 3), height: height)
        }
    }
}
