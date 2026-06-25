import Foundation

enum L {
    private static var currentLanguage: AppLanguage { AppLanguage.current }

    static func text(ko: String, en: String) -> String {
        currentLanguage == .korean ? ko : en
    }

    static var settings: String { text(ko: "설정", en: "Settings") }
    static var back: String { text(ko: "뒤로", en: "Back") }
    static var accounts: String { text(ko: "계정", en: "Accounts") }
    static var manageAccounts: String { text(ko: "계정 관리", en: "Accounts") }
    static var accountManagement: String { text(ko: "계정 관리", en: "Account Management") }
    static var addCodexAccount: String { text(ko: "Codex 계정 추가", en: "Add Codex Account") }
    static var addCodexAccountSubtitle: String { text(ko: "본인 소유 또는 사용 권한이 있는 계정만 저장", en: "Store only accounts you own or are authorized to use") }
    static var addAccount: String { text(ko: "추가", en: "Add") }
    static var signingIn: String { text(ko: "로그인 중", en: "Signing in") }
    static var storedAccounts: String { text(ko: "저장된 계정", en: "Stored Accounts") }
    static var noStoredAccounts: String { text(ko: "저장된 계정이 없습니다", en: "No stored accounts") }
    static var removeAccount: String { text(ko: "삭제", en: "Remove") }
    static var removing: String { text(ko: "삭제 중", en: "Removing") }
    static var switchingAccount: String { text(ko: "계정 전환 중", en: "Switching account") }
    static var tokenCost: String { text(ko: "토큰 비용", en: "Token Cost") }
    static var details: String { text(ko: "상세", en: "Details") }
    static var today: String { text(ko: "오늘", en: "Today") }
    static var input: String { text(ko: "입력", en: "Input") }
    static var cache: String { text(ko: "캐시", en: "Cache") }
    static var output: String { text(ko: "출력", en: "Output") }
    static var reasoning: String { text(ko: "추론", en: "Reasoning") }
    static var byAccountToday: String { text(ko: "오늘 계정별 사용량", en: "By Account Today") }
    static var noAttributedUsage: String { text(ko: "아직 계정별 사용량이 없습니다", en: "No attributed usage yet") }
    static var loadingUsageDetails: String { text(ko: "사용량 상세 정보를 불러오는 중", en: "Loading usage details") }
    static var recent: String { text(ko: "최근", en: "Recent") }
    static var noRecentUsage: String { text(ko: "최근 사용량이 없습니다", en: "No recent usage") }
    static var byAccountThisWeek: String { text(ko: "이번 주 계정별 사용량", en: "By Account This Week") }
    static var byAccountThisMonth: String { text(ko: "이번 달 계정별 사용량", en: "By Account This Month") }
    static var quit: String { text(ko: "종료", en: "Quit") }
    static var preferences: String { text(ko: "설정", en: "Preferences") }
    static var language: String { text(ko: "표시 언어", en: "Language") }
    static var languageSubtitle: String { text(ko: "앱에서 사용할 언어", en: "Language used in the app UI") }
    static var quotaAPI: String { text(ko: "상세 상태 조회 (실험적)", en: "Detailed status lookup (experimental)") }
    static var quotaAPISubtitle: String { text(ko: "조회가 불안정하면 끄세요", en: "Turn off if status is unreliable") }
    static var launchAtLogin: String { text(ko: "로그인 시 실행", en: "Launch at login") }
    static var launchAtLoginSubtitle: String { text(ko: "로그인하면 CodexHub 자동 실행", en: "Open CodexHub automatically after sign-in") }
    static var automation: String { text(ko: "알림 및 제안", en: "Reminders and suggestions") }
    static var usageReminder: String { text(ko: "사용량 알림", en: "Usage reminder") }
    static var usageReminderSubtitle: String { text(ko: "5H 잔여량이 적으면 알림", en: "Notify when 5H remaining is low") }
    static var reminderThreshold: String { text(ko: "알림 시점", en: "Reminder threshold") }
    static var remaining: String { text(ko: "남았을 때", en: "remaining") }
    static var accountSuggestion: String { text(ko: "전환 제안", en: "Switch suggestion") }
    static var accountSuggestionSubtitle: String { text(ko: "잔여량이 적으면 승인 전 제안만 표시", en: "Only asks before switching when usage is low") }
    static var accountSuggestionPolicyNote: String { text(ko: "OpenAI 또는 조직의 한도/정책 우회 용도로 사용하지 마세요.", en: "Do not use this to bypass OpenAI or organization limits or policies.") }
    static var suggestionThreshold: String { text(ko: "제안 시점", en: "Suggestion threshold") }
    static var privacy: String { text(ko: "개인정보", en: "Privacy") }
    static var attributionHistory: String { text(ko: "계정 연결 기록", en: "Attribution history") }
    static var attributionHistorySubtitle: String { text(ko: "사용량과 계정을 연결한 기록만 삭제", en: "Clears saved usage-to-account mapping only") }
    static var clearMap: String { text(ko: "기록 삭제", en: "Clear History") }
    static var status: String { text(ko: "상태", en: "Status") }
    static var auth: String { text(ko: "인증", en: "Auth") }
    static var codex: String { text(ko: "Codex", en: "Codex") }
    static var refresh: String { text(ko: "새로고침", en: "Refresh") }
    static var refreshing: String { text(ko: "새로고침 중", en: "Refreshing") }
    static var found: String { text(ko: "확인됨", en: "Found") }
    static var missing: String { text(ko: "없음", en: "Missing") }
    static var ok: String { text(ko: "정상", en: "OK") }
    static var updating: String { text(ko: "업데이트 중", en: "Updating") }
    static var ready: String { text(ko: "대기 중", en: "Ready") }
    static var thisWeek: String { text(ko: "이번 주", en: "This Week") }
    static var thisMonth: String { text(ko: "이번 달", en: "This Month") }
    static var active: String { text(ko: "활성", en: "Active") }
    static var switchAccount: String { text(ko: "전환", en: "Switch") }
    static var activeAccount: String { text(ko: "활성 계정", en: "Active account") }
    static var openTokenCostDetails: String { text(ko: "토큰 비용 상세 보기", en: "Open token cost details") }
    static var ledgerRecords: String { text(ko: "사용 기록", en: "ledger records") }

    static var quotaAPIUpdateFailed: String { text(ko: "상세 상태 조회 설정을 바꾸지 못했습니다", en: "Detailed status lookup update failed") }
    static var quotaAPIEnabled: String { text(ko: "상세 상태 조회가 켜졌습니다", en: "Detailed status lookup enabled") }
    static var quotaAPIDisabled: String { text(ko: "상세 상태 조회가 꺼졌습니다", en: "Detailed status lookup disabled") }
    static var attributionHistoryReset: String { text(ko: "계정 연결 기록을 삭제했습니다", en: "Attribution history reset") }
    static var switchCodexAccount: String { text(ko: "Codex 계정을 전환할까요?", en: "Switch Codex account?") }
    static var notNow: String { text(ko: "취소", en: "Cancel") }
    static var usageReminderTitle: String { text(ko: "CodexHub 사용량 알림", en: "CodexHub usage reminder") }
    static var launchAtLoginRequiresMacOS13: String { text(ko: "로그인 시 실행은 macOS 13 이상에서 지원됩니다", en: "Launch at login requires macOS 13+") }
    static var launchAtLoginEnabled: String { text(ko: "로그인 시 실행이 켜졌습니다", en: "Launch at login enabled") }
    static var launchAtLoginDisabled: String { text(ko: "로그인 시 실행이 꺼졌습니다", en: "Launch at login disabled") }
    static var notificationsEnabled: String { text(ko: "알림이 켜졌습니다", en: "Notifications enabled") }
    static var notificationsDenied: String { text(ko: "알림이 허용되지 않았습니다", en: "Notifications were not allowed") }
    static var accountLoginInProgress: String { text(ko: "Codex 로그인을 진행 중입니다", en: "Codex login is in progress") }
    static var accountSaved: String { text(ko: "Codex 계정을 저장했습니다", en: "Codex account saved") }
    static var accountLoginFailed: String { text(ko: "Codex 로그인을 완료하지 못했습니다", en: "Codex login did not complete") }
    static var codexLoginLogHint: String { text(ko: "자세한 내용은 codex-login.log를 확인하세요", en: "Check codex-login.log for details") }
    static var accountRemoved: String { text(ko: "계정을 삭제했습니다", en: "Account removed") }
    static var accountRemoveFailed: String { text(ko: "계정을 삭제하지 못했습니다", en: "Could not remove account") }
    static var activeAccountCannotBeRemoved: String { text(ko: "활성 계정은 삭제할 수 없습니다", en: "The active account cannot be removed") }
    static var codexRestartRequired: String { text(ko: "계정 전환은 완료됐습니다. Codex 앱을 수동으로 다시 열어주세요", en: "Account switched. Reopen the Codex app manually.") }
    static var codexRestartBlockedByInterrupt: String { text(ko: "계정 전환은 완료됐습니다. Codex가 작업 인터럽트 확인을 기다려 재시작을 취소했습니다. Codex 경고에서 직접 선택하세요.", en: "Account switched. Codex is waiting for an interrupt confirmation, so restart was canceled. Choose directly in the Codex prompt.") }
    static var authorizedAccountOnly: String { text(ko: "타인의 credential 공유나 저장은 지원하지 않습니다.", en: "Sharing or storing someone else's credentials is not supported.") }

    static func more(_ count: Int) -> String {
        text(ko: "+\(count)개 더", en: "+\(count) more")
    }

    static func switchToAccount(_ email: String) -> String {
        text(
            ko: "\(email) 계정으로 전환합니다. OpenAI 또는 조직의 한도/정책 우회 용도로 사용하지 마세요.",
            en: "Switch to \(email). Do not use this to bypass OpenAI or organization limits or policies."
        )
    }

    static func removeAccountMessage(_ email: String) -> String {
        text(ko: "\(email) 계정의 저장된 로그인 정보를 삭제할까요?", en: "Remove the stored login for \(email)?")
    }

    static func ledgerRecordCount(_ count: Int) -> String {
        text(ko: "\(count)개 \(ledgerRecords)", en: "\(count) \(ledgerRecords)")
    }

    static func usageScanProgress(completed: Int, total: Int) -> String {
        guard total > 0 else {
            return text(ko: "사용 기록 확인 중", en: "Checking usage records")
        }
        return text(ko: "\(completed)/\(total)개 파일 확인 중", en: "Scanning \(completed)/\(total) files")
    }

    static func autoSwitchMessage(activeAccount: String, activeRemaining: Int, candidateAccount: String, candidateRemaining: Int) -> String {
        text(
            ko: "\(activeAccount)은 5H 잔여량이 \(activeRemaining)%입니다. \(candidateAccount)은 \(candidateRemaining)% 남았습니다. 승인한 경우에만 전환됩니다. OpenAI 또는 조직의 한도/정책 우회 용도로 사용하지 마세요.",
            en: "\(activeAccount) has \(activeRemaining)% 5H remaining. \(candidateAccount) has \(candidateRemaining)% remaining. CodexHub switches only if you approve. Do not use this to bypass OpenAI or organization limits or policies."
        )
    }

    static func usageReminderBody(accountLabel: String, used: Int, remaining: Int) -> String {
        text(
            ko: "\(accountLabel) 계정의 5H 사용량은 \(used)%입니다. \(remaining)% 남았습니다.",
            en: "\(accountLabel) account is at \(used)% 5H usage. \(remaining)% remains."
        )
    }
}
