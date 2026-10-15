#if DEBUG
import SwiftUI
import OpenNoTypeCore

/// Interactive fixtures only. No AppModel binding, defaults, credentials, audio or provider client.
struct ModelPickerPreviewView: View {
    private enum Role: String, CaseIterable, Identifiable {
        case speech, text, alternative
        var id: String { rawValue }
        var title: String {
            switch self {
            case .speech: L("음성 모델", "Speech model")
            case .text: L("문장 모델", "Text model")
            case .alternative: L("보조 모델", "Alternative model")
            }
        }
    }

    @State private var provider: AIProvider = .openAI
    @State private var models: [String: String] = [:]
    @State private var controlsLocked = false
    @State private var revision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
                AppPageHeader(L("모델 선택 미리보기", "Model picker preview"))
                Label(L("합성 데이터 · 메모리에서만 변경 · API·키·사용자 설정 접근 없음", "Synthetic data · In-memory changes only · No API, credential, or user-setting access"), systemImage: "testtube.2")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                SettingsPanel(L("검증 조건", "Preview controls")) {
                    SettingsRow(L("제공자", "Provider")) {
                        Picker(L("제공자", "Provider"), selection: $provider) {
                            ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                        }.labelsHidden().frame(width: 240)
                    }
                    SettingsRow(L("선택 잠금", "Lock model editing")) {
                        Toggle(L("선택 잠금", "Lock model editing"), isOn: $controlsLocked).labelsHidden().toggleStyle(.switch)
                    }
                    SettingsRow(L("외부 값 변경", "Change owner values"), help: L("저장값이 목록 밖 모델로 바뀌거나 기본값으로 복원될 때 공통 선택기 상태가 따라오는지 확인합니다. 이 값들은 미리보기 메모리에만 있습니다.", "Check how the picker follows owner values changed to an unknown model or restored to defaults. These values exist only in preview memory.")) {
                        Button(L("목록 밖 값", "Unknown models")) { replaceOwnerValues(withUnknownModels: true) }
                        Button(L("기본값", "Defaults")) { replaceOwnerValues(withUnknownModels: false) }
                    }
                }
                ForEach(Role.allCases) { role in
                    SettingsPanel(role.title) {
                        if role == .speech && ProviderDefaults.forProvider(provider).requiresLocalTranscription {
                            SettingsRow(L("음성 인식", "Speech recognition"), help: L("Claude 연결은 로컬 음성 인식을 사용하므로 온라인 음성 모델을 선택하지 않습니다.", "Claude uses local speech recognition, so no online speech model is selected.")) {
                                Text(L("이 Mac에서 인식", "On this Mac")).font(AppTypography.body)
                            }
                        } else {
                            ProviderModelPicker(role.title, selection: modelBinding(for: role),
                                choices: choices(for: role), isEnabled: !controlsLocked,
                                contextID: "preview-\(provider.rawValue)-\(role.rawValue)-\(revision)")
                        }
                        SettingsRow(L("현재 적용값", "Applied value")) {
                            Text(currentModel(for: role).isEmpty ? L("없음", "None") : currentModel(for: role))
                                .font(AppTypography.utility).lineLimit(2).textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(AppLayout.pageInset)
            .frame(maxWidth: AppLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 960, minHeight: 680)
        .background(AppTheme.pageBackground)
        .font(AppTypography.body).buttonStyle(AppActionButtonStyle()).controlSize(.large)
    }

    private func key(_ provider: AIProvider, _ role: Role) -> String { "\(provider.rawValue)-\(role.rawValue)" }

    private func currentModel(for role: Role) -> String {
        models[key(provider, role)] ?? defaultModel(for: provider, role: role)
    }

    private func defaultModel(for provider: AIProvider, role: Role) -> String {
        let defaults = ProviderDefaults.forProvider(provider)
        return role == .speech ? defaults.transcriptionModel : defaults.textModel
    }

    private func choices(for role: Role) -> [ProviderModelChoice] {
        role == .speech ? ProviderModelChoice.speechChoices(for: provider) : ProviderModelChoice.textChoices(for: provider)
    }

    private func modelBinding(for role: Role) -> Binding<String> {
        let expectedProvider = provider
        let expectedRevision = revision
        let modelKey = key(expectedProvider, role)
        return Binding(get: {
            models[modelKey] ?? defaultModel(for: expectedProvider, role: role)
        }, set: { value in
            guard !controlsLocked, provider == expectedProvider, revision == expectedRevision else { return }
            models[modelKey] = value
        })
    }

    private func replaceOwnerValues(withUnknownModels: Bool) {
        for role in Role.allCases {
            models[key(provider, role)] = withUnknownModels
                ? "sample/\(role.rawValue)-model" : defaultModel(for: provider, role: role)
        }
        revision += 1
    }
}
#endif
