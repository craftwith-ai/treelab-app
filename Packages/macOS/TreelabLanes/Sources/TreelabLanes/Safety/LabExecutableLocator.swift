public import Foundation

/// Finds the `lab` program Treelab may run: an absolute path, never looked up in `PATH`.
///
/// The program (after following its links) must be a regular executable file owned by the user
/// or by root and writable by nobody else, inside a folder writable by nobody else: otherwise
/// another account could change what Treelab runs.
public struct LabExecutableLocator: Sendable {
    /// Paths tried in order.
    public let candidates: [URL]
    /// The owner accepted besides root, the current user by default.
    public let ownerID: uid_t

    /// Creates a locator.
    /// - Parameters:
    ///   - candidates: absolute paths tried in order; by default lab's own installation
    ///     (`~/.lab/current/bin/lab`), then Homebrew's and `/usr/local`'s links.
    ///   - ownerID: the accepted owner besides root.
    public init(candidates: [URL], ownerID: uid_t = geteuid()) {
        self.candidates = candidates
        self.ownerID = ownerID
    }

    /// The default candidates for a home folder.
    /// - Parameter home: the user's home folder.
    /// - Returns: the paths tried by Treelab.
    public static func defaultCandidates(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".lab/current/bin/lab"),
            URL(fileURLWithPath: "/opt/homebrew/bin/lab"),
            URL(fileURLWithPath: "/usr/local/bin/lab"),
        ]
    }

    /// The first acceptable program.
    /// - Returns: its resolved path.
    /// - Throws: ``LanesProblem/labUnavailable(_:)`` naming why each candidate was refused.
    public func locate() throws -> URL {
        var reasons: [String] = []
        for candidate in candidates {
            switch check(candidate) {
            case .success(let url): return url
            case .failure(let reason): reasons.append("\(candidate.path): \(reason)")
            }
        }
        throw LanesProblem.labUnavailable(reasons.joined(separator: "; "))
    }

    /// Checks one path.
    /// - Parameter candidate: an absolute path.
    /// - Returns: the resolved path, or the reason it is refused.
    public func check(_ candidate: URL) -> Result<URL, LabExecutableRefusal> {
        guard candidate.path.hasPrefix("/") else { return .failure(.notAbsolute) }
        guard let resolved = realpath(candidate.path, nil) else { return .failure(.missing) }
        let path = String(cString: resolved)
        free(resolved)
        var info = stat()
        guard stat(path, &info) == 0 else { return .failure(.missing) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return .failure(.notRegularFile) }
        guard info.st_uid == ownerID || info.st_uid == 0 else { return .failure(.wrongOwner) }
        guard (info.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { return .failure(.writableByOthers) }
        guard (info.st_mode & S_IXUSR) != 0 else { return .failure(.notExecutable) }
        var folder = stat()
        let folderPath = (path as NSString).deletingLastPathComponent
        guard stat(folderPath, &folder) == 0, (folder.st_mode & (S_IWGRP | S_IWOTH)) == 0 else {
            return .failure(.folderWritableByOthers)
        }
        return .success(URL(fileURLWithPath: path))
    }
}
