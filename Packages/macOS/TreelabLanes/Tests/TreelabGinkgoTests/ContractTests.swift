import Foundation
import Testing
@testable import TreelabGinkgo
import TreelabLanes

@Suite("Contract v1: Ginkgo's events (§5)")
struct EventDecodingTests {
    private let head = "\"v\":1,\"seq\":7,\"at\":1795765000123"

    @Test("every event of §5 is read")
    func everyEvent() throws {
        let cases: [(String, GinkgoEvent)] = [
            ("\"ev\":\"hello\",\"ginkgo\":\"2.0.0\",\"protocol\":1,\"capabilities\":[\"levels\",3],\"listen\":\"key\"",
             .hello(version: "2.0.0", protocolVersion: 1, capabilities: ["levels"], listen: .key)),
            ("\"ev\":\"state\",\"state\":\"name_listening\",\"mic\":true,\"focus\":\"carnet\"", .state(.nameListening, mic: true, focus: "carnet")),
            ("\"ev\":\"wake\"", .wake),
            ("\"ev\":\"key\",\"down\":true", .key(down: true)),
            ("\"ev\":\"interrupt\"", .interrupt),
            ("\"ev\":\"line\",\"who\":\"user\",\"id\":\"u1\",\"text\":\"Relance partage\",\"final\":false",
             .line(GinkgoLine(id: "u1", who: .user, text: "Relance partage", final: false))),
            ("\"ev\":\"did\",\"kind\":\"answer\",\"project\":\"treelab-app\",\"lane\":\"reglages\",\"text\":\"Réponse envoyée\"",
             .did(GinkgoDid(kind: .answer, project: "treelab-app", lane: "reglages", text: "Réponse envoyée"))),
            ("\"ev\":\"about\",\"project\":\"atelier-photo\",\"lane\":\"paiement\",\"qid\":\"q9\"",
             .about(GinkgoAbout(project: name("atelier-photo"), lane: name("paiement"), qid: "q9"))),
            ("\"ev\":\"about\"", .about(nil)),
            ("\"ev\":\"confirm\",\"project\":\"atelier-photo\",\"lane\":\"galerie\",\"until\":1795765120000",
             .confirm(GinkgoPendingClose(project: "atelier-photo", lane: "galerie", until: Date(timeIntervalSince1970: 1_795_765_120)))),
            ("\"ev\":\"confirm_end\",\"project\":\"atelier-photo\",\"lane\":\"galerie\",\"outcome\":\"cancelled\"",
             .confirmEnd(project: "atelier-photo", lane: "galerie", outcome: .cancelled)),
            ("\"ev\":\"news\",\"project\":\"carnet\",\"lane\":\"partage\",\"kind\":\"question\",\"text\":\"partage t’attend\"",
             .news(project: "carnet", lane: "partage", kind: "question", text: "partage t’attend")),
            ("\"ev\":\"mode\",\"listen\":\"name\"", .mode(.name)),
            ("\"ev\":\"refused\",\"reason\":\"mic_denied\",\"text\":\"Micro refusé\"", .refused(reason: "mic_denied", text: "Micro refusé")),
            ("\"ev\":\"error\",\"kind\":\"quota\",\"text\":\"Quota atteint\"", .error(kind: "quota", text: "Quota atteint")),
            ("\"ev\":\"level\",\"in\":0.25,\"out\":1.5", .level(input: 0.25, output: 1)),
            ("\"ev\":\"ack\",\"id\":4,\"ok\":false,\"text\":\"non\"", .ack(id: 4, ok: false, text: "non")),
            ("\"ev\":\"bye\"", .bye),
        ]
        for (body, expected) in cases {
            let read = try decode("{\(head),\(body)}")
            #expect(read == GinkgoEnvelope(seq: 7, at: Date(timeIntervalSince1970: 1_795_765_000.123), event: expected), "\(body)")
        }
    }

    @Test("snapshot carries state, mic, focus, mode, close, about, lines and actions")
    func snapshot() throws {
        let read = try decode("""
        {\(head),"ev":"snapshot","state":"speaking","mic":true,"focus":"treelab-app","listen":"command",\
        "confirm":{"project":"atelier-photo","lane":"galerie","until":1795765120000},\
        "about":{"project":"treelab-app","lane":"reglages"},\
        "lines":[{"who":"user","id":"u1","text":"Bonjour","final":true},{"who":"ginkgo","id":"g1","text":"Sal"}],\
        "did":[{"kind":"order","project":"carnet","text":"Relancé"}]}
        """)
        guard case let .snapshot(snapshot) = read?.event else {
            Issue.record("not a snapshot: \(String(describing: read))")
            return
        }
        #expect(snapshot.state == .speaking)
        #expect(snapshot.mic)
        #expect(snapshot.focus == "treelab-app")
        #expect(snapshot.listen == .command)
        #expect(snapshot.confirm?.lane == "galerie")
        #expect(snapshot.about == GinkgoAbout(project: name("treelab-app"), lane: name("reglages"), qid: nil))
        #expect(snapshot.lines.map(\.id) == ["u1", "g1"])
        #expect(snapshot.did.map(\.kind) == [.order])
    }

    @Test("unknown event, unknown field and incomplete event are ignored")
    func unknown() throws {
        #expect(try decode("{\(head),\"ev\":\"sing\",\"song\":\"la\"}") == nil)
        #expect(try decode("{\(head),\"ev\":\"wake\",\"loud\":true}")?.event == .wake)
        #expect(try decode("{\(head),\"ev\":\"state\",\"state\":\"dancing\",\"mic\":true}") == nil)
        #expect(try decode("{\(head),\"ev\":\"line\",\"who\":\"user\"}") == nil)
        #expect(try decode("not json") == nil)
        #expect(try decode("[1,2]") == nil)
        #expect(try decode("{\"v\":1,\"ev\":\"wake\",\"seq\":true,\"at\":1}") == nil)
    }

    @Test("an unsafe lane name in about is never shown")
    func unsafeAbout() throws {
        #expect(try decode("{\(head),\"ev\":\"about\",\"project\":\"../etc\",\"lane\":\"x\"}") == nil)
        #expect(try decode("{\(head),\"ev\":\"about\",\"project\":\"a;rm\",\"lane\":\"x\"}") == nil)
    }

    @Test("v other than 1 is refused with a message")
    func otherVersion() {
        #expect(throws: GinkgoProtocolError.unknownVersion(2)) { try decode("{\"v\":2,\"ev\":\"wake\",\"seq\":1,\"at\":1}") }
        #expect(throws: GinkgoProtocolError.unknownVersion(nil)) { try decode("{\"ev\":\"wake\",\"seq\":1,\"at\":1}") }
    }

    @Test("a seq that does not grow is ignored")
    func seq() {
        var session = GinkgoSession()
        let first = session.apply(envelope(5, .key(down: true)))
        let same = session.apply(envelope(5, .key(down: false)))
        let older = session.apply(envelope(3, .key(down: false)))
        #expect(first && !same && !older)
        #expect(session.keyDown)
        let next = session.apply(envelope(6, .key(down: false)))
        #expect(next)
        #expect(!session.keyDown)
    }
}

@Suite("Contract v1: line framing (§3)")
struct FramingTests {
    @Test("lines are cut at \\n, across reads")
    func cut() {
        var framer = GinkgoLineFramer()
        let first = framer.append(Data("{\"a\":1}\n{\"b\"".utf8))
        let second = framer.append(Data(":2}\n".utf8))
        #expect(first == [Data("{\"a\":1}".utf8)])
        #expect(second == [Data("{\"b\":2}".utf8)])
    }

    @Test("a line of 16 384 bytes is kept; one byte more is dropped up to the next \\n")
    func bound() {
        var framer = GinkgoLineFramer()
        let longest = Data(repeating: 0x61, count: ginkgoMaxLineBytes)
        let kept = framer.append(longest + Data([0x0A]))
        #expect(kept == [longest])
        let tooLong = Data(repeating: 0x62, count: ginkgoMaxLineBytes + 1)
        // Sent in two reads, then a good line right after the newline that ends it.
        let head = framer.append(tooLong.prefix(9000))
        let rest = framer.append(tooLong.dropFirst(9000) + Data("tail\n{\"ok\":1}\n".utf8))
        #expect(head.isEmpty)
        #expect(rest == [Data("{\"ok\":1}".utf8)])
        #expect(framer.dropped == 1)
    }
}

@Suite("Contract v1: Treelab's orders (§4)")
struct OrderTests {
    @Test("each order of §4 is written byte for byte, keys sorted, \\n at the end")
    func bytes() {
        let expected: [(GinkgoOrder, String)] = [
            (.hello(version: "1.2"), #"{"client":"treelab","id":1,"op":"hello","protocol":1,"v":1,"version":"1.2"}"#),
            (.open(focus: name("treelab-app")), #"{"focus":"treelab-app","id":2,"op":"open","v":1}"#),
            (.close, #"{"id":3,"op":"close","v":1}"#),
            (.mic(on: false), #"{"id":4,"on":false,"op":"mic","v":1}"#),
            (.cancelClose, #"{"id":5,"op":"cancel_close","v":1}"#),
            (.focus(project: name("carnet")), #"{"id":6,"op":"focus","project":"carnet","v":1}"#),
            (.subscribe([.levels]), #"{"id":7,"op":"subscribe","topics":["levels"],"v":1}"#),
            (.unsubscribe([.levels]), #"{"id":8,"op":"unsubscribe","topics":["levels"],"v":1}"#),
            (.quit, #"{"id":9,"op":"quit","v":1}"#),
        ]
        for (index, (order, line)) in expected.enumerated() {
            #expect(order.line(id: index + 1) == Data((line + "\n").utf8), "\(order.op)")
        }
    }

    @Test("the list of orders is exactly the 9 of §4: none confirms a close, answers or orders")
    func closedList() {
        let contract = ["hello", "open", "close", "mic", "cancel_close", "focus", "subscribe", "unsubscribe", "quit"]
        #expect(GinkgoOrder.allOps == contract)
        let every: [GinkgoOrder] = [.hello(version: "1"), .open(focus: name("p")), .close, .mic(on: true), .cancelClose,
                                    .focus(project: name("p")), .subscribe([.levels]), .unsubscribe([.levels]), .quit]
        #expect(every.map(\.op) == contract)
        for op in contract {
            #expect(!["confirm", "answer", "reply", "order", "tell", "yes"].contains { op.contains($0) }, "\(op)")
        }
    }
}
