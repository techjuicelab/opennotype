import XCTest
@testable import OpenNoTypeCore

final class AnthropicModelCatalogTests: KoreanPresentationTestCase {
    func testClaudeCatalogContainsVerifiedModelsAndKeepsTheExistingPinnedDefault() {
        let entries = TextModelCatalog.entries(for: .anthropic)
        XCTAssertEqual(Set(entries.map(\.id)), ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-6",
                                              "claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"])
        XCTAssertEqual(entries.count, 7)
        XCTAssertEqual(ProviderDefaults.forProvider(.anthropic).textModel, "claude-haiku-4-5-20251001")
        XCTAssertNotNil(TextModelCatalog.entry(id: ProviderDefaults.forProvider(.anthropic).textModel, provider: .anthropic))
        for entry in entries {
            XCTAssertEqual(entry.price.asOf, "2026-10-15")
            XCTAssertEqual(entry.price.sourceURL.absoluteString, "https://platform.claude.com/docs/en/about-claude/pricing")
            XCTAssertFalse(entry.id.contains("/"), "Direct Claude IDs must not use routed prefixes")
        }
        let rates = entries.map { $0.price.inputUSDPerMillion + $0.price.outputUSDPerMillion }
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertNil(TextModelCatalog.entry(id: "claude-custom-future", provider: .anthropic))
    }

    func testClaudePriceConditionsAndRequiredThinkingAreVisibleBeforeSelection() {
        let haiku = TextModelCatalog.entry(id: "claude-haiku-5-5", provider: .anthropic)
        XCTAssertEqual(haiku?.price.inputUSDPerMillion, 0.10)
        XCTAssertEqual(haiku?.price.outputUSDPerMillion, 0.50)
        XCTAssertTrue(haiku?.note?.contains("100,000") == true)
        XCTAssertTrue(haiku?.note?.contains("캐시 읽기·쓰기") == true)
        for id in ["claude-opus-5-5", "claude-fable-5-1"] {
            XCTAssertTrue(TextModelCatalog.entry(id: id, provider: .anthropic)?.note?.contains("추론을 끌 수 없는") == true)
        }
    }
}
