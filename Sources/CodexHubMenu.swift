import AppKit
import Foundation
import SwiftUI

struct CodexHubMenu: View {
    @ObservedObject var model: CodexHubModel
    @ObservedObject var settings: HubSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var panel: HubPanel = .usage
    @State private var tokenCostHover = false

    init(model: CodexHubModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if panel == .usage {
                accountGrid
                usageCard
                byAccountCard
            } else if panel == .costDetails {
                tokenCostDetails
            } else {
                settingsPanel
            }
            if panel == .usage {
                footer
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .onAppear {
            panel = .usage
        }
        .overlay {
            if model.isSwitchingAccount {
                switchProgressOverlay
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.isSwitchingAccount)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: HubImages.appIcon(for: colorScheme))
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("CodexHub")
                    .font(.system(size: 18, weight: .semibold))
            }
            Spacer()
            if panel == .usage {
                HubActionButton(title: L.settings, systemImage: "gearshape", iconOnly: true) {
                    panel = .settings
                }
            } else {
                HubActionButton(title: L.back, systemImage: "chevron.left", compact: true) {
                    panel = .usage
                }
            }
        }
    }

    private var accountGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.accounts)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if model.sortedAccounts.count <= 1 {
                ForEach(model.sortedAccounts, id: \.email) { account in
                    AccountCardView(model: model, account: account)
                }
            } else if model.sortedAccounts.count == 2 {
                LazyVGrid(columns: accountColumns, spacing: 10) {
                    ForEach(model.sortedAccounts, id: \.email) { account in
                        AccountCardView(model: model, account: account)
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: accountColumns, spacing: 10) {
                        ForEach(model.sortedAccounts, id: \.email) { account in
                            AccountCardView(model: model, account: account)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private var accountColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 14),
            GridItem(.flexible(minimum: 0), spacing: 14)
        ]
    }

    private var switchProgressOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 4) {
                    Text(L.switchingAccount)
                        .font(.system(size: 14, weight: .semibold))
                    if let email = model.switchingAccountEmail {
                        Text(model.compactEmail(email))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .glassPanel(cornerRadius: 13, tint: Color.white.opacity(0.10), stroke: Color.primary.opacity(0.10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var usageCard: some View {
        Button {
            panel = .costDetails
            model.loadUsageDetails(force: false)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(L.tokenCost)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(L.details)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(tokenCostHover ? 0.10 : 0.055))
                    .clipShape(Capsule())
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(L.today)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.summary(model.usage.today))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Divider().opacity(0.45)
                metricRow(L.input, value: Format.tokens(model.usage.today.totals.billedInputTokens), cost: Format.money(model.usage.today.costs.inputCost), icon: "tray.and.arrow.down")
                metricRow(L.cache, value: Format.tokens(model.usage.today.totals.cachedInputTokens), cost: Format.money(model.usage.today.costs.cachedInputCost), icon: "internaldrive")
                metricRow(L.output, value: Format.tokens(model.usage.today.totals.outputTokens), cost: Format.money(model.usage.today.costs.outputCost), icon: "arrow.up.right")
                metricRow(L.reasoning, value: Format.tokens(model.usage.today.totals.reasoningOutputTokens), cost: Format.money(model.usage.today.costs.reasoningCost), icon: "brain.head.profile")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(
                cornerRadius: 13,
                tint: Color.white.opacity(tokenCostHover ? 0.12 : 0.08),
                stroke: Color.primary.opacity(tokenCostHover ? 0.16 : 0.08),
                hovering: tokenCostHover
            )
        }
        .buttonStyle(.plain)
        .onHover { tokenCostHover = $0 }
        .help(L.openTokenCostDetails)
    }

    private var byAccountCard: some View {
        sectionCard(title: L.byAccountToday) {
            if model.todayByAccountRows.isEmpty {
                Text(L.noAttributedUsage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.todayByAccountRows, id: \.email) { row in
                    HStack {
                        Text(model.displayName(for: row.email))
                            .lineLimit(1)
                        Spacer()
                        Text(Format.money(row.aggregate.costs.totalCost))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private var tokenCostDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.isLoadingDetails && model.usageDetails == nil {
                sectionCard(title: L.tokenCost) {
                    usageDetailsProgressView
                }
            } else {
                let details = model.usageDetails ?? UsageDetailSnapshot(
                    today: model.usage.today,
                    week: .zero,
                    month: .zero,
                    weekByAccount: [:],
                    monthByAccount: [:],
                    recentDaily: model.usage.recentDaily,
                    scannedFiles: model.usage.scannedFiles,
                    lastError: model.usage.lastError
                )

                if model.isLoadingDetails {
                    sectionCard(title: L.loadingUsageDetails) {
                        usageDetailsProgressView
                    }
                }

                tokenCostSummaryCard(details)

                sectionCard(title: L.recent) {
                    if details.recentDaily.isEmpty {
                        Text(L.noRecentUsage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(details.recentDaily.prefix(3).enumerated()), id: \.offset) { _, row in
                            compactUsageRow(label: Format.day(row.0), value: Format.summary(row.1))
                        }
                    }
                }

                accountUsageSection(title: L.byAccountThisWeek, usage: details.weekByAccount, maxRows: 2)
                accountUsageSection(title: L.byAccountThisMonth, usage: details.monthByAccount, maxRows: 2)
            }

            HStack {
                Spacer(minLength: 0)
                RefreshButton(isRefreshing: model.isLoadingDetails) {
                    model.loadUsageDetails(force: true)
                }
            }
        }
        .onAppear {
            model.loadUsageDetails(force: false)
        }
    }

    private var usageDetailsProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.loadingUsageDetails)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let progress = model.usageDetailsProgress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: model.usageDetailsProgress ?? 0, total: 1)
                .progressViewStyle(.linear)

            if let progressText = model.usageDetailsProgressText {
                Text(progressText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text(Format.relative(model.lastRefreshDate))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RefreshButton(isRefreshing: model.isRefreshing) {
                model.refresh(force: true)
            }
            HubActionButton(title: L.quit, systemImage: "power", tone: .danger) {
                NSApp.terminate(nil)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: L.preferences) {
                languageRow()
                Divider().opacity(0.45)
                settingToggle(
                    title: L.launchAtLogin,
                    subtitle: L.launchAtLoginSubtitle,
                    isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })
                )
                Divider().opacity(0.45)
                settingToggle(
                    title: L.quotaAPI,
                    subtitle: L.quotaAPISubtitle,
                    isOn: Binding(get: { settings.quotaAPIEnabled }, set: { model.setQuotaAPIEnabled($0) })
                )
            }

            sectionCard(title: L.automation) {
                settingToggle(
                    title: L.usageReminder,
                    subtitle: L.usageReminderSubtitle,
                    isOn: Binding(get: { settings.usageReminderEnabled }, set: { settings.usageReminderEnabled = $0 })
                )
                if settings.usageReminderEnabled {
                    thresholdRow(
                        title: L.reminderThreshold,
                        value: Binding(get: { settings.reminderThreshold }, set: { settings.reminderThreshold = $0 }),
                        detail: L.remaining
                    )
                }
                Divider().opacity(0.45)
                settingToggle(
                    title: L.accountSuggestion,
                    subtitle: L.accountSuggestionSubtitle,
                    isOn: Binding(get: { settings.autoSwitchEnabled }, set: { settings.autoSwitchEnabled = $0 })
                )
                if settings.autoSwitchEnabled {
                    thresholdRow(
                        title: L.suggestionThreshold,
                        value: Binding(get: { settings.autoSwitchThreshold }, set: { settings.autoSwitchThreshold = $0 }),
                        detail: L.remaining
                    )
                }
            }

            sectionCard(title: L.privacy) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.attributionHistory)
                            .font(.system(size: 12, weight: .semibold))
                        Text(L.attributionHistorySubtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    HubActionButton(title: L.clearMap, systemImage: "trash", tone: .danger) {
                        model.resetAttributionHistory()
                    }
                }
            }

            sectionCard(title: L.status) {
                healthRow(L.auth, value: model.accounts.isEmpty ? L.missing : L.ok, good: model.accounts.isEmpty == false)
                healthRow(L.quotaAPI, value: model.quotaAPIStatus.label, good: model.quotaAPIStatus.isHealthy)
                healthRow(L.codex, value: FileManager.default.fileExists(atPath: "/Applications/Codex.app") ? L.found : L.missing, good: FileManager.default.fileExists(atPath: "/Applications/Codex.app"))
                healthRow(L.refresh, value: model.isRefreshing ? L.updating : L.ready, good: !model.isRefreshing)
                if let status = settings.statusMessage {
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func settingToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func thresholdRow(title: String, value: Binding<Int>, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ThresholdControl(value: value, range: 1...50)
        }
    }

    private func languageRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.language)
                    .font(.system(size: 12, weight: .semibold))
                Text(L.languageSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            languageSelector
        }
    }

    private var languageSelector: some View {
        HStack(spacing: 3) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    settings.language = language
                } label: {
                    Text(language.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: 68, height: 24)
                        .foregroundStyle(settings.language == language ? Color.primary : Color.secondary)
                        .background(
                            Capsule()
                                .fill(settings.language == language ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045))
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(Capsule())
        .frame(width: 148)
    }

    private func healthRow(_ title: String, value: String, good: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(good ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 13, tint: Color.white.opacity(0.08), stroke: Color.primary.opacity(0.08))
    }

    private func tokenCostSummaryCard(_ details: UsageDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.tokenCost)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L.ledgerRecordCount(details.scannedFiles))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            detailSummaryRow(L.today, aggregate: details.today)
            detailSummaryRow(L.thisWeek, aggregate: details.week)
            detailSummaryRow(L.thisMonth, aggregate: details.month)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 13, tint: Color.white.opacity(0.08), stroke: Color.primary.opacity(0.08))
    }

    private func accountUsageSection(title: String, usage: [String: UsageAggregate], maxRows: Int? = nil) -> some View {
        sectionCard(title: title) {
            let rows = usage
                .map { AccountUsageSummary(email: $0.key, aggregate: $0.value) }
                .sorted { model.displayName(for: $0.email) < model.displayName(for: $1.email) }
            let visibleRows = Array(rows.prefix(maxRows ?? rows.count))
            if rows.isEmpty {
                Text(L.noAttributedUsage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRows, id: \.email) { row in
                    compactUsageRow(label: model.displayName(for: row.email), value: Format.summary(row.aggregate))
                }
                if visibleRows.count < rows.count {
                    compactUsageRow(label: L.more(rows.count - visibleRows.count), value: "")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func compactUsageRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .font(.system(size: 11))
    }

    private func metricRow(_ label: String, value: String, cost: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text("\(value) · \(cost)")
                .fontWeight(.semibold)
        }
        .font(.system(size: 12))
    }

    private func detailSummaryRow(_ label: String, aggregate: UsageAggregate) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.summary(aggregate))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
    }
}
