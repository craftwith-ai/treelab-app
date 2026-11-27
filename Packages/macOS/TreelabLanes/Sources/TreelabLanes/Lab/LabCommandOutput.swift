import Foundation

/// What a lab command returned.
public struct LabCommandOutput: Sendable, Equatable {
    /// The exit code.
    public var status: Int32
    /// Standard output.
    public var standardOutput: String
    /// Standard error.
    public var standardError: String

    /// Creates an output.
    /// - Parameters:
    ///   - status: exit code.
    ///   - standardOutput: stdout.
    ///   - standardError: stderr.
    public init(status: Int32, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// lab's refusal in one line (`lab: ERROR …` or the last line of stderr), for the screen.
    public var refusal: String {
        let lines = standardError.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if let error = lines.last(where: { $0.hasPrefix("lab: ERROR") }) {
            return String(error.dropFirst("lab: ERROR".count)).trimmingCharacters(in: .whitespaces)
        }
        return lines.last(where: { !$0.isEmpty }) ?? "exit \(status)"
    }
}
