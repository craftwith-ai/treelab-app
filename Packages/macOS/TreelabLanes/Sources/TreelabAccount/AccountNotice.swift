import TreelabLanes

/// Where the account stands for Treelab.
public enum AccountStatus: Sendable, Equatable {
    /// Not read yet.
    case unknown
    /// lab speaks the contract: the account as it stands.
    case contract(AccountSnapshot)
    /// lab does not speak the contract yet: it comes with the next treelab version; nothing is
    /// launched (subscribing and the OpenAI key already work).
    case nextVersion
    /// lab is missing or could not run; its words.
    case labMissing(String)
}

/// What `lab subscribe` opened (`SUBSCRIBE=`).
public enum SubscribeOutcome: String, Sendable, Equatable {
    /// Stripe's page to subscribe.
    case checkout
    /// Stripe's page to manage the subscription and see the invoices.
    case portal
    /// The owner's account: nothing to pay.
    case owner
    /// Stripe's page to renew.
    case renew
    /// An earlier licence that stays valid: nothing to pay now.
    case legacy
    /// Nothing to open.
    case none
    /// A value this Treelab does not know.
    case other
}

/// The outcome of the person's last action, said on screen.
public enum AccountNotice: Sendable, Equatable {
    /// The sign-in link was sent to that address.
    case linkSent(email: String)
    /// Every session of the account was closed, this Mac included.
    case signedOutEverywhere
    /// lab opened Stripe's page (or said there is nothing to pay).
    case subscribeOpened(SubscribeOutcome)
    /// The OpenAI key is in the keychain.
    case keyStored
    /// A setting of Ginkgo was saved.
    case saved
    /// lab wrote the export there.
    case exported(path: String)
    /// The local data was erased.
    case erased
    /// lab refused, in its words (code 2 and `REASON=`, or its error line).
    case refused(String)
    /// The action needs the next treelab version: nothing was sent.
    case nextVersion
    /// lab is missing or could not run: nothing was sent.
    case labMissing(String)
    /// The address typed is not one lab could take as is: nothing was sent.
    case invalidEmail
    /// The key pasted is empty or on several lines: nothing was sent.
    case invalidKey
    /// The quiet hours are not `HH:MM` to `HH:MM`: nothing was sent.
    case invalidQuietHours
    /// The folder chosen cannot be passed to lab: nothing was sent.
    case invalidFolder
}

/// How lab refused an action.
public enum LabRefusal: Sendable, Equatable {
    /// `REASON=unsupported`: this lab cannot do it yet (the next treelab version).
    case unsupported
    /// Any other refusal, in lab's clear words.
    case said(String)
}

/// The first step of an erase, waiting for the person's confirmation.
public struct PendingErase: Sendable, Equatable {
    /// What lab says will be erased (`READBACK=`), in its words.
    public let readback: String
    /// The token to send back (`TOKEN=`).
    let token: LabEraseToken
}
