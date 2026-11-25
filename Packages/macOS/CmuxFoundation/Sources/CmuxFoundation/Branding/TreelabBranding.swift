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
    /// The folder name under `~/Library/Application Support` (Treelab uses its bundle identifier,
    /// the folder upstream already uses for bundle-scoped stores).
    public let applicationSupportDirectoryName: String
    /// The prefix of the socket files and of the `/tmp` marker (`<prefix>.sock`).
    public let socketPrefix: String
    /// The URL scheme the app registers (`<scheme>://`).
    public let urlScheme: String
    /// Managed-device policy keys this brand forces in code, as if a configuration profile set
    /// them to `true` (the raw values of `ManagedDevicePolicyKey` in CmuxSettings).
    ///
    /// Treelab cuts every Manaflow service and measurement tool this way: Cloud, remote control,
    /// Iroh relays, device discovery and incoming device access, telemetry (PostHog, Sentry and
    /// the remote feature flags), automatic updates and AI credential upload. SSH and Mosh stay
    /// (`DisableRemoteConnections` is not forced). Upstream cmux forces nothing.
    public let forcedManagedPolicyKeys: Set<String>
    /// Whether the app offers Manaflow's services in its interface: account and sign-in,
    /// the Pro offer, feedback, update checks, and the Settings sections for mobile, Cloud,
    /// devices and networking. Treelab hides those entries (their code stays).
    public let offersManaflowServices: Bool
    /// The accent of the app's own chrome (`#RRGGBB` for light and dark appearances), drawn in the
    /// default accent mode. `nil` keeps upstream's cmux blue.
    public let accentHex: AppearancePair?
    /// The terminal themes applied when the user has set no theme and no terminal color (the
    /// light theme in a light appearance, the dark one otherwise). `nil` keeps upstream's.
    public let defaultTerminalThemeNames: AppearancePair?
    /// Whether the About panel credits upstream cmux by Manaflow under the GPL.
    public let creditsUpstream: Bool
    private let helpSite: HelpSite

    private enum HelpSite: Equatable, Sendable { case cmux, treelab }

    /// A value for the light appearance and one for the dark appearance.
    public struct AppearancePair: Equatable, Sendable {
        public let light: String
        public let dark: String

        public init(light: String, dark: String) {
            self.light = light
            self.dark = dark
        }

        /// The value for a light (`false`) or dark (`true`) appearance.
        public func value(isDark: Bool) -> String { isDark ? dark : light }
    }

    /// Where the Help menus and the About panel send the user.
    public struct HelpLinks: Equatable, Sendable {
        /// The user guide.
        public let docs: URL
        /// What changed in each release.
        public let changelog: URL
        /// Where to ask for help or report a problem.
        public let support: URL
        /// The source repository.
        public let source: URL
        /// The community chat, or `nil` when the brand has none (its menu entry is hidden).
        public let community: URL?

        /// The source repository's page for one commit.
        public func commit(_ hash: String) -> URL? {
            URL(string: "\(source.absoluteString)/commit/\(hash)")
        }
    }

    /// The help links for the app's display language (`fr`, `en`, `ja`, `pt-BR`…; `nil` = English).
    public func helpLinks(languageCode: String?) -> HelpLinks {
        switch helpSite {
        case .cmux: return Self.cmuxHelpLinks
        case .treelab: return Self.treelabHelpLinks(languageCode: languageCode)
        }
    }

    /// The help links for the language the app is displayed in.
    public var helpLinks: HelpLinks {
        helpLinks(languageCode: Bundle.main.preferredLocalizations.first)
    }

    private static let cmuxHelpLinks = HelpLinks(
        docs: URL(string: "https://cmux.com/docs")!,
        changelog: URL(string: "https://cmux.com/docs/changelog")!,
        support: URL(string: "https://github.com/manaflow-ai/cmux/issues")!,
        source: URL(string: "https://github.com/manaflow-ai/cmux")!,
        community: URL(string: "https://discord.gg/xsgFEVrWCZ")!
    )

    /// treelab.sh in French or English (the site's two languages); its release notes exist in
    /// English only. Source on GitHub, no community chat.
    private static func treelabHelpLinks(languageCode: String?) -> HelpLinks {
        let site = (languageCode?.lowercased().hasPrefix("fr") ?? false) ? "fr" : "en"
        return HelpLinks(
            docs: URL(string: "https://treelab.sh/\(site)/guide/")!,
            changelog: URL(string: "https://treelab.sh/en/whats-new/")!,
            support: URL(string: "https://treelab.sh/\(site)/support/")!,
            source: URL(string: "https://github.com/craftwith-ai/treelab-app")!,
            community: nil
        )
    }

    /// Upstream cmux, values unchanged.
    public static let cmux = AppBranding(
        displayName: "cmux",
        bundleIdentifier: "com.cmuxterm.app",
        directoryName: "cmux",
        applicationSupportDirectoryName: "cmux",
        socketPrefix: "cmux",
        urlScheme: "cmux",
        forcedManagedPolicyKeys: [],
        offersManaflowServices: true,
        accentHex: nil,
        defaultTerminalThemeNames: nil,
        creditsUpstream: false,
        helpSite: .cmux
    )

    /// The Treelab fork.
    public static let treelab = AppBranding(
        displayName: "Treelab",
        bundleIdentifier: "sh.treelab.app",
        directoryName: "treelab",
        applicationSupportDirectoryName: "sh.treelab.app",
        socketPrefix: "treelab",
        urlScheme: "treelab",
        forcedManagedPolicyKeys: [
            "DisableCloud",
            "DisableRemoteControl",
            "DisableIrohNetworking",
            "DisableDeviceDiscovery",
            "DisableIncomingDeviceAccess",
            "DisableTelemetry",
            "DisableAutoUpdate",
            "DisableAICredentialUpload",
        ],
        offersManaflowServices: false,
        // treelab.sh's green on dark; a darker green reads on light chrome (6.35:1 on white).
        accentHex: AppearancePair(light: "#3D6B0F", dark: "#B6F27A"),
        // Shipped in Contents/Resources/ghostty/themes by scripts/treelab/build.sh.
        defaultTerminalThemeNames: AppearancePair(light: "Treelab Light", dark: "Treelab"),
        creditsUpstream: true,
        helpSite: .treelab
    )

    /// The About panel's line crediting upstream cmux by Manaflow under the GPL, in the app's
    /// language (`Treelab.xcstrings`), or `nil` when the brand does not credit upstream.
    public var upstreamCreditLine: String? {
        guard creditsUpstream else { return nil }
        let english = "Based on cmux by Manaflow — GPL-3.0-or-later"
        guard let bundle = CmuxFoundationLocalization.bundle else { return english }
        return String(
            localized: "treelab.about.upstreamCredit",
            defaultValue: String.LocalizationValue(stringLiteral: english),
            table: "Treelab",
            bundle: bundle
        )
    }

    /// The title of the Help entry that leads to ``HelpLinks/support``, in the app's language,
    /// or `nil` to keep upstream's "GitHub Issues" (its support link is the issue tracker).
    public var supportMenuTitle: String? {
        guard helpSite == .treelab else { return nil }
        guard let bundle = CmuxFoundationLocalization.bundle else { return "Support" }
        return String(localized: "treelab.help.support", defaultValue: "Support", table: "Treelab", bundle: bundle)
    }

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

    /// The identifier of the outermost `.app` bundle that contains `executableURL`.
    ///
    /// Outermost, so a helper app nested in Treelab (`Contents/Library/*.app`) shares its brand.
    public static func enclosingAppBundleIdentifier(executableURL: URL?) -> String? {
        guard var url = executableURL?.resolvingSymlinksInPath() else { return nil }
        var outermost: String?
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app", let identifier = Bundle(url: url)?.bundleIdentifier {
                outermost = identifier
            }
        }
        return outermost
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
