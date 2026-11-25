import CmuxFoundation
public import Foundation

/// The per-user directory that holds cmux's control-plane runtime state: the
/// control socket, its `last-socket-path` marker files, the socket password, and
/// the cached remote daemon binaries.
///
/// ## Why not Application Support
///
/// These files are read and written by **two separately code-signed binaries** —
/// the cmux app (bundle id `com.cmuxterm.app`) and the standalone `cmux` CLI
/// installed at `/usr/local/bin/cmux`. On macOS Sequoia, a non-sandboxed process
/// that reaches into another app's data under `~/Library/Application Support`,
/// `~/Library/Containers`, or `~/Library/Group Containers` triggers the
/// "<app> would like to access data from other apps" TCC ("App Data") prompt.
/// The CLI touches the control socket and the socket password on **every** agent
/// session-start and session-stop hook, so keeping those files in Application
/// Support made the prompt fire constantly
/// (https://github.com/manaflow-ai/cmux/issues/5146).
///
/// This directory therefore resolves to `~/.local/state/cmux`, a plain dotfolder
/// macOS does **not** treat as protected app data. It is the sibling of the
/// existing `~/.local/state/cmux/crash` breadcrumb directory.
///
/// ```swift
/// // The stable control socket; app and CLI agree on the same path by passing
/// // the real account home (`FileManager.default.homeDirectoryForCurrentUser`):
/// let home = FileManager.default.homeDirectoryForCurrentUser
/// let socket = CmuxStateDirectory.url(homeDirectory: home).appendingPathComponent("cmux.sock")
/// ```
public enum CmuxStateDirectory {
    /// The directory name segment under `~/.local/state` for the running brand.
    public static var directoryName: String { AppBranding.current.directoryName }

    /// The state directory of the running brand: `<home>/.local/state/cmux`.
    ///
    /// The home directory is injected (no ambient `FileManager.default` default)
    /// so this stays a pure, testable function with no hidden global state.
    /// Composition roots pass `FileManager.default.homeDirectoryForCurrentUser`,
    /// which resolves the real account home independently of the `HOME`
    /// environment variable, so the app and CLI always agree on the path even
    /// when a shell overrides `HOME`.
    ///
    /// - Parameter homeDirectory: The user's home directory.
    /// - Returns: The state directory URL (its parents are created on first write
    ///   by the socket listener, marker writer, and password store).
    public static func url(homeDirectory: URL) -> URL {
        url(homeDirectory: homeDirectory, branding: .current)
    }

    /// The state directory of `branding`: `<home>/.local/state/<directoryName>`.
    public static func url(homeDirectory: URL, branding: AppBranding) -> URL {
        branding.stateDirectory(homeDirectory: homeDirectory)
    }

    /// The legacy Application Support control directory
    /// (`~/Library/Application Support/cmux`).
    ///
    /// Retained so the app can migrate the socket password out of TCC-protected
    /// storage and mirror `last-socket-path` discovery markers for external
    /// clients that use the pre-0.64.20 contract. The listener, password store,
    /// and CLI use ``url(homeDirectory:)``; nothing on the CLI hook path should
    /// touch this location. The `FileManager` is injected (no ambient default)
    /// to keep the seam explicit for tests and alternate callers.
    ///
    /// - Parameter fileManager: Used to resolve Application Support.
    /// - Returns: The legacy directory, or `nil` when Application Support cannot
    ///   be resolved.
    public static func legacyApplicationSupportURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map(AppBranding.current.applicationSupportDirectory(in:))
    }
}
