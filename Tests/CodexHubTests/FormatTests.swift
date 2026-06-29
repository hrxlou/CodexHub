import XCTest
@testable import CodexHub

final class FormatTests: XCTestCase {
    private var previousLanguage: String?

    override func setUp() {
        super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: HubSettings.Keys.language)
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: HubSettings.Keys.language)
    }

    override func tearDown() {
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: HubSettings.Keys.language)
        } else {
            UserDefaults.standard.removeObject(forKey: HubSettings.Keys.language)
        }
        super.tearDown()
    }

    func testRemainingPercentClampsAndHandlesNil() {
        XCTAssertNil(Format.remainingPercent(fromUsed: nil))
        XCTAssertEqual(Format.remainingPercent(fromUsed: -20), 100)
        XCTAssertEqual(Format.remainingPercent(fromUsed: 35), 65)
        XCTAssertEqual(Format.remainingPercent(fromUsed: 140), 0)
    }

    func testPercentAndMoneyFormatting() {
        XCTAssertEqual(Format.percentUsed(nil), "--")
        XCTAssertEqual(Format.percentUsed(-1), "0%")
        XCTAssertEqual(Format.percentUsed(42), "42%")
        XCTAssertEqual(Format.percentUsed(140), "100%")
        XCTAssertEqual(Format.percentRemaining(fromUsed: nil), "--")
        XCTAssertEqual(Format.percentRemaining(fromUsed: 42), "58%")
        XCTAssertEqual(Format.money(1.234), "$1.23")
        XCTAssertEqual(Format.money(1.235), "$1.24")
    }

    func testTokenFormattingUsesLanguageSpecificCompaction() {
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(1_500), "1.5k")
        XCTAssertEqual(Format.tokens(2_000_000), "2m")

        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: HubSettings.Keys.language)
        XCTAssertEqual(Format.tokens(1_500), "2천")
        XCTAssertEqual(Format.tokens(25_000), "3만")
    }

    func testPreciseTokenFormattingKeepsDashboardDetail() {
        XCTAssertEqual(Format.preciseTokens(2_112_000_000), "2.11b")
        XCTAssertEqual(Format.preciseTokens(25_500_000), "25.5m")

        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: HubSettings.Keys.language)
        XCTAssertEqual(Format.preciseTokens(2_112_000_000), "21.12억")
        XCTAssertEqual(Format.preciseTokens(90_630_000), "9063만")
    }

    func testChartAxisDateUsesCompactLabels() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 29
        let date = components.date!

        XCTAssertEqual(Format.chartAxisDate(date), "Jun 29")
        XCTAssertEqual(Format.chartAxisDate(date, component: .month), "Jun")

        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: HubSettings.Keys.language)
        XCTAssertEqual(Format.chartAxisDate(date), "6월 29일")
        XCTAssertEqual(Format.chartAxisDate(date, component: .month), "6월")
    }

    func testQuotaResetParsesUsageText() {
        XCTAssertEqual(Format.quotaReset(from: "60% (09:05)", kind: .fiveHour), "09:05")
        XCTAssertEqual(Format.quotaReset(from: "60% (2026-06-26)", kind: .weekly), "Jun 26")
        XCTAssertEqual(Format.quotaReset(from: "-", kind: .fiveHour), "--:--")
        XCTAssertEqual(Format.quotaReset(from: "-", kind: .weekly), "--")
    }

    func testUsageProgressAndRecordCountsAreLocalizedNaturally() {
        XCTAssertEqual(L.ledgerRecordCount(125), "125 ledger records")
        XCTAssertEqual(L.usageScanProgress(completed: 12, total: 125), "Scanning 12 of 125 files")

        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: HubSettings.Keys.language)
        XCTAssertEqual(L.ledgerRecordCount(125), "사용 기록 125개")
        XCTAssertEqual(L.usageScanProgress(completed: 12, total: 125), "125개 파일 중 12개 확인 중")
    }
}
