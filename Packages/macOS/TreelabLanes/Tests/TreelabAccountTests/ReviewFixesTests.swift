import Foundation
import os
import Testing
import TreelabLanes

@testable import TreelabAccount

// MARK: Findings of the batch's single review, against the account contract v1.1

/// A lab whose `app signin` takes a while, as a real one talking to treelab's server.
actor SlowSignInLab: LabCommandRunning {
    private(set) var calls: [[String]] = []

    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        calls.append(command.arguments)
        switch command.arguments.prefix(2) {
        case ["app", "account"]: return ok(trialAccount.replacingOccurrences(of: "SIGNED_IN=yes", with: "SIGNED_IN=no"))
        case ["app", "ginkgo"]: return ok(ginkgoSettings)
        case ["app", "signin"]:
            try await Task.sleep(for: .milliseconds(300))
            return ok("SENT=yes\nEMAIL=camille@exemple.fr\n")
        default: return ok("PROVIDER=openai\nKEY=absent\n")
        }
    }
}

/// A v1.1 refusal: `REASON=` is a code on standard output, the clear text is on stderr.
func refusedV11(_ code: String, _ text: String) -> LabCommandOutput {
    LabCommandOutput(status: 2, standardOutput: "REASON=\(code)\n", standardError: "lab: ERROR \(text)\n")
}

@Suite("Review fixes: refusals, one action at a time, the WATCH= folder")
@MainActor
struct AccountReviewFixesTests {
    @Test("v1.1: REASON=unsupported (sign-in, sign-out before the accounts) is the next treelab version")
    func unsupportedIsNextVersion() async {
        let lab = currentLab { command in
            switch command {
            case .signIn: return refusedV11("unsupported", "accounts come with a later treelab version")
            case .signOutEverywhere: return refusedV11("unsupported", "accounts come with a later treelab version")
            default: return nil
            }
        }
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        await account.signIn(email: "camille@exemple.fr")
        #expect(account.notice == .nextVersion)
        account.clearNotice()
        await account.signOutEverywhere()
        #expect(account.notice == .nextVersion)
    }

    @Test("v1.1: any other refusal is said in lab's clear words (stderr), never by its machine code")
    func otherRefusalsInClearWords() async {
        let lab = currentLab { command in
            switch command {
            case .setGinkgo: return refusedV11("invalid", "an empty quiet range is refused")
            case .exportData: return refusedV11("unwritable", "~/.lab/config cannot be written, nothing changed")
            case .subscribe: return LabCommandOutput(status: 2, standardOutput: "REASON=usage\n", standardError: "")
            default: return nil
            }
        }
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        await account.setQuiet("22:00-07:00")
        #expect(account.notice == .refused("an empty quiet range is refused"))
        await account.exportData(to: URL(fileURLWithPath: "/Users/camille/Documents"))
        #expect(account.notice == .refused("~/.lab/config cannot be written, nothing changed"))
        // No clear text: the code is all lab said.
        await account.subscribe()
        #expect(account.notice == .refused("usage"))
    }

    @Test("Return pressed twice in the e-mail field sends one sign-in only")
    func oneSignInAtATime() async {
        let lab = SlowSignInLab()
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        async let first: Void = account.signIn(email: "camille@exemple.fr")
        async let second: Void = account.signIn(email: "camille@exemple.fr")
        _ = await (first, second)
        #expect(await lab.calls.filter { $0.prefix(2) == ["app", "signin"] }.count == 1)
    }

    private func watchingLab(_ file: String) -> FakeLab {
        currentLab(account: trialAccount.replacingOccurrences(of: "WATCH=/Users/camille/.lab/state/account", with: "WATCH=\(file)"))
    }

    @Test("a WATCH= folder missing at the first reading is watched once it exists (next reading)")
    func missingFolderArmedLater() async throws {
        let scratch = try ScratchFolder()
        let folder = scratch.url.appendingPathComponent("state")
        let file = folder.appendingPathComponent("account")
        let watcher = ScriptedFolders()
        let account = AccountModel(runner: watchingLab(file.path), watcher: watcher)
        await account.refresh()
        #expect(watcher.watched == [[folder.path]])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        // The settings opening reads the account again.
        await account.refresh()
        #expect(watcher.watched == [[folder.path], [folder.path]])
    }

    @Test("a WATCH= folder removed then made again is watched again (next reading)")
    func recreatedFolderArmedAgain() async throws {
        let scratch = try ScratchFolder()
        let folder = scratch.url.appendingPathComponent("state")
        let file = folder.appendingPathComponent("account")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        let watcher = ScriptedFolders()
        let account = AccountModel(runner: watchingLab(file.path), watcher: watcher)
        await account.refresh()
        #expect(watcher.watched.count == 1)
        // Keep the old folder's inode taken, so the new folder cannot reuse it.
        let moved = scratch.url.appendingPathComponent("state-old")
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        await account.refresh()
        #expect(watcher.watched.count == 2)
        // Nothing changed since: not armed a third time.
        await account.refresh()
        #expect(watcher.watched.count == 2)
    }
}
