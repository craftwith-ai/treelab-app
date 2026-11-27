import AppKit
import CmuxFeedback
import CmuxFoundation
import SwiftUI
import TreelabLanesUI

extension cmuxApp {
    @CommandsBuilder
    var helpCommands: some Commands {
        CommandGroup(replacing: .help) {
            // Treelab: the welcome of the first launch, reopened.
            if AppBranding.current != .cmux {
                Button(TreelabAccountCenter.welcomeMenuTitle) { AppDelegate.shared?.treelabAccount.showWelcome() }
                Divider()
            }
            primaryDocsHelpMenuItems
            secondaryDocsHelpMenuItems

            Divider()

            // A brand without Manaflow's services (Treelab) offers no Cloud, feedback, update or Pro item.
            if AppBranding.current.offersManaflowServices {
                Button(String(localized: "cloud.diagnostics.menu", defaultValue: "Cloud Diagnostics…")) {
                    AppDelegate.shared?.showCloudDiagnostics()
                }

                splitCommandButton(title: String(localized: "sidebar.help.sendFeedback", defaultValue: "Send Feedback"), shortcut: menuShortcut(for: .sendFeedback)) {
                    presentFeedbackFromHelpMenu()
                }

                Button(String(localized: "command.checkForUpdates.title", defaultValue: "Check for Updates")) {
                    AppDelegate.shared?.checkForUpdates(nil)
                }
            }

            Divider()

            helpResourceButton(.githubIssues)
            helpResourceButton(.discord)
            if AppBranding.current.offersManaflowServices, let offer = ProUpgradePresenter.currentUpgradeOffer {
                Button(ProUpgradePresenter.upgradeMenuTitle(for: offer)) {
                    ProUpgradePresenter.present(source: .helpMenu)
                }
            }
            #if DEBUG
            Button(String(localized: "menu.help.previewNativePricing", defaultValue: "Preview Native Pro Pricing…")) {
                ProUpgradePresenter.presentNativePricingPreview()
            }
            Button(String(localized: "debug.menu.cloudSidebarSpacingLab", defaultValue: "Cloud Sidebar Spacing Lab…")) {
                AppDelegate.shared?.debugWindowsCoordinator.cloudSidebarDebugLabController.show()
            }
            cloudWelcomeDebugMenuItems
            Button(String(localized: "menu.help.showProWelcomeChecklist", defaultValue: "Show Pro Welcome Checklist…")) {
                ProWelcomeChecklistPresenter.present()
            }
            Button(String(localized: "menu.help.featureFlags", defaultValue: "Feature Flags…")) {
                InternalFlagsPresenter.present()
            }
            Button(
                String(
                    localized: "debug.menu.sidebarFooterIconBalance",
                    defaultValue: "Footer Icon Balance Lab…"
                )
            ) {
                AppDelegate.shared?.debugWindowsCoordinator.showSidebarFooterIconBalanceWindow()
            }
            #endif

            Divider()

            Button(String(localized: "menu.help.keyboardShortcutsSettings", defaultValue: "Keyboard Shortcuts Settings…")) {
                openKeyboardShortcutsFromHelpMenu()
            }
        }
    }

    @ViewBuilder
    private var primaryDocsHelpMenuItems: some View {
        helpResourceButton(.gettingStarted)
        helpResourceButton(.concepts)
        helpResourceButton(.configuration)
        helpResourceButton(.customCommands)
        helpResourceButton(.dock)
        helpResourceButton(.keyboardShortcuts)
        helpResourceButton(.apiReference)
        helpResourceButton(.browserAutomation)
    }

    @ViewBuilder
    private var secondaryDocsHelpMenuItems: some View {
        helpResourceButton(.notifications)
        helpResourceButton(.ssh)
        helpResourceButton(.skills)
        agentIntegrationsHelpMenu
        helpResourceButton(.changelog)
    }

    private var agentIntegrationsHelpMenu: some View {
        Menu(String(localized: "menu.help.agentIntegrations", defaultValue: "Agent Integrations")) {
            helpResourceButton(.claudeCodeTeams)
            helpResourceButton(.ohMyOpenCode)
            helpResourceButton(.ohMyCodex)
            helpResourceButton(.ohMyClaudeCode)
        }
    }

    @ViewBuilder
    private func helpResourceButton(_ resource: CmuxHelpResource) -> some View {
        if let destination = Self.helpResourceDestination(resource) {
            Button(destination.title) {
                NSWorkspace.shared.open(destination.url)
            }
        }
    }

    /// Where a Help menu entry leads for the running brand. Treelab sends its guide, release
    /// notes and support entries to treelab.sh and has no community chat (`nil` hides the entry);
    /// the detailed docs pages stay on cmux.com, which documents the same features. Upstream
    /// cmux is unchanged.
    static func helpResourceDestination(
        _ resource: CmuxHelpResource,
        branding: AppBranding = .current
    ) -> (title: String, url: URL)? {
        guard branding != .cmux else { return (resource.title, resource.url) }
        let links = branding.helpLinks
        switch resource {
        case .gettingStarted: return (resource.title, links.docs)
        case .changelog: return (resource.title, links.changelog)
        case .githubIssues: return (branding.supportMenuTitle ?? resource.title, links.support)
        case .discord: return links.community.map { (title: resource.title, url: $0) }
        default: return (resource.title, resource.url)
        }
    }

    private func openKeyboardShortcutsFromHelpMenu() {
        if let appDelegate = AppDelegate.shared {
            appDelegate.openPreferencesWindow(
                debugSource: "helpMenu.keyboardShortcuts",
                navigationTarget: .keyboardShortcuts
            )
        } else {
            AppDelegate.presentPreferencesWindow(navigationTarget: .keyboardShortcuts)
        }
    }

    private func presentFeedbackFromHelpMenu() {
        if let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            FeedbackComposerBridge().openComposer(in: targetWindow)
            return
        }

        if let targetWindow = AppDelegate.shared?.showMainWindowFromMenuBar() {
            FeedbackComposerBridge().openComposer(in: targetWindow)
        }
    }
}
