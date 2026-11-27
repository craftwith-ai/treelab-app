public import Foundation
import AppKit
public import TreelabLanes

extension GinkgoModel {
    /// The model wired to the user's Ginkgo: its socket under lab's state folder, lab found by
    /// ``LabExecutableLocator``, the system's signals. The app's composition root calls it once.
    /// - Parameters:
    ///   - home: the user's home folder.
    ///   - clientVersion: Treelab's version.
    ///   - focus: the project of the lane shown.
    /// - Returns: a model, not started.
    public static func live(home: URL, clientVersion: String, focus: @escaping @MainActor () -> LabName?) -> GinkgoModel {
        GinkgoModel(
            runner: ProcessLabCommandRunner(locator: LabExecutableLocator(candidates: LabExecutableLocator.defaultCandidates(home: home))),
            location: .standard(home: home),
            signals: GinkgoSystemSignals(),
            defaults: .standard,
            clientVersion: clientVersion,
            focus: focus,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
    }

    /// The model on a demo folder: the stand-in Ginkgo's socket `<folder>/ginkgo/app.sock`, a lab
    /// that runs nothing (``DemoLabRunner``), its own preferences.
    /// - Parameters:
    ///   - folder: the demo folder.
    ///   - clientVersion: Treelab's version.
    ///   - focus: the project of the lane shown.
    /// - Returns: a model, not started.
    public static func demo(folder: URL, clientVersion: String, focus: @escaping @MainActor () -> LabName?) -> GinkgoModel {
        GinkgoModel(
            runner: DemoLabRunner(folder: folder),
            location: GinkgoSocketLocation(path: folder.appendingPathComponent("ginkgo/app.sock").path),
            signals: GinkgoSystemSignals(),
            defaults: UserDefaults(suiteName: "sh.treelab.ginkgo.demo") ?? .standard,
            clientVersion: clientVersion,
            focus: focus,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
    }
}
