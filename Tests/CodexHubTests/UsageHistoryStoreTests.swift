import XCTest
@testable import CodexHub

final class UsageHistoryStoreTests: XCTestCase {
    func testReplaceRowsMergesDuplicateDateAccountModelRows() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("usage-history.json")
        let store = UsageHistoryStore(fileURL: url, calendar: stableCalendar)
        let now = stableDate("2026-06-27T12:00:00Z")
        let day = stableCalendar.startOfDay(for: now)

        store.replaceRows([
            row(day: day, account: "a@example.com", model: "gpt-5", input: 100),
            row(day: day, account: "a@example.com", model: "gpt-5", input: 200),
            row(day: day, account: "b@example.com", model: "gpt-5", input: 300)
        ], now: now)

        let rows = store.loadRows(now: now)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.accountEmail == "a@example.com" }?.totals.inputTokens, 300)
        XCTAssertEqual(rows.first { $0.accountEmail == "b@example.com" }?.totals.inputTokens, 300)
    }

    func testReplaceRowsPrunesRowsOlderThanRetention() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("usage-history.json")
        let store = UsageHistoryStore(fileURL: url, calendar: stableCalendar, retentionDays: 365)
        let now = stableDate("2026-06-27T12:00:00Z")
        let current = stableCalendar.startOfDay(for: now)
        let old = stableCalendar.date(byAdding: .day, value: -365, to: current)!

        store.replaceRows([
            row(day: old, account: "old@example.com", model: "gpt-5", input: 100),
            row(day: current, account: "new@example.com", model: "gpt-5", input: 200)
        ], now: now)

        let rows = store.loadRows(now: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.accountEmail, "new@example.com")
    }

    func testClearRemovesOnlyHistoryFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let historyURL = root.appendingPathComponent("usage-history.json")
        let otherURL = root.appendingPathComponent("other.json")
        let store = UsageHistoryStore(fileURL: historyURL, calendar: stableCalendar)
        try "keep".write(to: otherURL, atomically: true, encoding: .utf8)

        store.replaceRows([
            row(day: stableCalendar.startOfDay(for: stableDate("2026-06-27T12:00:00Z")), account: "a@example.com", model: "gpt-5", input: 100)
        ], now: stableDate("2026-06-27T12:00:00Z"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))

        store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path))
    }

    private var stableCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func row(day: Date, account: String, model: String, input: Int) -> UsageHistoryRow {
        let totals = TokenTotals(
            inputTokens: input,
            cachedInputTokens: 0,
            outputTokens: 10,
            reasoningOutputTokens: 0,
            totalTokens: input + 10
        )
        return UsageHistoryRow(
            date: day,
            accountEmail: account,
            model: model,
            totals: totals,
            costs: CostTotals(totals: totals, rates: ModelPricingCatalog.fallback.defaultRates),
            updatedAt: day
        )
    }

    private func stableDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)!
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHubTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
