import XCTest
@testable import CodexHub

final class PricingCatalogTests: XCTestCase {
    func testPriceBookLoadsFromSwiftPMResources() {
        let catalog = ModelPricingCatalog.load()

        XCTAssertNotEqual(catalog.models, ModelPricingCatalog.fallback.models)
        XCTAssertEqual(catalog.defaultRates, ModelRates(input: 1.25, cachedInput: 0.125, output: 10.0))
        XCTAssertEqual(catalog.rates(for: "gpt-5-mini"), ModelRates(input: 0.25, cachedInput: 0.025, output: 2.0))
    }

    func testAliasAndFallbackLookup() {
        let catalog = ModelPricingCatalog.load()

        XCTAssertEqual(catalog.rates(for: "gpt-5.1-codex-max"), catalog.rates(for: "gpt-5.1-codex"))
        XCTAssertEqual(catalog.rates(for: "missing-model"), catalog.defaultRates)
        XCTAssertEqual(catalog.rates(for: nil), catalog.defaultRates)
    }
}
