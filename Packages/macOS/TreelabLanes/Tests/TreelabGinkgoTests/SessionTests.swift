import Foundation
import Testing
@testable import TreelabGinkgo
import TreelabLanes

@Suite("Following Ginkgo's state")
struct SessionTests {
    private let galerie = GinkgoPendingClose(project: "atelier-photo", lane: "galerie", until: Date(timeIntervalSince1970: 1_795_765_120))
    private let reglages = GinkgoAbout(project: name("treelab-app"), lane: name("reglages"), qid: "q1")

    private func snapshot(_ state: GinkgoVoiceState, mic: Bool, lines: [GinkgoLine] = [], did: [GinkgoDid] = []) -> GinkgoEvent {
        .snapshot(GinkgoSnapshot(state: state, mic: mic, focus: "treelab-app", listen: .command, confirm: nil, about: nil, lines: lines, did: did))
    }

    @Test("snapshot then events give state, mic, project, mode and version")
    func basics() {
        var session = GinkgoSession()
        session.apply(envelope(1, .hello(version: "2.0.0", protocolVersion: 1, capabilities: ["levels"], listen: .key)))
        #expect(session.version == "2.0.0")
        #expect(session.listen == .key)
        session.apply(envelope(2, snapshot(.closed, mic: false)))
        #expect(session.state == .closed)
        #expect(!session.mic)
        #expect(session.focus == "treelab-app")
        #expect(session.listen == .command)
        session.apply(envelope(3, .state(.listening, mic: true, focus: "carnet")))
        #expect(session.state == .listening)
        #expect(session.mic)
        #expect(session.focus == "carnet")
        session.apply(envelope(4, .mode(.name)))
        #expect(session.listen == .name)
    }

    @Test("a partial line is replaced by the next one with the same id, and keeps its start time")
    func partials() {
        var session = GinkgoSession()
        session.apply(envelope(1, .state(.listening, mic: true, focus: nil)))
        session.apply(envelope(2, .line(GinkgoLine(id: "u1", who: .user, text: "Gink", final: false)), at: 100))
        session.apply(envelope(3, .line(GinkgoLine(id: "u1", who: .user, text: "Ginkgo, qu’est-ce", final: false)), at: 101))
        session.apply(envelope(4, .line(GinkgoLine(id: "u1", who: .user, text: "Ginkgo, qu’est-ce qui m’attend ?", final: true)), at: 102))
        session.apply(envelope(5, .line(GinkgoLine(id: "g1", who: .ginkgo, text: "Cinq demandes", final: false)), at: 103))
        #expect(session.lines.map(\.text) == ["Ginkgo, qu’est-ce qui m’attend ?", "Cinq demandes"])
        #expect(session.lines.map(\.final) == [true, false])
        #expect(session.lines.first?.at == Date(timeIntervalSince1970: 100))
    }

    @Test("only the conversation in progress is kept: a new one starts empty")
    func newConversation() {
        var session = GinkgoSession()
        session.apply(envelope(1, .state(.listening, mic: true, focus: nil)))
        session.apply(envelope(2, .line(GinkgoLine(id: "u1", who: .user, text: "Bonjour", final: true))))
        session.apply(envelope(3, .did(GinkgoDid(kind: .order, project: "carnet", lane: "partage", text: "Relancé"))))
        session.apply(envelope(4, .about(reglages)))
        session.apply(envelope(5, .state(.thinking, mic: true, focus: nil)))
        session.apply(envelope(6, .state(.paused, mic: false, focus: nil)))
        #expect(session.lines.count == 1, "thinking and paused belong to the same conversation")
        session.apply(envelope(7, .state(.closed, mic: false, focus: nil)))
        #expect(session.lines.count == 1, "a closed conversation stays readable until the next one")
        session.apply(envelope(8, .state(.listening, mic: true, focus: nil)))
        #expect(session.lines.isEmpty)
        #expect(session.did.isEmpty)
        #expect(session.about == nil)
    }

    @Test("what Ginkgo did, the lane it talks about, and about {} clears it")
    func didAndAbout() {
        var session = GinkgoSession()
        session.apply(envelope(1, .did(GinkgoDid(kind: .answer, project: "treelab-app", lane: "reglages", text: "Réponse envoyée")), at: 200))
        #expect(session.did.map(\.text) == ["Réponse envoyée"])
        #expect(session.did.first?.at == Date(timeIntervalSince1970: 200))
        session.apply(envelope(2, .about(reglages)))
        #expect(session.about == reglages)
        session.apply(envelope(3, .about(nil)))
        #expect(session.about == nil)
    }

    @Test("a close waiting for its yes, then its end: cancelled, confirmed or expired")
    func pendingClose() {
        var session = GinkgoSession()
        session.apply(envelope(1, .confirm(galerie)))
        #expect(session.pendingClose == galerie)
        session.apply(envelope(2, .confirmEnd(project: "other", lane: "galerie", outcome: .expired)))
        #expect(session.pendingClose == galerie, "the end of another close leaves this one")
        session.apply(envelope(3, .confirmEnd(project: "atelier-photo", lane: "galerie", outcome: .cancelled)))
        #expect(session.pendingClose == nil)
        #expect(session.lastCloseOutcome == .cancelled)
        session.apply(envelope(4, .confirm(galerie)))
        #expect(session.lastCloseOutcome == nil)
        session.apply(envelope(5, .confirmEnd(project: "atelier-photo", lane: "galerie", outcome: .confirmed)))
        #expect(session.lastCloseOutcome == .confirmed)
    }

    @Test("refusals and errors are kept to be said plainly; a new conversation clears them")
    func problems() {
        var session = GinkgoSession()
        session.apply(envelope(1, .refused(reason: "mic_denied", text: "Micro refusé")))
        #expect(session.problem == GinkgoSession.Problem(isRefusal: true, code: "mic_denied", text: "Micro refusé"))
        session.apply(envelope(2, .error(kind: "network", text: "Réseau coupé")))
        #expect(session.problem == GinkgoSession.Problem(isRefusal: false, code: "network", text: "Réseau coupé"))
        session.apply(envelope(3, .state(.listening, mic: true, focus: nil)))
        #expect(session.problem == nil)
    }

    @Test("reconnecting in the middle of a conversation shows it whole from the snapshot")
    func reconnect() {
        var first = GinkgoSession()
        first.apply(envelope(40, .state(.speaking, mic: true, focus: nil)))
        // A new connection: seq starts again, the snapshot brings the open conversation.
        var second = GinkgoSession()
        let lines = [GinkgoLine(id: "u1", who: .user, text: "Relance partage", final: true),
                     GinkgoLine(id: "g1", who: .ginkgo, text: "Je relance", final: false)]
        second.apply(envelope(1, .hello(version: "2.0.0", protocolVersion: 1, capabilities: [], listen: nil)))
        second.apply(envelope(2, .snapshot(GinkgoSnapshot(state: .speaking, mic: true, focus: "carnet", listen: .command,
                                                         confirm: galerie, about: reglages, lines: lines,
                                                         did: [GinkgoDid(kind: .order, project: "carnet", lane: "partage", text: "Relancé")])), at: 300))
        #expect(second.state == .speaking)
        #expect(second.lines.map(\.id) == ["u1", "g1"])
        #expect(second.pendingClose == galerie)
        #expect(second.about == reglages)
        #expect(second.did.count == 1)
        second.apply(envelope(3, .state(.listening, mic: true, focus: nil)))
        #expect(second.lines.count == 2, "still the same conversation")
        second.apply(envelope(4, .line(GinkgoLine(id: "g1", who: .ginkgo, text: "Je relance partage.", final: true))))
        #expect(second.lines.map(\.text) == ["Relance partage", "Je relance partage."])
    }

    @Test("bye: Ginkgo is gone, microphone closed, nothing waits")
    func bye() {
        var session = GinkgoSession()
        session.apply(envelope(1, .state(.listening, mic: true, focus: nil)))
        session.apply(envelope(2, .confirm(galerie)))
        session.apply(envelope(3, .bye))
        #expect(session.isGone)
        #expect(session.state == .closed)
        #expect(!session.mic)
        #expect(session.pendingClose == nil)
    }

    @Test("levels never enter the session")
    func levels() {
        var session = GinkgoSession()
        let applied = session.apply(envelope(1, .level(input: 0.5, output: 0.1)))
        #expect(!applied)
    }

    @Test("lines and actions are bounded")
    func bounded() {
        var session = GinkgoSession()
        for index in 1...(GinkgoSession.maxLines + 5) {
            session.apply(envelope(index, .line(GinkgoLine(id: "l\(index)", who: .user, text: "x", final: true))))
        }
        #expect(session.lines.count == GinkgoSession.maxLines)
        #expect(session.lines.first?.id == "l6")
    }
}
