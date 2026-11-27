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
}
