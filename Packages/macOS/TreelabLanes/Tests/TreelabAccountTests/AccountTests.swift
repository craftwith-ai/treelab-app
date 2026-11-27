import Foundation
import os
import Testing
import TreelabLanes

@testable import TreelabAccount

// MARK: Reading `lab app account` and `lab app ginkgo` (contract v1 §3, §4)

@Suite("Reading lab app account")
struct AccountReadingTests {
    private func snapshot(_ text: String) -> AccountSnapshot? {
        if case let .contract(snapshot) = AccountContract.reading(from: ok(text)) { return snapshot }
        return nil
    }

    @Test("signed in, on trial, with the days left, the seats, the watch file and the check time")
    func trial() throws {
        let account = try #require(snapshot(trialAccount))
        #expect(account.signedIn)
        #expect(account.email == "camille@exemple.fr")
        #expect(account.plan == .trial)
        #expect(account.standing == .trial)
        #expect(account.trialDaysLeft == 9)
        #expect(account.seats == 1)
        #expect(account.checked == "2026-11-27T10:00:00Z")
        #expect(account.watch == ["/Users/camille/.lab/state/account"])
        #expect(account.renews == nil && account.ends == nil)
    }

    @Test("the offer comes from OFFER_* only")
    func offer() throws {
        let offer = try #require(snapshot(trialAccount)).offer
        #expect(offer.trialDays == 14)
        #expect(offer.month == Decimal(string: "39"))
        #expect(offer.year == Decimal(string: "390"))
        #expect(offer.currency == "EUR")
        #expect(offer.taxIncluded)
        #expect(offer.discountPercent == 20)
        #expect(offer.discountFromSeats == 5)
        #expect(offer.isComplete)
        let other = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=no\nOFFER_MONTH=12.50\nOFFER_YEAR=125\nOFFER_CURRENCY=USD\nOFFER_TAX=excluded\n")).offer
        #expect(other.month == Decimal(string: "12.50"))
        #expect(other.currency == "USD")
        #expect(!other.taxIncluded)
    }

    @Test("monthly, yearly and owner plans, with their dates and seats")
    func plans() throws {
        let monthly = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nEMAIL=a@b.fr\nPLAN=monthly\nSTATE=active\nRENEWS=2026-12-27\nSEATS=6\n"))
        #expect(monthly.plan == .monthly)
        #expect(monthly.standing == .active)
        #expect(monthly.renews == AccountDay(year: 2026, month: 12, day: 27))
        #expect(monthly.seats == 6)
        let yearly = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=yearly\nSTATE=active\nENDS=2027-01-31\n"))
        #expect(yearly.plan == .yearly)
        #expect(yearly.ends == AccountDay(year: 2027, month: 1, day: 31))
        let owner = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=owner\nSTATE=active\n"))
        #expect(owner.plan == .owner)
        let ended = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=trial\nSTATE=ended\nTRIAL_DAYS_LEFT=0\n"))
        #expect(ended.standing == .ended)
        #expect(ended.trialDaysLeft == 0)
        #expect(try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=monthly\nSTATE=unpaid\n")).standing == .unpaid)
    }

    @Test("signed out: no e-mail, no plan")
    func signedOut() throws {
        let account = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=no\nPLAN=none\nSTATE=none\nWATCH=/w/account\n"))
        #expect(!account.signedIn)
        #expect(account.email == nil)
        #expect(account.plan == AccountPlan.none)
        #expect(account.standing == AccountStanding.none)
    }

    @Test("missing keys stay unknown, and a wrong value is never guessed")
    func missingAndWrong() throws {
        let bare = try #require(snapshot("PROTOCOL=1\n"))
        #expect(!bare.signedIn)
        #expect(bare.email == nil && bare.trialDaysLeft == nil && bare.seats == nil && bare.checked == nil)
        #expect(bare.plan == AccountPlan.none && bare.standing == AccountStanding.none)
        #expect(bare.offer == AccountOffer())
        #expect(!bare.offer.isComplete)
        #expect(bare.watch.isEmpty)
        let wrong = try #require(snapshot("""
        PROTOCOL=1
        SIGNED_IN=maybe
        EMAIL=
        PLAN=platinum
        STATE=frozen
        TRIAL_DAYS_LEFT=abc
        SEATS=-1
        RENEWS=2026-13-40
        ENDS=tomorrow
        WATCH=relative/path
        OFFER_MONTH=39€
        OFFER_YEAR=-390
        OFFER_CURRENCY=euro
        OFFER_DISCOUNT_PCT=120
        OFFER_DISCOUNT_FROM=0
        """))
        #expect(!wrong.signedIn)
        #expect(wrong.email == nil)
        #expect(wrong.plan == AccountPlan.none)
        #expect(wrong.standing == AccountStanding.none)
        #expect(wrong.trialDaysLeft == nil)
        #expect(wrong.seats == nil)
        #expect(wrong.renews == nil && wrong.ends == nil)
        #expect(wrong.watch.isEmpty)
        #expect(wrong.offer.month == nil && wrong.offer.year == nil && wrong.offer.currency == nil)
        #expect(wrong.offer.discountPercent == nil && wrong.offer.discountFromSeats == nil)
    }

    @Test("protocol gate: no PROTOCOL=1, another protocol, an unknown command or a refusal mean the next treelab version")
    func protocolGate() {
        #expect(AccountContract.reading(from: ok("SIGNED_IN=yes\nPLAN=trial\n")) == .nextVersion)
        #expect(AccountContract.reading(from: ok("PROTOCOL=2\nSIGNED_IN=yes\n")) == .nextVersion)
        #expect(AccountContract.reading(from: ok("PROTOCOL=1.0\nSIGNED_IN=yes\n")) == .nextVersion)
        #expect(AccountContract.reading(from: ok("")) == .nextVersion)
        #expect(AccountContract.reading(from: refused("unknown command")) == .nextVersion)
        #expect(AccountContract.reading(from: LabCommandOutput(status: 1, standardOutput: "", standardError: "lab: ERROR unknown command: app account\n")) == .nextVersion)
        #expect(AccountContract.reading(from: LabCommandOutput(status: 2, standardOutput: trialAccount, standardError: "")) == .nextVersion)
        if case .contract = AccountContract.reading(from: ok(trialAccount)) {} else { Issue.record("PROTOCOL=1 must be read") }
    }

    @Test("Ginkgo's settings: listening, speech and quiet hours")
    func ginkgo() throws {
        let read = try #require(AccountContract.ginkgo(from: ok("LISTEN=key\nSPEAK=conversation\nQUIET=21:00-08:00\n")))
        #expect(read.listen == .key)
        #expect(read.speak == .conversation)
        #expect(read.quiet == QuietSetting("21:00-08:00"))
        #expect(read.quiet?.argument == "21:00-08:00")
        let off = try #require(AccountContract.ginkgo(from: ok("LISTEN=name\nSPEAK=never\nQUIET=off\n")))
        #expect(off.listen == .name)
        #expect(off.speak == .never)
        #expect(off.quiet == .off)
        // An empty ginkgo_speak is Ginkgo's default: always.
        #expect(try #require(AccountContract.ginkgo(from: ok("LISTEN=command\nSPEAK=\n"))).speak == .always)
        let unknown = try #require(AccountContract.ginkgo(from: ok("LISTEN=telepathy\nSPEAK=sometimes\nQUIET=25:00-08:00\n")))
        #expect(unknown.listen == nil && unknown.speak == nil && unknown.quiet == nil)
        #expect(AccountContract.ginkgo(from: refused("unknown command")) == nil)
    }

    @Test("the OpenAI key is only ever said present or absent")
    func key() {
        #expect(AccountContract.key(from: ok("PROVIDER=openai\nKEY=present\n")) == .present)
        #expect(AccountContract.key(from: ok("PROVIDER=openai\nKEY=absent\n")) == .absent)
        #expect(AccountContract.key(from: ok("PROVIDER=openai\n")) == .unknown)
        #expect(AccountContract.key(from: refused("no")) == .unknown)
    }

    @Test("quiet hours: HH:MM-HH:MM or off, nothing else")
    func quiet() {
        #expect(QuietSetting("off") == .off)
        #expect(QuietSetting("07:05-22:30")?.argument == "07:05-22:30")
        #expect(QuietSetting(from: "21:00", to: "08:00")?.argument == "21:00-08:00")
        for wrong in ["", "21:00", "24:00-08:00", "21:60-08:00", "9:00-08:00", "21:00-08:00 ", "21:00-08:00;rm", "--quiet", "21h00-08h00", "OFF"] {
            #expect(QuietSetting(wrong) == nil, "\(wrong)")
        }
    }
}

// MARK: What lab receives (contract v1 §2, §3)

@Suite("Arguments sent to lab")
struct AccountCommandTests {
    private let dangerous = #"camille"; $(touch /tmp/treelab-pwned); echo 'x@exemple.fr"#

    @Test("each command is an exact list of arguments")
    func arguments() throws {
        let email = try #require(LabEmailAddress("camille@exemple.fr"))
        #expect(LabCommand.account.arguments == ["app", "account"])
        #expect(LabCommand.signIn(email: email).arguments == ["app", "signin", "--email", "camille@exemple.fr"])
        #expect(LabCommand.signOutEverywhere.arguments == ["app", "signout", "--everywhere"])
        #expect(LabCommand.subscribe.arguments == ["subscribe"])
        #expect(LabCommand.ginkgoSettings.arguments == ["app", "ginkgo"])
        #expect(LabCommand.setGinkgo(try #require(.listen("key"))).arguments == ["app", "ginkgo", "--listen", "key"])
        #expect(LabCommand.setGinkgo(try #require(.speak("conversation"))).arguments == ["app", "ginkgo", "--speak", "conversation"])
        #expect(LabCommand.setGinkgo(try #require(.quiet("21:00-08:00"))).arguments == ["app", "ginkgo", "--quiet", "21:00-08:00"])
        #expect(LabCommand.setGinkgo(try #require(.quiet("off"))).arguments == ["app", "ginkgo", "--quiet", "off"])
        let folder = try #require(LabFolderPath("/Users/camille/Mes données"))
        #expect(LabCommand.exportData(folder: folder).arguments == ["app", "data", "--export", "/Users/camille/Mes données"])
        #expect(LabCommand.eraseData.arguments == ["app", "data", "--erase"])
        let token = try #require(LabEraseToken("erase-7f3a.91"))
        #expect(LabCommand.confirmErase(token: token).arguments == ["app", "data", "--erase", "--confirm", "erase-7f3a.91"])
    }

    @Test("a dangerous e-mail stays one argument, never interpreted")
    func dangerousEmail() throws {
        let email = try #require(LabEmailAddress(dangerous))
        let arguments = LabCommand.signIn(email: email).arguments
        #expect(arguments.count == 4)
        #expect(arguments.last == dangerous)
    }

    @Test("an e-mail that could become an option or a second line is refused")
    func refusedEmails() {
        for wrong in ["", "   ", "camille", "@exemple.fr", "camille@", "-x@exemple.fr", "--everywhere@x.fr", "a\nb@exemple.fr", "a\u{0}b@exemple.fr", "a\tb@exemple.fr",
                      String(repeating: "a", count: 250) + "@exemple.fr"] {
            #expect(LabEmailAddress(wrong) == nil, "\(wrong.debugDescription)")
        }
        #expect(LabEmailAddress("  camille@exemple.fr \n")?.value == "camille@exemple.fr")
    }

    @Test("the OpenAI key goes on standard input only, never in the arguments, never printed")
    func keyOnStandardInput() throws {
        let key = try #require(LabSecret("sk-test-4f2a"))
        let command = LabCommand.storeOpenAIKey(key)
        #expect(command.arguments == ["ginkgo", "key", "openai"])
        #expect(!command.arguments.joined(separator: " ").contains("sk-test"))
        #expect(command.standardInput?.standardInputData == Data("sk-test-4f2a\n".utf8))
        #expect(!String(describing: command).contains("sk-test"))
        #expect(!String(reflecting: command).contains("sk-test"))
        #expect(!String(describing: key).contains("sk-test"))
        #expect(!String(reflecting: key).contains("sk-test"))
        #expect(Mirror(reflecting: key).children.isEmpty)
        #expect(LabCommand.account.standardInput == nil)
        #expect(LabCommand.subscribe.standardInput == nil)
        for wrong in ["", "  ", "sk-a\nsk-b", "sk\u{0}x", String(repeating: "k", count: 4097)] {
            #expect(LabSecret(wrong) == nil)
        }
        #expect(LabSecret("  sk-test  \n")?.standardInputData == Data("sk-test\n".utf8))
    }

    @Test("Ginkgo settings take only the contract's values")
    func ginkgoValues() {
        for mode in ["command", "key", "name"] { #expect(LabGinkgoSetting.listen(mode) != nil) }
        for mode in ["always", "conversation", "never"] { #expect(LabGinkgoSetting.speak(mode) != nil) }
        #expect(LabGinkgoSetting.listen("--speak") == nil)
        #expect(LabGinkgoSetting.listen("Command") == nil)
        #expect(LabGinkgoSetting.speak("") == nil)
        #expect(LabGinkgoSetting.quiet("21:00-08:00; rm -rf ~") == nil)
        #expect(LabGinkgoSetting.quiet("25:00-08:00") == nil)
    }

    @Test("an export folder is an absolute path on one line, an erase token is never an option")
    func folderAndToken() {
        #expect(LabFolderPath("relative/folder") == nil)
        #expect(LabFolderPath("") == nil)
        #expect(LabFolderPath("/a\nb") == nil)
        #expect(LabFolderPath("-rf") == nil)
        #expect(LabFolderPath("/Users/camille/Export")?.value == "/Users/camille/Export")
        for wrong in ["", "-rf", "--confirm", "a b", "a;b", "a\nb", String(repeating: "a", count: 129)] {
            #expect(LabEraseToken(wrong) == nil, "\(wrong.debugDescription)")
        }
    }
}

// MARK: The model against a fake lab that records arguments and standard input

@MainActor
@Suite("Account model against a fake lab")
struct AccountModelTests {
    private func model(_ lab: FakeLab, watcher: ScriptedFolders = ScriptedFolders()) -> AccountModel {
        AccountModel(runner: lab, watcher: watcher)
    }

    @Test("reading: the account, then Ginkgo's settings, then whether the key is stored")
    func reads() async throws {
        let lab = currentLab()
        let account = model(lab)
        await account.refresh()
        #expect(await lab.arguments == [["app", "account"], ["app", "ginkgo"], ["ginkgo", "status"]])
        let snapshot = try #require(account.snapshot)
        #expect(snapshot.trialDaysLeft == 9)
        #expect(account.ginkgo.listen == .command)
        #expect(account.ginkgo.speak == .always)
        #expect(account.ginkgo.quiet == QuietSetting("21:00-08:00"))
        #expect(account.key == .present)
        #expect(account.speaksContract)
    }

    @Test("an old lab: next treelab version, only the key status is read, nothing is launched")
    func oldLabNothingLaunched() async {
        let lab = oldLab()
        let account = model(lab)
        await account.refresh()
        #expect(account.status == .nextVersion)
        #expect(!account.speaksContract)
        #expect(await lab.arguments == [["app", "account"], ["ginkgo", "status"]])
        await lab.forget()
        await account.signIn(email: "camille@exemple.fr")
        await account.signOutEverywhere()
        await account.setListening(.key)
        await account.setSpeech(.never)
        await account.setQuiet("21:00-08:00")
        await account.exportData(to: URL(fileURLWithPath: "/Users/camille/Export"))
        await account.beginErase()
        #expect(await lab.calls.isEmpty)
        #expect(account.notice == .nextVersion)
    }

    @Test("an old lab still subscribes and stores the key: they already work")
    func oldLabSubscribeAndKey() async {
        let lab = oldLab()
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.subscribe()
        #expect(await lab.arguments == [["subscribe"]])
        #expect(account.notice == .subscribeOpened(.checkout))
        await lab.forget()
        await account.storeOpenAIKey("sk-test-4f2a")
        #expect(await lab.calls.first == ReceivedCall(arguments: ["ginkgo", "key", "openai"], standardInput: Data("sk-test-4f2a\n".utf8)))
        #expect(account.notice == .keyStored)
    }

    @Test("lab missing: said, nothing else tried")
    func labMissing() async {
        let account = AccountModel(runner: MissingLab(), watcher: ScriptedFolders())
        await account.refresh()
        if case .labMissing = account.status {} else { Issue.record("expected labMissing, got \(account.status)") }
        let none = AccountModel(runner: nil, watcher: ScriptedFolders())
        await none.refresh()
        if case .labMissing = none.status {} else { Issue.record("expected labMissing, got \(none.status)") }
        await none.subscribe()
        if case .labMissing = none.notice {} else { Issue.record("expected labMissing notice") }
    }

    @Test("sign in: the e-mail typed, dangerous or not, reaches lab as one argument")
    func signIn() async {
        let dangerous = #"camille"; $(touch /tmp/treelab-pwned); echo 'x@exemple.fr"#
        let lab = currentLab { command in
            command.arguments.prefix(2) == ["app", "signin"] ? ok("SENT=yes\nEMAIL=\(command.arguments.last ?? "")\n") : nil
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.signIn(email: dangerous)
        #expect(await lab.arguments.first == ["app", "signin", "--email", dangerous])
        #expect(account.notice == .linkSent(email: dangerous))
    }

    @Test("an e-mail lab could misread is refused before anything is sent")
    func signInRefusedLocally() async {
        let lab = currentLab()
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.signIn(email: "-everywhere@x.fr")
        await account.signIn(email: "camille")
        #expect(await lab.calls.isEmpty)
        #expect(account.notice == .invalidEmail)
    }

    @Test("sign out everywhere, then the account is read again")
    func signOut() async {
        let lab = currentLab { command in command == .signOutEverywhere ? ok("SIGNED_OUT=all\n") : nil }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.signOutEverywhere()
        #expect(await lab.arguments.first == ["app", "signout", "--everywhere"])
        #expect(await lab.arguments.contains(["app", "account"]))
        #expect(account.notice == .signedOutEverywhere)
    }

    @Test("subscribe and manage go through lab subscribe, which opens Stripe's page")
    func subscribe() async {
        let lab = currentLab { command in command == .subscribe ? ok("SUBSCRIBE=portal\nRESULT=opened\n") : nil }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.subscribe()
        #expect(await lab.arguments == [["subscribe"]])
        #expect(account.notice == .subscribeOpened(.portal))
    }

    @Test("the key: on standard input only, then said present, never kept")
    func storeKey() async throws {
        let stored = KeyFlag()
        let lab = FakeLab { command in
            switch command.arguments {
            case ["app", "account"]: return ok(trialAccount)
            case ["app", "ginkgo"]: return ok(ginkgoSettings)
            case ["ginkgo", "status"]: return ok(stored.isSet ? "KEY=present\n" : "KEY=absent\n")
            case ["ginkgo", "key", "openai"]:
                stored.set()
                return ok("KEY=stored\n")
            default: return ok("")
            }
        }
        let account = model(lab)
        await account.refresh()
        #expect(account.key == .absent)
        await lab.forget()
        await account.storeOpenAIKey("  sk-proj-SECRET-4f2a \n")
        let calls = await lab.calls
        #expect(calls.first == ReceivedCall(arguments: ["ginkgo", "key", "openai"], standardInput: Data("sk-proj-SECRET-4f2a\n".utf8)))
        for call in calls {
            #expect(!call.arguments.joined().contains("SECRET"))
            if call.arguments != ["ginkgo", "key", "openai"] { #expect(call.standardInput == nil) }
        }
        #expect(account.notice == .keyStored)
        #expect(account.key == .present)
        #expect(!String(describing: account.status).contains("SECRET"))
        #expect(!String(describing: account.notice as Any).contains("SECRET"))
    }

    @Test("an empty or multi-line key is refused before anything is sent")
    func keyRefusedLocally() async {
        let lab = currentLab()
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.storeOpenAIKey("   ")
        await account.storeOpenAIKey("sk-a\nsk-b")
        #expect(await lab.calls.isEmpty)
        #expect(account.notice == .invalidKey)
    }

    @Test("listening, speech and quiet hours: exact arguments, the new value read back")
    func ginkgoSettingsWritten() async {
        let lab = currentLab { command in
            let arguments = command.arguments
            guard arguments.count == 4, arguments.prefix(2) == ["app", "ginkgo"] else { return nil }
            switch arguments[2] {
            case "--listen": return ok("LISTEN=\(arguments[3])\nSPEAK=always\nQUIET=21:00-08:00\n")
            case "--speak": return ok("LISTEN=command\nSPEAK=\(arguments[3])\nQUIET=21:00-08:00\n")
            default: return ok("LISTEN=command\nSPEAK=always\nQUIET=\(arguments[3])\n")
            }
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.setListening(.name)
        #expect(account.ginkgo.listen == .name)
        await account.setSpeech(.conversation)
        #expect(account.ginkgo.speak == .conversation)
        await account.setQuiet("22:30-07:15")
        #expect(account.ginkgo.quiet == QuietSetting("22:30-07:15"))
        await account.setQuiet("off")
        #expect(account.ginkgo.quiet == .off)
        #expect(await lab.arguments == [
            ["app", "ginkgo", "--listen", "name"],
            ["app", "ginkgo", "--speak", "conversation"],
            ["app", "ginkgo", "--quiet", "22:30-07:15"],
            ["app", "ginkgo", "--quiet", "off"],
        ])
        #expect(account.notice == .saved)
    }

    @Test("quiet hours are checked before calling lab")
    func quietValidated() async {
        let lab = currentLab()
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.setQuiet("25:00-08:00")
        await account.setQuiet("21:00-08:00; rm -rf ~")
        #expect(await lab.calls.isEmpty)
        #expect(account.notice == .invalidQuietHours)
    }

    @Test("export: the folder chosen, as one argument, and where lab wrote it")
    func export() async {
        let lab = currentLab { command in
            command.arguments.prefix(3) == ["app", "data", "--export"] ? ok("EXPORTED=/Users/camille/Mes données/treelab-2026-11-27\n") : nil
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.exportData(to: URL(fileURLWithPath: "/Users/camille/Mes données"))
        #expect(await lab.arguments == [["app", "data", "--export", "/Users/camille/Mes données"]])
        #expect(account.notice == .exported(path: "/Users/camille/Mes données/treelab-2026-11-27"))
    }

    @Test("erase in two steps: lab's readback and token, then the token sent back")
    func eraseTwoSteps() async throws {
        let lab = currentLab { command in
            switch command.arguments {
            case ["app", "data", "--erase"]: return ok("READBACK=Treelab’s settings, lab’s account session, the OpenAI key\nTOKEN=erase-7f3a\n")
            case ["app", "data", "--erase", "--confirm", "erase-7f3a"]: return ok("ERASED=yes\n")
            default: return nil
            }
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.confirmErase()
        #expect(await lab.calls.isEmpty, "no confirmation without the first step")
        await account.beginErase()
        let pending = try #require(account.pendingErase)
        #expect(pending.readback == "Treelab’s settings, lab’s account session, the OpenAI key")
        await account.confirmErase()
        #expect(await lab.arguments.prefix(2) == [["app", "data", "--erase"], ["app", "data", "--erase", "--confirm", "erase-7f3a"]])
        #expect(account.pendingErase == nil)
        #expect(account.notice == .erased)
    }

    @Test("erase cancelled: the token is forgotten, nothing else is sent")
    func eraseCancelled() async {
        let lab = currentLab { command in
            command.arguments == ["app", "data", "--erase"] ? ok("READBACK=everything\nTOKEN=erase-1\n") : nil
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.beginErase()
        account.cancelErase()
        #expect(account.pendingErase == nil)
        await account.confirmErase()
        #expect(await lab.arguments == [["app", "data", "--erase"]])
    }

    @Test("an erase token that could become an option is never sent back")
    func eraseBadToken() async {
        let lab = currentLab { command in
            command.arguments == ["app", "data", "--erase"] ? ok("READBACK=everything\nTOKEN=--everywhere\n") : nil
        }
        let account = model(lab)
        await account.refresh()
        await lab.forget()
        await account.beginErase()
        #expect(account.pendingErase == nil)
        await account.confirmErase()
        #expect(await lab.arguments == [["app", "data", "--erase"]])
        if case .refused = account.notice {} else { Issue.record("expected a refusal, got \(String(describing: account.notice))") }
    }

    @Test("a refusal by lab (code 2 and REASON=) is said in lab's words")
    func refusals() async {
        let lab = currentLab { command in
            switch command {
            case .signOutEverywhere: return refused("only the person can sign out everywhere")
            case .subscribe: return LabCommandOutput(status: 2, standardOutput: "", standardError: "lab: ERROR no browser to open\n")
            default: return nil
            }
        }
        let account = model(lab)
        await account.refresh()
        await account.signOutEverywhere()
        #expect(account.notice == .refused("only the person can sign out everywhere"))
        await account.subscribe()
        #expect(account.notice == .refused("no browser to open"))
    }

    @Test("the WATCH= file rewritten wakes a new reading; its folder changing alone does not")
    func watch() async throws {
        let folder = try ScratchFolder()
        let file = folder.url.appendingPathComponent("account")
        try "first\n".write(to: file, atomically: false, encoding: .utf8)
        let watcher = ScriptedFolders()
        let lab = currentLab(account: trialAccount.replacingOccurrences(of: "WATCH=/Users/camille/.lab/state/account", with: "WATCH=\(file.path)"))
        let account = model(lab, watcher: watcher)
        account.start()
        #expect(await eventually { await lab.arguments.count == 3 })
        let folderPath = folder.path
        #expect(await eventually { watcher.watched == [[folderPath]] })
        await lab.forget()
        // Another file of the folder, or the folder itself, while the account file stays the same.
        watcher.emit(folder.path + "/other")
        watcher.emit(folder.path)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await lab.calls.isEmpty)
        // lab replaces the file (a temporary file, then a rename): the kernel reports the folder.
        let temporary = folder.url.appendingPathComponent(".account.tmp")
        try "second, longer\n".write(to: temporary, atomically: false, encoding: .utf8)
        #expect(rename(temporary.path, file.path) == 0)
        watcher.emit(folder.path)
        #expect(await eventually { await lab.arguments.first == ["app", "account"] })
    }
}

/// Whether the fake lab stored the key.
final class KeyFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isSet: Bool { lock.withLock { $0 } }
    func set() { lock.withLock { $0 = true } }
}
