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
    case answerChoices(project: LabName, lane: LabName, qid: LabQuestionID, choices: [Int: [Int]])
    /// Answers a lane waiting without a box with the user's text (`lab ginkgo answer … --text`).
    case answerText(project: LabName, lane: LabName, text: String)
    /// Moves the lane to its next step (`lab next`): relaunches a stopped lane.
    case next(project: LabName, lane: LabName)
    /// Brings the lane's tab to the front (`lab app focus`).
    case focus(project: LabName, lane: LabName)
    /// Says where Ginkgo.app is, whether the OpenAI key is stored and which contract it speaks
    /// (`lab ginkgo status`: `APP=`, `KEY=`, `PROTOCOL=`).
    case ginkgoStatus
    /// Starts Ginkgo.app on a project (`lab ginkgo <project>`): with `background`, without a
    /// conversation nor microphone (`--background`).
    case ginkgoLaunch(project: LabName, background: Bool)

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
            var arguments = ["ginkgo", "answer", project.value, lane.value, "--qid", qid.value]
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
        case .ginkgoStatus:
            return ["ginkgo", "status"]
        case let .ginkgoLaunch(project, background):
            return ["ginkgo", project.value] + (background ? ["--background"] : [])
        }
    }
}
