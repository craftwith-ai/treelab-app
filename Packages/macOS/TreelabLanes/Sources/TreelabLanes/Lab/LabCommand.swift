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

    // Account and settings, contract v1 (`contrat-compte.md` §3).

    /// Reads the account, the trial, the plan, the seats and treelab's offer (`lab app account`).
    case account
    /// Sends the sign-in link to the address the person typed (`lab app signin --email <address>`).
    case signIn(email: LabEmailAddress)
    /// Closes every session of the account, this Mac included (`lab app signout --everywhere`).
    case signOutEverywhere
    /// Opens Stripe's secure page to subscribe, manage the subscription or see the invoices
    /// (`lab subscribe`; without a terminal lab opens the page and returns).
    case subscribe
    /// Stores the OpenAI key in the Mac's keychain (`lab ginkgo key openai`): the key goes on
    /// standard input (``standardInput``), never in the arguments.
    case storeOpenAIKey(LabSecret)
    /// Reads Ginkgo's settings: listening, speech, quiet hours (`lab app ginkgo`).
    case ginkgoSettings
    /// Writes one of Ginkgo's settings (`lab app ginkgo --listen|--speak|--quiet <value>`).
    case setGinkgo(LabGinkgoSetting)
    /// Writes a readable copy of Treelab's and lab's data, without secrets (`lab app data --export <folder>`).
    case exportData(folder: LabFolderPath)
    /// First step of an erase: lab says what will go and gives a token (`lab app data --erase`).
    case eraseData
    /// Second step of an erase, with the token of the first (`lab app data --erase --confirm <token>`).
    case confirmErase(token: LabEraseToken)

    /// What lab reads on its standard input: the secret of ``storeOpenAIKey(_:)``, nothing for
    /// every other command (an empty input).
    public var standardInput: LabSecret? {
        if case let .storeOpenAIKey(secret) = self { return secret }
        return nil
    }

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
        case .account:
            return ["app", "account"]
        case let .signIn(email):
            return ["app", "signin", "--email", email.value]
        case .signOutEverywhere:
            return ["app", "signout", "--everywhere"]
        case .subscribe:
            return ["subscribe"]
        case .storeOpenAIKey:
            return ["ginkgo", "key", "openai"]
        case .ginkgoSettings:
            return ["app", "ginkgo"]
        case let .setGinkgo(setting):
            return ["app", "ginkgo", setting.option, setting.value]
        case let .exportData(folder):
            return ["app", "data", "--export", folder.value]
        case .eraseData:
            return ["app", "data", "--erase"]
        case let .confirmErase(token):
            return ["app", "data", "--erase", "--confirm", token.value]
        }
    }
}
