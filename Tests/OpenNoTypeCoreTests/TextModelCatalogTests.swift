import Foundation
import XCTest
@testable import OpenNoTypeCore

final class TextModelCatalogTests: KoreanPresentationTestCase {
    func testOpenAICatalogUsesDirectModelIDsAndOfficialPrices() throws {
        let models = TextModelCatalog.entries(for: .openAI)
        let luna = try XCTUnwrap(models.first { $0.id == "gpt-6-luna" })
        XCTAssertEqual(luna.price.inputUSDPerMillion, 0.10)
        XCTAssertEqual(luna.price.outputUSDPerMillion, 0.50)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models {
            XCTAssertFalse(model.id.contains("/"), "OpenRouter IDs cannot be sent to the direct OpenAI endpoint")
            XCTAssertEqual(model.price.asOf, "2026-10-15")
            XCTAssertEqual(model.price.sourceURL.absoluteString, "https://developers.openai.com/api/docs/pricing")
        }
        XCTAssertNil(TextModelCatalog.entry(id: "openai/gpt-6-luna", provider: .openAI))
        XCTAssertNil(TextModelCatalog.entry(id: "gpt-6-luna", provider: .openRouter))
        XCTAssertNotNil(TextModelCatalog.entry(id: "openai/gpt-6-luna", provider: .openRouter))
        XCTAssertNil(TextModelCatalog.entry(id: "gpt-4.1-nano", provider: .openAI),
                     "Do not newly recommend a model scheduled to shut down on 2026-10-23")
        XCTAssertNotNil(TextModelCatalog.entry(id: "gpt-5.4-nano", provider: .openAI))
    }

    func testOpenAIChoicesKeepTheExistingDefaultAndPriceOrder() {
        let models = TextModelCatalog.entries(for: .openAI)
        let defaultModel = ProviderDefaults.forProvider(.openAI).textModel
        XCTAssertEqual(defaultModel, "gpt-4.1-mini")
        XCTAssertTrue(models.contains { $0.id == defaultModel })
        let rates = models.map { $0.price.inputUSDPerMillion + $0.price.outputUSDPerMillion }
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertNil(TextModelCatalog.entry(id: "my-custom-model", provider: .openAI))
    }

    func testCatalogHasDiversePaidChoicesWithDatedPublicPriceSources() {
        let models = TextModelCatalog.entries(for: .openRouter)
        XCTAssertGreaterThanOrEqual(models.count, 20)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertGreaterThanOrEqual(Set(models.compactMap { $0.id.split(separator: "/").first }).count, 8)
        for model in models {
            XCTAssertFalse(model.title.isEmpty)
            XCTAssertTrue(model.price.inputUSDPerMillion.isFinite && model.price.inputUSDPerMillion > 0)
            XCTAssertTrue(model.price.outputUSDPerMillion.isFinite && model.price.outputUSDPerMillion > 0)
            XCTAssertEqual(model.price.asOf, "2026-10-06")
            XCTAssertEqual(model.price.sourceURL.absoluteString, "https://openrouter.ai/api/v1/models")
        }
    }

    func testIdenticalModelIDsKeepProviderSpecificPrices() throws {
        let routed = try XCTUnwrap(TextModelCatalog.entry(id: "openai/gpt-oss-120b", provider: .openRouter))
        let direct = try XCTUnwrap(TextModelCatalog.entry(id: "openai/gpt-oss-120b", provider: .groq))
        XCTAssertEqual(routed.price.inputUSDPerMillion, 0.037, accuracy: 0.0000001)
        XCTAssertEqual(routed.price.outputUSDPerMillion, 0.17, accuracy: 0.0000001)
        XCTAssertEqual(direct.price.inputUSDPerMillion, 0.15, accuracy: 0.0000001)
        XCTAssertEqual(direct.price.outputUSDPerMillion, 0.60, accuracy: 0.0000001)
        XCTAssertEqual(direct.price.sourceURL.host, "console.groq.com")
        XCTAssertNil(TextModelCatalog.entry(id: "openai/gpt-oss-120b", provider: .openAI))
    }

    func testCatalogOmitsCostlyReasoningVariantAndUnstableOrSpecializedChoices() {
        let ids = TextModelCatalog.entries(for: .openRouter).map(\.id)
        XCTAssertFalse(ids.contains("openai/gpt-6-luna-pro"))
        for id in ids {
            XCTAssertFalse(id.contains(":free") || id.contains("preview") || id.contains("coder") || id.contains("batch"))
            XCTAssertFalse(id.hasPrefix("openrouter/"))
        }
        XCTAssertNil(TextModelCatalog.entry(id: "custom/not-in-catalog", provider: .openRouter))
        XCTAssertNotNil(TextModelCatalog.entry(id: ProviderDefaults.forProvider(.anthropic).textModel, provider: .anthropic))
    }

    func testExistingChoicesAndDefaultsRemainAvailableWithoutChangingDefaults() {
        let routedIDs = Set(TextModelCatalog.entries(for: .openRouter).map(\.id))
        XCTAssertTrue(routedIDs.isSuperset(of: ["openai/gpt-oss-120b", "qwen/qwen3-30b-a3b-instruct-2507", "google/gemini-3.1-flash-lite"]))
        XCTAssertEqual(ProviderDefaults.forProvider(.openRouter).textModel, "openai/gpt-4.1-mini")
        XCTAssertEqual(ProviderDefaults.forProvider(.groq).textModel, "openai/gpt-oss-120b")
        XCTAssertTrue(routedIDs.contains(ProviderDefaults.forProvider(.openRouter).textModel))
        XCTAssertTrue(TextModelCatalog.entries(for: .groq).map(\.id).contains(ProviderDefaults.forProvider(.groq).textModel))
    }

    func testDiscountAndMandatoryReasoningConditionsAreVisibleMetadata() {
        for id in ["upstage/solar-mini4", "upstage/solar-pro4"] {
            XCTAssertTrue(TextModelCatalog.entry(id: id, provider: .openRouter)?.note?.contains("할인") == true)
        }
        for id in ["z-ai/glm-5.3-flash", "google/gemini-3.5-flash-lite"] {
            XCTAssertTrue(TextModelCatalog.entry(id: id, provider: .openRouter)?.note?.contains("추론을 끌 수 없는") == true)
        }
    }
}
