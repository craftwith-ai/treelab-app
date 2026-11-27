public import Foundation
public import TreelabLanes

// Contract v1 between Treelab and Ginkgo.app (docs: contrat-ginkgo.md of the essai-fork lane).
// One JSON object per line; every message carries "v":1.

/// The protocol version Treelab speaks.
public let ginkgoProtocolVersion = 1

/// The largest line accepted, `\n` excluded.
public let ginkgoMaxLineBytes = 16_384

/// What Ginkgo is doing.
public enum GinkgoVoiceState: String, Sendable, Equatable, CaseIterable {
    case closed, connecting, listening, thinking, speaking, paused
    case nameListening = "name_listening"

    /// A conversation is open: the microphone listens to the person and the voice goes to OpenAI.
    public var isConversation: Bool {
        switch self {
        case .connecting, .listening, .thinking, .speaking: true
        case .closed, .paused, .nameListening: false
        }
    }
}

/// When Ginkgo listens.
public enum GinkgoListenMode: String, Sendable, Equatable {
    case command, key, name
}

/// Who said a line.
public enum GinkgoSpeaker: String, Sendable, Equatable {
    case user, ginkgo
}

/// What Ginkgo did for the person.
public enum GinkgoDidKind: String, Sendable, Equatable {
    case read, tell, answer, order, close, reply
}

/// How a close waiting for its spoken "yes" ended.
public enum GinkgoCloseOutcome: String, Sendable, Equatable {
    case confirmed, cancelled, expired
}

/// A line of the open conversation; a partial text is replaced by the next one with the same id.
public struct GinkgoLine: Sendable, Equatable {
    public var id: String
    public var who: GinkgoSpeaker
    public var text: String
    public var final: Bool

    public init(id: String, who: GinkgoSpeaker, text: String, final: Bool) {
        self.id = id
        self.who = who
        self.text = text
        self.final = final
    }
}

/// One thing Ginkgo did, in one plain sentence.
public struct GinkgoDid: Sendable, Equatable {
    public var kind: GinkgoDidKind
    public var project: String
    public var lane: String?
    public var text: String

    public init(kind: GinkgoDidKind, project: String, lane: String?, text: String) {
        self.kind = kind
        self.project = project
        self.lane = lane
        self.text = text
    }
}

/// The lane Ginkgo is talking about.
public struct GinkgoAbout: Sendable, Equatable {
    public var project: LabName
    public var lane: LabName
    public var qid: String?

    public init(project: LabName, lane: LabName, qid: String?) {
        self.project = project
        self.lane = lane
        self.qid = qid
    }
}

/// A lane close waiting for the person's spoken "yes".
public struct GinkgoPendingClose: Sendable, Equatable {
    public var project: String
    public var lane: String
    public var until: Date

    public init(project: String, lane: String, until: Date) {
        self.project = project
        self.lane = lane
        self.until = until
    }
}

/// The whole state sent right after `hello`.
public struct GinkgoSnapshot: Sendable, Equatable {
    public var state: GinkgoVoiceState
    public var mic: Bool
    public var focus: String?
    public var listen: GinkgoListenMode?
    public var confirm: GinkgoPendingClose?
    public var about: GinkgoAbout?
    public var lines: [GinkgoLine]
    public var did: [GinkgoDid]

    public init(state: GinkgoVoiceState, mic: Bool, focus: String?, listen: GinkgoListenMode?,
                confirm: GinkgoPendingClose?, about: GinkgoAbout?, lines: [GinkgoLine], did: [GinkgoDid]) {
        self.state = state
        self.mic = mic
        self.focus = focus
        self.listen = listen
        self.confirm = confirm
        self.about = about
        self.lines = lines
        self.did = did
    }
}

/// An event from Ginkgo (§5 of the contract).
public enum GinkgoEvent: Sendable, Equatable {
    case hello(version: String, protocolVersion: Int, capabilities: [String], listen: GinkgoListenMode?)
    case snapshot(GinkgoSnapshot)
    case state(GinkgoVoiceState, mic: Bool, focus: String?)
    case wake
    case key(down: Bool)
    case interrupt
    case line(GinkgoLine)
    case did(GinkgoDid)
    /// `nil`: Ginkgo talks about no lane any more.
    case about(GinkgoAbout?)
    case confirm(GinkgoPendingClose)
    case confirmEnd(project: String, lane: String, outcome: GinkgoCloseOutcome)
    case news(project: String, lane: String, kind: String, text: String)
    case mode(GinkgoListenMode)
    case refused(reason: String, text: String)
    case error(kind: String, text: String)
    case level(input: Double, output: Double)
    case ack(id: Int, ok: Bool, text: String?)
    case bye
}

/// An event with its order number and time.
public struct GinkgoEnvelope: Sendable, Equatable {
    public var seq: Int
    public var at: Date
    public var event: GinkgoEvent

    public init(seq: Int, at: Date, event: GinkgoEvent) {
        self.seq = seq
        self.at = at
        self.event = event
    }
}

/// What can be subscribed to.
public enum GinkgoTopic: String, Sendable, Equatable {
    case levels
}

/// An order from Treelab (§4 of the contract): a closed list. There is no order that confirms a
/// close, answers a lane or orders a tower: those stay the person's own voice.
public enum GinkgoOrder: Sendable, Equatable {
    case hello(version: String)
    case open(focus: LabName)
    case close
    case mic(on: Bool)
    case cancelClose
    case focus(project: LabName)
    case subscribe([GinkgoTopic])
    case unsubscribe([GinkgoTopic])
    case quit

    /// The operation name sent as `op`.
    public var op: String {
        switch self {
        case .hello: "hello"
        case .open: "open"
        case .close: "close"
        case .mic: "mic"
        case .cancelClose: "cancel_close"
        case .focus: "focus"
        case .subscribe: "subscribe"
        case .unsubscribe: "unsubscribe"
        case .quit: "quit"
        }
    }

    /// Every operation name of the contract, for the closed-list check.
    public static let allOps = ["hello", "open", "close", "mic", "cancel_close", "focus", "subscribe", "unsubscribe", "quit"]

    /// The line sent to Ginkgo, `\n` included; keys sorted so the bytes are stable.
    /// - Parameter id: the order number, increasing on the connection.
    public func line(id: Int) -> Data {
        var object: [String: Any] = ["v": ginkgoProtocolVersion, "op": op, "id": id]
        switch self {
        case let .hello(version):
            object["client"] = "treelab"
            object["version"] = version
            object["protocol"] = ginkgoProtocolVersion
        case let .open(focus):
            object["focus"] = focus.value
        case let .mic(on):
            object["on"] = on
        case let .focus(project):
            object["project"] = project.value
        case let .subscribe(topics), let .unsubscribe(topics):
            object["topics"] = topics.map(\.rawValue)
        case .close, .cancelClose, .quit:
            break
        }
        // Only strings, integers, booleans and arrays of strings: serialization cannot fail.
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        data.append(0x0A)
        return data
    }
}
