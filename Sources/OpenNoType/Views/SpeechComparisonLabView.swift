import SwiftUI
import OpenNoTypeCore

struct SpeechComparisonLabView: View {
    @Bindable var lab: SpeechComparisonLab
    let preferences: Preferences
    let appBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("내 음성으로 모델 비교", "Compare models with your voice"))
                .font(.system(size: 23, weight: .semibold)).tracking(-0.6)
            Text(L("이 Mac에 내려받은 모델을 같은 음성으로 차례대로 비교합니다. API 요청과 새 모델 다운로드는 없으며, 비교 내용은 기록에 저장하지 않습니다.", "Compare already-downloaded models in sequence using the same audio. No API requests or new downloads are made, and comparison content is not saved to history."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            referenceSection
            audioSection
            modelsSection
            if !lab.status.isEmpty {
                HStack(spacing: 8) {
                    if lab.isBusy && !lab.isRecording { ProgressView().controlSize(.small) }
                    Text(lab.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if lab.isBusy { Button(L("취소", "Cancel")) { lab.cancel() } }
                }
            }
            if let warning = lab.warning { Text(warning).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = lab.error { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
            resultsSection
        }
        .task { await lab.refreshAvailableModels() }
        .onDisappear { lab.close() }
    }

    private var referenceSection: some View {
        Surface(L("정답 문장", "Reference text")) {
            Text(L("실제로 말할 문장을 적어 주세요. 한국어·영어·숫자·자주 쓰는 이름을 섞으면 내 작업에 맞는 차이를 확인하기 쉽습니다.", "Write what you will actually say. Include Korean, English, numbers, and names you use to compare the models on your own work."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $lab.expectedText)
                .font(.system(size: 13)).frame(minHeight: 80, maxHeight: 160)
                .accessibilityLabel(L("비교용 정답 문장", "Comparison reference text"))
                .disabled(lab.isBusy)
            Text(L("CER은 공백 제거와 Unicode 정규화 후 편집 거리 ÷ 정답 길이입니다. 대소문자와 문장부호를 포함하며, 정답이 비어 있으면 계산하지 않습니다.", "CER is Unicode-scalar edit distance divided by reference length after whitespace removal and canonical normalization. Case and punctuation are included. It is unavailable for an empty reference."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var audioSection: some View {
        Surface(L("비교할 음성 · 최대 60초", "Comparison audio · Up to 60 seconds")) {
            HStack(spacing: 10) {
                if lab.isRecording {
                    ProgressView(value: lab.level).frame(width: 90)
                    Text(String(format: "%.1f s", lab.elapsed)).monospacedDigit().font(.system(size: 12))
                    Button(L("녹음 종료", "Stop recording"), systemImage: "stop.fill") { lab.stopRecording() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Picker(L("녹음 길이", "Recording length"), selection: $lab.recordingDuration) {
                        Text(L("15초", "15 seconds")).tag(15.0)
                        Text(L("30초", "30 seconds")).tag(30.0)
                        Text(L("60초", "60 seconds")).tag(60.0)
                    }.frame(maxWidth: 190).disabled(lab.isBusy || appBusy)
                    Button(L("비교용 녹음", "Record sample"), systemImage: "mic.fill") {
                        lab.startRecording(preferences: preferences)
                    }.disabled(lab.isBusy || appBusy)
                    Button(L("음성 파일 선택…", "Choose audio file…"), systemImage: "folder") { lab.importAudio() }
                        .disabled(lab.isBusy || appBusy)
                }
                Spacer()
                Button(L("비교 내용 지우기", "Clear comparison"), role: .destructive) { lab.clear() }
                    .disabled(!lab.hasSample && lab.results.isEmpty && !lab.isBusy && !lab.audioCleanupRequired)
            }
            if let name = lab.sampleName {
                Label("\(name) · \(String(format: "%.1f", lab.sampleDuration)) s", systemImage: "waveform")
                    .font(.system(size: 12)).textSelection(.enabled)
            }
            Text(L("녹음 원음 파일은 녹음 종료 후 삭제하고, 비교를 반복할 음성은 이 화면이 열려 있는 동안만 메모리에 둡니다. 취소·지우기·화면 닫기로 음성 메모리를 비웁니다.", "Recording files are deleted after capture. Audio remains in memory for repeated comparisons while this screen is open. Cancel, Clear, or leaving this screen clears that audio."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if appBusy { Text(L("일반 음성 입력이 끝난 뒤 비교를 시작해 주세요.", "Wait for normal voice input to finish before starting a comparison."))
                .font(.system(size: 12)).foregroundStyle(.orange) }
        }
    }

    private var modelsSection: some View {
        Surface(L("비교 모델", "Models to compare")) {
            ForEach(lab.availableModels) { item in
                Toggle(isOn: selection(item.model)) {
                    HStack {
                        Text(item.model.displayName)
                        Spacer()
                        Text(item.isDownloaded ? L("기기에 있음", "Downloaded") : L("준비 필요", "Not downloaded"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.disabled(!item.isDownloaded || lab.isBusy || appBusy)
            }
            HStack {
                Button(L("다운로드 상태 새로고침", "Refresh downloaded models")) {
                    Task { await lab.refreshAvailableModels() }
                }.disabled(lab.isBusy || appBusy)
                Spacer()
                Button(L("같은 음성으로 비교", "Compare the same audio"), systemImage: "play.fill") { lab.runComparison() }
                    .buttonStyle(.borderedProminent).disabled(!lab.canCompare || appBusy)
            }
            Text(L("모델 준비 시간과 음성 인식 시간을 따로 표시합니다. 이 개인 샘플의 결과가 실제 사용 전체의 정확도를 보장하지는 않습니다. CER과 수동 검토를 함께 확인하세요.", "Model preparation and transcription times are shown separately. Results on this personal sample do not guarantee accuracy across real-world use. Review CER and manual findings together."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var resultsSection: some View {
        if !lab.results.isEmpty {
            if let reference = lab.comparedExpectedText, reference != lab.expectedText {
                Text(L("아래 CER은 비교를 시작할 때 입력한 정답 문장 기준입니다. 변경한 문장으로 점수를 보려면 다시 비교하세요.", "CER below uses the reference captured when comparison started. Compare again to score the edited reference."))
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            ForEach($lab.results) { $result in
                SpeechComparisonResultView(result: $result, reference: lab.comparedExpectedText ?? "")
            }
        }
    }

    private func selection(_ model: LocalSpeechModel) -> Binding<Bool> {
        Binding(get: { lab.selectedModels.contains(model) }, set: { selected in
            if selected { lab.selectedModels.insert(model) } else { lab.selectedModels.remove(model) }
        })
    }
}

private struct SpeechComparisonResultView: View {
    @Binding var result: SpeechComparisonResult
    let reference: String

    var body: some View {
        Surface(result.model.displayName) {
            HStack(spacing: 24) {
                metric(L("모델 준비", "Preparation"), milliseconds: result.preparationMilliseconds)
                metric(L("음성 인식", "Transcription"), milliseconds: result.transcriptionMilliseconds)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CER").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(result.score?.characterErrorRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                }
                Spacer()
            }
            if let error = result.error { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
            if !result.transcript.isEmpty {
                Text(result.transcript).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                Text(L("정답의 숫자: \(numbers(reference))", "Reference numbers: \(numbers(reference))"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(L("인식한 숫자: \(numbers(result.transcript))", "Recognized numbers: \(numbers(result.transcript))"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Toggle(L("수동 검토 완료", "Manually reviewed"), isOn: $result.manuallyReviewed)
                HStack(spacing: 18) {
                    Stepper(L("숫자 오류 \(result.numberErrors)", "Number errors \(result.numberErrors)"), value: $result.numberErrors, in: 0...99)
                    Stepper(L("이름·용어 오류 \(result.termErrors)", "Name and term errors \(result.termErrors)"), value: $result.termErrors, in: 0...99)
                    Stepper(L("의미 오류 \(result.meaningErrors)", "Meaning errors \(result.meaningErrors)"), value: $result.meaningErrors, in: 0...99)
                }.font(.system(size: 11))
            }
        }
    }

    private func metric(_ title: String, milliseconds: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(milliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                .font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }
    }

    private func numbers(_ text: String) -> String {
        let fragments = SpeechComparisonScoring.numericFragments(in: text)
        return fragments.isEmpty ? L("없음", "None") : fragments.joined(separator: " · ")
    }
}
