public import Foundation

/// Why Treelab does not connect to a socket (§2 of the contract).
public enum GinkgoSocketRefusal: Error, Sendable, Equatable {
    /// Longer than `sun_path` allows (103 bytes): never truncated.
    case pathTooLong(String)
    /// No socket there: Ginkgo is not running, or does not speak the contract.
    case absent(String)
    /// A link, a file that is not a socket, or a folder that is not a folder.
    case notASocket(String)
    /// Owned by someone else.
    case foreignOwner(String)
    /// The folder or the socket can be opened by others.
    case openToOthers(String)
    /// The process at the other end belongs to another user.
    case foreignPeer(uid_t)
}

/// Where Ginkgo's socket is, and the checks made before connecting to it.
public struct GinkgoSocketLocation: Sendable, Equatable {
    /// `sun_path` holds 104 bytes, the final zero included.
    public static let maxPathBytes = 103

    public let path: String
    public let ownerID: uid_t

    /// - Parameters:
    ///   - path: the socket's path.
    ///   - ownerID: the user who must own the folder and the socket (Treelab's user).
    public init(path: String, ownerID: uid_t = geteuid()) {
        self.path = path
        self.ownerID = ownerID
    }

    /// `<lab state>/ginkgo/app.sock`: `LAB_STATE_DIR` when it is an absolute path, else `~/.lab/state`.
    public static func standard(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> GinkgoSocketLocation {
        let state: String
        if let custom = environment["LAB_STATE_DIR"], custom.hasPrefix("/") {
            state = custom
        } else {
            state = home.appendingPathComponent(".lab/state").path
        }
        return GinkgoSocketLocation(path: (state as NSString).appendingPathComponent("ginkgo/app.sock"))
    }

    /// Checks the path, the folder and the socket.
    /// - Throws: a ``GinkgoSocketRefusal``.
    public func check() throws {
        guard path.utf8.count <= Self.maxPathBytes else { throw GinkgoSocketRefusal.pathTooLong(path) }
        let folder = (path as NSString).deletingLastPathComponent
        var info = stat()
        guard lstat(folder, &info) == 0 else { throw GinkgoSocketRefusal.absent(path) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw GinkgoSocketRefusal.notASocket(folder) }
        guard info.st_uid == ownerID else { throw GinkgoSocketRefusal.foreignOwner(folder) }
        guard info.st_mode & 0o077 == 0 else { throw GinkgoSocketRefusal.openToOthers(folder) }
        guard lstat(path, &info) == 0 else { throw GinkgoSocketRefusal.absent(path) }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw GinkgoSocketRefusal.notASocket(path) }
        guard info.st_uid == ownerID else { throw GinkgoSocketRefusal.foreignOwner(path) }
        guard info.st_mode & 0o077 == 0 else { throw GinkgoSocketRefusal.openToOthers(path) }
    }

    /// Checks the user of the process at the other end.
    /// - Throws: ``GinkgoSocketRefusal/foreignPeer(_:)``.
    public func checkPeer(uid: uid_t) throws {
        guard uid == ownerID else { throw GinkgoSocketRefusal.foreignPeer(uid) }
    }
}
