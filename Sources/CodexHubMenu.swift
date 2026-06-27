import AppKit
import Foundation
import SwiftUI

private enum AccountActionKind {
    case switchAccount
    case removeAccount
}

private struct AccountActionConfirmation {
    let kind: AccountActionKind
    let account: CodexAccount
}

struct CodexHubMenu: View {
    @ObservedObject var model: CodexHubModel
    @ObservedObject var settings: HubSettings
    @Environment(\.colorScheme) private var colorScheme
    @State var panel: HubPanel = .usage
    @State var tokenCostHover = false
    @State var accountsExpanded = false
    @State var privacySettingsExpanded = false
    @State var statusExpanded = false
    @State var pendingRemoveAccountIdentity: String?
    @State var pendingSwitchAccountIdentity: String?

    init(model: CodexHubModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if panel == .usage {
                accountGrid
                usageCard
                byAccountCard
            } else if panel == .costDetails {
                tokenCostDetails
            } else if panel == .accountManagement {
                accountManagementPanel
            } else {
                settingsPanel
            }
            if panel == .usage {
                footer
            }
        }
        .padding(15)
        .frame(width: panel == .costDetails ? 560 : 392)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.white.opacity(0.055)
            }
        )
        .onAppear {
            panel = .usage
        }
        .overlay {
            if model.isSwitchingAccount {
                switchProgressOverlay
            } else if let confirmation = activeAccountConfirmation {
                accountActionOverlay(confirmation)
            }
        }
        .onExitCommand {
            if activeAccountConfirmation != nil {
                cancelAccountActionConfirmation()
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.isSwitchingAccount)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(nsImage: HubImages.appIcon(for: colorScheme))
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("CodexHub")
                    .font(.system(size: 17, weight: .semibold))
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

    private var activeAccountConfirmation: AccountActionConfirmation? {
        if let identity = pendingSwitchAccountIdentity,
           let account = model.accounts.first(where: { $0.identity == identity }) {
            return AccountActionConfirmation(kind: .switchAccount, account: account)
        }
        if let identity = pendingRemoveAccountIdentity,
           let account = model.accounts.first(where: { $0.identity == identity }) {
            return AccountActionConfirmation(kind: .removeAccount, account: account)
        }
        return nil
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
            .glassPanel(cornerRadius: 10, tint: Color.white.opacity(0.08), stroke: Color.primary.opacity(0.09))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func accountActionOverlay(_ confirmation: AccountActionConfirmation) -> some View {
        let isSwitch = confirmation.kind == .switchAccount
        return ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isSwitch ? L.switchCodexAccount : L.removeAccount)
                        .font(.system(size: 15, weight: .semibold))
                    Text(isSwitch ? L.switchToAccount(confirmation.account.email) : L.removeAccountMessage(confirmation.account.email))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    Spacer()
                    HubActionButton(title: L.notNow, systemImage: "xmark", compact: true, titleOnly: true) {
                        cancelAccountActionConfirmation()
                    }
                    .keyboardShortcut(.cancelAction)
                    HubActionButton(
                        title: isSwitch ? L.switchAccount : L.removeAccount,
                        systemImage: isSwitch ? "arrow.triangle.2.circlepath" : "trash",
                        tone: isSwitch ? .neutral : .danger,
                        compact: true,
                        titleOnly: true
                    ) {
                        let identity = confirmation.account.identity
                        pendingSwitchAccountIdentity = nil
                        pendingRemoveAccountIdentity = nil
                        if isSwitch {
                            model.switchAccount(identity)
                        } else {
                            model.removeAccount(identity)
                        }
                    }
                    .disabled(model.removingAccountIdentity != nil || model.isSwitchingAccount)
                }
            }
            .padding(18)
            .frame(width: 300, alignment: .leading)
            .glassPanel(cornerRadius: 10, tint: Color.white.opacity(0.09), stroke: Color.primary.opacity(0.09))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func cancelAccountActionConfirmation() {
        pendingSwitchAccountIdentity = nil
        pendingRemoveAccountIdentity = nil
    }

}
