import SwiftUI

extension CodexHubMenu {
    var accountManagementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: L.accountManagement) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.addCodexAccount)
                            .font(.system(size: 12, weight: .semibold))
                        Text(L.addCodexAccountSubtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    HubActionButton(
                        title: model.isAddingAccount ? L.signingIn : L.addAccount,
                        systemImage: model.isAddingAccount ? "hourglass" : "plus",
                        compact: true
                    ) {
                        model.addAccount()
                    }
                    .disabled(model.isAddingAccount)
                }
            }

            sectionCard(title: L.storedAccounts) {
                let storedAccounts = model.accounts
                if storedAccounts.isEmpty {
                    Text(L.noStoredAccounts)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(storedAccounts, id: \.identity) { account in
                        accountManagementRow(account)
                        if account.identity != storedAccounts.last?.identity {
                            Divider().opacity(0.45)
                        }
                    }
                }
            }
        }
    }

    private func accountManagementRow(_ account: CodexAccount) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.label)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if account.isActive {
                            Text(L.active)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(account.email)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Text(account.plan)
                        Text(account.lastActivity)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                if !account.isActive {
                    HubActionButton(
                        title: model.removingAccountIdentity == account.identity ? L.removing : L.removeAccount,
                        systemImage: "trash",
                        tone: .danger,
                        compact: true
                    ) {
                        pendingRemoveAccountIdentity = account.identity
                    }
                    .disabled(model.removingAccountIdentity != nil)
                    .help(L.removeAccount)
                }
            }
        }
    }
}
