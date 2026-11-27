import AppKit
import SwiftUI

/// The sizes of the welcome and the settings: the mock-up's 1280 plan, and its large plan from
/// 1500 points wide (1512×993 on the Mac of reference).
struct AccountScreenSize: Equatable {
    let isLarge: Bool
    init(width: CGFloat) { isLarge = width >= 1500 }
    var body: CGFloat { isLarge ? 15 : 13 }
    var small: CGFloat { isLarge ? 13 : 11.5 }
    var title: CGFloat { isLarge ? 34 : 28 }
    var heading: CGFloat { isLarge ? 22 : 18 }
    var big: CGFloat { isLarge ? 24 : 20 }
    var padding: CGFloat { isLarge ? 36 : 24 }
    var navigation: CGFloat { isLarge ? 300 : 240 }
    var leftColumn: CGFloat { isLarge ? 500 : 400 }
    var control: CGFloat { isLarge ? 40 : 34 }
    var cardSpacing: CGFloat { isLarge ? 18 : 14 }
}

/// A card of the HUD: a title in capitals, then its content.
struct HUDCard<Content: View>: View {
    let title: String
    var accent: Color? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: size.small, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(accent ?? palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(size.isLarge ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent?.opacity(0.7) ?? palette.line))
    }
}

/// The main action of a card: cyan border on the button fill.
struct HUDPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.body, weight: .semibold))
            .foregroundStyle(isEnabled ? palette.text : palette.textSecondary)
            .padding(.horizontal, 16)
            .frame(minHeight: size.control)
            .background(configuration.isPressed ? palette.cardRaised : palette.buttonFill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isEnabled ? palette.cyan : palette.line))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.7)
    }
}

/// A secondary action: a thin bright border, no fill.
struct HUDSecondaryButtonStyle: ButtonStyle {
    var danger = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.body, weight: .medium))
            .foregroundStyle(isEnabled ? (danger ? palette.red : palette.text) : palette.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: size.control)
            .background(configuration.isPressed ? palette.cardRaised : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(danger ? palette.red.opacity(0.8) : palette.lineBright))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.7)
    }
}

/// One choice among a few (listening mode, speech, theme): a ring that fills when chosen, a name,
/// a mark (" · default", " · soon") and a line of detail. A choice that cannot be taken is dimmed.
struct HUDChoiceRow: View {
    let name: String
    var mark: String = ""
    var markColor: Color? = nil
    var detail: String = ""
    let isSelected: Bool
    var isAvailable = true
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().stroke(isSelected ? palette.cyan : palette.lineBright, lineWidth: 1.5)
                    if isSelected { Circle().fill(palette.cyan).padding(4) }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text(name).font(.system(size: size.body, weight: .semibold)).foregroundStyle(palette.text)
                        if !mark.isEmpty {
                            Text(mark).font(.system(size: size.body)).foregroundStyle(markColor ?? palette.textSecondary)
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: size.small))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? palette.cardRaised : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected ? palette.cyan.opacity(0.8) : palette.line))
            .contentShape(Rectangle())
            .opacity(isAvailable && isEnabled ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A field of the HUD: the text on the card colour, a bright border.
struct HUDFieldModifier: ViewModifier {
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: size.body))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .frame(minHeight: size.control)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.lineBright))
    }
}

extension View {
    /// Draws a text field the HUD way.
    func hudField() -> some View { modifier(HUDFieldModifier()) }
}

/// A line of secondary text that wraps.
struct HUDNote: View {
    let text: String
    var color: Color? = nil
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        Text(text)
            .font(.system(size: size.small))
            .foregroundStyle(color ?? palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountScreenSizeKey: EnvironmentKey {
    static let defaultValue = AccountScreenSize(width: 1280)
}

extension EnvironmentValues {
    /// The size plan of the welcome and the settings.
    var accountScreenSize: AccountScreenSize {
        get { self[AccountScreenSizeKey.self] }
        set { self[AccountScreenSizeKey.self] = newValue }
    }
}

/// The Treelab mark of the mock-up (the welcome and the account entry): a tree of arcs in a rounded square.
struct TreelabMark: View {
    var side: CGFloat = 32
    private let palette = HUDPalette()

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 64
            let frame = CGRect(x: 2 * s, y: 2 * s, width: 60 * s, height: 60 * s)
            context.fill(Path(roundedRect: frame, cornerRadius: 14 * s), with: .color(palette.card))
            context.stroke(Path(roundedRect: frame, cornerRadius: 14 * s), with: .color(palette.cyan), lineWidth: 2 * s)
            func stroke(_ color: Color, _ build: (inout Path) -> Void) {
                var path = Path()
                build(&path)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, lineJoin: .round))
            }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            stroke(palette.text) { $0.move(to: p(6, 40)); $0.addLine(to: p(50, 40)) }
            stroke(palette.cyan) { $0.move(to: p(8, 40)); $0.addCurve(to: p(48, 38), control1: p(8, 14), control2: p(34, 12)) }
            stroke(palette.amber) { $0.move(to: p(14, 40)); $0.addCurve(to: p(45, 39), control1: p(15, 24), control2: p(34, 22)) }
            stroke(palette.cyan) { $0.move(to: p(20, 40)); $0.addCurve(to: p(42, 39), control1: p(21, 31), control2: p(33, 30)) }
            stroke(palette.cyan) { $0.move(to: p(10, 40)); $0.addCurve(to: p(46, 41), control1: p(12, 51), control2: p(34, 52)) }
            stroke(palette.text) { $0.move(to: p(50, 40)); $0.addCurve(to: p(59, 30), control1: p(54, 40), control2: p(56, 36)) }
            stroke(palette.text) { $0.move(to: p(50, 40)); $0.addCurve(to: p(59, 48), control1: p(54, 40), control2: p(56, 44)) }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
