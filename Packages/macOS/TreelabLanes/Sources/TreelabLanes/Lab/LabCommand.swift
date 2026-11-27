/// A lab command Treelab runs, as a list of arguments (never a shell line).
///
/// Every value is one argument: text typed by the user or written by a lane is never split,
/// expanded or interpreted.
public enum LabCommand: Sendable, Equatable {
    /// Declares Treelab as the reader of the snapshot and rewrites it (`lab app snapshot --reader <pid>`),
    /// for every project or for one lane.
    case snapshot(readerPID: Int32, project: LabName?, lane: LabName?)
    /// Reads what a lane asks, word for word (`lab ginkgo question`).
    case question(project: LabName, lane: LabName)
    /// Answers a question box with the user's choices (`lab ginkgo answer … --qid … --q n --choice c`).
    case answerChoices(project: LabName, lane: LabName, qid: String, choices: [Int: [Int]])
    /// Answers a lane waiting without a box with the user's text (`lab ginkgo answer … --text`).
    case answerText(project: LabName, lane: LabName, text: String)
    /// Moves the lane to its next step (`lab next`): relaunches a stopped lane.
    case next(project: LabName, lane: LabName)
    /// Brings the lane's tab to the front (`lab app focus`).
    case focus(project: LabName, lane: LabName)

    /// The arguments passed to lab, program name excluded.
    public var arguments: [String] {
        switch self {
        case let .snapshot(pid, project, lane):
            var arguments = ["app", "snapshot", "--reader", String(pid)]
            if let project {
                arguments.append(project.value)
                if let lane { arguments.append(lane.value) }
            }
            return arguments
        case let .question(project, lane):
            return ["ginkgo", "question", project.value, lane.value]
        case let .answerChoices(project, lane, qid, choices):
            var arguments = ["ginkgo", "answer", project.value, lane.value, "--qid", qid]
            for question in choices.keys.sorted() {
                arguments += ["--q", String(question)]
                for choice in choices[question] ?? [] { arguments += ["--choice", String(choice)] }
            }
            return arguments
        case let .answerText(project, lane, text):
            return ["ginkgo", "answer", project.value, lane.value, "--text", text]
        case let .next(project, lane):
            return ["next", project.value, lane.value]
        case let .focus(project, lane):
            return ["app", "focus", project.value, lane.value]
        }
    }
}
