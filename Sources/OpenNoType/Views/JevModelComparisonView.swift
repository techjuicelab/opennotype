import SwiftUI
import OpenNoTypeCore

/// This sheet asks for approved examples explicitly; it never imports or scans history.
struct JevModelComparisonView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var approved = false
    @State private var confirmsRun = false

    private var catalog: [TextModelCatalogEntry] { TextModelCatalog.entries(for: model.preferences.effectiveTextProvider) }

    var body: some View {
        @Bindable var comparison = model.jevModelComparison
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("내 사례로 문장 모델 비교", "Compare text models on my examples")).font(.title2.weight(.semibold))
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("인식 원문과 직접 확인한 정답을 1~5쌍 입력하세요. 같은 원문으로 모델 2~3개를 평가합니다. 정답은 생성 모델에 보여 주지 않고 Jev 검토의 기준으로만 사용합니다.", "Enter 1–5 source and approved-answer pairs. Evaluate 2–3 models on the same sources. Approved answers are used only as Jev review references and are never shown to the generation model."))
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach($comparison.cases) { $item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(L("평가 사례", "Evaluation example")).font(.headline)
                                Spacer()
                                Button(L("삭제", "Remove"), role: .destructive) { comparison.cases.removeAll { $0.id == item.id } }
                            }
                            HStack(alignment: .top, spacing: 12) {
                                caseEditor(L("인식 원문", "Source transcript"), text: $item.transcript)
                                caseEditor(L("내가 승인한 정답", "My approved answer"), text: $item.approvedText)
                            }
                        }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(comparison.isRunning || model.jevModelComparisonPreparing)
                    HStack {
                        Button(L("빈 사례 추가", "Add blank example"), systemImage: "plus") {
                            comparison.cases.append(.init(transcript: "", approvedText: ""))
                        }
                        Button(L("합성 예시 추가", "Add synthetic example")) {
                            comparison.cases.append(.init(transcript: "오픈 라우터 제이 이 브이 설정을 확인해 주세요",
                                approvedText: "OpenRouter JEV 설정을 확인해 주세요."))
                        }
                    }.disabled(comparison.isRunning || model.jevModelComparisonPreparing || comparison.cases.count >= 5)
                    Divider()
                    Text(L("비교할 문장 모델 · \(model.preferences.effectiveTextProvider.displayName)", "Text models to compare · \(model.preferences.effectiveTextProvider.displayName)")).font(.headline)
                    if catalog.count < 2 {
                        Text(L("이 제공자에는 가격이 확인된 비교 모델이 부족합니다. AI 연결에서 OpenRouter 또는 Groq 문장 제공자를 선택해 주세요.", "This provider has too few comparison models with known prices. Select OpenRouter or Groq as the text provider in AI connections."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(catalog) { entry in
                        Toggle(isOn: Binding(get: { comparison.selectedModels.contains(entry.id) }, set: { selected in
                            if selected { comparison.selectedModels.append(entry.id) }
                            else { comparison.selectedModels.removeAll { $0 == entry.id } }
                        })) {
                            HStack {
                                Text(entry.title)
                                Spacer()
                                Text("$\(rate(entry.price.inputUSDPerMillion)) / $\(rate(entry.price.outputUSDPerMillion))")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox)
                            .disabled(comparison.isRunning || model.jevModelComparisonPreparing || (!comparison.selectedModels.contains(entry.id) && comparison.selectedModels.count >= 3))
                    }
                    Text(L("입력 / 출력 100만 토큰당 참고 단가 · \(TextModelCatalog.checkedAt)", "Reference input / output price per 1M tokens · \(TextModelCatalog.checkedAt)"))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(L("최대 비교 예산", "Comparison budget"), selection: $comparison.budgetUSD) {
                        ForEach([0.01, 0.05, 0.10, 0.20], id: \.self) { Text(String(format: "US$%.2f", $0)).tag($0) }
                    }.frame(maxWidth: 300).disabled(comparison.isRunning || model.jevModelComparisonPreparing)
                    Text(L("현재 단가와 최대 출력 16,384토큰으로 보수적으로 예약합니다. 공급자 최종 청구의 보장 상한은 아닙니다. 비용 미확인·요청 실패·60초 초과 시 남은 비교를 중단합니다.", "Reserves conservatively using current reference rates and up to 16,384 output tokens. This is not a guaranteed ceiling on provider billing. Unknown cost, request failure or a 60-second limit stops remaining comparisons."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let estimate = comparison.estimatedReservationUSD {
                        Text(L("보수적 예상 상한: US$\(String(format: "%.4f", estimate))", "Conservative estimated ceiling: US$\(String(format: "%.4f", estimate))"))
                            .font(.callout).monospacedDigit()
                    }
                    Toggle(L("위 정답들을 확인했으며 이번 비교 기준으로 승인합니다", "I have checked and approve these answers as this comparison's references"), isOn: $approved)
                        .toggleStyle(.checkbox).disabled(comparison.isRunning || model.jevModelComparisonPreparing)
                    HStack {
                        Button(L("승인 사례로 비교…", "Compare approved examples…")) { confirmsRun = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!approved || comparison.isRunning || model.jevModelComparisonPreparing || !(1...5).contains(comparison.cases.count)
                                || !(2...3).contains(comparison.selectedModels.count))
                        if comparison.isRunning || model.jevModelComparisonPreparing {
                            ProgressView().controlSize(.small)
                            Button(L("비교 취소", "Cancel comparison")) { model.cancelJevModelComparison() }
                        }
                    }
                    if let status = comparison.status { Text(status).font(.callout).textSelection(.enabled) }
                    if model.jevModelComparisonPreparing {
                        Text(L("저장된 문장·Jev 연결을 준비하고 있어요…", "Preparing the saved text and Jev connections…"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(comparison.rows) { row in resultRow(row) }
                    if let recommendation = comparison.recommendedModel {
                        Text(L("이 사례의 추천: \(recommendation)", "Recommended for these examples: \(recommendation)")).font(.headline)
                        Button(L("이 문장 모델로 변경", "Use this text model")) { model.applyJevRecommendedModel(recommendation) }
                            .disabled(comparison.isRunning || model.jevModelComparisonPreparing)
                    }
                    Text(L("통과 건수는 승인한 사례의 의미·고정 표기 검사 결과이며 정확도 백분율이 아닙니다. 추천은 모든 사례를 통과한 모델 중 보고·추정 비용, 생성 시간 순입니다. 설정은 변경 버튼을 눌러야 바뀝니다. 문장과 결과는 이 창을 닫으면 지워집니다.", "Passed cases reflect meaning and literal checks against your approved examples, not an accuracy percentage. Recommendations prefer models passing every case, then known reported/estimated cost and generation time. Settings change only when you press Use. Closing this sheet clears its text and results."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.trailing, 8)
            }
        }.padding(22).frame(minWidth: 720, idealWidth: 820, minHeight: 650, idealHeight: 780)
        .onAppear {
            if comparison.selectedModels.isEmpty { comparison.selectedModels = Array(catalog.prefix(2).map(\.id)) }
            if comparison.cases.isEmpty {
                comparison.cases = [.init(transcript: "오픈 라우터 제이 이 브이 설정을 확인해 주세요", approvedText: "OpenRouter JEV 설정을 확인해 주세요.")]
            }
        }
        .onChange(of: comparison.cases) { _, _ in approved = false; confirmsRun = false }
        .onChange(of: comparison.selectedModels) { _, _ in confirmsRun = false }
        .onChange(of: comparison.budgetUSD) { _, _ in confirmsRun = false }
        .onChange(of: model.preferences.effectiveTextProvider) { _, _ in
            comparison.selectedModels = Array(catalog.prefix(2).map(\.id)); confirmsRun = false
        }
        .onChange(of: model.preferences.decisionProvider) { _, _ in confirmsRun = false }
        .onDisappear {
            if comparison.isRunning || model.jevModelComparisonPreparing { model.cancelJevModelComparison() }
            comparison.clearSensitiveData()
        }
        .confirmationDialog(L("선택한 서비스로 평가 사례를 전송할까요?", "Send the examples to the selected services?"), isPresented: $confirmsRun, titleVisibility: .visible) {
            Button(L("전송하고 비교", "Send and compare")) {
                guard approved else { return }
                model.runJevModelComparison()
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("\(model.preferences.effectiveTextProvider.displayName)에 각 인식 원문과 사전 힌트를 보내 생성하고, \(model.preferences.decisionProvider.displayName)에 승인 정답과 각 생성 결과를 보내 검토합니다. 최대 30요청·60초이며 추가 API 비용이 발생합니다. 녹음·다른 앱 문맥·전체 기록은 보내지 않습니다.", "Sends each source transcript and dictionary hints to \(model.preferences.effectiveTextProvider.displayName) for generation, then each approved answer and output to \(model.preferences.decisionProvider.displayName) for review. Up to 30 requests and 60 seconds, with additional API charges. Audio, surrounding app context and your history are not sent."))
        }
    }

    private func caseEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).font(.body).frame(minHeight: 76, maxHeight: 110)
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity)
    }

    private func resultRow(_ row: ModelEvaluationRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.model).font(.headline).textSelection(.enabled)
            Text(L("검토 완료 \(row.completedCount)/\(row.expectedCount) · 조건 통과 \(row.passedCount) · 평균 생성 \(UsageFormat.reviewLatency(row.meanSeconds)) · 합계 \(UsageFormat.usd(row.totalCostUSD))", "Reviewed \(row.completedCount)/\(row.expectedCount) · Passed \(row.passedCount) · Mean generation \(UsageFormat.reviewLatency(row.meanSeconds)) · Total \(UsageFormat.usd(row.totalCostUSD))"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(row.outputs) { output in
                if let text = output.text { Text(text).textSelection(.enabled) }
                if let issue = output.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rate(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2...4)).locale(Locale(identifier: "en_US"))) }
}
