public import Foundation
import TreelabLanes

/// Why a line from Ginkgo stops the connection.
public enum GinkgoProtocolError: Error, Sendable, Equatable {
    /// `v` is not 1: Ginkgo speaks another version of the contract.
    case unknownVersion(Int?)
}

/// Cuts the bytes read from the socket into lines, at most ``ginkgoMaxLineBytes`` each: a longer
/// line is dropped up to the next `\n`, and reading goes on.
public struct GinkgoLineFramer: Sendable {
    private var buffer = Data()
    private var skipping = false
    /// Lines dropped because they were too long.
    public private(set) var dropped = 0

    public init() {}

    /// Adds bytes read from the socket.
    /// - Returns: the complete lines, `\n` excluded.
    public mutating func append(_ bytes: Data) -> [Data] {
        var lines: [Data] = []
        for byte in bytes {
            if byte == 0x0A {
                if skipping { skipping = false } else { lines.append(buffer) }
                buffer.removeAll(keepingCapacity: true)
            } else if !skipping {
                buffer.append(byte)
                if buffer.count > ginkgoMaxLineBytes {
                    skipping = true
                    dropped += 1
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        }
        return lines
    }
}

/// Reads one line from Ginkgo (§3 and §5 of the contract).
public enum GinkgoEventDecoder {
    /// Decodes a line.
    /// - Returns: the event, or `nil` when it is unknown or incomplete (ignored).
    /// - Throws: ``GinkgoProtocolError/unknownVersion(_:)`` when `v` is not 1.
    public static func decode(_ line: Data) throws -> GinkgoEnvelope? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        let version = int(object["v"])
        guard version == ginkgoProtocolVersion else { throw GinkgoProtocolError.unknownVersion(version) }
        guard let name = object["ev"] as? String, let seq = int(object["seq"]), let at = int(object["at"]),
              let event = event(name, object)
        else { return nil }
        return GinkgoEnvelope(seq: seq, at: Date(timeIntervalSince1970: Double(at) / 1000), event: event)
    }

    private static func event(_ name: String, _ o: [String: Any]) -> GinkgoEvent? {
        switch name {
        case "hello":
            guard let version = o["ginkgo"] as? String, let proto = int(o["protocol"]) else { return nil }
            let capabilities = (o["capabilities"] as? [Any])?.compactMap { $0 as? String } ?? []
            return .hello(version: version, protocolVersion: proto, capabilities: capabilities,
                          listen: (o["listen"] as? String).flatMap(GinkgoListenMode.init(rawValue:)))
        case "snapshot":
            return snapshot(o).map(GinkgoEvent.snapshot)
        case "state":
            guard let state = (o["state"] as? String).flatMap(GinkgoVoiceState.init(rawValue:)), let mic = o["mic"] as? Bool
            else { return nil }
            return .state(state, mic: mic, focus: o["focus"] as? String)
        case "wake": return .wake
        case "key":
            guard let down = o["down"] as? Bool else { return nil }
            return .key(down: down)
        case "interrupt": return .interrupt
        case "line": return line(o).map(GinkgoEvent.line)
        case "did": return did(o).map(GinkgoEvent.did)
        case "about":
            if o["project"] == nil, o["lane"] == nil { return .about(nil) }
            return about(o).map(GinkgoEvent.about)
        case "confirm": return confirm(o).map(GinkgoEvent.confirm)
        case "confirm_end":
            guard let project = o["project"] as? String, let lane = o["lane"] as? String,
                  let outcome = (o["outcome"] as? String).flatMap(GinkgoCloseOutcome.init(rawValue:))
            else { return nil }
            return .confirmEnd(project: project, lane: lane, outcome: outcome)
        case "news":
            guard let project = o["project"] as? String, let lane = o["lane"] as? String,
                  let kind = o["kind"] as? String, let text = o["text"] as? String
            else { return nil }
            return .news(project: project, lane: lane, kind: kind, text: text)
        case "mode":
            guard let mode = (o["listen"] as? String).flatMap(GinkgoListenMode.init(rawValue:)) else { return nil }
            return .mode(mode)
        case "refused":
            guard let reason = o["reason"] as? String else { return nil }
            return .refused(reason: reason, text: o["text"] as? String ?? "")
        case "error":
            guard let kind = o["kind"] as? String else { return nil }
            return .error(kind: kind, text: o["text"] as? String ?? "")
        case "level":
            guard let input = double(o["in"]), let output = double(o["out"]) else { return nil }
            return .level(input: clamp(input), output: clamp(output))
        case "ack":
            guard let id = int(o["id"]), let ok = o["ok"] as? Bool else { return nil }
            return .ack(id: id, ok: ok, text: o["text"] as? String)
        case "bye": return .bye
        default: return nil
        }
    }

    private static func snapshot(_ o: [String: Any]) -> GinkgoSnapshot? {
        guard let state = (o["state"] as? String).flatMap(GinkgoVoiceState.init(rawValue:)), let mic = o["mic"] as? Bool
        else { return nil }
        return GinkgoSnapshot(
            state: state, mic: mic, focus: o["focus"] as? String,
            listen: (o["listen"] as? String).flatMap(GinkgoListenMode.init(rawValue:)),
            confirm: (o["confirm"] as? [String: Any]).flatMap(confirm),
            about: (o["about"] as? [String: Any]).flatMap(about),
            lines: ((o["lines"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(line) },
            did: ((o["did"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(did) }
        )
    }

    private static func line(_ o: [String: Any]) -> GinkgoLine? {
        guard let id = o["id"] as? String, let who = (o["who"] as? String).flatMap(GinkgoSpeaker.init(rawValue:)),
              let text = o["text"] as? String
        else { return nil }
        return GinkgoLine(id: id, who: who, text: text, final: o["final"] as? Bool ?? true)
    }

    private static func did(_ o: [String: Any]) -> GinkgoDid? {
        guard let kind = (o["kind"] as? String).flatMap(GinkgoDidKind.init(rawValue:)),
              let project = o["project"] as? String, let text = o["text"] as? String
        else { return nil }
        return GinkgoDid(kind: kind, project: project, lane: o["lane"] as? String, text: text)
    }

    /// Names are checked like every name passed to lab: an unsafe one is never shown as a lane.
    private static func about(_ o: [String: Any]) -> GinkgoAbout? {
        guard let project = (o["project"] as? String).flatMap(LabName.init),
              let lane = (o["lane"] as? String).flatMap(LabName.init)
        else { return nil }
        return GinkgoAbout(project: project, lane: lane, qid: o["qid"] as? String)
    }

    private static func confirm(_ o: [String: Any]) -> GinkgoPendingClose? {
        guard let project = o["project"] as? String, let lane = o["lane"] as? String, let until = int(o["until"])
        else { return nil }
        return GinkgoPendingClose(project: project, lane: lane, until: Date(timeIntervalSince1970: Double(until) / 1000))
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 9.0e15 else { return nil }
        return number.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
