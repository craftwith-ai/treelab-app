import Foundation
public import TreelabLanes

/// Every text of the lanes screens, localized from the package catalog (French with "tu", and
/// English; the other required languages are in the catalog too).
public struct LanesText: Sendable {
    /// Creates the text source.
    public init() {}

    /// "3 travaillent".
    public func working(_ count: Int) -> String {
        String(localized: "treelab.lanes.count.working", defaultValue: "\(count) working", bundle: .module)
    }

    /// "5 t'attendent".
    public func waiting(_ count: Int) -> String {
        String(localized: "treelab.lanes.count.waiting", defaultValue: "\(count) waiting for you", bundle: .module)
    }

    /// "2 arrêtées".
    public func stopped(_ count: Int) -> String {
        String(localized: "treelab.lanes.count.stopped", defaultValue: "\(count) stopped", bundle: .module)
    }

    /// "12 couloirs".
    public func lanes(_ count: Int) -> String {
        String(localized: "treelab.lanes.count.lanes", defaultValue: "\(count) lanes", bundle: .module)
    }

    /// "3 projets".
    public func projects(_ count: Int) -> String {
        String(localized: "treelab.lanes.count.projects", defaultValue: "\(count) projects", bundle: .module)
    }

    /// The name of a status, for the banner.
    public func status(_ status: LaneStatus) -> String {
        switch status {
        case .waitingForYou: String(localized: "treelab.lanes.status.waiting", defaultValue: "waiting for you", bundle: .module)
        case .working: String(localized: "treelab.lanes.status.working", defaultValue: "working", bundle: .module)
        case .stopped: String(localized: "treelab.lanes.status.stopped", defaultValue: "stopped", bundle: .module)
        case .offCounter: String(localized: "treelab.lanes.status.offCounter", defaultValue: "outside the counter", bundle: .module)
        }
    }

    /// The label of a request kind, in capitals.
    public func kind(_ kind: RequestKind?) -> String {
        switch kind ?? .other {
        case .question: String(localized: "treelab.lanes.kind.question", defaultValue: "QUESTION", bundle: .module)
        case .permission: String(localized: "treelab.lanes.kind.permission", defaultValue: "PERMISSION", bundle: .module)
        case .toTry: String(localized: "treelab.lanes.kind.toTry", defaultValue: "TO TRY", bundle: .module)
        case .blocked: String(localized: "treelab.lanes.kind.blocked", defaultValue: "BLOCKED", bundle: .module)
        case .toClarify: String(localized: "treelab.lanes.kind.toClarify", defaultValue: "TO CLARIFY", bundle: .module)
        case .closing: String(localized: "treelab.lanes.kind.closing", defaultValue: "CLOSING", bundle: .module)
        case .other: String(localized: "treelab.lanes.kind.other", defaultValue: "REQUEST", bundle: .module)
        }
    }

    /// A problem reading lab, in one sentence.
    public func problem(_ problem: LanesProblem) -> String {
        switch problem {
        case let .labUnavailable(reason):
            String(localized: "treelab.lanes.problem.labUnavailable", defaultValue: "lab not found: \(reason)", bundle: .module)
        case let .unknownLabVersion(version):
            String(localized: "treelab.lanes.problem.unknownVersion", defaultValue: "Treelab does not know this lab version (\(version)): update Treelab.", bundle: .module)
        case let .refusedFile(path, _):
            String(localized: "treelab.lanes.problem.refusedFile", defaultValue: "A lab file was refused for safety: \(path)", bundle: .module)
        case let .labRefused(reason):
            String(localized: "treelab.lanes.problem.labRefused", defaultValue: "lab refused: \(reason)", bundle: .module)
        }
    }

    /// The outcome of the last action.
    public func notice(_ notice: LanesNotice) -> String {
        switch notice {
        case let .sent(lane): String(localized: "treelab.feed.notice.sent", defaultValue: "Sent to \(lane).", bundle: .module)
        case let .relaunched(lanes): String(localized: "treelab.feed.notice.relaunched", defaultValue: "Relaunch asked for \(lanes.joined(separator: ", ")).", bundle: .module)
        case let .opened(lane): String(localized: "treelab.feed.notice.opened", defaultValue: "\(lane) opened.", bundle: .module)
        case let .refused(reason): String(localized: "treelab.feed.notice.refused", defaultValue: "lab refused, nothing was sent: \(reason)", bundle: .module)
        }
    }

    /// "attend depuis 28 min".
    public func waitingSince(_ duration: String) -> String {
        String(localized: "treelab.feed.waitingSince", defaultValue: "waiting for \(duration)", bundle: .module)
    }

    /// "reprend le 28 nov.".
    public func backOn(_ date: String) -> String {
        String(localized: "treelab.feed.backOn", defaultValue: "back on \(date)", bundle: .module)
    }

    /// Fixed labels.
    public var openFeed: String { String(localized: "treelab.lanes.counter.open", defaultValue: "Open the Feed", bundle: .module) }
    public var back: String { String(localized: "treelab.feed.back", defaultValue: "Lanes", bundle: .module) }
    public var queue: String { String(localized: "treelab.feed.queue", defaultValue: "QUEUE", bundle: .module) }
    public var oldestFirst: String { String(localized: "treelab.feed.oldestFirst", defaultValue: "oldest first", bundle: .module) }
    public var stoppedSection: String { String(localized: "treelab.feed.stoppedSection", defaultValue: "STOPPED", bundle: .module) }
    public var workingSection: String { String(localized: "treelab.feed.workingSection", defaultValue: "WORKING", bundle: .module) }
    public var offCounterSection: String { String(localized: "treelab.feed.offCounterSection", defaultValue: "AT REST · OUTSIDE THE COUNTER", bundle: .module) }
    public var relaunch: String { String(localized: "treelab.feed.relaunch", defaultValue: "Relaunch", bundle: .module) }
    public var relaunchAll: String { String(localized: "treelab.feed.relaunchAll", defaultValue: "Relaunch all", bundle: .module) }
    public var nothingRestarts: String { String(localized: "treelab.feed.nothingRestarts", defaultValue: "None restarts without a click.", bundle: .module) }
    public var empty: String { String(localized: "treelab.feed.empty", defaultValue: "Nothing waits for you.", bundle: .module) }
    public var readingQuestion: String { String(localized: "treelab.feed.readingQuestion", defaultValue: "Reading what the lane asks…", bundle: .module) }
    public var noQuestion: String { String(localized: "treelab.feed.noQuestion", defaultValue: "lab shows no question for this lane: open it to see.", bundle: .module) }
    public var lastMessage: String { String(localized: "treelab.feed.lastMessage", defaultValue: "LAST MESSAGE", bundle: .module) }
    public var recommended: String { String(localized: "treelab.feed.recommended", defaultValue: "recommended", bundle: .module) }
    public var send: String { String(localized: "treelab.feed.send", defaultValue: "Send", bundle: .module) }
    public var answerPlaceholder: String { String(localized: "treelab.feed.answerPlaceholder", defaultValue: "Tell Claude what to change…", bundle: .module) }
    public var openLane: String { String(localized: "treelab.feed.openLane", defaultValue: "Open the lane", bundle: .module) }
    public var nextRequest: String { String(localized: "treelab.feed.next", defaultValue: "NEXT", bundle: .module) }
    public var change: String { String(localized: "treelab.feed.keys.change", defaultValue: "change", bundle: .module) }
    public var answerKey: String { String(localized: "treelab.feed.keys.answer", defaultValue: "answer", bundle: .module) }
    public var sendKey: String { String(localized: "treelab.feed.keys.send", defaultValue: "send", bundle: .module) }
    public var chooseThenSend: String { String(localized: "treelab.feed.chooseThenSend", defaultValue: "Choose for each question, then send.", bundle: .module) }
    public var permanentLane: String { String(localized: "treelab.feed.permanent", defaultValue: "permanent lane", bundle: .module) }
}
