/// The id of a question box (`QID=`), safe to pass back to `lab ginkgo answer --qid`.
///
/// Letters, digits, `.`, `_`, `:` and `-`, starting with a letter or digit (never an option),
/// at most 128 characters.
public struct LabQuestionID: Sendable, Equatable {
    /// The id.
    public let value: String

    /// Validates `value`.
    /// - Parameter value: the `QID=` lab returned.
    /// - Returns: `nil` when it is not safe.
    public init?(_ value: String) {
        guard (1...128).contains(value.unicodeScalars.count),
              let first = value.unicodeScalars.first,
              Self.isLetterOrDigit(first),
              value.unicodeScalars.allSatisfy({ Self.isLetterOrDigit($0) || ".-_:".unicodeScalars.contains($0) })
        else { return nil }
        self.value = value
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
