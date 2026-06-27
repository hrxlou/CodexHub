import XCTest
@testable import CodexHub

final class TokenUsageScannerParsingTests: XCTestCase {
    private var previousCodexHome: String?

    override func setUp() {
        super.setUp()
        previousCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
    }

    override func tearDown() {
        if let previousCodexHome {
            setenv("CODEX_HOME", previousCodexHome, 1)
        } else {
            unsetenv("CODEX_HOME")
        }
        super.tearDown()
    }

    func testScanParsesLastTurnCumulativeDeltaAndIgnoresDuplicateFootprints() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHubTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let codexHome = temporaryRoot.appendingPathComponent("codex-home", isDirectory: true)
        let cacheURL = temporaryRoot.appendingPathComponent("usage-ledger.json")
        let attributionURL = temporaryRoot.appendingPathComponent("attribution-events.json")
        let sessionFile = try makeSessionFile(in: codexHome)
        setenv("CODEX_HOME", codexHome.path, 1)

        let now = ISO8601DateFormatter.codexHubTest.string(from: Date())
        let lines = [
            #"{"type":"turn_context","timestamp":"\#(now)","payload":{"model":"gpt-5-mini"}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":200,"output_tokens":400,"reasoning_output_tokens":100,"total_tokens":2400}}}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2600,"cached_input_tokens":250,"output_tokens":520,"reasoning_output_tokens":130,"total_tokens":3120}}}}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let scanner = TokenUsageScanner(accountStore: CodexAccountStore(), cacheURL: cacheURL)
        let attribution = AttributionStore(fileURL: attributionURL)
        let snapshot = scanner.scan(attribution: attribution, accounts: [])

        XCTAssertNil(snapshot.lastError)
        XCTAssertEqual(snapshot.scannedFiles, 1)
        XCTAssertEqual(snapshot.today.totals.inputTokens, 1_600)
        XCTAssertEqual(snapshot.today.totals.cachedInputTokens, 150)
        XCTAssertEqual(snapshot.today.totals.outputTokens, 320)
        XCTAssertEqual(snapshot.today.totals.reasoningOutputTokens, 80)
        XCTAssertEqual(snapshot.today.totals.totalTokens, 1_920)
        XCTAssertGreaterThan(snapshot.today.costs.totalCost, 0)

        let details = scanner.scanDetails(attribution: attribution, accounts: [])
        XCTAssertNil(details.lastError)
        XCTAssertEqual(details.month.totals.inputTokens, 1_600)
    }

    func testDashboardScanGroupsUsageByModel() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHubTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let codexHome = temporaryRoot.appendingPathComponent("codex-home", isDirectory: true)
        let cacheURL = temporaryRoot.appendingPathComponent("usage-ledger.json")
        let historyURL = temporaryRoot.appendingPathComponent("usage-history.json")
        let attributionURL = temporaryRoot.appendingPathComponent("attribution-events.json")
        let sessionFile = try makeSessionFile(in: codexHome, date: Date())
        setenv("CODEX_HOME", codexHome.path, 1)

        let now = ISO8601DateFormatter.codexHubTest.string(from: Date())
        let lines = [
            #"{"type":"turn_context","timestamp":"\#(now)","payload":{"model":"gpt-5-mini"}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}}"#,
            #"{"type":"turn_context","timestamp":"\#(now)","payload":{"model":"gpt-5"}}"#,
            #"{"type":"event_msg","timestamp":"\#(now)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":330}}}}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let scanner = TokenUsageScanner(accountStore: CodexAccountStore(), cacheURL: cacheURL)
        let attribution = AttributionStore(fileURL: attributionURL)
        let history = UsageHistoryStore(fileURL: historyURL)
        let snapshot = scanner.scanDashboard(attribution: attribution, accounts: [], historyStore: history, days: 30)

        XCTAssertEqual(snapshot.modelBreakdown.count, 2)
        XCTAssertEqual(snapshot.modelBreakdown.first { $0.label == "gpt-5-mini" }?.aggregate.totals.inputTokens, 100)
        XCTAssertEqual(snapshot.modelBreakdown.first { $0.label == "gpt-5" }?.aggregate.totals.inputTokens, 300)
    }

    func testDashboardScanUsesAttributionHistoryForAccountBreakdown() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHubTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let codexHome = temporaryRoot.appendingPathComponent("codex-home", isDirectory: true)
        let cacheURL = temporaryRoot.appendingPathComponent("usage-ledger.json")
        let historyURL = temporaryRoot.appendingPathComponent("usage-history.json")
        let attributionURL = temporaryRoot.appendingPathComponent("attribution-events.json")
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let firstSession = try makeSessionFile(in: codexHome, date: yesterday, name: "first.jsonl")
        let secondSession = try makeSessionFile(in: codexHome, date: Date(), name: "second.jsonl")
        setenv("CODEX_HOME", codexHome.path, 1)

        let firstTimestamp = ISO8601DateFormatter.codexHubTest.string(from: yesterday)
        let secondTimestamp = ISO8601DateFormatter.codexHubTest.string(from: Date())
        try [
            #"{"type":"turn_context","timestamp":"\#(firstTimestamp)","payload":{"model":"gpt-5"}}"#,
            #"{"type":"event_msg","timestamp":"\#(firstTimestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}}"#
        ].joined(separator: "\n").appending("\n").write(to: firstSession, atomically: true, encoding: .utf8)
        try [
            #"{"type":"turn_context","timestamp":"\#(secondTimestamp)","payload":{"model":"gpt-5"}}"#,
            #"{"type":"event_msg","timestamp":"\#(secondTimestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":330}}}}"#
        ].joined(separator: "\n").appending("\n").write(to: secondSession, atomically: true, encoding: .utf8)

        let switchTime = calendar.date(byAdding: .hour, value: 1, to: yesterday)!
        let events = [
            AttributionEvent(timestamp: Date(timeIntervalSince1970: 946_684_800), email: "first@example.com"),
            AttributionEvent(timestamp: switchTime, email: "second@example.com")
        ]
        let data = try JSONEncoder.codexHub.encode(events)
        try FileManager.default.createDirectory(at: attributionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: attributionURL)

        let scanner = TokenUsageScanner(accountStore: CodexAccountStore(), cacheURL: cacheURL)
        let attribution = AttributionStore(fileURL: attributionURL)
        let history = UsageHistoryStore(fileURL: historyURL)
        let snapshot = scanner.scanDashboard(attribution: attribution, accounts: [], historyStore: history, days: 30)

        XCTAssertEqual(snapshot.accountBreakdown.first { $0.label == "first@example.com" }?.aggregate.totals.inputTokens, 100)
        XCTAssertEqual(snapshot.accountBreakdown.first { $0.label == "second@example.com" }?.aggregate.totals.inputTokens, 300)
    }

    func testDashboardScanIncludesHistoryOlderThanCurrentMonth() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHubTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let codexHome = temporaryRoot.appendingPathComponent("codex-home", isDirectory: true)
        let cacheURL = temporaryRoot.appendingPathComponent("usage-ledger.json")
        let historyURL = temporaryRoot.appendingPathComponent("usage-history.json")
        let attributionURL = temporaryRoot.appendingPathComponent("attribution-events.json")
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let sessionFile = try makeSessionFile(in: codexHome, date: oldDate, name: "old.jsonl")
        setenv("CODEX_HOME", codexHome.path, 1)

        let timestamp = ISO8601DateFormatter.codexHubTest.string(from: oldDate)
        try [
            #"{"type":"turn_context","timestamp":"\#(timestamp)","payload":{"model":"gpt-5"}}"#,
            #"{"type":"event_msg","timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":550}}}}"#
        ].joined(separator: "\n").appending("\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let scanner = TokenUsageScanner(accountStore: CodexAccountStore(), cacheURL: cacheURL)
        let attribution = AttributionStore(fileURL: attributionURL)
        let history = UsageHistoryStore(fileURL: historyURL)
        let snapshot = scanner.scanDashboard(attribution: attribution, accounts: [], historyStore: history, days: 90)

        XCTAssertEqual(snapshot.total.totals.inputTokens, 500)
        XCTAssertEqual(snapshot.dailySeries.first { Calendar.current.isDate($0.date, inSameDayAs: oldDate) }?.aggregate.totals.inputTokens, 500)
    }

    private func makeSessionFile(in codexHome: URL) throws -> URL {
        try makeSessionFile(in: codexHome, date: Date())
    }

    private func makeSessionFile(in codexHome: URL, date: Date, name: String = "session.jsonl") throws -> URL {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let directory = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", components.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", components.day ?? 0), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}

private extension ISO8601DateFormatter {
    static var codexHubTest: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
