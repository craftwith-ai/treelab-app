import AppKit
import Foundation
import Testing
@testable import TreelabLanesUI

/// The account entry at the bottom of the sidebar must show its whole second line (trial days,
/// plan) in every language the app ships, at the default sidebar width (240 points, the width
/// of the 1280×800 window): seen cut as "Essai gratuit · 9 jours resta…" on 2026-11-27.
@Suite struct AccountBarFitTests {
    private static let sidebarWidth: CGFloat = 240

    private static func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TreelabLanesUI/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(json?["strings"] as? [String: Any])
    }

    /// Every value of a localization: plain, or each plural form.
    private static func values(_ node: Any?) -> [String] {
        guard let node = node as? [String: Any] else { return [] }
        if let unit = node["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return [value] }
        let variations = node["variations"] as? [String: Any] ?? [:]
        return variations.values.flatMap { kind in
            (kind as? [String: Any] ?? [:]).values.flatMap { values($0) }
        }
    }

    /// Lines AppKit lays the text out on at that width (line fragments, so taller scripts count right).
    private static func linesNeeded(_ text: String, width: CGFloat) -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: AccountBarEntry.subtitleFontSize)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
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
                    let text = value.replacingOccurrences(of: "%lld", with: "14")
                    let lines = Self.linesNeeded(text, width: width)
                    if lines > AccountBarEntry.subtitleLineLimit { cut.append("\(language) \(key): \(text) (\(lines) lines)") }
                }
            }
        }
        #expect(cut.isEmpty, "cut in the sidebar: \(cut.sorted().joined(separator: "; "))")
    }

    @Test func theEntryIsTallEnoughForItsLines() {
        let title = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 12, weight: .semibold))
        let line = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: AccountBarEntry.subtitleFontSize))
        let needed = title + 1 + CGFloat(AccountBarEntry.subtitleLineLimit) * line
        #expect(needed <= AccountBarEntry.height - 8)
    }
}
