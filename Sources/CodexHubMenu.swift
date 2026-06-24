import AppKit
import Foundation
import SwiftUI

struct CodexHubMenu: View {
    @ObservedObject var model: CodexHubModel
    @ObservedObject var settings: HubSettings
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
            Image(nsImage: HubImages.appIcon)
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("CodexHub")
                    .font(.system(size: 18, weight: .semibold))
            }
            Spacer()
            if panel == .usage {
                HubActionButton(title: "Settings", systemImage: "gearshape", iconOnly: true) {
                    panel = .settings
                }
            } else {
                HubActionButton(title: "Back", systemImage: "chevron.left", compact: true) {
                    panel = .usage
                }
            }
        }
    }

    private var accountGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(model.sortedAccounts.prefix(2), id: \.email) { account in
                    AccountCardView(model: model, account: account)
                }
            }
        }
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
                    Text("Switching account")
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
                    Text("Token Cost")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Details")
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
                    Text("Today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.summary(model.usage.today))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Divider().opacity(0.45)
                metricRow("Input", value: Format.tokens(model.usage.today.totals.billedInputTokens), cost: Format.money(model.usage.today.costs.inputCost), icon: "tray.and.arrow.down")
                metricRow("Cache", value: Format.tokens(model.usage.today.totals.cachedInputTokens), cost: Format.money(model.usage.today.costs.cachedInputCost), icon: "internaldrive")
                metricRow("Output", value: Format.tokens(model.usage.today.totals.outputTokens), cost: Format.money(model.usage.today.costs.outputCost), icon: "arrow.up.right")
                metricRow("Reasoning", value: Format.tokens(model.usage.today.totals.reasoningOutputTokens), cost: Format.money(model.usage.today.costs.reasoningCost), icon: "brain.head.profile")
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
        .help("Open token cost details")
    }

    private var byAccountCard: some View {
        sectionCard(title: "By Account Today") {
            if model.todayByAccountRows.isEmpty {
                Text("No attributed usage yet")
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
        VStack(alignment: .leading, spacing: 12) {
            if model.isLoadingDetails && model.usageDetails == nil {
                sectionCard(title: "Token Cost") {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading usage details")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                let details = model.usageDetails ?? UsageDetailSnapshot(
                    today: model.usage.today,
                    week: model.usage.weekLocal,
                    month: model.usage.monthLocal,
                    recentDaily: model.usage.recentDaily,
                    scannedFiles: model.usage.scannedFiles,
                    lastError: model.usage.lastError
                )

                tokenCostSummaryCard(details)

                sectionCard(title: "Recent") {
                    if details.recentDaily.isEmpty {
                        Text("No recent usage")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(details.recentDaily.prefix(7).enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(Format.day(row.0))
                                    .lineLimit(1)
                                Spacer()
                                Text(Format.summary(row.1))
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
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
            HubActionButton(title: "Quit", systemImage: "power", tone: .danger) {
                NSApp.terminate(nil)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: "Automation") {
                settingToggle(
                    title: "Quota API",
                    subtitle: "Use codex-auth API for 5H and weekly quota",
                    isOn: Binding(get: { settings.quotaAPIEnabled }, set: { model.setQuotaAPIEnabled($0) })
                )
                Divider().opacity(0.45)
                settingToggle(
                    title: "Launch at login",
                    subtitle: "Open CodexHub automatically after sign-in",
                    isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })
                )
                Divider().opacity(0.45)
                settingToggle(
                    title: "Usage reminder",
                    subtitle: "Notify when remaining 5H limit is low",
                    isOn: Binding(get: { settings.usageReminderEnabled }, set: { settings.usageReminderEnabled = $0 })
                )
                thresholdRow(
                    title: "Reminder threshold",
                    value: Binding(get: { settings.reminderThreshold }, set: { settings.reminderThreshold = $0 }),
                    detail: "remaining"
                )
                Divider().opacity(0.45)
                settingToggle(
                    title: "Auto switch",
                    subtitle: "Switch to the account with more 5H limit left",
                    isOn: Binding(get: { settings.autoSwitchEnabled }, set: { settings.autoSwitchEnabled = $0 })
                )
                thresholdRow(
                    title: "Switch threshold",
                    value: Binding(get: { settings.autoSwitchThreshold }, set: { settings.autoSwitchThreshold = $0 }),
                    detail: "remaining"
                )
            }

            sectionCard(title: "Status") {
                healthRow("Auth", value: model.accounts.isEmpty ? "Missing" : "OK", good: model.accounts.isEmpty == false)
                healthRow("Quota API", value: model.quotaAPIStatus.label, good: model.quotaAPIStatus.isHealthy)
                healthRow("Codex", value: FileManager.default.fileExists(atPath: "/Applications/Codex.app") ? "Found" : "Missing", good: FileManager.default.fileExists(atPath: "/Applications/Codex.app"))
                healthRow("Refresh", value: model.isRefreshing ? "Updating" : "Ready", good: !model.isRefreshing)
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
                    .lineLimit(1)
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
                Text("Token Cost")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(details.scannedFiles) files scanned")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            detailSummaryRow("Today", aggregate: details.today)
            detailSummaryRow("This Week", aggregate: details.week)
            detailSummaryRow("This Month", aggregate: details.month)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 13, tint: Color.white.opacity(0.08), stroke: Color.primary.opacity(0.08))
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
