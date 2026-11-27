import Foundation
import os
@testable import TreelabLanes

/// A lab that records every command and answers from a script.
actor RecordingLabRunner: LabCommandRunning {
    private(set) var commands: [LabCommand] = []
    private let answer: @Sendable (LabCommand) -> LabCommandOutput

    init(answer: @escaping @Sendable (LabCommand) -> LabCommandOutput = { _ in LabCommandOutput(status: 0, standardOutput: "", standardError: "") }) {
        self.answer = answer
    }

    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        commands.append(command)
        return answer(command)
    }
}

/// A file watcher driven by the test: `emit` sends paths to every stream watching an ancestor folder.
final class ScriptedWatcher: FileEventWatching {
    private let streams = OSAllocatedUnfairLock<[(paths: [String], continuation: AsyncStream<[String]>.Continuation)]>(initialState: [])

    func changes(under paths: [String]) -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        streams.withLock { $0.append((paths, continuation)) }
        return stream
    }

    var watched: [[String]] { streams.withLock { $0.map(\.paths) } }

    func emit(_ path: String) {
        let targets = streams.withLock { $0.filter { entry in entry.paths.contains { path == $0 || path.hasPrefix($0 + "/") } } }
        for target in targets { target.continuation.yield([path]) }
    }
}

/// A process watcher driven by the test.
final class ScriptedExits: ProcessExitWatching {
    private let streams = OSAllocatedUnfairLock<[AsyncStream<Int32>.Continuation]>(initialState: [])
    func exits(of pids: [Int32]) -> AsyncStream<Int32> {
        let (stream, continuation) = AsyncStream<Int32>.makeStream()
        streams.withLock { $0.append(continuation) }
        return stream
    }
    func end(_ pid: Int32) { streams.withLock { $0 }.forEach { $0.yield(pid) } }
}

/// Waits for `condition`, checking after each yield of the test's own task, at most `seconds`.
func eventually(_ seconds: Double = 3, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
