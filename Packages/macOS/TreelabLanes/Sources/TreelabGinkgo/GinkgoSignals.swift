public import Foundation
import AppKit

/// When Ginkgo becomes ready and when it stops (§1 of the contract): the two moments Treelab waits
/// for, without polling nor timer.
public protocol GinkgoSignals: Sendable {
    /// Each time Ginkgo listens on its socket (`dev.treelab.ginkgo.ready`).
    func ready() -> AsyncStream<Void>
    /// Each time Ginkgo.app's process ends.
    func terminations() -> AsyncStream<Void>
}

/// The system's signals: a distributed notification without content, and the end of the
/// `dev.treelab.ginkgo` process seen by `NSWorkspace`.
public struct GinkgoSystemSignals: GinkgoSignals {
    /// Ginkgo.app's bundle identifier.
    public static let bundleIdentifier = "dev.treelab.ginkgo"
    /// Posted by Ginkgo right after `listen()`.
    public static let readyName = Notification.Name("dev.treelab.ginkgo.ready")

    public init() {}

    public func ready() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = ReadyObserver(continuation: continuation)
            // AppKit holds distributed notifications back while the app is inactive: the ready
            // signal must come at once, or Treelab would wait for its own activation.
            DistributedNotificationCenter.default().addObserver(
                observer, selector: #selector(ReadyObserver.ready(_:)), name: Self.readyName, object: nil,
                suspensionBehavior: .deliverImmediately
            )
            continuation.onTermination = { _ in observer.remove() }
        }
    }

    public func terminations() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == Self.bundleIdentifier { continuation.yield() }
            }
            let holder = ObserverHolder(token: token, center: center)
            continuation.onTermination = { _ in holder.remove() }
        }
    }
}

/// Yields each ready signal; removed from the center when its stream ends.
private final class ReadyObserver: NSObject, @unchecked Sendable {
    // The continuation is Sendable; the center is thread-safe.
    private let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    @objc func ready(_ notification: Notification) { continuation.yield() }

    func remove() { DistributedNotificationCenter.default().removeObserver(self) }
}

/// Removes a block observer when its stream ends.
private final class ObserverHolder: @unchecked Sendable {
    // Both are only used once, in remove(); NotificationCenter is thread-safe.
    private let token: any NSObjectProtocol
    private let center: NotificationCenter

    init(token: any NSObjectProtocol, center: NotificationCenter) {
        self.token = token
        self.center = center
    }

    func remove() { center.removeObserver(token) }
}
