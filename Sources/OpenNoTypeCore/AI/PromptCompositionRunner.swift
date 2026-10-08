import Foundation

public enum PromptCompositionStage: Sendable {
    case drafting, reviewingDraft, polishing, reviewingFinal
}

public enum PromptCompositionFailure: Error, LocalizedError, Equatable, Sendable {
    case invalidInput, inputTooLarge, invalidOutput, reviewUnavailable, reviewHeld

    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            L("프롬프트로 정리할 발화를 확인해 주세요.", "Check the speech to turn into a prompt.")
        case .inputTooLarge:
            L("프롬프트 원문은 UTF-8 기준 12,000바이트까지입니다. 내용을 나누어 말해 주세요.", "Prompt source text can be up to 12,000 UTF-8 bytes. Split the recording into smaller requests.")
        case .invalidOutput:
            L("생성된 프롬프트가 비어 있거나 형식 또는 길이를 확인하지 못했습니다. 원문을 확인해 주세요.", "The generated prompt was empty or its format or length could not be verified. Check the transcript.")
        case .reviewUnavailable:
            L("Jev 검토를 완료하지 못했습니다. 최종 프롬프트로 제공하지 않았습니다.", "Jev review did not finish. No final prompt was provided.")
        case .reviewHeld:
            L("최종 검토에 확인이 필요한 항목이 있어 프롬프트를 보류했습니다. 원문과 초안을 확인해 주세요.", "The final review needs attention, so the prompt was held. Check the transcript and draft.")
        }
    }
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
