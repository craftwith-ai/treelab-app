public import Foundation

/// A stand-in for lab that never runs a program: it answers `lab ginkgo question` from files of a
/// demo folder (`questions/<project>/<lane>`, read through ``SnapshotFileGate``), accepts the reader
/// declaration, and refuses every action. Used to show invented lanes (screens, trials) without
/// touching the user's lab.
public struct DemoLabRunner: LabCommandRunning {
    private let folder: URL
    private let gate: SnapshotFileGate

    /// Creates the stand-in.
    /// - Parameters:
    ///   - folder: the demo folder.
    ///   - gate: the file checks.
    public init(folder: URL, gate: SnapshotFileGate = SnapshotFileGate()) {
        self.folder = folder
        self.gate = gate
    }

    /// Answers without running anything.
    /// - Parameter command: the command.
    /// - Returns: the question file, an empty success for the reader declaration, a refusal otherwise.
    public func run(_ command: LabCommand) async throws -> LabCommandOutput {
        switch command {
        case .snapshot:
            return LabCommandOutput(status: 0, standardOutput: "", standardError: "")
        case let .question(project, lane):
            let questions = folder.appendingPathComponent("questions")
            let file = questions.appendingPathComponent(project.value).appendingPathComponent(lane.value)
            let text = (try? gate.read(file, within: questions)) ?? "WAITS=none\n"
            return LabCommandOutput(status: 0, standardOutput: text, standardError: "")
        default:
            return LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR demo: nothing is sent\n")
        }
    }
}
