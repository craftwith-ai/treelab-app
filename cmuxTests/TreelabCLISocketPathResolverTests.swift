import CmuxSettings
import Darwin
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The CLI bundled in Treelab must reach Treelab's socket and never the user's cmux,
/// while the CLI bundled in cmux keeps reaching cmux.
@Suite struct TreelabCLISocketPathResolverTests {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("treelab-cli-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func resolveImplicitly(bundleIdentifier: String, stateDirectory: URL) -> CLISocketPathResolution {
        let resolver = CLISocketPathResolver(
            environment: [:],
            bundleIdentifier: bundleIdentifier,
            currentUserID: getuid(),
            inspectSocketPathEntry: { _ in .socket(ownerUserID: getuid()) },
            socketAcceptsConnections: { _ in true },
            stateDirectory: stateDirectory
        )
        return resolver.resolve(
            requestedPath: CLISocketPathResolver.defaultSocketPath(
                bundleIdentifier: bundleIdentifier,
                environment: [:]
            ),
            source: .implicitDefault
        )
    }

    @Test func treelabCLITargetsTreelabSocketAndNeverCmux() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let stateDirectory = AppBranding.treelab.stateDirectory(homeDirectory: home)

        let resolution = resolveImplicitly(bundleIdentifier: "sh.treelab.app", stateDirectory: stateDirectory)

        #expect(resolution.selectedPath == stateDirectory.appendingPathComponent("treelab.sock").path)
        #expect(!resolution.candidatePaths.isEmpty)
        for candidate in resolution.candidatePaths {
            #expect(!candidate.contains("/cmux"), "candidate \(candidate)")
        }
        #expect(CLISocketPathResolver.defaultSocketPath(bundleIdentifier: "sh.treelab.app", environment: [:])
            .hasSuffix("/.local/state/treelab/treelab.sock"))
    }

    @Test func cmuxCLIStillTargetsCmuxSocket() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let stateDirectory = CmuxStateDirectory.url(homeDirectory: home)

        let resolution = resolveImplicitly(bundleIdentifier: "com.cmuxterm.app", stateDirectory: stateDirectory)

        #expect(resolution.selectedPath == stateDirectory.appendingPathComponent("cmux.sock").path)
        #expect(resolution.candidatePaths.contains("/tmp/cmux.sock"))
        #expect(CLISocketPathResolver.defaultSocketPath(bundleIdentifier: "com.cmuxterm.app", environment: [:])
            .hasSuffix("/.local/state/cmux/cmux.sock"))
    }
}
