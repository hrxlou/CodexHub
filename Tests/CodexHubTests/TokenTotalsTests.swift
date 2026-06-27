import XCTest
@testable import CodexHub

final class TokenTotalsTests: XCTestCase {
    func testNormalizationClampsInvalidValues() {
        let totals = TokenTotals(
            inputTokens: 100,
            cachedInputTokens: 150,
            outputTokens: 20,
            reasoningOutputTokens: 25,
            totalTokens: 0
        ).normalized()

        XCTAssertEqual(totals.inputTokens, 100)
        XCTAssertEqual(totals.cachedInputTokens, 100)
        XCTAssertEqual(totals.outputTokens, 20)
        XCTAssertEqual(totals.reasoningOutputTokens, 20)
        XCTAssertEqual(totals.totalTokens, 120)
        XCTAssertEqual(totals.billedInputTokens, 0)
        XCTAssertEqual(totals.billingTokenTotal, 120)
    }

    func testDeltaAndAdding() {
        let previous = TokenTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 30, reasoningOutputTokens: 10, totalTokens: 130)
        let current = TokenTotals(inputTokens: 250, cachedInputTokens: 40, outputTokens: 90, reasoningOutputTokens: 30, totalTokens: 340)
        let delta = current.delta(since: previous)

        XCTAssertEqual(delta, TokenTotals(inputTokens: 150, cachedInputTokens: 20, outputTokens: 60, reasoningOutputTokens: 20, totalTokens: 210))
        XCTAssertEqual(previous.adding(delta), current)
    }

    func testLegacyCacheReadInputTokensDecoding() throws {
        let json = """
        {
          "input_tokens": 1000,
          "cache_read_input_tokens": 250,
          "output_tokens": 100,
          "reasoning_output_tokens": 20,
          "total_tokens": 1100
        }
        """
        let totals = try JSONDecoder().decode(TokenTotals.self, from: Data(json.utf8))

        XCTAssertEqual(totals.cachedInputTokens, 250)
        XCTAssertEqual(totals.billedInputTokens, 750)
        XCTAssertEqual(totals.billingTokenTotal, 1_100)
    }
}
