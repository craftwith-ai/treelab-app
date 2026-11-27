public import Foundation

/// Reads a file only when it is safe to trust: inside its folder, not a link, a regular file,
/// owned by the user, writable by nobody else, and small.
///
/// The file is opened with `O_NOFOLLOW` and checked on the open descriptor (`fstat`), so it
/// cannot be swapped between the check and the read.
public struct SnapshotFileGate: Sendable {
    /// The owner every file and folder must have, the current user by default.
    public let ownerID: uid_t
    /// The largest file read, 256 KiB by default (lab's files are a few kilobytes).
    public let maxBytes: Int

    /// Creates a gate.
    /// - Parameters:
    ///   - ownerID: the expected owner, `geteuid()` by default; tests pass another one.
    ///   - maxBytes: the size ceiling.
    public init(ownerID: uid_t = geteuid(), maxBytes: Int = 256 * 1024) {
        self.ownerID = ownerID
        self.maxBytes = maxBytes
    }

    /// Reads `file` after the checks.
    /// - Parameters:
    ///   - file: the file to read.
    ///   - folder: the folder it must stay inside; the folder itself must be the user's and not writable by others.
    /// - Returns: the content as UTF-8 text (invalid bytes replaced).
    /// - Throws: ``SnapshotFileRefusal`` naming the first failed check.
    public func read(_ file: URL, within folder: URL) throws -> String {
        guard let filePath = Self.inside(file, folder) else { throw SnapshotFileRefusal.outsideFolder }
        try checkFolder(Self.lexical(folder.path))
        let descriptor = open(filePath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case ELOOP: throw SnapshotFileRefusal.symbolicLink
            case ENOENT, ENOTDIR: throw SnapshotFileRefusal.missing
            default: throw SnapshotFileRefusal.unreadable
            }
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw SnapshotFileRefusal.unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw SnapshotFileRefusal.notRegularFile }
        guard info.st_uid == ownerID else { throw SnapshotFileRefusal.wrongOwner }
        guard (info.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { throw SnapshotFileRefusal.writableByOthers }
        guard info.st_size <= off_t(maxBytes) else { throw SnapshotFileRefusal.tooLarge }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return Darwin.read(descriptor, base, buffer.count)
        }
        guard count >= 0 else { throw SnapshotFileRefusal.unreadable }
        return String(decoding: data.prefix(count), as: UTF8.self)
    }

    /// The modification date of `file` when it passes the same checks, without reading it.
    /// - Parameters:
    ///   - file: the file.
    ///   - folder: the folder it must stay inside.
    /// - Returns: its modification date, or `nil` when it is refused or missing.
    public func modificationDate(of file: URL, within folder: URL) -> Date? {
        guard let filePath = Self.inside(file, folder) else { return nil }
        var info = stat()
        guard lstat(filePath, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == ownerID, (info.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }

    /// The file's path when it stays inside `folder`, compared on text alone (`.` and `..`
    /// resolved without the disk: Foundation's standardizing drops `/private` only for paths
    /// that exist, which would make a missing file look outside its folder).
    private static func inside(_ file: URL, _ folder: URL) -> String? {
        let folderPath = lexical(folder.path)
        let filePath = lexical(file.path)
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return filePath.hasPrefix(prefix) && filePath.count > prefix.count ? filePath : nil
    }

    private static func lexical(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    private func checkFolder(_ path: String) throws {
        var info = stat()
        guard stat(path, &info) == 0 else { throw SnapshotFileRefusal.missing }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw SnapshotFileRefusal.notRegularFile }
        guard info.st_uid == ownerID else { throw SnapshotFileRefusal.wrongOwner }
        guard (info.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { throw SnapshotFileRefusal.writableByOthers }
    }
}
