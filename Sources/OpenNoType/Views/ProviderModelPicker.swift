import SwiftUI

struct ProviderModelChoice: Identifiable {
    let id: String
    let title: String
}

/// Curated production models, not an account-specific availability check.
/// Source: https://console.groq.com/docs/models (2026-09-09).
enum GroqModelChoices {
    static let transcription = [
        ProviderModelChoice(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo · 기본"),
        ProviderModelChoice(id: "whisper-large-v3", title: "Whisper Large v3")
    ]
    static let text = [
        ProviderModelChoice(id: "openai/gpt-oss-120b", title: "GPT OSS 120B · 기본"),
        ProviderModelChoice(id: "openai/gpt-oss-20b", title: "GPT OSS 20B")
    ]
}

struct ProviderModelPicker: View {
    let title: String
    @Binding var selection: String
    let choices: [ProviderModelChoice]
    @State private var usesCustomModel: Bool
    private let customTag = "__custom_model__"

    init(_ title: String, selection: Binding<String>, choices: [ProviderModelChoice]) {
        self.title = title
        self._selection = selection
        self.choices = choices
        self._usesCustomModel = State(initialValue: !choices.contains { $0.id == selection.wrappedValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: Binding(get: {
                usesCustomModel ? customTag : selection
            }, set: { value in
                usesCustomModel = value == customTag
                if !usesCustomModel { selection = value }
            })) {
                ForEach(choices) { Text($0.title).tag($0.id) }
                Text("직접 입력…").tag(customTag)
            }
            .pickerStyle(.menu)
            if usesCustomModel {
                TextField("모델 ID", text: $selection)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title) ID 직접 입력")
            } else {
                Text(selection).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
