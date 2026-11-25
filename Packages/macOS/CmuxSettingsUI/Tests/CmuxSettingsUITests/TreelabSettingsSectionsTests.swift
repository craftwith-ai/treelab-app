import CmuxFoundation
import CmuxSettings
import Foundation
import Testing
@testable import CmuxSettingsUI

/// Treelab offers no Manaflow service, so Settings shows no Account, Mobile, Cloud, Devices or
/// Networking section, in the sidebar, in search results or as a landing pane; cmux keeps them.
@Suite("Treelab Settings sections")
struct TreelabSettingsSectionsTests {
    private static let manaflowSections: [SettingsSectionID] = [
        .account, .mobile, .cloudMachines, .computers, .networking,
    ]

    private func visibleEntries(_ query: String, branding: AppBranding) -> [SettingsSearchIndex.Entry] {
        let index = SettingsSearchIndex(catalog: SettingCatalog())
        return index.match(query).filter {
            SettingsSidebarEntryVisibility.isVisible(
                $0,
                isCloudSectionAvailable: true,
                isChiefAvailable: true,
                hiddenSections: SettingsSectionID.hidden(by: branding)
            )
        }
    }

    private func sectionRows(_ branding: AppBranding) -> Set<String> {
        Set(visibleEntries("", branding: branding).map(\.id).filter { $0.hasPrefix("section:") })
    }

    @Test func treelabSidebarListsNoManaflowSection() {
        let rows = sectionRows(.treelab)
        for section in Self.manaflowSections {
            #expect(!rows.contains("section:\(section.rawValue)"), "\(section.rawValue) is listed")
        }
        #expect(rows.contains("section:\(SettingsSectionID.app.rawValue)"))
        #expect(rows.contains("section:\(SettingsSectionID.terminal.rawValue)"))
    }

    @Test func cmuxSidebarKeepsEveryManaflowSection() {
        let rows = sectionRows(.cmux)
        for section in Self.manaflowSections {
            #expect(rows.contains("section:\(section.rawValue)"), "\(section.rawValue) is missing")
        }
    }

    @Test func treelabSearchFindsNoSettingOfAHiddenSection() {
        let hidden = Set(Self.manaflowSections)
        for query in ["sign", "connect", "pro", "pair", "iphone", "devices", "iroh", "cloud", "team"] {
            for entry in visibleEntries(query, branding: .treelab) {
                if case .setting(let parent) = entry.kind {
                    #expect(!hidden.contains(parent), "'\(query)' finds \(entry.id)")
                }
            }
        }
    }

    @Test @MainActor func treelabLandsOnTheFirstShownSectionInsteadOfAccount() {
        let hidden = SettingsSectionID.hidden(by: .treelab)

        #expect(SettingsSectionID.landing(hidden: hidden) == .app)
        for section in Self.manaflowSections {
            #expect(section.shown(hidden: hidden) == .app)
        }
        #expect(SettingsSectionID.terminal.shown(hidden: hidden) == .terminal)
    }

    @Test @MainActor func cmuxStillLandsOnAccount() {
        let hidden = SettingsSectionID.hidden(by: .cmux)

        #expect(hidden.isEmpty)
        #expect(SettingsSectionID.landing(hidden: hidden) == .account)
        #expect(SettingsSectionID.mobile.shown(hidden: hidden) == .mobile)
    }
}
