import Foundation
import Testing

@testable import TreelabLanes

@Suite("Reading lab's snapshot folder")
struct SnapshotFolderReaderTests {
    /// Builds a folder like `~/.lab/state/app-snapshot`, with project roots under the same temp folder.
    func fixture(_ tmp: TemporaryFolder, version: String = "1.8.2") throws -> URL {
        let snap = try tmp.folder("snap")
        let root = tmp.url.appendingPathComponent("work/demo").path
        try tmp.write("snap/version", version + "\n")
        try tmp.write("snap/projects/demo/project", "PROJECT=demo\nROOT=\(root)\nLANES=3\n")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try tmp.write("work/demo/.worktrees/api/.lab/waits-for", "question\n", mode: 0o600, date: old.addingTimeInterval(600))
        try tmp.write("work/demo/.worktrees/web/.lab/waits-for", "permission\n", mode: 0o600, date: old)
        try tmp.write("work/demo/.worktrees/sync/.lab/meta", "agent=claude\npermanent=yes\n", mode: 0o600)
        for (lane, extra) in [
            ("api", "WAITS_FOR=you\nWHY=question waiting: x\nSESSION=live\nFOR_YOU=yes\nWRITTEN=\(root)/.worktrees/api/.lab/waits-for\n"),
            ("web", "WAITS_FOR=you\nWHY=permission requested: Bash\nSESSION=live\nFOR_YOU=yes\nWRITTEN=\(root)/.worktrees/web/.lab/waits-for\n"),
            ("sync", "WAITS_FOR=nothing\nSESSION=none\nFOR_YOU=no\nWATCH=\(root)/.worktrees/sync/.lab/meta\n"),
        ] {
            try tmp.write("snap/projects/demo/lanes/\(lane)", "PROJECT=demo\nLANE=\(lane)\n" + extra)
        }
        return snap
    }

    @Test("projects and lanes are read; permanent and waiting dates come from the lane's own .lab")
    func read() throws {
        let tmp = try TemporaryFolder()
        let result = try SnapshotFolderReader(folder: fixture(tmp)).read()
        #expect(result.labVersion == "1.8.2")
        #expect(result.projects.map(\.project) == ["demo"])
        #expect(result.lanes.map(\.lane) == ["api", "sync", "web"])
        #expect(result.lanes.first { $0.lane == "sync" }?.permanent == true)
        let snapshot = LanesSnapshotBuilder().snapshot(projects: result.projects, lanes: result.lanes, labVersion: result.labVersion)
        #expect(snapshot.requests.map(\.record.lane) == ["web", "api"])
        #expect(snapshot.total == StatusCounts(waitingForYou: 2, working: 0, stopped: 0, offCounter: 1))
        #expect(result.refused.isEmpty)
    }

    @Test("an unknown or missing version stops the read")
    func version() throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp, version: "2.0.0")
        #expect(throws: LanesProblem.unknownLabVersion("2.0.0")) { try SnapshotFolderReader(folder: snap).read() }
        try FileManager.default.removeItem(at: snap.appendingPathComponent("version"))
        #expect(throws: LanesProblem.unknownLabVersion("")) { try SnapshotFolderReader(folder: snap).read() }
    }

    @Test("a refused lane file is skipped and reported, the others are read")
    func refusedLane() throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        chmod(snap.appendingPathComponent("projects/demo/lanes/web").path, 0o666)
        let result = try SnapshotFolderReader(folder: snap).read()
        #expect(result.lanes.map(\.lane) == ["api", "sync"])
        #expect(result.refused == ["projects/demo/lanes/web": .writableByOthers])
    }

    @Test("a lane file naming another lane, an unsafe entry name, or a meta outside the lane are ignored")
    func mismatches() throws {
        let tmp = try TemporaryFolder()
        let snap = try fixture(tmp)
        try tmp.write("snap/projects/demo/lanes/ghost", "PROJECT=demo\nLANE=api\n")
        try tmp.write("snap/projects/demo/lanes/-rf", "PROJECT=demo\nLANE=-rf\n")
        try tmp.write("elsewhere/meta", "permanent=yes\n", mode: 0o600)
        try tmp.write("snap/projects/demo/lanes/api", "PROJECT=demo\nLANE=api\nWATCH=\(tmp.url.path)/elsewhere/meta\n")
        let result = try SnapshotFolderReader(folder: snap).read()
        #expect(result.lanes.map(\.lane) == ["api", "sync", "web"])
        #expect(result.lanes.first { $0.lane == "api" }?.permanent == false)
    }
}
