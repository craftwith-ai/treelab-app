public import Foundation

extension LanesModel {
    /// The model wired to the real lab of the user: `~/.lab/state/app-snapshot`, lab found by
    /// ``LabExecutableLocator``, kernel and FSEvents watchers. The app's composition root calls it once.
    /// - Parameters:
    ///   - home: the user's home folder.
    ///   - readerPID: Treelab's process id.
    /// - Returns: a model, not started.
    public static func live(home: URL, readerPID: Int32) -> LanesModel {
        let locator = LabExecutableLocator(candidates: LabExecutableLocator.defaultCandidates(home: home))
        var runner: (any LabCommandRunning)?
        var unavailable: LanesProblem?
        do {
            runner = ProcessLabCommandRunner(executable: try locator.locate(), locator: locator)
        } catch let problem as LanesProblem {
            unavailable = problem
        } catch {
            unavailable = .labUnavailable(error.localizedDescription)
        }
        let service = LanesService(
            reader: SnapshotFolderReader(folder: home.appendingPathComponent(".lab/state/app-snapshot")),
            runner: runner,
            unavailable: unavailable,
            readerPID: readerPID,
            files: FSEventsFileWatcher(),
            entries: KernelDirectoryWatcher(),
            exits: KernelProcessExitWatcher()
        )
        return LanesModel(service: service, runner: runner)
    }

    /// The model on an invented demo folder (`app-snapshot/`, `questions/`): reads like the real
    /// one, runs no program (``DemoLabRunner``), refuses every action.
    /// - Parameters:
    ///   - folder: the demo folder.
    ///   - readerPID: Treelab's process id.
    /// - Returns: a model, not started.
    public static func demo(folder: URL, readerPID: Int32) -> LanesModel {
        let runner = DemoLabRunner(folder: folder)
        let service = LanesService(
            reader: SnapshotFolderReader(folder: folder.appendingPathComponent("app-snapshot")),
            runner: runner,
            readerPID: readerPID,
            files: FSEventsFileWatcher(),
            entries: KernelDirectoryWatcher(),
            exits: KernelProcessExitWatcher()
        )
        return LanesModel(service: service, runner: runner)
    }
}
