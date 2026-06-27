import Foundation

struct UsageAutomationPolicy {
    struct ReminderAction: Equatable {
        let signature: String
        let account: CodexAccount
        let used: Int
        let remaining: Int
    }

    struct SwitchSuggestion: Equatable {
        let signature: String
        let active: CodexAccount
        let candidate: CodexAccount
        let activeRemaining: Int
        let candidateRemaining: Int
    }

    let accounts: [CodexAccount]
    let reminderEnabled: Bool
    let reminderThreshold: Int
    let autoSwitchEnabled: Bool
    let autoSwitchThreshold: Int
    let date: Date
    let calendar: Calendar

    func reminder(excluding lastSignature: String?) -> ReminderAction? {
        guard reminderEnabled,
              let active = activeAccount,
              let used = active.usagePercent else { return nil }
        let remaining = remainingPercent(fromUsed: used)
        guard remaining <= reminderThreshold else { return nil }
        let signature = reminderSignature(account: active, threshold: reminderThreshold)
        guard signature != lastSignature else { return nil }
        return ReminderAction(signature: signature, account: active, used: used, remaining: remaining)
    }

    func switchSuggestion(excluding lastSignature: String?) -> SwitchSuggestion? {
        guard autoSwitchEnabled,
              let active = activeAccount,
              let used = active.usagePercent else { return nil }
        let activeRemaining = remainingPercent(fromUsed: used)
        guard activeRemaining <= autoSwitchThreshold else { return nil }

        let candidates = accounts
            .filter { !$0.isActive }
            .compactMap { account -> (CodexAccount, Int)? in
                guard let candidateRemaining = Format.remainingPercent(fromUsed: account.fiveHourUsedPercent) else { return nil }
                return (account, candidateRemaining)
            }
            .filter { $0.1 > activeRemaining }
            .filter { $0.1 > autoSwitchThreshold }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return left.0.label < right.0.label
            }
        guard let best = candidates.first else { return nil }

        let signature = "\(active.email):\(activeRemaining)->\(best.0.email):\(best.1)-\(autoSwitchThreshold)"
        guard signature != lastSignature else { return nil }
        return SwitchSuggestion(
            signature: signature,
            active: active,
            candidate: best.0,
            activeRemaining: activeRemaining,
            candidateRemaining: best.1
        )
    }

    private var activeAccount: CodexAccount? {
        accounts.first(where: { $0.isActive })
    }

    private func remainingPercent(fromUsed used: Int) -> Int {
        max(0, min(100, 100 - used))
    }

    private func reminderSignature(account: CodexAccount, threshold: Int) -> String {
        let day = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        return "\(account.identity)-\(threshold)-\(day)"
    }
}
