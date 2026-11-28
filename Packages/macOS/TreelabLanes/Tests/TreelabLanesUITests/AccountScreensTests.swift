import Foundation
import Testing
import TreelabAccount

@testable import TreelabLanesUI

@Suite("Welcome and settings: rules of the screens")
struct AccountScreensTests {
    private func defaults() -> UserDefaults {
        let name = "sh.treelab.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("the welcome opens by itself at the first launch only")
    func firstLaunchOnly() {
        let store = defaults()
        #expect(WelcomeGate(defaults: store).takeFirstLaunch(allowed: true))
        #expect(!WelcomeGate(defaults: store).takeFirstLaunch(allowed: true))
        #expect(!WelcomeGate(defaults: store).takeFirstLaunch(allowed: true))
    }

    @Test("while another demo runs, the welcome neither opens nor counts as seen")
    func otherDemo() {
        let store = defaults()
        #expect(!WelcomeGate(defaults: store).takeFirstLaunch(allowed: false))
        #expect(WelcomeGate(defaults: store).takeFirstLaunch(allowed: true))
    }

    @Test("the demo is read from this launch's arguments only, an absolute folder, a sane size")
    func demoArguments() {
        let demo = AccountDemoLaunch(arguments: ["Treelab", "-TreelabAccountDemo", "/tmp/demo", "-TreelabAccountDemoScreen", "welcome-3", "-TreelabAccountDemoSize", "1512x993"])
        #expect(demo?.folder.path == "/tmp/demo")
        #expect(demo?.screen == "welcome-3")
        #expect(demo?.size == CGSize(width: 1512, height: 993))
        #expect(AccountDemoLaunch(arguments: ["Treelab"]) == nil)
        #expect(AccountDemoLaunch(arguments: ["Treelab", "-TreelabAccountDemo", "relative"]) == nil)
        #expect(AccountDemoLaunch(arguments: ["Treelab", "-TreelabAccountDemo"]) == nil)
        #expect(AccountDemoLaunch(arguments: ["Treelab", "-TreelabAccountDemo", "/tmp/demo", "-TreelabAccountDemoSize", "99999x1"])?.size == nil)
    }

    @Test("prices are lab's offer, in its currency and the person's language")
    func prices() {
        let french = AccountPresentation(locale: Locale(identifier: "fr_FR"))
        let offer = AccountOffer(month: Decimal(string: "12.5"), year: Decimal(string: "125"), currency: "USD")
        #expect(french.price(offer.month, currency: offer.currency) == "12,50\u{a0}$US")
        #expect(french.price(offer.year, currency: offer.currency) == "125\u{a0}$US")
        #expect(french.price(nil, currency: "EUR") == nil)
        #expect(french.price(Decimal(7), currency: nil) == nil)
        #expect(AccountPresentation(locale: Locale(identifier: "en_US")).price(Decimal(7), currency: "EUR") == "€7")
    }

    @Test("the account entry says the trial's days, the plan, or the settings when lab lacks the contract")
    func barLine() {
        let english = AccountPresentation(locale: Locale(identifier: "en_US"))
        let trial = AccountSnapshot(signedIn: true, plan: .trial, standing: .trial, trialDaysLeft: 9)
        let yearly = AccountSnapshot(signedIn: true, plan: .yearly, standing: .active)
        #expect(english.barLine(.contract(trial)).contains("9"))
        #expect(english.barLine(.contract(yearly)) != english.barLine(.contract(trial)))
        #expect(english.barLine(.nextVersion) == english.barLine(.unknown))
        #expect(english.barLine(.contract(AccountSnapshot())) != english.barLine(.nextVersion))
    }

    @Test("an export notice names the folder, never its whole path")
    func exportedNotice() {
        let said = AccountPresentation().notice(.exported(path: "/Users/camille/Documents/treelab-export"))
        #expect(said.text.contains("treelab-export"))
        #expect(!said.text.contains("/Users"))
        #expect(!said.isProblem)
        #expect(AccountPresentation().notice(.refused("no")).isProblem)
    }

    /// A demo centre on an empty demo folder, with its own preferences.
    @MainActor
    private func demoCenter(screen: String?, store: UserDefaults) throws -> TreelabAccountCenter {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("treelab-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let arguments = ["Treelab", "-TreelabAccountDemo", folder.path] + (screen.map { ["-TreelabAccountDemoScreen", $0] } ?? [])
        #expect(AccountDemoLaunch(arguments: arguments) != nil)
        // Through make(), as the app builds it.
        return TreelabAccountCenter.make(arguments: arguments, home: folder, demoDefaults: store)
    }

    @Test("a demo launch without a screen follows the first-launch rule, in the demo's own preferences")
    @MainActor
    func demoWithoutScreenFollowsTheFirstLaunchRule() throws {
        let store = defaults()
        try demoCenter(screen: nil, store: store).start(showsWelcomeOnFirstLaunch: true)
        #expect(store.bool(forKey: TreelabAccountCenter.welcomeSeenKey))
    }

    @Test("make(): a demo launch keeps the demo's own preferences")
    @MainActor
    func makeKeepsTheDemoPreferences() throws {
        let store = defaults()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("treelab-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        TreelabAccountCenter.make(arguments: ["Treelab", "-TreelabAccountDemo", folder.path], home: folder, demoDefaults: store)
            .start(showsWelcomeOnFirstLaunch: true)
        #expect(store.bool(forKey: TreelabAccountCenter.welcomeSeenKey))
    }

    @Test("make(): a demo asked with a folder it cannot use runs no program and keeps the demo's preferences")
    @MainActor
    func unusableDemoStaysADemo() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("treelab-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        for arguments in [["Treelab", "-TreelabAccountDemo", "relative/folder"], ["Treelab", "-TreelabAccountDemo"]] {
            let store = defaults()
            let center = TreelabAccountCenter.make(arguments: arguments, home: home, demoDefaults: store)
            center.start(showsWelcomeOnFirstLaunch: true)
            #expect(store.bool(forKey: TreelabAccountCenter.welcomeSeenKey), "\(arguments)")
            await center.model.refresh()
            if case .labMissing = center.model.status {} else { Issue.record("\(arguments): a program ran, \(center.model.status)") }
        }
    }

    @Test("a demo launch on a named screen opens that screen and leaves the first launch untouched")
    @MainActor
    func demoScreenLeavesTheFirstLaunch() throws {
        let store = defaults()
        try demoCenter(screen: "account", store: store).start(showsWelcomeOnFirstLaunch: true)
        #expect(!store.bool(forKey: TreelabAccountCenter.welcomeSeenKey))
    }
}

@Suite("Welcome footer")
struct WelcomeFooterTests {
    @Test("every step of the welcome offers Later; the first and the last close it, the others skip their step")
    func laterEverywhere() {
        let footers = (1...TreelabWelcomeView.stepCount).map { WelcomeFooter(step: $0) }
        #expect(footers.map(\.later) == [.closes, .skipsStep, .skipsStep, .closes])
        #expect(footers.map(\.back) == [false, true, true, true])
        #expect(footers.map(\.isLast) == [false, false, false, true])
    }
}
