public import Foundation
public import Observation
public import TreelabLanes

/// What the welcome and the settings observe: the account, Ginkgo's settings and whether the
/// OpenAI key is stored, all read from lab; and the person's actions, all done by lab.
///
/// Treelab speaks the account contract v1 only when lab says `PROTOCOL=1`; otherwise the account
/// comes with the next treelab version and nothing is launched, except what already works
/// (`lab subscribe`, the OpenAI key). A new reading is woken by the `WATCH=` file lab rewrites,
/// never by a timer. Nothing here opens a network connection: lab does.
///
/// ```swift
/// let account = AccountModel.live(home: home)
/// account.start()
/// await account.signIn(email: "camille@exemple.fr")
/// ```
@MainActor
@Observable
public final class AccountModel {
    /// Where the account stands.
    public private(set) var status: AccountStatus = .unknown
    /// Ginkgo's settings, as lab keeps them.
    public private(set) var ginkgo = GinkgoPreferences()
    /// Whether the OpenAI key is stored.
    public private(set) var key: OpenAIKeyPresence = .unknown
    /// The outcome of the last action.
    public private(set) var notice: AccountNotice?
    /// An action is under way: the buttons wait.
    public private(set) var isBusy = false
    /// The first step of an erase, waiting for the person's confirmation.
    public private(set) var pendingErase: PendingErase?

    @ObservationIgnored private let runner: (any LabCommandRunning)?
    @ObservationIgnored private let watcher: any FileEventWatching
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var watchedFiles: [String] = []
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    /// Creates the model.
    /// - Parameters:
    ///   - runner: runs lab's commands; `nil` when lab cannot be found.
    ///   - watcher: wakes a reading when the `WATCH=` file changes.
    public init(runner: (any LabCommandRunning)?, watcher: any FileEventWatching) {
        self.runner = runner
        self.watcher = watcher
    }

    /// Reads the account and follows its `WATCH=` file. Calling it again does nothing.
    public func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
    }

    /// The account, when lab speaks the contract.
    public var snapshot: AccountSnapshot? {
        if case let .contract(snapshot) = status { return snapshot }
        return nil
    }

    /// Whether lab speaks the account contract.
    public var speaksContract: Bool { snapshot != nil }

    /// Forgets the last outcome.
    public func clearNotice() {
        notice = nil
    }

    // MARK: Reading

    /// Reads the account, then Ginkgo's settings (contract only), then whether the key is stored.
    /// A reading asked while one runs is done once more right after it.
    public func refresh() async {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            await readOnce()
        } while refreshAgain
    }

    private func readOnce() async {
        guard let runner else {
            status = .labMissing("")
            follow([])
            return
        }
        do {
            switch AccountContract.reading(from: try await runner.run(.account)) {
            case let .contract(snapshot):
                status = .contract(snapshot)
                if let settings = AccountContract.ginkgo(from: try await runner.run(.ginkgoSettings)) {
                    ginkgo = settings
                }
                follow(snapshot.watch)
            case .nextVersion:
                status = .nextVersion
                follow([])
            }
            key = AccountContract.key(from: try await runner.run(.ginkgoStatus))
        } catch {
            status = .labMissing(Self.describe(error))
            follow([])
        }
    }

    /// Watches the folders of `files` and reads again when one of the files changes.
    private func follow(_ files: [String]) {
        guard files != watchedFiles else { return }
        watchedFiles = files
        watchTask?.cancel()
        watchTask = nil
        guard !files.isEmpty else { return }
        let folders = Array(Set(files.map { ($0 as NSString).deletingLastPathComponent })).sorted()
        let wanted = Set(files)
        let stream = watcher.changes(under: folders)
        watchTask = Task { [weak self] in
            for await paths in stream {
                guard paths.contains(where: { wanted.contains($0) }) else { continue }
                await self?.refresh()
            }
        }
    }

    // MARK: Account

    /// Sends the sign-in link to `email` (`lab app signin --email`): the 14-day trial without a
    /// card starts at the first sign-in.
    /// - Parameter email: what the person typed, passed as one argument.
    public func signIn(email: String) async {
        guard speaksContractOrSay() else { return }
        guard let address = LabEmailAddress(email) else {
            notice = .invalidEmail
            return
        }
        guard let output = await perform(.signIn(email: address)) else { return }
        let sent = AccountContract.text(AccountContract.block(of: output).first("EMAIL")) ?? address.value
        notice = .linkSent(email: sent)
    }

    /// Closes every session of the account, this Mac included (`lab app signout --everywhere`),
    /// then reads the account again.
    public func signOutEverywhere() async {
        guard speaksContractOrSay() else { return }
        guard await perform(.signOutEverywhere) != nil else { return }
        notice = .signedOutEverywhere
        await refresh()
    }

    /// Opens Stripe's secure page through `lab subscribe`: to subscribe, manage the subscription
    /// or see the invoices. Works before the contract too.
    public func subscribe() async {
        guard let output = await perform(.subscribe) else { return }
        let value = AccountContract.block(of: output).first("SUBSCRIBE") ?? "other"
        notice = .subscribeOpened(SubscribeOutcome(rawValue: value) ?? .other)
    }

    // MARK: Ginkgo

    /// Stores the OpenAI key in the Mac's keychain (`lab ginkgo key openai`, the key on standard
    /// input), then reads whether it is stored. The key is not kept once the call is over.
    /// Works before the contract too.
    /// - Parameter key: what the person pasted.
    public func storeOpenAIKey(_ key: String) async {
        guard let secret = LabSecret(key) else {
            notice = .invalidKey
            return
        }
        guard await perform(.storeOpenAIKey(secret)) != nil else { return }
        notice = .keyStored
        if let runner, let output = try? await runner.run(.ginkgoStatus) {
            let presence = AccountContract.key(from: output)
            self.key = presence == .unknown ? .present : presence
        } else {
            self.key = .present
        }
    }

    /// Sets when Ginkgo listens (`lab app ginkgo --listen`).
    /// - Parameter mode: the person's choice.
    public func setListening(_ mode: GinkgoListening) async {
        guard let setting = LabGinkgoSetting.listen(mode.rawValue) else { return }
        await save(setting) { $0.listen = mode }
    }

    /// Sets when Ginkgo speaks out loud (`lab app ginkgo --speak`).
    /// - Parameter mode: the person's choice.
    public func setSpeech(_ mode: GinkgoSpeech) async {
        guard let setting = LabGinkgoSetting.speak(mode.rawValue) else { return }
        await save(setting) { $0.speak = mode }
    }

    /// Sets Ginkgo's quiet hours (`lab app ginkgo --quiet`), checked first.
    /// - Parameter text: `HH:MM-HH:MM` or `off`.
    public func setQuiet(_ text: String) async {
        guard speaksContractOrSay() else { return }
        guard let quiet = QuietSetting(text), let setting = LabGinkgoSetting.quiet(quiet.argument) else {
            notice = .invalidQuietHours
            return
        }
        await save(setting) { $0.quiet = quiet }
    }

    private func save(_ setting: LabGinkgoSetting, expected: (inout GinkgoPreferences) -> Void) async {
        guard speaksContractOrSay() else { return }
        guard let output = await perform(.setGinkgo(setting)) else { return }
        if let written = AccountContract.ginkgo(from: output), written != GinkgoPreferences() {
            ginkgo = ginkgo.merged(with: written)
        } else {
            expected(&ginkgo)
        }
        notice = .saved
    }

    // MARK: Data

    /// Has lab write a readable copy of Treelab's and lab's data, without secrets, in `folder`
    /// (`lab app data --export`).
    /// - Parameter folder: the folder the person chose.
    public func exportData(to folder: URL) async {
        guard speaksContractOrSay() else { return }
        guard let path = LabFolderPath(folder.path) else {
            notice = .invalidFolder
            return
        }
        guard let output = await perform(.exportData(folder: path)) else { return }
        notice = .exported(path: AccountContract.text(AccountContract.block(of: output).first("EXPORTED")) ?? path.value)
    }

    /// First step of an erase (`lab app data --erase`): lab says what will go and gives a token,
    /// kept until ``confirmErase()`` or ``cancelErase()``.
    public func beginErase() async {
        guard speaksContractOrSay() else { return }
        pendingErase = nil
        guard let output = await perform(.eraseData) else { return }
        let block = AccountContract.block(of: output)
        let raw = block.first("TOKEN") ?? ""
        guard let token = LabEraseToken(raw) else {
            notice = .refused("TOKEN=\(raw.prefix(40))")
            return
        }
        pendingErase = PendingErase(readback: AccountContract.text(block.first("READBACK")) ?? "", token: token)
        notice = nil
    }

    /// Second step of an erase: the token of the first step sent back
    /// (`lab app data --erase --confirm <token>`), then the account read again.
    public func confirmErase() async {
        guard let pending = pendingErase else { return }
        pendingErase = nil
        guard await perform(.confirmErase(token: pending.token)) != nil else { return }
        notice = .erased
        await refresh()
    }

    /// Gives up the erase: the token is forgotten, nothing is sent.
    public func cancelErase() {
        pendingErase = nil
    }

    // MARK: Running lab

    /// Says the next treelab version is needed, unless lab speaks the contract.
    private func speaksContractOrSay() -> Bool {
        switch status {
        case .contract: return true
        case let .labMissing(reason):
            notice = .labMissing(reason)
            return false
        case .nextVersion, .unknown:
            notice = .nextVersion
            return false
        }
    }

    /// Runs `command`; a refusal or a failure is said and gives `nil`.
    private func perform(_ command: LabCommand) async -> LabCommandOutput? {
        guard let runner else {
            notice = .labMissing("")
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let output = try await runner.run(command)
            guard output.status == 0 else {
                notice = .refused(AccountContract.refusal(of: output))
                return nil
            }
            return output
        } catch {
            notice = .labMissing(Self.describe(error))
            return nil
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let problem = error as? LanesProblem else { return error.localizedDescription }
        switch problem {
        case let .labUnavailable(reason), let .labRefused(reason), let .unknownLabVersion(reason): return reason
        case let .refusedFile(path, reason): return "\(path): \(reason.rawValue)"
        }
    }
}
