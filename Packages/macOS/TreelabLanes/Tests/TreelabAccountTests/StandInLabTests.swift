import Foundation
import Testing
import TreelabLanes

/// A stand-in lab program, run for real by ``ProcessLabCommandRunner``: it writes each argument it
/// received on its own line, and what came on its standard input, to files of its folder.
private struct StandInLab {
    let folder: ScratchFolder
    var program: URL { folder.url.appendingPathComponent("lab") }
    var receivedArguments: String { (try? String(contentsOf: folder.url.appendingPathComponent("args"), encoding: .utf8)) ?? "<none>" }
    var receivedInput: Data { (try? Data(contentsOf: folder.url.appendingPathComponent("stdin"))) ?? Data() }

    init() throws {
        folder = try ScratchFolder()
        let script = """
        #!/bin/sh
        for a in "$@"; do printf '%s\\n' "$a"; done > "\(folder.path)/args"
        cat > "\(folder.path)/stdin"
        printf 'KEY=stored\\n'

        """
        try script.write(to: program, atomically: true, encoding: .utf8)
        chmod(program.path, 0o700)
    }

    var runner: ProcessLabCommandRunner { ProcessLabCommandRunner(executable: program, timeout: .seconds(20)) }
}

@Suite("A real lab program receives exactly")
struct StandInLabTests {
    @Test("a dangerous e-mail arrives as one argument and is never run by a shell")
    func dangerousEmail() async throws {
        let lab = try StandInLab()
        let pwned = lab.folder.url.appendingPathComponent("PWNED").path
        let email = #"camille"; $(touch \#(pwned)); echo 'x@exemple.fr"#
        let address = try #require(LabEmailAddress(email))
        let output = try await lab.runner.run(.signIn(email: address))
        #expect(output.status == 0)
        #expect(lab.receivedArguments == "app\nsignin\n--email\n\(email)\n")
        #expect(!FileManager.default.fileExists(atPath: pwned))
        #expect(lab.receivedInput.isEmpty)
    }

    @Test("the OpenAI key arrives on standard input, never in the arguments")
    func keyOnStandardInput() async throws {
        let lab = try StandInLab()
        let key = try #require(LabSecret("sk-proj-SECRET-4f2a"))
        let output = try await lab.runner.run(.storeOpenAIKey(key))
        #expect(output.status == 0)
        #expect(output.standardOutput == "KEY=stored\n")
        #expect(lab.receivedArguments == "ginkgo\nkey\nopenai\n")
        #expect(lab.receivedInput == Data("sk-proj-SECRET-4f2a\n".utf8))
    }

    @Test("every other command gets an empty standard input")
    func noInput() async throws {
        let lab = try StandInLab()
        _ = try await lab.runner.run(.account)
        #expect(lab.receivedArguments == "app\naccount\n")
        #expect(lab.receivedInput.isEmpty)
        let token = try #require(LabEraseToken("erase-7f3a"))
        _ = try await lab.runner.run(.confirmErase(token: token))
        #expect(lab.receivedArguments == "app\ndata\n--erase\n--confirm\nerase-7f3a\n")
        #expect(lab.receivedInput.isEmpty)
    }

    @Test("a lab that never reads its input does not hang nor kill Treelab")
    func unreadInput() async throws {
        let folder = try ScratchFolder()
        let program = folder.url.appendingPathComponent("lab")
        try "#!/bin/sh\nexit 0\n".write(to: program, atomically: true, encoding: .utf8)
        chmod(program.path, 0o700)
        let key = try #require(LabSecret("sk-test"))
        let output = try await ProcessLabCommandRunner(executable: program, timeout: .seconds(20)).run(.storeOpenAIKey(key))
        #expect(output.status == 0)
    }
}

@Suite("Account brain: no network, no shell, no timer")
struct AccountSourceGuardTests {
    private static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func sources(_ target: String) throws -> String {
        let folder = Self.package.appendingPathComponent("Sources/\(target)")
        let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        return try files.map { try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("TreelabAccount: 0 network, 0 shell, 0 process of its own, 0 timer")
    func account() throws {
        let text = try sources("TreelabAccount")
        for word in ["URLSession", "NWConnection", "AF_INET", "socket(", "/bin/sh", "Process(", "posix_spawn", "Timer", "asyncAfter", "Task.sleep", "DispatchSource.makeTimer"] {
            #expect(!text.contains(word), "\(word)")
        }
        #expect(text.contains("PROTOCOL"), "the account brain checks the contract's protocol")
    }

    @Test("no price is written in the app: 39, 390 or € only come from OFFER_*")
    func noPriceLiteral() throws {
        for target in ["TreelabAccount", "TreelabLanesUI"] {
            let text = try sources(target)
            for literal in ["\"39\"", "\"390\"", " 39 ", " 390 ", "39 €", "390 €", "€", "3900", "39000", "Decimal(39", "Decimal(390"] {
                #expect(!text.contains(literal), "\(target): \(literal)")
            }
        }
    }
}
