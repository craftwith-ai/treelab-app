import CmuxFoundation
import Foundation
import Testing

@testable import CmuxTerminalCore

/// Treelab's terminal theme when the user has chosen none: "Treelab Light" in a light
/// appearance, "Treelab" in a dark one. A user theme still wins; cmux keeps its default.
@Suite struct TreelabDefaultThemeTests {
    @Test func treelabDefaultThemeFollowsTheAppearance() {
        #expect(GhosttyConfig.cmuxDefaultThemeName(preferredColorScheme: .light, branding: .treelab) == "Treelab Light")
        #expect(GhosttyConfig.cmuxDefaultThemeName(preferredColorScheme: .dark, branding: .treelab) == "Treelab")
    }

    @Test func treelabLeavesTheCmuxDefaultThemeUnchanged() {
        #expect(GhosttyConfig.cmuxDefaultThemeName(preferredColorScheme: .light, branding: .cmux) == "Apple System Colors Light")
        #expect(GhosttyConfig.cmuxDefaultThemeName(preferredColorScheme: .dark, branding: .cmux) == "Apple System Colors")
    }

    @Test func treelabManagedDefaultReadsItsThemeFilesFromTheBundle() throws {
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("treelab-theme-\(UUID().uuidString)", isDirectory: true)
        let themes = resources.appendingPathComponent("ghostty/themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        try "background = #0c1410\nforeground = #eef3ea\n".write(
            to: themes.appendingPathComponent("Treelab"), atomically: true, encoding: .utf8)
        try "background = #eef3ea\nforeground = #0c1410\n".write(
            to: themes.appendingPathComponent("Treelab Light"), atomically: true, encoding: .utf8)

        let dark = GhosttyConfig.cmuxDefaultThemeConfigContents(
            preferredColorScheme: .dark, environment: [:], bundleResourceURL: resources, branding: .treelab)
        let light = GhosttyConfig.cmuxDefaultThemeConfigContents(
            preferredColorScheme: .light, environment: [:], bundleResourceURL: resources, branding: .treelab)
        #expect(dark.contains("background = #0c1410"))
        #expect(light.contains("background = #eef3ea"))
    }

    @Test func treelabDefaultThemeYieldsToAUserThemeOrColor() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("treelab-user-theme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cases: [(String, Bool)] = [
            ("font-size = 14\n", true),
            ("theme = Dracula\n", false),
            ("theme = light:Solarized Light,dark:Solarized Dark\n", false),
            ("background = #000000\n", false),
        ]
        for (contents, applies) in cases {
            let file = dir.appendingPathComponent(UUID().uuidString)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            #expect(
                GhosttyConfig.shouldApplyManagedDefaultAppearance(configPaths: [file.path], adaptiveDefaultThemeEnabled: true)
                    == applies,
                "\(contents)")
        }
    }
}
