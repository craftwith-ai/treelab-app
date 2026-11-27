import Foundation
import Testing
@testable import TreelabGinkgo
import TreelabLanes

/// The model against a stand-in Ginkgo on a real socket.
@MainActor
@Suite("Launch and orders against a fake Ginkgo", .serialized)
struct ModelTests {
    private let defaults: UserDefaults
    private let signals = ScriptedSignals()

    init() {
        let suite = "sh.treelab.tests.ginkgo.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ fake: FakeGinkgo, lab: RecordingLab?, focus: String? = "treelab-app", reduceMotion: Bool = false) -> GinkgoModel {
        GinkgoModel(runner: lab, location: fake.location, signals: signals, defaults: defaults, clientVersion: "1.0",
                    focus: { focus.flatMap(LabName.init) }, reduceMotion: { reduceMotion })
    }

    /// A socket path where nothing listens yet, in the fake's folder.
    private func absentModel(_ fake: FakeGinkgo, lab: RecordingLab) -> (GinkgoModel, String) {
        let path = fake.folder + "/later.sock"
        let model = GinkgoModel(runner: lab, location: GinkgoSocketLocation(path: path), signals: signals, defaults: defaults,
                                clientVersion: "1.0", focus: { LabName("treelab-app") }, reduceMotion: { false })
        return (model, path)
    }

    @Test("Ginkgo present at start: connected, hello first")
    func presentAtStart() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        #expect(ginkgo.presence == .connected)
        #expect(await eventually { fake.ops == ["hello"] })
        #expect(fake.orders.first?["client"] as? String == "treelab")
        #expect(fake.orders.first?["protocol"] as? Int == 1)
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isMicrophoneOpen })
    }

    @Test("click with Ginkgo present: the screen opens and `open {focus}` is sent, never lab")
    func clickPresent() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        let ginkgo = model(fake, lab: lab)
        ginkgo.start()
        fake.greet()
        #expect(await eventually { ginkgo.session.version == "2.0.0" })
        ginkgo.openFromBar()
        #expect(ginkgo.isScreenPresented)
        #expect(await eventually { fake.ops == ["hello", "open"] })
        #expect(fake.orders.last?["focus"] as? String == "treelab-app")
        #expect(await lab.commands.isEmpty)
    }

    @Test("click with a conversation already open: nothing more is sent")
    func clickDuringConversation() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        ginkgo.openFromBar()
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.ops == ["hello"])
    }

    @Test("click with Ginkgo absent: lab ginkgo status, lab ginkgo <project>, then connection at the ready signal")
    func clickAbsent() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        let (ginkgo, path) = absentModel(fake, lab: lab)
        ginkgo.start()
        #expect(ginkgo.presence == .absent)
        ginkgo.openFromBar()
        #expect(await eventually { await lab.commands.count == 2 })
        #expect(await lab.commands == [.ginkgoStatus, .ginkgoLaunch(project: name("treelab-app"), background: false)])
        #expect(ginkgo.presence == .starting)
        // Ginkgo starts listening, then says it is ready.
        rename(fake.path, path)
        signals.fireReady()
        #expect(await eventually { ginkgo.presence == .connected })
        #expect(await eventually { fake.ops == ["hello"] }, "lab opened the conversation itself: no open is sent")
    }

    @Test("Ginkgo that ends while starting: absent again, nothing else")
    func endsWhileStarting() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        let (ginkgo, _) = absentModel(fake, lab: lab)
        ginkgo.start()
        ginkgo.talk()
        #expect(await eventually {
            let count = await lab.commands.count
            return ginkgo.presence == .starting && count == 2
        })
        signals.fireEnd()
        #expect(await eventually { ginkgo.presence == .absent })
    }

    @Test("a Ginkgo without the contract (1.8.3): update needed, nothing launched")
    func oldGinkgo() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab { _ in LabCommandOutput(status: 0, standardOutput: "PROVIDER=openai\nKEY=present\nAPP=/x/treelab-1.8.3/Ginkgo.app\nSOURCE=release\n", standardError: "") }
        let (ginkgo, _) = absentModel(fake, lab: lab)
        ginkgo.start()
        ginkgo.openFromBar()
        #expect(await eventually { ginkgo.presence == .updateNeeded })
        #expect(await lab.commands == [.ginkgoStatus])
    }

    @Test("lab that refuses --background by its usage (rc 2): update needed, nothing else")
    func labRefuses() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab { command in
            if case .ginkgoStatus = command {
                return LabCommandOutput(status: 0, standardOutput: "KEY=present\nPROTOCOL=1\n", standardError: "")
            }
            return LabCommandOutput(status: 2, standardOutput: "", standardError: "usage: lab ginkgo [project]\n")
        }
        defaults.set(true, forKey: GinkgoModel.keepActiveKey)
        let (ginkgo, _) = absentModel(fake, lab: lab)
        ginkgo.start()
        #expect(await eventually { ginkgo.presence == .updateNeeded })
        #expect(await lab.commands == [.ginkgoStatus, .ginkgoLaunch(project: name("treelab-app"), background: true)])
    }

    @Test("no OpenAI key stored: said plainly, nothing launched")
    func keyMissing() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab { _ in LabCommandOutput(status: 0, standardOutput: "KEY=absent\nPROTOCOL=1\n", standardError: "") }
        let (ginkgo, _) = absentModel(fake, lab: lab)
        ginkgo.start()
        ginkgo.talk()
        #expect(await eventually { ginkgo.presence == .keyMissing })
        #expect(await lab.commands == [.ginkgoStatus])
    }

    @Test("no lab project known: said plainly, nothing sent")
    func noProject() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil, focus: nil)
        ginkgo.start()
        ginkgo.talk()
        #expect(ginkgo.notice == .noProject)
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.ops == ["hello"])
    }

    @Test("keep active on at start, Ginkgo absent: lab ginkgo <project> --background")
    func keepActiveAtStart() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        defaults.set(true, forKey: GinkgoModel.keepActiveKey)
        let (ginkgo, _) = absentModel(fake, lab: lab)
        #expect(ginkgo.keepActive)
        ginkgo.start()
        #expect(await eventually { await lab.commands.count == 2 })
        #expect(await lab.commands.last == .ginkgoLaunch(project: name("treelab-app"), background: true))
    }

    @Test("keep active off at start: nothing launched")
    func keepActiveOffAtStart() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        let (ginkgo, _) = absentModel(fake, lab: lab)
        ginkgo.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await lab.commands.isEmpty)
    }

    @Test("keep active on while no project is known yet: the background start waits for one")
    func keepActiveWaitsForProject() async throws {
        let fake = try FakeGinkgo()
        let lab = RecordingLab.current()
        defaults.set(true, forKey: GinkgoModel.keepActiveKey)
        var project: String?
        let ginkgo = GinkgoModel(runner: lab, location: GinkgoSocketLocation(path: fake.folder + "/later.sock"), signals: signals,
                                 defaults: defaults, clientVersion: "1.0", focus: { project.flatMap(LabName.init) }, reduceMotion: { false })
        ginkgo.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await lab.commands.isEmpty)
        project = "carnet"
        ginkgo.projectsChanged()
        #expect(await eventually { await lab.commands.last == .ginkgoLaunch(project: name("carnet"), background: true) })
    }

    @Test("Escape: close when kept active, quit otherwise")
    func escape() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        ginkgo.setKeepActive(true)
        ginkgo.closeMicrophone()
        #expect(await eventually { fake.ops.last == "close" })
        ginkgo.setKeepActive(false)
        ginkgo.closeMicrophone()
        #expect(await eventually { fake.ops.last == "quit" })
        #expect(defaults.bool(forKey: GinkgoModel.keepActiveKey) == false)
    }

    @Test("a conversation ended by voice stops Ginkgo when not kept active, once")
    func endByVoice() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        fake.event("state", "\"state\":\"closed\",\"mic\":false")
        #expect(await eventually { fake.ops == ["hello", "quit"] })
        fake.event("state", "\"state\":\"closed\",\"mic\":false")
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.ops == ["hello", "quit"])
    }

    @Test("a conversation ended by voice leaves Ginkgo running when kept active")
    func endByVoiceKept() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.setKeepActive(true)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        fake.event("state", "\"state\":\"name_listening\",\"mic\":true")
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.ops == ["hello"])
    }

    @Test("Cancel on a close waiting for its yes: cancel_close; its end clears the card")
    func cancel() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        fake.event("confirm", "\"project\":\"atelier-photo\",\"lane\":\"galerie\",\"until\":1795765120000")
        #expect(await eventually { ginkgo.session.pendingClose != nil })
        ginkgo.cancelClose()
        #expect(await eventually { fake.ops.last == "cancel_close" })
        fake.event("ack", "\"id\":2,\"ok\":true")
        fake.event("confirm_end", "\"project\":\"atelier-photo\",\"lane\":\"galerie\",\"outcome\":\"cancelled\"")
        #expect(await eventually { ginkgo.session.pendingClose == nil && ginkgo.session.lastCloseOutcome == .cancelled })
    }

    @Test("a refused order is said in Ginkgo's words")
    func refusedOrder() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet()
        fake.event("ack", "\"id\":1,\"ok\":false,\"text\":\"Rien à annuler\"")
        #expect(await eventually { ginkgo.notice == .orderRefused("Rien à annuler") })
    }

    @Test("levels are asked for only while the screen is visible and a conversation is open")
    func levels() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet()
        #expect(await eventually { ginkgo.session.version != nil })
        ginkgo.setScreenVisible(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(fake.ops == ["hello"], "no conversation: no levels")
        fake.event("state", "\"state\":\"listening\",\"mic\":true")
        #expect(await eventually { fake.ops == ["hello", "subscribe"] })
        #expect(fake.orders.last?["topics"] as? [String] == ["levels"])
        fake.event("level", "\"in\":0.6,\"out\":0.1")
        #expect(await eventually { ginkgo.levels.received == 1 && ginkgo.levels.input == 0.6 })
        ginkgo.dismissScreen()
        #expect(await eventually { fake.ops == ["hello", "subscribe", "unsubscribe"] })
        #expect(ginkgo.levels.input == 0)
        fake.event("level", "\"in\":0.9,\"out\":0.1")
        try await Task.sleep(for: .milliseconds(80))
        #expect(ginkgo.levels.received == 1, "a level after unsubscribing is dropped")
        ginkgo.setScreenVisible(true)
        #expect(await eventually { fake.ops.last == "subscribe" })
        fake.event("state", "\"state\":\"closed\",\"mic\":false")
        #expect(await eventually { fake.ops.suffix(2) == ["unsubscribe", "quit"] || fake.ops.suffix(2) == ["quit", "unsubscribe"] })
    }

    @Test("reduced motion: the heart stays still, no level is asked for")
    func reducedMotion() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil, reduceMotion: true)
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        ginkgo.setScreenVisible(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.ops == ["hello"])
    }

    @Test("Ginkgo talks about a lane: the Feed is told, once per lane")
    func about() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        var told: [GinkgoAbout] = []
        ginkgo.onAbout = { told.append($0) }
        ginkgo.start()
        fake.greet(state: "listening", mic: true)
        fake.event("about", "\"project\":\"atelier-photo\",\"lane\":\"paiement\",\"qid\":\"q1\"")
        fake.event("line", "\"who\":\"ginkgo\",\"id\":\"g1\",\"text\":\"Le plan du paiement\",\"final\":true")
        fake.event("about", "\"project\":\"atelier-photo\",\"lane\":\"paiement\",\"qid\":\"q1\"")
        fake.event("about", "\"project\":\"carnet\",\"lane\":\"partage\"")
        #expect(await eventually { told.count == 2 })
        #expect(told.map(\.lane.value) == ["paiement", "partage"])
    }

    @Test("bye: Ginkgo absent, then a new connection at its next ready signal")
    func byeThenReconnect() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "speaking", mic: true)
        #expect(await eventually { ginkgo.isConversationOpen })
        fake.event("bye")
        #expect(await eventually { ginkgo.presence == .absent })
        #expect(!ginkgo.isMicrophoneOpen)
        signals.fireReady()
        #expect(await eventually { ginkgo.presence == .connected && fake.connectionCount == 2 })
    }

    @Test("the socket closes in the middle of a conversation: absent; reconnecting shows it whole")
    func reconnectMidConversation() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.greet(state: "speaking", mic: true)
        fake.event("line", "\"who\":\"user\",\"id\":\"u1\",\"text\":\"Relance partage\",\"final\":true")
        #expect(await eventually { ginkgo.session.lines.count == 1 })
        fake.dropClient()
        #expect(await eventually { ginkgo.presence == .absent })
        #expect(ginkgo.session.lines.isEmpty)
        signals.fireReady()
        #expect(await eventually { fake.connectionCount == 2 && fake.hasClient })
        fake.greet(state: "speaking", mic: true, lines: "[{\"who\":\"user\",\"id\":\"u1\",\"text\":\"Relance partage\",\"final\":true},{\"who\":\"ginkgo\",\"id\":\"g1\",\"text\":\"Je rel\",\"final\":false}]")
        #expect(await eventually { ginkgo.session.lines.map(\.id) == ["u1", "g1"] })
        #expect(ginkgo.isConversationOpen)
    }

    @Test("another version on the socket: unknown version said, disconnected")
    func otherVersion() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.raw(Data("{\"v\":2,\"ev\":\"hello\",\"seq\":1,\"at\":1,\"ginkgo\":\"3.0\",\"protocol\":2}\n".utf8))
        #expect(await eventually { ginkgo.presence == .unknownVersion })
        #expect(await eventually { !fake.hasClient })
    }

    @Test("a line too long is dropped and reading goes on")
    func tooLong() async throws {
        let fake = try FakeGinkgo()
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        fake.raw(Data(repeating: 0x7B, count: ginkgoMaxLineBytes + 10) + Data([0x0A]))
        fake.greet(state: "listening", mic: true)
        #expect(await eventually { ginkgo.isMicrophoneOpen })
    }

    @Test("a socket open to others is refused: Treelab does not connect")
    func refusedSocket() async throws {
        let fake = try FakeGinkgo()
        chmod(fake.path, 0o666)
        let ginkgo = model(fake, lab: nil)
        ginkgo.start()
        #expect(ginkgo.presence == .refused(.openToOthers(fake.path)))
        #expect(fake.connectionCount == 0)
    }
}
