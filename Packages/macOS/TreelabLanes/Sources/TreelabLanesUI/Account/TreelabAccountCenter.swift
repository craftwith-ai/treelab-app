public import AppKit
public import Foundation
public import Observation
public import TreelabAccount
import SwiftUI
import UserNotifications

/// The three sections of Treelab's settings window.
public enum TreelabSettingsSection: String, Sendable, CaseIterable, Identifiable {
    /// Account and subscription.
    case account
    /// Privacy and security.
    case privacy
    /// Appearance.
    case appearance

    public var id: String { rawValue }
}

/// Where the notifications stand for Treelab.
public enum NotificationPermissionState: Sendable, Equatable {
    /// Not known yet.
    case unknown
    /// macOS has not asked yet.
    case notAsked
    /// Allowed.
    case allowed
    /// Declined: only System Settings can allow them now.
    case denied
}

/// Asks macOS whether Treelab may send notifications; the seam the demo replaces.
@MainActor
public protocol NotificationPermissionAsking: AnyObject {
    /// The state now.
    func current() async -> NotificationPermissionState
    /// Asks the person (macOS shows its own dialog the first time).
    func request() async -> NotificationPermissionState
}

/// The system's notification permission.
@MainActor
final class SystemNotificationPermission: NotificationPermissionAsking {
    func current() async -> NotificationPermissionState {
        await Self.readState()
    }

    func request() async -> NotificationPermissionState {
        await Self.ask() ? .allowed : await Self.readState()
    }

    // Outside the main actor: the system calls these handlers on its own queue.
    nonisolated private static func readState() async -> NotificationPermissionState {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let state: NotificationPermissionState = switch settings.authorizationStatus {
                case .notDetermined: .notAsked
                case .denied: .denied
                case .authorized, .provisional, .ephemeral: .allowed
                @unknown default: .unknown
                }
                continuation.resume(returning: state)
            }
        }
    }

    nonisolated private static func ask() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// The demo's notification permission: never asks macOS. `notifications` in the demo folder
/// says `allowed`, `denied` or `notAsked` (the default); asking answers "allowed".
@MainActor
final class DemoNotificationPermission: NotificationPermissionAsking {
    private var state: NotificationPermissionState

    init(folder: URL) {
        let text = (try? String(contentsOf: folder.appendingPathComponent("notifications"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        state = switch text {
        case "allowed": .allowed
        case "denied": .denied
        default: .notAsked
        }
    }

    func current() async -> NotificationPermissionState { state }

    func request() async -> NotificationPermissionState {
        if state == .notAsked { state = .allowed }
        return state
    }
}

/// What the person sees of a window: the section shown, the welcome's step.
@MainActor
@Observable
final class AccountWindowsState {
    var section: TreelabSettingsSection = .account
    var welcomeStep = 1
}

/// The demo's launch arguments, read only from this launch's own arguments (never from saved
/// preferences): `-TreelabAccountDemo <folder>` (the demo lab, ``DemoAccountLab``),
/// `-TreelabAccountDemoScreen welcome-1…4|account|privacy|appearance` and
/// `-TreelabAccountDemoSize <width>x<height>`.
struct AccountDemoLaunch: Equatable {
    let folder: URL
    let screen: String?
    let size: CGSize?

    init?(arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let path = value("-TreelabAccountDemo"), path.hasPrefix("/") else { return nil }
        folder = URL(fileURLWithPath: path)
        screen = value("-TreelabAccountDemoScreen")
        size = value("-TreelabAccountDemoSize").flatMap { text in
            let parts = text.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 && parts.allSatisfy({ (400...4000).contains($0) }) ? CGSize(width: parts[0], height: parts[1]) : nil
        }
    }
}

/// Whether the welcome opens by itself: at the first launch only, once.
struct WelcomeGate {
    let defaults: UserDefaults

    /// Says whether this launch is the first one, and remembers that it happened.
    /// - Parameter allowed: `false` when another demo runs: nothing is shown nor remembered.
    /// - Returns: `true` the first time only.
    func takeFirstLaunch(allowed: Bool) -> Bool {
        guard allowed, !defaults.bool(forKey: TreelabAccountCenter.welcomeSeenKey) else { return false }
        defaults.set(true, forKey: TreelabAccountCenter.welcomeSeenKey)
        return true
    }
}

/// The account's model and Treelab's two windows of its own: the welcome (first launch only,
/// reopened from the Help menu) and "Account and settings" (opened by the account entry at the
/// bottom of the sidebar).
///
/// ```swift
/// let account = TreelabAccountCenter.make(home: home)
/// account.start(showsWelcomeOnFirstLaunch: true)
/// ```
@MainActor
public final class TreelabAccountCenter {
    /// The account, read from lab.
    public let model: AccountModel
    /// The preference that says the welcome was shown once.
    nonisolated public static let welcomeSeenKey = "TreelabWelcomeSeen"

    private let notifications: any NotificationPermissionAsking
    private let defaults: UserDefaults
    private let demo: AccountDemoLaunch?
    private let state = AccountWindowsState()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var started = false

    init(model: AccountModel, notifications: any NotificationPermissionAsking, defaults: UserDefaults, demo: AccountDemoLaunch?) {
        self.model = model
        self.notifications = notifications
        self.defaults = defaults
        self.demo = demo
    }

    /// The center wired to the person's lab, or to the demo folder when this launch's arguments
    /// name one (`-TreelabAccountDemo <folder>`, which runs no program and keeps its own preferences).
    /// - Parameters:
    ///   - arguments: this launch's arguments.
    ///   - home: the person's home folder.
    /// - Returns: a center, not started.
    public static func make(arguments: [String] = CommandLine.arguments, home: URL) -> TreelabAccountCenter {
        if let demo = AccountDemoLaunch(arguments: arguments) {
            return TreelabAccountCenter(
                model: .demo(folder: demo.folder),
                notifications: DemoNotificationPermission(folder: demo.folder),
                defaults: UserDefaults(suiteName: "sh.treelab.account.demo") ?? .standard,
                demo: demo
            )
        }
        return TreelabAccountCenter(model: .live(home: home), notifications: SystemNotificationPermission(), defaults: .standard, demo: nil)
    }

    /// The Help menu entry that reopens the welcome.
    public static var welcomeMenuTitle: String { AccountText().welcomeMenu }

    /// Starts reading the account; shows the welcome the first time Treelab opens (or the demo's
    /// screen). Calling it again does nothing.
    /// - Parameter showsWelcomeOnFirstLaunch: `false` keeps the welcome closed (another demo runs).
    public func start(showsWelcomeOnFirstLaunch: Bool) {
        guard !started else { return }
        started = true
        model.start()
        // A demo on a named screen shows it; a demo without one launches like Treelab, in its own preferences.
        if let demo, demo.screen != nil {
            Task { @MainActor in self.openDemoScreen(demo) }
            return
        }
        guard WelcomeGate(defaults: defaults).takeFirstLaunch(allowed: showsWelcomeOnFirstLaunch) else { return }
        // After the launch's own windows, so the welcome comes in front of them.
        Task { @MainActor in self.showWelcome() }
    }

    /// Shows the settings window on `section`.
    /// - Parameter section: the section to show.
    public func showSettings(_ section: TreelabSettingsSection = .account) {
        state.section = section
        let window = settingsWindow ?? makeWindow(
            title: AccountText().settingsWindow,
            size: CGSize(width: 1100, height: 740),
            minimum: CGSize(width: 860, height: 560),
            identifier: "TreelabAccountSettings",
            content: TreelabSettingsView(model: model, state: state, close: { [weak self] in self?.settingsWindow?.performClose(nil) })
        )
        settingsWindow = window
        Task { await model.refresh() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows the welcome on `step` (1 to 4).
    /// - Parameter step: the step to show.
    public func showWelcome(step: Int = 1) {
        state.welcomeStep = min(max(step, 1), TreelabWelcomeView.stepCount)
        let window = welcomeWindow ?? makeWindow(
            title: AccountText().welcomeMenu,
            size: CGSize(width: 1180, height: 760),
            minimum: CGSize(width: 900, height: 600),
            identifier: "TreelabWelcome",
            content: TreelabWelcomeView(
                model: model,
                state: state,
                notifications: notifications,
                finish: { [weak self] in self?.welcomeWindow?.performClose(nil) },
                openPrivacy: { [weak self] in self?.showSettings(.privacy) }
            )
        )
        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func openDemoScreen(_ demo: AccountDemoLaunch) {
        guard let screen = demo.screen else { return }
        if screen.hasPrefix("welcome") {
            showWelcome(step: Int(screen.split(separator: "-").last ?? "1") ?? 1)
            resize(welcomeWindow, to: demo.size)
        } else if let section = TreelabSettingsSection(rawValue: screen) {
            showSettings(section)
            resize(settingsWindow, to: demo.size)
        }
    }

    private func resize(_ window: NSWindow?, to size: CGSize?) {
        guard let window, let size else { return }
        window.setContentSize(size)
        window.center()
    }

    private func makeWindow(title: String, size: CGSize, minimum: CGSize, identifier: String, content: some View) -> NSWindow {
        let visible = NSScreen.main?.visibleFrame.size ?? size
        let fitted = CGSize(width: min(size.width, visible.width - 40), height: min(size.height, visible.height - 40))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: fitted),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x03 / 255, green: 0x08 / 255, blue: 0x0E / 255, alpha: 1)
        window.contentMinSize = minimum
        window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        window.center()
        return window
    }
}
