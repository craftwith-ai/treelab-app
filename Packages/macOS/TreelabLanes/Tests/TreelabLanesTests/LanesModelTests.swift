import Foundation
import Testing

@testable import TreelabLanes

@Suite("The Feed acts through lab")
@MainActor
struct LanesModelTests {
    /// Two waiting lanes (api older than web), one stopped (old), one working, one permanent at rest.
    func fixture(_ tmp: TemporaryFolder) throws -> URL {
        let snap = try tmp.folder("snap")
        let root = tmp.url.appendingPathComponent("work/demo").path
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(root)\n")
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try tmp.write("work/demo/.worktrees/api/.lab/waits-for", "q\n", mode: 0o600, date: t)
        try tmp.write("work/demo/.worktrees/web/.lab/waits-for", "q\n", mode: 0o600, date: t.addingTimeInterval(60))
        try tmp.write("work/demo/.worktrees/tower2/.lab/meta", "permanent=yes\n", mode: 0o600)
        let lanes: [(String, String)] = [
            ("api", "WAITS_FOR=you\nWHY=question waiting: x\nSESSION=live\nFOR_YOU=yes\nBATCH=lot-02-api\nWRITTEN=\(root)/.worktrees/api/.lab/waits-for\n"),
            ("web", "WAITS_FOR=you\nWHY=permission requested: Bash\nSESSION=live\nFOR_YOU=yes\nWRITTEN=\(root)/.worktrees/web/.lab/waits-for\n"),
            ("old", "WAITS_FOR=nothing\nSESSION=none\nFOR_YOU=no\n"),
            ("run", "WAITS_FOR=nothing\nSESSION=live\nFOR_YOU=no\n"),
            ("tower2", "WAITS_FOR=nothing\nSESSION=none\nFOR_YOU=no\nWATCH=\(root)/.worktrees/tower2/.lab/meta\n"),
        ]
        for (lane, extra) in lanes { try tmp.write("snap/projects/demo/lanes/\(lane)", "PROJECT=demo\nLANE=\(lane)\n" + extra) }
        return snap
    }

    func model(_ snap: URL, _ runner: RecordingLabRunner) async -> LanesModel {
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 9,
                                   files: ScriptedWatcher(), entries: ScriptedWatcher(), exits: ScriptedExits())
        let model = LanesModel(service: service, runner: runner)
        model.start()
        _ = await eventually { await MainActor.run { model.state.loaded } }
        return model
    }

    nonisolated static let box = """
    LANE=api
    WAITS=box
    QID=q-17
    QUESTION_1=Where do settings open?
    OPTION_1_1=Separate window
    OPTION_1_2=In a tab
    """

    @Test("the Feed opens on the oldest request and reads what it asks")
    func openFeed() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner { command in
            LabCommandOutput(status: 0, standardOutput: command.arguments.first == "ginkgo" ? Self.box : "", standardError: "")
        }
        let model = await model(try fixture(tmp), runner)
        #expect(model.state.snapshot.total == StatusCounts(waitingForYou: 2, working: 1, stopped: 1, offCounter: 1))
        model.openFeed()
        #expect(model.isFeedPresented)
        #expect(model.selectedRequest?.id == "demo/api")
        #expect(await eventually { await MainActor.run { model.questionLaneID == "demo/api" } })
        guard case let .box(qid, items) = model.question else { Issue.record("no box"); return }
        #expect(qid == "q-17" && items[0].options.count == 2)
        #expect(await runner.commands.contains(.question(project: LabName("demo")!, lane: LabName("api")!)))
    }

    @Test("a choice, a typed answer, a relaunch and an open go to lab with the exact arguments")
    func actions() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner { command in
            LabCommandOutput(status: 0, standardOutput: command.arguments.first == "ginkgo" && command.arguments[1] == "question" ? Self.box : "", standardError: "")
        }
        let model = await model(try fixture(tmp), runner)
        model.openFeed()
        _ = await eventually { await MainActor.run { model.questionLaneID == "demo/api" } }
        await model.answer(choices: [1: [2]])
        #expect(model.notice == .sent("demo/api"))
        await model.answer(text: "  go on; $(rm -rf ~)  ")
        let stopped = try #require(model.state.snapshot.lanes(.stopped).first)
        await model.relaunch(stopped)
        let offCounter = try #require(model.state.snapshot.lanes(.offCounter).first)
        await model.relaunch(offCounter)
        let working = try #require(model.state.snapshot.lanes(.working).first)
        await model.relaunch(working)
        await model.open(try #require(model.selectedRequest))
        let actions = await runner.commands.filter { $0.arguments.first != "app" || $0.arguments[1] != "snapshot" }.filter { $0.arguments[1] != "question" }
        #expect(actions.map(\.arguments) == [
            ["ginkgo", "answer", "demo", "api", "--qid", "q-17", "--q", "1", "--choice", "2"],
            ["ginkgo", "answer", "demo", "api", "--text", "go on; $(rm -rf ~)"],
            ["next", "demo", "old"],
            ["app", "focus", "demo", "api"],
        ])
        #expect(model.isFeedPresented == false)
    }

    @Test("Relaunch all relaunches every stopped lane, and only them")
    func relaunchAll() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let model = await model(try fixture(tmp), runner)
        await model.relaunchAll()
        #expect(await runner.commands.filter { $0.arguments.first == "next" }.map(\.arguments) == [["next", "demo", "old"]])
        #expect(model.notice == .relaunched(["demo/old"]))
    }

    @Test("lab's refusal is shown and nothing else is done")
    func refusal() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner { command in
            command.arguments.prefix(2) == ["ginkgo", "answer"]
                ? LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR lab ginkgo answer is the voice of the user (Ginkgo or their terminal): refused to an agent — nothing sent\n")
                : LabCommandOutput(status: 0, standardOutput: "", standardError: "")
        }
        let model = await model(try fixture(tmp), runner)
        model.openFeed()
        await model.answer(text: "yes")
        #expect(model.notice == .refused("lab ginkgo answer is the voice of the user (Ginkgo or their terminal): refused to an agent — nothing sent"))
        #expect(model.isFeedPresented)
        #expect(await runner.commands.filter { $0.arguments.first == "next" || $0.arguments.prefix(2) == ["app", "focus"] }.isEmpty)
    }

    @Test("the app opens the lane itself when it can, without lab")
    func openInApp() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let model = await model(try fixture(tmp), runner)
        var opened: [String] = []
        model.setOpenInApp { project, lane in opened.append("\(project.project)/\(lane.record.lane)"); return true }
        model.openFeed()
        await model.open(try #require(model.selectedRequest))
        #expect(opened == ["demo/api"])
        #expect(await runner.commands.filter { $0.arguments.prefix(2) == ["app", "focus"] }.isEmpty)
    }

    @Test("folders are matched to projects and lanes by path, never by name")
    func locate() async throws {
        let tmp = try TemporaryFolder()
        let model = await model(try fixture(tmp), RecordingLabRunner())
        let root = tmp.url.appendingPathComponent("work/demo").path
        #expect(model.location(forDirectory: root)?.project.id == "demo")
        #expect(model.location(forDirectory: root)?.lane == nil)
        #expect(model.location(forDirectory: root + "/.worktrees/api/Sources/")?.lane?.id == "demo/api")
        #expect(model.location(forDirectory: root + "/.worktrees/ghost")?.lane == nil)
        #expect(model.location(forDirectory: root + "-copy") == nil)
        #expect(model.location(forDirectory: "/elsewhere/demo") == nil)
    }
}
