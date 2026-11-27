import Foundation

/// Accepts only the lab versions whose snapshot format Treelab knows.
///
/// The snapshot folder carries a `version` file (lab's version, `1.5.107`). An unknown major
/// version is refused: the window says so instead of showing figures it may misread.
public struct LabVersionGate: Sendable {
    /// Major versions this build reads.
    public let supportedMajors: Set<Int>

    /// Creates the gate.
    /// - Parameter supportedMajors: major versions read, `[1]` by default.
    public init(supportedMajors: Set<Int> = [1]) {
        self.supportedMajors = supportedMajors
    }

    /// Checks `version`.
    /// - Parameter version: the content of the `version` file, `nil` when absent.
    /// - Returns: the trimmed version when it is accepted.
    /// - Throws: ``LanesProblem/unknownLabVersion(_:)`` otherwise.
    public func check(_ version: String?) throws -> String {
        let trimmed = (version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let majorText = trimmed.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        guard let major = Int(majorText), supportedMajors.contains(major) else {
            throw LanesProblem.unknownLabVersion(trimmed)
        }
        return trimmed
    }
}
