public import Foundation

// The values the account commands of contract v1 pass to lab (`lab app signin`, `lab app data`,
// `lab app ginkgo`, `lab ginkgo key openai`), each checked so it stays one argument that can never
// be read as an option or a second line. lab checks them again on its side.

/// Whether `scalar` is a control character (a newline, a tab, NUL…).
private func isControl(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.generalCategory == .control || scalar == "\u{2028}" || scalar == "\u{2029}"
}

/// An e-mail address typed by the person, passed as one argument after `--email`.
///
/// Spaces around it are dropped; it must hold an `@` with text on both sides, at most 254 bytes,
/// no control character, and never start with `-`. Anything else, quotes, `$(…)` or `;`
/// included, is passed as typed: lab receives it as data, never through a shell.
public struct LabEmailAddress: Sendable, Equatable {
    /// The address.
    public let value: String

    /// Checks `text`.
    /// - Parameter text: what the person typed.
    /// - Returns: `nil` when it is not one safe address.
    public init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...254).contains(value.utf8.count),
              !value.hasPrefix("-"),
              !value.unicodeScalars.contains(where: isControl),
              let at = value.lastIndex(of: "@"),
              at != value.startIndex,
              value.index(after: at) != value.endIndex
        else { return nil }
        self.value = value
    }
}

/// A secret passed to lab on standard input, never as an argument (the OpenAI key).
///
/// Printing it, in a log or a debugger, shows `<secret>`. Treelab keeps it only for the call that
/// sends it; Swift cannot promise to wipe the memory it lived in.
public struct LabSecret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let bytes: Data

    /// Checks `text`.
    /// - Parameter text: the key as pasted; spaces and line ends around it are dropped.
    /// - Returns: `nil` when it is empty, longer than 4096 bytes or holds a control character
    ///   (a second line would be a second answer to lab).
    public init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...4096).contains(value.utf8.count), !value.unicodeScalars.contains(where: isControl) else { return nil }
        bytes = Data(value.utf8) + Data([0x0A])
    }

    /// What lab reads on its standard input: the secret and one line end.
    public var standardInputData: Data { bytes }

    public var description: String { "<secret>" }
    public var debugDescription: String { "<secret>" }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// A folder chosen by the person (`lab app data --export <folder>`): an absolute path on one line.
public struct LabFolderPath: Sendable, Equatable {
    /// The path.
    public let value: String

    /// Checks `path`.
    /// - Parameter path: an absolute path.
    /// - Returns: `nil` when it is relative, longer than 1024 bytes or holds a control character.
    public init?(_ path: String) {
        guard path.hasPrefix("/"), (1...1024).contains(path.utf8.count), !path.unicodeScalars.contains(where: isControl) else { return nil }
        value = path
    }
}

/// The token lab gives at the first step of an erase (`TOKEN=`), sent back to confirm it.
///
/// Letters, digits, `.`, `_` and `-`, starting with a letter or digit (never an option), at most
/// 128 characters.
public struct LabEraseToken: Sendable, Equatable {
    /// The token.
    public let value: String

    /// Checks `value`.
    /// - Parameter value: the `TOKEN=` lab returned.
    /// - Returns: `nil` when it is not safe.
    public init?(_ value: String) {
        guard (1...128).contains(value.unicodeScalars.count),
              let first = value.unicodeScalars.first, Self.isLetterOrDigit(first),
              value.unicodeScalars.allSatisfy({ Self.isLetterOrDigit($0) || ".-_".unicodeScalars.contains($0) })
        else { return nil }
        self.value = value
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}

/// One of Ginkgo's settings written by lab (`lab app ginkgo --listen|--speak|--quiet <value>`),
/// built only from the contract's values.
public struct LabGinkgoSetting: Sendable, Equatable {
    /// The option, `--listen`, `--speak` or `--quiet`.
    public let option: String
    /// Its value.
    public let value: String

    private init(_ option: String, _ value: String) {
        self.option = option
        self.value = value
    }

    /// When Ginkgo listens: `command` (on click), `key` (key held) or `name` (its name heard on the Mac).
    public static func listen(_ mode: String) -> LabGinkgoSetting? {
        ["command", "key", "name"].contains(mode) ? LabGinkgoSetting("--listen", mode) : nil
    }

    /// When Ginkgo speaks: `always`, `conversation` or `never`.
    public static func speak(_ mode: String) -> LabGinkgoSetting? {
        ["always", "conversation", "never"].contains(mode) ? LabGinkgoSetting("--speak", mode) : nil
    }

    /// Ginkgo's quiet hours: `HH:MM-HH:MM` or `off`.
    public static func quiet(_ range: String) -> LabGinkgoSetting? {
        range == "off" || isQuietRange(range) ? LabGinkgoSetting("--quiet", range) : nil
    }

    /// Whether `text` is exactly `HH:MM-HH:MM`, hours 00 to 23 and minutes 00 to 59.
    public static func isQuietRange(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { isTime(String($0)) }
    }

    /// Whether `text` is exactly `HH:MM`.
    public static func isTime(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 5, scalars[2] == ":" else { return false }
        let digits = [scalars[0], scalars[1], scalars[3], scalars[4]]
        guard digits.allSatisfy({ ("0"..."9").contains($0) }) else { return false }
        let value = digits.map { Int($0.value) - 48 }
        return value[0] * 10 + value[1] < 24 && value[2] * 10 + value[3] < 60
    }
}
