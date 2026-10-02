import Foundation
import OpenNoTypeCore

enum JevRepairAttempt: Sendable {
    case repaired(text: String, review: DecisionResult, issues: [JevRepairIssue])
    case held(String)
    case cancelled
}

/// One generation and one independent recheck, never a retry loop or an insertion operation.
enum JevRepairRunner {
    static func run(request: ProcessingRequest, originalOutput: String, initialReview: DecisionResult,
                    configuration: ProviderConfiguration, decisionConfiguration: DecisionConfiguration,
                    terms: [DecisionTermCandidate], detailed: Bool,
                    client: ProviderClient, decisionClient: any DecisionEvaluating,
                    onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async -> JevRepairAttempt {
        var issues = JevRepairPolicy.issues(in: initialReview)
        if issues.isEmpty { issues = terms.isEmpty ? [.meaning] : [.entities] }
        var repair = request
        repair.context = nil
        repair.previousOutput = originalOutput
        repair.repairIssues = issues
        guard let reservation = JevRepairPolicy.repairReservationUSD(request: repair, configuration: configuration),
              reservation <= 0.05 else {
            return .held(L("교정 요청의 참고 비용 상한이 US$0.05 이내인지 확인하지 못했습니다.",
                           "The repair's reference-price reservation could not be confirmed within US$0.05."))
        }
        do {
            try Task.checkCancellation()
            let captured = repair
            let text = try await jevWithDeadline(seconds: 8) {
                try await client.process(captured, configuration: configuration, allowRetry: false, onUsage: onUsage)
            }
            try Task.checkCancellation()
            let review = try await decisionClient.evaluate(.init(transcript: request.transcript, cleanedText: text,
                termCandidates: terms, detailAxes: detailed ? DecisionDetailAxis.allCases : []),
                configuration: decisionConfiguration, onUsage: onUsage)
            try Task.checkCancellation()
            guard JevRepairPolicy.acceptsRepair(transcript: request.transcript, originalOutput: originalOutput,
                                                repairedOutput: text, review: review, terms: terms) else {
                return .held(L("교정안을 재검사했지만 의미·표기 보존 조건을 충족하지 못했습니다.",
                               "The repaired text did not meet the meaning and spelling preservation checks."))
            }
            return .repaired(text: text, review: review, issues: issues)
        } catch {
            if Task.isCancelled || error is CancellationError { return .cancelled }
            return .held(L("교정 또는 재검사를 완료하지 못했습니다. 원문과 결과를 직접 확인해 주세요.",
                           "Repair or recheck was unavailable. Compare the source and result yourself."))
        }
    }
}
