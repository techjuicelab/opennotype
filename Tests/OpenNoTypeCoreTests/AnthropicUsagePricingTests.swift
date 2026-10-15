import XCTest
@testable import OpenNoTypeCore

final class AnthropicUsagePricingTests: XCTestCase {
    private let rates: [(model: String, input: Double, output: Double, cached: Double)] = [
        ("claude-haiku-4-5-20251001", 1, 5, 0.10),
        ("claude-sonnet-4-6", 3, 15, 0.30),
        ("claude-opus-4-6", 5, 25, 0.50),
        ("claude-haiku-5-5", 0.10, 0.50, 0.01),
        ("claude-sonnet-5-5", 2, 10, 0.10),
        ("claude-opus-5-5", 4, 20, 0.20),
        ("claude-fable-5-1", 10, 50, 0.25)
    ]

    func testEveryClaudeChoiceHasMatchingReferenceAndEstimatedRatesIncludingCacheReads() throws {
        for item in rates {
            let usage = ProviderUsage(provider: .anthropic, model: item.model, stage: .textProcessing,
                inputTokens: 100, outputTokens: 200, cachedInputTokens: 1_000, reasoningTokens: 100)
            let cost = UsagePricing.cost(for: usage)
            let price = try XCTUnwrap(TextModelCatalog.entry(id: item.model, provider: .anthropic)?.price)
            XCTAssertEqual(cost.kind, .estimated, item.model)
            // Claude reports uncached input separately from cache reads, which may exceed input_tokens.
            let expected = (100 * item.input + 1_000 * item.cached + 200 * item.output) / 1_000_000
            XCTAssertEqual(try XCTUnwrap(cost.usd), expected, accuracy: 1e-12, item.model)
            XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, price.inputUSDPerMillion, item.model)
            XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, price.outputUSDPerMillion, item.model)
            XCTAssertEqual(cost.rateSnapshot?.cachedInputPerMillion, item.cached, item.model)
            XCTAssertEqual(cost.checkedAt, price.asOf, item.model)
            XCTAssertEqual(cost.sourceURL, price.sourceURL.absoluteString, item.model)
            var withoutReasoning = usage; withoutReasoning.reasoningTokens = nil
            XCTAssertEqual(UsagePricing.cost(for: withoutReasoning).usd, cost.usd,
                           "Thinking tokens are already included in output_tokens")
        }
    }

    func testHaikuFiveFiveThresholdCountsCacheReadsAndChangesTheEntireRequestOnlyAbove100000() throws {
        for (input, cached, multiplier) in [(90_000, 9_999, 1.0), (90_000, 10_000, 1.0),
                                           (90_000, 10_001, 5.0), (1, 100_000, 5.0), (100_001, 0, 5.0)] {
            let usage = ProviderUsage(provider: .anthropic, model: "claude-haiku-5-5", stage: .textProcessing,
                inputTokens: input, outputTokens: 100, cachedInputTokens: cached)
            let cost = UsagePricing.cost(for: usage)
            let expected = (Double(input) * 0.10 + Double(cached) * 0.01 + 100 * 0.50) * multiplier / 1_000_000
            XCTAssertEqual(try XCTUnwrap(cost.usd), expected, accuracy: 1e-12)
            XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, 0.10 * multiplier)
            XCTAssertEqual(cost.rateSnapshot?.cachedInputPerMillion, 0.01 * multiplier)
            XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, 0.50 * multiplier)
        }
        for item in rates where item.model != "claude-haiku-5-5" {
            let usage = ProviderUsage(provider: .anthropic, model: item.model, stage: .textProcessing,
                inputTokens: 90_000, outputTokens: 100, cachedInputTokens: 20_000)
            XCTAssertEqual(UsagePricing.cost(for: usage).rateSnapshot?.inputPerMillion, item.input, item.model)
        }
    }

    func testUnknownModelsAndUnresolvedCacheWriteDurationNeverBecomeFreeEstimates() {
        for item in rates {
            let base = ProviderUsage(provider: .anthropic, model: item.model, stage: .textProcessing,
                inputTokens: 100, outputTokens: 100)
            var events: [ProviderUsage] = []
            var missing = base; missing.outputTokens = nil; events.append(missing)
            var negative = base; negative.cachedInputTokens = -1; events.append(negative)
            var cacheWrite = base; cacheWrite.cacheWriteTokens = 1; events.append(cacheWrite)
            var audio = base; audio.audioInputTokens = 1; events.append(audio)
            var reasoning = base; reasoning.reasoningTokens = 101; events.append(reasoning)
            var future = base; future.reportedModel = item.model + "-future"; events.append(future)
            var failed = base; failed.outcome = .failed; events.append(failed)
            for usage in events {
                XCTAssertEqual(UsagePricing.cost(for: usage).kind, .unavailable, item.model)
                XCTAssertNil(UsagePricing.cost(for: usage).usd, item.model)
            }
        }
        let alias = ProviderUsage(provider: .anthropic, model: "claude-haiku-4-5", stage: .textProcessing,
                                  inputTokens: 100, outputTokens: 100)
        XCTAssertEqual(UsagePricing.cost(for: alias).kind, .estimated)
    }

    func testAllClaudeCatalogChoicesReachComparisonBudgetGatingAndHaveRepairReservations() throws {
        let example = ModelEvaluationCase(transcript: "제브 설정 확인", approvedText: "JEV 설정 확인")
        let request = ProcessingRequest(mode: .dictation, transcript: "제브 설정 확인", previousOutput: "제브 설정 확인")
        for item in rates {
            let companion = item.model == "claude-haiku-5-5" ? "claude-haiku-4-5-20251001" : "claude-haiku-5-5"
            do {
                let plan = try JevModelEvaluation.plan(cases: [example], models: [item.model, companion],
                    provider: .anthropic, decisionProvider: .typeSafe, dictionary: [], budgetUSD: 0.20)
                XCTAssertGreaterThan(plan.estimatedReservationUSD, 0, item.model)
            } catch {
                guard case .exceedsBudget(let estimate) = error as? ModelEvaluationError else {
                    return XCTFail("A known Claude model must reach the budget gate: \(item.model), \(error)")
                }
                XCTAssertGreaterThan(estimate, 0.20, item.model)
            }
            let config = ProviderConfiguration(provider: .anthropic, apiKey: "not-used", transcriptionModel: "", textModel: item.model)
            XCTAssertGreaterThan(try XCTUnwrap(JevRepairPolicy.repairReservationUSD(request: request, configuration: config)), 0, item.model)
        }
    }
}
