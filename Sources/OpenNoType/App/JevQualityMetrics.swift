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
    mutating func recordGeneration(provider: AIProvider, model: String, duration: TimeInterval) {
        update(provider: provider, model: model) { entry in
            entry.generationCount += 1
            if duration.isFinite, duration >= 0, (entry.generationLatencyTotal + duration).isFinite {
                entry.generationLatencyTotal += duration
                entry.generationLatencyCount += 1
            }
        }
    }

    /// Attribute a completed review to the model that produced the text, not the Jev reviewer.
    mutating func recordReview(provider: AIProvider, model: String, warning: Bool, duration: TimeInterval) {
        update(provider: provider, model: model) { entry in
            entry.reviewCount += 1
            if warning { entry.warningCount += 1 }
            if duration.isFinite, duration >= 0, (entry.reviewLatencyTotal + duration).isFinite {
                entry.reviewLatencyTotal += duration
                entry.reviewLatencyCount += 1
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

struct JevQualityMetric: Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let providerID: String
        let model: String
    }
    let id: ID
    let provider: AIProvider
    fileprivate(set) var generationCount = 0
    fileprivate(set) var generationLatencyTotal: TimeInterval = 0
    fileprivate(set) var generationLatencyCount = 0
    fileprivate(set) var reviewCount = 0
    fileprivate(set) var warningCount = 0
    fileprivate(set) var reviewLatencyTotal: TimeInterval = 0
    fileprivate(set) var reviewLatencyCount = 0
    fileprivate(set) var improvementOfferedCount = 0
    fileprivate(set) var improvementAdoptedCount = 0

    var meanGenerationDuration: TimeInterval? {
        generationLatencyCount > 0 ? generationLatencyTotal / Double(generationLatencyCount) : nil
    }

    var meanReviewDuration: TimeInterval? {
        reviewLatencyCount > 0 ? reviewLatencyTotal / Double(reviewLatencyCount) : nil
    }
}
