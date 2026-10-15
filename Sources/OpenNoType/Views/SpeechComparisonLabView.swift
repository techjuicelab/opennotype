import SwiftUI
import OpenNoTypeCore

struct SpeechComparisonLabView: View {
    @Bindable var lab: SpeechComparisonLab
    let preferences: Preferences
    let appBusy: Bool
    var isEditable = true
    var showsHeader = true
    @State private var selectedResultID: UUID?

    private var comparisonHelp: String {
        L("이 Mac에 내려받은 모델을 같은 음성으로 차례대로 비교합니다. API 요청과 새 모델 다운로드는 없으며 비교 내용은 기록에 저장하지 않습니다. 녹음 원음 파일은 종료 후 삭제하고 비교 음성은 이 화면이 열려 있는 동안만 메모리에 둡니다. 취소·지우기·화면 닫기로 음성 메모리를 비웁니다. 모델 파일 존재와 추론 준비 완료는 다른 상태입니다.", "Compares downloaded models on the same audio in sequence. No API requests or new downloads are made and comparison content is not stored in history. Recorded files are removed after capture; comparison audio stays in memory only while this screen is open. Cancel, Clear and leaving the screen clear audio memory. A downloaded model is not necessarily ready for inference.")
    }
    private var scoringHelp: String {
        L("CER은 공백 제거와 Unicode 정규화 후 Unicode scalar 편집 거리 ÷ 정답 길이입니다. 대소문자와 문장부호를 포함하며 정답이 비어 있으면 계산하지 않습니다. 모델 준비와 인식 시간을 분리합니다. 개인 샘플의 CER은 실제 사용 전체의 정확도나 의미 충실성을 보장하지 않으므로 인식문·숫자·이름·의미를 직접 검토하세요.", "CER is Unicode-scalar edit distance divided by reference length after whitespace removal and canonical normalization. Case and punctuation are included; an empty reference has no score. Preparation and inference times are separate. A personal sample's CER does not guarantee general accuracy or meaning fidelity; review the transcript, numbers, names and meaning yourself.")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            if showsHeader { AppPageHeader(L("음성 모델 비교", "Speech model comparison"), help: comparisonHelp) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { audioSection; modelsSection }
                VStack(alignment: .leading, spacing: 16) { audioSection; modelsSection }
            }
            referenceSection
            if !lab.status.isEmpty {
                HStack(spacing: 8) {
                    if lab.isBusy && !lab.isRecording { ProgressView().controlSize(.small) }
                    Text(lab.status).font(AppTypography.body).foregroundStyle(.secondary)
                    Spacer()
                    if lab.isBusy { Button(L("비교 취소", "Cancel comparison")) { lab.cancel() } }
                }
            }
            if let warning = lab.warning { Text(warning).font(AppTypography.caption).foregroundStyle(AppTheme.warm).textSelection(.enabled) }
            if let error = lab.error { Text(error).font(AppTypography.body).foregroundStyle(.red).textSelection(.enabled) }
            resultsSection
        }
        .task { await lab.refreshAvailableModels() }
        .onChange(of: lab.results.map(\.id)) { _, ids in if !ids.contains(where: { $0 == selectedResultID }) { selectedResultID = ids.first } }
        .onDisappear { lab.close() }
    }
    private var referenceSection: some View {
        Surface {
            HStack {
                Text(L("정답 문장", "Reference text")).font(AppTypography.sectionTitle)
                OptionHelp(title: L("정답 문장과 CER", "Reference text and CER"), message: L("실제로 말할 내용을 적어 주세요. 한국어·영어·숫자·자주 쓰는 이름을 섞으면 내 작업에 맞는 차이를 확인하기 쉽습니다.", "Enter what you will say. Mix Korean, English, numbers and names used in your work.") + "\n\n" + scoringHelp)
                Spacer()
            }
            TextEditor(text: $lab.expectedText).font(AppTypography.body).frame(minHeight: 88, maxHeight: 120)
                .accessibilityLabel(L("비교용 정답 문장", "Comparison reference text")).disabled(lab.isBusy || !isEditable)
        }
    }
    private var audioSection: some View {
        Surface {
            HStack {
                Text(L("비교할 음성", "Comparison audio")).font(AppTypography.sectionTitle)
                OptionHelp(title: L("비교 음성의 보관", "Comparison audio retention"), message: comparisonHelp)
                Spacer()
                Text(L("최대 60초", "Up to 60 seconds")).font(AppTypography.caption).foregroundStyle(.secondary)
            }
            if lab.isRecording {
                HStack(spacing: 12) {
                    ProgressView(value: lab.level).frame(width: 72)
                    Text(String(format: "%.1f s", lab.elapsed)).font(AppTypography.utility)
                    Button(L("녹음 종료", "Stop recording"), systemImage: "stop.fill") { lab.stopRecording() }.buttonStyle(AppActionButtonStyle(primary: true))
                }
            } else {
                HStack(spacing: 8) {
                    Picker(L("녹음 길이", "Recording length"), selection: $lab.recordingDuration) {
                        Text(L("15초", "15 seconds")).tag(15.0)
                        Text(L("30초", "30 seconds")).tag(30.0)
                        Text(L("60초", "60 seconds")).tag(60.0)
                    }.frame(maxWidth: 140).disabled(lab.isBusy || appBusy || !isEditable)
                    Button(L("비교용 녹음 시작", "Start sample recording"), systemImage: "mic.fill") { lab.startRecording(preferences: preferences) }.disabled(lab.isBusy || appBusy || !isEditable)
                }
                Button(L("음성 파일 선택…", "Choose audio file…"), systemImage: "folder") { lab.importAudio() }.disabled(lab.isBusy || appBusy || !isEditable)
            }
            if let name = lab.sampleName {
                Label("\(name) · \(String(format: "%.1f", lab.sampleDuration)) s", systemImage: "waveform").font(AppTypography.caption).textSelection(.enabled)
            } else if !lab.isBusy { Text(L("비교할 음성을 준비해 주세요", "Prepare a comparison sample")).font(AppTypography.caption).foregroundStyle(.secondary) }
            Button(L("비교 내용 지우기", "Clear comparison"), role: .destructive) { lab.clear() }
                .disabled(!lab.hasSample && lab.results.isEmpty && !lab.isBusy && !lab.audioCleanupRequired)
            if appBusy { Text(L("일반 음성 입력이 끝난 뒤 시작해 주세요.", "Wait for normal voice input to finish.")).font(AppTypography.caption).foregroundStyle(AppTheme.warm) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var modelsSection: some View {
        Surface {
            HStack {
                Text(L("비교 모델", "Models to compare")).font(AppTypography.sectionTitle)
                OptionHelp(title: L("비교 모델의 준비", "Model preparation"), message: scoringHelp + "\n\n" + L("기기에 있는 모델만 선택할 수 있습니다. 이 화면은 모델을 새로 다운로드하지 않으며 비교할 때 실제 준비 상태와 오류를 확인합니다.", "Only downloaded models can be selected. This screen does not download models; preparation and errors are checked during comparison."))
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(lab.availableModels) { item in
                    Toggle(isOn: selection(item.model)) {
                        HStack {
                            Text(item.model.displayName).font(AppTypography.body)
                            Spacer(minLength: 8)
                            Text(item.isDownloaded ? L("기기에 있음", "Downloaded") : L("준비 필요", "Not downloaded")).font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox).frame(minHeight: 44).disabled(!item.isDownloaded || lab.isBusy || appBusy || !isEditable)
                }
            }
            HStack(spacing: 8) {
                Button(L("모델 목록 새로고침", "Refresh models")) { Task { await lab.refreshAvailableModels() } }.disabled(lab.isBusy || appBusy || !isEditable)
                Spacer(minLength: 8)
                Button(L("비교 시작", "Start comparison"), systemImage: "play.fill") { lab.runComparison() }
                    .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!lab.canCompare || appBusy || !isEditable)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private var resultsSection: some View {
        if !lab.results.isEmpty {
            if let reference = lab.comparedExpectedText, reference != lab.expectedText {
                Text(L("비교 시작 당시 정답 기준입니다. 변경한 정답으로 보려면 다시 비교하세요.", "Scores use the reference captured at comparison start. Compare again for the edited reference."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            Surface {
                HStack { Text(L("비교 결과", "Comparison results")).font(AppTypography.sectionTitle); OptionHelp(title: L("비교 결과 읽기", "Reading comparison results"), message: scoringHelp); Spacer() }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    GridRow { Text(L("모델", "Model")); Text(L("준비", "Preparation")); Text(L("인식", "Inference")); Text("CER") }.font(AppTypography.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                    ForEach(lab.results) { item in
                        GridRow {
                            Button { selectedResultID = item.id } label: {
                                HStack(spacing: 6) { if item.id == (selectedResultID ?? lab.results.first?.id) { Image(systemName: "checkmark") }; Text(item.model.displayName) }
                            }.buttonStyle(.borderless).accessibilityAddTraits(item.id == (selectedResultID ?? lab.results.first?.id) ? .isSelected : [])
                            Text(milliseconds(item.preparationMilliseconds))
                            Text(milliseconds(item.transcriptionMilliseconds))
                            Text(item.score?.characterErrorRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                        }.font(AppTypography.body).monospacedDigit().frame(minHeight: 44)
                    }
                }
            }
            if let selected = lab.results.first(where: { $0.id == selectedResultID }) ?? lab.results.first {
                SpeechComparisonResultView(result: resultBinding(selected), reference: lab.comparedExpectedText ?? "", isEditable: isEditable).id(selected.id)
            }
        }
    }
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "—" }
    private func selection(_ model: LocalSpeechModel) -> Binding<Bool> {
        Binding(get: { lab.selectedModels.contains(model) }, set: { selected in
            guard isEditable, !lab.isBusy, !appBusy else { return }
            if selected { lab.selectedModels.insert(model) } else { lab.selectedModels.remove(model) }
        })
    }
    private func resultBinding(_ snapshot: SpeechComparisonResult) -> Binding<SpeechComparisonResult> {
        Binding(get: { lab.results.first { $0.id == snapshot.id } ?? snapshot }, set: { value in
            guard let index = lab.results.firstIndex(where: { $0.id == snapshot.id }) else { return }
            lab.results[index] = value
        })
    }
}

private struct SpeechComparisonResultView: View {
    @Binding var result: SpeechComparisonResult
    let reference: String
    var isEditable = true

    var body: some View {
        Surface(result.model.displayName) {
            if let error = result.error { Text(error).font(AppTypography.body).foregroundStyle(.red).textSelection(.enabled) }
            if !result.transcript.isEmpty {
                Text(result.transcript).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                DisclosureGroup(L("숫자 표기 비교", "Compare number fragments")) {
                    Text(L("정답의 숫자: \(numbers(reference))", "Reference numbers: \(numbers(reference))")).textSelection(.enabled)
                    Text(L("인식한 숫자: \(numbers(result.transcript))", "Recognized numbers: \(numbers(result.transcript))")).textSelection(.enabled)
                }.font(AppTypography.caption)
                Toggle(L("수동 검토 완료", "Manually reviewed"), isOn: $result.manuallyReviewed).font(AppTypography.body).disabled(!isEditable)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { errorControls }
                    VStack(alignment: .leading, spacing: 8) { errorControls }
                }.font(AppTypography.caption).disabled(!isEditable)
            }
        }
    }
    @ViewBuilder private var errorControls: some View {
        Stepper(L("숫자 오류 \(result.numberErrors)", "Number errors \(result.numberErrors)"), value: $result.numberErrors, in: 0...99)
        Stepper(L("이름·용어 오류 \(result.termErrors)", "Term errors \(result.termErrors)"), value: $result.termErrors, in: 0...99)
        Stepper(L("의미 오류 \(result.meaningErrors)", "Meaning errors \(result.meaningErrors)"), value: $result.meaningErrors, in: 0...99)
    }
    private func numbers(_ text: String) -> String {
        let fragments = SpeechComparisonScoring.numericFragments(in: text)
        return fragments.isEmpty ? L("없음", "None") : fragments.joined(separator: " · ")
    }
}
