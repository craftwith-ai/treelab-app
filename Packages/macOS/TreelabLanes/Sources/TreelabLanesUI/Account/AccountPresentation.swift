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

    /// The second line of the account entry at the bottom of the sidebar.
    func barLine(_ status: AccountStatus) -> String {
        guard case let .contract(account) = status else { return text.accountBarSettings }
        guard account.signedIn else { return text.accountBarSignedOut }
        switch (account.plan, account.standing) {
        case (_, .unpaid): return text.accountBarUnpaid
        case (.owner, _): return text.accountBarOwner
        case (.trial, .ended): return text.accountBarTrialEnded
        case (.trial, _): return account.trialDaysLeft.map(text.accountBarTrialDays) ?? text.accountBarTrial
        case (.monthly, .ended), (.yearly, .ended): return text.accountBarEnded
        case (.monthly, _): return text.accountBarMonthly
        case (.yearly, _): return text.accountBarYearly
        case (.none, _): return text.accountBarSignedOut
        }
    }

    /// The plan in one line, and the line under it (days left, renewal or end date).
    func plan(_ account: AccountSnapshot) -> (title: String, detail: String?) {
        if account.standing == .unpaid { return (text.accountPlanUnpaid, nil) }
        switch account.plan {
        case .trial:
            if account.standing == .ended { return (text.accountPlanTrialEnded, nil) }
            return (text.accountPlanTrial, account.trialDaysLeft.map(text.accountPlanDaysLeft))
        case .monthly, .yearly:
            if account.standing == .ended {
                return (text.accountPlanEnded, account.ends.flatMap(day).map(text.accountPlanEnds))
            }
            let title = account.plan == .monthly ? text.accountPlanMonthly : text.accountPlanYearly
            if let renews = account.renews.flatMap(day) { return (title, text.accountPlanRenews(renews)) }
            return (title, account.ends.flatMap(day).map(text.accountPlanEnds))
        case .owner:
            return (text.accountPlanOwner, nil)
        case .none:
            return (text.accountPlanNone, nil)
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
