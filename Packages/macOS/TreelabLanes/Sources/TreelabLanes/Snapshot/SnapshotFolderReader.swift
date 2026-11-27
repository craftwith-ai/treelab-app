public import Foundation

/// Reads the folder lab keeps for Treelab (`~/.lab/state/app-snapshot`): `version`, then
/// `projects/<project>/project` and `projects/<project>/lanes/<lane>`.
///
/// Every file goes through ``SnapshotFileGate``; folder entries whose name is not a safe
/// ``LabName`` are skipped. A refused file is reported, never half-read.
public struct SnapshotFolderReader: Sendable {
    /// The snapshot folder.
    public let folder: URL
    private let gate: SnapshotFileGate
    private let versionGate: LabVersionGate
    private let parser = KeyValueBlockParser()

    /// What one read found.
    public struct Result: Sendable, Equatable {
        /// lab's version.
        public var labVersion: String
        /// Projects read.
        public var projects: [ProjectRecord]
        /// Lanes read, enriched with `permanent` and `waitingSince`.
        public var lanes: [LaneRecord]
        /// Files refused by the gate, with the reason (shown in the window).
        public var refused: [String: SnapshotFileRefusal]
    }

    /// Creates a reader.
    /// - Parameters:
    ///   - folder: the snapshot folder.
    ///   - gate: the file checks.
    ///   - versionGate: the accepted lab versions.
    public init(folder: URL, gate: SnapshotFileGate = SnapshotFileGate(), versionGate: LabVersionGate = LabVersionGate()) {
        self.folder = folder
        self.gate = gate
        self.versionGate = versionGate
    }

    /// Reads the whole folder.
    /// - Returns: projects and lanes.
    /// - Throws: ``LanesProblem`` when the version is unknown or the folder itself is refused.
    public func read() throws -> Result {
        let versionText: String
        do {
            versionText = try gate.read(folder.appendingPathComponent("version"), within: folder)
        } catch let refusal as SnapshotFileRefusal {
            if refusal == .missing { throw LanesProblem.unknownLabVersion("") }
            throw LanesProblem.refusedFile(path: "version", reason: refusal)
        }
        let version = try versionGate.check(versionText)
        var projects: [ProjectRecord] = []
        var lanes: [LaneRecord] = []
        var refused: [String: SnapshotFileRefusal] = [:]
        let projectsFolder = folder.appendingPathComponent("projects")
        for name in entries(of: projectsFolder) {
            let projectFolder = projectsFolder.appendingPathComponent(name)
            if let project = readBlock(projectFolder.appendingPathComponent("project"), &refused).flatMap(ProjectRecord.init(block:)),
               project.project == name {
                projects.append(project)
                let lanesFolder = projectFolder.appendingPathComponent("lanes")
                for laneName in entries(of: lanesFolder) {
                    guard var lane = readBlock(lanesFolder.appendingPathComponent(laneName), &refused).flatMap(LaneRecord.init(block:)),
                          lane.project == name, lane.lane == laneName else { continue }
                    enrich(&lane, root: project.root)
                    lanes.append(lane)
                }
            }
        }
        return Result(labVersion: version, projects: projects, lanes: lanes, refused: refused)
    }

    private func entries(of folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { LabName($0) != nil }.sorted()
    }

    private func readBlock(_ file: URL, _ refused: inout [String: SnapshotFileRefusal]) -> KeyValueBlock? {
        do {
            return parser.blocks(in: try gate.read(file, within: folder)).first
        } catch let refusal as SnapshotFileRefusal {
            if refusal != .missing { refused[String(file.path.dropFirst(folder.path.count + 1))] = refusal }
            return nil
        } catch {
            return nil
        }
    }

    /// Reads `permanent=` from the lane's `.lab/meta` and the date of its `.lab/waits-for`,
    /// only when they sit in the lane's own folder under the project's root.
    private func enrich(_ lane: inout LaneRecord, root: String) {
        guard root.hasPrefix("/") else { return }
        let labFolder = URL(fileURLWithPath: root).appendingPathComponent(".worktrees/\(lane.lane)/.lab")
        if let meta = lane.metaPath, URL(fileURLWithPath: meta).standardizedFileURL == labFolder.appendingPathComponent("meta").standardizedFileURL,
           let text = try? gate.read(URL(fileURLWithPath: meta), within: labFolder) {
            lane.permanent = text.split(separator: "\n").contains("permanent=yes")
        }
        if let waits = lane.waitsForPath, URL(fileURLWithPath: waits).standardizedFileURL == labFolder.appendingPathComponent("waits-for").standardizedFileURL {
            lane.waitingSince = gate.modificationDate(of: URL(fileURLWithPath: waits), within: labFolder)
        }
    }
}
