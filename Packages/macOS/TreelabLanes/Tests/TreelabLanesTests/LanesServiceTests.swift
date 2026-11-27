import Foundation
import Testing

@testable import TreelabLanes

@Suite("Light: woken by changes only")
struct LanesServiceTests {
    /// A snapshot folder with one project and two lanes; `extra` adds lines to lane `api`.
    func fixture(_ tmp: TemporaryFolder, api extra: String = "") throws -> URL {
        let snap = try tmp.folder("snap")
        let root = tmp.url.appendingPathComponent("work/demo").path
        try tmp.write("snap/version", "1.8.2\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(root)\nWATCH_ENTRIES=\(root)/.worktrees\n")
        _ = try tmp.folder("work/demo/.worktrees/api/.lab")
        _ = try tmp.folder("docs/lots/api")
        try tmp.write("docs/lots/api/lot-01.md", "x")
        try tmp.write("snap/projects/demo/lanes/api", """
        PROJECT=demo
        LANE=api
        WAITS_FOR=you
        SESSION=live
        FOR_YOU=yes
        WATCH=\(root)/.worktrees/api/.lab/session.lock
        WATCH=\(tmp.url.path)/docs/lots/api/lot-01.md
        WRITTEN=\(root)/.worktrees/api/.lab/session.lock
        WATCH_ENTRIES=\(tmp.url.path)/docs/lots/api
        WATCH_PID=4242
        \(extra)
        """)
        try tmp.write("snap/projects/demo/lanes/web", "PROJECT=demo\nLANE=web\nSESSION=none\n")
        return snap
    }

    func service(_ snap: URL, _ runner: RecordingLabRunner, files: ScriptedWatcher, entries: ScriptedWatcher = ScriptedWatcher(), exits: ScriptedExits = ScriptedExits()) -> LanesService {
        LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 777, files: files, entries: entries, exits: exits)
    }

    @Test("at start: one full snapshot that declares the reader, then nothing while nothing changes")
    func registrationOnly() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let service = service(try fixture(tmp), runner, files: ScriptedWatcher())
        await service.start()
        await service.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(await runner.commands == [.snapshot(readerPID: 777, project: nil, lane: nil)])
        let states = await service.states()
        var iterator = states.makeAsyncIterator()
        let state = try #require(await iterator.next())
        #expect(state.snapshot.total == StatusCounts(waitingForYou: 1, working: 0, stopped: 1, offCounter: 0))
    }

    @Test("a document lab does not write itself calls for one targeted snapshot; a file lab writes does not")
    func documentChange() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let files = ScriptedWatcher()
        let service = service(try fixture(tmp), runner, files: files)
        await service.start()
        files.emit(tmp.url.appendingPathComponent("work/demo/.worktrees/api/.lab/session.lock").path)
        files.emit(tmp.url.appendingPathComponent("docs/lots/api/lot-01.md").path)
        let target = LabCommand.snapshot(readerPID: 777, project: LabName("demo"), lane: LabName("api"))
        #expect(await eventually { await runner.commands.contains(target) })
        try await Task.sleep(for: .milliseconds(200))
        #expect(await runner.commands.filter { $0 == target }.count == 1)
        #expect(await runner.commands.count == 2)
    }

    @Test("an entries folder is watched without depth; its change calls for a targeted snapshot")
    func entriesChange() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let entries = ScriptedWatcher()
        let service = service(try fixture(tmp), runner, files: ScriptedWatcher(), entries: entries)
        await service.start()
        let watched = Set(entries.watched.flatMap { $0 })
        #expect(watched.isSuperset(of: [tmp.url.appendingPathComponent("docs/lots/api").path, tmp.url.appendingPathComponent("work/demo/.worktrees").path]))
        #expect(watched.isSuperset(of: ["snap", "snap/projects", "snap/projects/demo", "snap/projects/demo/lanes"].map { tmp.url.appendingPathComponent($0).path }))
        entries.emit(tmp.url.appendingPathComponent("work/demo/.worktrees").path)
        #expect(await eventually { await runner.commands.contains(.snapshot(readerPID: 777, project: LabName("demo"), lane: nil)) })
    }

    @Test("the end of a watched process calls for a targeted snapshot")
    func processEnd() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let exits = ScriptedExits()
        let service = service(try fixture(tmp), runner, files: ScriptedWatcher(), exits: exits)
        await service.start()
        exits.end(4242)
        #expect(await eventually { await runner.commands.contains(.snapshot(readerPID: 777, project: LabName("demo"), lane: LabName("api"))) })
    }

    @Test("a wake date calls for a targeted snapshot when it comes, not before")
    func wake() async throws {
        let tmp = try TemporaryFolder()
        let runner = RecordingLabRunner()
        let at = Int(Date().timeIntervalSince1970) + 2
        let service = service(try fixture(tmp, api: "WAKE_AT=\(at)"), runner, files: ScriptedWatcher())
        await service.start()
        let target = LabCommand.snapshot(readerPID: 777, project: LabName("demo"), lane: LabName("api"))
        #expect(await runner.commands.contains(target) == false)
        #expect(await eventually(5) { await runner.commands.contains(target) })
    }

    @Test("with the real watchers, a lane file replaced as lab does is seen; at rest, no further call")
    func realWatchers() async throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        let runner = RecordingLabRunner()
        let service = LanesService(reader: SnapshotFolderReader(folder: snap), runner: runner, readerPID: 777,
                                   files: FSEventsFileWatcher(latency: 0.1), entries: KernelDirectoryWatcher(), exits: KernelProcessExitWatcher())
        await service.start()
        let rest = Double(ProcessInfo.processInfo.environment["TREELAB_REST_SECONDS"] ?? "2") ?? 2
        try await Task.sleep(for: .milliseconds(Int(rest * 1000)))
        let atRest = await runner.commands
        try tmp.replaceLikeLab("snap/projects/demo/lanes/web", "PROJECT=demo\nLANE=web\nSESSION=live\n")
        let seen = await eventually(5) {
            let states = await service.states()
            var iterator = states.makeAsyncIterator()
            return await iterator.next()?.snapshot.total.working == 1
        }
        #expect(seen)
        // 4242 is not a live process: its end is reported at once, one targeted call, then rest.
        #expect(atRest.filter { $0 == .snapshot(readerPID: 777, project: nil, lane: nil) }.count == 1)
        #expect(atRest.count <= 2)
        print("REST_SECONDS=\(rest) LAB_CALLS_AT_REST=\(atRest.count) CALLS=\(atRest.map(\.arguments))")
        await service.stop()
    }

    @Test("lab missing or refusing: the problem is shown, the files are still read")
    func problems() async throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        let missing = LanesService(reader: SnapshotFolderReader(folder: snap), runner: nil, unavailable: .labUnavailable("none"),
                                   readerPID: 1, files: ScriptedWatcher(), entries: ScriptedWatcher(), exits: ScriptedExits())
        await missing.start()
        var iterator = await missing.states().makeAsyncIterator()
        let state = try #require(await iterator.next())
        #expect(state.problem == .labUnavailable("none"))
        #expect(state.snapshot.total.counted == 2)
        let refusing = RecordingLabRunner { _ in LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR no reader\n") }
        let service = service(snap, refusing, files: ScriptedWatcher())
        await service.start()
        var second = await service.states().makeAsyncIterator()
        #expect(try #require(await second.next()).problem == .labRefused("no reader"))
    }
}
