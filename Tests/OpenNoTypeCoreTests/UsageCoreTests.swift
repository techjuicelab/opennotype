import Foundation
import XCTest
@testable import OpenNoTypeCore

final class UsageCoreTests: XCTestCase {
    func testDefaultOpenAITextRateSubtractsCachedTokensAndStoresPriceEvidence() throws {
        let event = ProviderUsage(provider: .openAI, model: "gpt-4.1-mini", reportedModel: "gpt-4.1-mini-2025-04-14",
                                  stage: .textProcessing, inputTokens: 1_000, outputTokens: 100, cachedInputTokens: 400)
        let cost = UsagePricing.cost(for: event)
        XCTAssertEqual(cost.kind, .estimated)
        XCTAssertEqual(try XCTUnwrap(cost.usd), 0.00044, accuracy: 0.00000001)
        XCTAssertEqual(cost.rateSnapshot?.inputPerMillion, 0.4)
        XCTAssertEqual(cost.checkedAt, "2026-09-10")
        XCTAssertEqual(cost.sourceURL, "https://developers.openai.com/api/docs/models/gpt-4.1-mini")
    }

    func testProviderReportedCostWinsForAnUnknownModelAndFailedOutcome() throws {
        let event = ProviderUsage(provider: .openRouter, model: "unknown/expensive", stage: .textProcessing,
                                  outcome: .failed, providerCostUSD: 0.0042)
        let cost = UsagePricing.cost(for: event)
        XCTAssertEqual(cost.kind, .providerReported)
        XCTAssertEqual(try XCTUnwrap(cost.usd), 0.0042)
        XCTAssertNil(cost.rateSnapshot)
    }

    func testReportedZeroIsKnownButMissingOpenRouterCostIsUnknown() {
        let reported = ProviderUsage(provider: .openRouter, model: "openai/gpt-4.1-mini", stage: .textProcessing, providerCostUSD: 0)
        XCTAssertEqual(UsagePricing.cost(for: reported).usd, 0)
        var missing = reported; missing.providerCostUSD = nil
        missing.inputTokens = 10; missing.outputTokens = 10
        XCTAssertEqual(UsagePricing.cost(for: missing).kind, .unavailable)
        XCTAssertNil(UsagePricing.cost(for: missing).usd)
    }

    func testLocalOperationsHaveZeroAPICostEvenOnCancellation() {
        let event = ProviderUsage(model: "whisper-small", stage: .transcription, outcome: .cancelled, audioSeconds: 10)
        XCTAssertEqual(UsagePricing.cost(for: event).kind, .local)
        XCTAssertEqual(UsagePricing.cost(for: event).usd, 0)
    }

    func testFailureAndCancellationNeverTurnIntoZeroOrDurationEstimate() {
        for outcome in [UsageOutcome.failed, .cancelled] {
            let event = ProviderUsage(provider: .groq, model: "whisper-large-v3-turbo", stage: .transcription,
                                      outcome: outcome, audioSeconds: 30)
            XCTAssertNil(UsagePricing.cost(for: event).usd)
            XCTAssertEqual(UsagePricing.cost(for: event).kind, .unavailable)
        }
    }

    func testGroqTranscriptionAccountsForMinimumTenSecondsPerAttempt() throws {
        let short = ProviderUsage(provider: .groq, model: "whisper-large-v3-turbo", stage: .transcription, attempt: 2, audioSeconds: 2)
        let long = ProviderUsage(provider: .groq, model: "whisper-large-v3-turbo", stage: .transcription, audioSeconds: 30)
        XCTAssertEqual(try XCTUnwrap(UsagePricing.cost(for: short).usd), 10 * 0.04 / 3600, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(UsagePricing.cost(for: long).usd), 30 * 0.04 / 3600, accuracy: 1e-10)
        XCTAssertEqual(UsagePricing.cost(for: short).rateSnapshot?.minimumAudioSeconds, 10)
    }

    func testOpenAIDurationModelIsDifferentFromTokenBasedTranscription() throws {
        let duration = ProviderUsage(provider: .openAI, model: "gpt-transcribe", stage: .transcription, audioSeconds: 60)
        XCTAssertEqual(try XCTUnwrap(UsagePricing.cost(for: duration).usd), 0.0045)
        var tokenModel = duration; tokenModel.model = "gpt-4o-mini-transcribe"
        XCTAssertNil(UsagePricing.cost(for: tokenModel).usd)
    }

    func testClaudeAddsCacheReadsInsteadOfSubtractingFromBaseInputTokens() throws {
        let event = ProviderUsage(provider: .anthropic, model: "claude-haiku-4-5-20251001", stage: .textProcessing,
                                  inputTokens: 100, outputTokens: 100, cachedInputTokens: 1_000)
        XCTAssertEqual(try XCTUnwrap(UsagePricing.cost(for: event).usd), 0.0007, accuracy: 1e-10)
    }

    func testGroqCachingAndReasoningAreNotDoubleCounted() throws {
        let event = ProviderUsage(provider: .groq, model: "openai/gpt-oss-120b", stage: .textProcessing,
                                  inputTokens: 1_000, outputTokens: 100, cachedInputTokens: 400, reasoningTokens: 50)
        XCTAssertEqual(try XCTUnwrap(UsagePricing.cost(for: event).usd), 0.00018, accuracy: 1e-10)
    }

    func testMissingOrInvalidCountsAndUnknownCacheWriteDurationAreUnavailable() {
        let base = ProviderUsage(provider: .openAI, model: "gpt-4.1-mini", stage: .textProcessing, inputTokens: 100, outputTokens: 100)
        var events: [ProviderUsage] = []
        var missing = base; missing.outputTokens = nil; events.append(missing)
        var negative = base; negative.inputTokens = -1; events.append(negative)
        var impossible = base; impossible.cachedInputTokens = 101; events.append(impossible)
        var cacheWrite = base; cacheWrite.cacheWriteTokens = 1; events.append(cacheWrite)
        var audio = base; audio.audioInputTokens = 1; events.append(audio)
        var reasoning = base; reasoning.reasoningTokens = 101; events.append(reasoning)
        for event in events {
            XCTAssertNil(UsagePricing.cost(for: event).usd)
            XCTAssertEqual(UsagePricing.cost(for: event).kind, .unavailable)
        }
    }

    func testExplicitZeroTokensCanBeEstimatedAsZero() {
        let event = ProviderUsage(provider: .openAI, model: "gpt-4.1-mini", stage: .textProcessing, inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(UsagePricing.cost(for: event).kind, .estimated)
        XCTAssertEqual(UsagePricing.cost(for: event).usd, 0)
        XCTAssertTrue(UsagePricing.cost(for: event).note?.contains("캐시 할인 내역이 없어") == true)
    }

    func testInvalidDurationAndReportedAmountsAreNotAcceptedAsKnownCosts() {
        for duration in [Double.nan, .infinity, -1, 0] {
            let event = ProviderUsage(provider: .groq, model: "whisper-large-v3-turbo", stage: .transcription, audioSeconds: duration)
            XCTAssertNil(UsagePricing.cost(for: event).usd)
        }
        for amount in [Double.nan, .infinity, -1] {
            let event = ProviderUsage(provider: .openRouter, model: "any", stage: .textProcessing, providerCostUSD: amount)
            XCTAssertNil(UsagePricing.cost(for: event).usd)
        }
    }

    func testUnknownReportedModelDoesNotBorrowRequestedModelsRate() {
        let event = ProviderUsage(provider: .openAI, model: "gpt-4.1-mini", reportedModel: "future-model",
                                  stage: .textProcessing, inputTokens: 100, outputTokens: 100)
        XCTAssertNil(UsagePricing.cost(for: event).usd)
    }

    func testUsageRoundTripKeepsRequestIdentityAndFrozenPrice() throws {
        let event = ProviderUsage(provider: .openAI, model: "gpt-transcribe", stage: .transcription, attempt: 2, audioSeconds: 10)
        let record = UsageRecord(jobID: UUID(), mode: .translation, isRecovery: true, event: event)
        let copy = try JSONDecoder().decode(UsageRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(copy, record)
        XCTAssertEqual(copy.id, event.id)
        XCTAssertEqual(copy.cost.rateSnapshot?.audioPerMinute, 0.0045)
    }
}
