import CmuxFoundation

/// Settings sections of Manaflow's services, which a brand that does not offer them (Treelab)
/// hides from the sidebar, the search results and every navigation. Their code stays.
extension SettingsSectionID {
    /// Account (sign-in, team, Pro offer), Mobile, Cloud, Devices and Networking.
    static let manaflowServiceSections: Set<SettingsSectionID> = [
        .account, .mobile, .cloudMachines, .computers, .networking,
    ]

    /// The sections `branding` hides.
    static func hidden(by branding: AppBranding = .current) -> Set<SettingsSectionID> {
        branding.offersManaflowServices ? [] : manaflowServiceSections
    }

    /// Where Settings lands when the stored or requested section is hidden: Account when shown,
    /// otherwise the first section of the display order that is shown.
    @MainActor
    static func landing(hidden: Set<SettingsSectionID> = hidden()) -> SettingsSectionID {
        guard hidden.contains(.account) else { return .account }
        return SettingsSectionMountModel.displayOrder.first { !hidden.contains($0) } ?? .account
    }

    /// This section, or ``landing(hidden:)`` when it is hidden.
    @MainActor
    func shown(hidden: Set<SettingsSectionID> = hidden()) -> SettingsSectionID {
        hidden.contains(self) ? Self.landing(hidden: hidden) : self
    }

    /// Where a navigation request scrolls: `destination` itself, or the top of the landing
    /// section (its own header) when the requested section is hidden.
    @MainActor
    static func shownDestination(
        _ destination: (section: SettingsSectionID, anchorID: String),
        hidden: Set<SettingsSectionID> = hidden()
    ) -> (section: SettingsSectionID, anchorID: String) {
        destination
    }
}

extension SettingsSidebarEntryVisibility {
    /// Whether `entry` is a hidden section's row or one of its settings.
    static func isInHiddenSection(_ entry: SettingsSearchIndex.Entry, hidden: Set<SettingsSectionID>) -> Bool {
        switch entry.kind {
        case .section:
            return hidden.contains { entry.id == "section:\($0.rawValue)" }
        case .setting(let parent):
            return hidden.contains(parent)
        }
    }
}
