import Foundation
public import Observation

/// What the window and the Feed observe: lab's lanes, the Feed's selection, the question read
/// for it and the outcome of the user's last action. Every action goes through lab.
///
/// ```swift
/// let model = LanesModel(service: service, runner: runner)
/// model.start()
/// model.openFeed()
/// ```
@MainActor
@Observable
public final class LanesModel {
    /// The last state read from lab.
    public private(set) var state = LanesState()
    /// Whether the Feed covers the window.
    public var isFeedPresented = false
    /// The request shown in large in the Feed, by `project/lane`.
    public private(set) var selectedRequestID: String?
    /// What the selected lane asks, word for word.
    public private(set) var question: LabQuestion = .none
    /// The lane the question was read for.
    public private(set) var questionLaneID: String?
    /// Whether the question is being read.
    public private(set) var isReadingQuestion = false
    /// The outcome of the last action.
    public private(set) var notice: LanesNotice?
    /// Lanes with an action under way.
    public private(set) var busyLaneIDs: Set<String> = []
    /// Choices picked in a box that waits for Send (question number → option numbers).
    public private(set) var picks: [Int: Set<Int>] = [:]
    /// Answers being typed, per lane: moving to another request keeps them.
    private var drafts: [String: String] = [:]

    private let service: LanesService
    private let runner: (any LabCommandRunning)?
    private let locator = LaneLocator()
    private let parser = KeyValueBlockParser()
    private var openInApp: (@MainActor (ProjectRecord, ClassifiedLane) -> Bool)?
    private var stateTask: Task<Void, Never>?

    /// Creates the model.
    /// - Parameters:
    ///   - service: the link to lab's snapshot.
    ///   - runner: runs lab's commands; `nil` when lab is unavailable (actions are then refused on screen).
    public init(service: LanesService, runner: (any LabCommandRunning)?) {
        self.service = service
        self.runner = runner
    }

    /// Sets how the app brings a lane forward itself (its workspace); without it, or when it
    /// returns `false`, `lab app focus` is used.
    /// - Parameter handler: returns `true` when the app showed the lane.
    public func setOpenInApp(_ handler: @escaping @MainActor (ProjectRecord, ClassifiedLane) -> Bool) {
        openInApp = handler
    }

    /// Starts following lab. Calling it again does nothing.
    public func start() {
        guard stateTask == nil else { return }
        let service = self.service
        stateTask = Task { [weak self] in
            let states = await service.states()
            Task { await service.start() }
            for await state in states {
                guard let self else { return }
                self.apply(state)
            }
        }
    }

    /// The requests in Feed order.
    public var requests: [ClassifiedLane] { state.snapshot.requests }

    /// The request shown in large: the selected one, else the oldest.
    public var selectedRequest: ClassifiedLane? {
        requests.first { $0.id == selectedRequestID } ?? requests.first
    }

    /// The project and lane of a folder.
    /// - Parameter directory: a workspace's or terminal's folder.
    /// - Returns: its location among lab's projects.
    public func location(forDirectory directory: String) -> LaneLocation? {
        locator.locate(directory: directory, in: state.snapshot)
    }

    /// Shows the Feed on the oldest request and reads its question.
    public func openFeed() {
        isFeedPresented = true
        notice = nil
        if selectedRequestID == nil || !requests.contains(where: { $0.id == selectedRequestID }) {
            selectedRequestID = requests.first?.id
        }
        Task { await readQuestion() }
    }

    /// Hides the Feed.
    public func closeFeed() {
        isFeedPresented = false
    }

    /// Shows request `id` in large and reads its question.
    /// - Parameter id: `project/lane`.
    public func select(_ id: String) {
        guard selectedRequestID != id else { return }
        selectedRequestID = id
        notice = nil
        picks = [:]
        Task { await readQuestion() }
    }

    /// The answer being typed for the selected request, sent by Return (``submit()``).
    public var draftAnswer: String {
        get { selectedRequest.flatMap { drafts[$0.id] } ?? "" }
        set {
            guard let id = selectedRequest?.id else { return }
            drafts[id] = newValue.isEmpty ? nil : newValue
        }
    }

    /// Moves the selection by `offset` in the queue (arrow keys).
    /// - Parameter offset: -1 for the previous request, +1 for the next.
    public func moveSelection(_ offset: Int) {
        guard let current = selectedRequest, let index = requests.firstIndex(of: current) else { return }
        let next = min(max(index + offset, 0), requests.count - 1)
        select(requests[next].id)
    }

    /// Reads what the selected lane asks (`lab ginkgo question`).
    public func readQuestion() async {
        guard let lane = selectedRequest, let runner,
              let project = LabName(lane.record.project), let laneName = LabName(lane.record.lane) else {
            question = .none
            questionLaneID = nil
            return
        }
        isReadingQuestion = true
        defer { isReadingQuestion = false }
        let output = try? await runner.run(.question(project: project, lane: laneName))
        guard selectedRequest?.id == lane.id else { return }
        questionLaneID = lane.id
        if let output, output.status == 0, let block = parser.blocks(in: output.standardOutput).first {
            question = LabQuestion.parse(block)
        } else {
            question = .none
        }
    }

    /// Answers the selected lane's question box with the user's choices (`lab ginkgo answer --qid … --q n --choice c`).
    /// - Parameter choices: chosen option numbers per question number.
    public func answer(choices: [Int: [Int]]) async {
        guard let lane = selectedRequest, questionLaneID == lane.id, case let .box(qid, _) = question,
              let project = LabName(lane.record.project), let laneName = LabName(lane.record.lane), !choices.isEmpty else { return }
        guard let questionID = LabQuestionID(qid) else {
            notice = .refused("question id refused: \(qid)")
            return
        }
        await perform(.answerChoices(project: project, lane: laneName, qid: questionID, choices: choices), for: lane, success: .sent(lane.id))
        await afterAnswer(lane)
    }

    /// Answers the selected lane with the user's text (`lab ginkgo answer --text`).
    /// - Parameter text: what the user typed; sent as one argument, never interpreted.
    public func answer(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let lane = selectedRequest,
              let project = LabName(lane.record.project), let laneName = LabName(lane.record.lane) else { return }
        await perform(.answerText(project: project, lane: laneName, text: trimmed), for: lane, success: .sent(lane.id))
        await afterAnswer(lane)
    }

    /// Once lab took an answer: the lane's typed text and picks are cleared, and what it asks
    /// now is read again (the agent may already wait on a new question).
    private func afterAnswer(_ lane: ClassifiedLane) async {
        guard notice == .sent(lane.id) else { return }
        drafts[lane.id] = nil
        picks = [:]
        if selectedRequest?.id == lane.id { await readQuestion() }
    }

    /// Key 1 to 9: picks that option of the first question (``pick(question:option:)``).
    /// - Parameter digit: the key pressed.
    /// - Returns: `false` when the question has no such option: the key is left to others.
    @discardableResult
    public func pressDigit(_ digit: Int) -> Bool {
        guard let lane = selectedRequest, questionLaneID == lane.id, case let .box(_, items) = question,
              let first = items.first, first.options.contains(where: { $0.number == digit }) else { return false }
        pick(question: first.number, option: digit)
        return true
    }

    /// Picks an option. A box with one single-choice question sends it at once; otherwise the
    /// pick waits for Send (``submit()``), and a multiple-choice question toggles it.
    /// - Parameters:
    ///   - number: the question's number.
    ///   - option: the option's number.
    public func pick(question number: Int, option: Int) {
        guard case let .box(_, items) = question, let item = items.first(where: { $0.number == number }),
              item.options.contains(where: { $0.number == option }) else { return }
        if items.count == 1 && !item.multiple {
            Task { await answer(choices: [number: [option]]) }
            return
        }
        var set = picks[number] ?? []
        if item.multiple {
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
        } else {
            set = [option]
        }
        picks[number] = set
    }

    /// Return in the Feed: the typed answer, or else the picked choices.
    public func submit() async {
        let chosen = picks.mapValues { $0.sorted() }.filter { !$0.value.isEmpty }
        if draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !chosen.isEmpty {
            await answer(choices: chosen)
        } else {
            await submitDraft()
        }
    }

    /// Sends ``draftAnswer`` to the selected lane, then clears it once lab took it.
    public func submitDraft() async {
        await answer(text: draftAnswer)
    }

    /// Relaunches a stopped lane (`lab next`).
    /// - Parameter lane: a lane of ``LaneStatus/stopped``; other lanes are ignored.
    public func relaunch(_ lane: ClassifiedLane) async {
        guard lane.status == .stopped, let project = LabName(lane.record.project), let laneName = LabName(lane.record.lane) else { return }
        await perform(.next(project: project, lane: laneName), for: lane, success: .relaunched([lane.id]))
    }

    /// Relaunches every stopped lane, one after the other.
    public func relaunchAll() async {
        let stopped = state.snapshot.lanes(.stopped)
        var done: [String] = []
        for lane in stopped {
            await relaunch(lane)
            if case .refused = notice { return }
            done.append(lane.id)
        }
        if !done.isEmpty { notice = .relaunched(done) }
    }

    /// Brings `lane` forward: in the app when it can, otherwise with `lab app focus`.
    /// - Parameter lane: the lane.
    public func open(_ lane: ClassifiedLane) async {
        if let project = state.snapshot.projects.first(where: { $0.id == lane.record.project })?.project,
           openInApp?(project, lane) == true {
            notice = .opened(lane.id)
            isFeedPresented = false
            return
        }
        guard let project = LabName(lane.record.project), let laneName = LabName(lane.record.lane) else { return }
        await perform(.focus(project: project, lane: laneName), for: lane, success: .opened(lane.id))
        if notice == .opened(lane.id) { isFeedPresented = false }
    }

    private func perform(_ command: LabCommand, for lane: ClassifiedLane, success: LanesNotice) async {
        guard let runner else {
            notice = .refused(Self.describe(state.problem ?? .labUnavailable("")))
            return
        }
        busyLaneIDs.insert(lane.id)
        defer { busyLaneIDs.remove(lane.id) }
        do {
            let output = try await runner.run(command)
            notice = output.status == 0 ? success : .refused(output.refusal)
        } catch let problem as LanesProblem {
            notice = .refused(Self.describe(problem))
        } catch {
            notice = .refused(error.localizedDescription)
        }
    }

    private func apply(_ newState: LanesState) {
        let before = selectedRequest
        state = newState
        guard isFeedPresented else { return }
        if let selected = selectedRequestID, !requests.contains(where: { $0.id == selected }) {
            // The answered request left the queue: show the next one.
            selectedRequestID = requests.first?.id
            picks = [:]
            Task { await readQuestion() }
        } else if let before, let now = selectedRequest, now.id == before.id, now.record != before.record {
            // lab wrote the selected lane again: it may ask something new.
            Task { await readQuestion() }
        }
    }

    /// A problem in one line, for the notice.
    /// - Parameter problem: the problem.
    /// - Returns: lab's words or the refused file.
    public static func describe(_ problem: LanesProblem) -> String {
        switch problem {
        case let .labUnavailable(reason), let .labRefused(reason), let .unknownLabVersion(reason): return reason
        case let .refusedFile(path, reason): return "\(path): \(reason.rawValue)"
        }
    }
}
