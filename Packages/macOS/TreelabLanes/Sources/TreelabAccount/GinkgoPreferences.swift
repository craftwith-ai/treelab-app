import TreelabLanes

/// When Ginkgo listens (`LISTEN=`, `lab app ginkgo --listen`).
public enum GinkgoListening: String, Sendable, Equatable, CaseIterable {
    /// On click: the microphone opens when the person clicks, Ginkgo's default.
    case command
    /// While ⌥ Space is held.
    case key
    /// When its name, "Ginkgo", is heard on the Mac.
    case name

    /// Ginkgo's default.
    public static let standard = GinkgoListening.command
}

/// When Ginkgo speaks out loud (`SPEAK=`, `lab app ginkgo --speak`).
public enum GinkgoSpeech: String, Sendable, Equatable, CaseIterable {
    /// Always, Ginkgo's default (an empty `ginkgo_speak`).
    case always
    /// Only during a conversation.
    case conversation
    /// Never.
    case never
}

/// Ginkgo's quiet hours (`QUIET=`, `lab app ginkgo --quiet`): off, or from one time to another.
public enum QuietSetting: Sendable, Equatable {
    /// No quiet hours.
    case off
    /// Quiet from `from` to `to`, each `HH:MM`.
    case hours(from: String, to: String)

    /// Reads `off` or `HH:MM-HH:MM`.
    /// - Parameter text: what lab wrote or the person chose.
    /// - Returns: `nil` for anything else.
    public init?(_ text: String) {
        if text == "off" {
            self = .off
            return
        }
        guard LabGinkgoSetting.isQuietRange(text) else { return nil }
        let parts = text.split(separator: "-").map(String.init)
        self = .hours(from: parts[0], to: parts[1])
    }

    /// Quiet hours from `from` to `to`.
    /// - Parameters:
    ///   - from: `HH:MM`.
    ///   - to: `HH:MM`.
    /// - Returns: `nil` unless both are `HH:MM`.
    public init?(from: String, to: String) {
        self.init("\(from)-\(to)")
    }

    /// The value given to `lab app ginkgo --quiet`.
    public var argument: String {
        switch self {
        case .off: "off"
        case let .hours(from, to): "\(from)-\(to)"
        }
    }
}

/// Ginkgo's settings as lab keeps them (`lab app ginkgo`); `nil` when unknown.
public struct GinkgoPreferences: Sendable, Equatable {
    /// When Ginkgo listens.
    public var listen: GinkgoListening?
    /// When Ginkgo speaks.
    public var speak: GinkgoSpeech?
    /// Its quiet hours.
    public var quiet: QuietSetting?

    /// Creates settings; unknown by default.
    public init(listen: GinkgoListening? = nil, speak: GinkgoSpeech? = nil, quiet: QuietSetting? = nil) {
        self.listen = listen
        self.speak = speak
        self.quiet = quiet
    }

    /// These settings with every value `other` knows.
    func merged(with other: GinkgoPreferences) -> GinkgoPreferences {
        GinkgoPreferences(listen: other.listen ?? listen, speak: other.speak ?? speak, quiet: other.quiet ?? quiet)
    }
}

/// Whether the OpenAI key is in the Mac's keychain (`lab ginkgo status`: `KEY=`). The key itself
/// is never read back.
public enum OpenAIKeyPresence: Sendable, Equatable {
    /// Not known yet.
    case unknown
    /// Stored.
    case present
    /// Not stored.
    case absent
}
