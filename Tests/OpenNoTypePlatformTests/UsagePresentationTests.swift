import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class UsagePresentationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func record(at createdAt: Date, provider: AIProvider? = .openAI, model: String = "requested-model",
                        reportedModel: String? = nil, stage: UsageStage = .textProcessing,
                        jobID: UUID = UUID(), attempt: Int = 1, outcome: UsageOutcome = .responseReceived,
                        isRecovery: Bool = false, input: Int? = nil, output: Int? = nil,
                        cached: Int? = nil, written: Int? = nil, audioTokens: Int? = nil,
                        reasoning: Int? = nil, seconds: Double? = nil,
                        cost: UsageCost = .init(kind: .unavailable)) -> UsageRecord {
        let event = ProviderUsage(createdAt: createdAt, provider: provider, model: model,
                                  reportedModel: reportedModel, stage: stage, outcome: outcome, attempt: attempt,
                                  inputTokens: input, outputTokens: output, cachedInputTokens: cached,
                                  cacheWriteTokens: written, audioInputTokens: audioTokens,
                                  reasoningTokens: reasoning, audioSeconds: seconds)
        return UsageRecord(jobID: jobID, mode: .dictation, isRecovery: isRecovery, event: event, cost: cost)
    }

    func testThisMonthUsesLocalCalendarBoundaryAcrossTheNewYear() {
        let now = date(2026, 1, 1, 14)
        let before = record(at: date(2025, 12, 31, 23, 59, 59))
        let midnight = record(at: date(2026, 1, 1))
        let current = record(at: now)
        let future = record(at: now.addingTimeInterval(1))
        let report = UsageAnalytics(records: [before, midnight, future, current], period: .month, now: now, calendar: calendar)
        XCTAssertEqual(report.records.map(\.id), [current.id, midnight.id])
        XCTAssertEqual(UsagePeriod.month.start(now: now, calendar: calendar), date(2026, 1, 1))
    }

    func testThisMonthIncludesLeapDayButNotThePreviousMonth() {
        let now = date(2024, 2, 29, 23, 59, 59)
        let first = record(at: date(2024, 2, 1))
        let leapDay = record(at: date(2024, 2, 29, 12))
        let january = record(at: date(2024, 1, 31, 23, 59, 59))
        let march = record(at: date(2024, 3, 1))
        let report = UsageAnalytics(records: [first, leapDay, january, march], period: .month, now: now, calendar: calendar)
        XCTAssertEqual(Set(report.records.map(\.id)), Set([first.id, leapDay.id]))
    }

    func testRecentSevenDaysIncludesWholeFirstLocalDayAcrossTheNewYear() {
        let now = date(2026, 1, 3, 8)
        let start = date(2025, 12, 28)
        let included = record(at: start)
        let justBefore = record(at: start.addingTimeInterval(-1))
        let report = UsageAnalytics(records: [included, justBefore], period: .week, now: now, calendar: calendar)
        XCTAssertEqual(report.records.map(\.id), [included.id])
        XCTAssertEqual(UsagePeriod.week.start(now: now, calendar: calendar), start)
    }

    func testAllTimeIncludesOldRecordsAndExcludesFutureClockValues() {
        let now = date(2026, 9, 10, 12)
        let old = record(at: date(1999, 1, 1))
        let recent = record(at: date(2026, 9, 1))
        let future = record(at: now.addingTimeInterval(60))
        let report = UsageAnalytics(records: [future, old, recent], period: .all, now: now, calendar: calendar)
        XCTAssertEqual(report.records.map(\.id), [recent.id, old.id])
        XCTAssertNil(UsagePeriod.all.start(now: now, calendar: calendar))
    }

    func testProviderFilterKeepsLocalUsageSeparateFromCloudRequests() {
        let now = date(2026, 9, 10)
        let local = record(at: now, provider: nil, stage: .transcription,
                           cost: .init(kind: .local, usd: 0))
        let openAI = record(at: now, provider: .openAI)
        let groq = record(at: now, provider: .groq)
        let records = [local, openAI, groq]
        let all = UsageAnalytics(records: records, period: .all, now: now, calendar: calendar)
        let onDevice = UsageAnalytics(records: records, period: .all, provider: "local", now: now, calendar: calendar)
        let cloud = UsageAnalytics(records: records, period: .all, provider: AIProvider.groq.rawValue, now: now, calendar: calendar)
        XCTAssertEqual(all.records.count, 3)
        XCTAssertEqual(all.totals.apiRequests, 2)
        XCTAssertEqual(onDevice.records.map(\.id), [local.id])
        XCTAssertEqual(onDevice.totals.apiRequests, 0)
        XCTAssertEqual(cloud.records.map(\.id), [groq.id])
        XCTAssertTrue(UsageAnalytics(records: records, period: .all, provider: "unknown-provider", now: now, calendar: calendar).records.isEmpty)
    }

    func testAutomaticRetryAndManualRecoveryDoNotInflateTheNumberOfJobs() {
        let now = date(2026, 9, 10)
        let initial = UUID(), recovery = UUID()
        let records = [
            record(at: now, stage: .transcription, jobID: initial, outcome: .failed, seconds: 10),
            record(at: now, stage: .transcription, jobID: initial, attempt: 2, seconds: 10),
            record(at: now, jobID: initial),
            record(at: now, provider: nil, stage: .transcription, jobID: recovery, isRecovery: true, seconds: 20,
                   cost: .init(kind: .local, usd: 0)),
            record(at: now, jobID: recovery, isRecovery: true)
        ]
        let totals = UsageTotals(records: records)
        XCTAssertEqual(totals.jobs, 2)
        XCTAssertEqual(totals.apiRequests, 4)
        XCTAssertEqual(totals.retries, 1)
        XCTAssertEqual(totals.recoveries, 1)
        XCTAssertEqual(totals.failedRequests, 1)
        XCTAssertEqual(totals.audioSeconds, 40)
    }

    func testGroupingUsesReportedModelAndKeepsProviderAndStageDistinct() throws {
        let now = date(2026, 9, 10)
        let records = [
            record(at: now, model: "alias-a", reportedModel: " actual-model "),
            record(at: now, model: "alias-b", reportedModel: "actual-model"),
            record(at: now, model: "alias-a", reportedModel: "actual-model", stage: .transcription),
            record(at: now, provider: .groq, model: "alias-a", reportedModel: "actual-model"),
            record(at: now, model: "fallback-model", reportedModel: "  ")
        ]
        let report = UsageAnalytics(records: records, period: .all, now: now, calendar: calendar)
        XCTAssertEqual(report.models.count, 4)
        let matching = try XCTUnwrap(report.models.first {
            $0.id.provider == AIProvider.openAI.rawValue && $0.id.model == "actual-model" && $0.id.stage == .textProcessing
        })
        XCTAssertEqual(matching.totals.records.count, 2)
        XCTAssertTrue(report.models.contains { $0.id.model == "fallback-model" })
    }

    func testKnownZeroAndUnavailableAmountsRemainDifferent() {
        let now = date(2026, 9, 10)
        let unknown = record(at: now)
        let zero = record(at: now, cost: .init(kind: .providerReported, usd: 0))
        let local = record(at: now, provider: nil, cost: .init(kind: .local, usd: 0))
        XCTAssertFalse(UsageTotals(records: [unknown]).hasKnownCost)
        XCTAssertFalse(UsageTotals(records: [unknown]).hasReportedCost)
        XCTAssertFalse(UsageTotals(records: [unknown]).hasEstimatedCost)
        XCTAssertTrue(UsageTotals(records: [zero]).hasReportedCost)
        XCTAssertFalse(UsageTotals(records: [zero]).hasEstimatedCost)
        XCTAssertTrue(UsageTotals(records: [zero]).hasKnownCost)
        XCTAssertTrue(UsageTotals(records: [local]).hasKnownCost)
        XCTAssertEqual(UsageTotals(records: [unknown, zero, local]).unknownCosts, 1)
        XCTAssertEqual(UsageTotals(records: [unknown, zero, local]).knownUSD, 0)
        XCTAssertEqual(UsageFormat.usd(nil), "미확인")
        XCTAssertNotEqual(UsageFormat.usd(0), UsageFormat.usd(nil))
        XCTAssertEqual(UsageFormat.usd(0.000001), "< US$0.0001")
    }

    func testReportedAndEstimatedAmountsAreAddedWithoutInventingUnknownAmounts() {
        let now = date(2026, 9, 10)
        let totals = UsageTotals(records: [
            record(at: now, cost: .init(kind: .providerReported, usd: 0.001)),
            record(at: now, cost: .init(kind: .estimated, usd: 0.002)),
            record(at: now),
            record(at: now, provider: nil, cost: .init(kind: .local, usd: 0))
        ])
        XCTAssertEqual(totals.reportedUSD, 0.001, accuracy: 0.00000001)
        XCTAssertEqual(totals.estimatedUSD, 0.002, accuracy: 0.00000001)
        XCTAssertEqual(totals.knownUSD, 0.003, accuracy: 0.00000001)
        XCTAssertEqual(totals.unknownCosts, 1)
    }

    func testTokenTotalsCountAnthropicCacheSeparatelyButDoNotDoubleCountOpenAISubsets() {
        let now = date(2026, 9, 10)
        let anthropic = record(at: now, provider: .anthropic, input: 100, output: 20, cached: 40, written: 30)
        let openAI = record(at: now, provider: .openAI, input: 100, output: 20, cached: 40, audioTokens: 50, reasoning: 10)
        let unknown = record(at: now)
        let totals = UsageTotals(records: [anthropic, openAI, unknown])
        XCTAssertEqual(totals.inputTokens, 270, "Anthropic input excludes cache; OpenAI cached/audio tokens are subsets of input.")
        XCTAssertEqual(totals.outputTokens, 40, "Reasoning tokens are already included in output.")
        XCTAssertEqual(totals.tokens, 310)
    }

    func testMissingTokenUsageIsNotDisplayedAsZeroAndExplicitZeroIsPreserved() {
        let now = date(2026, 9, 10)
        let missing = UsageTotals(records: [record(at: now)])
        XCTAssertNil(missing.inputTokens)
        XCTAssertNil(missing.outputTokens)
        XCTAssertNil(missing.tokens)
        XCTAssertEqual(UsageFormat.tokens(nil), "미제공")
        let zero = UsageTotals(records: [record(at: now, input: 0, output: 0)])
        XCTAssertEqual(zero.inputTokens, 0)
        XCTAssertEqual(zero.outputTokens, 0)
        XCTAssertEqual(zero.tokens, 0)
        XCTAssertEqual(UsageFormat.tokens(0), "0")
    }

    func testChartShowsSevenDaysOrElapsedMonthWithoutZerosOutsideTheSelection() {
        let now = date(2026, 9, 10, 12)
        let records = [record(at: now)]
        let week = UsageAnalytics(records: records, period: .week, now: now, calendar: calendar)
        let month = UsageAnalytics(records: records, period: .month, now: now, calendar: calendar)
        XCTAssertEqual(week.recentDays.count, 7)
        XCTAssertEqual(week.recentDays.first?.date, date(2026, 9, 4))
        XCTAssertEqual(month.recentDays.count, 10)
        XCTAssertEqual(month.recentDays.first?.date, date(2026, 9, 1))
        let firstDay = UsageAnalytics(records: [], period: .month, now: date(2026, 1, 1, 12), calendar: calendar)
        XCTAssertEqual(firstDay.recentDays.count, 1)
    }

    func testAllTimeChartIsBoundedWhileLifetimeTotalsKeepOlderUsage() {
        let now = date(2026, 9, 10, 12)
        let old = record(at: date(2025, 1, 1))
        let today = record(at: date(2026, 9, 10, 9))
        let local = record(at: date(2026, 9, 10, 10), provider: nil, stage: .transcription)
        let report = UsageAnalytics(records: [old, today, local], period: .all, now: now, calendar: calendar)
        XCTAssertEqual(report.totals.apiRequests, 2)
        XCTAssertEqual(report.recentDays.count, 30)
        XCTAssertEqual(report.recentDays.reduce(0) { $0 + $1.requests }, 1)
        XCTAssertEqual(report.recentDays.reduce(0) { $0 + $1.localOperations }, 1)
        XCTAssertEqual(report.recentDays.last?.date, calendar.startOfDay(for: now))
    }
}
