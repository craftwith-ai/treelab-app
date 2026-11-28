public import Foundation

/// The plan of the account (`PLAN=`, contract v1.1).
public enum AccountPlan: String, Sendable, Equatable, CaseIterable {
    /// The free trial.
    case trial
    /// A paid subscription, by the month or the year (``AccountPeriod``).
    case subscription
    /// A right without end (a one-time purchase, a pilot key): nothing more to pay.
    case lifetime
    /// A licence is there, its rights not read yet by lab.
    case unknown
    /// No plan.
    case none
}

/// How a subscription is paid (`PERIOD=`, empty until the accounts).
public enum AccountPeriod: String, Sendable, Equatable, CaseIterable {
    /// Paid by the month.
    case month
    /// Paid by the year.
    case year
}

/// The person's role in the account (`ROLE=`, empty without an account).
public enum AccountRole: String, Sendable, Equatable, CaseIterable {
    /// Manages the billing.
    case owner
    /// Invited: the team pays the seat.
    case member
}

/// What activates this Mac (`ACTIVATION=`).
public enum AccountActivation: String, Sendable, Equatable, CaseIterable {
    /// A licence key.
    case key
    /// The signed-in account.
    case account
    /// Nothing.
    case none
}

/// Where the account stands (`STATE=`).
public enum AccountStanding: String, Sendable, Equatable, CaseIterable {
    /// Paid and running.
    case active
    /// In its free trial.
    case trial
    /// The trial or the subscription has ended.
    case ended
    /// A payment failed (with the accounts).
    case unpaid
    /// Not read yet by lab.
    case unknown
    /// Nothing to say.
    case none
}

/// A day lab wrote as `YYYY-MM-DD` (`RENEWS=`, `ENDS=`).
public struct AccountDay: Sendable, Equatable {
    /// The year.
    public let year: Int
    /// The month, 1 to 12.
    public let month: Int
    /// The day, 1 to 31.
    public let day: Int

    /// Creates a day.
    /// - Parameters:
    ///   - year: the year.
    ///   - month: 1 to 12.
    ///   - day: 1 to 31.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads `YYYY-MM-DD`.
    /// - Parameter text: what lab wrote.
    /// - Returns: `nil` unless it is exactly a real calendar day in that form.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day as a date at noon in the Mac's time zone, for showing it in the person's language.
    public var date: Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

/// treelab's offer, read from lab (`OFFER_*`): Treelab writes no price of its own.
public struct AccountOffer: Sendable, Equatable {
    /// Days of the free trial (`OFFER_TRIAL_DAYS=`).
    public var trialDays: Int?
    /// The price of one seat for a month (`OFFER_MONTH=`).
    public var month: Decimal?
    /// The price of one seat for a year (`OFFER_YEAR=`).
    public var year: Decimal?
    /// The ISO 4217 currency code (`OFFER_CURRENCY=`, three capital letters).
    public var currency: String?
    /// Whether taxes are included (`OFFER_TAX=included`).
    public var taxIncluded: Bool
    /// The team discount, in percent (`OFFER_DISCOUNT_PCT=`).
    public var discountPercent: Int?
    /// The number of seats from which the discount applies (`OFFER_DISCOUNT_FROM=`).
    public var discountFromSeats: Int?

    /// Creates an offer; every value unknown by default.
    public init(
        trialDays: Int? = nil, month: Decimal? = nil, year: Decimal? = nil, currency: String? = nil,
        taxIncluded: Bool = false, discountPercent: Int? = nil, discountFromSeats: Int? = nil
    ) {
        self.trialDays = trialDays
        self.month = month
        self.year = year
        self.currency = currency
        self.taxIncluded = taxIncluded
        self.discountPercent = discountPercent
        self.discountFromSeats = discountFromSeats
    }

    /// Whether both prices and their currency are known, so they can be shown.
    public var isComplete: Bool { month != nil && year != nil && currency != nil }
}

/// What `lab app account` says, once it speaks the contract (`PROTOCOL=1`, v1.1). A value lab
/// leaves empty, or one this Treelab does not know, is `nil`: never guessed.
public struct AccountSnapshot: Sendable, Equatable {
    /// Whether this Mac is signed in (`SIGNED_IN=yes`); `no` until the accounts exist.
    public var signedIn: Bool
    /// What activates this Mac (`ACTIVATION=`).
    public var activation: AccountActivation?
    /// The account's e-mail (`EMAIL=`), shown only.
    public var email: String?
    /// The person's role (`ROLE=`).
    public var role: AccountRole?
    /// The plan (`PLAN=`).
    public var plan: AccountPlan?
    /// How the subscription is paid (`PERIOD=`).
    public var period: AccountPeriod?
    /// Where the account stands (`STATE=`).
    public var standing: AccountStanding?
    /// Days left in the trial (`TRIAL_DAYS_LEFT=`).
    public var trialDaysLeft: Int?
    /// When the subscription renews (`RENEWS=`).
    public var renews: AccountDay?
    /// When it ends (`ENDS=`).
    public var ends: AccountDay?
    /// The seats of the subscription (`SEATS=`), one per Mac.
    public var seats: Int?
    /// When lab last checked the rights, UTC (`CHECKED=`).
    public var checked: String?
    /// The files lab rewrites when the account changes (`WATCH=`), absolute paths.
    public var watch: [String]
    /// treelab's offer (`OFFER_*`, absent when lab lacks its offer file).
    public var offer: AccountOffer

    /// Creates a snapshot; signed out and empty by default.
    public init(
        signedIn: Bool = false, activation: AccountActivation? = nil, email: String? = nil, role: AccountRole? = nil,
        plan: AccountPlan? = AccountPlan.none, period: AccountPeriod? = nil, standing: AccountStanding? = AccountStanding.none,
        trialDaysLeft: Int? = nil, renews: AccountDay? = nil, ends: AccountDay? = nil, seats: Int? = nil,
        checked: String? = nil, watch: [String] = [], offer: AccountOffer = AccountOffer()
    ) {
        self.signedIn = signedIn
        self.activation = activation
        self.email = email
        self.role = role
        self.plan = plan
        self.period = period
        self.standing = standing
        self.trialDaysLeft = trialDaysLeft
        self.renews = renews
        self.ends = ends
        self.seats = seats
        self.checked = checked
        self.watch = watch
        self.offer = offer
    }

    /// Whether the account is subscribed or has a lifetime licence: "Manage" rather than "Subscribe".
    public var isSubscribed: Bool {
        switch plan {
        case .subscription: standing != .ended
        case .lifetime: true
        case .trial, .unknown, .some(.none), nil: false
        }
    }
}

/// What reading `lab app account` gave.
public enum AccountReading: Sendable, Equatable {
    /// lab speaks the contract: the account as it stands.
    case contract(AccountSnapshot)
    /// lab does not speak it yet (unknown command, a refusal or another protocol): the account
    /// comes with the next treelab version, and nothing is launched.
    case nextVersion
}
