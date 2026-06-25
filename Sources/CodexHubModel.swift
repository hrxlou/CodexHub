import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

final class CodexHubModel: ObservableObject {
    private let authService = CodexAuthService()
    private let usageScanner = TokenUsageScanner()
    private let attributionStore = AttributionStore()
    private let workQueue = DispatchQueue(label: "local.codexhub.model-work", qos: .utility)
    private let minimumRefreshInterval: TimeInterval = 60
    private let minimumDetailsRefreshInterval: TimeInterval = 30 * 60
    let settings = HubSettings()
    @Published var accounts: [CodexAccount] = []
    @Published var usage = UsageSnapshot(today: .zero, todayByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: nil)
    @Published var usageDetails: UsageDetailSnapshot?
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var isLoadingDetails = false
    @Published var isAddingAccount = false
    @Published var usageDetailsProgress: Double?
    @Published var usageDetailsProgressText: String?
    @Published var switchingAccountEmail: String?
    @Published var removingAccountIdentity: String?
    @Published var quotaAPIStatus: CodexAuthService.QuotaAPIStatus = .off
    @Published var lastRefreshDate: Date?
    private var refreshTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var lastReminderSignature: String?
    private var lastAutoSwitchSignature: String?
    private var lastUsageDetailsRefreshDate: Date?

    init() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        refresh(force: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        refreshTimer?.tolerance = 30
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var activeAccount: CodexAccount? {
        accounts.first(where: { $0.isActive })
    }

    var isSwitchingAccount: Bool {
        switchingAccountEmail != nil
    }

    var menuBarTitle: String {
        guard let activeAccount else {
            return "CodexHub · \(Format.money(usage.today.costs.totalCost))"
        }
        let activeUsage = usage.todayByAccount[activeAccount.email] ?? .zero
        return "\(activeAccount.label) · 5H \(Format.percentRemaining(fromUsed: activeAccount.fiveHourUsedPercent)) · W \(Format.percentRemaining(fromUsed: activeAccount.weeklyUsedPercent)) · \(Format.money(activeUsage.costs.totalCost))"
    }

    var sortedAccounts: [CodexAccount] {
        accounts.sorted { left, right in
            if left.label != right.label { return left.label < right.label }
            return left.email.localizedCaseInsensitiveCompare(right.email) == .orderedAscending
        }
    }

    var todayByAccountRows: [AccountUsageSummary] {
        usage.todayByAccount
            .map { AccountUsageSummary(email: $0.key, aggregate: $0.value) }
            .sorted { displayName(for: $0.email) < displayName(for: $1.email) }
    }

    func refresh(force: Bool) {
        guard !isRefreshing else { return }
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < minimumRefreshInterval {
            return
        }
        isRefreshing = true
        let useQuotaAPI = settings.quotaAPIEnabled
        workQueue.async {
            let listed = self.authService.listAccounts(useAPI: useQuotaAPI)
            let accounts = listed.accounts
            let defaultLegacy = accounts.first(where: { $0.email.lowercased().hasPrefix("n") || $0.email.lowercased().contains("snu") })?.email
                ?? accounts.first?.email
            self.attributionStore.seedLegacyAccountIfNeeded(defaultLegacy)
            if let active = accounts.first(where: { $0.isActive }) {
                self.attributionStore.recordActiveAccount(active.email)
            }
            let usage = self.usageScanner.scan(attribution: self.attributionStore, accounts: accounts)
            DispatchQueue.main.async {
                self.accounts = accounts
                self.usage = usage
                self.quotaAPIStatus = listed.quotaAPIStatus
                self.lastError = listed.error ?? usage.lastError
                self.lastRefreshDate = Date()
                self.switchingAccountEmail = nil
                self.isRefreshing = false
                self.evaluateAutomation()
                self.refreshUsageDetailsIfStale()
            }
        }
    }

    func accountMenuTitle(_ account: CodexAccount) -> String {
        let marker = account.isActive ? "*" : " "
        let accountUsage = usage.todayByAccount[account.email] ?? .zero
        return "\(marker) \(account.label)  5H \(Format.percentRemaining(fromUsed: account.fiveHourUsedPercent))  W \(Format.percentRemaining(fromUsed: account.weeklyUsedPercent))  \(L.today) \(Format.summary(accountUsage))  \(compactEmail(account.email))"
    }

    func displayName(for email: String) -> String {
        if let account = accounts.first(where: { $0.email == email }) {
            return "\(account.label) \(compactEmail(email))"
        }
        return email == "Unknown" ? L.text(ko: "알 수 없음", en: "Unknown") : compactEmail(email)
    }

    func compactEmail(_ email: String) -> String {
        guard email.count > 24 else { return email }
        return String(email.prefix(21)) + "..."
    }

    func switchAccount(_ identity: String) {
        guard let target = accounts.first(where: { $0.identity == identity }) else { return }
        guard target.isActive != true else { return }
        guard !isSwitchingAccount else { return }
        switchingAccountEmail = target.email
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.authService.switchTo(identity, useAPI: self.settings.quotaAPIEnabled)
            DispatchQueue.main.async {
                if result.status == 0 {
                    self.attributionStore.recordActiveAccount(target.email)
                    self.accounts = self.accounts.map { $0.settingActive($0.identity == identity) }
                    self.isRefreshing = false
                    self.refresh(force: true)
                } else {
                    self.lastError = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.switchingAccountEmail = nil
                    self.isRefreshing = false
                }
            }
        }
    }

    func addAccount(mode: LoginMode = .browser) {
        guard !isAddingAccount else { return }
        isAddingAccount = true
        isRefreshing = true
        settings.statusMessage = L.accountLoginInProgress
        DispatchQueue.global(qos: .userInitiated).async {
            let previousIdentity = self.authService.currentLoginIdentity()
            _ = self.authService.captureCurrentLogin(alias: nil)
            let login = self.authService.startCodexLogin(mode: mode)
            let currentIdentity = login.status == 0
                ? self.authService.waitForCurrentLoginIdentity(preferDifferentFrom: previousIdentity, timeout: 8)
                : nil
            let capture = login.status == 0 ? self.authService.captureCurrentLogin(alias: nil) : login
            let activation = (capture.status == 0 && currentIdentity != nil)
                ? self.authService.switchTo(currentIdentity!, useAPI: self.settings.quotaAPIEnabled)
                : capture
            DispatchQueue.main.async {
                self.isAddingAccount = false
                self.isRefreshing = false
                if login.status == 0 && capture.status == 0 && activation.status == 0 {
                    self.settings.statusMessage = L.accountSaved
                    self.refresh(force: true)
                } else {
                    let message = activation.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastError = message.isEmpty ? L.accountLoginFailed : "\(L.accountLoginFailed): \(message)"
                    self.settings.statusMessage = L.codexLoginLogHint
                }
            }
        }
    }

    func removeAccount(_ identity: String) {
        guard let account = accounts.first(where: { $0.identity == identity }) else { return }
        guard !account.isActive else {
            lastError = L.activeAccountCannotBeRemoved
            return
        }
        guard removingAccountIdentity == nil else { return }
        removingAccountIdentity = identity
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.authService.removeStoredAccount(identity)
            DispatchQueue.main.async {
                self.removingAccountIdentity = nil
                if result.status == 0 {
                    self.settings.statusMessage = L.accountRemoved
                    self.accounts.removeAll { $0.identity == identity }
                    self.usageDetails = nil
                    self.lastUsageDetailsRefreshDate = nil
                    self.refresh(force: true)
                } else {
                    let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastError = message.isEmpty ? L.accountRemoveFailed : message
                }
            }
        }
    }

    func loadUsageDetails(force: Bool) {
        if usageDetails != nil && !force {
            if let lastUsageDetailsRefreshDate,
               Date().timeIntervalSince(lastUsageDetailsRefreshDate) < minimumDetailsRefreshInterval {
                return
            }
        }
        guard !isLoadingDetails else { return }
        isLoadingDetails = true
        usageDetailsProgress = 0
        usageDetailsProgressText = nil
        let accounts = self.accounts
        workQueue.async {
            let details = self.usageScanner.scanDetails(attribution: self.attributionStore, accounts: accounts) { progress in
                DispatchQueue.main.async {
                    self.usageDetailsProgress = progress.fraction
                    self.usageDetailsProgressText = L.usageScanProgress(completed: progress.completedFiles, total: progress.totalFiles)
                }
            }
            DispatchQueue.main.async {
                self.usageDetails = details
                self.lastUsageDetailsRefreshDate = Date()
                self.isLoadingDetails = false
                self.usageDetailsProgress = nil
                self.usageDetailsProgressText = nil
                if let error = details.lastError {
                    self.lastError = error
                }
            }
        }
    }

    func setQuotaAPIEnabled(_ enabled: Bool) {
        guard settings.quotaAPIEnabled != enabled else { return }
        settings.quotaAPIEnabled = enabled
        quotaAPIStatus = enabled ? .on : .off
        settings.statusMessage = enabled ? L.quotaAPIEnabled : L.quotaAPIDisabled
        refresh(force: true)
    }

    func resetAttributionHistory() {
        attributionStore.resetHistory(currentEmail: activeAccount?.email)
        usageDetails = nil
        lastUsageDetailsRefreshDate = nil
        settings.statusMessage = L.attributionHistoryReset
        refresh(force: true)
    }

    private func refreshUsageDetailsIfStale() {
        guard usageDetails != nil else { return }
        guard let lastUsageDetailsRefreshDate,
              Date().timeIntervalSince(lastUsageDetailsRefreshDate) >= minimumDetailsRefreshInterval else { return }
        loadUsageDetails(force: true)
    }

    private func evaluateAutomation() {
        guard let active = activeAccount, let used = active.usagePercent else { return }
        let remaining = max(0, min(100, 100 - used))

        if settings.usageReminderEnabled && remaining <= settings.reminderThreshold {
            let day = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
            let signature = "\(active.email)-\(used)-\(day)"
            if signature != lastReminderSignature {
                lastReminderSignature = signature
                sendUsageReminder(account: active, used: used, remaining: remaining)
            }
        }

        let switchThreshold = settings.autoSwitchThreshold
        guard settings.autoSwitchEnabled && remaining <= switchThreshold else { return }
        let candidates = accounts
            .filter { !$0.isActive }
            .compactMap { account -> (CodexAccount, Int)? in
                guard let candidateRemaining = Format.remainingPercent(fromUsed: account.fiveHourUsedPercent) else { return nil }
                return (account, candidateRemaining)
            }
            .filter { $0.1 > remaining }
            .filter { $0.1 > switchThreshold }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return left.0.label < right.0.label
            }
        guard let best = candidates.first else { return }
        let signature = "\(active.email):\(remaining)->\(best.0.email):\(best.1)-\(switchThreshold)"
        guard signature != lastAutoSwitchSignature else { return }
        lastAutoSwitchSignature = signature
        promptAutoSwitch(from: active, to: best.0, activeRemaining: remaining, candidateRemaining: best.1)
    }

    private func promptAutoSwitch(from active: CodexAccount, to candidate: CodexAccount, activeRemaining: Int, candidateRemaining: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L.switchCodexAccount
        alert.informativeText = L.autoSwitchMessage(activeLabel: active.label, activeRemaining: activeRemaining, candidateLabel: candidate.label, candidateRemaining: candidateRemaining)
        alert.addButton(withTitle: L.switchAccount)
        alert.addButton(withTitle: L.notNow)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            switchAccount(candidate.email)
        }
    }

    private func sendUsageReminder(account: CodexAccount, used: Int, remaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = L.usageReminderTitle
        content.body = L.usageReminderBody(accountLabel: account.label, used: used, remaining: remaining)
        content.sound = .default
        let identifier = "codexhub-usage-\(account.email.hashValue)-\(used)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request) }
                }
            default:
                break
            }
        }
    }
}
