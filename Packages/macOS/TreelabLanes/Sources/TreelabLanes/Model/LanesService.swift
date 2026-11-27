public import Foundation

/// Treelab's link to lab: declares the app as reader, reads the snapshot folder again when it
/// changes, and asks lab for a targeted snapshot only when a watched document changes, a watched
/// process ends or a wake date comes. No timer, no network.
///
/// ```swift
/// let service = LanesService(reader: SnapshotFolderReader(folder: folder), runner: runner, readerPID: getpid(),
///                            files: FSEventsFileWatcher(), entries: KernelDirectoryWatcher(),
///                            exits: KernelProcessExitWatcher())
/// for await state in await service.states() { … }
/// ```
public actor LanesService {
    private let reader: SnapshotFolderReader
    private let builder = LanesSnapshotBuilder()
    private let runner: (any LabCommandRunning)?
    private let unavailable: LanesProblem?
    private let readerPID: Int32
    private let files: any FileEventWatching
    private let entries: any FileEventWatching
    private let exits: any ProcessExitWatching
    private let now: @Sendable () -> Date

    private var state = LanesState()
    private var observers: [UUID: AsyncStream<LanesState>.Continuation] = [:]
    private var started = false
    private var registration: LanesProblem?
    private var plan: LaneWatchPlan?
    private var folderTask: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?
    private var entriesTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var inFlight: Set<LaneTarget> = []
    private var snapshotFolders: [String] = []

    /// Creates the service.
    /// - Parameters:
    ///   - reader: reads the snapshot folder.
    ///   - runner: runs lab; `nil` when lab is unavailable, with the reason in `unavailable`.
    ///   - unavailable: why lab cannot run, shown on screen.
    ///   - readerPID: Treelab's process id, lab's reader mark.
    ///   - files: the file watcher (FSEvents in the app).
    ///   - entries: the folder-entries watcher (``KernelDirectoryWatcher`` in the app), for the
    ///     snapshot folders and `WATCH_ENTRIES=`.
    ///   - exits: the process-exit watcher.
    ///   - now: the clock for wake dates.
    public init(
        reader: SnapshotFolderReader,
        runner: (any LabCommandRunning)?,
        unavailable: LanesProblem? = nil,
        readerPID: Int32,
        files: any FileEventWatching,
        entries: any FileEventWatching,
        exits: any ProcessExitWatching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.reader = reader
        self.runner = runner
        self.unavailable = unavailable
        self.readerPID = readerPID
        self.files = files
        self.entries = entries
        self.exits = exits
        self.now = now
    }

    /// The states, starting with the current one.
    /// - Returns: a stream that ends when the caller drops it.
    public func states() -> AsyncStream<LanesState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LanesState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(state)
        observers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    /// Declares Treelab as reader (one full `lab app snapshot --reader <pid>`), reads the folder
    /// and starts watching. Calling it again does nothing.
    public func start() async {
        guard !started else { return }
        started = true
        if let runner {
            do {
                let output = try await runner.run(.snapshot(readerPID: readerPID, project: nil, lane: nil))
                registration = output.status == 0 ? nil : .labRefused(output.refusal)
            } catch let problem as LanesProblem {
                registration = problem
            } catch {
                registration = .labUnavailable(error.localizedDescription)
            }
        } else {
            registration = unavailable ?? .labUnavailable("")
        }
        reload()
    }

    /// Stops every watch.
    public func stop() {
        for task in [folderTask, documentTask, entriesTask, processTask, wakeTask] { task?.cancel() }
        folderTask = nil; documentTask = nil; entriesTask = nil; processTask = nil; wakeTask = nil
        plan = nil
        snapshotFolders = []
        started = false
    }

    /// Reads the folder again and publishes the result.
    public func reload() {
        do {
            let result = try reader.read()
            state = LanesState(
                snapshot: builder.snapshot(projects: result.projects, lanes: result.lanes, labVersion: result.labVersion),
                problem: registration,
                refusedFiles: result.refused,
                loaded: true
            )
            updateWatches(LaneWatchPlan(projects: result.projects, lanes: result.lanes, now: now()))
            watchSnapshotFolders(result.projects.map(\.project))
        } catch let problem as LanesProblem {
            state = LanesState(snapshot: .empty, problem: problem, refusedFiles: [:], loaded: true)
            updateWatches(nil)
            watchSnapshotFolders([])
        } catch {
            state = LanesState(snapshot: .empty, problem: .labUnavailable(error.localizedDescription), loaded: true)
            updateWatches(nil)
            watchSnapshotFolders([])
        }
        for observer in observers.values { observer.yield(state) }
    }

    /// Asks lab to rewrite `target`'s snapshot file, once at a time per target.
    /// - Parameter target: the project or lane.
    public func refresh(_ target: LaneTarget) async {
        guard let runner, let command = target.command(readerPID: readerPID), !inFlight.contains(target) else { return }
        inFlight.insert(target)
        _ = try? await runner.run(command)
        inFlight.remove(target)
    }

    private func refresh(_ targets: Set<LaneTarget>) async {
        for target in targets.sorted(by: { ($0.project, $0.lane ?? "") < ($1.project, $1.lane ?? "") }) {
            await refresh(target)
        }
    }

    private func updateWatches(_ newPlan: LaneWatchPlan?) {
        let old = plan
        plan = newPlan
        if old?.files != newPlan?.files {
            documentTask?.cancel()
            documentTask = nil
            if let newPlan, !newPlan.fileFolders.isEmpty {
                let stream = files.changes(under: newPlan.fileFolders)
                documentTask = Task { [weak self] in
                    for await paths in stream { await self?.documentsChanged(paths) }
                }
            }
        }
        if old?.entries != newPlan?.entries {
            entriesTask?.cancel()
            entriesTask = nil
            if let newPlan, !newPlan.entryFolders.isEmpty {
                let stream = entries.changes(under: newPlan.entryFolders)
                entriesTask = Task { [weak self] in
                    for await paths in stream { await self?.documentsChanged(paths) }
                }
            }
        }
        if old?.processes != newPlan?.processes {
            processTask?.cancel()
            processTask = nil
            if let newPlan, !newPlan.processes.isEmpty {
                let stream = exits.exits(of: Array(newPlan.processes.keys))
                processTask = Task { [weak self] in
                    for await pid in stream { await self?.processEnded(pid) }
                }
            }
        }
        if old?.nextWake?.date != newPlan?.nextWake?.date || old?.nextWake?.targets != newPlan?.nextWake?.targets {
            wakeTask?.cancel()
            wakeTask = nil
            if let wake = newPlan?.nextWake {
                let delay = max(0, wake.date.timeIntervalSince(now()))
                // A genuine deadline (the lane's own WAKE_AT), one-shot and cancelled on change.
                wakeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 50))
                    guard !Task.isCancelled else { return }
                    await self?.refresh(wake.targets)
                }
            }
        }
    }

    /// lab replaces each snapshot file by an atomic rename (`mv -f`), so watching the folders'
    /// entries (kqueue, no depth) sees every rewrite: the root, `projects/`, and each project's
    /// folder and `lanes/` folder.
    private func watchSnapshotFolders(_ projects: [String]) {
        let root = reader.folder.path
        var folders = [root, root + "/projects"]
        for project in projects {
            folders += [root + "/projects/" + project, root + "/projects/" + project + "/lanes"]
        }
        guard folders != snapshotFolders else { return }
        snapshotFolders = folders
        folderTask?.cancel()
        let stream = entries.changes(under: folders)
        folderTask = Task { [weak self] in
            for await _ in stream { await self?.reload() }
        }
    }

    private func documentsChanged(_ paths: [String]) async {
        guard let plan else { return }
        var targets: Set<LaneTarget> = []
        for path in paths { targets.formUnion(plan.targets(for: path)) }
        await refresh(targets)
    }

    private func processEnded(_ pid: Int32) async {
        guard let targets = plan?.processes[pid] else { return }
        await refresh(targets)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
