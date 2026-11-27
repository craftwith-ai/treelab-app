import Foundation

/// A private temporary folder for one test, removed at the end.
final class TemporaryFolder {
    let url: URL

    init() throws {
        let created = FileManager.default.temporaryDirectory.appendingPathComponent("treelab-lanes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        // The real path (`/private/var/…`), as lab and realpath(3) see it.
        let real = realpath(created.path, nil)
        url = URL(fileURLWithPath: real.map { String(cString: $0) } ?? created.path)
        free(real)
        chmod(url.path, 0o700)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ relative: String, _ text: String, mode: mode_t = 0o644, date: Date? = nil) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: false, encoding: .utf8)
        chmod(file.path, mode)
        if let date {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        return file
    }

    func folder(_ relative: String, mode: mode_t = 0o700) throws -> URL {
        let folder = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        chmod(folder.path, mode)
        return folder
    }
}
