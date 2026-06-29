import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

final class CodexHubModel: ObservableObject {
    private let accountStore: CodexAccountStore
    private let authService: CodexAuthService
    private let usageScanner: TokenUsageScanner
    private let usageHistoryStore: UsageHistoryStore
    private let attributionStore = AttributionStore()
    private let workQueue = DispatchQueue(label: "local.codexhub.model-work", qos: .utility)
    private let minimumRefreshInterval: TimeInterval = 60
    private let minimumDetailsRefreshInterval: TimeInterval = 30 * 60
    private let minimumDashboardRefreshInterval: TimeInterval = 30 * 60
    let settings = HubSettings()
    @Published var accounts: [CodexAccount] = []
    @Published var usage = UsageSnapshot(today: .zero, todayByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: nil)
    @Published var usageDetails: UsageDetailSnapshot?
    @Published var dashboardSnapshot = DashboardSnapshot.empty
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var isLoadingDetails = false
    @Published var isLoadingDashboard = false
    @Published var isAddingAccount = false
    @Published var usageDetailsProgress: Double?
    @Published var usageDetailsProgressText: String?
    @Published var dashboardProgress: Double?
    @Published var dashboardProgressText: String?
    @Published private(set) var dashboardRangeDays: Int?
    @Published var dashboardOpenRequest: UUID?
    @Published var switchingAccountEmail: String?
    @Published var removingAccountIdentity: String?
    @Published var quotaAPIStatus: CodexAuthService.QuotaAPIStatus = .off
    @Published var lastRefreshDate: Date?
    private var refreshTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var lastReminderSignature: String?
    private var lastAutoSwitchSignature: String?
    private var lastUsageDetailsRefreshDate: Date?
    private var lastDashboardRefreshDate: Date?
    private var loadingDashboardRangeDays: Int?
    private var pendingDashboardRequest: (force: Bool, days: Int)?
    private var refreshGeneration = 0
    private var usageDetailsGeneration = 0
    private var dashboardGeneration = 0

    init() {
        let accountStore = CodexAccountStore()
        self.accountStore = accountStore
        self.authService = CodexAuthService(accountStore: accountStore)
        self.usageScanner = TokenUsageScanner(accountStore: accountStore)
        self.usageHistoryStore = UsageHistoryStore()
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
        let totalTodayCost = usage.today.costs.totalCost
        guard let activeAccount else {
            return settings.menuBarShowsCost ? "CodexHub · \(Format.money(totalTodayCost))" : "CodexHub"
        }
        let activeUsage = usage.todayByAccount[activeAccount.email] ?? .zero
        var parts: [String] = []

        if settings.menuBarShowsAccountName {
            parts.append(activeAccount.label)
        }
        if settings.menuBarShowsFiveHour {
            parts.append("\(activeAccount.primaryQuotaLabel) \(Format.percentRemaining(fromUsed: activeAccount.fiveHourUsedPercent))")
        }
        if settings.menuBarShowsWeekly, activeAccount.shouldShowSecondaryQuota {
            parts.append("\(activeAccount.secondaryQuotaLabel) \(Format.percentRemaining(fromUsed: activeAccount.weeklyUsedPercent))")
        }
        if settings.menuBarShowsTokens {
            parts.append(Format.tokens(activeUsage.billingTokenTotal))
        }
        if settings.menuBarShowsCost {
            parts.append(Format.money(activeUsage.costs.totalCost))
        }

        return parts.isEmpty ? "CodexHub" : parts.joined(separator: " · ")
    }

    var sortedAccounts: [CodexAccount] {
        accounts
    }

    func openDashboardWindow() {
        dashboardOpenRequest = UUID()
        loadDashboard(force: false)
    }

    var todayByAccountRows: [AccountUsageSummary] {
        sortedAccountUsageRows(usage.todayByAccount)
    }

    func sortedAccountUsageRows(_ usageByAccount: [String: UsageAggregate]) -> [AccountUsageSummary] {
        usageByAccount
            .map { AccountUsageSummary(email: $0.key, aggregate: $0.value) }
            .sorted { left, right in
                if left.aggregate.billingTokenTotal != right.aggregate.billingTokenTotal {
                    return left.aggregate.billingTokenTotal > right.aggregate.billingTokenTotal
                }
                if left.aggregate.costs.totalCost != right.aggregate.costs.totalCost {
                    return left.aggregate.costs.totalCost > right.aggregate.costs.totalCost
                }
                return displayName(for: left.email) < displayName(for: right.email)
            }
    }

    func refresh(force: Bool) {
        guard !isRefreshing || force else { return }
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < minimumRefreshInterval {
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        let useQuotaAPI = settings.quotaAPIEnabled
        workQueue.async {
            let listed = self.authService.listAccounts(useAPI: useQuotaAPI)
            let accounts = listed.accounts
            let defaultLegacy = accounts.first?.email
            self.attributionStore.seedLegacyAccountIfNeeded(defaultLegacy)
            let usage = self.usageScanner.scan(attribution: self.attributionStore, accounts: accounts)
            DispatchQueue.main.async {
                guard self.refreshGeneration == generation else { return }
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
        var quotaParts = [
            "\(account.primaryQuotaLabel) \(Format.percentRemaining(fromUsed: account.fiveHourUsedPercent))"
        ]
        if account.shouldShowSecondaryQuota {
            quotaParts.append("\(account.secondaryQuotaLabel) \(Format.percentRemaining(fromUsed: account.weeklyUsedPercent))")
        }
        return "\(marker) \(account.label)  \(quotaParts.joined(separator: "  "))  \(L.today) \(Format.summary(accountUsage))  \(compactEmail(account.email))"
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
        guard confirmCodexAppThreadSwitchIfNeeded() else { return }
        invalidateRefreshResults()
        switchingAccountEmail = target.email
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.authService.switchTo(identity, useAPI: self.settings.quotaAPIEnabled)
            DispatchQueue.main.async {
                if result.status == 0 {
                    self.attributionStore.recordActiveAccount(target.email)
                    let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if message.isEmpty == false {
                        self.settings.statusMessage = message
                    }
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
        invalidateRefreshResults()
        isAddingAccount = true
        isRefreshing = true
        settings.statusMessage = L.accountLoginInProgress
        DispatchQueue.global(qos: .userInitiated).async {
            let login = self.authService.loginAndStoreAccount(mode: mode)
            DispatchQueue.main.async {
                self.isAddingAccount = false
                self.isRefreshing = false
                if login.result.status == 0 {
                    self.settings.statusMessage = L.accountSaved
                    self.refresh(force: true)
                } else {
                    let message = login.result.output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        invalidateRefreshResults()
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
                    self.dashboardSnapshot = .empty
                    self.lastDashboardRefreshDate = nil
                    self.dashboardRangeDays = nil
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
        usageDetailsGeneration += 1
        let generation = usageDetailsGeneration
        let accounts = self.accounts
        workQueue.async {
            let details = self.usageScanner.scanDetails(attribution: self.attributionStore, accounts: accounts) { progress in
                DispatchQueue.main.async {
                    guard self.usageDetailsGeneration == generation else { return }
                    self.usageDetailsProgress = progress.fraction
                    self.usageDetailsProgressText = L.usageScanProgress(completed: progress.completedFiles, total: progress.totalFiles)
                }
            }
            DispatchQueue.main.async {
                guard self.usageDetailsGeneration == generation else { return }
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

    func loadDashboard(force: Bool, days: Int = 30) {
        if isLoadingDashboard {
            if loadingDashboardRangeDays != days || force {
                let shouldForce = force || pendingDashboardRequest?.force == true
                pendingDashboardRequest = (shouldForce, days)
            }
            return
        }

        if dashboardSnapshot.isEmpty == false && !force {
            if let lastDashboardRefreshDate,
               dashboardRangeDays == days,
               Date().timeIntervalSince(lastDashboardRefreshDate) < minimumDashboardRefreshInterval {
                return
            }
        }
        guard !isLoadingDashboard else { return }
        isLoadingDashboard = true
        loadingDashboardRangeDays = days
        dashboardProgress = 0
        dashboardProgressText = nil
        dashboardGeneration += 1
        let generation = dashboardGeneration
        let accounts = self.accounts
        workQueue.async {
            let snapshot = self.usageScanner.scanDashboard(
                attribution: self.attributionStore,
                accounts: accounts,
                historyStore: self.usageHistoryStore,
                days: days
            ) { progress in
                DispatchQueue.main.async {
                    guard self.dashboardGeneration == generation else { return }
                    self.dashboardProgress = progress.fraction
                    self.dashboardProgressText = L.usageScanProgress(completed: progress.completedFiles, total: progress.totalFiles)
                }
            }
            DispatchQueue.main.async {
                guard self.dashboardGeneration == generation else { return }
                self.dashboardSnapshot = snapshot
                self.lastDashboardRefreshDate = Date()
                self.dashboardRangeDays = days
                self.isLoadingDashboard = false
                self.loadingDashboardRangeDays = nil
                self.dashboardProgress = nil
                self.dashboardProgressText = nil
                if let pendingRequest = self.pendingDashboardRequest {
                    self.pendingDashboardRequest = nil
                    self.loadDashboard(force: pendingRequest.force, days: pendingRequest.days)
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
        dashboardSnapshot = .empty
        lastDashboardRefreshDate = nil
        dashboardRangeDays = nil
        settings.statusMessage = L.attributionHistoryReset
        refresh(force: true)
    }

    func clearDashboardHistory() {
        usageHistoryStore.clear()
        dashboardSnapshot = .empty
        lastDashboardRefreshDate = nil
        dashboardRangeDays = nil
        settings.statusMessage = L.dashboardHistoryCleared
    }

    private func refreshUsageDetailsIfStale() {
        guard usageDetails != nil else { return }
        guard let lastUsageDetailsRefreshDate,
              Date().timeIntervalSince(lastUsageDetailsRefreshDate) >= minimumDetailsRefreshInterval else { return }
        loadUsageDetails(force: true)
    }

    private func evaluateAutomation() {
        let policy = UsageAutomationPolicy(
            accounts: accounts,
            reminderEnabled: settings.usageReminderEnabled,
            reminderThreshold: settings.reminderThreshold,
            autoSwitchEnabled: settings.autoSwitchEnabled,
            autoSwitchThreshold: settings.autoSwitchThreshold,
            date: Date(),
            calendar: .current
        )

        if let reminder = policy.reminder(excluding: lastReminderSignature) {
            lastReminderSignature = reminder.signature
            sendUsageReminder(account: reminder.account, used: reminder.used, remaining: reminder.remaining)
        }

        if let suggestion = policy.switchSuggestion(excluding: lastAutoSwitchSignature) {
            lastAutoSwitchSignature = suggestion.signature
            promptAutoSwitch(
                from: suggestion.active,
                to: suggestion.candidate,
                activeRemaining: suggestion.activeRemaining,
                candidateRemaining: suggestion.candidateRemaining
            )
        }
    }

    private func invalidateRefreshResults() {
        refreshGeneration += 1
        usageDetailsGeneration += 1
        dashboardGeneration += 1
        isLoadingDetails = false
        usageDetailsProgress = nil
        usageDetailsProgressText = nil
        isLoadingDashboard = false
        loadingDashboardRangeDays = nil
        pendingDashboardRequest = nil
        dashboardProgress = nil
        dashboardProgressText = nil
    }

    private func promptAutoSwitch(from active: CodexAccount, to candidate: CodexAccount, activeRemaining: Int, candidateRemaining: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L.switchCodexAccount
        alert.informativeText = L.autoSwitchMessage(
            activeAccount: active.email,
            activeQuotaLabel: active.primaryQuotaLabel,
            activeRemaining: activeRemaining,
            candidateAccount: candidate.email,
            candidateQuotaLabel: candidate.primaryQuotaLabel,
            candidateRemaining: candidateRemaining
        )
        alert.addButton(withTitle: L.switchAccount)
        alert.addButton(withTitle: L.notNow)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            switchAccount(candidate.identity)
        }
    }

    private func confirmCodexAppThreadSwitchIfNeeded() -> Bool {
        guard let activity = authService.codexAppThreadActivity(),
              activity.hasActiveThreads else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.codexActiveThreadsTitle
        alert.informativeText = L.codexActiveThreadsSwitchMessage(
            activeCount: activity.activeThreadCount,
            waitingOnApprovalCount: activity.waitingOnApprovalCount,
            waitingOnUserInputCount: activity.waitingOnUserInputCount
        )
        alert.addButton(withTitle: L.notNow)
        alert.addButton(withTitle: L.switchAccount)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func sendUsageReminder(account: CodexAccount, used: Int, remaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = L.usageReminderTitle
        content.body = L.usageReminderBody(
            accountLabel: account.label,
            quotaLabel: account.primaryQuotaLabel,
            used: used,
            remaining: remaining
        )
        content.sound = .default
        let identifier = "codexhub-usage-\(stableIdentifierComponent(account.identity))-\(settings.reminderThreshold)"
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

    private func stableIdentifierComponent(_ value: String) -> String {
        let encoded = value.utf8.map { String(format: "%02x", $0) }.joined()
        return String(encoded.prefix(48))
    }
}
