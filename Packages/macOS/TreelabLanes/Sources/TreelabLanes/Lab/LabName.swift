/// A project or lane name safe to pass to lab as one argument.
///
/// Letters, digits, `.`, `_` and `-`, starting with a letter or digit (a leading `-` would be
/// read as an option), at most 100 characters.
public struct LabName: Sendable, Equatable, CustomStringConvertible {
    /// The name.
    public let value: String

    /// Validates `value`.
    /// - Parameter value: a project or lane name read from lab.
    /// - Returns: `nil` when the name is not safe.
    public init?(_ value: String) {
        guard (1...100).contains(value.count),
              let first = value.unicodeScalars.first,
              Self.isLetterOrDigit(first),
              value.unicodeScalars.allSatisfy({ Self.isLetterOrDigit($0) || $0 == "." || $0 == "_" || $0 == "-" })
        else { return nil }
        self.value = value
    }

    /// The name itself.
    public var description: String { value }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
