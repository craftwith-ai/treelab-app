import Foundation
import Testing

@testable import TreelabLanes

@Suite("Security by design: files")
struct SnapshotFileGateTests {
    @Test("a safe file is read")
    func safe() throws {
        let tmp = try TemporaryFolder()
        let file = try tmp.write("version", "1.8.2\n")
        #expect(try SnapshotFileGate().read(file, within: tmp.url) == "1.8.2\n")
    }

    @Test("a symbolic link is refused, even to a safe file inside the folder")
    func link() throws {
        let tmp = try TemporaryFolder()
        let target = try tmp.write("real", "x")
        let link = tmp.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: SnapshotFileRefusal.symbolicLink) { try SnapshotFileGate().read(link, within: tmp.url) }
    }

    @Test("a path leaving its folder is refused")
    func outside() throws {
        let tmp = try TemporaryFolder()
        let inner = try tmp.folder("inner")
        try tmp.write("secret", "x")
        let escaping = inner.appendingPathComponent("../secret")
        #expect(throws: SnapshotFileRefusal.outsideFolder) { try SnapshotFileGate().read(escaping, within: inner) }
        #expect(throws: SnapshotFileRefusal.outsideFolder) { try SnapshotFileGate().read(URL(fileURLWithPath: "/etc/hosts"), within: inner) }
    }

    @Test("a file others may write is refused (group or everyone)")
    func writable() throws {
        let tmp = try TemporaryFolder()
        let everyone = try tmp.write("a", "x", mode: 0o666)
        let group = try tmp.write("b", "x", mode: 0o664)
        #expect(throws: SnapshotFileRefusal.writableByOthers) { try SnapshotFileGate().read(everyone, within: tmp.url) }
        #expect(throws: SnapshotFileRefusal.writableByOthers) { try SnapshotFileGate().read(group, within: tmp.url) }
    }

    @Test("a folder others may write is refused")
    func writableFolder() throws {
        let tmp = try TemporaryFolder()
        let open = try tmp.folder("open", mode: 0o777)
        let file = try tmp.write("open/version", "1")
        #expect(throws: SnapshotFileRefusal.writableByOthers) { try SnapshotFileGate().read(file, within: open) }
    }

    @Test("a file of another owner is refused")
    func owner() throws {
        let tmp = try TemporaryFolder()
        let file = try tmp.write("version", "1")
        let other = SnapshotFileGate(ownerID: geteuid() &+ 1)
        #expect(throws: SnapshotFileRefusal.wrongOwner) { try other.read(file, within: tmp.url) }
    }

    @Test("a file over the ceiling is refused")
    func large() throws {
        let tmp = try TemporaryFolder()
        let file = try tmp.write("big", String(repeating: "x", count: 2_000))
        #expect(throws: SnapshotFileRefusal.tooLarge) { try SnapshotFileGate(maxBytes: 1_024).read(file, within: tmp.url) }
    }

    @Test("a pipe or a folder is not a regular file")
    func notRegular() throws {
        let tmp = try TemporaryFolder()
        let fifo = tmp.url.appendingPathComponent("fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: SnapshotFileRefusal.notRegularFile) { try SnapshotFileGate().read(fifo, within: tmp.url) }
        let folder = try tmp.folder("dir")
        #expect(throws: SnapshotFileRefusal.notRegularFile) { try SnapshotFileGate().read(folder, within: tmp.url) }
    }
}

@Suite("Security by design: the lab program")
struct LabExecutableLocatorTests {
    func program(_ tmp: TemporaryFolder, _ name: String = "lab", mode: mode_t = 0o755) throws -> URL {
        try tmp.write(name, "#!/bin/sh\nexit 0\n", mode: mode)
    }

    @Test("a regular executable of the user, in a closed folder, is accepted; links are resolved")
    func accepted() throws {
        let tmp = try TemporaryFolder()
        let lab = try program(tmp)
        #expect(try LabExecutableLocator(candidates: [lab]).locate() == lab)
        let link = tmp.url.appendingPathComponent("current")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: lab)
        #expect(try LabExecutableLocator(candidates: [link]).locate().path == lab.path)
    }

    @Test("relative, missing, writable by others, not executable, or in an open folder: refused")
    func refused() throws {
        let tmp = try TemporaryFolder()
        let locator = LabExecutableLocator(candidates: [])
        #expect(locator.check(URL(string: "lab")!) == .failure(.notAbsolute))
        #expect(locator.check(tmp.url.appendingPathComponent("none")) == .failure(.missing))
        #expect(locator.check(try program(tmp, "w", mode: 0o777)) == .failure(.writableByOthers))
        #expect(locator.check(try program(tmp, "x", mode: 0o644)) == .failure(.notExecutable))
        _ = try tmp.folder("open", mode: 0o777)
        #expect(locator.check(try program(tmp, "open/lab")) == .failure(.folderWritableByOthers))
        #expect(locator.check(try tmp.folder("dir")) == .failure(.notRegularFile))
        #expect(LabExecutableLocator(candidates: [try program(tmp, "y")], ownerID: geteuid() &+ 1).check(try program(tmp, "y")) == .failure(.wrongOwner))
    }

    @Test("no candidate: lab is unavailable, each reason named")
    func unavailable() throws {
        let tmp = try TemporaryFolder()
        let locator = LabExecutableLocator(candidates: [tmp.url.appendingPathComponent("none")])
        #expect(throws: LanesProblem.self) { try locator.locate() }
    }
}

@Suite("Security by design: arguments")
struct LabCommandTests {
    @Test("names that could become options or paths are refused")
    func names() {
        for bad in ["", "-rf", "--reader", "a b", "$(x)", "a;b", "../x", ".hidden", String(repeating: "a", count: 101), "é"] {
            #expect(LabName(bad) == nil, "\(bad) must be refused")
        }
        for good in ["essai-fork", "lot.1_a", "A9"] { #expect(LabName(good) != nil) }
    }

    @Test("every command is a list of arguments")
    func arguments() throws {
        let p = try #require(LabName("demo"))
        let l = try #require(LabName("api"))
        #expect(LabCommand.snapshot(readerPID: 42, project: nil, lane: nil).arguments == ["app", "snapshot", "--reader", "42"])
        #expect(LabCommand.snapshot(readerPID: 42, project: p, lane: l).arguments == ["app", "snapshot", "--reader", "42", "demo", "api"])
        #expect(LabCommand.question(project: p, lane: l).arguments == ["ginkgo", "question", "demo", "api"])
        #expect(LabCommand.answerChoices(project: p, lane: l, qid: try #require(LabQuestionID("q-1")), choices: [2: [1, 3], 1: [2]]).arguments
            == ["ginkgo", "answer", "demo", "api", "--qid", "q-1", "--q", "1", "--choice", "2", "--q", "2", "--choice", "1", "--choice", "3"])
        #expect(LabCommand.next(project: p, lane: l).arguments == ["next", "demo", "api"])
        #expect(LabCommand.focus(project: p, lane: l).arguments == ["app", "focus", "demo", "api"])
    }

    @Test("a typed text with $(…), ; and quotes reaches lab as one untouched argument")
    func textStaysOneArgument() async throws {
        let tmp = try TemporaryFolder()
        let record = tmp.url.appendingPathComponent("argv")
        let marker = tmp.url.appendingPathComponent("pwned")
        // The fake lab writes each argument it receives, NUL-terminated.
        let lab = try tmp.write("lab", "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\0' \"$a\"; done > '\(record.path)'\necho OK\n", mode: 0o755)
        let text = "go on $(touch \(marker.path)); `touch \(marker.path)` \"quoted\" 'single' && rm -rf ~"
        let output = try await ProcessLabCommandRunner(executable: lab).run(
            .answerText(project: try #require(LabName("demo")), lane: try #require(LabName("api")), text: text)
        )
        #expect(output.status == 0)
        #expect(output.standardOutput == "OK\n")
        let recorded = try Data(contentsOf: record).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        #expect(recorded == ["ginkgo", "answer", "demo", "api", "--text", text])
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("lab's refusal is read in one line")
    func refusal() {
        let output = LabCommandOutput(status: 1, standardOutput: "", standardError: "note\nlab: ERROR lab ginkgo answer is the voice of the user — nothing sent\n")
        #expect(output.refusal == "lab ginkgo answer is the voice of the user — nothing sent")
        #expect(LabCommandOutput(status: 3, standardOutput: "", standardError: "").refusal == "exit 3")
    }

    @Test("a command that never ends is stopped at its deadline")
    func timeout() async throws {
        let tmp = try TemporaryFolder()
        let lab = try tmp.write("lab", "#!/bin/sh\nexec sleep 30\n", mode: 0o755)
        let started = ContinuousClock.now
        await #expect(throws: LanesProblem.self) {
            _ = try await ProcessLabCommandRunner(executable: lab, timeout: .milliseconds(300)).run(.next(project: LabName("p")!, lane: LabName("l")!))
        }
        #expect(ContinuousClock.now - started < .seconds(10))
    }
}

@Suite("Unknown lab versions")
struct LabVersionGateTests {
    @Test("major 1 is read, anything else refused with its value")
    func versions() throws {
        #expect(try LabVersionGate().check("1.8.2\n") == "1.8.2")
        #expect(throws: LanesProblem.unknownLabVersion("2.0.0")) { try LabVersionGate().check("2.0.0") }
        #expect(throws: LanesProblem.unknownLabVersion("")) { try LabVersionGate().check(nil) }
        #expect(throws: LanesProblem.unknownLabVersion("abc")) { try LabVersionGate().check("abc") }
    }
}

@Suite("Demo mode runs no program")
struct DemoLabRunnerTests {
    @Test("questions come from the demo folder; every action is refused; nothing is executed")
    func demo() async throws {
        let tmp = try TemporaryFolder()
        try tmp.write("questions/demo/api", "WAITS=box\nQID=q-1\nQUESTION_1=Go?\nOPTION_1_1=Yes\n")
        let runner = DemoLabRunner(folder: tmp.url)
        let p = try #require(LabName("demo")), l = try #require(LabName("api"))
        #expect(try await runner.run(.question(project: p, lane: l)).standardOutput.hasPrefix("WAITS=box"))
        #expect(try await runner.run(.question(project: p, lane: try #require(LabName("web")))).standardOutput == "WAITS=none\n")
        #expect(try await runner.run(.snapshot(readerPID: 1, project: nil, lane: nil)).status == 0)
        for command in [LabCommand.next(project: p, lane: l), .focus(project: p, lane: l), .answerText(project: p, lane: l, text: "x")] {
            let output = try await runner.run(command)
            #expect(output.status == 1 && output.refusal == "demo: nothing is sent")
        }
    }
}
