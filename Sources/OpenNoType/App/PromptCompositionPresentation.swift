import Foundation
import OpenNoTypeCore

enum PromptCompositionProgressStage: Equatable, Sendable {
    case drafting, reviewingDraft, polishing, reviewingFinal

    init(_ stage: PromptCompositionStage) {
        switch stage {
        case .drafting: self = .drafting
        case .reviewingDraft: self = .reviewingDraft
        case .polishing: self = .polishing
        case .reviewingFinal: self = .reviewingFinal
        }
    }
}

enum PromptCompositionInterruption: Equatable, Sendable {
    case generationFailed, reviewFailed, reviewHeld
}

/// Disposable source, intermediate draft and reviewed final prompt. No settings persistence.
struct PromptCompositionPresentation: Equatable, Sendable {
    let id = UUID()
    let transcript: String
    var originalTranscript: String? = nil
    var draft: String?
    var finalCandidate: String?
    var draftReview: PromptCompositionReviewResult?
    var finalReview: PromptCompositionReviewResult?
    var output: String?
    var status: String
    var isProcessing = true
    var held = false
    var stage: PromptCompositionProgressStage = .drafting
    var interruption: PromptCompositionInterruption?

    var recognizedTranscript: String { originalTranscript ?? transcript }
    var transcriptTitle: String {
        originalTranscript == nil ? L("말한 내용 보기", "View transcript")
            : L("프롬프트에 사용한 원문 보기", "View prompt source")
    }

    static func sourceValidationFailure(_ text: String) -> PromptCompositionFailure? {
        guard text.utf8.count <= PromptCompositionLimits.maximumSourceBytes else { return .inputTooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
              }) else { return .invalidInput }
        return nil
    }

    func canRegenerate(with text: String) -> Bool {
        !isProcessing && Self.sourceValidationFailure(text) == nil
    }

    mutating func stop(with error: Error) {
        isProcessing = false
        held = true
        status = error.localizedDescription
        if let failure = error as? PromptCompositionFailure, failure == .reviewHeld {
            interruption = .reviewHeld
        } else {
            switch stage {
            case .drafting, .polishing: interruption = .generationFailed
            case .reviewingDraft, .reviewingFinal: interruption = .reviewFailed
            }
        }
    }

    var title: String {
        switch interruption {
        case .generationFailed:
            return stage == .polishing ? L("프롬프트 다듬기 실패", "Prompt polishing failed")
                : L("프롬프트 생성 실패", "Prompt generation failed")
        case .reviewFailed: return L("프롬프트 검토 실패", "Prompt review failed")
        case .reviewHeld: return L("보류된 프롬프트", "Held prompt")
        case nil:
            if held { return L("프롬프트 만들기 중단", "Prompt creation stopped") }
            return isProcessing ? L("프롬프트 만드는 중", "Creating your prompt") : L("만든 프롬프트", "Your prompt")
        }
    }

    var interruptionDescription: String? {
        switch interruption {
        case .generationFailed:
            return stage == .polishing
                ? L("초안 검토 후 다듬기를 완료하지 못했습니다. 최종 검토는 시작되지 않았습니다.", "Polishing did not finish after the draft review. The final review has not started.")
                : L("초안을 만들지 못했습니다. Jev 검토는 시작되지 않았습니다.", "The draft could not be created. Jev review has not started.")
        case .reviewFailed:
            return stage == .reviewingFinal
                ? L("최종 후보의 Jev 검토를 완료하지 못했습니다. 내용에 대한 통과·보류 판정은 없습니다.", "Jev could not finish reviewing the final candidate. There is no pass or hold verdict for its content.")
                : L("초안의 Jev 검토를 완료하지 못했습니다. 다듬기와 최종 검토는 시작되지 않았습니다.", "Jev could not finish reviewing the draft. Polishing and the final review have not started.")
        case .reviewHeld, nil: return nil
        }
    }

    var inspectionDescription: String {
        var available: [String] = []
        if !transcript.isEmpty {
            available.append(originalTranscript == nil ? L("말한 내용", "the transcript")
                : L("프롬프트에 사용한 원문", "the prompt source"))
        }
        if let originalTranscript, !originalTranscript.isEmpty {
            available.append(L("처음 인식된 원문", "the originally recognized transcript"))
        }
        if held, let finalCandidate, !finalCandidate.isEmpty { available.append(L("최종 검토 후보", "the final review candidate")) }
        if let draft, !draft.isEmpty, draft != output, !held || draft != finalCandidate {
            available.append(L("중간 초안", "the intermediate draft"))
        }
        if finalReview != nil { available.append(L("최종 검토 항목", "the final review details")) }
        else if draftReview != nil { available.append(L("초안 검토 항목", "the draft review details")) }
        let contents = available.joined(separator: L("·", ", "))
        let details = available.isEmpty
            ? L("확인할 중간 내용이 없습니다.", "There is no intermediate content to inspect.")
            : L("추가 요청 없이 \(contents)을 확인할 수 있어요.", "You can inspect \(contents) without another request.")
        return L("아래 내용은 확인용이며 최종 프롬프트로 제공하지 않았습니다. ", "The content below is for inspection and was not provided as a final prompt. ") + details
    }
}
