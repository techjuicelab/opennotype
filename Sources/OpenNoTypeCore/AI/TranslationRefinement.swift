import Foundation

public enum TranslationRefinementFailure: String, Error, LocalizedError, Equatable, Sendable {
    case invalidRequest, inputTooLarge, invalidOutput, outputTooLarge, protectedContentChanged, requestFailed

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return L("번역을 다듬을 요청을 확인할 수 없어 입력을 보류했습니다.", "Insertion was held because the translation refinement request could not be verified.")
        case .inputTooLarge:
            return L("원문과 번역 초안이 다듬기 크기 제한을 초과하여 입력을 보류했습니다.", "Insertion was held because the source and translation draft exceed the refinement size limit.")
        case .invalidOutput:
            return L("다듬은 번역의 응답을 확인할 수 없어 입력을 보류했습니다.", "Insertion was held because the refined translation response could not be verified.")
        case .outputTooLarge:
            return L("다듬은 번역이 크기 제한을 초과하여 입력을 보류했습니다.", "Insertion was held because the refined translation exceeds the size limit.")
        case .protectedContentChanged:
            return L("다듬은 번역에서 보존 조건을 확인하지 못해 입력을 보류했습니다.", "Insertion was held because a protected translation constraint was not preserved.")
        case .requestFailed:
            return L("번역 다듬기를 완료하지 못해 입력을 보류했습니다. 원문과 초안을 확인해 주세요.", "Insertion was held because translation refinement did not finish. Check the source and draft.")
        }
    }
}

/// These cases describe string changes, not semantic approval or native-speaker quality.
public enum TranslationRefinementResult: Equatable, Sendable {
    case unchanged(String)
    case refined(String)
    case held(TranslationRefinementFailure)

    public var text: String? {
        switch self {
        case .unchanged(let text), .refined(let text): text
        case .held: nil
        }
    }
}

/// One optional text call. The caller retains the original and draft and controls insertion.
public enum TranslationRefinementRunner {
    public static let maximumCombinedTextBytes = 24_000
    public static let maximumRequestSeconds: TimeInterval = 30
    static let maximumPromptBytes = 64_000

    public static func run(request: ProcessingRequest, draft: String,
                           process: @Sendable (ProcessingRequest) async throws -> String) async throws -> TranslationRefinementResult {
        try Task.checkCancellation()
        guard request.requiresTranslation, request.previousOutput == nil, request.translationDraft == nil,
              !request.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .held(.invalidRequest)
        }
        guard validText(draft) else { return .held(.invalidOutput) }
        guard fits(source: request.transcript, text: draft) else { return .held(.inputTooLarge) }
        var refinement = request
        refinement.translationDraft = draft
        // Dictation review categories cannot authorize changing translation content.
        refinement.reviewLessons = []
        refinement.repairIssues = []
        do { _ = try ProcessingPrompt.build(refinement) }
        catch { return .held(.invalidRequest) }
        try Task.checkCancellation()
        do {
            let raw = try await process(refinement)
            try Task.checkCancellation()
            guard validText(raw) else { return .held(.invalidOutput) }
            let output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fits(source: request.transcript, text: output) else { return .held(.outputTooLarge) }
            // Apply the same narrow local checks as generation, against the source, not the draft.
            try TranslationOutputGuard.validate(source: request.transcript, output: output,
                                                targetLanguage: request.effectiveTargetLanguage)
            try Task.checkCancellation()
            return output == draft.trimmingCharacters(in: .whitespacesAndNewlines)
                ? .unchanged(output) : .refined(output)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            switch error as? ProviderError {
            case .translationLiteralChanged, .translationTimeInferred: return .held(.protectedContentChanged)
            case .emptyOutput, .invalidResponse, .incompleteOutput, .refused: return .held(.invalidOutput)
            case .responseTooLarge: return .held(.outputTooLarge)
            default: return .held(.requestFailed)
            }
        }
    }

    static func fits(source: String, text: String) -> Bool {
        source.utf8.count + text.utf8.count <= maximumCombinedTextBytes
    }

    static func validText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }
    }
}
