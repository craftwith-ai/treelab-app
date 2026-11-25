import CmuxFoundation
import Foundation
import Testing

@testable import CmuxSettings

/// Treelab (`sh.treelab.app`) runs beside the user's cmux, so it must never reach cmux's
/// socket, markers or folders; cmux identifiers keep their upstream values.
@Suite struct TreelabBrandingTests {
    private let home = URL(fileURLWithPath: "/Users/test-user", isDirectory: true)
    private let accountHome = FileManager.default.homeDirectoryForCurrentUser

    private var cmuxStableSocket: String {
        CmuxStateDirectory.url(homeDirectory: accountHome)
            .appendingPathComponent("cmux.sock", isDirectory: false).path
    }

    private func defaultSocket(_ bundleIdentifier: String?) -> String {
        SocketControlSettings.defaultSocketPath(
            bundleIdentifier: bundleIdentifier,
            environment: [:],
            isDebugBuild: false,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
    }

    // MARK: - Treelab gets its own socket, markers and folders

    @Test func treelabStableSocketLivesInItsOwnStateDirectory() {
        let socket = defaultSocket("sh.treelab.app")

        #expect(socket == accountHome.path + "/.local/state/treelab/treelab.sock")
        #expect(socket != cmuxStableSocket)
        #expect(!socket.contains("/cmux"))
    }

    @Test func treelabMarkerFilesNeverNameCmuxMarkers() {
        let directory = AppBranding.treelab.stateDirectory(homeDirectory: home)
        let paths = SocketPathMarkerFiles.paths(
            bundleIdentifier: "sh.treelab.app",
            environment: [:],
            directory: directory
        )

        #expect(paths == [
            "/Users/test-user/.local/state/treelab/last-socket-path",
            "/tmp/treelab-last-socket-path",
        ])
    }

    @Test func treelabFoldersDifferFromCmuxFolders() {
        let support = URL(fileURLWithPath: "/Users/test-user/Library/Application Support", isDirectory: true)

        #expect(AppBranding.treelab.stateDirectory(homeDirectory: home).path
            == "/Users/test-user/.local/state/treelab")
        #expect(AppBranding.treelab.configDirectory(homeDirectory: home).path
            == "/Users/test-user/.config/treelab")
        #expect(AppBranding.treelab.applicationSupportDirectory(in: support).path
            == "/Users/test-user/Library/Application Support/Treelab")
        #expect(AppBranding.treelab.stateDirectory(homeDirectory: home)
            != AppBranding.cmux.stateDirectory(homeDirectory: home))
        #expect(AppBranding.treelab.applicationSupportDirectory(in: support)
            != AppBranding.cmux.applicationSupportDirectory(in: support))
    }

    @Test func treelabIgnoresAnInheritedCmuxSocketOverride() {
        let path = SocketControlSettings.socketPath(
            environment: [
                "CMUX_SOCKET_PATH": cmuxStableSocket,
                "CMUX_BUNDLE_ID": "com.cmuxterm.app",
            ],
            bundleIdentifier: "sh.treelab.app",
            isDebugBuild: false,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )

        #expect(path == accountHome.path + "/.local/state/treelab/treelab.sock")
    }

    // MARK: - Unknown identifiers fail closed

    @Test func unknownIdentifierNeverGetsCmuxStableSocket() {
        for identifier in ["org.example.unknown", "sh.treelab.app.beta", ""] {
            let socket = defaultSocket(identifier)
            #expect(socket != cmuxStableSocket, "identifier \(identifier)")
            #expect(!socket.contains("/cmux"), "identifier \(identifier)")
        }
    }

    @Test func brandResolutionFailsClosedToTreelab() {
        #expect(AppBranding.resolve(bundleIdentifier: "com.cmuxterm.app") == .cmux)
        #expect(AppBranding.resolve(bundleIdentifier: "com.cmuxterm.app.nightly") == .cmux)
        #expect(AppBranding.resolve(bundleIdentifier: "com.cmuxterm.app.debug.my-tag") == .cmux)
        #expect(AppBranding.resolve(bundleIdentifier: "sh.treelab.app") == .treelab)
        #expect(AppBranding.resolve(bundleIdentifier: "org.example.unknown") == .treelab)
        #expect(AppBranding.resolve(bundleIdentifier: nil) == .treelab)
        #expect(AppBranding.resolve(bundleIdentifier: "com.cmuxterm.apple") == .treelab)
    }

    @Test func processBrandIsTreelabForTheAppItsCLIAndAnAnonymousBinary() {
        #expect(AppBranding.processBranding(
            mainBundleIdentifier: "sh.treelab.app",
            enclosingAppBundleIdentifier: "sh.treelab.app"
        ) == .treelab)
        // The bundled CLI: its own identity differs, the enclosing app is Treelab.
        #expect(AppBranding.processBranding(
            mainBundleIdentifier: nil,
            enclosingAppBundleIdentifier: "sh.treelab.app"
        ) == .treelab)
        // A binary copied out of any bundle has no identity: never cmux.
        #expect(AppBranding.processBranding(
            mainBundleIdentifier: nil,
            enclosingAppBundleIdentifier: nil
        ) == .treelab)
        #expect(AppBranding.processBranding(
            mainBundleIdentifier: "com.cmuxterm.app",
            enclosingAppBundleIdentifier: "com.cmuxterm.app"
        ) == .cmux)
        // A test host keeps upstream values.
        #expect(AppBranding.processBranding(
            mainBundleIdentifier: "com.apple.dt.xctest.tool",
            enclosingAppBundleIdentifier: "com.apple.dt.Xcode"
        ) == .cmux)
    }

    // MARK: - cmux keeps its upstream values

    @Test func cmuxIdentifiersKeepUpstreamValues() {
        #expect(AppBranding.current == .cmux)
        #expect(CmuxStateDirectory.url(homeDirectory: home).path == "/Users/test-user/.local/state/cmux")
        #expect(defaultSocket("com.cmuxterm.app") == cmuxStableSocket)
        #expect(defaultSocket("com.cmuxterm.app.nightly") == "/tmp/cmux-nightly.sock")
        #expect(defaultSocket("com.cmuxterm.app.staging.my-tag") == "/tmp/cmux-staging-my-tag.sock")
        #expect(SocketControlSettings.legacyStableDefaultSocketPath == "/tmp/cmux.sock")
        #expect(SocketPathMarkerFiles.paths(
            bundleIdentifier: "com.cmuxterm.app",
            environment: [:],
            directory: CmuxStateDirectory.url(homeDirectory: home)
        ) == [
            "/Users/test-user/.local/state/cmux/last-socket-path",
            "/tmp/cmux-last-socket-path",
        ])
        #expect(SocketControlSettings.userScopedStableSocketPath(currentUserID: 501)
            == CmuxStateDirectory.url(homeDirectory: accountHome).path + "/cmux-501.sock")
    }

    // MARK: - Names and folders read from the brand

    @Test func treelabRebrandsTranslatedNamesAndCmuxKeepsThem() {
        #expect(AppBranding.treelab.rebranded("À propos de cmux") == "À propos de Treelab")
        #expect(AppBranding.treelab.rebranded("Quitter cmux ?") == "Quitter Treelab ?")
        #expect(AppBranding.cmux.rebranded("Quit cmux") == "Quit cmux")
    }

    @Test func stateDirectoryAndConfigFollowTheGivenBrand() {
        #expect(CmuxStateDirectory.url(homeDirectory: home, branding: .treelab).path
            == "/Users/test-user/.local/state/treelab")
        #expect(CmuxStateDirectory.url(homeDirectory: home, branding: .cmux).path
            == "/Users/test-user/.local/state/cmux")
        #expect(CmuxConfigLocation(home: home, branding: .treelab).userConfigFile.path
            == "/Users/test-user/.config/treelab/cmux.json")
        #expect(CmuxConfigLocation(home: home).userConfigFile.path
            == "/Users/test-user/.config/cmux/cmux.json")
    }
}
