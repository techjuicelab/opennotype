import Foundation
import OpenNoTypeCore

enum UsagePeriod: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }
    var title: String {
        switch self { case .week: "최근 7일"; case .month: "이번 달"; case .all: "전체 기록" }
    }
    func start(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .week: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .month: calendar.dateInterval(of: .month, for: now)?.start
        case .all: nil
        }
    }
}

struct UsageTotals {
    let records: [UsageRecord]
    var apiRequests: Int { records.filter { $0.event.provider != nil }.count }
    var jobs: Int { Set(records.map(\.jobID)).count }
    var retries: Int { records.filter { $0.event.attempt > 1 }.count }
    var recoveries: Int { Set(records.filter(\.isRecovery).map(\.jobID)).count }
    var failedRequests: Int { records.filter { $0.event.outcome != .responseReceived }.count }
    var reportedUSD: Double { amount(kind: .providerReported) }
    var estimatedUSD: Double { amount(kind: .estimated) }
    var knownUSD: Double { reportedUSD + estimatedUSD }
    var unknownCosts: Int { records.filter { $0.event.provider != nil && $0.cost.usd == nil }.count }
    var hasKnownCost: Bool { records.contains { $0.cost.usd != nil } }
    var hasReportedCost: Bool { records.contains { $0.cost.kind == .providerReported && $0.cost.usd != nil } }
    var hasEstimatedCost: Bool { records.contains { $0.cost.kind == .estimated && $0.cost.usd != nil } }
    var inputTokens: Int? {
        let values = records.compactMap { record -> Int? in
            guard let input = record.event.inputTokens, input >= 0 else { return nil }
            // Claude reports non-cache input separately; other providers include cache reads.
            if record.event.provider == .anthropic {
                return Self.safeSum([input, max(0, record.event.cachedInputTokens ?? 0), max(0, record.event.cacheWriteTokens ?? 0)])
            }
            return input
        }
        return values.isEmpty ? nil : Self.safeSum(values)
    }
    var outputTokens: Int? { tokenSum(\.outputTokens) }
    var tokens: Int? {
        guard inputTokens != nil || outputTokens != nil else { return nil }
        return Self.safeSum([inputTokens ?? 0, outputTokens ?? 0])
    }
    var audioSeconds: Double {
        records.filter { $0.event.stage == .transcription }.compactMap { $0.event.audioSeconds }
            .filter { $0.isFinite && $0 >= 0 }.reduce(0, +)
    }
    var audioCount: Int { records.filter { $0.event.stage == .transcription && $0.event.audioSeconds != nil }.count }
    private func amount(kind: UsageCost.Kind) -> Double {
        records.filter { $0.cost.kind == kind }.compactMap { $0.cost.usd }
            .filter { $0.isFinite && $0 >= 0 }.reduce(0, +)
    }
    private func tokenSum(_ field: KeyPath<ProviderUsage, Int?>) -> Int? {
        let values = records.compactMap { $0.event[keyPath: field] }.filter { $0 >= 0 }
        return values.isEmpty ? nil : Self.safeSum(values)
    }
    private static func safeSum(_ values: [Int]) -> Int {
        values.reduce(0) { sum, value in
            let (next, overflow) = sum.addingReportingOverflow(value)
            return overflow ? Int.max : next
        }
    }
}

struct UsageModelGroup: Identifiable {
    struct ID: Hashable { let provider: String; let model: String; let stage: UsageStage }
    let id: ID
    let providerName: String
    let totals: UsageTotals
}

struct UsageDay: Identifiable {
    var id: Date { date }
    let date: Date
    let requests: Int
    let localOperations: Int
}

struct UsageAnalytics {
    let records: [UsageRecord]
    let now: Date
    let calendar: Calendar
    let period: UsagePeriod
    init(records: [UsageRecord], period: UsagePeriod, provider: String = "all", now: Date = Date(), calendar: Calendar = .current) {
        self.now = now; self.calendar = calendar; self.period = period
        let start = period.start(now: now, calendar: calendar)
        self.records = records.filter { record in
            record.event.createdAt <= now && (start == nil || record.event.createdAt >= start!)
                && (provider == "all" || (record.event.provider?.rawValue ?? "local") == provider)
        }.sorted { $0.event.createdAt > $1.event.createdAt }
    }
    var totals: UsageTotals { .init(records: records) }
    var models: [UsageModelGroup] {
        let groups = Dictionary(grouping: records) { record in
            UsageModelGroup.ID(provider: record.event.provider?.rawValue ?? "local",
                model: record.event.effectiveModel, stage: record.event.stage)
        }
        return groups.map { key, values in
            UsageModelGroup(id: key, providerName: values.first?.event.provider?.displayName ?? "이 Mac", totals: .init(records: values))
        }.sorted {
            if $0.totals.knownUSD != $1.totals.knownUSD { return $0.totals.knownUSD > $1.totals.knownUSD }
            if $0.totals.records.count != $1.totals.records.count { return $0.totals.records.count > $1.totals.records.count }
            return ($0.id.provider + $0.id.model + $0.id.stage.rawValue) < ($1.id.provider + $1.id.model + $1.id.stage.rawValue)
        }
    }
    /// The all-time view still limits the chart to 30 days; its totals and model groups remain all-time.
    var recentDays: [UsageDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day),
                  period.start(now: now, calendar: calendar).map({ day >= $0 }) ?? true else { return nil }
            let values = records.filter { $0.event.createdAt >= day && $0.event.createdAt < end }
            return .init(date: day, requests: values.filter { $0.event.provider != nil }.count,
                         localOperations: values.filter { $0.event.provider == nil }.count)
        }
    }
}

enum UsageFormat {
    static func usd(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "미확인" }
        if value > 0 && value < 0.0001 { return "< US$0.0001" }
        return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(value < 1 ? 4 : 2)))
    }
    static func tokens(_ count: Int?) -> String { count.map { $0.formatted() } ?? "미제공" }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "미확인" }
        let whole = Int(seconds.rounded())
        if whole >= 3600 { return "\(whole / 3600)시간 \((whole % 3600) / 60)분" }
        if whole >= 60 { return "\(whole / 60)분 \(whole % 60)초" }
        return "\(whole)초"
    }
}
