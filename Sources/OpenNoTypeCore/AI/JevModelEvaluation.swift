import Foundation

/// A user-approved evaluation example, held in memory only. Approval is never inferred from history.
public struct ModelEvaluationCase: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var transcript: String
    public var approvedText: String
    public init(id: UUID = UUID(), transcript: String, approvedText: String) {
        self.id = id; self.transcript = transcript; self.approvedText = approvedText
    }
}

public struct ModelEvaluationOutput: Identifiable, Equatable, Sendable {
    public var id: UUID { caseID }
    public let caseID: UUID
    public let text: String?
    public let passed: Bool
    public let issue: String?
    /// Text-generation duration only; the separate Jev call is excluded.
    public let seconds: TimeInterval?
    public init(caseID: UUID, text: String?, passed: Bool, issue: String?, seconds: TimeInterval?) {
        self.caseID = caseID; self.text = text; self.passed = passed; self.issue = issue; self.seconds = seconds
    }
}

public struct ModelEvaluationRow: Identifiable, Equatable, Sendable {
    public var id: String { model }
    public let model: String
    public let expectedCount: Int
    public var completedCount = 0
    public var passedCount = 0
    public var totalCostUSD: Double?
    public var errors: [String] = []
    public var outputs: [ModelEvaluationOutput] = []
    public var meanSeconds: TimeInterval? {
        let times = outputs.compactMap(\.seconds).filter { $0.isFinite && $0 >= 0 }
        guard !times.isEmpty else { return nil }
        let sum = times.reduce(0, +)
        return sum.isFinite ? sum / Double(times.count) : nil
    }
    public init(model: String, expectedCount: Int) { self.model = model; self.expectedCount = expectedCount }
}

public struct ModelEvaluationPlan: Equatable, Sendable {
    public let models: [String]
    public let estimatedReservationUSD: Double
    public let maximumCalls: Int
    public let reservations: [ModelEvaluationReservation]
}

public struct ModelEvaluationReservation: Equatable, Sendable {
    public let model: String
    public let caseID: UUID
    public let generationUSD: Double
    public let reviewUSD: Double
}

public enum ModelEvaluationError: Error, LocalizedError, Equatable, Sendable {
    case invalidCases, inputTooLarge, invalidModels, invalidBudget, unavailablePrice, exceedsBudget(estimate: Double), unknownCost, failedRequest, expired
    public var errorDescription: String? {
        switch self {
        case .invalidCases: L("승인할 원문과 정답을 1~5개 입력해 주세요. 문장당 최대 4,000바이트이며 비어 있으면 안 됩니다.", "Enter 1–5 source and approved-answer pairs, each nonempty and at most 4,000 bytes per text.")
        case .inputTooLarge: L("사전 힌트를 포함한 평가 입력이 16 KB를 넘습니다. 사례나 사전 힌트를 줄여 주세요.", "Evaluation input including dictionary hints exceeds 16 KB. Reduce the examples or dictionary hints.")
        case .invalidModels: L("서로 다른 문장 모델 2~3개를 선택해 주세요.", "Select 2–3 different text models.")
        case .invalidBudget: L("비교 예산은 US$0 초과, US$0.20 이하여야 합니다.", "The comparison budget must be greater than US$0 and at most US$0.20.")
        case .unavailablePrice: L("선택 모델의 예약 비용을 계산할 수 없어 전송하지 않았습니다.", "Nothing was sent because a selected model's reservation cost is unknown.")
        case .exceedsBudget(let amount): L("보수적 예상 상한 US$\(String(format: "%.4f", amount))이 예산을 넘습니다. 모델·사례 수를 줄이거나 예산을 조정해 주세요.", "The conservative estimated ceiling of US$\(String(format: "%.4f", amount)) exceeds the budget. Reduce the models or cases, or adjust the budget.")
        case .unknownCost: L("한 요청의 비용을 확인하지 못해 남은 비교를 중단했습니다. 무료로 집계하지 않습니다.", "Stopped the remaining comparison because a request's cost is unknown. It is not counted as free.")
        case .failedRequest: L("요청이 실패해 남은 비교를 중단했습니다. 기존 문장 모델 설정은 유지됩니다.", "A request failed, so the remaining comparison stopped. Your text-model setting is unchanged.")
        case .expired: L("비교 제한 시간 60초가 지나 남은 요청을 취소했습니다.", "The 60-second comparison limit was reached; remaining requests were cancelled.")
        }
    }
}

/// Pure evaluation policy: no networking, storage, model switching or inferred human approval.
public enum JevModelEvaluation {
    public static let maximumBudgetUSD = 0.20
    public static let maximumOutputTokens = 16_384

    public static func plan(cases: [ModelEvaluationCase], models: [String], provider: AIProvider,
                            decisionProvider: DecisionProvider, dictionary: [DictionaryEntry],
                            budgetUSD: Double) throws -> ModelEvaluationPlan {
        guard (1...5).contains(cases.count), Set(cases.map(\.id)).count == cases.count,
              cases.allSatisfy({ item in [item.transcript, item.approvedText].allSatisfy {
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4_000
              } }) else { throw ModelEvaluationError.invalidCases }
        let identifiers = models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...3).contains(identifiers.count), Set(identifiers).count == identifiers.count,
              identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256
                  && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
            throw ModelEvaluationError.invalidModels
        }
        guard budgetUSD.isFinite, budgetUSD > 0, budgetUSD <= maximumBudgetUSD else { throw ModelEvaluationError.invalidBudget }
        var estimate: Double = 0
        var reservations: [ModelEvaluationReservation] = []
        for model in identifiers {
            for item in cases {
                let prompt = try ProcessingPrompt.build(.init(mode: .dictation, transcript: item.transcript, dictionary: dictionary))
                guard prompt.input.utf8.count <= 16_000 else { throw ModelEvaluationError.inputTooLarge }
                // UTF-8 bytes plus framing is a deliberately generous input-token reservation.
                let upperInput = prompt.instructions.utf8.count + prompt.input.utf8.count + 4_096
                let generation: Double
                if provider == .openRouter {
                    guard let price = TextModelCatalog.entry(id: model, provider: provider)?.price,
                          price.inputUSDPerMillion.isFinite, price.inputUSDPerMillion >= 0,
                          price.outputUSDPerMillion.isFinite, price.outputUSDPerMillion >= 0 else { throw ModelEvaluationError.unavailablePrice }
                    generation = (Double(upperInput) * price.inputUSDPerMillion
                                  + Double(maximumOutputTokens) * price.outputUSDPerMillion) / 1_000_000
                } else {
                    let usage = ProviderUsage(provider: provider, model: model, stage: .textProcessing,
                                              inputTokens: upperInput, outputTokens: maximumOutputTokens)
                    guard let value = UsagePricing.cost(for: usage).usd else { throw ModelEvaluationError.unavailablePrice }
                    generation = value
                }
                let review = decisionReservationUSD(provider: decisionProvider)
                estimate += generation + review
                reservations.append(.init(model: model, caseID: item.id, generationUSD: generation, reviewUSD: review))
            }
        }
        guard estimate.isFinite, estimate >= 0 else { throw ModelEvaluationError.unavailablePrice }
        guard estimate <= budgetUSD else { throw ModelEvaluationError.exceedsBudget(estimate: estimate) }
        return .init(models: identifiers, estimatedReservationUSD: estimate,
                     maximumCalls: identifiers.count * cases.count * 2, reservations: reservations)
    }

    /// A reservation, not a promise of the provider's final bill. The existing verified Jev 1.13
    /// benchmark uses $0.042/M input and free output for both routes (2026-10-01).
    private static func decisionReservationUSD(provider: DecisionProvider) -> Double {
        let upperInput = DecisionClient.maximumRequestBytes + 4_096
        if provider == .typeSafe {
            let usage = ProviderUsage(decisionProvider: provider, model: provider.model, reportedModel: provider.model,
                                      stage: .decisionReview, inputTokens: upperInput, outputTokens: 0)
            return UsagePricing.cost(for: usage).usd ?? .infinity
        }
        return Double(upperInput) * 0.042 / 1_000_000
    }

    /// A semantic signal is only one condition. Literal differences fail this conservative sample
    /// check even when Jev misses them; a pass is not a calibrated accuracy score.
    public static func passes(approvedText: String, output: String, review: DecisionResult) -> Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && [review.meaningChanged, review.contentAdded, review.contentOmitted].allSatisfy { $0.isFinite && (0..<0.5).contains($0) }
            && literalsPreserved(approvedText: approvedText, output: output)
    }

    public static func literalsPreserved(approvedText: String, output: String) -> Bool {
        func literals(_ text: String) -> [String: Int] {
            let pattern = #"https?://[^\s<>\"']+|`[^`\n]+`|\"[^\"\n]+\"|'[^'\n]+'|“[^”\n]+”|‘[^’\n]+’|\p{N}+(?:[.,:/-]\p{N}+)*|[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|(?<![A-Za-z0-9_])(?=[A-Za-z0-9]*[A-Z][A-Za-z0-9]*[A-Z])[A-Za-z][A-Za-z0-9]*(?![A-Za-z0-9_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
            var result: [String: Int] = [:]
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { result[String(text[range]), default: 0] += 1 }
            }
            return result
        }
        return literals(approvedText) == literals(output)
    }

    public static func ranked(_ rows: [ModelEvaluationRow]) -> [ModelEvaluationRow] {
        rows.sorted {
            if $0.passedCount != $1.passedCount { return $0.passedCount > $1.passedCount }
            if $0.completedCount != $1.completedCount { return $0.completedCount > $1.completedCount }
            let leftCost = $0.totalCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
            let rightCost = $1.totalCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
            if leftCost != rightCost { return leftCost < rightCost }
            let leftTime = $0.meanSeconds ?? .infinity, rightTime = $1.meanSeconds ?? .infinity
            return leftTime == rightTime ? $0.model < $1.model : leftTime < rightTime
        }
    }

    public static func recommendedModel(_ rows: [ModelEvaluationRow]) -> String? {
        ranked(rows).first { $0.expectedCount > 0 && $0.completedCount == $0.expectedCount
            && $0.passedCount == $0.expectedCount && $0.errors.isEmpty
            && $0.totalCostUSD.map({ $0.isFinite && $0 >= 0 }) == true }?.model
    }
}
