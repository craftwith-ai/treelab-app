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
        let yearly = AccountSnapshot(signedIn: true, plan: .subscription, period: .year, standing: .active)
        #expect(english.barLine(.contract(trial)).contains("9"))
        #expect(english.barLine(.contract(yearly)) != english.barLine(.contract(trial)))
        #expect(english.barLine(.nextVersion) == english.barLine(.unknown))
        #expect(english.barLine(.contract(AccountSnapshot())) != english.barLine(.nextVersion))
    }

    @Test("v1.1: a lifetime key on a Mac not signed in says its licence, never 'not signed in · free trial'")
    func lifetimeKeyLines() {
        let english = AccountPresentation(locale: Locale(identifier: "en_US"))
        let text = AccountText()
        let key = AccountSnapshot(signedIn: false, activation: .key, plan: .lifetime, standing: .active)
        #expect(english.barLine(.contract(key)) == text.accountBarLifetime)
        #expect(english.plan(key).title == text.accountPlanLifetime)
    }

    @Test("a Mac that already pays or has nothing more to pay is never offered the free trial nor its prices")
    func noTrialPitchToAPayingMac() {
        let presentation = AccountPresentation()
        let text = AccountText()
        let offer = AccountOffer(trialDays: 14, month: 39, year: 390, currency: "EUR", taxIncluded: true)
        let lifetime = AccountSnapshot(signedIn: false, activation: .key, plan: .lifetime, standing: .active, offer: offer)
        let monthly = AccountSnapshot(signedIn: true, plan: .subscription, period: .month, standing: .active, offer: offer)
        for paying in [lifetime, monthly] {
            #expect(!presentation.offersTrial(paying))
            #expect(presentation.welcomeAccountTitle(paying) == text.welcomeOverviewAccount)
            #expect(presentation.signInDetail(paying) == nil)
        }
        let trial = AccountSnapshot(signedIn: true, plan: .trial, standing: .trial, trialDaysLeft: 9, offer: offer)
        let signedOut = AccountSnapshot(signedIn: false, plan: AccountPlan.none, offer: offer)
        let over = AccountSnapshot(signedIn: true, plan: .subscription, period: .month, standing: .ended, offer: offer)
        for open in [trial, signedOut, over] {
            #expect(presentation.offersTrial(open))
            #expect(presentation.welcomeAccountTitle(open) == text.welcomeTrialTitleDays(14))
        }
        #expect(presentation.signInDetail(signedOut) == text.accountSignInDetailDays(14))
        #expect(presentation.signInDetail(AccountSnapshot()) == text.accountSignInDetail)
        // lab not answering the contract yet: the step stays the trial's, as before.
        #expect(presentation.offersTrial(nil))
        #expect(presentation.welcomeAccountTitle(nil) == text.welcomeTrialTitle)
    }

    @Test("v1.1: a subscription says its period, or only 'subscription' before the accounts; ended is ended")
    func subscriptionLines() {
        let english = AccountPresentation(locale: Locale(identifier: "en_US"))
        let text = AccountText()
        let month = AccountSnapshot(signedIn: true, plan: .subscription, period: .month, standing: .active)
        #expect(english.barLine(.contract(month)) == text.accountBarMonthly)
        #expect(english.plan(month).title == text.accountPlanMonthly)
        let year = AccountSnapshot(signedIn: true, plan: .subscription, period: .year, standing: .active)
        #expect(english.barLine(.contract(year)) == text.accountBarYearly)
        #expect(english.plan(year).title == text.accountPlanYearly)
        let bare = AccountSnapshot(signedIn: false, activation: .key, plan: .subscription, standing: .active)
        #expect(english.barLine(.contract(bare)) == text.accountBarSubscription)
        #expect(english.plan(bare).title == text.accountPlanSubscription)
        let over = AccountSnapshot(signedIn: true, plan: .subscription, period: .month, standing: .ended)
        #expect(english.barLine(.contract(over)) == text.accountBarEnded)
        let member = AccountSnapshot(signedIn: true, role: .member, plan: .subscription, period: .month, standing: .active)
        #expect(english.roleLine(member) == text.accountPlanMember)
        #expect(english.roleLine(month) == nil)
    }

    @Test("v1.1: rights not read yet, or a plan this Treelab does not know, are said not known yet")
    func unknownPlanLines() {
        let english = AccountPresentation(locale: Locale(identifier: "en_US"))
        let text = AccountText()
        for plan in [AccountPlan.unknown, nil] {
            let account = AccountSnapshot(signedIn: false, activation: .key, plan: plan, standing: .unknown)
            #expect(english.barLine(.contract(account)) == text.accountBarUnknown)
            #expect(english.plan(account).title == text.accountPlanUnknown && english.plan(account).detail == text.accountPlanUnknownDetail)
        }
        #expect(english.barLine(.contract(AccountSnapshot(signedIn: false, plan: AccountPlan.none))) == text.accountBarSignedOut)
        #expect(english.barLine(.contract(AccountSnapshot(signedIn: true, plan: AccountPlan.none))) == text.accountBarNone)
    }

    @Test("lab missing is said as such, never as the next treelab version")
    func labMissingIsNotNextVersion() {
        let presentation = AccountPresentation()
        let text = AccountText()
        #expect(presentation.unavailableTitle(.labMissing("not located")) == text.settingsLabMissingTitle)
        #expect(presentation.unavailableTitle(.nextVersion) == text.settingsNextVersionTitle)
        #expect(presentation.unavailableTitle(.contract(AccountSnapshot())) == nil)
        #expect(presentation.unavailableNote(.labMissing("not located"), nextVersion: text.welcomeTrialNextVersion) == text.settingsLabMissing)
        #expect(presentation.unavailableNote(.nextVersion, nextVersion: text.welcomeTrialNextVersion) == text.welcomeTrialNextVersion)
        #expect(presentation.unavailableNote(.unknown, nextVersion: text.settingsNextVersionSetting) == nil)
        #expect(presentation.unavailableNote(.contract(AccountSnapshot()), nextVersion: text.settingsNextVersionSetting) == nil)
    }

    @Test("quiet hours are shown on only when lab has hours: lab not knowing them is not 21:00–08:00")
    func quietHoursForm() {
        #expect(!SpeechCard.form(for: nil).isOn)
        #expect(!SpeechCard.form(for: .off).isOn)
        #expect(SpeechCard.form(for: .hours(from: "22:30", to: "07:15")) == QuietHoursForm(isOn: true, from: "22:30", to: "07:15"))
    }

    @Test("v1.1: Ginkgo's listening saved for its next opening is said so, not as a problem")
    func savedForNextOpenNotice() {
        let said = AccountPresentation().notice(.savedForNextOpen)
        #expect(said.text == AccountText().accountNoticeSavedNextOpen)
        #expect(!said.isProblem)
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
