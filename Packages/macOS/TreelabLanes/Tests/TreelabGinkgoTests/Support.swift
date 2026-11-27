import Foundation
import os
import TreelabGinkgo
import TreelabLanes

/// A stand-in Ginkgo on a real Unix socket, faithful to the contract: it accepts one client at a
/// time, records every order line it receives and sends the event lines the test writes.
///
/// The socket lives in a short folder under `/tmp` (0700, socket 0600): the test temporary folders
/// are too long for `sun_path`.
final class FakeGinkgo: @unchecked Sendable {
    let folder: String
    let path: String
    private let listener: Int32
    private let queue = DispatchQueue(label: "sh.treelab.tests.fake-ginkgo")
    // Everything below is only touched on `queue`.
    private var acceptSource: (any DispatchSourceRead)?
    private var clientSource: (any DispatchSourceRead)?
    private var client: Int32 = -1
    private var buffer = Data()
    private var lines: [Data] = []
    private var connections = 0
    private var seq = 0

    /// - Parameter subfolder: a private folder under the temporary one that holds `app.sock`
    ///   (`"ginkgo"` gives the demo layout `<folder>/ginkgo/app.sock`); none: `<folder>/app.sock`.
    init(subfolder: String? = nil) throws {
        var template = Array("/tmp/tlgk.XXXXXX".utf8CString)
        guard let made = mkdtemp(&template) else { throw CocoaError(.fileWriteUnknown) }
        folder = String(cString: made)
        chmod(folder, 0o700)
        var parent = folder
        if let subfolder {
            parent += "/" + subfolder
            guard mkdir(parent, 0o700) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        path = parent + "/app.sock"
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 4) == 0 else { throw CocoaError(.fileWriteUnknown) }
        chmod(path, 0o600)
        queue.sync {
            let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptClient() }
            acceptSource = source
            source.resume()
        }
    }

    deinit {
        acceptSource?.cancel()
        clientSource?.cancel()
        if client >= 0 { close(client) }
        close(listener)
        unlink(path)
        let parent = (path as NSString).deletingLastPathComponent
        if parent != folder { rmdir(parent) }
        rmdir(folder)
    }

    /// The location Treelab checks and connects to.
    var location: GinkgoSocketLocation { GinkgoSocketLocation(path: path) }

    /// Order lines received, `\n` excluded, raw bytes.
    var received: [Data] { queue.sync { lines } }

    /// The `op` of each order received.
    var ops: [String] {
        received.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }.compactMap { $0["op"] as? String }
    }

    /// The orders received, decoded.
    var orders: [[String: Any]] {
        received.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// Clients accepted so far.
    var connectionCount: Int { queue.sync { connections } }

    /// Whether a client is connected now.
    var hasClient: Bool { queue.sync { client >= 0 } }

    /// Sends an event: `body` is the JSON object's content without `v`, `seq` and `at`.
    func event(_ name: String, _ body: String = "") {
        waitForClient()
        queue.sync {
            seq += 1
            let extra = body.isEmpty ? "" : "," + body
            writeLocked(Data("{\"v\":1,\"ev\":\"\(name)\",\"seq\":\(seq),\"at\":1795765000000\(extra)}\n".utf8))
        }
    }

    /// Sends raw bytes.
    func raw(_ data: Data) {
        waitForClient()
        queue.sync { writeLocked(data) }
    }

    /// Treelab connects from its own thread: an event is only written once it is accepted (2 s at most).
    private func waitForClient() {
        for _ in 0..<200 where !hasClient { usleep(10_000) }
    }

    /// Closes the client's connection, as Ginkgo does when it stops.
    func dropClient() {
        queue.sync {
            clientSource?.cancel()
            clientSource = nil
            if client >= 0 { close(client) }
            client = -1
        }
    }

    /// Plays `hello` then `snapshot`, as Ginkgo does right after a client connects.
    func greet(state: String = "closed", mic: Bool = false, lines: String = "[]") {
        event("hello", "\"ginkgo\":\"2.0.0\",\"protocol\":1,\"capabilities\":[\"levels\"],\"listen\":\"command\"")
        event("snapshot", "\"state\":\"\(state)\",\"mic\":\(mic),\"focus\":\"treelab-app\",\"listen\":\"command\",\"lines\":\(lines),\"did\":[]")
    }

    private func acceptClient() {
        let accepted = accept(listener, nil, nil)
        guard accepted >= 0 else { return }
        if client >= 0 { close(client) }
        clientSource?.cancel()
        client = accepted
        connections += 1
        seq = 0
        let source = DispatchSource.makeReadSource(fileDescriptor: accepted, queue: queue)
        source.setEventHandler { [weak self] in self?.readClient(accepted) }
        clientSource = source
        source.resume()
    }

    private func readClient(_ descriptor: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &chunk, chunk.count)
        guard count > 0 else {
            if descriptor == client {
                clientSource?.cancel()
                clientSource = nil
                close(client)
                client = -1
            }
            return
        }
        buffer.append(contentsOf: chunk[0..<count])
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
    }

    private func writeLocked(_ data: Data) {
        guard client >= 0 else { return }
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}

/// Ready and end signals driven by the test.
final class ScriptedSignals: GinkgoSignals, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(ready: [AsyncStream<Void>.Continuation], ends: [AsyncStream<Void>.Continuation])>(initialState: ([], []))

    func ready() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { $0.ready.append(continuation) }
        return stream
    }

    func terminations() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { $0.ends.append(continuation) }
        return stream
    }

    func fireReady() { lock.withLock { $0.ready }.forEach { $0.yield() } }
    func fireEnd() { lock.withLock { $0.ends }.forEach { $0.yield() } }
}

/// A lab that records every command and answers from a script.
actor RecordingLab: LabCommandRunning {
    private(set) var commands: [LabCommand] = []
    private let answer: @Sendable (LabCommand) -> LabCommandOutput

    init(answer: @escaping @Sendable (LabCommand) -> LabCommandOutput) {
        self.answer = answer
    }

    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        commands.append(command)
        return answer(command)
    }

    /// A lab whose Ginkgo speaks the contract and has its key; `onLaunch` runs when lab starts it.
    static func current(onLaunch: @escaping @Sendable () -> Void = {}) -> RecordingLab {
        RecordingLab { command in
            switch command {
            case .ginkgoStatus:
                return LabCommandOutput(status: 0, standardOutput: "PROVIDER=openai\nKEY=present\nAPP=/x/Ginkgo.app\nSOURCE=release\nPROTOCOL=1\n", standardError: "")
            case .ginkgoLaunch:
                onLaunch()
                return LabCommandOutput(status: 0, standardOutput: "", standardError: "")
            default:
                return LabCommandOutput(status: 1, standardOutput: "", standardError: "unexpected")
            }
        }
    }
}

/// Waits for `condition`, checking every 10 ms, at most `seconds`.
func eventually(_ seconds: Double = 3, _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

/// An envelope for the reducer tests.
func envelope(_ seq: Int, _ event: GinkgoEvent, at: Double = 1_795_765_000) -> GinkgoEnvelope {
    GinkgoEnvelope(seq: seq, at: Date(timeIntervalSince1970: at), event: event)
}

/// A decoded line, for the decoder tests.
func decode(_ json: String) throws -> GinkgoEnvelope? {
    try GinkgoEventDecoder.decode(Data(json.utf8))
}

/// A name known to be valid.
func name(_ value: String) -> LabName { LabName(value)! }
