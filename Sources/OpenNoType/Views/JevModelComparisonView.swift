import SwiftUI
import OpenNoTypeCore

/// This sheet asks for approved examples explicitly; it never imports or scans history.
struct JevModelComparisonView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var approved = false
    @State private var confirmsRun = false
    @State private var showsResults = false
    @State private var expandedCaseID: UUID?
    @State private var modelRowIDs = [UUID(), UUID()]

    private var comparison: JevModelComparison { model.jevModelComparison }
    private var catalog: [TextModelCatalogEntry] { TextModelCatalog.entries(for: model.preferences.effectiveTextProvider) }
    private var priceVerificationDates: String { Set(catalog.map { $0.price.asOf }).sorted().joined(separator: ", ") }
    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }
    private var locked: Bool { comparison.isRunning || model.jevModelComparisonPreparing }
    private var evaluationPlan: Result<ModelEvaluationPlan, Error> {
        Result {
            try JevModelEvaluation.plan(cases: comparison.cases, models: comparison.selectedModels,
                provider: model.preferences.effectiveTextProvider, decisionProvider: model.preferences.decisionProvider,
                dictionary: model.dictionary, budgetUSD: comparison.budgetUSD)
        }
    }
    private var planFailure: Error? {
        if case .failure(let error) = evaluationPlan { return error }
        return nil
    }
    private var canRun: Bool { editable && approved && !locked && planFailure == nil }
    private var planFailureSummary: String? {
        guard let error = planFailure else { return nil }
        switch error as? ModelEvaluationError {
        case .invalidCases: return L("원문과 승인 정답 1~5쌍을 확인해 주세요.", "Check 1–5 source and approved-answer pairs.")
        case .invalidModels: return L("유효한 서로 다른 모델 ID 2~3개가 필요합니다.", "Choose 2–3 distinct valid model IDs.")
        case .invalidBudget: return L("비교 예산을 확인해 주세요.", "Check the comparison budget.")
        case .unavailablePrice: return L("선택 모델 단가 미확인 · 비교 전송 불가", "Selected model pricing unknown · Comparison cannot be sent")
        case .exceedsBudget: return L("예약 비용이 비교 예산을 넘습니다.", "Reserved cost exceeds the comparison budget.")
        case .inputTooLarge: return L("원문·사전 입력량이 비교 한도를 넘습니다.", "Source and dictionary input exceed the comparison limit.")
        default: return error.localizedDescription
        }
    }
    private var comparisonHelp: String {
        L("인식 원문과 직접 확인한 정답을 1~5쌍 입력하고 같은 원문으로 문장 모델 2~3개를 비교합니다. 문장당 최대 4,000바이트입니다. 정답은 생성 모델에 보내지 않고 Jev 검토 기준으로만 사용합니다. 전체 기록·녹음·다른 앱 문맥을 수집하지 않습니다. 창을 닫으면 실행을 취소하고 문장과 결과를 지웁니다.", "Enter 1–5 source and approved-answer pairs, up to 4,000 bytes each, and compare 2–3 text models on the same sources. Approved answers are used only as Jev references, not sent to generation models. History, audio and surrounding app context are not collected. Closing cancels execution and clears text and results.")
    }
    private var budgetHelp: String {
        L("현재 참고 단가와 최대 출력 16,384토큰으로 보수적으로 예약합니다. 공급자 최종 청구의 보장 상한은 아닙니다. 비용 미확인·요청 실패·60초 초과 시 남은 비교를 중단합니다. 이미 처리한 요청은 과금될 수 있습니다.", "Reserves conservatively using current reference rates and up to 16,384 output tokens. This is not a guaranteed ceiling on provider billing. Unknown cost, request failure or the 60-second limit stops remaining comparisons. Processed requests may still be billed.")
    }
    private var modelSelectionHelp: String {
        L("각 행에서 목록의 모델 또는 마지막 직접 입력(Custom)을 선택합니다. 직접 입력은 ‘적용’이나 Return으로 확정한 ID만 비교하며, 적용 전에는 기존 ID를 유지합니다. 서로 다른 모델 2~3개가 필요합니다. 일반 문장 처리에서 사용 가능한 직접 입력 ID라도 비교 단가를 계산할 수 없으면 전송하지 않습니다. 모델·사례·예산은 기존 비교 계획 검증을 함께 통과해야 합니다.", "Choose a catalog model or the final Custom option in each row. Only an ID committed with Apply or Return is compared; the current ID stays in use before that. Select 2–3 distinct models. A custom ID usable for normal text processing is not sent for comparison if its pricing cannot be calculated. Models, examples, and budget must pass the existing comparison-plan checks.")
    }
    private var resultHelp: String {
        L("통과 건수는 승인한 사례의 의미·고정 표기 검사 결과이며 정확도 백분율이 아닙니다. 추천은 모든 사례를 통과한 모델 중 보고·추정 비용, 생성 시간 순입니다. 설정은 ‘이 문장 모델 적용’을 눌러야 바뀝니다. 생성 시간은 문장 생성 단계만 포함하며 별도 Jev 검토 시간은 제외합니다.", "Passed cases reflect meaning and literal checks against approved examples, not an accuracy percentage. Recommendations prefer models passing every case, then known reported/estimated cost and generation time. Settings change only when you press Apply this text model. Generation time excludes separate Jev review time.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppPageHeader(L("문장 모델 비교", "Text model comparison"), help: comparisonHelp)
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker(L("비교 단계", "Comparison stage"), selection: $showsResults) {
                Text(L("준비", "Setup")).tag(false)
                Text(L("결과", "Results")).tag(true)
            }.pickerStyle(.segmented).frame(width: 200)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsResults { resultsSection }
                    else { casesSection; modelsSection; approvalSection }
                    if let status = comparison.status { Text(status).font(AppTypography.body).textSelection(.enabled) }
                    if locked {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(model.jevModelComparisonPreparing ? L("저장된 문장·Jev 연결 준비 중", "Preparing saved text and Jev connections") : L("승인 사례 비교 중", "Comparing approved examples")).font(AppTypography.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("비교 취소", "Cancel comparison")) { model.cancelJevModelComparison() }
                        }
                    }
                }.padding(.trailing, 4)
            }
        }
        .padding(24).frame(minWidth: 640, idealWidth: 760, minHeight: 500, idealHeight: 640)
        .background(AppTheme.pageBackground).buttonStyle(AppActionButtonStyle())
        .onAppear {
            let selected = JevModelComparisonModelBindings.fillingRequiredRows(
                in: comparison.selectedModels, choices: catalog.map(\.id))
            if selected != comparison.selectedModels { comparison.selectedModels = selected }
            syncModelRows()
            if comparison.cases.isEmpty { comparison.cases = [.init(transcript: "오픈 라우터 제이 이 브이 설정을 확인해 주세요", approvedText: "OpenRouter JEV 설정을 확인해 주세요.")] }
            expandedCaseID = comparison.cases.first?.id
        }
        .onChange(of: comparison.cases) { _, _ in approved = false; confirmsRun = false }
        .onChange(of: comparison.selectedModels) { _, _ in confirmsRun = false; syncModelRows() }
        .onChange(of: comparison.budgetUSD) { _, _ in confirmsRun = false }
        .onChange(of: model.preferences.effectiveTextProvider) { _, _ in
            comparison.selectedModels = initialModelSelection
            modelRowIDs = [UUID(), UUID()]
            confirmsRun = false
        }
        .onChange(of: model.preferences.decisionProvider) { _, _ in confirmsRun = false }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in if required { confirmsRun = false } }
        .onChange(of: model.jevModelComparisonPreparing) { _, preparing in if preparing { showsResults = true } }
        .onChange(of: comparison.isRunning) { _, running in if running { showsResults = true } }
        .onDisappear {
            if locked { model.cancelJevModelComparison() }
            comparison.clearSensitiveData()
        }
        .confirmationDialog(L("선택한 서비스로 평가 사례를 전송할까요?", "Send the examples to the selected services?"), isPresented: $confirmsRun, titleVisibility: .visible) {
            Button(L("전송하고 비교", "Send and compare")) { guard canRun else { return }; model.runJevModelComparison() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("\(model.preferences.effectiveTextProvider.displayName)에 각 인식 원문과 사전 힌트를 보내 생성하고, \(model.preferences.decisionProvider.displayName)에 승인 정답과 각 생성 결과를 보내 검토합니다. 최대 30요청·60초이며 추가 API 비용이 발생합니다. 녹음·다른 앱 문맥·전체 기록은 보내지 않습니다.", "Sends each source transcript and dictionary hints to \(model.preferences.effectiveTextProvider.displayName) for generation, then each approved answer and output to \(model.preferences.decisionProvider.displayName) for review. Up to 30 requests and 60 seconds, with additional API charges. Audio, surrounding app context and your history are not sent."))
        }
    }

    private var casesSection: some View {
        @Bindable var comparison = model.jevModelComparison
        return Surface {
            HStack { Text(L("평가 사례", "Evaluation examples")).font(AppTypography.sectionTitle); OptionHelp(title: L("평가 사례", "Evaluation examples"), message: comparisonHelp); Spacer(); Text("\(comparison.cases.count)/5").font(AppTypography.caption).foregroundStyle(.secondary) }
            ForEach(Array(comparison.cases.enumerated()), id: \.element.id) { index, item in
                DisclosureGroup(isExpanded: Binding(get: { expandedCaseID == item.id }, set: { expandedCaseID = $0 ? item.id : nil })) {
                    HStack(alignment: .top, spacing: 16) {
                        caseEditor(L("인식 원문", "Source transcript"), text: JevModelComparisonCaseBindings.text(in: $comparison.cases, id: item.id, field: \.transcript, isEditable: { editable && !locked }))
                        caseEditor(L("내가 승인한 정답", "My approved answer"), text: JevModelComparisonCaseBindings.text(in: $comparison.cases, id: item.id, field: \.approvedText, isEditable: { editable && !locked }))
                    }.padding(.top, 8).disabled(locked || !editable)
                    HStack { Spacer(); Button(L("이 사례 삭제", "Remove example"), role: .destructive) { guard editable, !locked else { return }; comparison.cases.removeAll { $0.id == item.id } }.disabled(locked || !editable) }
                } label: {
                    Text(L("사례 \(index + 1)", "Example \(index + 1)")).font(AppTypography.body.weight(.medium)).frame(minHeight: 32)
                }
            }
            HStack(spacing: 12) {
                Button(L("빈 사례 추가", "Add blank example"), systemImage: "plus") { addCase(synthetic: false) }
                Button(L("합성 사례 추가", "Add synthetic example")) { addCase(synthetic: true) }
            }.disabled(locked || !editable || comparison.cases.count >= 5)
        }
    }
    private var modelsSection: some View {
        @Bindable var comparison = model.jevModelComparison
        return Surface {
            HStack { Text(L("비교 모델", "Models to compare")).font(AppTypography.sectionTitle); Spacer(); Text(model.preferences.effectiveTextProvider.displayName).font(AppTypography.caption).foregroundStyle(.secondary) }
            if catalog.count < 2 {
                Text(L("현재 제공자의 목록에 모델이 부족합니다. 직접 입력한 ID도 단가가 확인되어야 비교할 수 있습니다.", "This provider has too few catalog models. A manually entered ID also needs known pricing for comparison.")).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            VStack(spacing: 0) {
                ForEach(Array(modelRowIDs.enumerated()), id: \.element) { index, rowID in
                    ProviderModelPicker(L("모델 \(index + 1)", "Model \(index + 1)"),
                        selection: JevModelComparisonModelBindings.text(in: $comparison.selectedModels, at: index,
                            contextID: modelContext(rowID), currentContextID: { currentModelContext(at: index) },
                            isEditable: { editable && !locked }),
                        choices: ProviderModelChoice.textChoices(for: model.preferences.effectiveTextProvider),
                        isEnabled: editable && !locked, contextID: modelContext(rowID))
                    if index < modelRowIDs.count - 1 { Divider() }
                }
            }
            HStack {
                if comparison.selectedModels.count < 3 {
                    Button(L("모델 추가", "Add model"), systemImage: "plus") { addComparisonModel() }
                        .disabled(!editable || locked || comparison.selectedModels.count != 2)
                } else {
                    Button(L("모델 3 제외", "Remove model 3"), systemImage: "minus") { removeLastComparisonModel() }
                        .disabled(!editable || locked || comparison.selectedModels.count != 3)
                }
                Spacer()
                OptionHelp(title: L("직접 입력과 비교 조건", "Custom models and comparison requirements"), message: modelSelectionHelp)
            }
            HStack {
                if !priceVerificationDates.isEmpty {
                    Text(L("100만 토큰당 입력 / 출력 · \(priceVerificationDates)", "Input / output per 1M tokens · \(priceVerificationDates)")).font(AppTypography.caption).foregroundStyle(.secondary)
                }
                OptionHelp(title: L("참고 단가와 비교 예산", "Reference rates and budget"), message: budgetHelp)
            }
            SettingsRow(L("최대 비교 예산", "Comparison budget"), help: budgetHelp) {
                Picker(L("최대 비교 예산", "Comparison budget"), selection: $comparison.budgetUSD) {
                    ForEach([0.01, 0.05, 0.10, 0.20], id: \.self) { Text(String(format: "US$%.2f", $0)).tag($0) }
                }.disabled(locked || !editable)
            }
            if let estimate = comparison.estimatedReservationUSD { Text(L("보수적 예약액: US$\(String(format: "%.4f", estimate))", "Conservative reservation: US$\(String(format: "%.4f", estimate))")).font(AppTypography.caption).monospacedDigit() }
            Text(L("추가 API 비용 · 최종 청구의 보장 상한 아님", "Additional API cost · Not a guaranteed billing ceiling")).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
        }
    }
    private var approvalSection: some View {
        Surface {
            Toggle(L("정답을 확인했으며 이번 비교 기준으로 승인합니다", "I checked and approve these reference answers"), isOn: $approved).toggleStyle(.checkbox).font(AppTypography.body).disabled(locked || !editable)
            if !locked, let summary = planFailureSummary, let error = planFailure {
                HStack(alignment: .top, spacing: 8) {
                    Text(summary).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    OptionHelp(title: L("비교를 시작할 수 없는 이유", "Why comparison cannot start"), message: error.localizedDescription + "\n\n" + modelSelectionHelp + "\n\n" + budgetHelp)
                }
            }
            HStack {
                Button(L("비교 시작…", "Start comparison…")) { guard canRun else { return }; confirmsRun = true }
                    .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!canRun)
                Spacer()
                Text(L("사례 수정 시 재승인", "Changes require approval again")).font(AppTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var resultsSection: some View {
        if comparison.rows.isEmpty {
            Surface {
                Text(locked ? L("승인한 비교를 준비하고 있습니다", "Preparing the approved comparison") : L("아직 비교 결과가 없습니다", "No comparison results yet")).font(AppTypography.sectionTitle)
                if !locked { Button(L("비교 설정 보기", "View comparison setup")) { showsResults = false } }
            }
        } else {
            Surface {
                HStack { Text(L("비교 결과", "Comparison results")).font(AppTypography.sectionTitle); OptionHelp(title: L("비교 결과와 추천", "Results and recommendation"), message: resultHelp); Spacer() }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow { Text(L("모델", "Model")); Text(L("검토", "Reviewed")); Text(L("통과", "Passed")); Text(L("생성", "Generation")); Text(L("비용", "Cost")) }.font(AppTypography.caption).foregroundStyle(.secondary)
                    ForEach(comparison.rows) { row in
                        GridRow { Text(row.model).textSelection(.enabled); Text("\(row.completedCount)/\(row.expectedCount)"); Text("\(row.passedCount)"); Text(UsageFormat.reviewLatency(row.meanSeconds)); Text(UsageFormat.usd(row.totalCostUSD)) }.font(AppTypography.body).monospacedDigit().frame(minHeight: 32)
                    }
                }
                ForEach(comparison.rows) { row in
                    DisclosureGroup(row.model) { resultRow(row).padding(.top, 8) }.font(AppTypography.body)
                }
            }
            if let recommendation = comparison.recommendedModel {
                Surface {
                    Text(L("이 사례의 추천: \(recommendation)", "Recommended for these examples: \(recommendation)")).font(AppTypography.body.weight(.medium)).textSelection(.enabled)
                    Button(L("이 문장 모델 적용", "Apply this text model")) {
                        guard editable, !locked, catalog.contains(where: { $0.id == recommendation }) else { return }
                        model.applyJevRecommendedModel(recommendation)
                    }
                        .buttonStyle(AppActionButtonStyle(primary: true))
                        .disabled(locked || !editable || !catalog.contains(where: { $0.id == recommendation }))
                    if !catalog.contains(where: { $0.id == recommendation }) {
                        Text(L("현재 제공자 목록에 없는 모델 · 이 화면에서 적용 불가", "Model is outside this provider’s catalog · Cannot apply here"))
                            .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    }
                }
            }
        }
    }
    private var initialModelSelection: [String] {
        JevModelComparisonModelBindings.fillingRequiredRows(in: [], choices: catalog.map(\.id))
    }
    private func modelContext(_ rowID: UUID) -> String {
        "comparison-\(model.preferences.effectiveTextProvider.rawValue)-\(rowID.uuidString)"
    }
    private func currentModelContext(at index: Int) -> String? {
        guard modelRowIDs.indices.contains(index) else { return nil }
        return modelContext(modelRowIDs[index])
    }
    private func syncModelRows() {
        let count = max(2, min(3, comparison.selectedModels.count))
        if modelRowIDs.count > count { modelRowIDs = Array(modelRowIDs.prefix(count)) }
        while modelRowIDs.count < count { modelRowIDs.append(UUID()) }
    }
    private func addComparisonModel() {
        guard editable, !locked, comparison.selectedModels.count == 2 else { return }
        let current = Set(comparison.selectedModels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        comparison.selectedModels.append(catalog.first(where: { !current.contains($0.id) })?.id ?? "")
        syncModelRows()
    }
    private func removeLastComparisonModel() {
        guard editable, !locked, comparison.selectedModels.count == 3 else { return }
        comparison.selectedModels.removeLast()
        syncModelRows()
    }
    private func addCase(synthetic: Bool) {
        guard editable, !locked, comparison.cases.count < 5 else { return }
        let item = ModelEvaluationCase(transcript: synthetic ? "오픈 라우터 제이 이 브이 설정을 확인해 주세요" : "", approvedText: synthetic ? "OpenRouter JEV 설정을 확인해 주세요." : "")
        comparison.cases.append(item); expandedCaseID = item.id
    }
    private func caseEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppTypography.caption).foregroundStyle(.secondary)
            TextEditor(text: text).font(AppTypography.body).frame(minHeight: 88, maxHeight: 120).accessibilityLabel(title)
        }.frame(maxWidth: .infinity)
    }
    private func resultRow(_ row: ModelEvaluationRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(row.outputs) { output in
                if let text = output.text { Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled) }
                if let issue = output.issue { Text(issue).font(AppTypography.caption).foregroundStyle(AppTheme.warm).textSelection(.enabled) }
            }
            ForEach(Array(row.errors.enumerated()), id: \.offset) { _, error in Text(error).font(AppTypography.caption).foregroundStyle(AppTheme.warm).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
