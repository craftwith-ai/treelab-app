import Foundation
import os
import Testing
@testable import TreelabGinkgo

/// The system's ready signal, through the real distributed notification center.
@MainActor
@Suite("System signals", .serialized)
struct SignalsTests {
    /// Whether `stream` yields within `seconds`.
    private func yields(_ stream: AsyncStream<Void>, within seconds: Double) async -> Bool {
        let received = OSAllocatedUnfairLock(initialState: false)
        let task = Task { for await _ in stream { received.withLock { $0 = true }; return } }
        defer { task.cancel() }
        return await eventually(seconds) { received.withLock { $0 } }
    }

    @Test("the ready signal reaches Treelab")
    func ready() async {
        let stream = GinkgoSystemSignals().ready()
        DistributedNotificationCenter.default().postNotificationName(GinkgoSystemSignals.readyName, object: nil, userInfo: nil, deliverImmediately: false)
        #expect(await yields(stream, within: 3))
    }

    @Test("the ready signal reaches Treelab while its notifications are held (app inactive, review R2)")
    func readyWhileHeld() async {
        let center = DistributedNotificationCenter.default()
        let stream = GinkgoSystemSignals().ready()
        center.suspended = true
        defer { center.suspended = false }
        center.postNotificationName(GinkgoSystemSignals.readyName, object: nil, userInfo: nil, deliverImmediately: false)
        #expect(await yields(stream, within: 3))
    }
}
