import Foundation

/// What Treelab knows of Ginkgo on one connection, built from its events (levels excluded: they
/// change 30 times a second and live in ``GinkgoLevels``).
public struct GinkgoSession: Sendable, Equatable {
    /// Lines kept on screen: the open conversation only, the latest ones.
    public static let maxLines = 200
    /// Actions kept on screen.
    public static let maxDid = 50

    public private(set) var version: String?
    public private(set) var state: GinkgoVoiceState = .closed
    public private(set) var mic = false
    public private(set) var focus: String?
    public private(set) var listen: GinkgoListenMode?
    public private(set) var lines: [GinkgoLine] = []
    public private(set) var did: [GinkgoDid] = []
    public private(set) var about: GinkgoAbout?
    public private(set) var pendingClose: GinkgoPendingClose?
    /// How the last close waiting for its "yes" ended, until the next one.
    public private(set) var lastCloseOutcome: GinkgoCloseOutcome?
    /// The last refusal or error, said in plain words by the screen.
    public private(set) var problem: Problem?
    private var lastSeq: Int?

    /// A refusal (`refused`) or an error (`error`).
    public struct Problem: Sendable, Equatable {
        public var isRefusal: Bool
        public var code: String
        public var text: String
    }

    public init() {}

    /// Applies an event.
    /// - Returns: `false` when it was ignored (a `seq` that does not grow, or a level).
    @discardableResult
    public mutating func apply(_ envelope: GinkgoEnvelope) -> Bool {
        if let lastSeq, envelope.seq <= lastSeq { return false }
        lastSeq = envelope.seq
        switch envelope.event {
        case let .hello(version, _, _, listen):
            self.version = version
            if let listen { self.listen = listen }
        case let .snapshot(snapshot):
            state = snapshot.state
            mic = snapshot.mic
            focus = snapshot.focus
            if let listen = snapshot.listen { self.listen = listen }
            pendingClose = snapshot.confirm
            about = snapshot.about
            lines = Array(snapshot.lines.suffix(Self.maxLines)).map { $0.dated(envelope.at) }
            did = Array(snapshot.did.suffix(Self.maxDid)).map { $0.dated(envelope.at) }
            problem = nil
        case let .state(newState, mic, focus):
            if newState.isConversation, !state.isConversation { startConversation() }
            state = newState
            self.mic = mic
            if let focus { self.focus = focus }
            if newState.isConversation { problem = nil }
        case .wake, .interrupt, .key, .news:
            // Read (§5) but not shown: announcements are lab's, said by Ginkgo itself.
            break
        case let .line(line):
            if let index = lines.lastIndex(where: { $0.id == line.id }) {
                lines[index] = line.dated(lines[index].at ?? envelope.at)
            } else {
                lines.append(line.dated(envelope.at))
                if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
            }
        case let .did(action):
            did.append(action.dated(envelope.at))
            if did.count > Self.maxDid { did.removeFirst(did.count - Self.maxDid) }
        case let .about(about):
            self.about = about
        case let .confirm(close):
            pendingClose = close
            lastCloseOutcome = nil
        case let .confirmEnd(project, lane, outcome):
            // Only one close waits at a time: an end without project nor lane is its end.
            let named = project != nil || lane != nil
            if !named || (pendingClose?.project == project && pendingClose?.lane == lane) { pendingClose = nil }
            lastCloseOutcome = outcome
        case let .mode(listen):
            self.listen = listen
        case let .refused(reason, text):
            problem = Problem(isRefusal: true, code: reason, text: text)
        case let .error(kind, text):
            problem = Problem(isRefusal: false, code: kind, text: text)
        case .level:
            return false
        case .ack:
            break
        case .bye:
            state = .closed
            mic = false
            pendingClose = nil
        }
        return true
    }

    /// The lines to show: with less motion asked by the Mac, whole lines only (§6).
    public func shownLines(wholeOnly: Bool) -> [GinkgoLine] {
        wholeOnly ? lines.filter(\.final) : lines
    }

    /// A new conversation shows only its own lines.
    private mutating func startConversation() {
        lines = []
        did = []
        about = nil
        lastCloseOutcome = nil
    }
}

extension GinkgoLine {
    /// The line with its start time, kept when it already has one.
    func dated(_ date: Date) -> GinkgoLine {
        var line = self
        if line.at == nil { line.at = date }
        return line
    }
}

extension GinkgoDid {
    /// The action with its time, kept when it already has one.
    func dated(_ date: Date) -> GinkgoDid {
        var action = self
        if action.at == nil { action.at = date }
        return action
    }
}
