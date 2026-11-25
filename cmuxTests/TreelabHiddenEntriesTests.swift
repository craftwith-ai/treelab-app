import CmuxCommandPalette
import CmuxFoundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Treelab shows no entry of Manaflow's services: no account button or Pro badge in the
/// sidebar footer, and the palette leaves out the app's real sign-in, team, Pro and update
/// commands. cmux keeps them.
@Suite struct TreelabHiddenEntriesTests {
    @Test func treelabFooterHasNoAccountButtonAndNoProBadge() {
        for mode in [WorkspacePresentationModeSettings.Mode.standard, .minimal] {
            let shown = SidebarFooterControl.allCases.filter {
                SidebarFooterPresentationPolicy.isVisible($0, presentationMode: mode, branding: .treelab)
            }
            #expect(!shown.contains(.account), "\(mode): account button shown")
            #expect(!shown.contains(.upgrade), "\(mode): Pro badge shown")
        }
        #expect(SidebarFooterPresentationPolicy.isVisible(.help, presentationMode: .standard, branding: .treelab))
    }

    @Test func cmuxFooterKeepsAccountButtonAndProBadge() {
        #expect(SidebarFooterPresentationPolicy.isVisible(.account, presentationMode: .standard, branding: .cmux))
        #expect(SidebarFooterPresentationPolicy.isVisible(.upgrade, presentationMode: .minimal, branding: .cmux))
    }

    /// The policy names the commands the app actually registers, so a renamed command cannot
    /// slip back into Treelab's palette.
    @Test func treelabPaletteLeavesOutTheAppsAccountProAndUpdateCommands() {
        let appCommandIDs = [
            ContentView.commandPaletteAuthSignInCommandId,
            ContentView.commandPaletteAuthSignOutCommandId,
            ContentView.commandPaletteAuthTeamPickerCommandId,
            ContentView.commandPaletteAuthTeamMembersCommandId,
            ContentView.commandPaletteProUpgradeCommandId,
            ContentView.commandPaletteProWelcomeChecklistCommandId,
        ]
        let toggleIDs = ContentView.commandPaletteSettingsToggleCommandContributions().map(\.commandId)
            .filter { $0.hasSuffix(".sendAnonymousTelemetry") || $0.hasSuffix(".showCloudDeviceIconsInSidebar") }
        #expect(toggleIDs.count == 2)

        let treelab = TreelabCommandPalettePolicy(branding: .treelab)
        let cmux = TreelabCommandPalettePolicy(branding: .cmux)
        for commandID in appCommandIDs + toggleIDs {
            #expect(!treelab.allows(commandId: commandID), "\(commandID) is offered by Treelab")
            #expect(cmux.allows(commandId: commandID), "\(commandID) is left out by cmux")
        }
    }
}
