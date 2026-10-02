import Foundation
import OpenNoTypeCore

/// Disposable previews are tied to the exact source; neither is saved to history.
struct JevImprovement: Identifiable {
    let id: UUID
    let target: JevReviewTarget
    let provider: AIProvider
    let model: String
    let usageEpoch: UUID
    var output: String?
    var review: DecisionResult?
    var status: String?
    var isProcessing = true
    var adopted = false
}

struct JevCorrectionReview: Identifiable {
    let id: UUID
    let candidate: LearningCandidate
    let entry: DictionaryEntry
    var review: DecisionResult?
    var status: String?
    var isProcessing = true
    var canSave: Bool {
        !isProcessing && review?.terms.first?.choice == .useCandidate
            && (review?.maximumRiskProbability ?? 1) < 0.9
    }
}
