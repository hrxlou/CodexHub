import XCTest
@testable import CodexHub

final class AppServerRateLimitParserTests: XCTestCase {
    func testParsesRateLimitsByLimitIdAndPlanType() {
        let line = """
        {"jsonrpc":"2.0","id":2,"result":{"rateLimitsByLimitId":{"other":{"primary":{"used_percent":99}},"codex":{"primary":{"used_percent":42.4,"resets_at":1800003600,"window_duration_mins":300},"secondary":{"used_percent":12,"resets_at":1800604800,"window_duration_mins":10080},"plan_type":"chatgpt_plus"}}}}
        """

        let limits = AppServerRateLimitParser.parseJSONRPCLine(line)

        XCTAssertEqual(limits?.planType, "chatgpt_plus")
        XCTAssertEqual(limits?.primary?.displayPercent, 42)
        XCTAssertEqual(limits?.primary?.displayKind(fallback: .unknown), .fiveHour)
        XCTAssertEqual(limits?.secondary?.displayPercent, 12)
        XCTAssertEqual(limits?.secondary?.displayKind(fallback: .unknown), .weekly)
    }

    func testParsesCamelCaseFallbackSnapshot() {
        let line = """
        {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":101,"resetsAt":1800003600,"windowDurationMins":43200},"planType":"chatgpt_pro"}}}
        """

        let limits = AppServerRateLimitParser.parseJSONRPCLine(line)

        XCTAssertEqual(limits?.planType, "chatgpt_pro")
        XCTAssertEqual(limits?.primary?.displayPercent, 100)
        XCTAssertEqual(limits?.primary?.displayKind(fallback: .unknown), .monthly)
        XCTAssertNil(limits?.secondary)
    }

    func testIgnoresNonRateLimitResponses() {
        XCTAssertNil(AppServerRateLimitParser.parseJSONRPCLine(#"{"jsonrpc":"2.0","id":1,"result":{}}"#))
        XCTAssertNil(AppServerRateLimitParser.parseJSONRPCLine("not-json"))
    }
}
