import Foundation
import SwiftUI

extension CodexHubMenu {
    var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: L.preferences) {
                languageRow()
                Divider().opacity(0.45)
                menuBarDisplayPicker
                Divider().opacity(0.45)
                settingToggle(
                    title: L.launchAtLogin,
                    subtitle: L.launchAtLoginSubtitle,
                    isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })
                )
            }

            sectionCard(title: L.automation) {
                settingToggle(
                    title: L.usageReminder,
                    subtitle: L.usageReminderSubtitle,
                    isOn: Binding(
                        get: { settings.usageReminderEnabled },
                        set: { enabled in
                            settings.usageReminderEnabled = enabled
                            if enabled {
                                model.refresh(force: true)
                            }
                        }
                    )
                )
                if settings.usageReminderEnabled {
                    thresholdRow(
                        title: L.reminderThreshold,
                        value: Binding(
                            get: { settings.reminderThreshold },
                            set: { threshold in
                                settings.reminderThreshold = threshold
                                model.refresh(force: true)
                            }
                        ),
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

            sectionCard(title: L.advanced) {
                disclosureRow(title: L.privacy, isExpanded: $privacySettingsExpanded)
                if privacySettingsExpanded {
                    privacyControls
                }
                Divider().opacity(0.45)
                disclosureRow(title: L.status, isExpanded: $statusExpanded)
                if statusExpanded {
                    statusControls
                }
            }
        }
    }

    private var menuBarDisplayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.menuBarDisplay)
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                menuBarDisplayChip(L.menuBarAccountName, isOn: Binding(get: { settings.menuBarShowsAccountName }, set: { settings.menuBarShowsAccountName = $0 }))
                menuBarDisplayChip(L.menuBarFiveHour, isOn: Binding(get: { settings.menuBarShowsFiveHour }, set: { settings.menuBarShowsFiveHour = $0 }))
                menuBarDisplayChip(L.menuBarWeekly, isOn: Binding(get: { settings.menuBarShowsWeekly }, set: { settings.menuBarShowsWeekly = $0 }))
                menuBarDisplayChip(L.menuBarTokens, isOn: Binding(get: { settings.menuBarShowsTokens }, set: { settings.menuBarShowsTokens = $0 }))
                menuBarDisplayChip(L.menuBarCost, isOn: Binding(get: { settings.menuBarShowsCost }, set: { settings.menuBarShowsCost = $0 }))
            }
        }
    }

    private var privacyControls: some View {
        VStack(spacing: 10) {
            destructiveSettingRow(
                title: L.attributionHistory,
                subtitle: L.attributionHistorySubtitle,
                buttonTitle: L.clearMap
            ) {
                model.resetAttributionHistory()
            }
            Divider().opacity(0.45)
            destructiveSettingRow(
                title: L.dashboardHistory,
                subtitle: L.dashboardHistorySubtitle,
                buttonTitle: L.clearData
            ) {
                model.clearDashboardHistory()
            }
        }
        .padding(.top, 2)
    }

    private var statusControls: some View {
        VStack(spacing: 7) {
            settingToggle(
                title: L.quotaAPI,
                subtitle: L.quotaAPISubtitle,
                isOn: Binding(get: { settings.quotaAPIEnabled }, set: { model.setQuotaAPIEnabled($0) })
            )
            Divider().opacity(0.45)
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
        .padding(.top, 2)
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

    private func menuBarDisplayChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary.opacity(0.72))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isOn.wrappedValue ? Color.accentColor : Color.primary.opacity(0.055))
            )
            .overlay(
                Capsule()
                    .stroke(isOn.wrappedValue ? Color.clear : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func disclosureRow(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func destructiveSettingRow(title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer()
            HubActionButton(title: buttonTitle, systemImage: "trash", tone: .danger, action: action)
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
}
