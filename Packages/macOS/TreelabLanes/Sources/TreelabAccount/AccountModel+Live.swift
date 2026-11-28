public import Foundation
public import TreelabLanes

extension AccountModel {
    /// The model wired to the person's lab: found by ``LabExecutableLocator`` before each call,
    /// woken by the kernel when the `WATCH=` file's folder changes. The app's composition root calls it once.
    /// - Parameter home: the person's home folder.
    /// - Returns: a model, not started.
    public static func live(home: URL) -> AccountModel {
        AccountModel(
            runner: ProcessLabCommandRunner(locator: LabExecutableLocator(candidates: LabExecutableLocator.defaultCandidates(home: home))),
            watcher: fileWatcher()
        )
    }

    /// The model on a demo folder (``DemoAccountLab``): runs no program.
    /// - Parameter folder: the demo folder.
    /// - Returns: a model, not started.
    public static func demo(folder: URL) -> AccountModel {
        AccountModel(runner: DemoAccountLab(folder: folder), watcher: fileWatcher())
    }

    /// What wakes the account: the kernel's watch of the `WATCH=` file's folder (lab replaces the
    /// file by a rename). FSEvents is not used: it stays silent for processes started from some
    /// sessions (lot 09), where the kernel's watch sees every rename.
    public static func fileWatcher() -> any FileEventWatching {
        KernelDirectoryWatcher()
    }
}
