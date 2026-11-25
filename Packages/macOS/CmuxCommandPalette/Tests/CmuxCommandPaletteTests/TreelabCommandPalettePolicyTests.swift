import CmuxCommandPalette
import CmuxFoundation
import Testing

/// Treelab's palette offers no sign-in, Pro offer, update check, telemetry or Cloud-icon toggle;
/// every other command stays, and cmux keeps them all.
@Suite("Treelab command palette policy")
struct TreelabCommandPalettePolicyTests {
    private static let manaflowCommands = [
        "palette.auth.signIn",
        "palette.auth.signOut",
        "palette.auth.teamPicker",
        "palette.auth.teamMembers",
        "palette.pro.upgrade",
        "palette.pro.welcomeChecklist",
        "palette.mobileConnect",
        "palette.checkForUpdates",
        "palette.attemptUpdate",
        "palette.applyUpdateIfAvailable",
        "palette.toggleSetting.sendAnonymousTelemetry",
        "palette.toggleSetting.showCloudDeviceIconsInSidebar",
    ]

    private static let everydayCommands = [
        "palette.newTerminalTab",
        "palette.terminalSplitRight",
        "palette.openGhosttySettings",
        "palette.toggleSetting.showPullRequestsInSidebar",
    ]

    @Test func treelabLeavesOutEveryManaflowCommand() {
        let policy = TreelabCommandPalettePolicy(branding: .treelab)
        for command in Self.manaflowCommands {
            #expect(!policy.allows(commandId: command), "\(command) is offered")
        }
    }

    @Test func treelabKeepsEverydayCommands() {
        let policy = TreelabCommandPalettePolicy(branding: .treelab)
        for command in Self.everydayCommands {
            #expect(policy.allows(commandId: command), "\(command) is left out")
        }
    }

    @Test func cmuxOffersEveryCommand() {
        let policy = TreelabCommandPalettePolicy(branding: .cmux)
        for command in Self.manaflowCommands + Self.everydayCommands {
            #expect(policy.allows(commandId: command), "\(command) is left out")
        }
    }
}
