public import Foundation
public import TreelabLanes

/// A stand-in for lab's account commands that never runs a program, to show the welcome and the
/// settings on invented accounts (screens, trials) without touching the person's lab, keychain or
/// treelab account.
///
/// It answers from files of a demo folder, read through ``SnapshotFileGate``:
/// - `account`: the text of `lab app account` (contract v1.1); without it, lab is "the one of today"
///   and `lab app account` is an unknown command (the "next version" state);
/// - `ginkgo`: the text of `lab app ginkgo`; `ginkgo-status`: the text of `lab ginkgo status`;
/// - `refuse`: when present, its first line is lab's `REASON=` code for every action, its second
///   line lab's clear text on stderr (v1.1).
///
/// Actions answer as the contract says, keep their effect in memory only (Ginkgo's settings, the
/// key said present) and are written, arguments only, to `actions.log`. The key itself is never
/// written nor kept: only its length is noted.
public actor DemoAccountLab: LabCommandRunning {
    private let folder: URL
    private let gate: SnapshotFileGate
    private var settings: [String: String] = [:]
    private var keyStored = false
    private var token: String?

    /// Creates the stand-in.
    /// - Parameters:
    ///   - folder: the demo folder.
    ///   - gate: the file checks.
    public init(folder: URL, gate: SnapshotFileGate = SnapshotFileGate()) {
        self.folder = folder
        self.gate = gate
    }

    /// Answers without running anything.
    /// - Parameter command: the command.
    /// - Returns: the contract's answer for the demo folder.
    public func run(_ command: LabCommand) async throws -> LabCommandOutput {
        switch command {
        case .account:
            guard let text = file("account") else { return unknownCommand(command) }
            return ok(text)
        case .ginkgoSettings:
            guard file("account") != nil else { return unknownCommand(command) }
            return ok(ginkgoText())
        case .ginkgoStatus:
            let text = file("ginkgo-status") ?? "PROVIDER=openai\nKEY=absent\n"
            return ok(keyStored ? text.replacingOccurrences(of: "KEY=absent", with: "KEY=present") : text)
        default:
            break
        }
        note(command)
        let refusal = file("refuse")?.split(separator: "\n").map(String.init) ?? []
        if let reason = refusal.first, !reason.isEmpty {
            let words = refusal.count > 1 ? "lab: ERROR \(refusal[1])\n" : ""
            return LabCommandOutput(status: 2, standardOutput: "REASON=\(reason)\n", standardError: words)
        }
        switch command {
        case .subscribe:
            return ok("SUBSCRIBE=\(file("subscribe")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "checkout")\nRESULT=demo\n")
        case .storeOpenAIKey:
            keyStored = true
            return ok("KEY=stored\n")
        case .account, .ginkgoSettings, .ginkgoStatus:
            return ok("")
        default:
            break
        }
        guard file("account") != nil else { return unknownCommand(command) }
        switch command {
        case let .signIn(email):
            return ok("SENT=yes\nEMAIL=\(email.value)\n")
        case .signOutEverywhere:
            return ok("SIGNED_OUT=all\n")
        case let .setGinkgo(setting):
            settings[setting.option] = setting.value
            // v1.1: the listening mode waits for Ginkgo's next opening.
            return ok(ginkgoText() + "APPLIES=\(setting.option == "--listen" ? "next-open" : "now")\n")
        case let .exportData(path):
            return ok("EXPORTED=\(path.value)/treelab-export\n")
        case .eraseData:
            let issued = "demo-erase-\(Int.random(in: 1000...9999))"
            token = issued
            return ok("READBACK=\(file("erase-readback")?.split(separator: "\n").first.map(String.init) ?? "on this Mac only: the settings lab keeps for Ginkgo and Treelab, the account cache and the OpenAI key")\nTOKEN=\(issued)\n")
        case let .confirmErase(given):
            guard given.value == token else {
                return LabCommandOutput(status: 2, standardOutput: "REASON=invalid\n", standardError: "lab: ERROR the erase token has expired\n")
            }
            token = nil
            return ok("ERASED=yes\n")
        default:
            return LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR demo: nothing is sent\n")
        }
    }

    private func ok(_ text: String) -> LabCommandOutput {
        LabCommandOutput(status: 0, standardOutput: text, standardError: "")
    }

    private func unknownCommand(_ command: LabCommand) -> LabCommandOutput {
        LabCommandOutput(status: 2, standardOutput: "", standardError: "lab: ERROR unknown command: \(command.arguments.prefix(2).joined(separator: " "))\n")
    }

    private func file(_ name: String) -> String? {
        try? gate.read(folder.appendingPathComponent(name), within: folder)
    }

    private func ginkgoText() -> String {
        var values: [String: String] = ["--listen": "command", "--speak": "always", "--quiet": "21:00-08:00"]
        if let text = file("ginkgo") {
            for block in KeyValueBlockParser().blocks(in: text).prefix(1) {
                if let value = block.first("LISTEN") { values["--listen"] = value }
                if let value = block.first("SPEAK") { values["--speak"] = value }
                if let value = block.first("QUIET") { values["--quiet"] = value }
            }
        }
        values.merge(settings) { _, new in new }
        return "LISTEN=\(values["--listen"] ?? "")\nSPEAK=\(values["--speak"] ?? "")\nQUIET=\(values["--quiet"] ?? "")\n"
    }

    /// Appends the command's arguments to `actions.log`; a secret is noted by its length only.
    private func note(_ command: LabCommand) {
        var line = command.arguments.joined(separator: " ")
        if let secret = command.standardInput { line += " <standard input: \(secret.standardInputData.count) bytes>" }
        let log = folder.appendingPathComponent("actions.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: log, options: .withoutOverwriting)
        }
    }
}
