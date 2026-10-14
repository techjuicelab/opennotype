import SwiftUI
import OpenNoTypeCore

struct VoiceInputOptionsView: View {
    @Bindable var model: AppModel
    var showsProcessing = true
    var showsRecording = true
    var embedded = false
    private var controlsEnabled: Bool {
        !model.isBusy && !model.preferencesRecoveryRequired && !AppLaunch.isPreview
    }
    private var selectedMicrophoneDisconnected: Bool {
        guard let uid = model.preferences.inputDeviceUID else { return false }
        return !model.inputDevices.contains(where: { $0.uid == uid })
    }
    private var processingState: String? {
        if model.preferences.dictationProcessing == .onDeviceVerbatim && model.preferences.dictationOutputLanguage.isTranslation {
            return L("번역 중 미적용 · 빠른 로컬 선택 유지", "Paused during translation · Quick choice kept")
        }
        if model.preferences.usesFastDictation && model.localState != .ready {
            return L("로컬 모델 · \(model.localState.label)", "Local model · \(model.localState.label)")
        }
        return nil
    }

    var body: some View {
        Group {
            if embedded { optionRows }
            else { SettingsPanel(L("녹음", "Recording")) { optionRows } }
        }
        .task { if showsRecording && !AppLaunch.isPreview { await model.refreshVoiceInputOptions() } }
    }

    @ViewBuilder private var optionRows: some View {
        if showsProcessing {
            SettingsRow(L("받아쓰기 처리", "Dictation processing"), help: L("정리해서 입력은 인식한 문장을 AI로 정리합니다. 빠른 로컬 받아쓰기는 말한 언어 유지일 때만 이 Mac의 인식문을 AI 정리·자동 Jev 없이 입력합니다. API 키는 필요 없지만 로컬 모델 준비가 필요합니다. 번역·선택 수정·프롬프트는 별도의 AI 처리를 사용합니다. 인식문이 발화를 완벽히 복제한다는 뜻은 아닙니다.", "Cleanup uses AI to edit the transcript. Quick on-device dictation applies only when keeping the spoken language and types the local transcript without AI cleanup or automatic Jev. It needs a prepared local model, not an API key. Translation, selected-text edits, and prompts use their separate AI processing. A transcript is not guaranteed to reproduce speech perfectly."), state: processingState) {
                Picker(L("받아쓰기 처리", "Dictation processing"), selection: $model.preferences.dictationProcessing) {
                    ForEach(DictationProcessingMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
            }
        }
        if showsRecording {
            SettingsRow(L("녹음 마이크", "Recording microphone"), help: L("시스템 기본 또는 지정 마이크를 사용합니다. 목록에 없는 지정 장치는 연결 끊김으로 표시하며 저장한 선택은 유지합니다. 장치를 연결한 뒤 목록을 새로고침할 수 있습니다.", "Use the system default or a selected microphone. A selected device missing from the list is shown as disconnected and its saved choice is kept. Refresh after connecting it."), state: selectedMicrophoneDisconnected ? L("선택한 마이크 연결 끊김", "Selected microphone disconnected") : nil) {
                Picker(L("녹음 마이크", "Recording microphone"), selection: Binding(
                    get: { model.preferences.inputDeviceUID ?? "" },
                    set: { if controlsEnabled { model.preferences.inputDeviceUID = $0.isEmpty ? nil : $0 } })) {
                    Text(L("시스템 기본 마이크", "System default microphone")).tag("")
                    ForEach(model.inputDevices) { Text($0.name).tag($0.uid) }
                    if let uid = model.preferences.inputDeviceUID, selectedMicrophoneDisconnected {
                        Text(L("선택한 마이크 연결 끊김", "Selected microphone disconnected")).tag(uid)
                    }
                }.labelsHidden().frame(width: 200).disabled(!controlsEnabled)
                Button { Task { await model.refreshVoiceInputOptions() } } label: { Image(systemName: "arrow.clockwise") }
                    .frame(width: 32).disabled(!controlsEnabled)
                    .help(L("마이크 목록 새로고침", "Refresh microphones"))
                    .accessibilityLabel(L("마이크 목록 새로고침", "Refresh microphones"))
            }
            SettingsRow(L("단축키 동작", "Shortcut activation"), help: L("한 번 누르기는 다음 누름까지 녹음합니다. 누르는 동안 녹음은 키를 떼면 끝납니다. 혼합은 짧게 누르면 계속 녹음하고 길게 누르면 떼는 순간 끝납니다.", "Toggle records until the next press. Hold ends on release. Hybrid toggles after a tap and ends on release after a hold.")) {
                Picker(L("단축키 동작", "Shortcut activation"), selection: $model.preferences.shortcutActivation) {
                    ForEach(ShortcutActivationMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
            }
            SettingsRow(L("준비·종료 알림음", "Ready and stop sounds"), help: L("마이크가 실제 음성을 받을 준비가 됐을 때와 종료 때 소리를 냅니다. 시스템 음소거와 함께 쓰면 들리지 않을 수 있습니다.", "Plays sounds when the microphone is ready and when recording stops. System mute may silence them."), state: model.preferences.recordingAudioFeedback && model.preferences.muteWhileRecording ? L("음소거로 준비 알림음이 들리지 않을 수 있음", "System mute may silence the ready sound") : nil) {
                Toggle(L("준비·종료 알림음", "Ready and stop sounds"), isOn: $model.preferences.recordingAudioFeedback)
                    .labelsHidden().toggleStyle(.switch).disabled(!controlsEnabled)
            }
            SettingsRow(L("녹음 중 시스템 음소거", "Mute system audio while recording"), help: L("종료 후 이전 상태로 복원하며 녹음 중 직접 바꾼 값은 존중합니다. 알림음도 들리지 않을 수 있습니다.", "Restores the prior state afterward and respects changes you make during recording. Recording sounds may be inaudible.")) {
                Toggle(L("녹음 중 시스템 음소거", "Mute system audio while recording"), isOn: $model.preferences.muteWhileRecording)
                    .labelsHidden().toggleStyle(.switch).disabled(!controlsEnabled)
            }
        }
    }
}

struct LocalModelOptionsView: View {
    @Bindable var model: AppModel
    var embedded = false
    @State private var confirmsDeletion = false
    private var controlsEnabled: Bool {
        !model.isBusy && !model.preferencesRecoveryRequired && !AppLaunch.isPreview
    }
    private var preparing: Bool {
        switch model.localState { case .downloading, .loading: true; default: false }
    }
    private var cacheDescription: String {
        guard let cache = model.localModelCaches.first(where: { $0.model == model.preferences.localSpeechModel }) else {
            return L("파일 상태 확인 전", "Files not checked")
        }
        return cache.isDownloaded
            ? L("저장됨 · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))", "Downloaded · \(ByteCountFormatter.string(fromByteCount: cache.storedBytes, countStyle: .file))")
            : L("파일 준비 필요", "Files needed")
    }

    var body: some View {
        Group {
            if embedded { optionRows }
            else { SettingsPanel(L("파일과 메모리", "Files and memory")) { optionRows } }
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

    private var optionRows: some View {
        Group {
            SettingsRow(L("인식 모델", "Speech model"), help: L("이 Mac에서 사용할 모델입니다. 한국어·영어 지원은 한영 혼용·고유명사 정확도의 보장이 아닙니다. 작은 모델은 자원 사용을 줄일 수 있습니다. 모델 선택·파일 저장·메모리 준비는 별개입니다.", "The model used on this Mac. Korean and English support does not guarantee mixed-language or proper-name accuracy. Smaller models may reduce resource use. Selection, files, and memory readiness are separate.")) {
                Picker(L("인식 모델", "Speech model"), selection: $model.preferences.localSpeechModel) {
                    ForEach(LocalSpeechModel.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
            }
            SettingsRow(L("메모리 준비", "Memory readiness"), help: L("파일 저장과 메모리 준비는 다릅니다. 모델과 토크나이저가 모두 필요합니다. 준비 중에는 중복 준비와 파일 삭제를 막습니다.", "Saved files and a model loaded in memory are different. Model and tokenizer are both required. Setup blocks duplicate preparation and file deletion."), state: model.localState.label) {
                if model.localState == .ready {
                    Label(L("준비됨", "Ready"), systemImage: "checkmark.circle").foregroundStyle(AppTheme.accentForeground)
                } else if preparing {
                    Button(L("준비 취소", "Cancel setup")) { model.cancelLocalPreparation() }.disabled(!controlsEnabled)
                } else {
                    Button(L("다운로드·준비", "Download / prepare"), action: model.prepareLocal)
                        .disabled(!controlsEnabled).buttonStyle(AppActionButtonStyle(primary: true))
                }
            }
            SettingsRow(L("선택 모델 파일", "Selected model files"), help: L("이 모델과 토크나이저 파일만 삭제합니다. 기록·사전·다른 모델은 유지됩니다. 다시 사용하려면 다운로드해야 합니다.", "Deletes only this model and tokenizer. History, dictionary, and other models are kept. Download again to use it."), state: cacheDescription) {
                Button(L("파일 삭제…", "Delete files…"), role: .destructive) { confirmsDeletion = true }
                    .disabled(!controlsEnabled || preparing)
            }
            SettingsRow(L("메모리 유지", "Keep in memory"), help: L("미사용 시 모델 메모리를 해제하는 시점입니다. 파일은 남고 다음 녹음에 다시 준비하므로 첫 반응이 느려질 수 있습니다.", "When to unload an idle model. Files remain. The next recording reloads it, which may delay the first response.")) {
                Picker(L("메모리 유지", "Keep in memory"), selection: $model.preferences.localModelUnloadPolicy) {
                    ForEach(LocalModelUnloadPolicy.allCases) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 240).disabled(!controlsEnabled)
            }
            LocalPreviewSettingsRow(model: model)
        }
    }
}

struct LocalPreviewSettingsRow: View {
    @Bindable var model: AppModel
    private var enabled: Bool { !model.isBusy && !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var state: String? {
        guard model.preferences.localPreviewEnabled else { return nil }
        if model.preferences.speakerFilterEnabled { return L("현재 미적용 · 내 목소리 필터 켜짐", "Paused · Enrolled voice filter is on") }
        if !model.preferences.needsLocalForDictation { return L("현재 미적용 · 로컬 인식에서 사용", "Paused · On-device recognition only") }
        return L("실험 · 추가 연산 · 확정 결과 아님", "Experimental · Extra computation · Not final")
    }
    var body: some View {
        SettingsRow(L("녹음 중 미리보기", "Preview while recording"), help: L("로컬 인식에서 최근 12초를 반복 인식하는 실험입니다. 최종 입력은 전체 녹음을 다시 인식합니다. 추가 연산이 필요하며 내 목소리 필터가 켜지면 미리보기는 미적용됩니다. 저장된 선택은 유지됩니다.", "Experimental repeated recognition of the last 12 seconds locally. Final input re-transcribes the full recording. Adds computation and is paused with the enrolled voice filter, keeping the saved choice."), state: state) {
            Toggle(L("녹음 중 미리보기", "Preview while recording"), isOn: $model.preferences.localPreviewEnabled)
                .labelsHidden().toggleStyle(.switch).disabled(!enabled)
        }
    }
}
