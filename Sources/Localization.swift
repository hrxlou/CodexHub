import Foundation

enum L {
    private static var currentLanguage: AppLanguage { AppLanguage.current }

    static func text(ko: String, en: String) -> String {
        currentLanguage == .korean ? ko : en
    }

    static var settings: String { text(ko: "설정", en: "Settings") }
    static var back: String { text(ko: "뒤로", en: "Back") }
    static var dashboard: String { text(ko: "대시보드", en: "Dashboard") }
    static var openDashboard: String { text(ko: "상세 대시보드 열기", en: "Open Dashboard") }
    static var accounts: String { text(ko: "계정", en: "Accounts") }
    static var manageAccounts: String { text(ko: "계정 관리", en: "Manage Accounts") }
    static var showAllAccounts: String { text(ko: "모두 보기", en: "Show All") }
    static var collapseAccounts: String { text(ko: "접기", en: "Collapse") }
    static var accountManagement: String { text(ko: "계정 관리", en: "Account Management") }
    static var addCodexAccount: String { text(ko: "Codex 계정 추가", en: "Add Codex Account") }
    static var addCodexAccountSubtitle: String { text(ko: "본인이 사용할 수 있는 계정만 추가하세요", en: "Add only accounts you are authorized to use") }
    static var addAccount: String { text(ko: "추가", en: "Add") }
    static var signingIn: String { text(ko: "로그인 중", en: "Signing in") }
    static var storedAccounts: String { text(ko: "저장된 계정", en: "Stored Accounts") }
    static var noStoredAccounts: String { text(ko: "저장된 계정이 없습니다", en: "No stored accounts") }
    static var removeAccount: String { text(ko: "삭제", en: "Remove") }
    static var removing: String { text(ko: "삭제 중", en: "Removing") }
    static var switchingAccount: String { text(ko: "계정 전환 중", en: "Switching account") }
    static var tokenCost: String { text(ko: "토큰 사용량", en: "Token Usage") }
    static var details: String { text(ko: "상세", en: "Details") }
    static var today: String { text(ko: "오늘", en: "Today") }
    static var input: String { text(ko: "입력", en: "Input") }
    static var cache: String { text(ko: "캐시", en: "Cache") }
    static var output: String { text(ko: "출력", en: "Output") }
    static var reasoning: String { text(ko: "추론", en: "Reasoning") }
    static var byAccountToday: String { text(ko: "오늘 계정별 사용량", en: "By Account Today") }
    static var noAttributedUsage: String { text(ko: "아직 계정별 사용량이 없습니다", en: "No attributed usage yet") }
    static var loadingUsageDetails: String { text(ko: "사용량 정보를 불러오는 중", en: "Loading usage data") }
    static var recent: String { text(ko: "최근", en: "Recent") }
    static var noRecentUsage: String { text(ko: "최근 사용량이 없습니다", en: "No recent usage") }
    static var byAccountThisWeek: String { text(ko: "이번 주 계정별 사용량", en: "By Account This Week") }
    static var byAccountThisMonth: String { text(ko: "이번 달 계정별 사용량", en: "By Account This Month") }
    static var quit: String { text(ko: "종료", en: "Quit") }
    static var preferences: String { text(ko: "설정", en: "Preferences") }
    static var language: String { text(ko: "표시 언어", en: "Language") }
    static var languageSubtitle: String { text(ko: "앱 화면에 표시할 언어", en: "Language shown in the app") }
    static var quotaAPI: String { text(ko: "할당량 상세 조회", en: "Detailed quota lookup") }
    static var quotaAPISubtitle: String { text(ko: "Codex의 상세 할당량 상태를 조회합니다", en: "Fetch detailed quota status from Codex") }
    static var launchAtLogin: String { text(ko: "로그인 시 실행", en: "Launch at login") }
    static var launchAtLoginSubtitle: String { text(ko: "Mac에 로그인하면 CodexHub를 자동으로 엽니다", en: "Open CodexHub automatically when you sign in") }
    static var automation: String { text(ko: "알림 및 제안", en: "Reminders and suggestions") }
    static var usageReminder: String { text(ko: "5시간 한도 알림", en: "5-hour limit reminder") }
    static var usageReminderSubtitle: String { text(ko: "5시간 한도 잔여량이 설정값 이하이면 알립니다", en: "Notify when 5-hour remaining quota is below the threshold") }
    static var reminderThreshold: String { text(ko: "알림 시점", en: "Reminder threshold") }
    static var remaining: String { text(ko: "5시간 한도 잔여량", en: "5-hour quota remaining") }
    static var accountSuggestion: String { text(ko: "계정 전환 제안", en: "Account switch suggestion") }
    static var accountSuggestionSubtitle: String { text(ko: "5시간 한도 잔여량이 낮으면 전환할 계정을 제안합니다", en: "Suggest another account when 5-hour remaining quota is low") }
    static var accountSuggestionPolicyNote: String { text(ko: "", en: "") }
    static var suggestionThreshold: String { text(ko: "제안 시점", en: "Suggestion threshold") }
    static var privacy: String { text(ko: "개인정보", en: "Privacy") }
    static var attributionHistory: String { text(ko: "계정 연결 기록", en: "Attribution history") }
    static var attributionHistorySubtitle: String { text(ko: "사용량을 계정에 연결한 기록을 삭제합니다", en: "Clear the mapping between usage and accounts") }
    static var dashboardHistory: String { text(ko: "대시보드 사용량 데이터", en: "Dashboard usage data") }
    static var dashboardHistorySubtitle: String { text(ko: "집계 데이터만 삭제하고 원본 로그는 유지합니다", en: "Clear aggregates only; original logs are kept") }
    static var clearMap: String { text(ko: "기록 삭제", en: "Clear History") }
    static var clearData: String { text(ko: "데이터 삭제", en: "Clear Data") }
    static var status: String { text(ko: "상태", en: "Status") }
    static var auth: String { text(ko: "로그인", en: "Sign-in") }
    static var codex: String { text(ko: "Codex", en: "Codex") }
    static var refresh: String { text(ko: "새로고침", en: "Refresh") }
    static var refreshing: String { text(ko: "새로고침 중", en: "Refreshing") }
    static var found: String { text(ko: "확인됨", en: "Found") }
    static var missing: String { text(ko: "없음", en: "Missing") }
    static var ok: String { text(ko: "정상", en: "OK") }
    static var updating: String { text(ko: "업데이트 중", en: "Updating") }
    static var ready: String { text(ko: "대기 중", en: "Ready") }
    static var advanced: String { text(ko: "고급", en: "Advanced") }
    static var unavailable: String { text(ko: "사용 불가", en: "Unavailable") }
    static var thisWeek: String { text(ko: "이번 주", en: "This Week") }
    static var thisMonth: String { text(ko: "이번 달", en: "This Month") }
    static var active: String { text(ko: "활성", en: "Active") }
    static var switchAccount: String { text(ko: "전환", en: "Switch") }
    static var activeAccount: String { text(ko: "활성 계정", en: "Active account") }
    static var openTokenCostDetails: String { text(ko: "토큰 사용량 상세 보기", en: "Open token usage details") }
    static var ledgerRecords: String { text(ko: "사용 기록", en: "ledger records") }
    static var menuBarDisplay: String { text(ko: "메뉴바 표시", en: "Menu bar display") }
    static var menuBarAccountName: String { text(ko: "이름", en: "Name") }
    static var menuBarFiveHour: String { text(ko: "5H", en: "5H") }
    static var menuBarWeekly: String { text(ko: "1W", en: "1W") }
    static var menuBarTokens: String { text(ko: "토큰", en: "Tokens") }
    static var menuBarCost: String { text(ko: "비용", en: "Cost") }

    static var quotaAPIUpdateFailed: String { text(ko: "할당량 상세 조회 설정을 바꾸지 못했습니다", en: "Could not update detailed quota lookup") }
    static var quotaAPIEnabled: String { text(ko: "할당량 상세 조회가 켜졌습니다", en: "Detailed quota lookup enabled") }
    static var quotaAPIDisabled: String { text(ko: "할당량 상세 조회가 꺼졌습니다", en: "Detailed quota lookup disabled") }
    static var attributionHistoryReset: String { text(ko: "계정 연결 기록을 삭제했습니다", en: "Attribution history reset") }
    static var dashboardHistoryCleared: String { text(ko: "대시보드 사용량 데이터를 삭제했습니다", en: "Dashboard usage data cleared") }
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
    static var codexActiveThreadsTitle: String { text(ko: "진행 중인 Codex 작업이 있습니다", en: "Codex has active work") }
    static var authorizedAccountOnly: String { text(ko: "타인 계정 저장 불가", en: "Do not store others' accounts") }
    static var totalCost: String { text(ko: "총 비용", en: "Total cost") }
    static var billingTokens: String { text(ko: "청구 토큰", en: "Billable tokens") }
    static var tokenTrend: String { text(ko: "사용량 추세", en: "Usage trend") }
    static var byAccount: String { text(ko: "계정별", en: "By Account") }
    static var byModel: String { text(ko: "모델별", en: "By Model") }
    static var last30Days: String { text(ko: "최근 30일", en: "Last 30 days") }
    static var periodSummary: String { text(ko: "기간 요약", en: "Period Summary") }
    static var peakDay: String { text(ko: "최고 사용일", en: "Peak Day") }
    static var peakWeek: String { text(ko: "최고 사용 주", en: "Peak Week") }
    static var peakMonth: String { text(ko: "최고 사용 월", en: "Peak Month") }
    static var activeDays: String { text(ko: "사용한 날", en: "Active days") }
    static var dailyAverage: String { text(ko: "일평균", en: "Daily average") }
    static var weeklyAverage: String { text(ko: "주평균", en: "Weekly average") }
    static var monthlyAverage: String { text(ko: "월평균", en: "Monthly average") }
    static var todayShare: String { text(ko: "오늘 비중", en: "Today's share") }
    static var topAccountShare: String { text(ko: "상위 계정 비중", en: "Top account share") }
    static var activityPattern: String { text(ko: "활동 패턴", en: "Activity pattern") }
    static var noUsageInRange: String { text(ko: "선택한 기간 사용량이 없습니다", en: "No usage in this range") }
    static var noDashboardData: String { text(ko: "아직 표시할 대시보드 데이터가 없습니다", en: "No dashboard data yet") }
    static var date: String { text(ko: "날짜", en: "Date") }

    static func more(_ count: Int) -> String {
        text(ko: "+\(count)개 더", en: "+\(count) more")
    }

    static func days(_ count: Int) -> String {
        text(ko: "\(count)일", en: "\(count)d")
    }

    static func switchToAccount(_ email: String) -> String {
        text(
            ko: "\(email) 계정으로 전환합니다.",
            en: "Switch to \(email)."
        )
    }

    static func removeAccountMessage(_ email: String) -> String {
        text(ko: "\(email) 계정의 저장된 로그인 정보를 삭제할까요?", en: "Remove the stored login for \(email)?")
    }

    static func ledgerRecordCount(_ count: Int) -> String {
        text(ko: "사용 기록 \(count)개", en: "\(count) \(ledgerRecords)")
    }

    static func usageScanProgress(completed: Int, total: Int) -> String {
        guard total > 0 else {
            return text(ko: "사용 기록 확인 중", en: "Checking usage records")
        }
        return text(ko: "\(total)개 파일 중 \(completed)개 확인 중", en: "Scanning \(completed) of \(total) files")
    }

    static func autoSwitchMessage(
        activeAccount: String,
        activeQuotaLabel: String,
        activeRemaining: Int,
        candidateAccount: String,
        candidateQuotaLabel: String,
        candidateRemaining: Int
    ) -> String {
        text(
            ko: "\(activeAccount) \(activeQuotaLabel) \(activeRemaining)% 남음. \(candidateAccount) \(candidateQuotaLabel) \(candidateRemaining)% 남음. 승인 후 전환됩니다.",
            en: "\(activeAccount): \(activeRemaining)% \(activeQuotaLabel) left. \(candidateAccount): \(candidateRemaining)% \(candidateQuotaLabel) left. Switches only after approval."
        )
    }

    static func codexActiveThreadsSwitchMessage(
        activeCount: Int,
        waitingOnApprovalCount: Int,
        waitingOnUserInputCount: Int
    ) -> String {
        let waitingCount = waitingOnApprovalCount + waitingOnUserInputCount
        if waitingCount > 0 {
            return text(
                ko: "Codex 앱에 승인 또는 입력을 기다리는 작업을 포함해 \(activeCount)개의 진행 중인 작업이 있습니다. 계정을 전환하면 해당 작업이 중단되거나 계정 상태가 바뀔 수 있습니다. 계속 전환할까요?",
                en: "The Codex app has \(activeCount) active local thread(s), including work waiting for approval or input. Switching accounts may interrupt that work or change its account state. Continue switching?"
            )
        }
        return text(
            ko: "Codex 앱에 \(activeCount)개의 진행 중인 작업이 있습니다. 계정을 전환하면 해당 작업이 중단되거나 계정 상태가 바뀔 수 있습니다. 계속 전환할까요?",
            en: "The Codex app has \(activeCount) active local thread(s). Switching accounts may interrupt that work or change its account state. Continue switching?"
        )
    }

    static func usageReminderBody(accountLabel: String, quotaLabel: String, used: Int, remaining: Int) -> String {
        text(
            ko: "\(accountLabel) 계정의 \(quotaLabel) 사용량은 \(used)%입니다. \(remaining)% 남았습니다.",
            en: "\(accountLabel) account is at \(used)% \(quotaLabel) usage. \(remaining)% remains."
        )
    }
}
