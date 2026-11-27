import Foundation
import os
import TreelabLanes

/// What the fake lab received for one call: its exact arguments and what came on standard input.
struct ReceivedCall: Sendable, Equatable {
    let arguments: [String]
    let standardInput: Data?
}

/// A lab that records every call (arguments and standard input) and answers from a script.
actor FakeLab: LabCommandRunning {
    private(set) var calls: [ReceivedCall] = []
    private let answer: @Sendable (LabCommand) -> LabCommandOutput

    init(answer: @escaping @Sendable (LabCommand) -> LabCommandOutput) {
        self.answer = answer
    }

    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        calls.append(ReceivedCall(arguments: command.arguments, standardInput: command.standardInput?.standardInputData))
        return answer(command)
    }

    /// The arguments of every call, in order.
    var arguments: [[String]] { calls.map(\.arguments) }

    /// Forgets the calls made so far (the first reading), to look at one action alone.
    func forget() { calls = [] }
}

/// A lab that cannot be started.
struct MissingLab: LabCommandRunning {
    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        throw LanesProblem.labUnavailable("lab not located")
    }
}

/// A file watcher driven by the test: `emit` sends a path to every stream watching its folder.
final class ScriptedFolders: FileEventWatching {
    private let streams = OSAllocatedUnfairLock<[(paths: [String], continuation: AsyncStream<[String]>.Continuation)]>(initialState: [])

    func changes(under paths: [String]) -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        streams.withLock { $0.append((paths, continuation)) }
        return stream
    }

    var watched: [[String]] { streams.withLock { $0.map(\.paths) } }

    func emit(_ path: String) {
        let targets = streams.withLock { $0.filter { entry in entry.paths.contains { path == $0 || path.hasPrefix($0 + "/") } } }
        for target in targets { target.continuation.yield([path]) }
    }
}

func ok(_ text: String) -> LabCommandOutput {
    LabCommandOutput(status: 0, standardOutput: text, standardError: "")
}

func refused(_ reason: String) -> LabCommandOutput {
    LabCommandOutput(status: 2, standardOutput: "REASON=\(reason)\n", standardError: "lab: ERROR \(reason)\n")
}

/// `lab app account` for a person on day 5 of the 14-day trial, offer of treelab included.
let trialAccount = """
PROTOCOL=1
SIGNED_IN=yes
EMAIL=camille@exemple.fr
PLAN=trial
STATE=trial
TRIAL_DAYS_LEFT=9
SEATS=1
CHECKED=2026-11-27T10:00:00Z
WATCH=/Users/camille/.lab/state/account
OFFER_TRIAL_DAYS=14
OFFER_MONTH=39
OFFER_YEAR=390
OFFER_CURRENCY=EUR
OFFER_TAX=included
OFFER_DISCOUNT_PCT=20
OFFER_DISCOUNT_FROM=5

"""

let ginkgoSettings = "LISTEN=command\nSPEAK=always\nQUIET=21:00-08:00\n"

/// A lab that speaks the contract: the trial account, Ginkgo's settings, the key stored.
func currentLab(account: String = trialAccount, ginkgo: String = ginkgoSettings, key: String = "KEY=present",
                actions: @escaping @Sendable (LabCommand) -> LabCommandOutput? = { _ in nil }) -> FakeLab {
    FakeLab { command in
        if let answer = actions(command) { return answer }
        switch command.arguments {
        case ["app", "account"]: return ok(account)
        case ["app", "ginkgo"]: return ok(ginkgo)
        case ["ginkgo", "status"]: return ok("PROVIDER=openai\n\(key)\nAPP=/Applications/Ginkgo.app\nSOURCE=release\n")
        default: return ok("")
        }
    }
}

/// A lab of today, before the contract: `lab app account` is an unknown command.
func oldLab(actions: @escaping @Sendable (LabCommand) -> LabCommandOutput? = { _ in nil }) -> FakeLab {
    FakeLab { command in
        if let answer = actions(command) { return answer }
        switch command.arguments {
        case ["ginkgo", "status"]: return ok("PROVIDER=openai\nKEY=absent\n")
        case ["subscribe"]: return ok("SUBSCRIBE=checkout\nRESULT=opened\n")
        case ["ginkgo", "key", "openai"]: return ok("KEY=stored\n")
        default: return LabCommandOutput(status: 2, standardOutput: "", standardError: "lab: ERROR unknown command: \(command.arguments.prefix(2).joined(separator: " "))\n")
        }
    }
}

/// Waits for `condition`, checking after each yield of the test's own task, at most `seconds`.
func eventually(_ seconds: Double = 3, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// A private temporary folder for one test, removed at the end.
final class ScratchFolder {
    let url: URL

    init() throws {
        let created = FileManager.default.temporaryDirectory.appendingPathComponent("treelab-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        let real = realpath(created.path, nil)
        url = URL(fileURLWithPath: real.map { String(cString: $0) } ?? created.path)
        free(real)
        chmod(url.path, 0o700)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var path: String { url.path }
}
