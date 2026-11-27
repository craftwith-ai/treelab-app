import Foundation
import Testing
import os

@testable import TreelabLanes

/// The findings of the batch's single review, each one written red before its fix.
@Suite("Review findings")
@MainActor
struct ReviewFixesTests {
    nonisolated static let twoQuestions = """
    WAITS=box
    QID=q-2
    QUESTION_1=Where?
    OPTION_1_1=Here
    OPTION_1_2=There
    QUESTION_2=When?
    OPTION_2_1=Now
    OPTION_2_2=Later
    """

    /// One waiting lane `demo/api` (plus `demo/web`, waiting later), read through scripted watchers.
    func fixture(_ tmp: TemporaryFolder) throws -> URL {
        let snap = try tmp.folder("snap")
        let root = tmp.url.appendingPathComponent("work/demo").path
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(root)\n")
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try tmp.write("work/demo/.worktrees/api/.lab/waits-for", "q\n", mode: 0o600, date: t)
        try tmp.write("work/demo/.worktrees/web/.lab/waits-for", "q\n", mode: 0o600, date: t.addingTimeInterval(60))
        for lane in ["api", "web"] {
            try tmp.write("snap/projects/demo/lanes/\(lane)", "PROJECT=demo\nLANE=\(lane)\nWAITS_FOR=you\nWHY=question waiting: x\nSESSION=live\nFOR_YOU=yes\nWRITTEN=\(root)/.worktrees/\(lane)/.lab/waits-for\n")
        }
        return snap
    }

    func model(_ snap: URL, _ runner: RecordingLabRunner, entries: ScriptedWatcher = ScriptedWatcher()) async -> LanesModel {
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 9,
                                   files: ScriptedWatcher(), entries: entries, exits: ScriptedExits())
        let model = LanesModel(service: service, runner: runner)
        model.start()
        _ = await eventually { await MainActor.run { model.state.loaded } }
        return model
    }

    func answering(_ box: String) -> RecordingLabRunner {
        RecordingLabRunner { command in
            LabCommandOutput(status: 0, standardOutput: command.arguments.prefix(2) == ["ginkgo", "question"] ? box : "", standardError: "")
        }
    }

    func opened(_ model: LanesModel) async {
        model.openFeed()
        _ = await eventually { await MainActor.run { model.questionLaneID == "demo/api" } }
    }

    // Finding 1: keys 1 to 9 pick a choice, from the model (the palette focus lock no longer applies to the Feed).
    @Test("key 2 on a one-question box sends that choice to lab")
    func digitSends() async throws {
        let tmp = try TemporaryFolder()
        let runner = answering(LanesModelTests.box)
        let model = await model(try fixture(tmp), runner)
        await opened(model)
        #expect(model.pressDigit(2))
        #expect(await eventually { await runner.commands.contains(.answerChoices(project: LabName("demo")!, lane: LabName("api")!, qid: LabQuestionID("q-17")!, choices: [1: [2]])) })
        #expect(!model.pressDigit(7), "no seventh option: the key is left alone")
    }

    // Finding 10: Return sends the picks of a box with several questions when nothing is typed.
    @Test("on a two-question box keys pick, then Return sends the picks")
    func returnSendsPicks() async throws {
        let tmp = try TemporaryFolder()
        let runner = answering(Self.twoQuestions)
        let model = await model(try fixture(tmp), runner)
        await opened(model)
        #expect(model.pressDigit(2))
        model.pick(question: 2, option: 1)
        #expect(model.picks == [1: [2], 2: [1]])
        #expect(await !runner.commands.contains { if case .answerChoices = $0 { true } else { false } })
        await model.submit()
        #expect(await runner.commands.contains(.answerChoices(project: LabName("demo")!, lane: LabName("api")!, qid: LabQuestionID("q-2")!, choices: [1: [2], 2: [1]])))
    }

    // Finding 11: the typed answer belongs to its lane; moving to another request does not lose it.
    @Test("a typed answer stays with its lane when the selection moves")
    func draftPerLane() async throws {
        let tmp = try TemporaryFolder()
        let model = await model(try fixture(tmp), answering(LanesModelTests.box))
        await opened(model)
        model.draftAnswer = "a long answer"
        model.moveSelection(1)
        #expect(model.selectedRequest?.id == "demo/web")
        #expect(model.draftAnswer.isEmpty)
        model.moveSelection(-1)
        #expect(model.draftAnswer == "a long answer")
    }

    // Finding 7: after an answer, and when the lane is written again, the question is read again.
    @Test("the question is read again after an answer and when the selected lane changes")
    func questionReadAgain() async throws {
        let tmp = try TemporaryFolder()
        let entries = ScriptedWatcher()
        let snap = try fixture(tmp)
        let runner = answering(LanesModelTests.box)
        let model = await model(snap, runner, entries: entries)
        await opened(model)
        let question = LabCommand.question(project: LabName("demo")!, lane: LabName("api")!)
        let asked: @Sendable () async -> Int = { await runner.commands.filter { $0 == question }.count }
        let first = await asked()
        await model.answer(choices: [1: [1]])
        #expect(await eventually { await asked() > first })
        let second = await asked()
        try tmp.write("work/demo/.worktrees/api/.lab/waits-for", "q2\n", mode: 0o600, date: Date(timeIntervalSince1970: 1_700_000_500))
        entries.emit(snap.appendingPathComponent("projects/demo/lanes").path)
        #expect(await eventually { await asked() > second })
    }

    // Security review of the fixes: picks belong to the question they were made for. When lab
    // asks a new question (new QID) before Send, the old picks are dropped, never sent with it.
    @Test("picks made for one question are never sent with the next one")
    func picksBelongToTheirQuestion() async throws {
        let tmp = try TemporaryFolder()
        let entries = ScriptedWatcher()
        let snap = try fixture(tmp)
        let asked = OSAllocatedUnfairLock(initialState: Self.twoQuestions)
        let runner = RecordingLabRunner { command in
            LabCommandOutput(status: 0, standardOutput: command.arguments.prefix(2) == ["ginkgo", "question"] ? asked.withLock { $0 } : "", standardError: "")
        }
        let model = await model(snap, runner, entries: entries)
        await opened(model)
        #expect(model.pressDigit(2))
        #expect(model.picks == [1: [2]])
        asked.withLock { $0 = Self.twoQuestions.replacingOccurrences(of: "QID=q-2", with: "QID=q-3") }
        try tmp.write("work/demo/.worktrees/api/.lab/waits-for", "q3\n", mode: 0o600, date: Date(timeIntervalSince1970: 1_700_000_900))
        entries.emit(snap.appendingPathComponent("projects/demo/lanes").path)
        #expect(await eventually { await MainActor.run { if case let .box(qid, _) = model.question { qid == "q-3" } else { false } } })
        #expect(model.picks.isEmpty)
        await model.submit()
        #expect(await !runner.commands.contains { if case .answerChoices = $0 { true } else { false } })
    }

    // Finding 12: a question id lab cannot have written is said, not silently dropped.
    @Test("a refused question id is shown and nothing is sent")
    func refusedQuestionID() async throws {
        let tmp = try TemporaryFolder()
        let runner = answering(LanesModelTests.box.replacingOccurrences(of: "QID=q-17", with: "QID=q/17"))
        let model = await model(try fixture(tmp), runner)
        await opened(model)
        await model.answer(choices: [1: [1]])
        guard case .refused = model.notice else { Issue.record("no notice: \(String(describing: model.notice))"); return }
        #expect(await !runner.commands.contains { if case .answerChoices = $0 { true } else { false } })
    }
}

@Suite("Review findings, reading and lab")
struct ReviewFixesServiceTests {
    // Finding 3: a WAKE_AT that is not a real date is ignored (it used to crash the app).
    @Test("WAKE_AT infinite, not a number or centuries away is ignored")
    func wakeAt() throws {
        for bad in ["inf", "nan", "1e300", "-5"] {
            let block = try #require(KeyValueBlockParser().blocks(in: "PROJECT=p\nLANE=l\nWAKE_AT=\(bad)\n").first)
            #expect(LaneRecord(block: block)?.wakeAt == nil, "WAKE_AT=\(bad)")
        }
        let good = try #require(KeyValueBlockParser().blocks(in: "PROJECT=p\nLANE=l\nWAKE_AT=1800000000\n").first)
        #expect(LaneRecord(block: good)?.wakeAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    // Finding 4: a folder in the middle that is a link leading out of the snapshot folder is refused.
    @Test("a project folder that is a link to elsewhere is refused")
    func linkedFolder() throws {
        let tmp = try TemporaryFolder()
        let snap = try tmp.folder("snap")
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("elsewhere/evil/project", "PROJECT=evil\nROOT=/tmp/evil\n")
        _ = try tmp.folder("snap/projects", mode: 0o700)
        try FileManager.default.createSymbolicLink(atPath: snap.appendingPathComponent("projects/evil").path,
                                                   withDestinationPath: tmp.url.appendingPathComponent("elsewhere/evil").path)
        let result = try SnapshotFolderReader(folder: snap).read()
        #expect(result.projects.isEmpty)
        #expect(result.refused["projects/evil/project"] == .outsideFolder)
    }

    // Finding 5: lab is located again before each run, so an update that relinks `current` is followed.
    @Test("lab updated in place (current relinked) is followed at the next run")
    func relinkedLab() async throws {
        let tmp = try TemporaryFolder()
        try tmp.write("releases/one/lab", "#!/bin/sh\necho one\n", mode: 0o755)
        try tmp.write("releases/two/lab", "#!/bin/sh\necho two\n", mode: 0o755)
        let current = tmp.url.appendingPathComponent("current")
        try FileManager.default.createSymbolicLink(atPath: current.path, withDestinationPath: tmp.url.appendingPathComponent("releases/one").path)
        let runner = ProcessLabCommandRunner(locator: LabExecutableLocator(candidates: [current.appendingPathComponent("lab")]))
        let command = LabCommand.next(project: LabName("p")!, lane: LabName("l")!)
        #expect(try await runner.run(command).standardOutput == "one\n")
        try FileManager.default.removeItem(at: current)
        try FileManager.default.createSymbolicLink(atPath: current.path, withDestinationPath: tmp.url.appendingPathComponent("releases/two").path)
        #expect(try await runner.run(command).standardOutput == "two\n")
    }

    /// demo/api watches its batch file; demo/web's file is mode 0666.
    func fixture(_ tmp: TemporaryFolder) throws -> URL {
        let snap = try tmp.folder("snap")
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(tmp.url.path)/work\n")
        try tmp.write("docs/lot.md", "x\n")
        try tmp.write("snap/projects/demo/lanes/api", "PROJECT=demo\nLANE=api\nWATCH=\(tmp.url.path)/docs/lot.md\n")
        return snap
    }

    // Finding 5 (second half): a refresh lab refuses is said on the counter, not dropped.
    @Test("a targeted refresh that lab refuses is shown as a problem")
    func refreshRefused() async throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        let runner = RecordingLabRunner { command in
            command.arguments.count > 4
                ? LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR busy\n")
                : LabCommandOutput(status: 0, standardOutput: "", standardError: "")
        }
        let files = ScriptedWatcher()
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 3,
                                   files: files, entries: ScriptedWatcher(), exits: ScriptedExits())
        await service.start()
        files.emit(tmp.url.appendingPathComponent("docs/lot.md").path)
        let shown = await eventually {
            var iterator = await service.states().makeAsyncIterator()
            return await iterator.next()?.problem == .labRefused("busy")
        }
        #expect(shown)
    }

    // Finding 8: a refused file is said on the counter (its lane is missing from the figures).
    @Test("a lane file others may write is refused and the refusal is shown")
    func refusedFileShown() async throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        try tmp.write("snap/projects/demo/lanes/web", "PROJECT=demo\nLANE=web\n", mode: 0o666)
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: RecordingLabRunner(), readerPID: 3,
                                   files: ScriptedWatcher(), entries: ScriptedWatcher(), exits: ScriptedExits())
        await service.start()
        var iterator = await service.states().makeAsyncIterator()
        let state = try #require(await iterator.next())
        #expect(state.problem == .refusedFile(path: "projects/demo/lanes/web", reason: .writableByOthers))
    }

    // Finding 9: a change seen while the same refresh runs is not lost: one more run follows.
    @Test("a refresh asked during the same refresh runs once more afterwards")
    func refreshQueued() async throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        let runner = SlowLabRunner()
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 3,
                                   files: ScriptedWatcher(), entries: ScriptedWatcher(), exits: ScriptedExits())
        let target = LaneTarget(project: "demo", lane: "api")
        async let first: Void = service.refresh(target)
        try await Task.sleep(for: .milliseconds(50))
        await service.refresh(target)
        await first
        #expect(await eventually { await runner.count == 2 })
    }

    // Finding 2: a lanes folder created after the start is watched too (real kernel watcher).
    @Test("a lanes folder that appears later is watched: its next change is seen")
    func lateLanesFolder() async throws {
        let tmp = try TemporaryFolder()
        let snap = try tmp.folder("snap")
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(tmp.url.path)/work\n")
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: RecordingLabRunner(), readerPID: 3,
                                   files: ScriptedWatcher(), entries: KernelDirectoryWatcher(), exits: ScriptedExits())
        await service.start()
        @Sendable func total() async -> StatusCounts? {
            var iterator = await service.states().makeAsyncIterator()
            return await iterator.next()?.snapshot.total
        }
        _ = try tmp.folder("snap/projects/demo/lanes", mode: 0o755)
        try tmp.replaceLikeLab("snap/projects/demo/lanes/api", "PROJECT=demo\nLANE=api\nSESSION=none\n")
        #expect(await eventually(5) { await total()?.stopped == 1 })
        try tmp.replaceLikeLab("snap/projects/demo/lanes/api", "PROJECT=demo\nLANE=api\nSESSION=live\n")
        #expect(await eventually(5) { await total()?.working == 1 })
        await service.stop()
    }
}

/// A lab whose every call takes 300 ms, counting its calls.
actor SlowLabRunner: LabCommandRunning {
    private(set) var count = 0
    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        count += 1
        try await Task.sleep(for: .milliseconds(300))
        return LabCommandOutput(status: 0, standardOutput: "", standardError: "")
    }
}

@Suite("Seen on the real lab")
struct RealLabFindingsTests {
    // The first full snapshot of every lane took 93 s on the Mac (142 lanes), close to the 120 s
    // wait: that one call gets a longer wait, every other call keeps the usual one.
    @Test("the full snapshot at launch gets a longer wait than the other calls")
    func fullSnapshotWait() {
        let runner = ProcessLabCommandRunner(executable: URL(fileURLWithPath: "/usr/bin/true"))
        #expect(runner.wait(for: .snapshot(readerPID: 1, project: nil, lane: nil)) >= .seconds(600))
        #expect(runner.wait(for: .snapshot(readerPID: 1, project: LabName("p"), lane: LabName("l"))) == .seconds(120))
        #expect(runner.wait(for: .next(project: LabName("p")!, lane: LabName("l")!)) == .seconds(120))
    }

    // The app showed 0 everywhere for the 93 s of that first snapshot: the files lab already
    // wrote are now shown at once, then read again once lab has rewritten them.
    @Test("the files already written are shown before lab answers the reader declaration")
    func filesBeforeRegistration() async throws {
        let tmp = try TemporaryFolder()
        let snap = try tmp.folder("snap")
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(tmp.url.path)/work\n")
        try tmp.write("snap/projects/demo/lanes/api", "PROJECT=demo\nLANE=api\nSESSION=live\n")
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: SlowLabRunner(), readerPID: 3,
                                   files: ScriptedWatcher(), entries: ScriptedWatcher(), exits: ScriptedExits())
        let starting = Task { await service.start() }
        let early = await eventually(0.2) {
            var iterator = await service.states().makeAsyncIterator()
            return await iterator.next()?.snapshot.total.working == 1
        }
        #expect(early, "shown while lab still works on the declaration (300 ms)")
        await starting.value
    }
}

@Suite("Seen on the screens")
struct ScreenFindingsTests {
    // The Feed got no digit: the app's key monitor now hands plain 1–9 to the model.
    @Test("only a plain digit 1 to 9 picks a choice")
    func choiceDigit() {
        #expect(LanesModel.choiceDigit("2", withModifiers: false) == 2)
        #expect(LanesModel.choiceDigit("9", withModifiers: false) == 9)
        for other in ["0", "12", "a", "", "²", "٣"] { #expect(LanesModel.choiceDigit(other, withModifiers: false) == nil, "\(other)") }
        #expect(LanesModel.choiceDigit(nil, withModifiers: false) == nil)
        #expect(LanesModel.choiceDigit("2", withModifiers: true) == nil, "Command-2 and the like stay shortcuts")
    }

    // The banner and the Feed showed lab's English prefixes ("question waiting: …").
    @Test("the reason shown drops lab's prefix and keeps the sentence")
    func reason() throws {
        func record(_ why: String) throws -> LaneRecord {
            let block = try #require(KeyValueBlockParser().blocks(in: "PROJECT=p\nLANE=l\nWHY=\(why)\n").first)
            return try #require(LaneRecord(block: block))
        }
        #expect(try record("question waiting: Les réglages s'ouvrent-ils à part ?").reason == "Les réglages s'ouvrent-ils à part ?")
        #expect(try record("permission requested: Bash").reason == "Bash")
        #expect(try record("work finished: Maquette prête").reason == "Maquette prête")
        #expect(try record("lane blocked: Claude a terminé").reason == "Claude a terminé")
        #expect(try record("next step to clarify: Lot 1").reason == "Lot 1")
        #expect(try record("closing: acceptance missing").reason == "acceptance missing")
        #expect(try record("checks running").reason == "checks running", "no known prefix: kept whole")
        #expect(try record("note: keep this").reason == "note: keep this", "an unknown prefix is the lane's own text")
        #expect(try record("question waiting").reason == "question waiting", "nothing after the prefix: kept whole")
    }
}
