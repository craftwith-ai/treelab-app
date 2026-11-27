import Foundation

/// Reads lab's `KEY=value` text into blocks separated by blank lines.
///
/// Lines whose key is not upper-case letters, digits and underscores are skipped, so a stray
/// line can never become a field.
///
/// ```swift
/// let blocks = KeyValueBlockParser().blocks(in: "PROJECT=demo\nLANE=api\n")
/// blocks.first?.first("LANE") // "api"
/// ```
public struct KeyValueBlockParser: Sendable {
    /// Creates a parser.
    public init() {}

    /// Splits `text` into blocks.
    /// - Parameter text: the output of a lab command or the content of a snapshot file.
    /// - Returns: the non-empty blocks, in order.
    public func blocks(in text: String) -> [KeyValueBlock] {
        var blocks: [KeyValueBlock] = []
        var current: [KeyValueBlock.Entry] = []
        // Only "\n" ends a line, as lab writes them: another newline character (U+2028, a lone
        // "\r"…) inside a value must never start a field. Split on scalars, since "\r\n" is one
        // Character in Swift, then drop the "\r" of a "\r\n" ending.
        for scalars in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = Substring(String(String.UnicodeScalarView(scalars)))
            if line.unicodeScalars.last == "\r" { line = Substring(String(line.unicodeScalars.dropLast())) }
            if line.isEmpty {
                if !current.isEmpty { blocks.append(KeyValueBlock(entries: current)) }
                current = []
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals])
            guard isKey(key) else { continue }
            current.append(KeyValueBlock.Entry(key: key, value: String(line[line.index(after: equals)...])))
        }
        if !current.isEmpty { blocks.append(KeyValueBlock(entries: current)) }
        return blocks
    }

    private func isKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, ("A"..."Z").contains(first) else { return false }
        return key.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }
}
