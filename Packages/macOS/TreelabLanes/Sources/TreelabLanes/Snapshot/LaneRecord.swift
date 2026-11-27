public import Foundation

/// One lane as lab describes it for Treelab (`lab app lanes`, one snapshot file per lane).
public struct LaneRecord: Sendable, Equatable, Identifiable {
    /// `project/lane`, unique across projects.
    public var id: String { "\(project)/\(lane)" }
    /// The project name (`PROJECT=`).
    public var project: String
    /// The lane name (`LANE=`).
    public var lane: String
    /// What the lane waits for (`WAITS_FOR=`): `you`, `merge`, `acceptance`, `close`, `date`, `ci` or `nothing`.
    public var waitsFor: String
    /// Why, in lab's words (`WHY=`); text written by a lane, shown, never executed.
    public var why: String
    /// Whether an agent session runs in the lane (`SESSION=live`).
    public var sessionLive: Bool
    /// The current batch (`BATCH=`), for example `lot-02-api`.
    public var batch: String
    /// The batch state (`BATCH_STATE=`), as written in the batch file.
    public var batchState: String
    /// The tower's rule: the user must act (`FOR_YOU=yes`).
    public var forYou: Bool
    /// The first date the lane can change without a file (`WAKE_AT=`, epoch seconds).
    public var wakeAt: Date?
    /// Files whose change can change this lane (`WATCH=`).
    public var watchPaths: [String]
    /// Folders whose entries can change this lane (`WATCH_ENTRIES=`).
    public var watchEntries: [String]
    /// Paths lab keeps up to date itself (`WRITTEN=`): their change needs no new snapshot.
    public var writtenPaths: [String]
    /// Processes whose end changes this lane (`WATCH_PID=`).
    public var watchPIDs: [Int32]
    /// A permanent lane (`permanent=yes` in its `.lab/meta`), never counted at rest.
    public var permanent: Bool
    /// When the lane started to wait (date of its `.lab/waits-for`), used to order requests.
    public var waitingSince: Date?

    /// Creates a lane.
    /// - Parameters:
    ///   - project: the project name.
    ///   - lane: the lane name.
    ///   - waitsFor: `WAITS_FOR=`, `nothing` by default.
    ///   - why: `WHY=`, empty by default.
    ///   - sessionLive: `SESSION=live`.
    ///   - batch: `BATCH=`.
    ///   - batchState: `BATCH_STATE=`.
    ///   - forYou: `FOR_YOU=yes`.
    ///   - wakeAt: `WAKE_AT=` as a date.
    ///   - watchPaths: `WATCH=`.
    ///   - watchEntries: `WATCH_ENTRIES=`.
    ///   - writtenPaths: `WRITTEN=`.
    ///   - watchPIDs: `WATCH_PID=`.
    ///   - permanent: a permanent lane.
    ///   - waitingSince: when the wait started.
    public init(
        project: String,
        lane: String,
        waitsFor: String = "nothing",
        why: String = "",
        sessionLive: Bool = false,
        batch: String = "",
        batchState: String = "",
        forYou: Bool = false,
        wakeAt: Date? = nil,
        watchPaths: [String] = [],
        watchEntries: [String] = [],
        writtenPaths: [String] = [],
        watchPIDs: [Int32] = [],
        permanent: Bool = false,
        waitingSince: Date? = nil
    ) {
        self.project = project
        self.lane = lane
        self.waitsFor = waitsFor
        self.why = why
        self.sessionLive = sessionLive
        self.batch = batch
        self.batchState = batchState
        self.forYou = forYou
        self.wakeAt = wakeAt
        self.watchPaths = watchPaths
        self.watchEntries = watchEntries
        self.writtenPaths = writtenPaths
        self.watchPIDs = watchPIDs
        self.permanent = permanent
        self.waitingSince = waitingSince
    }

    /// Reads a lane from its block; `nil` without `PROJECT=` or `LANE=`.
    /// - Parameter block: one block of `lab app lanes` or of a lane snapshot file.
    public init?(block: KeyValueBlock) {
        guard let project = block.first("PROJECT"), !project.isEmpty,
              let lane = block.first("LANE"), !lane.isEmpty else { return nil }
        self.init(
            project: project,
            lane: lane,
            waitsFor: block.first("WAITS_FOR") ?? "nothing",
            why: block.first("WHY") ?? "",
            sessionLive: block.first("SESSION") == "live",
            batch: block.first("BATCH") ?? "",
            batchState: block.first("BATCH_STATE") ?? "",
            forYou: block.first("FOR_YOU") == "yes",
            wakeAt: block.first("WAKE_AT").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)),
            watchPaths: block.all("WATCH"),
            watchEntries: block.all("WATCH_ENTRIES"),
            writtenPaths: block.all("WRITTEN"),
            watchPIDs: block.all("WATCH_PID").compactMap(Int32.init)
        )
    }

    /// The lane's `.lab/meta` among its watched files, if lab lists it.
    public var metaPath: String? { watchPaths.first { $0.hasSuffix("/.lab/meta") } }

    /// The lane's `.lab/waits-for` among the watched or written files, if lab lists it.
    public var waitsForPath: String? {
        (watchPaths + writtenPaths).first { $0.hasSuffix("/.lab/waits-for") }
    }
}
