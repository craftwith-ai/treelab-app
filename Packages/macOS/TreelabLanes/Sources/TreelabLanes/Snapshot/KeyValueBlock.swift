import Foundation

/// One block of `KEY=value` lines, the text format lab writes for Treelab.
///
/// A key may repeat (`WATCH=` lists several paths), so values keep their order. Values are
/// data written by lab and by lanes: they are shown or compared, never executed.
public struct KeyValueBlock: Sendable, Equatable {
    /// The `(key, value)` pairs in file order.
    public let entries: [Entry]

    /// One `KEY=value` line.
    public struct Entry: Sendable, Equatable {
        /// The key, upper-case letters, digits and underscores.
        public let key: String
        /// Everything after the first `=`, unchanged.
        public let value: String
    }

    /// Creates a block from its entries.
    /// - Parameter entries: the pairs in file order.
    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The first value of `key`, or `nil` when the key is absent.
    /// - Parameter key: the key to look up.
    /// - Returns: the first value written for that key.
    public func first(_ key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    /// Every value of `key`, in file order.
    /// - Parameter key: the key to look up.
    /// - Returns: the values, empty when the key is absent.
    public func all(_ key: String) -> [String] {
        entries.filter { $0.key == key }.map(\.value)
    }
}
