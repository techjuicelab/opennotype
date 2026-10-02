import Foundation
import OpenNoTypeCore

/// Transient sources and alternatives. Never persisted, and never used to retarget automatic typing.
struct JevEditClarification: Identifiable {
    let id: UUID
    let original: String
    let instruction: String
    var assessment: DecisionEditAssessment?
    var output: String?
    var status: String?
    var isProcessing = false
}

struct JevReRecognition: Identifiable {
    let id: UUID
    let original: String
    var alternative: String?
    var assessment: DecisionTranscriptAssessment?
    var output: String?
    var status: String?
    var isProcessing = true
}

/// Local gates deliberately require exact equality. They do not guess semantic safety.
enum JevAssistancePolicy {
    static func canSkipReview(transcript: String, output: String, terms: [DecisionTermCandidate]) -> Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && transcript == output && terms.isEmpty
    }

    static func editIsClear(_ value: DecisionEditAssessment?) -> Bool {
        guard let value else { return false }
        return value.choice == .clear && value.confidence >= 0.6 && (value.probabilities[.clear] ?? 0) >= 0.7
    }

    static func transcriptsEquivalent(_ value: DecisionTranscriptAssessment) -> Bool {
        value.choice == .equivalent && value.confidence >= 0.6 && (value.probabilities[.equivalent] ?? 0) >= 0.7
    }

    static func needsNameRecheck(output: String, terms: [DecisionTermCandidate]) -> Bool {
        terms.contains { output.localizedCaseInsensitiveContains($0.original)
            && !output.localizedCaseInsensitiveContains($0.candidate) }
    }

    static func alternativeTranscriptionConfiguration(_ selected: ProviderConfiguration) -> ProviderConfiguration? {
        var alternate = selected
        switch selected.provider {
        case .groq:
            guard ["whisper-large-v3", "whisper-large-v3-turbo"].contains(selected.transcriptionModel) else { return nil }
            alternate.transcriptionModel = selected.transcriptionModel == "whisper-large-v3"
                ? "whisper-large-v3-turbo" : "whisper-large-v3"
        case .openAI:
            guard ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"].contains(selected.transcriptionModel) else { return nil }
            alternate.transcriptionModel = selected.transcriptionModel == "gpt-4o-transcribe"
                ? "gpt-4o-mini-transcribe" : "gpt-4o-transcribe"
        case .openRouter, .anthropic: return nil
        }
        return alternate
    }

    /// Reserve a conservative known-price ceiling before an automatic extra request.
    static func automaticImprovementFitsBudget(model: String, provider: AIProvider, promptBytes: Int) -> Bool {
        guard promptBytes >= 0, promptBytes <= 100_000,
              let entry = TextModelCatalog.entries(for: provider).first(where: { $0.id == model }) else { return false }
        let input = entry.price.inputUSDPerMillion, output = entry.price.outputUSDPerMillion
        let estimatedInput = Double(promptBytes + 1_024) // Includes a conservative request framing reserve.
        let maximum = (estimatedInput * input + 16_384 * output) / 1_000_000 + 0.003
        return maximum.isFinite && maximum <= 0.05
    }
}

private enum JevDeadlineError: Error { case expired }

/// Cancels URLSession work when the auxiliary request exceeds its bounded wait.
func jevWithDeadline<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw JevDeadlineError.expired
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw CancellationError() }
        return value
    }
}
