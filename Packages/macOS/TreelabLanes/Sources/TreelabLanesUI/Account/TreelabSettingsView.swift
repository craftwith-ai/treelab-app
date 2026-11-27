import AppKit
import SwiftUI
import TreelabAccount

/// Treelab's settings window ("Account and settings", plans "Réglages" of the accepted mock-up):
/// the three sections on the left, the chosen one on the right. Escape closes the window.
struct TreelabSettingsView: View {
    let model: AccountModel
    @Bindable var state: AccountWindowsState
    let close: () -> Void
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        GeometryReader { proxy in
            let size = AccountScreenSize(width: proxy.size.width)
            VStack(spacing: 0) {
                SettingsHeader(model: model, section: state.section)
                Rectangle().fill(palette.line).frame(height: 1)
                HStack(spacing: 0) {
                    SettingsNavigation(state: state)
                        .frame(width: size.navigation)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(palette.bar)
                    Rectangle().fill(palette.line).frame(width: 1)
                    ScrollView {
                        VStack(alignment: .leading, spacing: size.cardSpacing) {
                            AccountNoticeLine(model: model)
                            switch state.section {
                            case .account: AccountSettingsSection(model: model, width: proxy.size.width - size.navigation - 2 * size.padding)
                            case .privacy: PrivacySettingsSection(model: model, width: proxy.size.width - size.navigation - 2 * size.padding)
                            case .appearance: AppearanceSettingsSection()
                            }
                        }
                        .padding(size.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .environment(\.accountScreenSize, size)
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .onExitCommand(perform: close)
        .onChange(of: state.section) { model.clearNotice() }
    }
}

/// SETTINGS, the section's name and the account's e-mail, under the window's buttons.
private struct SettingsHeader: View {
    let model: AccountModel
    let section: TreelabSettingsSection
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(text.settingsHeader).font(.system(size: size.heading, weight: .bold)).tracking(3)
                .accessibilityAddTraits(.isHeader)
            Text(SettingsNavigation.name(section)).font(.system(size: size.body)).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            if let email = model.snapshot?.email, model.snapshot?.signedIn == true {
                Text(verbatim: email).font(.system(size: size.small)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, size.padding)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .background(palette.bar)
    }
}

/// The three sections, each with its line of detail.
private struct SettingsNavigation: View {
    @Bindable var state: AccountWindowsState
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    static func name(_ section: TreelabSettingsSection) -> String {
        let text = AccountText()
        switch section {
        case .account: return text.settingsAccount
        case .privacy: return text.settingsPrivacy
        case .appearance: return text.settingsAppearance
        }
    }

    static func detail(_ section: TreelabSettingsSection) -> String {
        let text = AccountText()
        switch section {
        case .account: return text.settingsAccountDetail
        case .privacy: return text.settingsPrivacyDetail
        case .appearance: return text.settingsAppearanceDetail
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TreelabSettingsSection.allCases) { section in
                let selected = state.section == section
                Button {
                    state.section = section
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.name(section)).font(.system(size: size.body, weight: .semibold)).foregroundStyle(palette.text)
                        Text(Self.detail(section)).font(.system(size: size.small)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? palette.cardRaised : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? palette.cyan.opacity(0.8) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AccountText().settingsSections)
    }
}

/// The outcome of the person's last action, in cyan, or in red for a problem.
struct AccountNoticeLine: View {
    let model: AccountModel
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        if let notice = model.notice {
            let said = AccountPresentation().notice(notice)
            HStack(spacing: 10) {
                Image(systemName: said.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(said.isProblem ? palette.red : palette.cyan)
                    .accessibilityHidden(true)
                Text(said.text).font(.system(size: size.body)).foregroundStyle(said.isProblem ? palette.red : palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if case let .exported(path) = notice {
                    Button(AccountText().accountShowInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(HUDSecondaryButtonStyle())
                }
            }
            .padding(12)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(said.isProblem ? palette.red.opacity(0.7) : palette.cyan.opacity(0.6)))
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Comes with the next treelab version", or "lab cannot be found", for a section that needs the contract.
struct AccountUnavailableCard: View {
    let model: AccountModel
    let message: String
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        switch model.status {
        case .labMissing:
            HUDCard(title: text.settingsNextVersionTitle, accent: palette.amber) { HUDNote(text: text.settingsLabMissing, color: palette.text) }
        case .unknown:
            HUDNote(text: text.settingsReading)
        case .nextVersion:
            HUDCard(title: text.settingsNextVersionTitle, accent: palette.amber) { HUDNote(text: message, color: palette.text) }
        case .contract:
            EmptyView()
        }
    }
}

/// Two columns when the section is wide enough, one otherwise.
struct SettingsColumns<Left: View, Right: View>: View {
    let width: CGFloat
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right
    @Environment(\.accountScreenSize) private var size

    var body: some View {
        if width >= 720 {
            HStack(alignment: .top, spacing: size.cardSpacing) {
                VStack(alignment: .leading, spacing: size.cardSpacing) { left() }.frame(maxWidth: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: size.cardSpacing) { right() }.frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: size.cardSpacing) {
                left()
                right()
            }
        }
    }
}

// MARK: Account and subscription

/// Account, seats and subscription: prices from treelab's offer, payment on Stripe's page.
struct AccountSettingsSection: View {
    let model: AccountModel
    let width: CGFloat
    @Environment(\.accountScreenSize) private var size
    private let text = AccountText()

    var body: some View {
        if let account = model.snapshot {
            SettingsColumns(width: width) {
                AccountCard(model: model, account: account)
                // Seats belong to a signed-in account.
                if account.signedIn { SeatsCard(account: account) }
            } right: {
                SubscriptionCard(model: model, account: account)
            }
        } else {
            AccountUnavailableCard(model: model, message: text.settingsNextVersionAccount)
            if model.status == .nextVersion {
                SubscriptionCard(model: model, account: nil)
            }
        }
    }
}

/// YOUR ACCOUNT: the e-mail and "Sign out everywhere", or the e-mail field and the sign-in link.
private struct AccountCard: View {
    let model: AccountModel
    let account: AccountSnapshot
    @State private var email = ""
    @State private var confirming = false
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.accountCardAccount) {
            if account.signedIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: account.email ?? "—").font(.system(size: size.big, weight: .semibold)).textSelection(.enabled)
                    HUDNote(text: text.accountSignedInDetail)
                }
                Button(text.accountSignOutEverywhere) { confirming = true }
                    .buttonStyle(HUDSecondaryButtonStyle(danger: true))
                    .disabled(model.isBusy)
                    .confirmationDialog(text.accountSignOutEverywhereConfirm, isPresented: $confirming) {
                        Button(text.accountSignOutEverywhere, role: .destructive) { Task { await model.signOutEverywhere() } }
                        Button(text.settingsCancel, role: .cancel) {}
                    } message: {
                        Text(text.accountSignOutEverywhereDetail)
                    }
                HUDNote(text: text.accountSignOutEverywhereDetail)
            } else {
                Text(text.accountSignedOut).font(.system(size: size.body, weight: .semibold))
                SignInForm(model: model, email: $email, button: text.accountSendLink)
                HUDNote(text: account.offer.trialDays.map(text.accountSignInDetailDays) ?? text.accountSignInDetail)
            }
        }
    }
}

/// The e-mail field and its button: the address goes to lab as typed, in one piece.
struct SignInForm: View {
    let model: AccountModel
    @Binding var email: String
    let button: String
    @Environment(\.accountScreenSize) private var size
    private let text = AccountText()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.accountEmail).font(.system(size: size.small, weight: .medium)).foregroundStyle(HUDPalette().textSecondary)
            HStack(spacing: 10) {
                TextField(text.accountEmail, text: $email)
                    .textContentType(.emailAddress)
                    .hudField()
                    .onSubmit(send)
                    .accessibilityLabel(text.accountEmail)
                Button(button, action: send)
                    .buttonStyle(HUDPrimaryButtonStyle())
                    .disabled(model.isBusy || email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func send() {
        let typed = email
        Task { await model.signIn(email: typed) }
    }
}

/// YOUR SEATS: one seat per Mac.
private struct SeatsCard: View {
    let account: AccountSnapshot
    @Environment(\.accountScreenSize) private var size
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.accountCardSeats) {
            Text(account.seats.map(text.accountSeats) ?? text.accountSeatsUnknown).font(.system(size: size.big, weight: .semibold))
            HUDNote(text: text.accountSeatsDetail)
        }
    }
}

/// SUBSCRIPTION: the plan, the offer's prices, and lab subscribe (Stripe's page) to subscribe or manage.
struct SubscriptionCard: View {
    let model: AccountModel
    let account: AccountSnapshot?
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()
    private let presentation = AccountPresentation()

    var body: some View {
        HUDCard(title: text.accountCardSubscription) {
            if let account {
                let plan = presentation.plan(account)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.system(size: size.big, weight: .semibold))
                        .foregroundStyle(account.standing == .unpaid ? palette.amber : palette.text)
                    if let detail = plan.detail {
                        Text(detail).font(.system(size: size.body, weight: .medium))
                            .foregroundStyle(account.plan == .trial ? palette.cyan : palette.textSecondary)
                    }
                }
                if !account.isSubscribed {
                    if account.plan == .trial { HUDNote(text: text.accountTrialNoCharge) }
                    OfferRows(offer: account.offer)
                }
            } else {
                HUDNote(text: text.accountOfferUnknown)
            }
            let subscribed = account?.isSubscribed == true
            Button(subscribed ? text.accountManage : text.accountSubscribe) { Task { await model.subscribe() } }
                .buttonStyle(HUDPrimaryButtonStyle())
                .disabled(model.isBusy || model.status == .unknown)
            HUDNote(text: text.accountCardOnStripe)
            HUDNote(text: text.accountInvoices)
            HUDNote(text: text.accountStopAnytime, color: palette.cyan)
        }
    }
}

/// The two plans with treelab's prices per seat, the team discount and the taxes, all from lab.
private struct OfferRows: View {
    let offer: AccountOffer
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()
    private let presentation = AccountPresentation()

    var body: some View {
        if offer.isComplete, let month = presentation.price(offer.month, currency: offer.currency),
           let year = presentation.price(offer.year, currency: offer.currency) {
            VStack(alignment: .leading, spacing: 8) {
                row(text.accountOfferMonth, text.accountOfferPerMonth(month))
                row(text.accountOfferYear, text.accountOfferPerYear(year))
                if let percent = offer.discountPercent, let from = offer.discountFromSeats {
                    HUDNote(text: text.accountOfferDiscount(presentation.percent(percent), from), color: palette.text)
                }
                if offer.taxIncluded { HUDNote(text: text.accountOfferTaxIncluded) }
            }
        } else {
            HUDNote(text: text.accountOfferUnknown)
        }
    }

    private func row(_ name: String, _ price: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.system(size: size.body, weight: .semibold))
            Spacer(minLength: 12)
            Text(price).font(.system(size: size.body)).foregroundStyle(palette.textSecondary)
        }
        .padding(10)
        .background(palette.bar, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.line))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Privacy and security

/// What leaves the Mac and to whom, Ginkgo's listening and speech, the OpenAI key, the spoken
/// "yes", export and erase.
struct PrivacySettingsSection: View {
    let model: AccountModel
    let width: CGFloat
    @Environment(\.accountScreenSize) private var size

    var body: some View {
        LeavesCard()
        SettingsColumns(width: width) {
            ListeningCard(model: model)
            SpeechCard(model: model)
        } right: {
            OpenAIKeyCard(model: model)
            SafeguardsCard()
            DataCard(model: model)
        }
    }
}

/// WHAT LEAVES YOUR MAC: to whom, what and when; no one else.
private struct LeavesCard: View {
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.privacyCardLeaves) {
            Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    header(text.privacyColumnTo)
                    header(text.privacyColumnWhat)
                    header(text.privacyColumnWhen)
                }
                Divider().overlay(palette.line).gridCellUnsizedAxes(.horizontal)
                row("Treelab", text.privacyTreelabWhat, text.privacyTreelabWhen)
                row("Claude", text.privacyClaudeWhat, text.privacyClaudeWhen)
                row("OpenAI", text.privacyOpenaiWhat, text.privacyOpenaiWhen)
                row("Stripe", text.privacyStripeWhat, text.privacyStripeWhen)
                GridRow {
                    Text(text.privacyNobody).font(.system(size: size.body, weight: .semibold)).foregroundStyle(palette.cyan)
                    cell(text.privacyNobodyWhat, palette.cyan)
                    cell(text.privacyNobodyWhen, palette.cyan)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: size.small, weight: .semibold)).foregroundStyle(palette.textSecondary)
    }

    private func cell(_ value: String, _ color: Color? = nil) -> some View {
        Text(value).font(.system(size: size.body)).foregroundStyle(color ?? palette.text).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ name: String, _ what: String, _ when: String) -> some View {
        GridRow {
            Text(verbatim: name).font(.system(size: size.body, weight: .semibold))
            cell(what)
            cell(when, palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The three listening modes, "On click" by default.
struct ListeningChoices: View {
    let model: AccountModel
    /// The choice kept by the welcome while lab cannot save it yet.
    var local: Binding<GinkgoListening>? = nil
    private let text = AccountText()

    var body: some View {
        let current = model.speaksContract ? (model.ginkgo.listen ?? .standard) : (local?.wrappedValue ?? .standard)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GinkgoListening.allCases, id: \.self) { mode in
                HUDChoiceRow(
                    name: name(mode),
                    mark: mode == .standard ? text.privacyListenDefault : "",
                    detail: detail(mode),
                    isSelected: current == mode
                ) {
                    if model.speaksContract {
                        Task { await model.setListening(mode) }
                    } else if let local {
                        local.wrappedValue = mode
                    }
                }
                .disabled(model.isBusy || (!model.speaksContract && local == nil))
            }
            if !model.speaksContract { HUDNote(text: text.settingsNextVersionSetting, color: HUDPalette().amber) }
        }
    }

    private func name(_ mode: GinkgoListening) -> String {
        switch mode {
        case .command: text.privacyListenCommand
        case .key: text.privacyListenKey
        case .name: text.privacyListenName
        }
    }

    private func detail(_ mode: GinkgoListening) -> String {
        switch mode {
        case .command: text.privacyListenCommandDetail
        case .key: text.privacyListenKeyDetail
        case .name: text.privacyListenNameDetail
        }
    }
}

/// GINKGO · WHEN IT LISTENS, and why it needs the microphone.
private struct ListeningCard: View {
    let model: AccountModel
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.privacyCardListen) {
            ListeningChoices(model: model)
            HUDNote(text: text.privacyMicrophone)
        }
    }
}

/// GINKGO · WHEN IT SPEAKS: always, in a conversation or never; quiet hours.
struct SpeechCard: View {
    /// Speech options on one row of the card.
    nonisolated static let optionsPerRow = 3

    /// Width left to an option's name in the Privacy section of a settings window `windowWidth`
    /// points wide: the navigation and its divider, the page's paddings, the second of two columns,
    /// the card's paddings, the spacings between the options, then the option's paddings, its
    /// circle and the spacing after it (HUDChoiceRow).
    nonisolated static func optionNameWidth(windowWidth: CGFloat) -> CGFloat {
        let size = AccountScreenSize(width: windowWidth)
        let section = windowWidth - size.navigation - 1 - 2 * size.padding
        let column = section >= 720 ? (section - size.cardSpacing) / 2 : section
        let card = column - 2 * (size.isLarge ? 20 : 16)
        let option = (card - 8 * CGFloat(optionsPerRow - 1)) / CGFloat(optionsPerRow)
        return option - 2 * 10 - 16 - 12
    }

    let model: AccountModel
    @State private var quietOn = true
    @State private var from = SpeechCard.time("21:00")
    @State private var to = SpeechCard.time("08:00")
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        let enabled = model.speaksContract && !model.isBusy
        HUDCard(title: text.privacyCardSpeak) {
            HUDNote(text: text.privacySpeakIntro, color: palette.text)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: Self.optionsPerRow),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(GinkgoSpeech.allCases, id: \.self) { mode in
                    HUDChoiceRow(name: name(mode), isSelected: (model.ginkgo.speak ?? .always) == mode) {
                        Task { await model.setSpeech(mode) }
                    }
                }
            }
            .disabled(!enabled)
            Toggle(text.privacyQuiet, isOn: $quietOn)
                .toggleStyle(.switch)
                .font(.system(size: size.body, weight: .semibold))
                .disabled(!enabled)
                .onChange(of: quietOn) { _, on in
                    if !on, model.ginkgo.quiet != .off { Task { await model.setQuiet("off") } }
                }
            if quietOn {
                HStack(spacing: 8) {
                    Text(text.privacyQuietFrom).font(.system(size: size.body))
                    DatePicker(text.privacyQuietFrom, selection: $from, displayedComponents: .hourAndMinute).labelsHidden()
                    Text(text.privacyQuietTo).font(.system(size: size.body))
                    DatePicker(text.privacyQuietTo, selection: $to, displayedComponents: .hourAndMinute).labelsHidden()
                    Spacer(minLength: 0)
                }
                .disabled(!enabled)
                Button(text.privacyQuietSave) {
                    let range = "\(Self.clock(from))-\(Self.clock(to))"
                    Task { await model.setQuiet(range) }
                }
                .buttonStyle(HUDSecondaryButtonStyle())
                .disabled(!enabled)
                HUDNote(text: text.privacyQuietDetail)
            }
            if !model.speaksContract { HUDNote(text: text.settingsNextVersionSetting, color: palette.amber) }
        }
        .onAppear(perform: load)
        .onChange(of: model.ginkgo) { load() }
    }

    private func load() {
        switch model.ginkgo.quiet {
        case .off: quietOn = false
        case let .hours(start, end):
            quietOn = true
            from = Self.time(start)
            to = Self.time(end)
        case nil: break
        }
    }

    private func name(_ mode: GinkgoSpeech) -> String {
        switch mode {
        case .always: text.privacySpeakAlways
        case .conversation: text.privacySpeakConversation
        case .never: text.privacySpeakNever
        }
    }

    /// `HH:MM` as today's date at that time, for the time pickers.
    static func time(_ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(hour: parts.first ?? 0, minute: parts.count > 1 ? parts[1] : 0)
        return Calendar.current.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    /// A date's time as `HH:MM`.
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// YOUR OPENAI KEY: present or absent only, never shown; replaced through lab, on standard input.
struct OpenAIKeyCard: View {
    let model: AccountModel
    var compact = false
    @State private var editing = false
    @State private var key = ""
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: model.key == .present ? "key.fill" : "key")
                    .foregroundStyle(model.key == .present ? palette.cyan : palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if model.key == .present {
                        Text(verbatim: "•••• •••• ••••").font(.system(size: size.body, design: .monospaced)).accessibilityHidden(true)
                    }
                    Text(status).font(.system(size: size.small)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 8)
                if !editing {
                    Button(model.key == .present ? text.privacyKeyReplace : text.privacyKeyAdd) { editing = true }
                        .buttonStyle(HUDSecondaryButtonStyle())
                }
            }
            if editing {
                SecureField(text.privacyKeyField, text: $key)
                    .hudField()
                    .onSubmit(store)
                    .accessibilityLabel(text.privacyKeyField)
                HStack(spacing: 10) {
                    Button(text.privacyKeyStore, action: store)
                        .buttonStyle(HUDPrimaryButtonStyle())
                        .disabled(model.isBusy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(text.settingsCancel) {
                        key = ""
                        editing = false
                    }
                    .buttonStyle(HUDSecondaryButtonStyle())
                }
            }
            HUDNote(text: compact ? text.welcomeGinkgoKeyDetail : text.privacyKeyDetail)
        }
        if compact {
            content
        } else {
            HUDCard(title: text.privacyCardKey) { content }
        }
    }

    private var status: String {
        switch model.key {
        case .present: text.privacyKeyPresent
        case .absent: text.privacyKeyAbsent
        case .unknown: text.privacyKeyUnknown
        }
    }

    private func store() {
        // The field is emptied at once: the key lives only for the call that hands it to lab.
        let pasted = key
        key = ""
        editing = false
        Task { await model.storeOpenAIKey(pasted) }
    }
}

/// SAFEGUARDS, ALWAYS ON: the spoken "yes" within 120 seconds.
private struct SafeguardsCard: View {
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.privacyCardSafeguards) { HUDNote(text: text.privacySafeguards, color: HUDPalette().text) }
    }
}

/// YOUR DATA: export to a folder the person picks; erase in two steps.
private struct DataCard: View {
    let model: AccountModel
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        let enabled = model.speaksContract && !model.isBusy
        HUDCard(title: text.privacyCardData) {
            Button(text.privacyExport, action: export)
                .buttonStyle(HUDSecondaryButtonStyle())
                .disabled(!enabled)
            HUDNote(text: text.privacyExportDetail)
            if let pending = model.pendingErase {
                VStack(alignment: .leading, spacing: 8) {
                    HUDNote(text: pending.readback.isEmpty ? text.privacyEraseReady : text.privacyEraseReadback(pending.readback), color: palette.amber)
                    HStack(spacing: 10) {
                        Button(text.privacyEraseConfirm) { Task { await model.confirmErase() } }
                            .buttonStyle(HUDSecondaryButtonStyle(danger: true))
                            .disabled(model.isBusy)
                        Button(text.settingsCancel) { model.cancelErase() }
                            .buttonStyle(HUDSecondaryButtonStyle())
                    }
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.red.opacity(0.6)))
            } else {
                Button(text.privacyErase) { Task { await model.beginErase() } }
                    .buttonStyle(HUDSecondaryButtonStyle(danger: true))
                    .disabled(!enabled)
            }
            HUDNote(text: text.privacyEraseDetail)
            if !model.speaksContract { HUDNote(text: text.settingsNextVersionSetting, color: palette.amber) }
        }
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = text.privacyExportPrompt
        panel.message = text.privacyExportMessage
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await model.exportData(to: folder) }
    }
}

// MARK: Appearance

/// The HUD theme chosen ("Black" soon, not selectable), motion that follows the Mac, the language.
struct AppearanceSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        HUDCard(title: text.appearanceCardTheme) {
            HStack(alignment: .top, spacing: size.cardSpacing) {
                ThemeOption(name: "HUD", mark: text.appearanceSelected, markColor: palette.cyan, detail: text.appearanceHudDetail,
                            selected: true, available: true, background: palette.background, line: palette.cyan)
                ThemeOption(name: text.appearanceBlack, mark: text.appearanceSoon, markColor: palette.amber, detail: text.appearanceBlackDetail,
                            selected: false, available: false, background: .black, line: Color(white: 0.55))
            }
        }
        HUDCard(title: text.appearanceCardMotion) {
            HUDChoiceRow(
                name: text.appearanceMotionFollow,
                detail: reduceMotion ? text.appearanceMotionReduced : text.appearanceMotionAllowed,
                isSelected: true
            ) {}
            Button(text.appearanceMotionOpen) { open("x-apple.systempreferences:com.apple.Accessibility-Settings.extension") }
                .buttonStyle(HUDSecondaryButtonStyle())
        }
        HUDCard(title: text.appearanceCardLanguage) {
            Text(text.appearanceLanguageCurrent(Self.languageName())).font(.system(size: size.big, weight: .semibold))
            HUDNote(text: text.appearanceLanguageDetail)
            Button(text.appearanceLanguageOpen) { open("x-apple.systempreferences:com.apple.Localization-Settings.extension") }
                .buttonStyle(HUDSecondaryButtonStyle())
        }
    }

    /// The language Treelab is shown in, named in that language ("français").
    static func languageName() -> String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code) ?? code
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One theme: a small preview, its name, its mark and a line of detail.
private struct ThemeOption: View {
    let name: String
    let mark: String
    let markColor: Color
    let detail: String
    let selected: Bool
    let available: Bool
    let background: Color
    let line: Color
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(background)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(line.opacity(0.9)).frame(width: 60, height: 6)
                    RoundedRectangle(cornerRadius: 2).fill(line.opacity(0.5)).frame(width: 90, height: 6)
                    RoundedRectangle(cornerRadius: 2).fill(line.opacity(0.3)).frame(width: 40, height: 6)
                }
                .padding(12)
            }
            .frame(height: size.isLarge ? 110 : 80)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(line.opacity(0.6)))
            .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(name).font(.system(size: size.body, weight: .semibold))
                Text(mark).font(.system(size: size.body)).foregroundStyle(markColor)
            }
            HUDNote(text: detail)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.cardRaised : palette.bar, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? palette.cyan : palette.line))
        .opacity(available ? 1 : 0.75)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
