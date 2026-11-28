import Foundation
public import TreelabLanes

/// The account contract between Treelab and lab (`contrat-compte.md`, v1.1): how lab's answers are read.
///
/// Every value is data written by lab: it is shown or compared, never executed. A value Treelab
/// does not know stays unknown (`nil`), it is never guessed.
public enum AccountContract {
    /// The protocol Treelab speaks (`PROTOCOL=1`).
    public static let protocolVersion = "1"

    private static let parser = KeyValueBlockParser()

    /// Reads `lab app account`.
    /// - Parameter output: what lab returned.
    /// - Returns: the account, or ``AccountReading/nextVersion`` when lab does not speak this
    ///   contract (an unknown command, a refusal, another protocol).
    public static func reading(from output: LabCommandOutput) -> AccountReading {
        guard output.status == 0, let block = parser.blocks(in: output.standardOutput).first,
              block.first("PROTOCOL") == protocolVersion
        else { return .nextVersion }
        let offer = AccountOffer(
            trialDays: count(block.first("OFFER_TRIAL_DAYS"), in: 1...3650),
            month: price(block.first("OFFER_MONTH")),
            year: price(block.first("OFFER_YEAR")),
            currency: currency(block.first("OFFER_CURRENCY")),
            taxIncluded: block.first("OFFER_TAX") == "included",
            discountPercent: count(block.first("OFFER_DISCOUNT_PCT"), in: 1...100),
            discountFromSeats: count(block.first("OFFER_DISCOUNT_FROM"), in: 1...10_000)
        )
        return .contract(AccountSnapshot(
            signedIn: block.first("SIGNED_IN") == "yes",
            activation: block.first("ACTIVATION").flatMap(AccountActivation.init(rawValue:)),
            email: text(block.first("EMAIL")),
            role: block.first("ROLE").flatMap(AccountRole.init(rawValue:)),
            plan: block.first("PLAN").flatMap(AccountPlan.init(rawValue:)),
            period: block.first("PERIOD").flatMap(AccountPeriod.init(rawValue:)),
            standing: block.first("STATE").flatMap(AccountStanding.init(rawValue:)),
            trialDaysLeft: count(block.first("TRIAL_DAYS_LEFT"), in: 0...3650),
            renews: block.first("RENEWS").flatMap(AccountDay.init),
            ends: block.first("ENDS").flatMap(AccountDay.init),
            seats: count(block.first("SEATS"), in: 1...10_000),
            checked: text(block.first("CHECKED")),
            watch: Array(block.all("WATCH").filter { $0.hasPrefix("/") && !$0.contains("\u{0}") }.prefix(8)),
            offer: offer
        ))
    }

    /// Whether a written Ginkgo setting waits for Ginkgo's next opening (`APPLIES=next-open`,
    /// v1.1: the listening mode) rather than applying now.
    /// - Parameter output: what `lab app ginkgo --listen|--speak|--quiet` returned.
    /// - Returns: `true` for `next-open` only.
    public static func appliesAtNextOpen(_ output: LabCommandOutput) -> Bool {
        block(of: output).first("APPLIES") == "next-open"
    }

    /// Reads `lab app ginkgo`, or the answer of `lab app ginkgo --listen|--speak|--quiet`.
    /// - Parameter output: what lab returned.
    /// - Returns: the settings, `nil` when lab refused or failed.
    public static func ginkgo(from output: LabCommandOutput) -> GinkgoPreferences? {
        guard output.status == 0 else { return nil }
        let block = parser.blocks(in: output.standardOutput).first ?? KeyValueBlock(entries: [])
        let speak = block.first("SPEAK").flatMap { $0.isEmpty ? .always : GinkgoSpeech(rawValue: $0) }
        return GinkgoPreferences(
            listen: block.first("LISTEN").flatMap(GinkgoListening.init(rawValue:)),
            speak: speak,
            quiet: block.first("QUIET").flatMap(QuietSetting.init)
        )
    }

    /// Reads whether the OpenAI key is stored (`lab ginkgo status`: `KEY=present|absent`).
    /// - Parameter output: what lab returned.
    /// - Returns: present, absent, or unknown.
    public static func key(from output: LabCommandOutput) -> OpenAIKeyPresence {
        guard output.status == 0, let value = parser.blocks(in: output.standardOutput).first?.first("KEY") else { return .unknown }
        switch value {
        case "present", "stored": return .present
        case "absent": return .absent
        default: return .unknown
        }
    }

    /// The first block of an answer, empty when there is none.
    /// - Parameter output: what lab returned.
    /// - Returns: its first `KEY=value` block.
    public static func block(of output: LabCommandOutput) -> KeyValueBlock {
        parser.blocks(in: output.standardOutput).first ?? KeyValueBlock(entries: [])
    }

    /// How lab refused (contract v1.1): `REASON=` is a code on standard output
    /// (`usage|invalid|unsupported|unwritable`, `agent` later), the clear text is on stderr.
    /// - Parameter output: what lab returned.
    /// - Returns: ``LabRefusal/unsupported`` (the next treelab version), or one line for the
    ///   screen: lab's clear text, else its code, else its exit status.
    public static func refusal(of output: LabCommandOutput) -> LabRefusal {
        let code = text(block(of: output).first("REASON"))
        if code == "unsupported" { return .unsupported }
        let saysSomething = output.standardError.split(separator: "\n").contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if saysSomething, let clear = text(output.refusal) { return .said(clear) }
        return .said(code ?? output.refusal)
    }

    /// A shown value: trimmed, at most 320 characters, `nil` when empty.
    static func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return String(value.prefix(320))
    }

    /// A whole number written in digits only, within `range`.
    static func count(_ value: String?, in range: ClosedRange<Int>) -> Int? {
        guard let value, !value.isEmpty, value.count <= 6, value.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let number = Int(value), range.contains(number) else { return nil }
        return number
    }

    /// A price: digits, then at most two decimals after a point (`39`, `12.50`).
    static func price(_ value: String?) -> Decimal? {
        guard let value, !value.isEmpty, value.count <= 12 else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              parts.count == 1 || (1...2).contains(parts[1].count)
        else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// An ISO 4217 code: three capital letters.
    static func currency(_ value: String?) -> String? {
        guard let value, value.unicodeScalars.count == 3, value.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        return value
    }
}
