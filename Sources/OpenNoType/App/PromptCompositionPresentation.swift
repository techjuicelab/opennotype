import Foundation
import OpenNoTypeCore

/// Disposable source, intermediate draft and reviewed final prompt. No settings persistence.
struct PromptCompositionPresentation: Equatable, Sendable {
    let transcript: String
    var draft: String?
    var finalCandidate: String?
    var draftReview: PromptCompositionReviewResult?
    var finalReview: PromptCompositionReviewResult?
    var output: String?
    var status: String
    var isProcessing = true
    var held = false
}
