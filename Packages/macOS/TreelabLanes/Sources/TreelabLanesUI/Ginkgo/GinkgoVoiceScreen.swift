import AppKit
public import SwiftUI
public import TreelabGinkgo

/// Ginkgo's voice screen, over the whole window (plan "Ginkgo · voice screen" of the accepted
/// mock-up): the heart that follows the voice on the left, the conversation being written, what
/// Ginkgo did, the lane it talks about and a close waiting for a spoken "yes" on the right.
/// Escape closes the microphone, a second Escape goes back to the lanes.
public struct GinkgoVoiceScreen: View {
    @Bindable private var model: GinkgoModel
    private let onShowRequest: (GinkgoAbout) -> Void
    private let palette = HUDPalette()
    private let text = GinkgoText()
    @State private var host = HostWindow()
    /// The screen holds the keyboard focus, like the Feed: without it Escape never reaches it.
    @FocusState private var focused: Bool

    /// Creates the screen.
    /// - Parameters:
    ///   - model: Ginkgo's model.
    ///   - onShowRequest: "See in the Feed" on the lane Ginkgo talks about.
    public init(model: GinkgoModel, onShowRequest: @escaping (GinkgoAbout) -> Void) {
        self.model = model
        self.onShowRequest = onShowRequest
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = GinkgoScreenSize(width: proxy.size.width)
            VStack(spacing: 0) {
                GinkgoScreenHeader(model: model)
                Rectangle().fill(palette.line).frame(height: 1)
                HStack(alignment: .top, spacing: size.gap) {
                    GinkgoStateColumn(model: model, size: size)
                        .frame(width: size.leftColumn)
                    VStack(alignment: .leading, spacing: 14) {
                        GinkgoMessage(model: model)
                        GinkgoConversationCard(session: model.session, wholeOnly: model.isMotionReduced, size: size)
                        GinkgoActivity(model: model, size: size, onShowRequest: onShowRequest)
                        GinkgoScreenFooter(model: model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, 20).padding(.horizontal, 28).padding(.bottom, 24)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, .dark)
        .background(HostWindowReader(host: host))
        .onExitCommand { model.escape() }
        .onAppear { model.setScreenVisible(true) }
        .onDisappear { model.setScreenVisible(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            // A hidden or covered window draws nothing: the levels stop until it is seen again.
            guard let window = host.window, (note.object as? NSWindow) === window else { return }
            model.setScreenVisible(window.occlusionState.contains(.visible))
        }
    }
}

/// The two sizes of the mock-up: 1280 and, from 1600 points wide, 1728.
struct GinkgoScreenSize {
    let isLarge: Bool
    init(width: CGFloat) { isLarge = width >= 1600 }
    var leftColumn: CGFloat { isLarge ? 700 : 520 }
    var gap: CGFloat { isLarge ? 40 : 28 }
    var heart: CGFloat { isLarge ? 560 : 400 }
    var stateTitle: CGFloat { isLarge ? 30 : 24 }
    var line: CGFloat { isLarge ? 20 : 15 }
    var countdown: CGFloat { isLarge ? 32 : 26 }
}

// MARK: Header

/// "‹ Lanes", GINKGO and its line, the microphone and the listening mode.
struct GinkgoScreenHeader: View {
    let model: GinkgoModel
    private let palette = HUDPalette()
    private let text = GinkgoText()
    private let lanesText = LanesText()

    var body: some View {
        HStack(spacing: 20) {
            Button { model.dismissScreen() } label: {
                HStack(spacing: 8) {
                    Text(verbatim: "‹ \(lanesText.back)").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.cyan)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lanesText.back)
            Rectangle().fill(palette.line).frame(width: 1, height: 24).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "GINKGO").font(.system(size: 20, weight: .bold)).tracking(3.2)
                    .accessibilityAddTraits(.isHeader)
                Text(text.subtitle).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 12)
            GinkgoMicrophonePill(microphone: model.microphone)
            if let listen = model.session.listen {
                HStack(spacing: 6) {
                    Text(text.listenLabel).foregroundStyle(palette.textSecondary)
                    Text(text.listen(listen)).fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(palette.bar)
    }
}

/// The microphone, always said: red and filled while open, hollow while closed.
struct GinkgoMicrophonePill: View {
    let microphone: GinkgoMicrophone
    private let palette = HUDPalette()
    private let text = GinkgoText()

    private var open: Bool { microphone != .off }

    private var detail: String {
        switch microphone {
        case .off: text.micOffDetail
        case .conversation: text.micOnDetail
        case .name: text.micNameDetail
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if open {
                    Circle().fill(palette.red)
                } else {
                    Circle().stroke(palette.steel, lineWidth: 1.5)
                }
            }
            .frame(width: 9, height: 9)
            Text(open ? text.micOn : text.micOff).fontWeight(.semibold)
            Text(detail).foregroundStyle(palette.textSecondary)
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(palette.card)
        .overlay(Rectangle().stroke(open ? palette.red : palette.line))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Left column

/// The heart, the state in large, the voice line and the four states.
struct GinkgoStateColumn: View {
    let model: GinkgoModel
    let size: GinkgoScreenSize
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        let state = model.presence == .connected ? model.session.state : .closed
        let words = text.state(state, awaitingYes: model.session.pendingClose != nil)
        VStack(spacing: 14) {
            GinkgoHeart(levels: model.levels, state: state)
                .frame(width: size.heart, height: size.heart)
                .accessibilityElement()
                .accessibilityLabel(Self.sentenceCase(words.title))
                .accessibilityAddTraits(.isImage)
            VStack(spacing: 4) {
                Text(words.title)
                    .font(.system(size: size.stateTitle, weight: .bold))
                    .tracking(size.stateTitle * 0.2)
                    .foregroundStyle(color(of: state))
                Text(words.detail).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            GinkgoVoiceLine(levels: model.levels, flowing: model.isSubscribedToLevels)
                .frame(width: 48 * 6, height: 36)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            GinkgoStatesRow(current: state)
        }
        .frame(maxHeight: .infinity)
    }

    /// "J’ÉCOUTE" read as "J’écoute": capitals are for the eye, not for VoiceOver.
    static func sentenceCase(_ title: String) -> String {
        let lower = title.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    private func color(of state: GinkgoVoiceState) -> Color {
        switch state {
        case .speaking: palette.text
        case .closed, .paused, .nameListening: palette.textSecondary
        case .listening, .thinking, .connecting: palette.cyan
        }
    }
}

/// The four states of the mock-up, the current one raised.
struct GinkgoStatesRow: View {
    let current: GinkgoVoiceState
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        let states: [(GinkgoVoiceState, String, String)] = [
            (.listening, "waveform", text.shortListening),
            (.thinking, "ellipsis.bubble", text.shortThinking),
            (.speaking, "speaker.wave.2", text.shortSpeaking),
            (.closed, "mic.slash", text.shortClosed),
        ]
        HStack(spacing: 8) {
            ForEach(states, id: \.0) { state, symbol, name in
                let isCurrent = state == current
                VStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 18)).accessibilityHidden(true)
                    Text(name).font(.system(size: 12, weight: .bold)).tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 6)
                .foregroundStyle(isCurrent ? palette.text : palette.textSecondary)
                .background(isCurrent ? palette.cardRaised : Color.clear)
                .overlay { if isCurrent { HUDCorners(color: palette.lineBright) } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }
}

// MARK: Right column

/// What stands in the way, in plain words: Ginkgo absent or to update, its refusals and errors.
struct GinkgoMessage: View {
    let model: GinkgoModel
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isProblem ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(isProblem ? palette.amber : palette.cyan)
                    .accessibilityHidden(true)
                Text(message).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardRaised)
            .overlay(Rectangle().stroke(isProblem ? palette.amber : palette.line))
            .accessibilityElement(children: .combine)
        }
    }

    /// The outcome of the last action first, then where Ginkgo stands, then what Ginkgo refused.
    private var message: String? {
        if let notice = model.notice { return text.notice(notice) }
        if let presence = text.presence(model.presence) { return presence }
        if let problem = model.session.problem { return text.problem(problem) }
        return nil
    }

    /// Ginkgo absent or starting is only information; everything else stops the person.
    private var isProblem: Bool {
        if model.notice != nil { return true }
        switch model.presence {
        case .absent, .starting, .unknown: return false
        case .connected: return model.session.problem != nil
        case .updateNeeded, .unknownVersion, .keyMissing, .refused, .labFailed: return true
        }
    }
}

/// The open conversation, written as it is said; a partial line ends with a fixed cursor.
struct GinkgoConversationCard: View {
    let session: GinkgoSession
    /// Less motion asked by the Mac: whole lines only, no line written as it is said (§6).
    let wholeOnly: Bool
    let size: GinkgoScreenSize
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        let lines = session.shownLines(wholeOnly: wholeOnly)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(text.conversationTitle).font(.system(size: 12, weight: .bold)).tracking(1.9).foregroundStyle(palette.cyan)
                    .accessibilityAddTraits(.isHeader)
                Text(text.conversationDetail).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            if lines.isEmpty {
                Text(text.conversationEmpty).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            } else {
                // A plain stack (at most `GinkgoSession.maxLines`) has exact heights, so the bottom
                // anchor shows the latest line; at least as tall as the card and aligned to its top,
                // a short conversation starts at the top instead of sinking to the bottom.
                GeometryReader { viewport in
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(lines, id: \.id) { line in
                                    GinkgoLineRow(line: line, size: size).id(line.id)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                        }
                        .defaultScrollAnchor(.bottom)
                        // What Ginkgo did, the lane and the close often arrive after the lines and
                        // take the card's height. AppKit then keeps the top in place, and a scroll
                        // asked without new lines still measures the old height and does nothing:
                        // a new height makes a new scroll view, which starts at its bottom anchor.
                        .id(viewport.size.height)
                        .onChange(of: lines.last) { _, last in
                            if let last { reader.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.card)
        .overlay(HUDCorners(color: palette.lineBright, length: 10))
    }
}

/// One line: who, when, what.
struct GinkgoLineRow: View {
    let line: GinkgoLine
    let size: GinkgoScreenSize
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.who == .ginkgo ? "GINKGO" : text.you)
                    .font(.system(size: 11, weight: .bold)).tracking(1.8)
                    .foregroundStyle(line.who == .ginkgo ? palette.cyan : palette.textSecondary)
                if let at = line.at {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
            (Text(line.text) + Text(verbatim: line.final ? "" : "▍").foregroundColor(palette.cyan))
                .font(.system(size: size.line))
                .lineSpacing(size.line * 0.3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What Ginkgo did, the lane it talks about, a close waiting for its "yes" and how it ended.
struct GinkgoActivity: View {
    let model: GinkgoModel
    let size: GinkgoScreenSize
    let onShowRequest: (GinkgoAbout) -> Void
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        let session = model.session
        VStack(alignment: .leading, spacing: 8) {
            Text(text.didTitle).font(.system(size: 12, weight: .bold)).tracking(1.9)
                .accessibilityAddTraits(.isHeader)
            if session.did.isEmpty {
                Text(text.didEmpty).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            }
            ForEach(Array(session.did.suffix(size.isLarge ? 4 : 2).enumerated()), id: \.offset) { _, did in
                GinkgoDidRow(did: did)
            }
            if let about = session.about {
                GinkgoAboutCard(about: about) { onShowRequest(about) }
            }
            if let close = session.pendingClose {
                GinkgoConfirmCard(close: close, size: size) { model.cancelClose() }
            } else if let outcome = session.lastCloseOutcome {
                Text(text.outcome(outcome)).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

/// One thing Ginkgo did.
struct GinkgoDidRow: View {
    let did: GinkgoDid
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").foregroundStyle(palette.cyan).accessibilityHidden(true)
            Text(text.did(did.kind)).fontWeight(.semibold)
            Text(verbatim: did.lane.map { "\(did.project) › \($0)" } ?? did.project).fontWeight(.semibold)
            Text(did.text).foregroundStyle(palette.textSecondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if let at = did.at {
                Text(at, format: .dateTime.hour().minute())
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(palette.bar)
        .overlay(Rectangle().stroke(palette.line))
        .accessibilityElement(children: .combine)
    }
}

/// The lane Ginkgo talks about, with a way to its request in the Feed.
struct GinkgoAboutCard: View {
    let about: GinkgoAbout
    let onShow: () -> Void
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.aboutTitle).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(palette.cyan)
                Text(verbatim: "\(about.project.value) › \(about.lane.value)").font(.system(size: 14, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: onShow) {
                Text(text.aboutOpen).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.cyan)
                    .padding(.horizontal, 12).frame(height: 30)
                    .overlay(Rectangle().stroke(palette.lineBright))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(palette.card)
        .overlay(Rectangle().stroke(palette.line))
    }
}

/// A lane close waiting for the spoken "yes", with the time left and "Cancel".
struct GinkgoConfirmCard: View {
    let close: GinkgoPendingClose
    let size: GinkgoScreenSize
    let onCancel: () -> Void
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.bubble").font(.system(size: 20)).foregroundStyle(palette.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.confirmTitle).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(palette.amber)
                Text(text.confirmWhat("\(close.project) › \(close.lane)")).font(.system(size: 13, weight: .semibold))
                Text(text.confirmDetail).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            // The system draws the countdown: Treelab keeps no timer of its own.
            let now = Date()
            Text(timerInterval: now...max(now, close.until), countsDown: true)
                .font(.system(size: size.countdown, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.amber)
                .fixedSize()
                .accessibilityLabel(text.timeLeft)
            Button(action: onCancel) {
                Text(text.cancel).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 34)
                    .overlay(Rectangle().stroke(palette.lineBright))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(palette.cardRaised)
        .overlay(HUDCorners(color: palette.amber, length: 14))
    }
}

/// "Close the microphone" (Escape) or "Talk", "Keep Ginkgo active" and the help.
struct GinkgoScreenFooter: View {
    let model: GinkgoModel
    private let palette = HUDPalette()
    private let text = GinkgoText()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { model.keepActive }, set: { model.setKeepActive($0) })) {
                    Text(text.keepActive).font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(palette.cyan)
                // The switch itself carries its name: VoiceOver otherwise reads a bare "0".
                .accessibilityLabel(text.keepActive)
                Text(model.keepActive ? text.keepActiveOn : text.keepActiveOff)
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                if model.isConversationOpen {
                    Button { model.closeMicrophone() } label: {
                        HStack(spacing: 10) {
                            KeyCap("esc")
                            Text(text.closeMicrophone)
                        }
                        .modifier(GinkgoMainButton())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { model.talk() } label: {
                        Text(text.talk).modifier(GinkgoMainButton())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.presence == .starting)
                }
                Text(text.help).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The look of "Close the microphone" and "Talk".
struct GinkgoMainButton: ViewModifier {
    private let palette = HUDPalette()

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(palette.cyan)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(palette.buttonFill)
            .overlay(Rectangle().stroke(palette.cyan))
            .contentShape(Rectangle())
            .fixedSize()
    }
}
