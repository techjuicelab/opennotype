import Foundation

public enum PromptCompositionStage: Sendable {
    case drafting, reviewingDraft, polishing, reviewingFinal
}

public struct PromptCompositionOutput: Equatable, Sendable {
    public let draft: String
    public let text: String
}

/// Two bounded generation calls and two independent reviews. Never executes the generated request.
public enum PromptCompositionRunner {
    /// Delivers valid request/review pairs before rejecting a held result, so callers can retain evidence.
    public static func run(request: ProcessingRequest,
        process: @Sendable (ProcessingRequest) async throws -> String,
        review: @Sendable (PromptCompositionReviewRequest) async throws -> PromptCompositionReviewResult,
        onProgress: @Sendable (PromptCompositionStage, String?) async throws -> Void = { _, _ in },
        onReview: @Sendable (PromptCompositionStage, PromptCompositionReviewRequest,
                            PromptCompositionReviewResult) async throws -> Void = { _, _, _ in }
    ) async throws -> PromptCompositionOutput {
        try Task.checkCancellation()
        guard request.mode == .prompt, request.promptDraft == nil, request.translationDraft == nil,
              request.previousOutput == nil, request.promptReviewIssues.isEmpty,
              !request.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptCompositionFailure.invalidInput
        }
        guard request.transcript.utf8.count <= PromptCompositionLimits.maximumSourceBytes else {
            throw PromptCompositionFailure.inputTooLarge
        }
        guard PromptCompositionLimits.validText(request.transcript, maximumBytes: PromptCompositionLimits.maximumSourceBytes) else {
            throw PromptCompositionFailure.invalidInput
        }
        func checked(_ text: String, isDraft: Bool = false) throws -> String {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let valid = isDraft ? PromptCompositionLimits.validDraft(text) : PromptCompositionLimits.validOutput(text)
            guard valid else { throw PromptCompositionFailure.invalidOutput }
            return value
        }
        try await onProgress(.drafting, nil)
        try Task.checkCancellation()
        let draft = try checked(await process(request), isDraft: true)
        let draftIsComplete = PromptCompositionLimits.validOutput(draft)
        try Task.checkCancellation()
        try await onProgress(.reviewingDraft, draft)
        let draftReviewRequest = PromptCompositionReviewRequest(transcript: request.transcript, prompt: draft)
        let first = try await review(draftReviewRequest)
        try Task.checkCancellation()
        guard first.isValid else { throw PromptCompositionFailure.reviewUnavailable }
        try await onReview(.reviewingDraft, draftReviewRequest, first)
        try Task.checkCancellation()
        var refinement = request
        refinement.promptDraft = draft
        var repairIssues = Set(first.issues)
        if !draftIsComplete { repairIssues.insert(.intent) }
        refinement.promptReviewIssues = PromptCompositionIssue.allCases.filter(repairIssues.contains)
        try await onProgress(.polishing, draft)
        try Task.checkCancellation()
        let polished = try checked(await process(refinement))
        // A complete draft with no review issues must not drift during an unnecessary rewording.
        // The selected text itself still needs the independent final review.
        let final = first.accepted && draftIsComplete ? draft : polished
        try Task.checkCancellation()
        try await onProgress(.reviewingFinal, final)
        let finalReviewRequest = PromptCompositionReviewRequest(transcript: request.transcript, prompt: final)
        let last = try await review(finalReviewRequest)
        try Task.checkCancellation()
        guard last.isValid else { throw PromptCompositionFailure.reviewUnavailable }
        try await onReview(.reviewingFinal, finalReviewRequest, last)
        try Task.checkCancellation()
        guard last.accepted else { throw PromptCompositionFailure.reviewHeld }
        return .init(draft: draft, text: final)
    }
}
