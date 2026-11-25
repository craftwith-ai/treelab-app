import AppKit
import CmuxFoundation
import Foundation
import Testing

@testable import CmuxSettings

/// What Treelab shows of its brand: accent, help links, upstream credit and hidden shortcuts.
/// Upstream cmux keeps its own values.
@Suite struct TreelabBrandLookTests {
    private static let siteGreen = [0xB6, 0xF2, 0x7A]
    private static let readableGreen = [0x3D, 0x6B, 0x0F]

    // MARK: Accent

    @Test func treelabDefaultAccentIsTheSiteGreenInDarkAndAReadableGreenInLight() {
        let accent = CmuxAccentColor(mode: .cmux, customHex: nil, branding: .treelab)
        #expect(rgbBytes(accent.nsColor(isDark: true)) == Self.siteGreen)
        #expect(rgbBytes(accent.nsColor(isDark: false)) == Self.readableGreen)
    }

    @Test func treelabAccentFollowsTheDrawingAppearance() throws {
        let dynamic = CmuxAccentColor(mode: .cmux, customHex: nil, branding: .treelab).dynamicNSColor
        for (name, expected) in [(NSAppearance.Name.aqua, Self.readableGreen), (.darkAqua, Self.siteGreen)] {
            let appearance = try #require(NSAppearance(named: name))
            var drawn: [Int] = []
            appearance.performAsCurrentDrawingAppearance { drawn = rgbBytes(dynamic) }
            #expect(drawn == expected, "appearance \(name.rawValue)")
        }
    }

    @Test func treelabLightAccentReadsOnWhiteAndDarkAccentOnTheSitePage() {
        let accent = CmuxAccentColor(mode: .cmux, customHex: nil, branding: .treelab)
        #expect(contrastRatio(accent.nsColor(isDark: false), NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)) >= 4.5)
        let page = NSColor(srgbRed: 0x0C / 255.0, green: 0x14 / 255.0, blue: 0x10 / 255.0, alpha: 1)
        #expect(contrastRatio(accent.nsColor(isDark: true), page) >= 4.5)
    }

    @Test func treelabCustomModeWithoutAColorFallsBackToTheBrandAccent() {
        let accent = CmuxAccentColor(mode: .custom, customHex: nil, branding: .treelab)
        #expect(rgbBytes(accent.nsColor(isDark: true)) == Self.siteGreen)
        #expect(rgbBytes(accent.nsColor(isDark: false)) == Self.readableGreen)
    }

    @Test func treelabLeavesTheCmuxBluesUnchangedForCmux() {
        let accent = CmuxAccentColor(mode: .cmux, customHex: nil, branding: .cmux)
        #expect(rgbBytes(accent.nsColor(isDark: false)) == [0, 136, 255])
        #expect(rgbBytes(accent.nsColor(isDark: true)) == [0, 145, 255])
        #expect(AppBranding.cmux.accentHex == nil)
    }

    // MARK: Help links

    @Test func treelabHelpLinksPointToTreelabShInFrench() {
        let links = AppBranding.treelab.helpLinks(languageCode: "fr")
        #expect(links.docs.absoluteString == "https://treelab.sh/fr/guide/")
        #expect(links.support.absoluteString == "https://treelab.sh/fr/support/")
        // The release notes exist in English only (treelab.sh/fr/whats-new/ answers 404).
        #expect(links.changelog.absoluteString == "https://treelab.sh/en/whats-new/")
    }

    @Test func treelabHelpLinksUseEnglishOutsideFrench() {
        for language in ["en", "ja", "pt-BR", nil] as [String?] {
            let links = AppBranding.treelab.helpLinks(languageCode: language)
            #expect(links.docs.absoluteString == "https://treelab.sh/en/guide/", "language \(language ?? "nil")")
            #expect(links.support.absoluteString == "https://treelab.sh/en/support/")
            #expect(links.changelog.absoluteString == "https://treelab.sh/en/whats-new/")
        }
        #expect(AppBranding.treelab.helpLinks(languageCode: "fr-CA").docs.absoluteString == "https://treelab.sh/fr/guide/")
    }

    @Test func treelabSourceIsItsRepositoryWithoutCommunityChat() {
        let links = AppBranding.treelab.helpLinks(languageCode: "en")
        #expect(links.source.absoluteString == "https://github.com/craftwith-ai/treelab-app")
        #expect(links.commit("962fe96e6")?.absoluteString == "https://github.com/craftwith-ai/treelab-app/commit/962fe96e6")
        #expect(links.community == nil)
    }

    @Test func treelabLeavesTheCmuxHelpLinksUnchanged() {
        for language in ["fr", "en"] {
            let links = AppBranding.cmux.helpLinks(languageCode: language)
            #expect(links.docs.absoluteString == "https://cmux.com/docs")
            #expect(links.changelog.absoluteString == "https://cmux.com/docs/changelog")
            #expect(links.support.absoluteString == "https://github.com/manaflow-ai/cmux/issues")
            #expect(links.source.absoluteString == "https://github.com/manaflow-ai/cmux")
            #expect(links.community?.absoluteString == "https://discord.gg/xsgFEVrWCZ")
            #expect(links.commit("abc")?.absoluteString == "https://github.com/manaflow-ai/cmux/commit/abc")
        }
    }

    // MARK: Upstream credit

    @Test func treelabCreditsUpstreamAndCmuxDoesNot() {
        #expect(AppBranding.treelab.creditsUpstream)
        #expect(!AppBranding.cmux.creditsUpstream)
    }

    @Test func treelabCreditLineIsTranslatedInEveryShippedLanguage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CmuxFoundation/Sources/CmuxFoundation/Resources/Treelab.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let entry = try #require(strings["treelab.about.upstreamCredit"] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let shipped = ["ar", "bs", "da", "de", "en", "es", "fr", "it", "ja", "km", "ko", "nb", "pl", "pt-BR", "ru",
                       "th", "tr", "uk", "zh-Hans", "zh-Hant"]
        var english: String?
        for language in shipped {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            #expect(unit?["state"] as? String == "translated", "\(language) not translated")
            #expect(value.contains("cmux") && value.contains("Manaflow") && value.contains("GPL-3.0-or-later"),
                    "\(language): \(value)")
            if language == "en" { english = value } else { #expect(value != english, "\(language) copies English") }
        }
        #expect(english == "Based on cmux by Manaflow — GPL-3.0-or-later")
    }

    // MARK: Shortcuts

    @Test func treelabHidesTheSendFeedbackShortcut() {
        #expect(ShortcutAction.brandUnavailableActions(branding: .treelab) == [.sendFeedback])
        #expect(ShortcutAction.brandUnavailableActions(branding: .cmux).isEmpty)
        let visible = ShortcutAction.settingsVisibleActions(hiding: ShortcutAction.brandUnavailableActions(branding: .treelab))
        #expect(!visible.contains(.sendFeedback))
        #expect(visible.contains(.openSettings))
    }
}

private func rgbBytes(_ color: NSColor) -> [Int] {
    guard let srgb = color.usingColorSpace(.sRGB) else { return [] }
    return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
}

private func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
    func luminance(_ color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent) + 0.7152 * channel(srgb.greenComponent)
            + 0.0722 * channel(srgb.blueComponent)
    }
    let (light, dark) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
    return (light + 0.05) / (dark + 0.05)
}
