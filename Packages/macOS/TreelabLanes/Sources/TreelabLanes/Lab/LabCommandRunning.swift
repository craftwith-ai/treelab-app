/// Runs a ``LabCommand``; the seam tests replace with a recording fake.
public protocol LabCommandRunning: Sendable {
    /// Runs `command` and waits for it.
    /// - Parameter command: the command.
    /// - Returns: its output, whatever its exit code.
    /// - Throws: when lab cannot be started or does not finish in time.
    func run(_ command: LabCommand) async throws -> LabCommandOutput
}
