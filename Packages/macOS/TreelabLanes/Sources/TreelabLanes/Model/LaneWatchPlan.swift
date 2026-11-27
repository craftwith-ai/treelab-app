public import Foundation

/// What to watch so a lane is rewritten exactly when it can change: the documents lab does not
/// keep up to date itself (`WATCH=` minus `WRITTEN=`, `WATCH_ENTRIES=`), the processes
/// (`WATCH_PID=`) and the first date (`WAKE_AT=`).
public struct LaneWatchPlan: Sendable, Equatable {
    /// Files whose change calls for a targeted snapshot.
    public var files: [String: Set<LaneTarget>]
    /// Folders whose entries' change calls for a targeted snapshot.
    public var entries: [String: Set<LaneTarget>]
    /// Processes whose end calls for a targeted snapshot.
    public var processes: [Int32: Set<LaneTarget>]
    /// The next date a lane may change by itself, with its lanes.
    public var nextWake: (date: Date, targets: Set<LaneTarget>)?

    /// Builds the plan from what was read.
    /// - Parameters:
    ///   - projects: projects read.
    ///   - lanes: lanes read.
    ///   - now: the current date; earlier wake dates are ignored.
    public init(projects: [ProjectRecord], lanes: [LaneRecord], now: Date) {
        var files: [String: Set<LaneTarget>] = [:]
        var entries: [String: Set<LaneTarget>] = [:]
        var processes: [Int32: Set<LaneTarget>] = [:]
        var wake: (date: Date, targets: Set<LaneTarget>)?
        for project in projects {
            let target = LaneTarget(project: project.project, lane: nil)
            for path in project.watchPaths where path.hasPrefix("/") { files[path, default: []].insert(target) }
            for path in project.watchEntries where path.hasPrefix("/") { entries[path, default: []].insert(target) }
        }
        for lane in lanes {
            let target = LaneTarget(project: lane.project, lane: lane.lane)
            let written = Set(lane.writtenPaths)
            for path in lane.watchPaths where path.hasPrefix("/") && !written.contains(path) {
                files[path, default: []].insert(target)
            }
            for path in lane.watchEntries where path.hasPrefix("/") { entries[path, default: []].insert(target) }
            for pid in lane.watchPIDs where pid > 1 { processes[pid, default: []].insert(target) }
            if let date = lane.wakeAt, date > now {
                if let current = wake, current.date < date { continue }
                if let current = wake, current.date == date { wake = (date, current.targets.union([target])) } else { wake = (date, [target]) }
            }
        }
        self.files = files
        self.entries = entries
        self.processes = processes
        self.nextWake = wake
    }

    /// The folders FSEvents watches for ``files``: each file's own folder.
    public var fileFolders: [String] {
        Set(files.keys.map { ($0 as NSString).deletingLastPathComponent }).sorted()
    }

    /// The folders whose entries are watched (``KernelDirectoryWatcher``, not recursive).
    public var entryFolders: [String] { entries.keys.sorted() }

    /// The targets a changed path concerns: a watched file, or a watched folder itself (its entries changed).
    /// - Parameter path: a path a watcher reported.
    /// - Returns: the lanes and projects to rewrite.
    public func targets(for path: String) -> Set<LaneTarget> {
        (files[path] ?? []).union(entries[path] ?? [])
    }

    public static func == (lhs: LaneWatchPlan, rhs: LaneWatchPlan) -> Bool {
        lhs.files == rhs.files && lhs.entries == rhs.entries && lhs.processes == rhs.processes
            && lhs.nextWake?.date == rhs.nextWake?.date && lhs.nextWake?.targets == rhs.nextWake?.targets
    }
}
