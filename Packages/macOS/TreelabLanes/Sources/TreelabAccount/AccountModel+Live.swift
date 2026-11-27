public import Foundation
import TreelabLanes

extension AccountModel {
    /// The model wired to the person's lab: found by ``LabExecutableLocator`` before each call,
    /// woken by FSEvents on the `WATCH=` file. The app's composition root calls it once.
    /// - Parameter home: the person's home folder.
    /// - Returns: a model, not started.
    public static func live(home: URL) -> AccountModel {
        AccountModel(
            runner: ProcessLabCommandRunner(locator: LabExecutableLocator(candidates: LabExecutableLocator.defaultCandidates(home: home))),
            watcher: FSEventsFileWatcher()
        )
    }

    /// The model on a demo folder (``DemoAccountLab``): runs no program.
    /// - Parameter folder: the demo folder.
    /// - Returns: a model, not started.
    public static func demo(folder: URL) -> AccountModel {
        AccountModel(runner: DemoAccountLab(folder: folder), watcher: FSEventsFileWatcher())
    }
}
