/// One project as lab describes it for Treelab (a project snapshot file).
public struct ProjectRecord: Sendable, Equatable, Identifiable {
    /// The project name.
    public var id: String { project }
    /// The project name (`PROJECT=`).
    public var project: String
    /// The main checkout (`ROOT=`); each lane lives under `ROOT/.worktrees/<lane>`.
    public var root: String
    /// Files whose change can change the project (`WATCH=`).
    public var watchPaths: [String]
    /// Folders whose entries can change the project (`WATCH_ENTRIES=`).
    public var watchEntries: [String]

    /// Creates a project.
    /// - Parameters:
    ///   - project: the project name.
    ///   - root: the main checkout path.
    ///   - watchPaths: `WATCH=`.
    ///   - watchEntries: `WATCH_ENTRIES=`.
    public init(project: String, root: String, watchPaths: [String] = [], watchEntries: [String] = []) {
        self.project = project
        self.root = root
        self.watchPaths = watchPaths
        self.watchEntries = watchEntries
    }

    /// Reads a project from its block; `nil` without `PROJECT=` or `ROOT=`.
    /// - Parameter block: the content of a project snapshot file.
    public init?(block: KeyValueBlock) {
        guard let project = block.first("PROJECT"), !project.isEmpty,
              let root = block.first("ROOT"), root.hasPrefix("/") else { return nil }
        self.init(project: project, root: root, watchPaths: block.all("WATCH"), watchEntries: block.all("WATCH_ENTRIES"))
    }
}
