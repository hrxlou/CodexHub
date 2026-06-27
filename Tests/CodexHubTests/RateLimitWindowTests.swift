import XCTest
@testable import CodexHub

final class RateLimitWindowTests: XCTestCase {
    func testKindInferenceUsesWindowDurationWhenAvailable() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: 5 * 60,
                resetsAt: nil,
                observedAt: observedAt,
                fallback: .unknown
            ),
            .fiveHour
        )
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: 7 * 24 * 60,
                resetsAt: nil,
                observedAt: observedAt,
                fallback: .unknown
            ),
            .weekly
        )
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: 30 * 24 * 60,
                resetsAt: nil,
                observedAt: observedAt,
                fallback: .unknown
            ),
            .monthly
        )
    }

    func testKindInferenceFallsBackForExpiredOrMissingReset() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: nil,
                resetsAt: nil,
                observedAt: observedAt,
                fallback: .weekly
            ),
            .weekly
        )
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: nil,
                resetsAt: observedAt.addingTimeInterval(-1),
                observedAt: observedAt,
                fallback: .monthly
            ),
            .monthly
        )
    }

    func testKindInferencePreservesFallbackWhenDurationIsMissing() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyResetSoon = observedAt.addingTimeInterval(2 * 60 * 60)
        let monthlyReset = observedAt.addingTimeInterval(10 * 24 * 60 * 60)

        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: nil,
                resetsAt: weeklyResetSoon,
                observedAt: observedAt,
                fallback: .weekly
            ),
            .weekly
        )
        XCTAssertEqual(
            AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: nil,
                resetsAt: monthlyReset,
                observedAt: observedAt,
                fallback: .monthly
            ),
            .monthly
        )
    }

    func testDisplayTextUsesTimeForFiveHourAndDateForLongerWindows() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: HubSettings.Keys.language)
        let reset = Date(timeIntervalSince1970: 1_782_432_000)
        let fiveHour = AppServerRateLimitWindow(displayPercent: 42, resetsAt: reset, kind: .fiveHour)
        let weekly = AppServerRateLimitWindow(displayPercent: 42, resetsAt: reset, kind: .weekly)

        XCTAssertTrue(fiveHour.displayText(fallbackKind: .fiveHour).contains(":"))
        XCTAssertFalse(weekly.displayText(fallbackKind: .weekly).contains(":"))
    }
}
