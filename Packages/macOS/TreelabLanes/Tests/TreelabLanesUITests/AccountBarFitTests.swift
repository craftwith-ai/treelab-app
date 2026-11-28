import AppKit
import Foundation
import Testing
@testable import TreelabLanesUI

/// The account entry at the bottom of the sidebar must show its whole second line (trial days,
/// plan) in every language the app ships, at the default sidebar width (240 points, the width
/// of the 1280×800 window): seen cut as "Essai gratuit · 9 jours resta…" on 2026-11-27.
@Suite struct AccountBarFitTests {
    private static let sidebarWidth: CGFloat = 240

    static func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TreelabLanesUI/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(json?["strings"] as? [String: Any])
    }

    /// Every value of a localization: plain, or each plural form.
    static func values(_ node: Any?) -> [String] {
        guard let node = node as? [String: Any] else { return [] }
        if let unit = node["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return [value] }
        let variations = node["variations"] as? [String: Any] ?? [:]
        return variations.values.flatMap { kind in
            (kind as? [String: Any] ?? [:]).values.flatMap { values($0) }
        }
    }

    /// Lines AppKit lays the text out on at that width (line fragments, so taller scripts count right).
    private static func linesNeeded(_ text: String, width: CGFloat) -> Int {
        lines(text, width: width, font: .systemFont(ofSize: AccountBarEntry.subtitleFontSize)).count
    }

    /// The text of each line AppKit lays the text out on at that width, with the standard line-break
    /// strategy SwiftUI's Text uses (it pushes words down rather than leave one alone on the last line).
    static func lines(_ text: String, width: CGFloat, font: NSFont) -> [String] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakStrategy = .standard
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: characters))
        }
        return lines
    }

    @Test func everyBarLineFitsInEveryLanguage() throws {
        let width = AccountBarEntry.subtitleWidth(sidebarWidth: Self.sidebarWidth)
        let skipped: Set<String> = ["treelab.account.bar.title", "treelab.account.bar.open", "treelab.account.bar.settings"]
        var cut: [String] = []
        for (key, entry) in try Self.catalog() where key.hasPrefix("treelab.account.bar.") && !skipped.contains(key) {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, node) in localizations {
                for value in Self.values(node) {
                    let text = AccountBarEntry.shownLine(value.replacingOccurrences(of: "%lld", with: "14"))
                    let lines = Self.linesNeeded(text, width: width)
                    if lines > AccountBarEntry.subtitleLineLimit { cut.append("\(language) \(key): \(text) (\(lines) lines)") }
                }
            }
        }
        #expect(cut.isEmpty, "cut in the sidebar: \(cut.sorted().joined(separator: "; "))")
    }

    /// Seen 2026-11-28 at 1280×800: "Essai gratuit" then "· 9 jours restants", the second line
    /// opening on the separator. The separator stays with the word before it.
    @Test func noBarLineStartsWithTheSeparator() throws {
        let width = AccountBarEntry.subtitleWidth(sidebarWidth: Self.sidebarWidth)
        let font = NSFont.systemFont(ofSize: AccountBarEntry.subtitleFontSize)
        var opened: [String] = []
        for (key, entry) in try Self.catalog() where key.hasPrefix("treelab.account.bar.") {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, node) in localizations {
                for value in Self.values(node) {
                    for days in ["9", "14"] {
                        let shown = AccountBarEntry.shownLine(value.replacingOccurrences(of: "%lld", with: days))
                        let laid = Self.lines(shown, width: width, font: font)
                        if laid.dropFirst().contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("·") }) {
                            opened.append("\(language) \(key): \(laid.joined(separator: " / "))")
                        }
                    }
                }
            }
        }
        #expect(opened.isEmpty, "a line opens on the separator: \(Set(opened).sorted().joined(separator: "; "))")
    }

    @Test func theEntryIsTallEnoughForItsLines() {
        let title = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 12, weight: .semibold))
        let line = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: AccountBarEntry.subtitleFontSize))
        let needed = title + 1 + CGFloat(AccountBarEntry.subtitleLineLimit) * line
        #expect(needed <= AccountBarEntry.height - 8)
    }
}

/// "Ginkgo · when it speaks" in Privacy: each option's name on one line, in every language, at
/// both window widths of the settings (1280 and 1512 points): seen 2026-11-28, "En conversation"
/// on two lines in a third of the card, its box taller than "Toujours" and "Jamais".
@Suite struct SpeechOptionsFitTests {
    @Test(arguments: [CGFloat(1280), CGFloat(1512)])
    func everySpeechOptionFitsOnOneLine(windowWidth: CGFloat) throws {
        let width = SpeechCard.optionNameWidth(windowWidth: windowWidth)
        let font = NSFont.systemFont(ofSize: AccountScreenSize(width: windowWidth).body, weight: .semibold)
        let keys = ["treelab.privacy.speak.always", "treelab.privacy.speak.conversation", "treelab.privacy.speak.never"]
        let catalog = try AccountBarFitTests.catalog()
        var wrapped: [String] = []
        for key in keys {
            let localizations = (catalog[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            #expect(localizations.count == 20, "\(key): \(localizations.count) languages")
            for (language, node) in localizations {
                for value in AccountBarFitTests.values(node) {
                    let laid = AccountBarFitTests.lines(value, width: width, font: font)
                    if laid.count > 1 { wrapped.append("\(language) \(key): \(laid.joined(separator: " / "))") }
                }
            }
        }
        #expect(wrapped.isEmpty, "on two lines at \(Int(windowWidth)) points: \(wrapped.sorted().joined(separator: "; "))")
    }
}
