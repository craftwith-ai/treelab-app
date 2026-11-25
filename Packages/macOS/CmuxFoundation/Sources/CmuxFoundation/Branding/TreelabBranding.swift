public import Darwin
public import Foundation

/// The names and per-user locations that tell the Treelab fork apart from upstream cmux.
///
/// Treelab is built from this repository with the bundle identifier `sh.treelab.app` and
/// runs beside the user's own cmux. The helpers that derive the control socket, its marker
/// files and the state folders read these values, so the two apps never share runtime state.
///
/// Upstream identifiers (`com.cmuxterm.app` and its `com.cmuxterm.app.*` variants) keep the
/// upstream values unchanged. Every other identifier, an unknown one included, resolves to
/// Treelab: a build of this fork never falls back to cmux's stable socket.
public struct AppBranding: Equatable, Sendable {
    /// The name shown in the Dock, the menus and the About panel.
    public let displayName: String
    /// The stable bundle identifier of this brand.
    public let bundleIdentifier: String
    /// The folder name under `~/.local/state` and `~/.config`.
    public let directoryName: String
    /// The folder name under `~/Library/Application Support`.
    public let applicationSupportDirectoryName: String
    /// The prefix of the socket files and of the `/tmp` marker (`<prefix>.sock`).
    public let socketPrefix: String
    /// The URL scheme the app registers (`<scheme>://`).
    public let urlScheme: String

    /// Upstream cmux, values unchanged.
    public static let cmux = AppBranding(
        displayName: "cmux",
        bundleIdentifier: "com.cmuxterm.app",
        directoryName: "cmux",
        applicationSupportDirectoryName: "cmux",
        socketPrefix: "cmux",
        urlScheme: "cmux"
    )

    /// The Treelab fork.
    public static let treelab = AppBranding(
        displayName: "Treelab",
        bundleIdentifier: "sh.treelab.app",
        directoryName: "treelab",
        applicationSupportDirectoryName: "Treelab",
        socketPrefix: "treelab",
        urlScheme: "treelab"
    )

    /// The stable socket file name inside ``stateDirectory(homeDirectory:)``.
    public var socketFileName: String { "\(socketPrefix).sock" }

    /// The per-user stable socket file name, used when the shared one is taken.
    public func userScopedSocketFileName(currentUserID: uid_t) -> String {
        "\(socketPrefix)-\(currentUserID).sock"
    }

    /// The legacy stable socket path under `/tmp`.
    public var legacyTmpSocketPath: String { "/tmp/\(socketPrefix).sock" }

    /// The legacy per-user stable socket path under `/tmp`.
    public func legacyUserScopedTmpSocketPath(currentUserID: uid_t) -> String {
        "/tmp/\(userScopedSocketFileName(currentUserID: currentUserID))"
    }

    /// The `/tmp` marker that records the stable build's last socket path.
    public var tmpMarkerPath: String { "/tmp/\(socketPrefix)-last-socket-path" }

    /// The control-plane state folder: `<home>/.local/state/<directoryName>`.
    public func stateDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// The user configuration folder: `<home>/.config/<directoryName>`.
    public func configDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// The Application Support folder of this brand inside `applicationSupport`.
    public func applicationSupportDirectory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }

    /// Puts this brand's name in a translated string that names the upstream app.
    ///
    /// Menus and dialogs keep their translations (`"À propos de cmux"`) and show this
    /// brand's name (`"À propos de Treelab"`). Upstream cmux gets the text unchanged.
    public func rebranded(_ text: String) -> String {
        self == .cmux ? text : text.replacingOccurrences(of: Self.cmux.displayName, with: displayName)
    }

    /// Whether `bundleIdentifier` is upstream cmux or one of its variants.
    public static func isUpstreamIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let identifier = normalized(bundleIdentifier) else { return false }
        return identifier == cmux.bundleIdentifier || identifier.hasPrefix(cmux.bundleIdentifier + ".")
    }

    /// Whether `bundleIdentifier` is Treelab or one of its variants.
    public static func isTreelabIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let identifier = normalized(bundleIdentifier) else { return false }
        return identifier == treelab.bundleIdentifier || identifier.hasPrefix(treelab.bundleIdentifier + ".")
    }

    /// The brand of a bundle identifier: cmux for upstream identifiers, Treelab otherwise.
    ///
    /// - Parameter bundleIdentifier: Any bundle identifier, or `nil`.
    /// - Returns: ``cmux`` for `com.cmuxterm.app` and its variants, ``treelab`` for anything else.
    public static func resolve(bundleIdentifier: String?) -> AppBranding {
        isUpstreamIdentifier(bundleIdentifier) ? .cmux : .treelab
    }

    /// The brand of the running process.
    ///
    /// Treelab when the process belongs to a Treelab bundle (its own app, or the app that
    /// contains this executable, like the bundled CLI) or has no bundle identity at all.
    /// Upstream cmux otherwise, which keeps upstream values for cmux builds and test hosts.
    public static let current: AppBranding = processBranding(
        mainBundleIdentifier: Bundle.main.bundleIdentifier,
        enclosingAppBundleIdentifier: enclosingAppBundleIdentifier(executableURL: Bundle.main.executableURL)
    )

    /// Decides the process brand from its identities (pure, for tests).
    ///
    /// - Parameters:
    ///   - mainBundleIdentifier: `Bundle.main.bundleIdentifier`.
    ///   - enclosingAppBundleIdentifier: The identifier of the `.app` that contains the executable.
    /// - Returns: The process brand.
    public static func processBranding(
        mainBundleIdentifier: String?,
        enclosingAppBundleIdentifier: String?
    ) -> AppBranding {
        let identities = [enclosingAppBundleIdentifier, mainBundleIdentifier].compactMap(normalized)
        if identities.isEmpty || identities.contains(where: isTreelabIdentifier) {
            return .treelab
        }
        return .cmux
    }

    /// The identifier of the nearest `.app` bundle that contains `executableURL`.
    public static func enclosingAppBundleIdentifier(executableURL: URL?) -> String? {
        guard var url = executableURL?.resolvingSymlinksInPath() else { return nil }
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app", let identifier = Bundle(url: url)?.bundleIdentifier {
                return identifier
            }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
