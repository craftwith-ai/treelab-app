public import AppKit
import SwiftUI
public import TreelabLanes

/// A project's lane indicators for an AppKit sidebar row: hosts ``ProjectIndicators`` and asks
/// the row to lay out again when the indicators' width changes (a lane changed status).
@MainActor
public final class TreelabRowIndicatorsView: NSView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private weak var model: LanesModel?
    private var directory: String?

    /// Creates the view, empty until ``update(model:directory:)``.
    /// - Parameter frameRect: the initial frame.
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.sizingOptions = [.intrinsicContentSize]
        addSubview(host)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    /// Shows the indicators of the project `directory` belongs to.
    /// - Parameters:
    ///   - model: the lanes model, `nil` to show nothing.
    ///   - directory: the workspace's folder.
    public func update(model: LanesModel?, directory: String?) {
        guard model !== self.model || directory != self.directory else { return }
        self.model = model
        self.directory = directory
        guard let model else {
            host.rootView = AnyView(EmptyView())
            return
        }
        host.rootView = AnyView(
            ProjectIndicators(model: model, directory: directory)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] _ in
                    self?.superview?.needsLayout = true
                    self?.superview?.superview?.needsLayout = true
                }
        )
    }

    /// Places the indicators so they end at `maxX` on the title line.
    /// - Parameters:
    ///   - maxX: where they end.
    ///   - centerY: the title line's center.
    ///   - apply: `false` only measures.
    /// - Returns: the width they take, 0 when there is nothing to show.
    public func place(endingAt maxX: CGFloat, centerY: CGFloat, apply: Bool) -> CGFloat {
        let size = model == nil ? .zero : host.fittingSize
        guard size.width > 1 else {
            if apply { frame = .zero }
            return 0
        }
        if apply {
            frame = NSRect(x: maxX - size.width, y: centerY - size.height / 2, width: size.width, height: size.height)
            host.frame = bounds
        }
        return size.width
    }
}
