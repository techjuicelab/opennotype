import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenNoTypeCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var recordingHotkey: Int?
    @State private var eventMonitor: Any?
    @State private var showWritingProfiles = false
    @State private var writingProfileApps: [WritingProfileApp] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("나에게 맞는 OpenNoType")
                    .font(.system(size: 25, weight: .semibold)).tracking(-0.6)
                Text("입력 방식은 앱에서, Mac 접근 권한은 시스템 설정에서 관리해요.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Picker("설정 분류", selection: $model.settingsSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }.pickerStyle(.segmented)
            Text(model.settingsSection.detail)
                .font(.system(size: 13)).foregroundStyle(.secondary)
            sectionContent
        }
        .onChange(of: model.settingsSection) { _, _ in stopHotkeyRecording() }
        .onDisappear { stopHotkeyRecording() }
    }

    @ViewBuilder private var sectionContent: some View {
        switch model.settingsSection {
        case .connection:
            connectionSection
            Surface("사용량과 비용") {
                Text("음성 인식과 문장 처리에 사용한 모델별 요청·사용량을 확인하세요. 로컬 처리는 API 사용과 따로 표시합니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                Button("모델별 사용량 보기", systemImage: "chart.bar.xaxis") { model.page = .usage }
            }
        case .input:
            hotkeysSection
            translationSection
            writingProfilesSection
            diagnosticsSection
        case .privacy:
            transmissionSection
            contextSection
            learningSection
            usagePrivacySection
            retentionSection
        case .general:
            generalSection
            UpdateSettingsView(updater: .shared)
            permissionsSection
        }
    }

    private var connectionSection: some View {
        Surface("AI 연결") {
            Picker("제공자", selection: $model.preferences.provider) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented).onChange(of: model.preferences.provider) { _, _ in model.loadKey() }
            HStack {
                SecureField("\(model.preferences.provider.displayName) API 키", text: $model.apiKeyDraft).textFieldStyle(.roundedBorder)
                Button(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.keySaved ? "저장된 키 삭제" : "Keychain에 저장") { model.saveKey() }
                    .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.keySaved)
            }
            Text(model.keyDraftIsChanged ? "키가 변경되었습니다. 저장해야 다음 처리에 적용됩니다." : model.keySaved ? "키가 저장되어 있습니다. 연결 여부는 실제 처리 때 확인됩니다." : "사용할 API 키를 저장해 주세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if model.preferences.provider == .groq {
                Text("Groq API 키 하나로 음성 인식과 문장 정리를 연결합니다. 키는 이 Mac의 Keychain에 저장됩니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Link("Groq 연결 안내", destination: URL(string: "https://console.groq.com/docs/quickstart")!)
                    .font(.system(size: 12))
            }
            Text("대화 앱 구독과 API 사용료는 별개입니다. 사용료는 선택한 AI 제공자가 부과합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if model.preferences.provider == .anthropic {
                Label("로컬 음성 인식 사용 · Claude 연결에 필수", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.accentForeground)
                Text("음성 모델 화면에서 먼저 준비해 주세요. 인식한 글은 문장 처리를 위해 Anthropic으로 전송합니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Toggle("음성 인식을 이 Mac에서 처리", isOn: $model.preferences.useLocalTranscription)
            }
            if model.preferences.provider == .openRouter {
                Text("OpenRouter는 선택한 모델의 공급자로 요청을 전달합니다. 같은 모델이어도 실제 처리 공급자가 달라질 수 있으며, 이 앱은 특정 공급자에 고정하지 않습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            if model.preferences.provider == .groq {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.preferences.needsLocal {
                        ProviderModelPicker("음성 인식 모델", selection: transcriptionModelBinding, choices: GroqModelChoices.transcription)
                            .id("groq-transcription")
                    } else {
                        Text("음성은 이 Mac에서 인식하고, 문장 정리는 아래 Groq 모델이 처리합니다.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ProviderModelPicker("문장 정리 모델", selection: textModelBinding, choices: GroqModelChoices.text)
                        .id("groq-text")
                    Text("선택은 자동 저장됩니다. 목록에 없는 모델은 ‘직접 입력’을 선택하세요. 모델 이용 가능 여부는 Groq 계정에 따라 달라집니다.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.top, 8)
            } else {
                otherProviderModels
            }
            Button("로컬 모델 준비 상태 보기", systemImage: "desktopcomputer") { model.page = .voice }
                .padding(.top, 2)
        }
    }

    private var translationSection: some View {
        Surface("번역") {
            Picker("번역할 언어", selection: $model.preferences.targetLanguage) {
                Text("영어 · 미국식").tag("English (United States)")
                Text("영어 · 영국식").tag("English (United Kingdom)")
                Text("한국어").tag("Korean")
                Text("일본어").tag("Japanese")
                Text("중국어 · 간체").tag("Chinese (Simplified)")
                Text("중국어 · 번체").tag("Chinese (Traditional)")
            }
            Text("입력 언어는 자동으로 인식합니다. 녹음이 끝나면 의미와 말투를 살린 번역문을 입력합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var hotkeysSection: some View {
        Surface("단축키") {
            ForEach(Array(InputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                HStack {
                    Text(mode.title).font(.system(size: 12)); Spacer()
                    Button(recordingHotkey == index ? "새 단축키를 누르세요…" : model.preferences.hotkeys[index].label) { recordHotkey(index) }
                        .font(.system(size: 12, design: .monospaced)).frame(minWidth: 150)
                }
            }
            Text("한 번 누르면 녹음 시작, 다시 누르면 종료합니다. Option·Control·Command를 포함한 조합을 사용하세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(model.hotkeyConflicts, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            Button("다른 앱과 겹치는 단축키 확인") { model.refreshHotkeyConflicts() }.controlSize(.small)
        }
        .onAppear { model.refreshHotkeyConflicts() }
    }

    private var contextSection: some View {
        Surface("문맥 사용 · 앱별 허용") {
            Text("허용한 앱에서만 커서 앞 최대 1,000자를 AI 제공자에게 함께 보냅니다. 보안 입력란은 제외하고, 문맥은 기록에 저장하지 않습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            if model.preferences.allowedContextApps.isEmpty {
                Label("현재 허용된 앱이 없습니다", systemImage: "lock").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(model.preferences.allowedContextApps.sorted(), id: \.self) { bundle in
                HStack {
                    Image(systemName: "app"); Text(appName(bundle)).font(.system(size: 12)); Spacer()
                    Button("허용 해제") { model.preferences.allowedContextApps.remove(bundle) }.controlSize(.small)
                }
            }
            Button("앱 추가…", systemImage: "plus") { addContextApp() }
        }
    }

    private var retentionSection: some View {
        Surface("기록과 보관") {
            Toggle("받아쓰기·번역 결과 기록", isOn: $model.preferences.historyEnabled)
            Picker("텍스트 보관 기간", selection: $model.preferences.retentionDays) {
                Text("1일").tag(1); Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90); Text("계속 보관").tag(-1)
            }.onChange(of: model.preferences.retentionDays) { _, _ in Task { await model.refreshData() } }
            Text("성공한 녹음은 즉시 삭제합니다. 실패한 녹음은 암호화해 24시간 동안 복구할 수 있습니다. 앱 실행 중에는 만료된 파일을 정리하며, 앱이 꺼져 있으면 다음 실행 때 정리합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private var diagnosticsSection: some View {
        Surface("입력 문제 확인") {
            Text("테스트를 준비한 뒤 원하는 입력창에서 받아쓰기 단축키를 누르세요. ‘OpenNoType 입력 테스트입니다.’를 입력하며 녹음·API 호출·메시지 전송은 하지 않습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button(model.inputTestArmed ? "입력창에서 단축키를 눌러 주세요" : "녹음 없이 입력 테스트 준비") { model.armInputTest() }
                .disabled(model.inputTestArmed || model.isBusy)
            Button("5초 뒤 입력 테스트") { model.scheduleInputTest() }.disabled(model.isBusy)
            if model.inputTestArmed {
                Button("입력 테스트 준비 취소") { model.cancelInputTest() }
            }
            if !model.inputDiagnostics.isEmpty {
                Text(model.inputDiagnostics).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            if let timings = model.lastProcessingTimings {
                Divider()
                Text("최근 처리 시간").font(.system(size: 12, weight: .medium))
                Text(timings).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text("입력·확인에는 붙여넣은 뒤의 확인 대기가 포함됩니다. 화면에 글이 보인 시각과 다를 수 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }

    private var transmissionSection: some View {
        Surface("AI로 보내는 정보") {
            Label(model.preferences.needsLocal ? "음성 인식은 이 Mac에서 처리" : "녹음은 \(model.preferences.provider.displayName) 서비스로 전송", systemImage: model.preferences.needsLocal ? "desktopcomputer" : "network")
                .font(.system(size: 13, weight: .medium))
            Text("인식한 글과 요청은 문장 처리를 위해 \(model.preferences.provider.displayName) 서비스로 보냅니다. 선택 문장 수정은 선택한 문장도 함께 보냅니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            if model.preferences.provider == .openRouter {
                Text("OpenRouter는 선택한 모델을 제공하는 공급자로 요청을 전달합니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button("AI 연결과 음성 인식 방식 변경") { model.settingsSection = .connection }
        }
    }

    private var learningSection: some View {
        Surface("개인 사전 학습") {
            Toggle("안전한 이름·표기 교정 자동 학습", isOn: $model.preferences.automaticLearningEnabled)
            Text("입력 직후 직접 고친 이름과 표기 중 확실한 교정만 개인 사전에 반영합니다. 의미가 달라질 수 있는 변경은 검토 후 저장할 수 있습니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button("개인 사전과 교정 검토", systemImage: "character.book.closed") { model.page = .dictionary }
                if model.canUndoLastLearning {
                    Button("최근 자동 학습 되돌리기") { Task { await model.undoLastLearning() } }
                }
            }
        }
    }

    private var usagePrivacySection: some View {
        Surface("사용량 통계") {
            Toggle("사용량 통계 기록", isOn: $model.preferences.usageTrackingEnabled)
            Text("모델·요청 횟수·토큰·음성 처리 시간 등의 사용 정보만 이 Mac에 암호화해 보관합니다. 통계에는 문장 내용과 녹음 원음을 포함하지 않습니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            Text("결과 기록 설정과 별도로 최대 10,000건을 보관합니다. 끄면 새 요청 수집을 중단합니다. 이미 수집해 저장 중인 기록은 늦게 반영될 수 있고, 기존 통계는 유지됩니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button("사용량과 보관 중인 통계 보기", systemImage: "chart.bar.xaxis") { model.page = .usage }
        }
    }

    private var generalSection: some View {
        Surface("앱 실행과 화면") {
            Toggle("Mac에 로그인할 때 실행", isOn: Binding(get: { model.launchAtLoginEnabled }, set: { model.setLaunchAtLogin($0) }))
            if let status = model.loginItemStatusText {
                Label(status, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            Button("로그인 항목 시스템 설정 열기", systemImage: "arrow.up.forward.square") { model.openLoginItemSettings() }
            Divider()
            Picker("화면 모드", selection: $model.preferences.appearance) {
                Text("시스템 설정에 맞춤").tag("system")
                Text("라이트").tag("light")
                Text("다크").tag("dark")
            }
            Text("설정은 자동으로 저장됩니다. API 키는 ‘Keychain에 저장’을 눌러 적용하세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        Surface("Mac 접근 권한") {
            permissionStatus("마이크", detail: "단축키나 버튼으로 시작한 녹음에 사용합니다.", allowed: model.microphoneAllowed)
            HStack {
                if !model.microphoneAllowed && !model.microphonePermissionNeedsSettings {
                    Button("마이크 사용 요청") { Task { await model.requestMicrophone() } }
                }
                Button("마이크 시스템 설정 열기", systemImage: "arrow.up.forward.square") { model.openMicrophoneSettings() }
            }
            Divider()
            permissionStatus("손쉬운 사용", detail: "선택한 문장을 읽고, 다른 앱의 커서 위치에 글을 입력합니다.", allowed: model.accessibilityAllowed)
            Button("손쉬운 사용 시스템 설정 열기", systemImage: "arrow.up.forward.square") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Text("시스템 설정 › 개인정보 보호 및 보안에서 OpenNoType을 허용한 뒤 돌아오세요. 앱이 활성화되면 권한 상태를 다시 확인합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button("권한 상태 다시 확인", systemImage: "arrow.clockwise") { model.refreshPermissions() }
                Button("입력 테스트로 확인") { model.settingsSection = .input }
            }
        }
        .onAppear { model.refreshPermissions() }
    }

    private func permissionStatus(_ title: String, detail: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Label(allowed ? "허용됨" : "허용 필요", systemImage: allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(allowed ? AppTheme.accentForeground : .orange)
        }
    }

    private var transcriptionModelBinding: Binding<String> {
        Binding(get: { model.preferences.transcriptionModel }, set: { model.preferences.transcriptionModels[model.preferences.provider.rawValue] = $0 })
    }

    private var textModelBinding: Binding<String> {
        Binding(get: { model.preferences.textModel }, set: { model.preferences.textModels[model.preferences.provider.rawValue] = $0 })
    }

    private var otherProviderModels: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("사용할 모델").font(.system(size: 14, weight: .medium))
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("문장 처리") {
                    TextField("모델 ID", text: textModelBinding)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 260)
                }
                if !model.preferences.needsLocal {
                    LabeledContent("음성 인식") {
                        TextField("모델 ID", text: transcriptionModelBinding)
                            .textFieldStyle(.roundedBorder).frame(minWidth: 260)
                    }
                }
                Text("선택한 계정에서 이용 가능한 모델을 입력하세요. 다른 제공자로 자동 전환하지 않습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("변경 내용은 자동 저장됩니다. 모델 ID를 비우면 기본 모델을 사용합니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

    private var writingProfilesSection: some View {
        Surface("앱별 작성 방식") {
            Text("녹음을 시작한 앱에 맞춰 문장과 형식을 정리합니다. 기본적으로 반말·존댓말은 말한 그대로 유지하며, 아래에서 말투를 지정한 앱에서만 바꿉니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            DisclosureGroup("앱별 설정 \(writingProfileApps.count)개 보기", isExpanded: $showWritingProfiles) {
                VStack(alignment: .leading, spacing: 18) {
            ForEach(writingProfileApps) { app in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 12))
                        Text(model.preferences.writingProfiles[app.id] == nil ? "기본 설정" : "사용자 설정")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Picker("\(app.name) 작성 형식", selection: profileKindBinding(app.id)) {
                        ForEach(WritingProfileKind.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 100)
                    Picker("\(app.name) 말투", selection: profileToneBinding(app.id)) {
                        ForEach(WritingTone.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 160)
                    Button("복원") {
                        model.preferences.writingProfiles.removeValue(forKey: app.id)
                        refreshWritingProfileApps()
                    }
                    .controlSize(.small)
                    .disabled(model.preferences.writingProfiles[app.id] == nil)
                    .help("이 앱의 작성 방식을 기본값으로 복원")
                    .accessibilityLabel("\(app.name) 기본값 복원")
                }
            }
                }.padding(.top, 14)
            }
            if writingProfileApps.isEmpty {
                Text("앱을 추가해 작성 방식과 말투를 지정할 수 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button("앱 추가…", systemImage: "plus") { addWritingProfileApp() }
            Text("앱 이름만 구분하므로 브라우저의 웹사이트나 대화 상대는 판단하지 않습니다. 이 설정으로 주변 텍스트를 읽지는 않습니다. 문맥 사용은 개인정보 설정에서 별도로 허용할 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
        .onAppear { refreshWritingProfileApps() }
    }

    private func profileKindBinding(_ bundleID: String) -> Binding<WritingProfileKind> {
        Binding(get: { model.preferences.writingProfile(for: bundleID).kind }, set: { kind in
            var profile = model.preferences.writingProfile(for: bundleID)
            profile.kind = kind
            model.preferences.writingProfiles[bundleID] = profile
        })
    }

    private func profileToneBinding(_ bundleID: String) -> Binding<WritingTone> {
        Binding(get: { model.preferences.writingProfile(for: bundleID).tone }, set: { tone in
            var profile = model.preferences.writingProfile(for: bundleID)
            profile.tone = tone
            model.preferences.writingProfiles[bundleID] = profile
        })
    }

    private func refreshWritingProfileApps() {
        let identifiers = Set(WritingProfile.knownAppBundleIDs).union(model.preferences.writingProfiles.keys)
        writingProfileApps = identifiers.compactMap { identifier in
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                // Some Codex installations retain the older ChatGPT.app filename.
                let name = identifier == "com.openai.codex" ? "Codex" : url.deletingPathExtension().lastPathComponent
                return WritingProfileApp(id: identifier, name: name)
            }
            guard model.preferences.writingProfiles[identifier] != nil else { return nil }
            return WritingProfileApp(id: identifier, name: identifier)
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func addWritingProfileApp() {
        let panel = NSOpenPanel()
        panel.title = "작성 방식을 지정할 앱 선택"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier else { continue }
            model.preferences.writingProfiles[identifier] = model.preferences.writingProfile(for: identifier)
        }
        refreshWritingProfileApps()
        showWritingProfiles = true
    }

    private struct WritingProfileApp: Identifiable {
        let id: String
        let name: String
    }

    private func recordHotkey(_ index: Int) {
        stopHotkeyRecording(); recordingHotkey = index
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopHotkeyRecording(); return nil }
            guard let binding = HotkeyBinding.from(event) else { return nil }
            model.updateHotkey(binding, index: index); stopHotkeyRecording(); return nil
        }
    }
    private func stopHotkeyRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil; recordingHotkey = nil
    }
    private func addContextApp() {
        let panel = NSOpenPanel(); panel.title = "문맥 사용을 허용할 앱 선택"
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier { model.preferences.allowedContextApps.insert(identifier) }
        }
    }
    private func appName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return url.deletingPathExtension().lastPathComponent
    }
}

struct VoiceSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("이 Mac에서 듣고 구분해요").font(.system(size: 23, weight: .semibold)).tracking(-0.6)
            Text("모델은 처음 한 번 내려받습니다. 로컬 모델의 음성 처리는 기기에서 이루어집니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Surface("현재 음성 인식 방식") {
            Label(model.preferences.needsLocal ? "로컬 음성 인식 사용 중" : "\(model.preferences.provider.displayName) API 음성 인식 사용 중", systemImage: model.preferences.needsLocal ? "desktopcomputer" : "network")
                .font(.system(size: 14, weight: .medium))
            Text("모델을 다운로드해도 사용 방식이 자동으로 바뀌지는 않습니다. AI 연결 설정에서 로컬 인식을 선택하세요. Claude 연결에서는 로컬 인식이 필수입니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text("로컬 음성 인식에는 API 인식 비용이 들지 않습니다. 이후 문장 처리는 선택한 AI 제공자의 API를 사용합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button("음성 인식 방식 변경") { model.settingsSection = .connection; model.page = .settings }
        }
        Surface("로컬 음성 인식") {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Whisper Large v3").font(.system(size: 15, weight: .semibold))
                    Text("약 627 MB + 기기 준비 공간 · 다국어 음성 인식").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "desktopcomputer").font(.system(size: 30, weight: .light)).foregroundStyle(AppTheme.accentForeground)
            }
            modelStatus(model.localState)
            Button(model.localState == .ready ? "모델 준비됨" : "모델 다운로드 / 준비", action: model.prepareLocal)
                .disabled(model.localState.working || model.localState == .ready).buttonStyle(.borderedProminent)
            if model.localState.working { Button("모델 준비 취소") { model.cancelLocalPreparation() } }
            Text("선택한 로컬 기능에 필요한 모델은 이미 내려받았다면 앱 실행 시 이 Mac에서 준비합니다. 새 다운로드는 위 버튼으로 시작합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Claude 키만 사용할 때 필요합니다. OpenAI·Groq·OpenRouter 연결에서도 로컬 인식을 선택할 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
        Surface("내 목소리 구분 · 실험 단계") {
            Text(LocalSpeakerRecognizer.limitation).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            Text("현재 빌드는 실제 사용자·TV·겹말 환경의 성능 검증 전입니다. 필터는 기본적으로 꺼져 있습니다.")
                .font(.system(size: 12)).foregroundStyle(.orange)
            modelStatus(model.speakerState)
            Button(model.speakerState == .ready ? "화자 모델 준비됨" : "화자 모델 다운로드 / 준비 · 약 14 MB", action: model.prepareSpeaker)
                .disabled(model.speakerState.working || model.speakerState == .ready)
            if model.speakerState.working { Button("화자 모델 준비 취소") { model.cancelSpeakerPreparation() } }
            Divider()
            HStack {
                Label(model.hasSpeakerProfile ? "내 목소리가 등록되어 있습니다" : "아직 등록된 목소리가 없습니다", systemImage: model.hasSpeakerProfile ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 12))
                Spacer()
                if model.hasSpeakerProfile { Button("삭제", role: .destructive) { Task { await model.deleteVoice() } } }
            }
            HStack {
                Button(model.hasSpeakerProfile ? "다시 등록" : "목소리 등록 시작") { Task { await model.enrollVoice() } }
                    .disabled(model.speakerState != .ready || model.isBusy)
                if model.phase == .enrolling { Button("등록 녹음 종료") { model.stop() } }
            }
            Text("조용한 곳에서 혼자 10~20초 동안 자연스럽게 말해 주세요. 등록 녹음은 삭제하고 목소리 특징만 암호화해 저장합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Toggle("등록한 내 목소리 필터 사용", isOn: $model.preferences.speakerFilterEnabled)
                .disabled(!model.hasSpeakerProfile || model.speakerState != .ready)
        }
        Surface("모델과 라이선스") {
            Text("WhisperKit / Whisper 모델: MIT\nFluidAudio 코드: Apache-2.0\n화자 모델: CC BY 4.0 — FluidInference, pyannote, WeSpeaker")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            Link("음성 모델 출처", destination: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!)
            Link("화자 모델 출처", destination: URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml")!)
        }
    }
    @ViewBuilder private func modelStatus(_ state: LocalModelState) -> some View {
        HStack {
            if state.working { ProgressView().controlSize(.small) }
            Text(state.label).font(.system(size: 12)).foregroundStyle(state == .ready ? AppTheme.accentForeground : .secondary)
        }
        if case .downloading(let progress) = state { ProgressView(value: progress) }
    }
}

private extension LocalModelState {
    var working: Bool {
        switch self { case .downloading, .loading: true; default: false }
    }
}
