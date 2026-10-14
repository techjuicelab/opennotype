import SwiftUI
import OpenNoTypeCore

struct VoiceInputOptionsView: View {
    @Bindable var model: AppModel
    private var controlsEnabled: Bool {
        !model.isBusy && !model.preferencesRecoveryRequired && !AppLaunch.isPreview
    }
    private var selectedMicrophoneDisconnected: Bool {
        guard let uid = model.preferences.inputDeviceUID else { return false }
        return !model.inputDevices.contains(where: { $0.uid == uid })
    }

    var body: some View {
        Surface(L("녹음과 받아쓰기", "Recording and dictation")) {
            HStack {
                OptionHelpLabel(L("받아쓰기 처리", "Dictation processing"), help: L("정리해서 입력은 인식한 문장을 AI로 정리합니다. 빠른 로컬 받아쓰기는 말한 언어를 유지할 때만 적용하며, 이 Mac에서 인식한 원문을 AI 정리·자동 Jev 검토 없이 입력합니다. API 키는 필요 없지만 로컬 모델을 먼저 준비해야 합니다. 번역·문장 수정·프롬프트 만들기는 별도의 AI 처리를 사용합니다.", "Clean up before typing uses AI to clean up the transcript. Quick on-device dictation applies only when keeping the spoken language and types the on-device transcript without AI cleanup or automatic Jev review. No API key is required, but a local model must be prepared first. Translation, selected-text edits and prompt creation use their separate AI processing."))
                Spacer()
                Picker(L("받아쓰기 처리", "Dictation processing"), selection: $model.preferences.dictationProcessing) {
                    ForEach(DictationProcessingMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .disabled(!controlsEnabled)
            }
            if model.preferences.dictationProcessing == .onDeviceVerbatim && model.preferences.dictationOutputLanguage.isTranslation {
                Label(L("번역 출력 중 · 빠른 로컬 설정은 현재 미적용", "Translation output · Quick on-device setting is paused"), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if model.preferences.usesFastDictation && model.localState != .ready {
                HStack {
                    Label(L("로컬 모델 · \(model.localState.label)", "Local model · \(model.localState.label)"), systemImage: "desktopcomputer")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("모델 준비 상태 보기", "View model setup")) { model.page = .voice }
                        .controlSize(.small)
                        .disabled(!controlsEnabled)
                }
            }
            HStack {
                OptionHelpLabel(L("단축키 동작", "Shortcut activation"), help: L("한 번 눌러 시작·다시 눌러 종료는 다음 누름까지 녹음합니다. 누르는 동안 녹음은 키를 떼면 종료합니다. 혼합 모드에서는 짧게 누르면 다음 누름까지 녹음하고, 길게 누르면 키를 떼는 순간 종료합니다.", "Press to start and stop records until the next press. Hold to record ends when you release the key. Hold or toggle records until the next press after a tap, or stops on release after a hold."))
                Spacer()
                Picker(L("단축키 동작", "Shortcut activation"), selection: $model.preferences.shortcutActivation) {
                    ForEach(ShortcutActivationMode.allCases) { Text(activationTitle($0)).tag($0) }
                }
                .labelsHidden()
                .disabled(!controlsEnabled)
            }
            HStack {
                OptionHelpLabel(L("녹음 마이크", "Recording microphone"), help: L("시스템 기본 마이크 또는 녹음에 사용할 특정 마이크를 선택합니다. 목록에 없는 지정 마이크는 연결 끊김으로 표시합니다. 장치를 연결한 뒤 목록을 새로고침할 수 있습니다.", "Choose the system default microphone or a specific microphone for recording. A selected microphone missing from the list is shown as disconnected. Refresh the list after connecting a device."))
                Spacer()
                Picker(L("녹음 마이크", "Recording microphone"), selection: Binding(
                    get: { model.preferences.inputDeviceUID ?? "" },
                    set: { model.preferences.inputDeviceUID = $0.isEmpty ? nil : $0 })) {
                    Text(L("시스템 기본 마이크", "System default microphone")).tag("")
                    ForEach(model.inputDevices) { Text($0.name).tag($0.uid) }
                    if let uid = model.preferences.inputDeviceUID, selectedMicrophoneDisconnected {
                        Text(L("선택한 마이크 연결 끊김", "Selected microphone disconnected")).tag(uid)
                    }
                }
                .labelsHidden()
                .disabled(!controlsEnabled)
                Button(L("마이크 목록 새로고침", "Refresh microphones"), systemImage: "arrow.clockwise") {
                    Task { await model.refreshVoiceInputOptions() }
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .disabled(!controlsEnabled)
            }
            if selectedMicrophoneDisconnected {
                Label(L("선택한 마이크 연결 끊김", "Selected microphone disconnected"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            OptionToggle(L("녹음 준비·종료 알림음", "Recording ready and stop sounds"),
                         help: L("마이크가 실제 음성을 받을 준비가 됐을 때와 녹음을 끝낼 때 소리로 알려 줍니다. 녹음 중 시스템 소리 음소거를 함께 사용하면 준비 알림음이 들리지 않을 수 있습니다.", "Plays sounds when the microphone is ready to receive audio and when recording stops. The ready sound may be inaudible while system mute is enabled."),
                         isOn: $model.preferences.recordingAudioFeedback, isEnabled: controlsEnabled)
            OptionToggle(L("녹음 중 시스템 소리 음소거", "Mute system audio while recording"),
                         help: L("녹음 중 시스템 소리를 음소거하고 녹음이 끝나면 이전 상태로 복원합니다. 녹음 중 직접 바꾼 설정은 존중합니다. 녹음 알림음도 들리지 않을 수 있습니다.", "Mutes system audio while recording and restores the previous state afterward, respecting changes you make during capture. Recording sounds may also be inaudible."),
                         isOn: $model.preferences.muteWhileRecording, isEnabled: controlsEnabled)
            if model.preferences.recordingAudioFeedback && model.preferences.muteWhileRecording {
                Label(L("시스템 음소거로 준비 알림음이 들리지 않을 수 있어요", "System mute may silence the ready sound"), systemImage: "speaker.slash")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .task { if !AppLaunch.isPreview { await model.refreshVoiceInputOptions() } }
    }
    private func activationTitle(_ mode: ShortcutActivationMode) -> String {
        switch mode {
        case .toggle: L("한 번 눌러 시작·다시 눌러 종료", "Press to start and stop")
        case .hold: L("누르는 동안 녹음", "Hold to record")
        case .holdOrToggle: L("짧게 누르기·길게 누르기 혼합", "Hold or toggle")
        }
    }
}

struct LocalModelOptionsView: View {
    @Bindable var model: AppModel
    @State private var confirmsDeletion = false
    private var controlsEnabled: Bool {
        !model.isBusy && !model.preferencesRecoveryRequired && !AppLaunch.isPreview
    }
    private var preparing: Bool {
        switch model.localState { case .downloading, .loading: true; default: false }
    }
    var body: some View {
        Surface(L("로컬 음성 인식", "On-device speech recognition")) {
            HStack {
                OptionHelpLabel(L("인식 모델", "Speech model"), help: L("이 Mac에서 음성을 인식할 때 사용할 모델입니다. 모두 한국어·영어를 지원합니다. 작은 모델은 자원 사용을 줄일 수 있으나 한영 혼용·고유명사 정확도는 같은 녹음으로 비교해 주세요. 모델 선택과 파일 다운로드·메모리 준비는 별도입니다.", "The model used for on-device speech recognition. All models support Korean and English. Smaller models can reduce resource use; compare mixed-language and proper-name accuracy on the same recording. Choosing a model is separate from downloading its files and loading it into memory."))
                Spacer()
                Picker(L("인식 모델", "Speech model"), selection: $model.preferences.localSpeechModel) {
                    ForEach(LocalSpeechModel.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .disabled(!controlsEnabled)
            }
            HStack {
                Text(model.localState.label).font(.system(size: 13))
                Spacer()
                if model.localState != .ready {
                    Button(L("모델 다운로드 / 준비", "Download / prepare model"), action: model.prepareLocal)
                        .disabled(!controlsEnabled || preparing).buttonStyle(.borderedProminent)
                }
                if preparing {
                    Button(L("준비 취소", "Cancel setup")) { model.cancelLocalPreparation() }
                        .disabled(!controlsEnabled)
                }
            }
            HStack {
                OptionHelpLabel(L("모델 파일", "Model files"), help: L("다운로드한 모델 파일과 메모리에 준비된 모델은 별도입니다. 모델 또는 토크나이저 파일이 없으면 준비가 필요합니다. 선택 모델 파일만 삭제하며, 기록·사전·다른 모델은 유지됩니다. 다시 사용하려면 모델을 다운로드해야 합니다.", "Downloaded model files and a model loaded in memory are separate states. Missing model or tokenizer files require setup. Deleting removes only the selected model's files; history, dictionary and other models are kept. Download the model again to use it."))
                Spacer()
                if let cache = model.localModelCaches.first(where: { $0.model == model.preferences.localSpeechModel }) {
                    Text(cache.isDownloaded
                         ? L("저장됨 · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))", "Downloaded · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))")
                         : L("파일 준비 필요", "Files needed"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Button(L("선택 모델 파일 삭제…", "Delete selected model files…"), role: .destructive) { confirmsDeletion = true }
                    .disabled(!controlsEnabled || preparing)
            }
            HStack {
                OptionHelpLabel(L("모델 메모리 유지", "Keep model in memory"), help: L("사용하지 않을 때 메모리에 올린 모델을 언제 해제할지 정합니다. 메모리를 해제해도 다운로드한 파일은 남습니다. 다음 녹음 때 다시 준비하므로 첫 반응이 느려질 수 있습니다.", "Choose when to unload an idle model from memory. Downloaded files remain. The next recording reloads the model and may take longer to start."))
                Spacer()
                Picker(L("모델 메모리 유지", "Keep model in memory"), selection: $model.preferences.localModelUnloadPolicy) {
                    ForEach(LocalModelUnloadPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .disabled(!controlsEnabled)
            }
            OptionToggle(L("녹음 중 로컬 미리보기 · 실험", "On-device preview while recording · Experimental"),
                         help: L("로컬 인식을 사용할 때 최근 12초를 반복 인식해 표시합니다. 미리보기는 확정 결과가 아니며, 최종 입력은 녹음 전체를 다시 인식합니다. 추가 연산이 필요하고 내 목소리 필터를 켜면 미리보기를 사용하지 않습니다.", "With on-device recognition, repeatedly transcribes the last 12 seconds for display. The preview is not final; final typing re-transcribes the full recording. This adds computation and is unavailable with the enrolled voice filter."),
                         isOn: $model.preferences.localPreviewEnabled, isEnabled: controlsEnabled)
            if model.preferences.localPreviewEnabled {
                if model.preferences.speakerFilterEnabled {
                    Label(L("현재 미적용 · 내 목소리 필터 사용 중", "Paused · Enrolled voice filter is on"), systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if !model.preferences.needsLocalForDictation {
                    Label(L("현재 미적용 · 로컬 음성 인식에서 사용", "Paused · Available with on-device speech recognition"), systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Label(L("미리보기 켜짐 · 추가 연산", "Preview on · Extra processing"), systemImage: "waveform")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(L("선택한 로컬 모델 파일을 삭제할까요?", "Delete the selected local model files?"), isPresented: $confirmsDeletion) {
            Button(L("모델 파일 삭제", "Delete model files"), role: .destructive) { Task { await model.deleteSelectedLocalModel() } }
                .disabled(!controlsEnabled || preparing)
        } message: {
            Text(L("기록·사전·다른 모델은 유지됩니다. 이 모델을 다시 사용하려면 다운로드가 필요합니다.", "History, dictionary and other models are kept. Download this model again to use it."))
        }
        .task { if !AppLaunch.isPreview { await model.refreshVoiceInputOptions() } }
        .onChange(of: model.preferences.localSpeechModel) { _, _ in Task { await model.refreshVoiceInputOptions() } }
    }
}
