import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class JevQualityMetricsTests: KoreanPresentationTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGenerationTimingIsAttributedSeparatelyFromReviewAndImprovementEvents() throws {
        var metrics = JevQualityMetrics()
        metrics.recordGeneration(provider: .openRouter, model: " model-a ", duration: 1.2)
        metrics.recordGeneration(provider: .openRouter, model: "model-a", duration: 0.8)
        metrics.recordGeneration(provider: .groq, model: "model-a", duration: 0.25)
        metrics.recordGeneration(provider: .openRouter, model: "model-b", duration: 0.5)
        metrics.recordReview(provider: .openRouter, model: "model-a", warning: true, duration: 0.1)
        metrics.recordImprovementOffered(provider: .openRouter, model: "model-a")
        metrics.recordImprovementAdopted(provider: .openRouter, model: "model-a")
        XCTAssertEqual(metrics.rows.count, 3)
        let row = try XCTUnwrap(metrics.rows.first { $0.provider == .openRouter && $0.id.model == "model-a" })
        XCTAssertEqual(row.generationCount, 2)
        XCTAssertEqual(row.generationLatencyCount, 2)
        XCTAssertEqual(row.generationLatencyTotal, 2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(row.meanGenerationDuration), 1, accuracy: 0.000_001)
        XCTAssertEqual(row.reviewCount, 1)
        XCTAssertEqual(row.meanReviewDuration, 0.1)
        XCTAssertEqual(row.improvementOfferedCount, 1)
        XCTAssertEqual(row.improvementAdoptedCount, 1)
        XCTAssertEqual(metrics.rows.first { $0.provider == .groq }?.meanGenerationDuration, 0.25)
    }

    func testInvalidAndOverflowingGenerationDurationsNeverBecomeZeroLatency() throws {
        var metrics = JevQualityMetrics()
        for duration in [-1.0, Double.nan, Double.infinity] {
            metrics.recordGeneration(provider: .openRouter, model: "model", duration: duration)
        }
        let row = try XCTUnwrap(metrics.rows.first)
        XCTAssertEqual(row.generationCount, 3)
        XCTAssertEqual(row.generationLatencyCount, 0)
        XCTAssertEqual(row.generationLatencyTotal, 0)
        XCTAssertNil(row.meanGenerationDuration)
        XCTAssertEqual(UsageFormat.reviewLatency(row.meanGenerationDuration), "미확인")
        metrics.recordGeneration(provider: .openRouter, model: "model", duration: 0)
        XCTAssertEqual(metrics.rows.first?.generationCount, 4)
        XCTAssertEqual(metrics.rows.first?.meanGenerationDuration, 0)
        metrics.recordGeneration(provider: .groq, model: "overflow", duration: Double.greatestFiniteMagnitude)
        metrics.recordGeneration(provider: .groq, model: "overflow", duration: Double.greatestFiniteMagnitude)
        let overflow = try XCTUnwrap(metrics.rows.first { $0.provider == .groq })
        XCTAssertEqual(overflow.generationCount, 2)
        XCTAssertEqual(overflow.generationLatencyCount, 1)
        XCTAssertEqual(overflow.meanGenerationDuration, Double.greatestFiniteMagnitude)
        XCTAssertEqual(overflow.reviewCount, 0)
    }

    func testReviewsStayAttributedToTheirProviderAndRequestedModel() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: " model-a ", warning: true, duration: 0.2)
        metrics.recordReview(provider: .openRouter, model: "model-a", warning: false, duration: 0.4)
        metrics.recordReview(provider: .groq, model: "model-a", warning: false, duration: 0.8)
        metrics.recordReview(provider: .openRouter, model: "model-b", warning: false, duration: 0.1)
        XCTAssertEqual(metrics.rows.count, 3)
        let row = try XCTUnwrap(metrics.rows.first { $0.provider == .openRouter && $0.id.model == "model-a" })
        XCTAssertEqual(row.reviewCount, 2)
        XCTAssertEqual(row.warningCount, 1)
        XCTAssertEqual(row.reviewLatencyCount, 2)
        XCTAssertEqual(try XCTUnwrap(row.meanReviewDuration), 0.3, accuracy: 0.000_001)
        XCTAssertEqual(metrics.rows.first { $0.provider == .groq }?.reviewCount, 1)
    }

    func testUnavailableOrInvalidTimingNeverBecomesZeroLatency() throws {
        var metrics = JevQualityMetrics()
        for duration in [-1.0, Double.nan, Double.infinity] {
            metrics.recordReview(provider: .openRouter, model: "model", warning: false, duration: duration)
        }
        let row = try XCTUnwrap(metrics.rows.first)
        XCTAssertEqual(row.reviewCount, 3)
        XCTAssertEqual(row.reviewLatencyCount, 0)
        XCTAssertEqual(row.reviewLatencyTotal, 0)
        XCTAssertNil(row.meanReviewDuration)
        XCTAssertEqual(UsageFormat.reviewLatency(row.meanReviewDuration), "미확인")
        metrics.recordReview(provider: .openRouter, model: "model", warning: true, duration: 0.25)
        XCTAssertEqual(metrics.rows.first?.reviewCount, 4)
        XCTAssertEqual(metrics.rows.first?.meanReviewDuration, 0.25)
        XCTAssertEqual(UsageFormat.reviewLatency(metrics.rows.first?.meanReviewDuration), "0.25초")
    }

    func testUnknownModelDoesNotCreateAnAttribution() {
        var metrics = JevQualityMetrics()
        metrics.recordGeneration(provider: .openRouter, model: " \n", duration: 1)
        metrics.recordReview(provider: .openRouter, model: " \n", warning: true, duration: 1)
        metrics.recordImprovementOffered(provider: .groq, model: "")
        metrics.recordImprovementAdopted(provider: .groq, model: " ")
        XCTAssertTrue(metrics.isEmpty)
    }

    func testImprovementEventsDoNotInventAdditionalReviewsOrWarnings() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: "model", warning: true, duration: 0.2)
        metrics.recordImprovementOffered(provider: .openRouter, model: "model")
        metrics.recordImprovementOffered(provider: .openRouter, model: "model")
        metrics.recordImprovementAdopted(provider: .openRouter, model: "model")
        let row = try XCTUnwrap(metrics.rows.first)
        XCTAssertEqual(row.reviewCount, 1)
        XCTAssertEqual(row.warningCount, 1)
        XCTAssertEqual(row.improvementOfferedCount, 2)
        XCTAssertEqual(row.improvementAdoptedCount, 1)
        XCTAssertEqual(row.reviewLatencyCount, 1)
    }

    func testClearAndNewInstanceBothStartEmpty() {
        var metrics = JevQualityMetrics()
        metrics.recordGeneration(provider: .openRouter, model: "model", duration: 1.2)
        metrics.recordReview(provider: .openRouter, model: "model", warning: true, duration: 0.2)
        metrics.recordImprovementOffered(provider: .openRouter, model: "model")
        metrics.recordImprovementAdopted(provider: .openRouter, model: "model")
        metrics.clear()
        XCTAssertTrue(metrics.isEmpty)
        XCTAssertTrue(metrics.rows.isEmpty)
        metrics.recordReview(provider: .groq, model: "new-model", warning: false, duration: 0.5)
        XCTAssertEqual(metrics.rows.first?.reviewCount, 1)
        XCTAssertEqual(metrics.rows.first?.generationCount, 0)
        XCTAssertNil(metrics.rows.first?.meanGenerationDuration)
        XCTAssertEqual(metrics.rows.first?.warningCount, 0)
        XCTAssertEqual(metrics.rows.first?.improvementAdoptedCount, 0)
        XCTAssertTrue(JevQualityMetrics().isEmpty)
    }

    func testCostAttributionUsesRequestedModelAndOnlyTextProcessing() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: "chosen-model", warning: false, duration: 0.25)
        let records = [
            record(model: "chosen-model", reportedModel: "actual-alias", cost: .init(kind: .providerReported, usd: 0.1)),
            record(model: "chosen-model", cost: .init(kind: .estimated, usd: 0.2)),
            record(model: "chosen-model", stage: .decisionReview, cost: .init(kind: .providerReported, usd: 0.3)),
            record(model: "chosen-model", stage: .transcription, cost: .init(kind: .providerReported, usd: 0.4)),
            record(provider: .groq, model: "chosen-model", cost: .init(kind: .providerReported, usd: 0.5)),
            record(model: "other-model", reportedModel: "chosen-model", cost: .init(kind: .providerReported, usd: 0.6))
        ]
        let row = try XCTUnwrap(UsageAnalytics(records: records, period: .all, now: now).qualityModels(metrics).first)
        XCTAssertEqual(row.textProcessingCosts.records.count, 2)
        XCTAssertEqual(row.textProcessingCosts.knownUSD, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(row.metric.reviewCount, 1, "Costs cover all matching text requests; they are not per-review charges")
    }

    func testPeriodChangesCostsButNotCurrentSessionCounters() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: "model", warning: true, duration: 0.25)
        let records = [
            record(at: now.addingTimeInterval(-90 * 86_400), model: "model", cost: .init(kind: .providerReported, usd: 1)),
            record(model: "model", cost: .init(kind: .providerReported, usd: 2)),
            record(at: now.addingTimeInterval(86_400), model: "model", cost: .init(kind: .providerReported, usd: 4))
        ]
        let all = try XCTUnwrap(UsageAnalytics(records: records, period: .all, now: now).qualityModels(metrics).first)
        let week = try XCTUnwrap(UsageAnalytics(records: records, period: .week, now: now).qualityModels(metrics).first)
        XCTAssertEqual(all.textProcessingCosts.knownUSD, 3)
        XCTAssertEqual(week.textProcessingCosts.knownUSD, 2)
        XCTAssertEqual(all.metric.reviewCount, week.metric.reviewCount)
        XCTAssertEqual(all.metric.warningCount, week.metric.warningCount)
    }

    func testProviderFilterDoesNotHideMetricsWhenUsageCostsAreMissing() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: "model", warning: false, duration: 0.1)
        metrics.recordReview(provider: .groq, model: "model", warning: true, duration: 0.2)
        let rows = UsageAnalytics(records: [], period: .week, provider: AIProvider.groq.rawValue, now: now).qualityModels(metrics)
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.metric.provider, .groq)
        XCTAssertFalse(row.textProcessingCosts.hasKnownCost)
        XCTAssertTrue(UsageAnalytics(records: [], period: .all, provider: "typesafe", now: now).qualityModels(metrics).isEmpty)
    }

    func testUnknownCostAndExplicitZeroRemainDistinctInComparison() throws {
        var metrics = JevQualityMetrics()
        metrics.recordReview(provider: .openRouter, model: "free-reported", warning: false, duration: 0)
        metrics.recordReview(provider: .openRouter, model: "unknown", warning: false, duration: 0)
        let rows = UsageAnalytics(records: [
            record(model: "free-reported", cost: .init(kind: .providerReported, usd: 0)),
            record(model: "unknown", cost: .init(kind: .unavailable))
        ], period: .all, now: now).qualityModels(metrics)
        let zero = try XCTUnwrap(rows.first { $0.id.model == "free-reported" })
        let unknown = try XCTUnwrap(rows.first { $0.id.model == "unknown" })
        XCTAssertTrue(zero.textProcessingCosts.hasKnownCost)
        XCTAssertEqual(zero.textProcessingCosts.knownUSD, 0)
        XCTAssertFalse(unknown.textProcessingCosts.hasKnownCost)
        XCTAssertEqual(unknown.textProcessingCosts.unknownCosts, 1)
    }

    private func record(at date: Date? = nil, provider: AIProvider = .openRouter, model: String,
                        reportedModel: String? = nil, stage: UsageStage = .textProcessing,
                        cost: UsageCost) -> UsageRecord {
        let event = ProviderUsage(createdAt: date ?? now, provider: provider, model: model,
                                  reportedModel: reportedModel, stage: stage)
        return UsageRecord(jobID: UUID(), mode: .dictation, isRecovery: false, event: event, cost: cost)
    }
}
