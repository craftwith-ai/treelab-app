public import Foundation

/// Runs lab as a child process: its exact path, the arguments as a list, no shell. Its standard
/// input is empty, except the secret of ``LabCommand/storeOpenAIKey(_:)``, which only ever goes there.
///
/// The program is checked again right before each run (``LabExecutableLocator/check(_:)``), so a
/// program replaced after it was located is refused; a runner made with a locator only finds lab
/// again before each run, so an update that relinks lab's installation is followed. The environment is inherited unchanged: lab's own guards (for example, `lab ginkgo answer`
/// refused to an agent) keep seeing who really runs it. A command that does not finish within
/// `timeout` is terminated.
public struct ProcessLabCommandRunner: LabCommandRunning {
    private let executable: URL?
    private let locator: LabExecutableLocator?
    private let timeout: Duration

    /// The wait of the full snapshot (every lane of every project, run once at launch).
    public static let fullSnapshotTimeout: Duration = .seconds(600)

    /// Creates a runner.
    /// - Parameters:
    ///   - executable: lab's path, from ``LabExecutableLocator``.
    ///   - locator: checks the program again before each run; `nil` only in tests of the runner itself.
    ///   - timeout: the longest wait, 120 seconds by default (`lab next` may open a session).
    public init(executable: URL, locator: LabExecutableLocator? = nil, timeout: Duration = .seconds(120)) {
        self.executable = executable
        self.locator = locator
        self.timeout = timeout
    }

    /// Runs `command`.
    /// - Parameter command: the command.
    /// - Returns: exit code, stdout and stderr.
    /// - Throws: ``LanesProblem/labUnavailable(_:)`` when lab cannot start or overruns `timeout`.
    /// Creates a runner that finds lab with `locator` before each run.
    /// - Parameters:
    ///   - locator: lab's candidate paths and checks.
    ///   - timeout: the longest wait of a call, 120 seconds by default.
    public init(locator: LabExecutableLocator, timeout: Duration = .seconds(120)) {
        self.executable = nil
        self.locator = locator
        self.timeout = timeout
    }

    /// The wait allowed for `command`: the full snapshot reads every lane and gets more.
    func wait(for command: LabCommand) -> Duration {
        if case .snapshot(_, nil, _) = command { return max(timeout, Self.fullSnapshotTimeout) }
        return timeout
    }

    /// lab's path for this run, checked now.
    private func resolve() throws -> URL {
        guard let executable else {
            guard let locator else { throw LanesProblem.labUnavailable("lab not located") }
            return try locator.locate()
        }
        if let locator, case let .failure(reason) = locator.check(executable) {
            throw LanesProblem.labUnavailable("\(executable.path): \(reason)")
        }
        return executable
    }

    public func run(_ command: LabCommand) async throws -> LabCommandOutput {
        let executable = try resolve()
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        if let secret = command.standardInput {
            // The secret is written into the pipe before lab starts (it is far smaller than a
            // pipe's buffer), then the writing end is closed: lab reads it and an end of file, and
            // a lab that never reads cannot block Treelab nor break its pipe.
            let input = Pipe()
            let writer = input.fileHandleForWriting
            do {
                try writer.write(contentsOf: secret.standardInputData)
                try writer.close()
            } catch {
                throw LanesProblem.labUnavailable("lab \(command.arguments.prefix(2).joined(separator: " ")): standard input refused")
            }
            process.standardInput = input
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let outputFD = output.fileHandleForReading.fileDescriptor
        let errorFD = errors.fileHandleForReading.fileDescriptor
        do {
            try process.run()
        } catch {
            throw LanesProblem.labUnavailable(error.localizedDescription)
        }
        // Pipes are drained concurrently, keyed by their raw descriptor (Int32 is Sendable).
        async let outData = Self.drain(outputFD)
        async let errData = Self.drain(errorFD)
        let deadline = Task { [wait = wait(for: command)] in
            try await Task.sleep(for: wait)
            process.terminate()
        }
        let (out, err) = await (outData, errData)
        process.waitUntilExit()
        deadline.cancel()
        if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGTERM {
            throw LanesProblem.labUnavailable("lab \(command.arguments.prefix(2).joined(separator: " ")) did not finish in time")
        }
        return LabCommandOutput(
            status: process.terminationStatus,
            standardOutput: String(decoding: out, as: UTF8.self),
            standardError: String(decoding: err, as: UTF8.self)
        )
    }

    private static func drain(_ descriptor: Int32) async -> Data {
        await Task.detached {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                if count > 0 { data.append(contentsOf: buffer[0..<count]) } else if count == 0 || errno != EINTR { break }
            }
            return data
        }.value
    }
}
