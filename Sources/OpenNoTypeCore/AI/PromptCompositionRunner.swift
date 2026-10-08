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
    public static func run(request: ProcessingRequest,
        process: @Sendable (ProcessingRequest) async throws -> String,
        review: @Sendable (PromptCompositionReviewRequest) async throws -> PromptCompositionReviewResult,
        onProgress: @Sendable (PromptCompositionStage, String?) async throws -> Void = { _, _ in }
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
        func checked(_ text: String) throws -> String {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PromptCompositionLimits.validOutput(value) else { throw PromptCompositionFailure.invalidOutput }
            return value
        }
        try await onProgress(.drafting, nil)
        try Task.checkCancellation()
        let draft = try checked(await process(request))
        try Task.checkCancellation()
        try await onProgress(.reviewingDraft, draft)
        let first = try await review(.init(transcript: request.transcript, prompt: draft))
        try Task.checkCancellation()
        guard first.isValid else { throw PromptCompositionFailure.reviewUnavailable }
        var refinement = request
        refinement.promptDraft = draft
        refinement.promptReviewIssues = first.issues
        try await onProgress(.polishing, draft)
        try Task.checkCancellation()
        let polished = try checked(await process(refinement))
        // A draft with no review issues must not drift during an unnecessary rewording.
        // The selected text itself still needs the independent final review.
        let final = first.accepted ? draft : polished
        try Task.checkCancellation()
        try await onProgress(.reviewingFinal, draft)
        let last = try await review(.init(transcript: request.transcript, prompt: final))
        try Task.checkCancellation()
        guard last.isValid else { throw PromptCompositionFailure.reviewUnavailable }
        guard last.accepted else { throw PromptCompositionFailure.reviewHeld }
        return .init(draft: draft, text: final)
    }
}
