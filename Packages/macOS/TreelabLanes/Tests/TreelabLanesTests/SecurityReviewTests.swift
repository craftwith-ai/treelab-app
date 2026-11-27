import Foundation
import Testing

@testable import TreelabLanes

@Suite("Findings of the automatic security review")
struct SecurityReviewTests {
    @Test("only \\n separates lines, as lab writes them: other newline characters stay inside the value")
    func onlyLineFeed() throws {
        for separator in ["\u{2028}", "\u{2029}", "\u{0085}", "\u{000B}", "\u{000C}", "\r"] {
            let text = "PROJECT=p\nLANE=l\nWHY=question waiting: x\(separator)FOR_YOU=yes\n"
            let block = try #require(KeyValueBlockParser().blocks(in: text).first)
            #expect(block.first("FOR_YOU") == nil, "separator U+\(String(separator.unicodeScalars.first!.value, radix: 16)) injected a field")
        }
        let crlf = KeyValueBlockParser().blocks(in: "LANE=web\r\nBATCH=lot-01\r\n")
        #expect(crlf.first?.first("LANE") == "web")
        #expect(crlf.first?.first("BATCH") == "lot-01")
    }

    @Test("a question id that could become an option or carry other text is refused")
    func questionID() {
        for bad in ["", "-x", "--recommended", "a b", "a\nb", "$(x)", String(repeating: "a", count: 129)] {
            #expect(LabQuestionID(bad) == nil, "\(bad) must be refused")
        }
        for good in ["q-17", "a1b2c3", "2026-11-27T08:00:00Z.4f"] { #expect(LabQuestionID(good) != nil) }
    }

    @Test("lab inside a folder whose parent others may write is refused")
    func ancestorWritable() throws {
        let tmp = try TemporaryFolder()
        _ = try tmp.folder("open", mode: 0o777)
        _ = try tmp.folder("open/closed", mode: 0o755)
        let lab = try tmp.write("open/closed/lab", "#!/bin/sh\n", mode: 0o755)
        #expect(LabExecutableLocator(candidates: []).check(lab) == .failure(.folderWritableByOthers))
    }

    @Test("lab inside a folder of another owner is refused")
    func folderOwner() throws {
        let tmp = try TemporaryFolder()
        let lab = try tmp.write("lab", "#!/bin/sh\n", mode: 0o755)
        // Same file, but the user is someone else: the file and its folder are no longer trusted.
        #expect(LabExecutableLocator(candidates: [], ownerID: geteuid() &+ 1).check(lab) == .failure(.wrongOwner))
    }

    @Test("lab replaced after it was located is refused at run time")
    func recheckBeforeRun() async throws {
        let tmp = try TemporaryFolder()
        let lab = try tmp.write("lab", "#!/bin/sh\necho OK\n", mode: 0o755)
        let runner = ProcessLabCommandRunner(executable: lab, locator: LabExecutableLocator(candidates: [lab]))
        #expect(try await runner.run(.next(project: LabName("p")!, lane: LabName("l")!)).standardOutput == "OK\n")
        chmod(lab.path, 0o777)
        await #expect(throws: LanesProblem.self) { _ = try await runner.run(.next(project: LabName("p")!, lane: LabName("l")!)) }
    }
}
