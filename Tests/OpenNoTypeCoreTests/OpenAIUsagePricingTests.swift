import XCTest
@testable import OpenNoTypeCore

final class OpenAIUsagePricingTests: XCTestCase {
    private let rates: [(model: String, input: Double, output: Double, cached: Double)] = [
        ("gpt-6-luna", 0.10, 0.50, 0.01),
        ("gpt-6-sol", 2.00, 10.00, 0.20),
        ("gpt-6.1-sol", 2.00, 10.00, 0.10),
        ("gpt-6-astra", 10.00, 50.00, 1.00),
        ("gpt-5.4-nano", 0.20, 1.25, 0.02),
        ("gpt-4.1", 2.00, 8.00, 0.50)
    ]

    func testOpenAICatalogModelsUseVerifiedRatesAndCatalogPriceEvidence() throws {
        for item in rates {
            let entry = try XCTUnwrap(TextModelCatalog.entry(id: item.model, provider: .openAI))
            let usage = ProviderUsage(provider: .openAI, model: item.model, stage: .textProcessing,
                inputTokens: 1_000, outputTokens: 100, cachedInputTokens: 400, reasoningTokens: 50)
            let cost = UsagePricing.cost(for: usage)
            XCTAssertEqual(cost.kind, .estimated, item.model)
            let expected = (600 * item.input + 400 * item.cached + 100 * item.output) / 1_000_000
            XCTAssertEqual(try XCTUnwrap(cost.usd), expected, accuracy: 1e-12, item.model)
            XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, item.input, item.model)
            XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, item.output, item.model)
            XCTAssertEqual(cost.rateSnapshot?.cachedInputPerMillion, item.cached, item.model)
            XCTAssertEqual(entry.price.inputUSDPerMillion, item.input, item.model)
            XCTAssertEqual(entry.price.outputUSDPerMillion, item.output, item.model)
            XCTAssertEqual(cost.checkedAt, entry.price.asOf, item.model)
            XCTAssertEqual(cost.sourceURL, entry.price.sourceURL.absoluteString, item.model)
            var withoutReasoning = usage
            withoutReasoning.reasoningTokens = nil
            XCTAssertEqual(UsagePricing.cost(for: withoutReasoning).usd, cost.usd,
                           "Reasoning is already included in output tokens: \(item.model)")
        }
    }

    func testVerifiedSnapshotsUseTheirCanonicalRatesAndUnknownReportedModelsFailClosed() throws {
        for (model, snapshot) in [("gpt-4.1", "gpt-4.1-2025-04-14"),
                                  ("gpt-5.4-nano", "gpt-5.4-nano-2026-03-17")] {
            let canonical = ProviderUsage(provider: .openAI, model: model, stage: .textProcessing,
                inputTokens: 1_000, outputTokens: 100, cachedInputTokens: 400)
            var reported = canonical
            reported.reportedModel = snapshot
            XCTAssertEqual(UsagePricing.cost(for: reported), UsagePricing.cost(for: canonical), snapshot)
        }
        for model in ["gpt-6-luna-2026-10-15", "gpt-6-sol-2026-10-15", "gpt-6.1-sol-2026-10-15",
                      "gpt-6-astra-2026-10-15", "gpt-4.1-future", "gpt-5.4-nano-future", "custom-future-model"] {
            let usage = ProviderUsage(provider: .openAI, model: "gpt-6-luna", reportedModel: model,
                stage: .textProcessing, inputTokens: 1_000, outputTokens: 100)
            XCTAssertEqual(UsagePricing.cost(for: usage).kind, .unavailable, model)
            XCTAssertNil(UsagePricing.cost(for: usage).usd, model)
        }
    }

    func testGPT6LongContextRatesApplyOnlyAboveTheTotalInputThreshold() throws {
        for item in rates where item.model.hasPrefix("gpt-6") {
            for input in [271_999, 272_000, 272_001] {
                let cached = 40_000
                let usage = ProviderUsage(provider: .openAI, model: item.model, stage: .textProcessing,
                    inputTokens: input, outputTokens: 100, cachedInputTokens: cached)
                let cost = UsagePricing.cost(for: usage)
                let inputMultiplier = input > 272_000 ? 2.0 : 1.0
                let outputMultiplier = input > 272_000 ? 1.5 : 1.0
                let expected = (Double(input - cached) * item.input * inputMultiplier
                    + Double(cached) * item.cached * inputMultiplier
                    + 100 * item.output * outputMultiplier) / 1_000_000
                XCTAssertEqual(try XCTUnwrap(cost.usd), expected, accuracy: 1e-12, item.model)
                XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, item.input * inputMultiplier)
                XCTAssertEqual(cost.rateSnapshot?.cachedInputPerMillion, item.cached * inputMultiplier)
                XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, item.output * outputMultiplier)
            }
        }
        for item in rates where !item.model.hasPrefix("gpt-6") {
            let usage = ProviderUsage(provider: .openAI, model: item.model, stage: .textProcessing,
                inputTokens: 272_001, outputTokens: 100, cachedInputTokens: 40_000)
            let cost = UsagePricing.cost(for: usage)
            XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, item.input, item.model)
            XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, item.output, item.model)
            XCTAssertEqual(cost.rateSnapshot?.cachedInputPerMillion, item.cached, item.model)
        }
    }

    func testNewOpenAIModelsKeepUnsupportedAndInvalidUsageUnavailable() {
        for item in rates {
            let base = ProviderUsage(provider: .openAI, model: item.model, stage: .textProcessing,
                inputTokens: 100, outputTokens: 100)
            var events: [ProviderUsage] = []
            var missing = base; missing.outputTokens = nil; events.append(missing)
            var negative = base; negative.inputTokens = -1; events.append(negative)
            var cache = base; cache.cachedInputTokens = 101; events.append(cache)
            var cacheWrite = base; cacheWrite.cacheWriteTokens = 1; events.append(cacheWrite)
            var audio = base; audio.audioInputTokens = 1; events.append(audio)
            var reasoning = base; reasoning.reasoningTokens = 101; events.append(reasoning)
            var failed = base; failed.outcome = .failed; events.append(failed)
            var cancelled = base; cancelled.outcome = .cancelled; events.append(cancelled)
            for event in events {
                XCTAssertEqual(UsagePricing.cost(for: event).kind, .unavailable, item.model)
                XCTAssertNil(UsagePricing.cost(for: event).usd, item.model)
            }
        }
    }
}
