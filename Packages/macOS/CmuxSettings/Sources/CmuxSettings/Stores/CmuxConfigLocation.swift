import CmuxFoundation
import Foundation

/// Conventional on-disk locations for the cmux JSON config.
///
/// A small value-typed bundle of URLs. Construct one with an explicit `home`
/// directory and inject it into the parts of the app that need to know where
/// the config file lives. No shared singletons; tests use a custom `home` URL
/// pointing into a temp directory.
///
/// ```swift
/// let locations = CmuxConfigLocation()
/// let store = JSONConfigStore(fileURL: locations.userConfigFile)
/// ```
public struct CmuxConfigLocation: Sendable, Hashable {
    /// The primary cmux config file: `<home>/.config/cmux/cmux.json`.
    public let userConfigFile: URL

    /// The legacy fallback: `<home>/.config/cmux/settings.json`. The app's
    /// settings reader checks this when the primary file is absent.
    public let legacyFallbackFile: URL

    /// Creates a location bundle anchored at the given home directory.
    ///
    /// - Parameters:
    ///   - home: The home directory to anchor paths to. Defaults to
    ///     `FileManager.default.homeDirectoryForCurrentUser`. Pass a temp URL
    ///     in tests.
    ///   - branding: The brand whose folder holds the files (`~/.config/treelab` for Treelab).
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        branding: AppBranding = .current
    ) {
        let directory = branding.configDirectory(homeDirectory: home)
        self.userConfigFile = directory.appending(path: "cmux.json")
        self.legacyFallbackFile = directory.appending(path: "settings.json")
    }
}
