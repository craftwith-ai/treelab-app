import Foundation
import TreelabGinkgo

/// Every text of the Ginkgo screens, localized from the package catalog (French with "tu", and
/// English; the other required languages are in the catalog too).
struct GinkgoText: Sendable {
    private func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value, bundle: .module)
    }

    var subtitle: String { t("treelab.ginkgo.subtitle", "your voice to steer your lanes") }
    var micOn: String { t("treelab.ginkgo.mic.on", "Microphone on") }
    var micOnDetail: String { t("treelab.ginkgo.mic.on.detail", "your voice goes to OpenAI during this conversation") }
    var micOff: String { t("treelab.ginkgo.mic.off", "Microphone off") }
    var micOffDetail: String { t("treelab.ginkgo.mic.off.detail", "nothing is heard, nothing leaves") }
    var listenLabel: String { t("treelab.ginkgo.listen.label", "Listening:") }

    func listen(_ mode: GinkgoListenMode) -> String {
        switch mode {
        case .command: t("treelab.ginkgo.listen.command", "on click")
        case .key: t("treelab.ginkgo.listen.key", "key held")
        case .name: t("treelab.ginkgo.listen.name", "its name")
        }
    }

    /// The big title and the line under it, for a state.
    func state(_ state: GinkgoVoiceState, awaitingYes: Bool) -> (title: String, detail: String) {
        switch state {
        case .listening:
            (t("treelab.ginkgo.state.listening", "LISTENING"),
             awaitingYes ? t("treelab.ginkgo.state.listening.confirm", "Say “yes” to confirm, or “stop”.")
                         : t("treelab.ginkgo.state.listening.detail", "Speak when you like."))
        case .thinking:
            (t("treelab.ginkgo.state.thinking", "THINKING"), t("treelab.ginkgo.state.thinking.detail", "Ginkgo reads the state of your lanes."))
        case .speaking:
            (t("treelab.ginkgo.state.speaking", "SPEAKING"), t("treelab.ginkgo.state.speaking.detail", "Ginkgo answers out loud."))
        case .connecting:
            (t("treelab.ginkgo.state.connecting", "CONNECTING"), t("treelab.ginkgo.state.connecting.detail", "Ginkgo opens the conversation with OpenAI."))
        case .paused:
            (t("treelab.ginkgo.state.paused", "PAUSED"), t("treelab.ginkgo.state.paused.detail", "The conversation waits."))
        case .nameListening:
            (t("treelab.ginkgo.state.name", "WAITING FOR ITS NAME"), t("treelab.ginkgo.state.name.detail", "Say “Ginkgo” to talk."))
        case .closed:
            (t("treelab.ginkgo.state.closed", "MICROPHONE OFF"), t("treelab.ginkgo.state.closed.detail", "Nothing is heard, nothing leaves."))
        }
    }

    var shortListening: String { t("treelab.ginkgo.short.listening", "Listening") }
    var shortThinking: String { t("treelab.ginkgo.short.thinking", "Thinking") }
    var shortSpeaking: String { t("treelab.ginkgo.short.speaking", "Speaking") }
    var shortClosed: String { t("treelab.ginkgo.short.closed", "Mic off") }

    var conversationTitle: String { t("treelab.ginkgo.conversation", "CONVERSATION") }
    var conversationDetail: String { t("treelab.ginkgo.conversation.detail", "what you say is written, then Ginkgo’s answer") }
    var conversationEmpty: String {
        t("treelab.ginkgo.conversation.empty", "Click “Talk” or Ginkgo in the sidebar: the microphone opens, and closes when you say “stop”.")
    }
    var you: String { t("treelab.ginkgo.who.user", "YOU") }

    var didTitle: String { t("treelab.ginkgo.did", "WHAT GINKGO DID") }
    var didEmpty: String { t("treelab.ginkgo.did.empty", "Nothing yet: Ginkgo only acts when you ask.") }

    func did(_ kind: GinkgoDidKind) -> String {
        switch kind {
        case .read: t("treelab.ginkgo.did.read", "Read")
        case .tell: t("treelab.ginkgo.did.tell", "Message passed")
        case .answer: t("treelab.ginkgo.did.answer", "Answer sent")
        case .order: t("treelab.ginkgo.did.order", "Order given")
        case .close: t("treelab.ginkgo.did.close", "Close asked")
        case .reply: t("treelab.ginkgo.did.reply", "Tower’s reply")
        }
    }

    var confirmTitle: String { t("treelab.ginkgo.confirm", "TO CONFIRM OUT LOUD") }
    func confirmWhat(_ lane: String) -> String { t("treelab.ginkgo.confirm.what", "Close \(lane)") }
    var confirmDetail: String { t("treelab.ginkgo.confirm.detail", "Say “yes” within 2 minutes; without your “yes”, nothing happens.") }
    var cancel: String { t("treelab.ginkgo.confirm.cancel", "Cancel") }
    var timeLeft: String { t("treelab.ginkgo.confirm.left", "Time left") }

    func outcome(_ outcome: GinkgoCloseOutcome) -> String {
        switch outcome {
        case .cancelled: t("treelab.ginkgo.outcome.cancelled", "Close cancelled: nothing is done.")
        case .expired: t("treelab.ginkgo.outcome.expired", "No “yes” in time: nothing is closed.")
        case .confirmed: t("treelab.ginkgo.outcome.confirmed", "Close confirmed out loud.")
        }
    }

    var aboutTitle: String { t("treelab.ginkgo.about", "GINKGO IS TALKING ABOUT") }
    var aboutOpen: String { t("treelab.ginkgo.about.open", "See in the Feed") }
    var closeMicrophone: String { t("treelab.ginkgo.button.close", "Close the microphone") }
    var talk: String { t("treelab.ginkgo.button.talk", "Talk") }
    var keepActive: String { t("treelab.ginkgo.keep", "Keep Ginkgo active") }
    var keepActiveOn: String { t("treelab.ginkgo.keep.on", "Ginkgo starts with Treelab, microphone off, and stays in the background.") }
    var keepActiveOff: String { t("treelab.ginkgo.keep.off", "Ending the conversation stops Ginkgo.") }
    var help: String {
        t("treelab.ginkgo.help", "Escape or “stop” closes the microphone, so does a silence; a second Escape takes you back to the lanes. Ginkgo uses your OpenAI key, kept in the Mac’s keychain.")
    }

    /// What the screen says when Ginkgo is not connected, `nil` when it is.
    func presence(_ presence: GinkgoPresence) -> String? {
        switch presence {
        case .connected, .unknown: nil
        case .absent: t("treelab.ginkgo.presence.absent", "Ginkgo is not running: “Talk” starts it.")
        case .starting: t("treelab.ginkgo.presence.starting", "Ginkgo is starting…")
        case .updateNeeded:
            t("treelab.ginkgo.presence.update", "Ginkgo needs an update to work with Treelab: update treelab, then try again. Nothing was started.")
        case .unknownVersion:
            t("treelab.ginkgo.presence.version", "Unknown version of Ginkgo: update Treelab and Ginkgo. Treelab disconnected.")
        case .keyMissing:
            t("treelab.ginkgo.presence.key", "Ginkgo needs your OpenAI key: type lab ginkgo key openai in a terminal. Nothing was started.")
        case let .refused(refusal):
            t("treelab.ginkgo.presence.refused", "Ginkgo’s channel is not safe (\(Self.path(of: refusal))): Treelab does not connect.")
        case let .labFailed(line):
            t("treelab.ginkgo.presence.lab", "lab could not start Ginkgo: \(line)")
        }
    }

    func notice(_ notice: GinkgoNotice) -> String {
        switch notice {
        case .noProject: t("treelab.ginkgo.notice.project", "No lab project found to talk about.")
        case let .orderRefused(text): t("treelab.ginkgo.notice.refused", "Ginkgo refused: \(text)")
        }
    }

    /// A refusal or an error from Ginkgo, in plain words; Ginkgo's own text otherwise.
    func problem(_ problem: GinkgoSession.Problem) -> String {
        switch problem.code {
        case "no_key": t("treelab.ginkgo.problem.key", "Ginkgo has no OpenAI key: type lab ginkgo key openai in a terminal.")
        case "mic_denied":
            t("treelab.ginkgo.problem.mic", "The Mac refuses the microphone to Ginkgo: allow it in System Settings › Privacy & Security › Microphone.")
        default: problem.text
        }
    }

    /// The bar entry's second line.
    func bar(_ presence: GinkgoPresence, state: GinkgoVoiceState, mic: Bool) -> String {
        switch presence {
        case .connected:
            guard mic, state.isConversation else { return t("treelab.ginkgo.bar.closed", "Microphone off · click to talk") }
            switch state {
            case .thinking: return t("treelab.ginkgo.bar.thinking", "Microphone on · thinking")
            case .speaking: return t("treelab.ginkgo.bar.speaking", "Microphone on · speaking")
            default: return t("treelab.ginkgo.bar.listening", "Microphone on · listening")
            }
        case .absent, .unknown: return t("treelab.ginkgo.bar.absent", "Not running · click to talk")
        case .starting: return t("treelab.ginkgo.bar.starting", "Starting…")
        case .updateNeeded, .unknownVersion: return t("treelab.ginkgo.bar.update", "Update needed")
        case .keyMissing: return t("treelab.ginkgo.bar.key", "OpenAI key missing")
        case .refused, .labFailed: return t("treelab.ginkgo.bar.problem", "Unavailable")
        }
    }

    var openGinkgo: String { t("treelab.ginkgo.bar.open", "Open Ginkgo") }

    private static func path(of refusal: GinkgoSocketRefusal) -> String {
        switch refusal {
        case let .pathTooLong(path), let .absent(path), let .notASocket(path), let .foreignOwner(path), let .openToOthers(path): path
        case let .foreignPeer(uid): "uid \(uid)"
        }
    }
}
