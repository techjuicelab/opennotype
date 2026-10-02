import Foundation
import Observation
import OpenNoTypeCore

/// Explicit, bounded evaluation only. Cases and outputs are transient and never change app settings.
@MainActor @Observable
final class JevModelComparison {
    var cases: [ModelEvaluationCase] = [] { didSet { if oldValue != cases { invalidate() } } }
    var selectedModels: [String] = [] { didSet { if oldValue != selectedModels { invalidate() } } }
    var budgetUSD: Double = 0.05 { didSet { if oldValue != budgetUSD { invalidate() } } }
    private(set) var rows: [ModelEvaluationRow] = []
    private(set) var status: String?
    private(set) var isRunning = false
    private(set) var recommendedModel: String?
    private(set) var estimatedReservationUSD: Double?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func cancelAll() {
        invalidate()
        status = L("비교를 취소했습니다. 문장 모델 설정은 바꾸지 않았습니다.", "Comparison cancelled. Your text-model setting is unchanged.")
    }

    func clearSensitiveData() {
        invalidate()
        cases.removeAll()
    }

    func reportPreparationFailure() {
        status = L("모델 비교 연결을 준비하지 못했습니다. 저장된 문장·Jev 키를 확인해 주세요.", "Could not prepare model comparison. Check the saved text and Jev keys.")
    }

    private func invalidate() {
        epoch = UUID(); task?.cancel(); task = nil; deadlineTask?.cancel(); deadlineTask = nil
        isRunning = false; rows = []; recommendedModel = nil; estimatedReservationUSD = nil; status = nil
    }

    func run(configuration: ProviderConfiguration, decisionConfiguration: DecisionConfiguration,
             dictionary: [DictionaryEntry], client: ProviderClient, reviewer: any DecisionEvaluating,
             onUsage: (@Sendable (ProviderUsage) async -> Void)? = nil) async {
        guard !isRunning else { return }
        invalidate()
        let selectedCases = cases, selected = selectedModels, budget = budgetUSD
        let plan: ModelEvaluationPlan
        do {
            plan = try JevModelEvaluation.plan(cases: selectedCases, models: selected,
                provider: configuration.provider, decisionProvider: decisionConfiguration.provider,
                dictionary: dictionary, budgetUSD: budget)
        } catch {
            if case ModelEvaluationError.exceedsBudget(let estimate) = error { estimatedReservationUSD = estimate }
            status = error.localizedDescription; return
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !decisionConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = L("문장 처리와 Jev 검토에 저장된 API 키가 필요합니다.", "Saved API keys are required for text processing and Jev review."); return
        }
        let operation = UUID(); epoch = operation
        estimatedReservationUSD = plan.estimatedReservationUSD
        rows = plan.models.map { .init(model: $0, expectedCount: selectedCases.count) }
        isRunning = true
        status = L("승인한 같은 사례로 문장 모델을 비교하고 있어요…", "Comparing text models on the same approved cases…")
        let pending = Task { [weak self] in
            guard let self else { return }
            await execute(cases: selectedCases, plan: plan, budget: budget, operation: operation,
                configuration: configuration, decisionConfiguration: decisionConfiguration,
                dictionary: dictionary, client: client, reviewer: reviewer, onUsage: onUsage)
        }
        task = pending
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, epoch == operation, isRunning else { return }
            epoch = UUID(); task?.cancel(); task = nil; isRunning = false; recommendedModel = nil
            status = ModelEvaluationError.expired.localizedDescription
        }
        await pending.value
        guard epoch == operation else { return }
        deadlineTask?.cancel(); deadlineTask = nil; task = nil; isRunning = false
    }

    private func execute(cases: [ModelEvaluationCase], plan: ModelEvaluationPlan, budget: Double, operation: UUID,
                         configuration: ProviderConfiguration, decisionConfiguration: DecisionConfiguration,
                         dictionary: [DictionaryEntry], client: ProviderClient, reviewer: any DecisionEvaluating,
                         onUsage: (@Sendable (ProviderUsage) async -> Void)?) async {
        func current() -> Bool { !Task.isCancelled && epoch == operation }
        let totalLedger = ModelEvaluationUsageLedger()
        for model in plan.models {
            let modelLedger = ModelEvaluationUsageLedger()
            let collectUsage: @Sendable (ProviderUsage) async -> Void = { event in
                await totalLedger.record(event); await modelLedger.record(event)
                await onUsage?(event)
            }
            var config = configuration; config.textModel = model
            for item in cases {
                guard current() else { return }
                var output: String?
                var duration: TimeInterval?
                do {
                    guard let reservation = plan.reservations.first(where: { $0.model == model && $0.caseID == item.id }) else {
                        throw ModelEvaluationError.unavailablePrice
                    }
                    let beforeGeneration = await totalLedger.count
                    let previousCosts = await totalLedger.summary()
                    guard current() else { return }
                    let previousAmount = beforeGeneration == 0 ? 0 : previousCosts.amount
                    guard let previousAmount else { throw ModelEvaluationError.unknownCost }
                    guard previousAmount + reservation.generationUSD + reservation.reviewUSD <= budget else {
                        throw ModelEvaluationError.exceedsBudget(estimate: previousAmount + reservation.generationUSD + reservation.reviewUSD)
                    }
                    let started = ProcessInfo.processInfo.systemUptime
                    // approvedText is deliberately absent. Every model sees the same source and hints.
                    let generated = try await client.process(.init(mode: .dictation, transcript: item.transcript,
                        dictionary: dictionary), configuration: config, allowRetry: false, onUsage: collectUsage)
                    guard current() else { return }
                    output = generated; duration = ProcessInfo.processInfo.systemUptime - started
                    let textCosts = await modelLedger.summary()
                    guard current() else { return }
                    let afterGeneration = await totalLedger.count
                    guard current() else { return }
                    guard textCosts.allKnown, afterGeneration == beforeGeneration + 1 else { throw ModelEvaluationError.unknownCost }
                    let total = await totalLedger.summary()
                    guard current() else { return }
                    guard let spent = total.amount, spent + reservation.reviewUSD <= budget else {
                        throw ModelEvaluationError.exceedsBudget(estimate: (total.amount ?? budget) + reservation.reviewUSD)
                    }
                    guard item.approvedText.utf8.count + generated.utf8.count <= 16_000 else { throw DecisionError.inputTooLarge }
                    // The reference is the user's approved answer, not the possibly misrecognized ASR.
                    let reviewed = try await reviewer.evaluate(.init(transcript: item.approvedText, cleanedText: generated),
                        configuration: decisionConfiguration, onUsage: collectUsage)
                    guard current() else { return }
                    // Some injected evaluators return usage instead of invoking the callback. Dedupe by request ID.
                    if let usage = reviewed.usage {
                        let isNew = await totalLedger.record(usage)
                        await modelLedger.record(usage)
                        if isNew { await onUsage?(usage) }
                        guard current() else { return }
                    }
                    let costs = await modelLedger.summary()
                    let grandTotal = await totalLedger.summary()
                    let afterReview = await totalLedger.count
                    guard current() else { return }
                    guard costs.allKnown, grandTotal.allKnown, afterReview == afterGeneration + 1 else { throw ModelEvaluationError.unknownCost }
                    guard let spent = grandTotal.amount, spent <= budget else { throw ModelEvaluationError.exceedsBudget(estimate: grandTotal.amount ?? budget) }
                    let passed = JevModelEvaluation.passes(approvedText: item.approvedText, output: generated, review: reviewed)
                    let issue = passed ? nil : L("승인 정답과 의미 또는 고정 표기가 다르거나, 검토 신호가 불확실합니다.", "Meaning or literal text differs from the approved answer, or the review signal is uncertain.")
                    append(.init(caseID: item.id, text: generated, passed: passed, issue: issue, seconds: duration),
                           to: model, cost: costs.amount, completed: true)
                } catch {
                    guard current() else { return }
                    let costs = await modelLedger.summary()
                    guard current() else { return }
                    let message = error is ModelEvaluationError ? error.localizedDescription : ModelEvaluationError.failedRequest.localizedDescription
                    let cost: Double?
                    if case ModelEvaluationError.unknownCost = error { cost = nil } else { cost = costs.amount }
                    append(.init(caseID: item.id, text: output, passed: false, issue: message, seconds: duration),
                           to: model, cost: cost, completed: false)
                    if let index = rows.firstIndex(where: { $0.model == model }) { rows[index].errors.append(message) }
                    status = message; recommendedModel = nil; return
                }
            }
        }
        guard current() else { return }
        rows = JevModelEvaluation.ranked(rows)
        recommendedModel = JevModelEvaluation.recommendedModel(rows)
        status = recommendedModel == nil
            ? L("비교를 마쳤습니다. 모든 승인 사례의 조건을 충족한 추천 모델은 없습니다. 각 결과를 직접 확인해 주세요.", "Comparison complete. No model met the conditions for every approved case. Inspect the outputs.")
            : L("비교를 마쳤습니다. 추천은 이 사례들에서의 적합성·비용·생성 시간을 기준으로 하며 정확도 보장은 아닙니다.", "Comparison complete. The recommendation reflects these cases, cost and generation time; it is not an accuracy guarantee.")
    }

    private func append(_ output: ModelEvaluationOutput, to model: String, cost: Double?, completed: Bool) {
        guard let index = rows.firstIndex(where: { $0.model == model }) else { return }
        rows[index].outputs.append(output); rows[index].totalCostUSD = cost
        if completed { rows[index].completedCount += 1 }
        if output.passed { rows[index].passedCount += 1 }
    }
}

private actor ModelEvaluationUsageLedger {
    private var events: [UUID: ProviderUsage] = [:]
    var count: Int { events.count }
    @discardableResult func record(_ event: ProviderUsage) -> Bool {
        let isNew = events[event.id] == nil; events[event.id] = event; return isNew
    }
    struct Summary { let allKnown: Bool; let amount: Double? }
    func summary() -> Summary {
        let costs = events.values.map { UsagePricing.cost(for: $0).usd }
        guard !costs.isEmpty, costs.allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } == true }) else {
            return .init(allKnown: false, amount: nil)
        }
        let sum = costs.compactMap { $0 }.reduce(0, +)
        return .init(allKnown: sum.isFinite, amount: sum.isFinite ? sum : nil)
    }
}
