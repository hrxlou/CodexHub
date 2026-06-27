import AppKit
import SwiftUI

extension CodexHubMenu {
    var accountGrid: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                Text(L.accounts)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HubActionButton(title: L.manageAccounts, systemImage: "person.crop.circle.badge.gearshape", compact: true, titleOnly: true) {
                    panel = .accountManagement
                }
            }
            if model.sortedAccounts.count <= 2 {
                LazyVGrid(columns: accountColumns, spacing: 10) {
                    ForEach(model.sortedAccounts, id: \.identity) { account in
                        AccountCardView(model: model, account: account) { selected in
                            pendingSwitchAccountIdentity = selected.identity
                        }
                    }
                    if model.sortedAccounts.count < 2 {
                        AddAccountCardView(isAddingAccount: model.isAddingAccount) {
                            model.addAccount()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    accountGridBody

                    if accountsExpanded {
                        HStack {
                            Spacer()
                            HubActionButton(title: L.collapseAccounts, systemImage: "chevron.up", compact: true) {
                                accountsExpanded = false
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: model.sortedAccounts.count) { _, count in
            if count <= 4 {
                accountsExpanded = false
            }
        }
    }

    var usageCard: some View {
        Button {
            panel = .costDetails
            model.loadDashboard(force: false)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                Divider().opacity(0.45)
                metricRow(L.input, value: Format.tokens(model.usage.today.totals.billedInputTokens), cost: Format.money(model.usage.today.costs.inputCost), icon: "tray.and.arrow.down")
                metricRow(L.cache, value: Format.tokens(model.usage.today.totals.cachedInputTokens), cost: Format.money(model.usage.today.costs.cachedInputCost), icon: "internaldrive")
                metricRow(L.output, value: Format.tokens(model.usage.today.totals.outputTokens), cost: Format.money(model.usage.today.costs.outputCost), icon: "arrow.up.right")
                metricRow(L.reasoning, value: Format.tokens(model.usage.today.totals.reasoningOutputTokens), cost: Format.money(model.usage.today.costs.reasoningCost), icon: "brain.head.profile")
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(
                cornerRadius: 10,
                tint: Color.white.opacity(tokenCostHover ? 0.10 : 0.065),
                stroke: Color.primary.opacity(tokenCostHover ? 0.13 : 0.075),
                hovering: tokenCostHover
            )
        }
        .buttonStyle(.plain)
        .onHover { tokenCostHover = $0 }
        .help(L.openTokenCostDetails)
    }

    var byAccountCard: some View {
        sectionCard(title: L.byAccountToday) {
            let rows = model.todayByAccountRows
            let visibleRows = Array(rows.prefix(3))
            if rows.isEmpty {
                Text(L.noAttributedUsage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRows, id: \.email) { row in
                    HStack {
                        Text(model.displayName(for: row.email))
                            .lineLimit(1)
                        Spacer()
                        Text(Format.summary(row.aggregate))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .font(.system(size: 12))
                }
                if visibleRows.count < rows.count {
                    HStack {
                        Text(L.more(rows.count - visibleRows.count))
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    var footer: some View {
        HStack(spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text(Format.relative(model.lastRefreshDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
            }
            Spacer()
            RefreshButton(isRefreshing: model.isRefreshing) {
                model.refresh(force: true)
            }
            HubActionButton(title: L.quit, systemImage: "power", tone: .danger, compact: true) {
                NSApp.terminate(nil)
            }
        }
    }

    private var accountColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 14),
            GridItem(.flexible(minimum: 0), spacing: 14)
        ]
    }

    private var accountGridBody: some View {
        Group {
            if accountGridShouldScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    accountGridCells
                        .padding(.trailing, 4)
                        .padding(.bottom, 10)
                }
                .frame(height: 300)
            } else {
                accountGridCells
            }
        }
    }

    private var accountGridCells: some View {
        LazyVGrid(columns: accountColumns, spacing: 10) {
            ForEach(visibleAccountCards, id: \.identity) { account in
                AccountCardView(model: model, account: account) { selected in
                    pendingSwitchAccountIdentity = selected.identity
                }
            }

            if accountGridShowMoreCount > 0 {
                AccountGridActionCardView(
                    title: L.showAllAccounts,
                    subtitle: L.more(accountGridShowMoreCount),
                    systemImage: "chevron.down"
                ) {
                    accountsExpanded = true
                }
            } else if model.sortedAccounts.count == 3 {
                AddAccountCardView(isAddingAccount: model.isAddingAccount) {
                    model.addAccount()
                }
            }
        }
    }

    private var visibleAccountCards: [CodexAccount] {
        if accountsExpanded || model.sortedAccounts.count <= 4 {
            return model.sortedAccounts
        }
        return Array(model.sortedAccounts.prefix(3))
    }

    private var accountGridShowMoreCount: Int {
        guard !accountsExpanded else { return 0 }
        return max(0, model.sortedAccounts.count - visibleAccountCards.count)
    }

    private var accountGridShouldScroll: Bool {
        accountsExpanded && accountGridContentHeight > 300
    }

    private var accountGridContentHeight: CGFloat {
        let cardHeight: CGFloat = 126
        let rowSpacing: CGFloat = 10
        let rowCount = CGFloat((visibleAccountCards.count + 1) / 2)
        return rowCount * cardHeight + max(0, rowCount - 1) * rowSpacing
    }

    private func metricRow(_ label: String, value: String, cost: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(Color.secondary.opacity(0.72))
            Text(label)
            Spacer()
            Text("\(value) · \(cost)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }
}
