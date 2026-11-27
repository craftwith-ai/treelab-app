import AppKit
import SwiftUI
import TreelabAccount

/// The welcome, at Treelab's first launch (plan "Accueil · première ouverture" of the accepted
/// mock-up): Treelab's words on the left; four steps on the right — welcome, the free trial
/// without a card, Ginkgo (key, microphone, listening), notifications — each with its reason and
/// "Later".
struct TreelabWelcomeView: View {
    /// The number of steps.
    nonisolated static let stepCount = 4

    let model: AccountModel
    @Bindable var state: AccountWindowsState
    let notifications: any NotificationPermissionAsking
    let finish: () -> Void
    let openPrivacy: () -> Void
    private let palette = HUDPalette()

    var body: some View {
        GeometryReader { proxy in
            let size = AccountScreenSize(width: proxy.size.width)
            HStack(spacing: 0) {
                WelcomeColumn(openPrivacy: openPrivacy)
                    .frame(width: size.leftColumn)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(palette.bar)
                Rectangle().fill(palette.line).frame(width: 1)
                WelcomeSteps(model: model, state: state, notifications: notifications, finish: finish)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .environment(\.accountScreenSize, size)
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .onExitCommand(perform: finish)
    }
}

/// Welcome, what Treelab does, its four words, and what leaves the Mac.
private struct WelcomeColumn: View {
    let openPrivacy: () -> Void
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: size.isLarge ? 22 : 16) {
                TreelabMark(side: size.isLarge ? 80 : 60)
                Text(text.welcomeTitle).font(.system(size: size.title, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(text.welcomeIntro).font(.system(size: size.body)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    word(text.welcomeWordLane, text.welcomeWordLaneDetail)
                    word(text.welcomeWordBatch, text.welcomeWordBatchDetail)
                    word(text.welcomeWordTower, text.welcomeWordTowerDetail)
                    word("Feed", text.welcomeWordFeedDetail)
                }
                Rectangle().fill(palette.line).frame(height: 1)
                HUDNote(text: text.welcomePrivacy)
                Button(action: openPrivacy) {
                    Text(text.welcomeLeaves).font(.system(size: size.body, weight: .semibold)).foregroundStyle(palette.cyan)
                }
                .buttonStyle(.plain)
            }
            .padding(size.padding)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func word(_ name: String, _ meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name).font(.system(size: size.body, weight: .bold)).foregroundStyle(palette.cyan)
            Text(meaning).font(.system(size: size.body)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the welcome's footer offers at a step: "Back" from the second step, "Later" (which skips
/// the step, or closes the welcome), then "Start", "Continue" or, on the last step, "Enter".
struct WelcomeFooter: Equatable {
    /// What "Later" does.
    enum Later: Equatable { case skipsStep, closes }

    let back: Bool
    let later: Later
    let isLast: Bool

    init(step: Int, count: Int = TreelabWelcomeView.stepCount) {
        back = step > 1
        isLast = step >= count
        later = isLast || step <= 1 ? .closes : .skipsStep
    }
}

/// The step shown, its place among the four, and the buttons to move on.
private struct WelcomeSteps: View {
    let model: AccountModel
    @Bindable var state: AccountWindowsState
    let notifications: any NotificationPermissionAsking
    let finish: () -> Void
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        let step = state.welcomeStep
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text.welcomeStep(step, TreelabWelcomeView.stepCount))
                    .font(.system(size: size.small, weight: .semibold)).tracking(1.6).foregroundStyle(palette.textSecondary)
                StepIndicator(step: step)
                HUDNote(text: text.welcomeChangeLater)
            }
            .padding(.horizontal, size.padding)
            .padding(.top, 34)
            .padding(.bottom, 16)
            Rectangle().fill(palette.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: size.cardSpacing) {
                    switch step {
                    case 1: OverviewStep()
                    case 2: TrialStep(model: model)
                    case 3: GinkgoStep(model: model)
                    default: NotificationsStep(notifications: notifications)
                    }
                    AccountNoticeLine(model: model)
                }
                .padding(size.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(palette.line).frame(height: 1)
            let footer = WelcomeFooter(step: step)
            HStack(spacing: 12) {
                if footer.back {
                    Button(text.welcomeBack) { go(step - 1) }.buttonStyle(HUDSecondaryButtonStyle())
                }
                Spacer(minLength: 12)
                switch footer.later {
                case .skipsStep: Button(text.welcomeLater) { go(step + 1) }.buttonStyle(HUDSecondaryButtonStyle())
                case .closes: Button(text.welcomeLater, action: finish).buttonStyle(HUDSecondaryButtonStyle())
                }
                if footer.isLast {
                    Button(text.welcomeEnter, action: finish).buttonStyle(HUDPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                } else {
                    Button(step == 1 ? text.welcomeStart : text.welcomeContinue) { go(step + 1) }
                        .buttonStyle(HUDPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, size.padding)
            .padding(.vertical, 14)
            .background(palette.bar)
        }
    }

    private func go(_ step: Int) {
        model.clearNotice()
        state.welcomeStep = min(max(step, 1), TreelabWelcomeView.stepCount)
    }
}

/// The four steps by name, the current one lit.
private struct StepIndicator: View {
    let step: Int
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        let names = [text.welcomeOverviewWelcome, text.welcomeOverviewAccount, "Ginkgo", text.welcomeOverviewNotifications]
        HStack(spacing: 8) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                let number = index + 1
                let current = number == step
                HStack(spacing: 6) {
                    Text(verbatim: "\(number)")
                        .font(.system(size: size.small, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(current ? palette.cyan : (number < step ? palette.cardRaised : Color.clear), in: Circle())
                        .foregroundStyle(current ? palette.background : palette.text)
                        .overlay(Circle().stroke(current ? palette.cyan : palette.lineBright))
                    Text(verbatim: name).font(.system(size: size.small, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? palette.text : palette.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(current ? [.isSelected] : [])
                if number < names.count {
                    Rectangle().fill(palette.line).frame(width: 18, height: 1).accessibilityHidden(true)
                }
            }
        }
    }
}

/// A step's title, with its tag ("OPTIONAL", "RECOMMENDED").
private struct StepTitle: View {
    let title: String
    var tag: String? = nil
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tag {
                Text(tag).font(.system(size: size.small, weight: .semibold)).tracking(1.6).foregroundStyle(palette.amber)
            }
            Text(title).font(.system(size: size.heading + 4, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Step 1: the four steps ahead, and the promise about what leaves the Mac.
private struct OverviewStep: View {
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        StepTitle(title: text.welcomeOverviewTitle)
        VStack(alignment: .leading, spacing: 10) {
            row(1, text.welcomeOverviewWelcome, text.welcomeOverviewWelcomeDetail)
            row(2, text.welcomeOverviewAccount, text.welcomeOverviewAccountDetail)
            row(3, "Ginkgo", text.welcomeOverviewGinkgoDetail)
            row(4, text.welcomeOverviewNotifications, text.welcomeOverviewNotificationsDetail)
        }
        HUDCard(title: text.privacyCardLeaves, accent: palette.cyan) {
            HUDNote(text: text.welcomePrivacy, color: palette.text)
        }
    }

    private func row(_ number: Int, _ name: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)").font(.system(size: size.body, weight: .bold)).foregroundStyle(palette.cyan).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.system(size: size.body, weight: .semibold))
                Text(detail).font(.system(size: size.small)).foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Step 2: the free trial without a card, by e-mail; or the account as it stands.
private struct TrialStep: View {
    let model: AccountModel
    @State private var email = ""
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()
    private let presentation = AccountPresentation()

    var body: some View {
        let offer = model.snapshot?.offer
        StepTitle(title: offer?.trialDays.map(text.welcomeTrialTitleDays) ?? text.welcomeTrialTitle)
        HUDNote(text: text.welcomeTrialNoCard, color: palette.text)
        HUDCard(title: text.accountCardAccount) {
            switch model.status {
            case let .contract(account) where account.signedIn:
                Text(text.welcomeTrialSignedIn(account.email ?? "—")).font(.system(size: size.body, weight: .semibold))
                let plan = presentation.plan(account)
                Text(plan.detail.map { "\(plan.title) · \($0)" } ?? plan.title)
                    .font(.system(size: size.body)).foregroundStyle(palette.cyan)
            case .contract:
                SignInForm(model: model, email: $email, button: text.welcomeTrialStart)
            case .unknown:
                HUDNote(text: text.settingsReading)
            case .nextVersion, .labMissing:
                HUDNote(text: text.welcomeTrialNextVersion, color: palette.amber)
            }
            if let offer, offer.isComplete, let month = presentation.price(offer.month, currency: offer.currency),
               let year = presentation.price(offer.year, currency: offer.currency) {
                HUDNote(text: text.welcomeTrialThen(month, year))
                if offer.taxIncluded { HUDNote(text: text.accountOfferTaxIncluded) }
            }
        }
        HUDNote(text: text.welcomeTrialWhy)
    }
}

/// Step 3: Ginkgo — the OpenAI key on standard input, the microphone and its reason, the listening mode.
private struct GinkgoStep: View {
    let model: AccountModel
    @State private var listening = GinkgoListening.standard
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        StepTitle(title: text.welcomeGinkgoTitle, tag: text.welcomeOptional)
        HUDCard(title: text.welcomeGinkgoKey) {
            OpenAIKeyCard(model: model, compact: true)
        }
        HUDCard(title: text.welcomeGinkgoMicTitle) {
            HUDNote(text: text.welcomeGinkgoMic, color: palette.text)
        }
        HUDCard(title: text.welcomeGinkgoListenTitle) {
            ListeningChoices(model: model, local: $listening)
        }
    }
}

/// Step 4: notifications, asked only when the person clicks "Allow".
private struct NotificationsStep: View {
    let notifications: any NotificationPermissionAsking
    @State private var permission = NotificationPermissionState.unknown
    @Environment(\.accountScreenSize) private var size
    private let palette = HUDPalette()
    private let text = AccountText()

    var body: some View {
        StepTitle(title: text.welcomeNotificationsTitle, tag: text.welcomeRecommended)
        HUDCard(title: text.welcomeOverviewNotifications) {
            HUDNote(text: text.welcomeNotificationsWhy, color: palette.text)
            switch permission {
            case .allowed:
                Label(text.welcomeNotificationsAllowed, systemImage: "checkmark.circle")
                    .font(.system(size: size.body, weight: .semibold)).foregroundStyle(palette.cyan)
            case .denied:
                HUDNote(text: text.welcomeNotificationsDenied, color: palette.amber)
            case .notAsked, .unknown:
                Button(text.welcomeNotificationsAllow) {
                    Task { permission = await notifications.request() }
                }
                .buttonStyle(HUDPrimaryButtonStyle())
            }
        }
        .task { permission = await notifications.current() }
    }
}
