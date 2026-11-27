public import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    /// Asks the window given as `object` to show the Feed (posted by the counter and the banner).
    public static let treelabFeedRequested = Notification.Name("sh.treelab.lanes.feedRequested")
    /// Asks the window given as `object` to show Ginkgo's voice screen (posted by the bar entry).
    public static let treelabGinkgoRequested = Notification.Name("sh.treelab.ginkgo.screenRequested")
}

/// The window a SwiftUI view is in, so its action targets that window even while the app is in
/// the background (there is no key window then).
@MainActor
final class HostWindow {
    weak var window: NSWindow?

    /// Asks this window to show the Feed.
    func requestFeed() {
        NotificationCenter.default.post(name: .treelabFeedRequested, object: window)
    }

    /// Asks this window to show Ginkgo's voice screen.
    func requestGinkgo() {
        NotificationCenter.default.post(name: .treelabGinkgoRequested, object: window)
    }
}

/// Keeps ``HostWindow`` up to date with the window the view is placed in.
struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.host = host
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.host = host
        host.window = view.window
    }

    final class ReaderView: NSView {
        weak var host: HostWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host?.window = window
        }
    }
}
