import Foundation
import OpenNoTypeCore

/// Aggregate counters for this app session. Deliberately not Codable and never contains user text.
struct JevQualityMetrics: Sendable {
    private var entries: [JevQualityMetric.ID: JevQualityMetric] = [:]

    var rows: [JevQualityMetric] {
        entries.values.sorted {
            if $0.id.providerID != $1.id.providerID { return $0.id.providerID < $1.id.providerID }
            return $0.id.model < $1.id.model
        }
    }
    var isEmpty: Bool { entries.isEmpty }

    /// One completed text-processing call, independently of whether Jev reviews its result.
    mutating func recordGeneration(provider: AIProvider, model: String, duration: TimeInterval, outcome: JevMetricOutcome = .completed) {
        update(provider: provider, model: model) { entry in
            entry.generationAttemptCount += 1
            if outcome == .completed { entry.generationCount += 1 }
            if outcome == .failed { entry.generationFailureCount += 1 }
            if outcome == .cancelled { entry.generationCancellationCount += 1 }
            if duration.isFinite, duration >= 0, (entry.generationLatencyTotal + duration).isFinite {
                entry.generationLatencyTotal += duration
                entry.generationLatencyCount += 1
                entry.generationDurations.append(duration)
                if entry.generationDurations.count > 256 { entry.generationDurations.removeFirst() }
            }
        }
    }

    /// Attribute a completed review to the model that produced the text, not the Jev reviewer.
    mutating func recordReview(provider: AIProvider, model: String, warning: Bool, duration: TimeInterval, outcome: JevMetricOutcome = .completed) {
        update(provider: provider, model: model) { entry in
            entry.reviewAttemptCount += 1
            if outcome == .completed { entry.reviewCount += 1 }
            if outcome == .failed { entry.reviewFailureCount += 1 }
            if outcome == .cancelled { entry.reviewCancellationCount += 1 }
            if outcome == .completed && warning { entry.warningCount += 1 }
            if duration.isFinite, duration >= 0, (entry.reviewLatencyTotal + duration).isFinite {
                entry.reviewLatencyTotal += duration
                entry.reviewLatencyCount += 1
                entry.reviewDurations.append(duration)
                if entry.reviewDurations.count > 256 { entry.reviewDurations.removeFirst() }
            }
        }
    }

    /// Recording-stop to terminal pipeline state, including retry, held, failed and cancelled jobs.
    mutating func recordPipeline(provider: AIProvider, model: String, duration: TimeInterval, outcome: JevMetricOutcome) {
        update(provider: provider, model: model) { entry in
            entry.pipelineAttemptCount += 1
            switch outcome {
            case .completed: entry.pipelineCompletedCount += 1
            case .held: entry.pipelineHeldCount += 1
            case .failed: entry.pipelineFailureCount += 1
            case .cancelled: entry.pipelineCancellationCount += 1
            }
            if duration.isFinite, duration >= 0 {
                entry.pipelineDurations.append(duration)
                if entry.pipelineDurations.count > 256 { entry.pipelineDurations.removeFirst() }
            }
        }
    }

    /// One event when an improvement finishes; no original or improved text is retained here.
    mutating func recordImprovementOffered(provider: AIProvider, model: String) {
        update(provider: provider, model: model) { $0.improvementOfferedCount += 1 }
    }

    /// The caller emits this only for the first explicit copy of a given improvement.
    mutating func recordImprovementAdopted(provider: AIProvider, model: String) {
        update(provider: provider, model: model) { $0.improvementAdoptedCount += 1 }
    }

    mutating func clear() { entries.removeAll() }

    private mutating func update(provider: AIProvider, model: String, _ change: (inout JevQualityMetric) -> Void) {
        let identifier = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return }
        let id = JevQualityMetric.ID(providerID: provider.rawValue, model: identifier)
        var entry = entries[id] ?? JevQualityMetric(id: id, provider: provider)
        change(&entry)
        entries[id] = entry
    }
}

enum JevMetricOutcome: Sendable { case completed, held, failed, cancelled }

struct JevQualityMetric: Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let providerID: String
        let model: String
    }
    let id: ID
    let provider: AIProvider
    fileprivate(set) var generationCount = 0
    fileprivate(set) var generationAttemptCount = 0
    fileprivate(set) var generationFailureCount = 0
    fileprivate(set) var generationCancellationCount = 0
    fileprivate(set) var generationLatencyTotal: TimeInterval = 0
    fileprivate(set) var generationLatencyCount = 0
    fileprivate(set) var reviewCount = 0
    fileprivate(set) var reviewAttemptCount = 0
    fileprivate(set) var reviewFailureCount = 0
    fileprivate(set) var reviewCancellationCount = 0
    fileprivate(set) var warningCount = 0
    fileprivate(set) var reviewLatencyTotal: TimeInterval = 0
    fileprivate(set) var reviewLatencyCount = 0
    fileprivate(set) var improvementOfferedCount = 0
    fileprivate(set) var improvementAdoptedCount = 0
    fileprivate(set) var pipelineAttemptCount = 0
    fileprivate(set) var pipelineCompletedCount = 0
    fileprivate(set) var pipelineHeldCount = 0
    fileprivate(set) var pipelineFailureCount = 0
    fileprivate(set) var pipelineCancellationCount = 0
    fileprivate var generationDurations: [TimeInterval] = []
    fileprivate var reviewDurations: [TimeInterval] = []
    fileprivate var pipelineDurations: [TimeInterval] = []
    var p50GenerationDuration: TimeInterval? { Self.percentile(generationDurations, 0.5) }
    var p95GenerationDuration: TimeInterval? { Self.percentile(generationDurations, 0.95) }
    var p50ReviewDuration: TimeInterval? { Self.percentile(reviewDurations, 0.5) }
    var p95ReviewDuration: TimeInterval? { Self.percentile(reviewDurations, 0.95) }
    var p50PipelineDuration: TimeInterval? { Self.percentile(pipelineDurations, 0.5) }
    var p95PipelineDuration: TimeInterval? { Self.percentile(pipelineDurations, 0.95) }
    var heldRate: Double? { pipelineAttemptCount > 0 ? Double(pipelineHeldCount) / Double(pipelineAttemptCount) : nil }

    /// Nearest-rank percentiles of the most recent 256 valid durations; never user text.
    private static func percentile(_ values: [TimeInterval], _ quantile: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), index = max(0, Int(ceil(Double(sorted.count) * quantile)) - 1)
        return sorted[index]
    }

    var meanGenerationDuration: TimeInterval? {
        generationLatencyCount > 0 ? generationLatencyTotal / Double(generationLatencyCount) : nil
    }

    var meanReviewDuration: TimeInterval? {
        reviewLatencyCount > 0 ? reviewLatencyTotal / Double(reviewLatencyCount) : nil
    }
}
