public import Foundation

/// Runs lab as a child process: its exact path, the arguments as a list, no shell.
///
/// The environment is inherited unchanged: lab's own guards (for example, `lab ginkgo answer`
/// refused to an agent) keep seeing who really runs it. A command that does not finish within
/// `timeout` is terminated.
public struct ProcessLabCommandRunner: LabCommandRunning {
    private let executable: URL
    private let timeout: Duration

    /// Creates a runner.
    /// - Parameters:
    ///   - executable: lab's path, from ``LabExecutableLocator``.
    ///   - timeout: the longest wait, 120 seconds by default (`lab next` may open a session).
    public init(executable: URL, timeout: Duration = .seconds(120)) {
        self.executable = executable
        self.timeout = timeout
    }

    /// Runs `command`.
    /// - Parameter command: the command.
    /// - Returns: exit code, stdout and stderr.
    /// - Throws: ``LanesProblem/labUnavailable(_:)`` when lab cannot start or overruns `timeout`.
    public func run(_ command: LabCommand) async throws -> LabCommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
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
        let deadline = Task { [timeout] in
            try await Task.sleep(for: timeout)
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
