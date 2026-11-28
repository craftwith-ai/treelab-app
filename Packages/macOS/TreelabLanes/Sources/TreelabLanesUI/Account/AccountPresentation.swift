import Foundation
import TreelabAccount

/// What the account screens say, worked out from the model's state: lines, prices from treelab's
/// offer (never written in the app), the outcome of the last action.
struct AccountPresentation: Sendable {
    private let text = AccountText()
    private let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// The second line of the account entry at the bottom of the sidebar: the plan first, since a
    /// Mac activated by a licence key is not signed in before the accounts (v1.1).
    func barLine(_ status: AccountStatus) -> String {
        guard case let .contract(account) = status else { return text.accountBarSettings }
        if account.standing == .unpaid { return text.accountBarUnpaid }
        switch account.plan {
        case .lifetime: return text.accountBarLifetime
        case .subscription:
            if account.standing == .ended { return text.accountBarEnded }
            switch account.period {
            case .month: return text.accountBarMonthly
            case .year: return text.accountBarYearly
            case nil: return text.accountBarSubscription
            }
        case .trial:
            if account.standing == .ended { return text.accountBarTrialEnded }
            return account.trialDaysLeft.map(text.accountBarTrialDays) ?? text.accountBarTrial
        case .unknown, nil: return text.accountBarUnknown
        case .some(.none): return account.signedIn ? text.accountBarNone : text.accountBarSignedOut
        }
    }

    /// Whether the account screens pitch the free trial and the prices after it: never to a Mac that
    /// already pays or has nothing more to pay (``AccountSnapshot/isSubscribed``: a running
    /// subscription, a lifetime licence). `nil` (lab not answering the contract yet) keeps the trial.
    func offersTrial(_ account: AccountSnapshot?) -> Bool {
        account?.isSubscribed != true
    }

    /// The title of the welcome's account step: the free trial, or the account alone once it pays.
    func welcomeAccountTitle(_ account: AccountSnapshot?) -> String {
        guard offersTrial(account) else { return text.welcomeOverviewAccount }
        return account?.offer.trialDays.map(text.welcomeTrialTitleDays) ?? text.welcomeTrialTitle
    }

    /// The line under the settings' sign-in field: the one-time link and the trial it starts, never
    /// a trial promised to a Mac that pays.
    func signInDetail(_ account: AccountSnapshot) -> String? {
        guard offersTrial(account) else { return nil }
        return account.offer.trialDays.map(text.accountSignInDetailDays) ?? text.accountSignInDetail
    }

    /// The plan in one line, and the line under it (days left, renewal or end date).
    func plan(_ account: AccountSnapshot) -> (title: String, detail: String?) {
        if account.standing == .unpaid { return (text.accountPlanUnpaid, nil) }
        switch account.plan {
        case .trial:
            if account.standing == .ended { return (text.accountPlanTrialEnded, nil) }
            return (text.accountPlanTrial, account.trialDaysLeft.map(text.accountPlanDaysLeft))
        case .subscription:
            if account.standing == .ended {
                return (text.accountPlanEnded, account.ends.flatMap(day).map(text.accountPlanEnds))
            }
            let title = switch account.period {
            case .month: text.accountPlanMonthly
            case .year: text.accountPlanYearly
            case nil: text.accountPlanSubscription
            }
            if let renews = account.renews.flatMap(day) { return (title, text.accountPlanRenews(renews)) }
            return (title, account.ends.flatMap(day).map(text.accountPlanEnds))
        case .lifetime:
            return (text.accountPlanLifetime, nil)
        case .unknown, nil:
            return (text.accountPlanUnknown, text.accountPlanUnknownDetail)
        case .some(.none):
            return (text.accountPlanNone, nil)
        }
    }

    /// Who pays the seat, when the team does (`ROLE=member`).
    func roleLine(_ account: AccountSnapshot) -> String? {
        account.role == .member ? text.accountPlanMember : nil
    }

    /// The title of a section's card when lab cannot give the account: lab missing, or a lab
    /// before the contract. `nil` otherwise.
    func unavailableTitle(_ status: AccountStatus) -> String? {
        switch status {
        case .labMissing: text.settingsLabMissingTitle
        case .nextVersion: text.settingsNextVersionTitle
        case .unknown, .contract: nil
        }
    }

    /// The note under a setting or a step that needs the contract: lab missing is said as such,
    /// never as the next treelab version. `nil` while reading or when lab speaks the contract.
    /// - Parameters:
    ///   - status: where the account stands.
    ///   - nextVersion: what to say for a lab before the contract.
    func unavailableNote(_ status: AccountStatus, nextVersion: String) -> String? {
        switch status {
        case .labMissing: text.settingsLabMissing
        case .nextVersion: nextVersion
        case .unknown, .contract: nil
        }
    }

    /// A day in the person's language ("27 décembre 2026").
    func day(_ day: AccountDay) -> String? {
        day.date.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale)) }
    }

    /// A price of the offer in its currency and the person’s language ("12,50 $US", "$12.50").
    func price(_ amount: Decimal?, currency: String?) -> String? {
        guard let amount, let currency else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = amount == amount.rounded ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber)
    }

    /// The team discount in the person's language ("20 %"), without its sign.
    func percent(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: Double(value) / 100)) ?? String(value)
    }

    /// The outcome of the last action, and whether it is a problem (said in red).
    func notice(_ notice: AccountNotice) -> (text: String, isProblem: Bool) {
        switch notice {
        case let .linkSent(email): (text.accountNoticeLinkSent(email), false)
        case .signedOutEverywhere: (text.accountNoticeSignedOut, false)
        case let .subscribeOpened(outcome):
            switch outcome {
            case .checkout, .portal, .renew: (text.accountNoticeStripe, false)
            case .owner: (text.accountNoticeOwner, false)
            case .legacy: (text.accountNoticeLegacy, false)
            case .none, .other: (text.accountNoticeNothing, false)
            }
        case .keyStored: (text.accountNoticeKeyStored, false)
        case .saved: (text.accountNoticeSaved, false)
        case .savedForNextOpen: (text.accountNoticeSavedNextOpen, false)
        case let .exported(path): (text.accountNoticeExported((path as NSString).lastPathComponent), false)
        case .erased: (text.accountNoticeErased, false)
        case let .refused(reason): (text.accountNoticeRefused(reason), true)
        case .nextVersion: (text.accountNoticeNextVersion, true)
        case .labMissing: (text.accountNoticeLabMissing, true)
        case .invalidEmail: (text.accountNoticeInvalidEmail, true)
        case .invalidKey: (text.accountNoticeInvalidKey, true)
        case .invalidQuietHours: (text.accountNoticeInvalidQuiet, true)
        case .invalidFolder: (text.accountNoticeInvalidFolder, true)
        }
    }
}

private extension Decimal {
    /// The value without its decimals.
    var rounded: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }
}
