import Foundation
import os
import Testing
import TreelabLanes

@testable import TreelabAccount

// MARK: Findings of the batch's single review, against the account contract v1.1

/// A lab whose `app signin` takes a while, as a real one talking to treelab's server.
actor SlowSignInLab: LabCommandRunning {
    private(set) var calls: [[String]] = []

    func run(_ command: LabCommand) async throws -> LabCommandOutput {
        calls.append(command.arguments)
        switch command.arguments.prefix(2) {
        case ["app", "account"]: return ok(trialAccount.replacingOccurrences(of: "SIGNED_IN=yes", with: "SIGNED_IN=no"))
        case ["app", "ginkgo"]: return ok(ginkgoSettings)
        case ["app", "signin"]:
            try await Task.sleep(for: .milliseconds(300))
            return ok("SENT=yes\nEMAIL=camille@exemple.fr\n")
        default: return ok("PROVIDER=openai\nKEY=absent\n")
        }
    }
}

/// A v1.1 refusal: `REASON=` is a code on standard output, the clear text is on stderr.
func refusedV11(_ code: String, _ text: String) -> LabCommandOutput {
    LabCommandOutput(status: 2, standardOutput: "REASON=\(code)\n", standardError: "lab: ERROR \(text)\n")
}

@Suite("Review fixes: refusals, one action at a time, the WATCH= folder")
@MainActor
struct AccountReviewFixesTests {
    @Test("v1.1: REASON=unsupported (sign-in, sign-out before the accounts) is the next treelab version")
    func unsupportedIsNextVersion() async {
        let lab = currentLab { command in
            switch command {
            case .signIn: return refusedV11("unsupported", "accounts come with a later treelab version")
            case .signOutEverywhere: return refusedV11("unsupported", "accounts come with a later treelab version")
            default: return nil
            }
        }
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        await account.signIn(email: "camille@exemple.fr")
        #expect(account.notice == .nextVersion)
        account.clearNotice()
        await account.signOutEverywhere()
        #expect(account.notice == .nextVersion)
    }

    @Test("v1.1: any other refusal is said in lab's clear words (stderr), never by its machine code")
    func otherRefusalsInClearWords() async {
        let lab = currentLab { command in
            switch command {
            case .setGinkgo: return refusedV11("invalid", "an empty quiet range is refused")
            case .exportData: return refusedV11("unwritable", "~/.lab/config cannot be written, nothing changed")
            case .subscribe: return LabCommandOutput(status: 2, standardOutput: "REASON=usage\n", standardError: "")
            default: return nil
            }
        }
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        await account.setQuiet("22:00-07:00")
        #expect(account.notice == .refused("an empty quiet range is refused"))
        await account.exportData(to: URL(fileURLWithPath: "/Users/camille/Documents"))
        #expect(account.notice == .refused("~/.lab/config cannot be written, nothing changed"))
        // No clear text: the code is all lab said.
        await account.subscribe()
        #expect(account.notice == .refused("usage"))
    }

    @Test("Return pressed twice in the e-mail field sends one sign-in only")
    func oneSignInAtATime() async {
        let lab = SlowSignInLab()
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        async let first: Void = account.signIn(email: "camille@exemple.fr")
        async let second: Void = account.signIn(email: "camille@exemple.fr")
        _ = await (first, second)
        #expect(await lab.calls.filter { $0.prefix(2) == ["app", "signin"] }.count == 1)
    }

    private func watchingLab(_ file: String) -> FakeLab {
        currentLab(account: trialAccount.replacingOccurrences(of: "WATCH=/Users/camille/.lab/state/account", with: "WATCH=\(file)"))
    }

    @Test("a WATCH= folder missing at the first reading is watched once it exists (next reading)")
    func missingFolderArmedLater() async throws {
        let scratch = try ScratchFolder()
        let folder = scratch.url.appendingPathComponent("state")
        let file = folder.appendingPathComponent("account")
        let watcher = ScriptedFolders()
        let account = AccountModel(runner: watchingLab(file.path), watcher: watcher)
        await account.refresh()
        #expect(watcher.watched == [[folder.path]])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        // The settings opening reads the account again.
        await account.refresh()
        #expect(watcher.watched == [[folder.path], [folder.path]])
    }

    @Test("a WATCH= folder removed then made again is watched again (next reading)")
    func recreatedFolderArmedAgain() async throws {
        let scratch = try ScratchFolder()
        let folder = scratch.url.appendingPathComponent("state")
        let file = folder.appendingPathComponent("account")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        let watcher = ScriptedFolders()
        let account = AccountModel(runner: watchingLab(file.path), watcher: watcher)
        await account.refresh()
        #expect(watcher.watched.count == 1)
        // Keep the old folder's inode taken, so the new folder cannot reuse it.
        let moved = scratch.url.appendingPathComponent("state-old")
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PLAN=trial\n".write(to: file, atomically: false, encoding: .utf8)
        await account.refresh()
        #expect(watcher.watched.count == 2)
        // Nothing changed since: not armed a third time.
        await account.refresh()
        #expect(watcher.watched.count == 2)
    }
}

// MARK: `lab app account` and `lab app ginkgo`, contract v1.1

/// `lab app account` v1.1 for a Mac activated by a lifetime licence key, before the accounts:
/// every key present, empty when lab does not know it yet.
let lifetimeKeyAccount = """
PROTOCOL=1
SIGNED_IN=no
ACTIVATION=key
EMAIL=
ROLE=
PLAN=lifetime
PERIOD=
STATE=active
TRIAL_DAYS_LEFT=
RENEWS=
ENDS=
SEATS=
CHECKED=2026-11-28T08:00:00Z
WATCH=/Users/camille/.lab/cache/entitlements
OFFER_TRIAL_DAYS=14
OFFER_MONTH=39.50
OFFER_YEAR=390
OFFER_CURRENCY=EUR
OFFER_TAX=included

"""

@Suite("Reading lab app account, contract v1.1")
struct AccountReadingV11Tests {
    private func snapshot(_ text: String) -> AccountSnapshot? {
        if case let .contract(snapshot) = AccountContract.reading(from: ok(text)) { return snapshot }
        return nil
    }

    @Test("a lifetime key on a Mac not signed in: ACTIVATION=key, PLAN=lifetime, empty keys unknown")
    func lifetimeKey() throws {
        let account = try #require(snapshot(lifetimeKeyAccount))
        #expect(!account.signedIn)
        #expect(account.activation == .key)
        #expect(account.plan == .lifetime)
        #expect(account.standing == .active)
        #expect(account.role == nil && account.period == nil && account.email == nil)
        #expect(account.trialDaysLeft == nil && account.renews == nil && account.ends == nil && account.seats == nil)
        #expect(account.watch == ["/Users/camille/.lab/cache/entitlements"])
        #expect(account.isSubscribed)
        #expect(account.offer.month == Decimal(string: "39.50"))
    }

    @Test("a subscription: PLAN=subscription with PERIOD=month|year, ROLE=owner|member, ACTIVATION=account")
    func subscription() throws {
        let yearly = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nACTIVATION=account\nEMAIL=a@b.fr\nROLE=owner\nPLAN=subscription\nPERIOD=year\nSTATE=active\nRENEWS=2027-11-28\nENDS=\nSEATS=3\n"))
        #expect(yearly.plan == .subscription && yearly.period == .year)
        #expect(yearly.role == .owner && yearly.activation == .account)
        #expect(yearly.renews == AccountDay(year: 2027, month: 11, day: 28) && yearly.ends == nil)
        #expect(yearly.seats == 3 && yearly.isSubscribed)
        let member = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nROLE=member\nPLAN=subscription\nPERIOD=month\nSTATE=active\n"))
        #expect(member.role == .member && member.period == .month)
        let over = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=subscription\nPERIOD=month\nSTATE=ended\nRENEWS=\nENDS=2026-12-01\n"))
        #expect(!over.isSubscribed)
    }

    @Test("unknown rights are said unknown; an empty, missing or new value is never guessed")
    func unknownNeverGuessed() throws {
        let unread = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=no\nACTIVATION=key\nPLAN=unknown\nSTATE=unknown\n"))
        #expect(unread.plan == .unknown && unread.standing == .unknown)
        let empty = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=no\nACTIVATION=\nROLE=\nPLAN=\nPERIOD=\nSTATE=\n"))
        #expect(empty.plan == nil && empty.standing == nil && empty.activation == nil && empty.role == nil && empty.period == nil)
        let newer = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nACTIVATION=chip\nROLE=admin\nPLAN=team\nPERIOD=week\nSTATE=paused\n"))
        #expect(newer.plan == nil && newer.standing == nil && newer.activation == nil && newer.role == nil && newer.period == nil)
        #expect(!newer.isSubscribed)
        // v1 words are not v1.1's: never read as a plan.
        #expect(try #require(snapshot("PROTOCOL=1\nSIGNED_IN=yes\nPLAN=monthly\nSTATE=active\n")).plan == nil)
    }

    @Test("OFFER_* missing (rc 0): still the contract, no price known")
    func offerMissing() throws {
        let account = try #require(snapshot("PROTOCOL=1\nSIGNED_IN=no\nACTIVATION=none\nPLAN=none\nSTATE=none\n"))
        #expect(account.activation == AccountActivation.none)
        #expect(account.offer == AccountOffer() && !account.offer.isComplete)
    }
}

@Suite("Ginkgo's settings written, contract v1.1")
@MainActor
struct GinkgoSettingsV11Tests {
    @Test("after --listen lab says APPLIES=next-open: Ginkgo takes it the next time it opens")
    func appliesNextOpen() async {
        let lab = currentLab { command in
            guard command.arguments.prefix(2) == ["app", "ginkgo"], command.arguments.count == 4 else { return nil }
            if command.arguments[2] == "--listen" { return ok("LISTEN=\(command.arguments[3])\nSPEAK=always\nQUIET=21:00-08:00\nAPPLIES=next-open\n") }
            return ok("LISTEN=command\nSPEAK=\(command.arguments[3])\nQUIET=21:00-08:00\nAPPLIES=now\n")
        }
        let account = AccountModel(runner: lab, watcher: ScriptedFolders())
        await account.refresh()
        await account.setListening(.name)
        #expect(account.notice == .savedForNextOpen)
        #expect(account.ginkgo.listen == .name)
        await account.setSpeech(.never)
        #expect(account.notice == .saved)
    }
}
