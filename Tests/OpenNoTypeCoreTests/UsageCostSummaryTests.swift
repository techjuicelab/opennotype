import XCTest
@testable import OpenNoTypeCore

final class UsageCostSummaryTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func record(_ day: Int, hour: Int = 12, mode: InputMode = .dictation, stage: UsageStage = .textProcessing,
                        usd: Double?, job: UUID = UUID(), audio: Double? = nil) -> UsageRecord {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        let event = ProviderUsage(createdAt: date, provider: .groq, model: "m", stage: stage, audioSeconds: audio)
        let cost = usd.map { UsageCost(kind: .estimated, usd: $0) } ?? UsageCost(kind: .unavailable)
        return UsageRecord(jobID: job, mode: mode, event: event, cost: cost)
    }

    func testRolesFollowStageAndMode() {
        XCTAssertEqual(UsageCostSummary.role(of: record(1, stage: .transcription, usd: 0)), .transcription)
        XCTAssertEqual(UsageCostSummary.role(of: record(1, stage: .decisionReview, usd: 0)), .review)
        XCTAssertEqual(UsageCostSummary.role(of: record(1, mode: .dictation, usd: 0)), .cleanup)
        XCTAssertEqual(UsageCostSummary.role(of: record(1, mode: .translation, usd: 0)), .translation)
        XCTAssertEqual(UsageCostSummary.role(of: record(1, mode: .rewrite, usd: 0)), .rewrite)
        XCTAssertEqual(UsageCostSummary.role(of: record(1, mode: .prompt, usd: 0)), .prompt)
    }

    func testMonthToDateCountsUnknownCostsSeparatelyAndIgnoresLastMonth() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))!
        let job = UUID()
        let previous = UsageRecord(jobID: UUID(), mode: .dictation,
            event: ProviderUsage(createdAt: calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!, provider: .groq, model: "m", stage: .textProcessing),
            cost: UsageCost(kind: .estimated, usd: 9))
        let records = [
            record(2, stage: .transcription, usd: 0.01, job: job, audio: 30),
            record(2, usd: 0.02, job: job),
            record(3, mode: .translation, usd: nil),
            previous
        ]
        let summary = UsageCostSummary.monthToDate(records, now: now, calendar: calendar)
        XCTAssertEqual(summary.totalUSD, 0.03, accuracy: 1e-9)
        XCTAssertEqual(summary.unknownRequests, 1)
        XCTAssertEqual(summary.requests, 3)
        XCTAssertEqual(summary.jobs, 2)
        XCTAssertEqual(summary.byRole[.transcription]?.audioSeconds, 30)
        XCTAssertEqual(summary.byRole[.translation]?.knownUSD, 0)
        XCTAssertEqual(summary.byRole[.translation]?.unknownRequests, 1)
    }

    func testForecastNeedsEnoughRequestsAndAveragesOverCoveredDays() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))!
        XCTAssertNil(UsageCostSummary.recentForecast([record(19, usd: 0.1)], now: now, calendar: calendar))
        // Two days covered (19th and 20th), four jobs, $0.40 total.
        let records = (0..<4).map { index in record(index < 2 ? 19 : 20, hour: 9 + index, usd: 0.1) } + [record(20, hour: 14, usd: nil)]
        let forecast = UsageCostSummary.recentForecast(records, now: now, calendar: calendar)
        XCTAssertNotNil(forecast)
        XCTAssertEqual(forecast?.activeDays, 2)
        XCTAssertEqual(forecast?.monthlyUSD ?? 0, 0.4 / 2 * 30, accuracy: 1e-9)
        XCTAssertEqual(forecast?.perJobUSD ?? 0, 0.4 / 5, accuracy: 1e-9)
        XCTAssertEqual(forecast?.unknownRequests, 1)
        XCTAssertEqual(forecast?.monthlyUSD(jobsPerDay: 10) ?? 0, 0.08 * 10 * 30, accuracy: 1e-9)
    }
}
