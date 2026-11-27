public import Foundation
public import Observation
public import TreelabLanes

/// Where Ginkgo stands for Treelab.
public enum GinkgoPresence: Sendable, Equatable {
    /// Not looked at yet.
    case unknown
    /// Not running, or not listening on its socket.
    case absent
    /// lab was asked to start it: Treelab waits for its ready signal.
    case starting
    /// Connected: ``GinkgoModel/session`` follows it.
    case connected
    /// Ginkgo does not speak this contract (no `PROTOCOL=1`, or lab refused `--background` by its
    /// usage): nothing is launched.
    case updateNeeded
    /// Ginkgo answered with another version of the contract (`v`): Treelab disconnected.
    case unknownVersion
    /// The OpenAI key is not stored: nothing is launched.
    case keyMissing
    /// The socket failed a safety check: Treelab does not connect.
    case refused(GinkgoSocketRefusal)
    /// lab is missing or failed; its first line of error, if any.
    case labFailed(String)
}

/// What the microphone does.
public enum GinkgoMicrophone: Sendable, Equatable {
    /// Closed.
    case off
    /// Open for a conversation: the voice goes to OpenAI.
    case conversation
    /// Open only to hear Ginkgo's name, on the Mac (listen mode `name`).
    case name
}

/// A plain message about the last action.
public enum GinkgoNotice: Sendable, Equatable {
    /// No lab project is known to start the conversation on.
    case noProject
    /// Ginkgo refused an order, in its words.
    case orderRefused(String)
}

/// What the Ginkgo screens observe, and the orders they give. Every order goes through Ginkgo's
/// socket, and Ginkgo is only started by lab: Treelab never touches sound and never confirms a close.
///
/// ```swift
/// let ginkgo = GinkgoModel.live(home: home, version: "1.0", focus: { project })
/// ginkgo.start()
/// ginkgo.openFromBar()
/// ```
@MainActor
@Observable
public final class GinkgoModel {
    /// Where Ginkgo stands.
    public private(set) var presence: GinkgoPresence = .unknown
    /// What Ginkgo said on the current connection.
    public private(set) var session = GinkgoSession()
    /// The voice screen covers a window.
    public var isScreenPresented = false
    /// "Keep Ginkgo active": on, Ginkgo starts with Treelab without microphone and stays; off,
    /// ending the conversation stops Ginkgo.
    public private(set) var keepActive: Bool
    /// The levels are subscribed to (screen visible, conversation open, motion allowed).
    public private(set) var isSubscribedToLevels = false
    /// The outcome of the last action.
    public private(set) var notice: GinkgoNotice?
    /// The voice levels, outside observation.
    @ObservationIgnored public let levels = GinkgoLevels()
    /// Called when Ginkgo starts talking about a lane, so the Feed can show its request.
    @ObservationIgnored public var onAbout: (@MainActor (GinkgoAbout) -> Void)?

    /// The preference key of "Keep Ginkgo active".
    public static let keepActiveKey = "TreelabGinkgoKeepActive"

    @ObservationIgnored private let runner: (any LabCommandRunning)?
    @ObservationIgnored private let location: GinkgoSocketLocation
    @ObservationIgnored private let signals: any GinkgoSignals
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clientVersion: String
    @ObservationIgnored private let focusProject: @MainActor () -> LabName?
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool
    @ObservationIgnored private let peer: GinkgoConnection.PeerReader
    @ObservationIgnored private var connection: GinkgoConnection?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isScreenVisible = false
    @ObservationIgnored private var quitSent = false
    @ObservationIgnored private var backgroundLaunchWaiting = false
    /// A click that waits for the connection's snapshot (or for Ginkgo to start) to open the
    /// conversation, so an open one is never opened twice.
    @ObservationIgnored private var pendingOpen: LabName?
    @ObservationIgnored private var hasSnapshot = false
    /// The connection's last `seq`, levels included; kept here so a level never touches the
    /// observed session.
    @ObservationIgnored private var lastSeq: Int?

    /// Creates the model.
    /// - Parameters:
    ///   - runner: runs lab; `nil` when lab is unavailable.
    ///   - location: Ginkgo's socket.
    ///   - signals: Ginkgo's ready and end signals.
    ///   - defaults: where "Keep Ginkgo active" is kept.
    ///   - clientVersion: Treelab's version, sent in `hello`.
    ///   - focus: the project of the lane shown, where a conversation starts.
    ///   - reduceMotion: whether the Mac asks for less motion (then no level is asked for).
    ///   - peer: reads the socket peer's user; the kernel's by default.
    public init(runner: (any LabCommandRunning)?, location: GinkgoSocketLocation, signals: any GinkgoSignals,
                defaults: UserDefaults, clientVersion: String, focus: @escaping @MainActor () -> LabName?,
                reduceMotion: @escaping @MainActor () -> Bool, peer: @escaping GinkgoConnection.PeerReader = GinkgoConnection.kernelPeer) {
        self.runner = runner
        self.location = location
        self.signals = signals
        self.defaults = defaults
        self.clientVersion = clientVersion
        self.focusProject = focus
        self.reduceMotion = reduceMotion
        self.peer = peer
        keepActive = defaults.bool(forKey: Self.keepActiveKey)
    }

    // MARK: Actions

    /// Follows Ginkgo: connects if it listens, and starts it in the background when "Keep Ginkgo
    /// active" is on. Calling it again does nothing.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        // Streams are made now, so a ready signal sent while lab starts Ginkgo is not missed.
        let ready = signals.ready()
        let ends = signals.terminations()
        tasks.append(Task { [weak self] in
            for await _ in ready { self?.ginkgoIsReady() }
        })
        tasks.append(Task { [weak self] in
            for await _ in ends { self?.ginkgoEnded() }
        })
        if !connectIfListening(), keepActive { launchInBackground() }
    }

    /// The bar's click: shows the voice screen and opens the conversation.
    public func openFromBar() {
        isScreenPresented = true
        talk()
    }

    /// "Talk": opens the conversation on the project shown, starting Ginkgo through lab when it is
    /// not running. A conversation already open is left as it is.
    public func talk() {
        notice = nil
        guard let project = focusProject() else {
            notice = .noProject
            return
        }
        if connectIfListening() {
            openWhenKnown(project)
            return
        }
        if presence == .starting {
            // Ginkgo is starting (in the background): the conversation opens once connected.
            pendingOpen = project
            return
        }
        Task { await launch(project: project, background: false) }
    }

    /// Escape on the screen: closes the microphone. With "Keep Ginkgo active" Ginkgo stays
    /// (`close`), otherwise it stops (`quit`).
    public func closeMicrophone() {
        guard let connection else { return }
        if keepActive {
            connection.send(.close)
        } else {
            quitSent = true
            connection.send(.quit)
        }
    }

    /// Escape on the voice screen: closes the microphone while a conversation is open; otherwise
    /// takes the person back to the lanes.
    public func escape() {
        if isConversationOpen {
            closeMicrophone()
        } else {
            dismissScreen()
        }
    }

    /// "Cancel" on a close waiting for its spoken "yes".
    public func cancelClose() {
        connection?.send(.cancelClose)
    }

    /// Turns "Keep Ginkgo active" on or off; it applies from the next end of conversation and the
    /// next launch of Treelab.
    public func setKeepActive(_ on: Bool) {
        keepActive = on
        defaults.set(on, forKey: Self.keepActiveKey)
    }

    /// The voice screen became visible or hidden: levels are only asked for while it is seen.
    public func setScreenVisible(_ visible: Bool) {
        isScreenVisible = visible
        updateLevelSubscription()
    }

    /// Hides the voice screen; the conversation goes on.
    public func dismissScreen() {
        isScreenPresented = false
        setScreenVisible(false)
    }

    /// lab's projects changed: a background start waiting for a project goes now.
    public func projectsChanged() {
        if backgroundLaunchWaiting, connection == nil { launchInBackground() }
    }

    /// Opens the conversation on `project` unless one is open; on a fresh connection, once its
    /// snapshot says whether one is.
    private func openWhenKnown(_ project: LabName) {
        guard hasSnapshot else {
            pendingOpen = project
            return
        }
        if !session.state.isConversation { connection?.send(.open(focus: project)) }
    }

    /// Whether the microphone is open now.
    public var isMicrophoneOpen: Bool { presence == .connected && session.mic }

    /// Whether a conversation is open now.
    public var isConversationOpen: Bool { presence == .connected && session.state.isConversation }

    /// Whether the Mac asks for less motion: the heart stays still and only whole lines are shown.
    public var isMotionReduced: Bool { reduceMotion() }

    /// What the microphone does now, said the same way by the bar and the voice screen.
    public var microphone: GinkgoMicrophone {
        guard isMicrophoneOpen else { return .off }
        return session.state.isConversation ? .conversation : .name
    }

    // MARK: Connection

    /// Connects when Ginkgo listens.
    /// - Returns: whether a connection is open.
    @discardableResult
    private func connectIfListening() -> Bool {
        if connection != nil { return true }
        do {
            attach(try GinkgoConnection.open(location, peer: peer))
            return true
        } catch let refusal as GinkgoSocketRefusal {
            if case .absent = refusal {
                switch presence {
                case .unknown, .connected, .refused: setPresence(.absent)
                default: break
                }
            } else {
                setPresence(.refused(refusal))
            }
            return false
        } catch {
            return false
        }
    }

    private func attach(_ connection: GinkgoConnection) {
        self.connection = connection
        session = GinkgoSession()
        setPresence(.connected)
        isSubscribedToLevels = false
        hasSnapshot = false
        lastSeq = nil
        quitSent = false
        backgroundLaunchWaiting = false
        connection.send(.hello(version: clientVersion))
        tasks.append(Task { [weak self] in
            for await item in connection.events {
                guard let self else { return }
                self.handle(item, from: connection)
            }
        })
    }

    private func handle(_ item: GinkgoConnectionEvent, from source: GinkgoConnection) {
        guard source === connection else { return }
        switch item {
        case let .event(envelope):
            // One growing `seq` per connection for every event, levels included (§3).
            if let lastSeq, envelope.seq <= lastSeq { return }
            lastSeq = envelope.seq
            if case let .level(input, output) = envelope.event {
                if isSubscribedToLevels { levels.update(input: input, output: output) }
                return
            }
            let wasConversation = session.state.isConversation
            let previousAbout = session.about
            guard session.apply(envelope) else { return }
            switch envelope.event {
            case .bye:
                detach(.absent)
                return
            case let .hello(_, protocolVersion, _, _) where protocolVersion != ginkgoProtocolVersion:
                // §7: Treelab requires protocol 1, also from a Ginkgo already running.
                detach(.updateNeeded)
                return
            case .snapshot:
                hasSnapshot = true
                if let project = pendingOpen {
                    pendingOpen = nil
                    if !session.state.isConversation { source.send(.open(focus: project)) }
                }
            case let .ack(_, ok, text) where !ok:
                notice = .orderRefused(text ?? "")
            default:
                break
            }
            if let about = session.about, about != previousAbout { onAbout?(about) }
            if wasConversation, !session.state.isConversation, !keepActive, !quitSent {
                quitSent = true
                source.send(.quit)
            }
            updateLevelSubscription()
        case let .ended(end):
            if case .unknownVersion = end { detach(.unknownVersion) } else { detach(.absent) }
        }
    }

    private func detach(_ newPresence: GinkgoPresence) {
        connection?.close()
        connection = nil
        setPresence(newPresence)
        session = GinkgoSession()
        isSubscribedToLevels = false
        levels.reset()
    }

    /// Where Ginkgo stands changed: a notice about an earlier action no longer holds, and a click
    /// waiting to open the conversation is dropped when Ginkgo cannot be reached.
    private func setPresence(_ newPresence: GinkgoPresence) {
        if newPresence != presence { notice = nil }
        if newPresence != .starting, newPresence != .connected { pendingOpen = nil }
        presence = newPresence
    }

    private func updateLevelSubscription() {
        let wanted = connection != nil && isScreenVisible && session.state.isConversation && !reduceMotion()
        guard wanted != isSubscribedToLevels else { return }
        isSubscribedToLevels = wanted
        if !wanted { levels.reset() }
        connection?.send(wanted ? .subscribe([.levels]) : .unsubscribe([.levels]))
    }

    private func ginkgoIsReady() {
        connectIfListening()
    }

    private func ginkgoEnded() {
        if presence == .starting { setPresence(.absent) }
    }

    // MARK: Launch through lab

    private func launchInBackground() {
        guard let project = focusProject() else {
            backgroundLaunchWaiting = true
            followFocus()
            return
        }
        backgroundLaunchWaiting = false
        Task { await launch(project: project, background: true) }
    }

    /// Waits for the project a background start needs: whatever `focus` reads (lab's projects,
    /// the lane shown) is followed, so no view has to be on screen to tell.
    private func followFocus() {
        withObservationTracking {
            _ = focusProject()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.projectsChanged() }
        }
    }

    /// Starts Ginkgo through lab, after `lab ginkgo status` says it speaks this contract and the
    /// key is stored (contract v1.1); otherwise nothing is launched.
    func launch(project: LabName, background: Bool) async {
        guard presence != .starting else { return }
        guard let runner else {
            setPresence(.labFailed(""))
            return
        }
        setPresence(.starting)
        do {
            let status = try await runner.run(.ginkgoStatus)
            let block = KeyValueBlockParser().blocks(in: status.standardOutput).first
            guard status.status == 0, block?.first("PROTOCOL") == String(ginkgoProtocolVersion) else {
                setPresence(.updateNeeded)
                return
            }
            guard block?.first("KEY") == "present" else {
                setPresence(.keyMissing)
                return
            }
            // Started meanwhile (its ready signal came): lab would stop it to start it again.
            if connectIfListening() {
                if !background { openWhenKnown(project) }
                return
            }
            let result = try await runner.run(.ginkgoLaunch(project: project, background: background))
            if result.status == 2 {
                setPresence(.updateNeeded)
                return
            }
            guard result.status == 0 else {
                setPresence(.labFailed(Self.firstLine(result.standardError)))
                return
            }
            // Its ready signal may have come before lab returned.
            connectIfListening()
        } catch {
            setPresence(.labFailed(Self.firstLine(String(describing: error))))
        }
    }

    private static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n", omittingEmptySubsequences: true).first ?? "").trimmingCharacters(in: .whitespaces)
    }
}
