public import CmuxFoundation

/// Command-palette commands of Manaflow's services, which a brand that does not offer them
/// (Treelab) leaves out of the palette: sign-in and team, the Pro offer, update checks, and the
/// settings toggles for telemetry and Cloud icons. Their handlers stay registered.
public struct TreelabCommandPalettePolicy: Sendable {
    /// The command IDs of Manaflow's services.
    public static let manaflowServiceCommandIDs: Set<String> = [
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

    private let offersManaflowServices: Bool

    /// Creates the policy for `branding` (the running app's brand by default).
    public init(branding: AppBranding = .current) {
        offersManaflowServices = branding.offersManaflowServices
    }

    /// Whether the palette may offer the command `commandId`.
    public func allows(commandId: String) -> Bool {
        offersManaflowServices || !Self.manaflowServiceCommandIDs.contains(commandId)
    }
}
