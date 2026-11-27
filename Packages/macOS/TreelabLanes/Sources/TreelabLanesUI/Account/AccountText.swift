import Foundation

// Every text of the welcome, the settings window and the account entry (lot 11), localized from
// the package catalog: French with "tu", English, and the other languages of the catalog. One
// property per key; a text with a value takes it as an argument (a count selects its plural).
// Names stay verbatim on screen and have no key: Treelab, Claude, OpenAI, Stripe, Ginkgo, HUD, Feed.

/// The texts of the lot-11 screens.
struct AccountText: Sendable {
    private func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value, bundle: .module)
    }

    /// « Compte Treelab »
    var accountBarTitle: String { t("treelab.account.bar.title", "Treelab account") }
    /// « Ouvrir le compte et les réglages »
    var accountBarOpen: String { t("treelab.account.bar.open", "Open account and settings") }
    /// « Essai gratuit · %lld jours restants »
    func accountBarTrialDays(_ a: Int) -> String {
        String(localized: "treelab.account.bar.trialDays", defaultValue: "Free trial · \(a) days left", bundle: .module)
    }
    /// « Essai gratuit »
    var accountBarTrial: String { t("treelab.account.bar.trial", "Free trial") }
    /// « Essai terminé · abonne-toi »
    var accountBarTrialEnded: String { t("treelab.account.bar.trialEnded", "Trial over · subscribe") }
    /// « Abonné · au mois »
    var accountBarMonthly: String { t("treelab.account.bar.monthly", "Subscribed · monthly") }
    /// « Abonné · à l’année »
    var accountBarYearly: String { t("treelab.account.bar.yearly", "Subscribed · yearly") }
    /// « Propriétaire · rien à payer »
    var accountBarOwner: String { t("treelab.account.bar.owner", "Owner · nothing to pay") }
    /// « Paiement en attente »
    var accountBarUnpaid: String { t("treelab.account.bar.unpaid", "Payment pending") }
    /// « Abonnement terminé »
    var accountBarEnded: String { t("treelab.account.bar.ended", "Subscription over") }
    /// « Pas connecté · essai gratuit »
    var accountBarSignedOut: String { t("treelab.account.bar.signedOut", "Not signed in · free trial") }
    /// « Réglages »
    var accountBarSettings: String { t("treelab.account.bar.settings", "Settings") }
    /// « Compte et réglages »
    var settingsWindow: String { t("treelab.settings.window", "Account and settings") }
    /// « RÉGLAGES »
    var settingsHeader: String { t("treelab.settings.header", "SETTINGS") }
    /// « Sections des réglages »
    var settingsSections: String { t("treelab.settings.sections", "Settings sections") }
    /// « Compte et abonnement »
    var settingsAccount: String { t("treelab.settings.account", "Account and subscription") }
    /// « Essai, formule, postes, factures »
    var settingsAccountDetail: String { t("treelab.settings.account.detail", "Trial, plan, seats, invoices") }
    /// « Confidentialité et sécurité »
    var settingsPrivacy: String { t("treelab.settings.privacy", "Privacy and security") }
    /// « Ce qui sort du Mac, Ginkgo, clé »
    var settingsPrivacyDetail: String { t("treelab.settings.privacy.detail", "What leaves the Mac, Ginkgo, key") }
    /// « Apparence »
    var settingsAppearance: String { t("treelab.settings.appearance", "Appearance") }
    /// « Thème, mouvement, langue »
    var settingsAppearanceDetail: String { t("treelab.settings.appearance.detail", "Theme, motion, language") }
    /// « Lecture de ton compte… »
    var settingsReading: String { t("treelab.settings.reading", "Reading your account…") }
    /// « ARRIVE AVEC LA PROCHAINE VERSION DE TREELAB »
    var settingsNextVersionTitle: String { t("treelab.settings.nextVersion.title", "COMING WITH THE NEXT TREELAB VERSION") }
    /// « Ton compte arrive avec la prochaine version de treelab. S’abonner et ta clé OpenAI marchent déjà. »
    var settingsNextVersionAccount: String { t("treelab.settings.nextVersion.account", "Your account comes with the next version of treelab. Subscribing and your OpenAI key already work.") }
    /// « Ce réglage arrive avec la prochaine version de treelab. »
    var settingsNextVersionSetting: String { t("treelab.settings.nextVersion.setting", "This setting comes with the next version of treelab.") }
    /// « Treelab ne trouve pas lab sur ce Mac. »
    var settingsLabMissing: String { t("treelab.settings.labMissing", "Treelab cannot find lab on this Mac.") }
    /// « Annuler »
    var settingsCancel: String { t("treelab.settings.cancel", "Cancel") }
    /// « Lien envoyé à %@. Ouvre-le sur ce Mac pour te connecter. »
    func accountNoticeLinkSent(_ a: String) -> String {
        String(localized: "treelab.account.notice.linkSent", defaultValue: "Link sent to \(a). Open it on this Mac to sign in.", bundle: .module)
    }
    /// « Déconnecté partout, ce Mac compris. »
    var accountNoticeSignedOut: String { t("treelab.account.notice.signedOut", "Signed out everywhere, this Mac included.") }
    /// « La page sécurisée de Stripe s’ouvre dans ton navigateur. »
    var accountNoticeStripe: String { t("treelab.account.notice.stripe", "Stripe’s secure page opens in your browser.") }
    /// « Ton compte est celui du propriétaire : rien à payer. »
    var accountNoticeOwner: String { t("treelab.account.notice.owner", "Yours is the owner’s account: nothing to pay.") }
    /// « Ta licence actuelle reste valable : rien à payer pour l’instant. »
    var accountNoticeLegacy: String { t("treelab.account.notice.legacy", "Your current licence stays valid: nothing to pay for now.") }
    /// « Rien à ouvrir pour l’instant. »
    var accountNoticeNothing: String { t("treelab.account.notice.nothing", "Nothing to open for now.") }
    /// « Clé rangée dans le trousseau du Mac. »
    var accountNoticeKeyStored: String { t("treelab.account.notice.keyStored", "Key stored in the Mac’s keychain.") }
    /// « Enregistré. »
    var accountNoticeSaved: String { t("treelab.account.notice.saved", "Saved.") }
    /// « Copie de tes données écrite dans le dossier « %@ ». »
    func accountNoticeExported(_ a: String) -> String {
        String(localized: "treelab.account.notice.exported", defaultValue: "Copy of your data written to the folder “\(a)”.", bundle: .module)
    }
    /// « Tes données sur ce Mac sont effacées. »
    var accountNoticeErased: String { t("treelab.account.notice.erased", "Your data on this Mac is erased.") }
    /// « lab a refusé, rien n’a changé : %@ »
    func accountNoticeRefused(_ a: String) -> String {
        String(localized: "treelab.account.notice.refused", defaultValue: "lab refused, nothing changed: \(a)", bundle: .module)
    }
    /// « Arrive avec la prochaine version de treelab : rien n’est parti. »
    var accountNoticeNextVersion: String { t("treelab.account.notice.nextVersion", "Comes with the next version of treelab: nothing was sent.") }
    /// « Treelab ne trouve pas lab sur ce Mac : rien n’est parti. »
    var accountNoticeLabMissing: String { t("treelab.account.notice.labMissing", "Treelab cannot find lab on this Mac: nothing was sent.") }
    /// « Cette adresse ne va pas : vérifie-la. »
    var accountNoticeInvalidEmail: String { t("treelab.account.notice.invalidEmail", "That address won’t do: check it.") }
    /// « Colle ta clé OpenAI sur une seule ligne. »
    var accountNoticeInvalidKey: String { t("treelab.account.notice.invalidKey", "Paste your OpenAI key on one line.") }
    /// « Les heures calmes vont d’une heure à une autre. »
    var accountNoticeInvalidQuiet: String { t("treelab.account.notice.invalidQuiet", "Quiet hours go from one time to another.") }
    /// « Ce dossier ne peut pas servir : choisis-en un autre. »
    var accountNoticeInvalidFolder: String { t("treelab.account.notice.invalidFolder", "This folder can’t be used: pick another one.") }
    /// « Montrer dans le Finder »
    var accountShowInFinder: String { t("treelab.account.showInFinder", "Show in Finder") }
    /// « TON COMPTE »
    var accountCardAccount: String { t("treelab.account.card.account", "YOUR ACCOUNT") }
    /// « connexion par lien e-mail, sans mot de passe »
    var accountSignedInDetail: String { t("treelab.account.signedInDetail", "sign-in by e-mail link, no password") }
    /// « Déconnecter partout »
    var accountSignOutEverywhere: String { t("treelab.account.signOutEverywhere", "Sign out everywhere") }
    /// « Ferme toutes les sessions de ton compte, ce Mac compris. »
    var accountSignOutEverywhereDetail: String { t("treelab.account.signOutEverywhere.detail", "Closes every session of your account, this Mac included.") }
    /// « Déconnecter partout ? »
    var accountSignOutEverywhereConfirm: String { t("treelab.account.signOutEverywhere.confirm", "Sign out everywhere?") }
    /// « Pas encore connecté. »
    var accountSignedOut: String { t("treelab.account.signedOut", "Not signed in yet.") }
    /// « Ton e-mail »
    var accountEmail: String { t("treelab.account.email", "Your e-mail") }
    /// « Recevoir le lien de connexion »
    var accountSendLink: String { t("treelab.account.sendLink", "Get the sign-in link") }
    /// « Pas de mot de passe : un lien à usage unique arrive dans ta boîte. L’essai gratuit de %lld jours démarre à ta première connexion, sans carte. »
    func accountSignInDetailDays(_ a: Int) -> String {
        String(localized: "treelab.account.signInDetail.days", defaultValue: "No password: a one-time link arrives in your inbox. The \(a)-day free trial starts at your first sign-in, no card needed.", bundle: .module)
    }
    /// « Pas de mot de passe : un lien à usage unique arrive dans ta boîte. L’essai gratuit démarre à ta première connexion, sans carte. »
    var accountSignInDetail: String { t("treelab.account.signInDetail", "No password: a one-time link arrives in your inbox. The free trial starts at your first sign-in, no card needed.") }
    /// « TES POSTES »
    var accountCardSeats: String { t("treelab.account.card.seats", "YOUR SEATS") }
    /// « %lld postes »
    func accountSeats(_ a: Int) -> String {
        String(localized: "treelab.account.seats", defaultValue: "\(a) seats", bundle: .module)
    }
    /// « Postes pas encore connus »
    var accountSeatsUnknown: String { t("treelab.account.seats.unknown", "Seats not known yet") }
    /// « Un poste = un Mac. Tu en ajoutes depuis la page de l’abonnement. »
    var accountSeatsDetail: String { t("treelab.account.seats.detail", "One seat = one Mac. You add seats from the subscription page.") }
    /// « ABONNEMENT »
    var accountCardSubscription: String { t("treelab.account.card.subscription", "SUBSCRIPTION") }
    /// « Essai gratuit »
    var accountPlanTrial: String { t("treelab.account.plan.trial", "Free trial") }
    /// « %lld jours restants »
    func accountPlanDaysLeft(_ a: Int) -> String {
        String(localized: "treelab.account.plan.daysLeft", defaultValue: "\(a) days left", bundle: .module)
    }
    /// « Essai terminé »
    var accountPlanTrialEnded: String { t("treelab.account.plan.trialEnded", "Trial over") }
    /// « Abonnement au mois »
    var accountPlanMonthly: String { t("treelab.account.plan.monthly", "Monthly subscription") }
    /// « Abonnement à l’année »
    var accountPlanYearly: String { t("treelab.account.plan.yearly", "Yearly subscription") }
    /// « Propriétaire : rien à payer »
    var accountPlanOwner: String { t("treelab.account.plan.owner", "Owner: nothing to pay") }
    /// « Pas d’abonnement »
    var accountPlanNone: String { t("treelab.account.plan.none", "No subscription") }
    /// « Paiement en attente : mets ta carte à jour sur la page de Stripe. »
    var accountPlanUnpaid: String { t("treelab.account.plan.unpaid", "Payment pending: update your card on Stripe’s page.") }
    /// « Abonnement terminé »
    var accountPlanEnded: String { t("treelab.account.plan.ended", "Subscription over") }
    /// « Se renouvelle le %@ »
    func accountPlanRenews(_ a: String) -> String {
        String(localized: "treelab.account.plan.renews", defaultValue: "Renews on \(a)", bundle: .module)
    }
    /// « Se termine le %@ »
    func accountPlanEnds(_ a: String) -> String {
        String(localized: "treelab.account.plan.ends", defaultValue: "Ends on \(a)", bundle: .module)
    }
    /// « Rien n’est prélevé à la fin de l’essai. Pour continuer, choisis ta formule : »
    var accountTrialNoCharge: String { t("treelab.account.trialNoCharge", "Nothing is charged when the trial ends. To go on, pick your plan:") }
    /// « Au mois »
    var accountOfferMonth: String { t("treelab.account.offer.month", "By the month") }
    /// « À l’année »
    var accountOfferYear: String { t("treelab.account.offer.year", "By the year") }
    /// « %@ par poste et par mois »
    func accountOfferPerMonth(_ a: String) -> String {
        String(localized: "treelab.account.offer.perMonth", defaultValue: "\(a) per seat per month", bundle: .module)
    }
    /// « %@ par poste et par an »
    func accountOfferPerYear(_ a: String) -> String {
        String(localized: "treelab.account.offer.perYear", defaultValue: "\(a) per seat per year", bundle: .module)
    }
    /// « Remise d’équipe : −%@ sur tous les postes dès %lld postes »
    func accountOfferDiscount(_ a: String, _ b: Int) -> String {
        String(localized: "treelab.account.offer.discount", defaultValue: "Team discount: −\(a) on every seat from \(b) seats", bundle: .module)
    }
    /// « toutes taxes comprises »
    var accountOfferTaxIncluded: String { t("treelab.account.offer.taxIncluded", "taxes included") }
    /// « Les prix sont sur la page de Stripe. »
    var accountOfferUnknown: String { t("treelab.account.offer.unknown", "Prices are shown on Stripe’s page.") }
    /// « S’abonner · paiement chez Stripe ↗ »
    var accountSubscribe: String { t("treelab.account.subscribe", "Subscribe · payment with Stripe ↗") }
    /// « Gérer l’abonnement et les factures ↗ »
    var accountManage: String { t("treelab.account.manage", "Manage subscription and invoices ↗") }
    /// « Tu tapes ta carte sur la page sécurisée de Stripe, dans ton navigateur : Treelab ne la voit jamais. »
    var accountCardOnStripe: String { t("treelab.account.cardOnStripe", "You type your card on Stripe’s secure page, in your browser: Treelab never sees it.") }
    /// « Arrête quand tu veux : ta version reste à toi. »
    var accountStopAnytime: String { t("treelab.account.stopAnytime", "Stop whenever you like: your version stays yours.") }
    /// « Les factures arrivent par e-mail et sur la page de Stripe. »
    var accountInvoices: String { t("treelab.account.invoices", "Invoices arrive by e-mail and on Stripe’s page.") }
    /// « CE QUI SORT DE TON MAC »
    var privacyCardLeaves: String { t("treelab.privacy.card.leaves", "WHAT LEAVES YOUR MAC") }
    /// « Vers »
    var privacyColumnTo: String { t("treelab.privacy.column.to", "To") }
    /// « Quoi »
    var privacyColumnWhat: String { t("treelab.privacy.column.what", "What") }
    /// « Quand »
    var privacyColumnWhen: String { t("treelab.privacy.column.when", "When") }
    /// « Ton e-mail et ton abonnement »
    var privacyTreelabWhat: String { t("treelab.privacy.treelab.what", "Your e-mail and your subscription") }
    /// « À la connexion et à chaque échéance »
    var privacyTreelabWhen: String { t("treelab.privacy.treelab.when", "When you sign in and at each renewal") }
    /// « Ce que tes couloirs lui montrent pour travailler »
    var privacyClaudeWhat: String { t("treelab.privacy.claude.what", "What your lanes show it to work") }
    /// « Quand un couloir travaille, avec ton compte Claude »
    var privacyClaudeWhen: String { t("treelab.privacy.claude.when", "When a lane works, with your Claude account") }
    /// « Ta voix, et ce que Ginkgo lit de tes couloirs pour te répondre »
    var privacyOpenaiWhat: String { t("treelab.privacy.openai.what", "Your voice, and what Ginkgo reads of your lanes to answer you") }
    /// « Seulement pendant une conversation, avec ta clé »
    var privacyOpenaiWhen: String { t("treelab.privacy.openai.when", "Only during a conversation, with your key") }
    /// « Ta carte, sur sa propre page »
    var privacyStripeWhat: String { t("treelab.privacy.stripe.what", "Your card, on its own page") }
    /// « Quand tu t’abonnes »
    var privacyStripeWhen: String { t("treelab.privacy.stripe.when", "When you subscribe") }
    /// « Personne d’autre »
    var privacyNobody: String { t("treelab.privacy.nobody", "No one else") }
    /// « Aucune mesure de ton usage, aucun pistage, aucun rapport d’erreur envoyé »
    var privacyNobodyWhat: String { t("treelab.privacy.nobody.what", "No usage measurement, no tracking, no error report sent") }
    /// « Jamais »
    var privacyNobodyWhen: String { t("treelab.privacy.nobody.when", "Never") }
    /// « GINKGO · QUAND IL ÉCOUTE »
    var privacyCardListen: String { t("treelab.privacy.card.listen", "GINKGO · WHEN IT LISTENS") }
    /// « Au clic »
    var privacyListenCommand: String { t("treelab.privacy.listen.command", "On click") }
    /// «  · par défaut »
    var privacyListenDefault: String { t("treelab.privacy.listen.default", " · default") }
    /// « Le micro s’ouvre quand tu cliques, et se ferme quand tu dis « stop » ou après un silence. »
    var privacyListenCommandDetail: String { t("treelab.privacy.listen.command.detail", "The microphone opens when you click, and closes when you say “stop” or after a silence.") }
    /// « Touche tenue ⌥ Espace »
    var privacyListenKey: String { t("treelab.privacy.listen.key", "Key held ⌥ Space") }
    /// « Ginkgo écoute tant que tu tiens la touche, pas une seconde de plus. »
    var privacyListenKeyDetail: String { t("treelab.privacy.listen.key.detail", "Ginkgo listens while you hold the key, not a second longer.") }
    /// « En disant « Ginkgo » »
    var privacyListenName: String { t("treelab.privacy.listen.name", "By saying “Ginkgo”") }
    /// « Son nom est reconnu sur ton Mac seul ; rien ne part chez OpenAI avant. »
    var privacyListenNameDetail: String { t("treelab.privacy.listen.name.detail", "Its name is recognized on your Mac alone; nothing goes to OpenAI before.") }
    /// « Le micro : Ginkgo te le demandera à ta première conversation, pour t’entendre. Treelab n’écoute jamais. »
    var privacyMicrophone: String { t("treelab.privacy.microphone", "The microphone: Ginkgo will ask you for it at your first conversation, to hear you. Treelab never listens.") }
    /// « GINKGO · QUAND IL PARLE »
    var privacyCardSpeak: String { t("treelab.privacy.card.speak", "GINKGO · WHEN IT SPEAKS") }
    /// « Quand un couloir se met à t’attendre, Ginkgo te l’annonce à voix haute : »
    var privacySpeakIntro: String { t("treelab.privacy.speak.intro", "When a lane starts waiting for you, Ginkgo says so out loud:") }
    /// « Toujours »
    var privacySpeakAlways: String { t("treelab.privacy.speak.always", "Always") }
    /// « En conversation »
    var privacySpeakConversation: String { t("treelab.privacy.speak.conversation", "In a conversation") }
    /// « Jamais »
    var privacySpeakNever: String { t("treelab.privacy.speak.never", "Never") }
    /// « Heures calmes »
    var privacyQuiet: String { t("treelab.privacy.quiet", "Quiet hours") }
    /// « de »
    var privacyQuietFrom: String { t("treelab.privacy.quiet.from", "from") }
    /// « à »
    var privacyQuietTo: String { t("treelab.privacy.quiet.to", "to") }
    /// « Rien à voix haute pendant ces heures. »
    var privacyQuietDetail: String { t("treelab.privacy.quiet.detail", "Nothing out loud during these hours.") }
    /// « Enregistrer les heures calmes »
    var privacyQuietSave: String { t("treelab.privacy.quiet.save", "Save the quiet hours") }
    /// « TA CLÉ OPENAI »
    var privacyCardKey: String { t("treelab.privacy.card.key", "YOUR OPENAI KEY") }
    /// « Rangée dans le trousseau du Mac »
    var privacyKeyPresent: String { t("treelab.privacy.key.present", "Stored in the Mac’s keychain") }
    /// « Pas encore de clé »
    var privacyKeyAbsent: String { t("treelab.privacy.key.absent", "No key yet") }
    /// « État de la clé inconnu »
    var privacyKeyUnknown: String { t("treelab.privacy.key.unknown", "Key status not known") }
    /// « Remplacer »
    var privacyKeyReplace: String { t("treelab.privacy.key.replace", "Replace") }
    /// « Ajouter ma clé »
    var privacyKeyAdd: String { t("treelab.privacy.key.add", "Add my key") }
    /// « Colle ta clé OpenAI »
    var privacyKeyField: String { t("treelab.privacy.key.field", "Paste your OpenAI key") }
    /// « Ranger au trousseau »
    var privacyKeyStore: String { t("treelab.privacy.key.store", "Store in the keychain") }
    /// « Ginkgo ne la lit que pour ouvrir une conversation, et ne l’envoie qu’à OpenAI. Treelab ne l’affiche jamais. »
    var privacyKeyDetail: String { t("treelab.privacy.key.detail", "Ginkgo reads it only to open a conversation, and sends it only to OpenAI. Treelab never shows it.") }
    /// « GARDE-FOUS, TOUJOURS ACTIFS »
    var privacyCardSafeguards: String { t("treelab.privacy.card.safeguards", "SAFEGUARDS, ALWAYS ON") }
    /// « Fermer un couloir demande ton « oui » à voix haute, dans les 120 secondes. Sans ton « oui », rien ne se passe. Ginkgo n’agit que sur ta demande. »
    var privacySafeguards: String { t("treelab.privacy.safeguards", "Closing a lane needs your spoken “yes”, within 120 seconds. Without your “yes”, nothing happens. Ginkgo acts only when you ask.") }
    /// « TES DONNÉES »
    var privacyCardData: String { t("treelab.privacy.card.data", "YOUR DATA") }
    /// « Exporter mes données… »
    var privacyExport: String { t("treelab.privacy.export", "Export my data…") }
    /// « Une copie lisible des données de Treelab et de lab, sans aucun secret. »
    var privacyExportDetail: String { t("treelab.privacy.export.detail", "A readable copy of Treelab’s and lab’s data, without any secret.") }
    /// « Exporter ici »
    var privacyExportPrompt: String { t("treelab.privacy.export.prompt", "Export here") }
    /// « Choisis le dossier où écrire la copie. »
    var privacyExportMessage: String { t("treelab.privacy.export.message", "Choose the folder to write the copy to.") }
    /// « Effacer mes données… »
    var privacyErase: String { t("treelab.privacy.erase", "Erase my data…") }
    /// « Efface les données de Treelab et de lab sur ce Mac ; ta clé OpenAI quitte le trousseau. Deux étapes : rien ne part sans ta confirmation. »
    var privacyEraseDetail: String { t("treelab.privacy.erase.detail", "Erases Treelab’s and lab’s data on this Mac; your OpenAI key leaves the keychain. Two steps: nothing goes without your confirmation.") }
    /// « lab va effacer : %@ »
    func privacyEraseReadback(_ a: String) -> String {
        String(localized: "treelab.privacy.erase.readback", defaultValue: "lab will erase: \(a)", bundle: .module)
    }
    /// « lab est prêt à effacer tes données sur ce Mac. »
    var privacyEraseReady: String { t("treelab.privacy.erase.ready", "lab is ready to erase your data on this Mac.") }
    /// « Effacer pour de bon »
    var privacyEraseConfirm: String { t("treelab.privacy.erase.confirm", "Erase for good") }
    /// « THÈME »
    var appearanceCardTheme: String { t("treelab.appearance.card.theme", "THEME") }
    /// « · choisi »
    var appearanceSelected: String { t("treelab.appearance.selected", "· selected") }
    /// « Traits lumineux sur fond nuit, mouvement léger. »
    var appearanceHudDetail: String { t("treelab.appearance.hud.detail", "Bright lines on a night background, light motion.") }
    /// « Noir »
    var appearanceBlack: String { t("treelab.appearance.black", "Black") }
    /// « · bientôt »
    var appearanceSoon: String { t("treelab.appearance.soon", "· soon") }
    /// « Plus sobre, plus noir. Il arrive dans une prochaine version. »
    var appearanceBlackDetail: String { t("treelab.appearance.black.detail", "Plainer, darker. It comes in a future version.") }
    /// « MOUVEMENT »
    var appearanceCardMotion: String { t("treelab.appearance.card.motion", "MOTION") }
    /// « Suit le réglage du Mac »
    var appearanceMotionFollow: String { t("treelab.appearance.motion.follow", "Follows the Mac’s setting") }
    /// « Aujourd’hui : animations permises. Si le Mac réduit les animations, Treelab les coupe, Ginkgo compris. »
    var appearanceMotionAllowed: String { t("treelab.appearance.motion.allowed", "Today: animations allowed. If the Mac reduces motion, Treelab turns them off, Ginkgo included.") }
    /// « Le Mac réduit les animations : Treelab les coupe, Ginkgo compris. »
    var appearanceMotionReduced: String { t("treelab.appearance.motion.reduced", "The Mac reduces motion: Treelab turns animations off, Ginkgo included.") }
    /// « Changer dans les Réglages Système »
    var appearanceMotionOpen: String { t("treelab.appearance.motion.open", "Change in System Settings") }
    /// « LANGUE »
    var appearanceCardLanguage: String { t("treelab.appearance.card.language", "LANGUAGE") }
    /// « Langue de Treelab : %@ »
    func appearanceLanguageCurrent(_ a: String) -> String {
        String(localized: "treelab.appearance.language.current", defaultValue: "Treelab’s language: \(a)", bundle: .module)
    }
    /// « Treelab suit la langue de ton Mac ; tu peux en choisir une autre pour Treelab seul. Ginkgo te répond dans la tienne. »
    var appearanceLanguageDetail: String { t("treelab.appearance.language.detail", "Treelab follows your Mac’s language; you can pick another one for Treelab alone. Ginkgo answers in yours.") }
    /// « Choisir dans les Réglages Système »
    var appearanceLanguageOpen: String { t("treelab.appearance.language.open", "Choose in System Settings") }
    /// « Accueil de Treelab »
    var welcomeMenu: String { t("treelab.welcome.menu", "Treelab welcome") }
    /// « Bienvenue dans Treelab »
    var welcomeTitle: String { t("treelab.welcome.title", "Welcome to Treelab") }
    /// « Treelab fait avancer tes projets avec Claude, chantier par chantier, et te dit seulement quand il a besoin de toi. Quatre mots à connaître : »
    var welcomeIntro: String { t("treelab.welcome.intro", "Treelab moves your projects forward with Claude, one piece of work at a time, and tells you only when it needs you. Four words to know:") }
    /// « Couloir »
    var welcomeWordLane: String { t("treelab.welcome.word.lane", "Lane") }
    /// « Un chantier de ton projet, avec son propre Claude. »
    var welcomeWordLaneDetail: String { t("treelab.welcome.word.lane.detail", "A piece of work in your project, with its own Claude.") }
    /// « Lot »
    var welcomeWordBatch: String { t("treelab.welcome.word.batch", "Batch") }
    /// « Une étape d’un couloir, de la question à la livraison. »
    var welcomeWordBatchDetail: String { t("treelab.welcome.word.batch.detail", "One step of a lane, from the question to the delivery.") }
    /// « Tour »
    var welcomeWordTower: String { t("treelab.welcome.word.tower", "Tower") }
    /// « Le veilleur qui livre et relance tes couloirs. »
    var welcomeWordTowerDetail: String { t("treelab.welcome.word.tower.detail", "The watcher that delivers and restarts your lanes.") }
    /// « Tout ce qui t’attend, une demande à la fois. »
    var welcomeWordFeedDetail: String { t("treelab.welcome.word.feed.detail", "Everything waiting for you, one request at a time.") }
    /// « Aucune mesure de ton usage, aucun pistage. Ton travail ne sort que vers Claude, et vers OpenAI quand tu parles à Ginkgo. »
    var welcomePrivacy: String { t("treelab.welcome.privacy", "No usage measurement, no tracking. Your work only leaves for Claude, and for OpenAI when you talk to Ginkgo.") }
    /// « ÉTAPE %lld SUR %lld »
    func welcomeStep(_ a: Int, _ b: Int) -> String {
        String(localized: "treelab.welcome.step", defaultValue: "STEP \(a) OF \(b)", bundle: .module)
    }
    /// « Tout se change plus tard, dans les réglages. »
    var welcomeChangeLater: String { t("treelab.welcome.changeLater", "Everything can be changed later, in the settings.") }
    /// « Plus tard »
    var welcomeLater: String { t("treelab.welcome.later", "Later") }
    /// « Continuer › »
    var welcomeContinue: String { t("treelab.welcome.continue", "Continue ›") }
    /// « ‹ Retour »
    var welcomeBack: String { t("treelab.welcome.back", "‹ Back") }
    /// « Entrer dans Treelab › »
    var welcomeEnter: String { t("treelab.welcome.enter", "Enter Treelab ›") }
    /// « Commencer › »
    var welcomeStart: String { t("treelab.welcome.start", "Start ›") }
    /// « FACULTATIF »
    var welcomeOptional: String { t("treelab.welcome.optional", "OPTIONAL") }
    /// « CONSEILLÉ »
    var welcomeRecommended: String { t("treelab.welcome.recommended", "RECOMMENDED") }
    /// « À TON CHOIX »
    var welcomeYourChoice: String { t("treelab.welcome.yourChoice", "YOUR CHOICE") }
    /// « Quatre étapes, deux minutes »
    var welcomeOverviewTitle: String { t("treelab.welcome.overview.title", "Four steps, two minutes") }
    /// « Bienvenue »
    var welcomeOverviewWelcome: String { t("treelab.welcome.overview.welcome", "Welcome") }
    /// « Ton compte »
    var welcomeOverviewAccount: String { t("treelab.welcome.overview.account", "Your account") }
    /// « Les notifications »
    var welcomeOverviewNotifications: String { t("treelab.welcome.overview.notifications", "Notifications") }
    /// « Les mots de Treelab, et ce qui sort de ton Mac. »
    var welcomeOverviewWelcomeDetail: String { t("treelab.welcome.overview.welcome.detail", "Treelab’s words, and what leaves your Mac.") }
    /// « Un essai gratuit, sans carte. »
    var welcomeOverviewAccountDetail: String { t("treelab.welcome.overview.account.detail", "A free trial, no card.") }
    /// « Ta voix pour piloter tes couloirs, si tu veux. »
    var welcomeOverviewGinkgoDetail: String { t("treelab.welcome.overview.ginkgo.detail", "Your voice to steer your lanes, if you want it.") }
    /// « Pour savoir quand un couloir t’attend. »
    var welcomeOverviewNotificationsDetail: String { t("treelab.welcome.overview.notifications.detail", "To know when a lane waits for you.") }
    /// « Ce qui sort de ton Mac, et vers qui › »
    var welcomeLeaves: String { t("treelab.welcome.leaves", "What leaves your Mac, and to whom ›") }
    /// « Ton compte, essai gratuit de %lld jours »
    func welcomeTrialTitleDays(_ a: Int) -> String {
        String(localized: "treelab.welcome.trial.titleDays", defaultValue: "Your account, \(a)-day free trial", bundle: .module)
    }
    /// « Ton compte, essai gratuit »
    var welcomeTrialTitle: String { t("treelab.welcome.trial.title", "Your account, free trial") }
    /// « Sans carte. Rien n’est prélevé à la fin de l’essai. »
    var welcomeTrialNoCard: String { t("treelab.welcome.trial.noCard", "No card. Nothing is charged when the trial ends.") }
    /// « Pourquoi ? Pour garder ton essai et ton abonnement sur chacun de tes Mac. Pas de mot de passe : un lien à usage unique arrive dans ta boîte. »
    var welcomeTrialWhy: String { t("treelab.welcome.trial.why", "Why? To keep your trial and your subscription on each of your Macs. No password: a one-time link arrives in your inbox.") }
    /// « Commencer l’essai »
    var welcomeTrialStart: String { t("treelab.welcome.trial.start", "Start the trial") }
    /// « Ensuite, si tu continues : %@ par mois ou %@ par an, par poste. »
    func welcomeTrialThen(_ a: String, _ b: String) -> String {
        String(localized: "treelab.welcome.trial.then", defaultValue: "Then, if you go on: \(a) a month or \(b) a year, per seat.", bundle: .module)
    }
    /// « Connecté : %@ »
    func welcomeTrialSignedIn(_ a: String) -> String {
        String(localized: "treelab.welcome.trial.signedIn", defaultValue: "Signed in: \(a)", bundle: .module)
    }
    /// « La connexion arrive avec la prochaine version de treelab. Tu peux déjà t’abonner depuis les réglages. »
    var welcomeTrialNextVersion: String { t("treelab.welcome.trial.nextVersion", "Signing in comes with the next version of treelab. You can already subscribe from the settings.") }
    /// « Ginkgo, ta voix pour piloter tes couloirs »
    var welcomeGinkgoTitle: String { t("treelab.welcome.ginkgo.title", "Ginkgo, your voice to steer your lanes") }
    /// « Ta clé OpenAI »
    var welcomeGinkgoKey: String { t("treelab.welcome.ginkgo.key", "Your OpenAI key") }
    /// « Rangée dans le trousseau du Mac par lab, jamais envoyée à Treelab. »
    var welcomeGinkgoKeyDetail: String { t("treelab.welcome.ginkgo.keyDetail", "Stored in the Mac’s keychain by lab, never sent to Treelab.") }
    /// « Pourquoi le micro ? »
    var welcomeGinkgoMicTitle: String { t("treelab.welcome.ginkgo.micTitle", "Why the microphone?") }
    /// « Pour que Ginkgo t’entende, seulement quand tu le décides. Ginkgo te le demandera à ta première conversation, pour t’entendre. Treelab n’écoute jamais. »
    var welcomeGinkgoMic: String { t("treelab.welcome.ginkgo.mic", "For Ginkgo to hear you, only when you decide. Ginkgo will ask you for it at your first conversation, to hear you. Treelab never listens.") }
    /// « Quand Ginkgo écoute »
    var welcomeGinkgoListenTitle: String { t("treelab.welcome.ginkgo.listenTitle", "When Ginkgo listens") }
    /// « Être prévenu quand un couloir attend »
    var welcomeNotificationsTitle: String { t("treelab.welcome.notifications.title", "Stay told when a lane waits") }
    /// « Pourquoi ? Pour savoir qu’un couloir t’attend, même quand Treelab est derrière une autre fenêtre. Seulement quand on a besoin de toi ; jamais de publicité. »
    var welcomeNotificationsWhy: String { t("treelab.welcome.notifications.why", "Why? To know a lane is waiting for you, even when Treelab is behind another window. Only when you’re needed; never ads.") }
    /// « Autoriser »
    var welcomeNotificationsAllow: String { t("treelab.welcome.notifications.allow", "Allow") }
    /// « Notifications autorisées. »
    var welcomeNotificationsAllowed: String { t("treelab.welcome.notifications.allowed", "Notifications allowed.") }
    /// « Notifications refusées : tu peux les autoriser dans Réglages Système › Notifications. »
    var welcomeNotificationsDenied: String { t("treelab.welcome.notifications.denied", "Notifications declined: you can allow them in System Settings › Notifications.") }
}
