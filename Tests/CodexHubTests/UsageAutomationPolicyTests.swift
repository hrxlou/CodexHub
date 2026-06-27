import XCTest
@testable import CodexHub

final class UsageAutomationPolicyTests: XCTestCase {
    func testReminderFiresOncePerSignatureWhenRemainingIsBelowThreshold() {
        let active = account(identity: "active", email: "active@example.com", used: 95, active: true)
        let policy = UsageAutomationPolicy(
            accounts: [active],
            reminderEnabled: true,
            reminderThreshold: 10,
            autoSwitchEnabled: false,
            autoSwitchThreshold: 10,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: Calendar(identifier: .gregorian)
        )

        let reminder = policy.reminder(excluding: nil)

        XCTAssertEqual(reminder?.account.identity, "active")
        XCTAssertEqual(reminder?.used, 95)
        XCTAssertEqual(reminder?.remaining, 5)
        XCTAssertNil(policy.reminder(excluding: reminder?.signature))
    }

    func testReminderDoesNotFireWhenDisabledOrAboveThreshold() {
        let active = account(identity: "active", email: "active@example.com", used: 50, active: true)
        let policy = UsageAutomationPolicy(
            accounts: [active],
            reminderEnabled: true,
            reminderThreshold: 10,
            autoSwitchEnabled: false,
            autoSwitchThreshold: 10,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertNil(policy.reminder(excluding: nil))
    }

    func testSwitchSuggestionChoosesHighestRemainingCandidateAboveThreshold() {
        let active = account(identity: "active", email: "active@example.com", used: 95, active: true)
        let lowerCandidate = account(identity: "lower", email: "lower@example.com", used: 80, active: false)
        let bestCandidate = account(identity: "best", email: "best@example.com", used: 10, active: false)
        let policy = UsageAutomationPolicy(
            accounts: [active, lowerCandidate, bestCandidate],
            reminderEnabled: false,
            reminderThreshold: 10,
            autoSwitchEnabled: true,
            autoSwitchThreshold: 10,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: Calendar(identifier: .gregorian)
        )

        let suggestion = policy.switchSuggestion(excluding: nil)

        XCTAssertEqual(suggestion?.active.identity, "active")
        XCTAssertEqual(suggestion?.candidate.identity, "best")
        XCTAssertEqual(suggestion?.activeRemaining, 5)
        XCTAssertEqual(suggestion?.candidateRemaining, 90)
        XCTAssertNil(policy.switchSuggestion(excluding: suggestion?.signature))
    }

    func testSwitchSuggestionRequiresCandidateAboveActiveAndThreshold() {
        let active = account(identity: "active", email: "active@example.com", used: 95, active: true)
        let belowThreshold = account(identity: "low", email: "low@example.com", used: 92, active: false)
        let policy = UsageAutomationPolicy(
            accounts: [active, belowThreshold],
            reminderEnabled: false,
            reminderThreshold: 10,
            autoSwitchEnabled: true,
            autoSwitchThreshold: 10,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertNil(policy.switchSuggestion(excluding: nil))
    }

    private func account(identity: String, email: String, used: Int, active: Bool) -> CodexAccount {
        CodexAccount(
            selector: identity,
            identity: identity,
            email: email,
            alias: nil,
            plan: "chatgpt_plus",
            fiveHourUsage: "\(used)%",
            fiveHourUsedPercent: used,
            fiveHourQuotaKind: .fiveHour,
            weeklyUsage: "-",
            weeklyUsedPercent: nil,
            weeklyQuotaKind: nil,
            lastActivity: "-",
            lastUsedAt: nil,
            isActive: active
        )
    }
}
