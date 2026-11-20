import Foundation

/// The task a usage record paid for, as shown in AI model settings.
public enum CostRole: String, CaseIterable, Sendable {
    case transcription, cleanup, translation, rewrite, prompt, review

    public var title: String {
        switch self {
        case .transcription: L("음성 인식", "Speech recognition")
        case .cleanup: L("받아쓰기 정리", "Dictation cleanup")
        case .translation: L("번역", "Translation")
        case .rewrite: L("선택 문장 수정", "Edit selected text")
        case .prompt: L("프롬프트 만들기", "Prompt creation")
        case .review: L("문장 검토 (Jev)", "Text review (Jev)")
        }
    }
}

public struct RoleCost: Equatable, Sendable {
    public var requests = 0
    /// Sum of recorded amounts. Requests whose cost could not be verified are counted separately,
    /// never as zero.
    public var knownUSD: Double = 0
    public var unknownRequests = 0
    public var audioSeconds: Double = 0
    public init() {}
}

public struct CostSummary: Equatable, Sendable {
    public var byRole: [CostRole: RoleCost] = [:]
    public var totalUSD: Double = 0
    public var unknownRequests = 0
    public var requests = 0
    public var jobs = 0
    public init() {}
}

/// Recent usage projected to a month. Only verified amounts are projected.
public struct CostForecast: Equatable, Sendable {
    public var monthlyUSD: Double
    public var dailyJobs: Double
    public var perJobUSD: Double
    public var activeDays: Int
    public var sampleRequests: Int
    public var unknownRequests: Int

    /// The same per-job cost at another daily volume.
    public func monthlyUSD(jobsPerDay: Double) -> Double { perJobUSD * jobsPerDay * 30 }
}

/// Recent per-request averages for one task, so a projection can be priced at current rates.
public struct RoleUsageAverage: Equatable, Sendable {
    public var requestsPerDay: Double
    public var inputTokens: Double?
    public var outputTokens: Double?
    public var audioSeconds: Double?
    public var recordedUSD: Double?
}

public struct RecentUsage: Equatable, Sendable {
    public var activeDays: Int
    public var sampleRequests: Int
    public var jobsPerDay: Double
    public var byRole: [CostRole: RoleUsageAverage]
}

public enum UsageCostSummary {
    public static func role(of record: UsageRecord) -> CostRole {
        switch record.event.stage {
        case .transcription: return .transcription
        case .decisionReview: return .review
        case .textProcessing:
            switch record.mode {
            case .dictation: return .cleanup
            case .translation: return .translation
            case .rewrite: return .rewrite
            case .prompt: return .prompt
            }
        }
    }

    public static func summarize(_ records: [UsageRecord], from start: Date, to end: Date) -> CostSummary {
        var summary = CostSummary()
        var jobs = Set<UUID>()
        for record in records where record.event.createdAt >= start && record.event.createdAt < end {
            var role = summary.byRole[self.role(of: record)] ?? RoleCost()
            role.requests += 1
            if let usd = record.cost.usd, usd.isFinite, usd >= 0 {
                role.knownUSD += usd
                summary.totalUSD += usd
            } else {
                role.unknownRequests += 1
                summary.unknownRequests += 1
            }
            if let seconds = record.event.audioSeconds, seconds.isFinite, seconds > 0 { role.audioSeconds += seconds }
            summary.byRole[self.role(of: record)] = role
            summary.requests += 1
            jobs.insert(record.jobID)
        }
        summary.jobs = jobs.count
        return summary
    }

    public static func monthToDate(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current) -> CostSummary {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return summarize(records, from: start, to: now.addingTimeInterval(1))
    }

    /// Projects the last 30 days to a month once there are enough requests to be meaningful.
    /// Fewer days of history are averaged over the days actually covered.
    public static func recentForecast(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current,
                                      minimumRequests: Int = 5) -> CostForecast? {
        let windowStart = now.addingTimeInterval(-30 * 86_400)
        let summary = summarize(records, from: windowStart, to: now.addingTimeInterval(1))
        guard summary.requests >= minimumRequests, summary.jobs > 0 else { return nil }
        let earliest = records.map(\.event.createdAt).filter { $0 >= windowStart && $0 <= now }.min() ?? now
        let startDay = calendar.startOfDay(for: earliest), today = calendar.startOfDay(for: now)
        let days = (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
        let activeDays = min(30, max(1, days))
        let perJob = summary.totalUSD / Double(summary.jobs)
        let dailyJobs = Double(summary.jobs) / Double(activeDays)
        return CostForecast(monthlyUSD: summary.totalUSD / Double(activeDays) * 30, dailyJobs: dailyJobs,
                            perJobUSD: perJob, activeDays: activeDays, sampleRequests: summary.requests,
                            unknownRequests: summary.unknownRequests)
    }

    /// Averages of the last 30 days by task: how often it runs and how large a request is.
    /// Prices are applied by the caller, so changing a model changes the projection.
    public static func recentUsage(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current,
                                   minimumRequests: Int = 5) -> RecentUsage? {
        let windowStart = now.addingTimeInterval(-30 * 86_400)
        let window = records.filter { $0.event.createdAt >= windowStart && $0.event.createdAt <= now }
        guard window.count >= minimumRequests, let earliest = window.map(\.event.createdAt).min() else { return nil }
        let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: now)).day ?? 0) + 1
        let activeDays = min(30, max(1, days))
        var byRole: [CostRole: RoleUsageAverage] = [:]
        for role in CostRole.allCases {
            let items = window.filter { self.role(of: $0) == role }
            guard !items.isEmpty else { continue }
            func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            byRole[role] = RoleUsageAverage(
                requestsPerDay: Double(items.count) / Double(activeDays),
                inputTokens: mean(items.compactMap { $0.event.inputTokens.map(Double.init) }),
                outputTokens: mean(items.compactMap { $0.event.outputTokens.map(Double.init) }),
                audioSeconds: mean(items.compactMap { $0.event.audioSeconds }.filter { $0.isFinite && $0 > 0 }),
                recordedUSD: mean(items.compactMap { $0.cost.usd }.filter { $0.isFinite && $0 >= 0 }))
        }
        return RecentUsage(activeDays: activeDays, sampleRequests: window.count,
                           jobsPerDay: Double(Set(window.map(\.jobID)).count) / Double(activeDays), byRole: byRole)
    }
}
