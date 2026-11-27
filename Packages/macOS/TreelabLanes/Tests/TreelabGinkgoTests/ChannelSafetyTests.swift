import Foundation
import Testing
@testable import TreelabGinkgo
import TreelabLanes

@Suite("Channel safety (§2)", .serialized)
struct ChannelSafetyTests {
    @Test("a path longer than 103 bytes is refused with its name, never truncated")
    func longPath() throws {
        let path = "/tmp/" + String(repeating: "g", count: 92) + "/app.sock"
        #expect(path.utf8.count == 106)
        #expect(throws: GinkgoSocketRefusal.pathTooLong(path)) { try GinkgoSocketLocation(path: path).check() }
        let exact = "/tmp/" + String(repeating: "g", count: 89) + "/app.sock"
        #expect(exact.utf8.count == 103)
        #expect(throws: GinkgoSocketRefusal.absent(exact)) { try GinkgoSocketLocation(path: exact).check() }
    }

    @Test("a socket that answers, in a 0700 folder, is accepted")
    func good() throws {
        let fake = try FakeGinkgo()
        try fake.location.check()
        let connection = try GinkgoConnection.open(fake.location)
        connection.close()
    }

    @Test("a link in place of the socket is refused")
    func link() throws {
        let fake = try FakeGinkgo()
        let linked = fake.folder + "/link.sock"
        symlink(fake.path, linked)
        defer { unlink(linked) }
        #expect(throws: GinkgoSocketRefusal.notASocket(linked)) { try GinkgoSocketLocation(path: linked).check() }
    }

    @Test("a linked folder is refused")
    func linkedFolder() throws {
        let fake = try FakeGinkgo()
        let folderLink = fake.folder + ".lnk"
        symlink(fake.folder, folderLink)
        defer { unlink(folderLink) }
        #expect(throws: GinkgoSocketRefusal.notASocket(folderLink)) { try GinkgoSocketLocation(path: folderLink + "/app.sock").check() }
    }

    @Test("a socket or folder owned by someone else is refused")
    func otherOwner() throws {
        let fake = try FakeGinkgo()
        let other = GinkgoSocketLocation(path: fake.path, ownerID: geteuid() + 1)
        #expect(throws: GinkgoSocketRefusal.foreignOwner(fake.folder)) { try other.check() }
    }

    @Test("a folder or a socket open to others is refused")
    func openToOthers() throws {
        let fake = try FakeGinkgo()
        chmod(fake.folder, 0o755)
        #expect(throws: GinkgoSocketRefusal.openToOthers(fake.folder)) { try fake.location.check() }
        chmod(fake.folder, 0o700)
        chmod(fake.path, 0o666)
        #expect(throws: GinkgoSocketRefusal.openToOthers(fake.path)) { try fake.location.check() }
        chmod(fake.path, 0o600)
        try fake.location.check()
    }

    @Test("a plain file in place of the socket is refused")
    func plainFile() throws {
        let fake = try FakeGinkgo()
        let file = fake.folder + "/file.sock"
        FileManager.default.createFile(atPath: file, contents: Data(), attributes: [.posixPermissions: 0o600])
        defer { unlink(file) }
        #expect(throws: GinkgoSocketRefusal.notASocket(file)) { try GinkgoSocketLocation(path: file).check() }
    }

    @Test("a peer of another user is refused and the connection closed")
    func foreignPeer() async throws {
        let fake = try FakeGinkgo()
        #expect(throws: GinkgoSocketRefusal.foreignPeer(0)) { try fake.location.checkPeer(uid: 0) }
        let stranger = geteuid() + 1
        #expect(throws: GinkgoSocketRefusal.foreignPeer(stranger)) {
            _ = try GinkgoConnection.open(fake.location, peer: { _ in stranger })
        }
        #expect(await eventually { !fake.hasClient })
        #expect(fake.received.isEmpty)
    }

    @Test("the kernel says the peer is this user")
    func kernelPeer() throws {
        let fake = try FakeGinkgo()
        let connection = try GinkgoConnection.open(fake.location)
        connection.close()
    }

    @Test("the standard socket is under lab's state folder, LAB_STATE_DIR respected when absolute")
    func standard() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(GinkgoSocketLocation.standard(home: home, environment: [:]).path == "/Users/someone/.lab/state/ginkgo/app.sock")
        #expect(GinkgoSocketLocation.standard(home: home, environment: ["LAB_STATE_DIR": "/srv/lab"]).path == "/srv/lab/ginkgo/app.sock")
        #expect(GinkgoSocketLocation.standard(home: home, environment: ["LAB_STATE_DIR": "rel"]).path == "/Users/someone/.lab/state/ginkgo/app.sock")
    }
}

@Suite("Launch through lab (§1)")
struct LabLaunchTests {
    @Test("lab is called with a list of arguments: ginkgo <project>, --background when asked")
    func arguments() {
        #expect(LabCommand.ginkgoLaunch(project: name("treelab-app"), background: false).arguments == ["ginkgo", "treelab-app"])
        #expect(LabCommand.ginkgoLaunch(project: name("treelab-app"), background: true).arguments == ["ginkgo", "treelab-app", "--background"])
        #expect(LabCommand.ginkgoStatus.arguments == ["ginkgo", "status"])
    }

    @Test("project names are checked: an unsafe one never reaches lab")
    func names() {
        for unsafe in ["", "-x", "--background", "a b", "a;rm -rf", "../up", "p/q", "$(id)", "é"] {
            #expect(LabName(unsafe) == nil, "\(unsafe)")
        }
    }

    @Test("lab runs at its exact path, each argument apart, no shell")
    func exactPath() async throws {
        var template = Array("/tmp/tllab.XXXXXX".utf8CString)
        let folder = String(cString: mkdtemp(&template)!)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let lab = folder + "/lab"
        // The stand-in lab writes each argument it received on its own line.
        try "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"\(folder)/args\"\n".write(toFile: lab, atomically: true, encoding: .utf8)
        chmod(lab, 0o755)
        let runner = ProcessLabCommandRunner(executable: URL(fileURLWithPath: lab))
        let output = try await runner.run(.ginkgoLaunch(project: name("carnet-recettes"), background: true))
        #expect(output.status == 0)
        #expect(try String(contentsOfFile: folder + "/args", encoding: .utf8) == "ginkgo\ncarnet-recettes\n--background\n")
    }
}

@Suite("Nothing but a local socket")
struct SourceGuardTests {
    private static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func sources(_ target: String) throws -> String {
        let folder = Self.package.appendingPathComponent("Sources/\(target)")
        let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        return try files.map { try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("TreelabGinkgo: no network, no shell, no sound, no timer")
    func ginkgo() throws {
        let text = try sources("TreelabGinkgo")
        for word in ["AF_INET", "URLSession", "NWConnection", "/bin/sh", "AVAudio", "AVCapture", "CoreAudio", "Timer", "asyncAfter", "Task.sleep"] {
            #expect(!text.contains(word), "\(word)")
        }
    }

    @Test("the lanes brain keeps 0 socket")
    func brain() throws {
        #expect(try !sources("TreelabLanes").contains("socket("))
    }
}
