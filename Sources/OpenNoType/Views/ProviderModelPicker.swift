import SwiftUI
import OpenNoTypeCore

struct ProviderModelChoice: Identifiable {
    let id: String
    let title: String
    var price: TextModelPrice? = nil
    var note: String? = nil

    var menuTitle: String {
        guard let price else { return title }
        return "\(title) · \(Self.usd(price.inputUSDPerMillion)) / \(Self.usd(price.outputUSDPerMillion))"
    }

    var accessibilityTitle: String {
        guard let price else { return title }
        return "\(title), 100만 토큰당 입력 \(Self.usd(price.inputUSDPerMillion)), 출력 \(Self.usd(price.outputUSDPerMillion))"
    }

    private static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))
            .precision(.fractionLength(2...6)))
    }

    static func textChoices(for provider: AIProvider) -> [Self] {
        TextModelCatalog.entries(for: provider).map {
            Self(id: $0.id, title: $0.title + ($0.id == ProviderDefaults.forProvider(provider).textModel ? " · 기본" : ""), price: $0.price, note: $0.note)
        }
    }
}

/// Curated production models, not an account-specific availability check.
/// Sources and text-token rates are maintained in TextModelCatalog.
enum GroqModelChoices {
    static let transcription = [
        ProviderModelChoice(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo · 기본"),
        ProviderModelChoice(id: "whisper-large-v3", title: "Whisper Large v3")
    ]
    static let text = ProviderModelChoice.textChoices(for: .groq)
}

/// Public OpenRouter catalogue, checked 2026-10-01; account availability is checked on use.
enum OpenRouterModelChoices {
    static let text = ProviderModelChoice.textChoices(for: .openRouter)
}

struct ProviderModelPicker: View {
    let title: String
    @Binding var selection: String
    let choices: [ProviderModelChoice]
    @State private var usesCustomModel: Bool
    private let customTag = "__custom_model__"
    private var selectedChoice: ProviderModelChoice? { choices.first { $0.id == selection } }

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
                ForEach(choices) { choice in
                    Text(choice.menuTitle).tag(choice.id).accessibilityLabel(choice.accessibilityTitle)
                }
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
            if choices.contains(where: { $0.price != nil }) {
                Text("메뉴 가격: 입력 / 출력 · 100만 토큰당 USD")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let price = selectedChoice?.price {
                    HStack(spacing: 8) {
                        Link(price.sourceURL.host == "openrouter.ai" ? "공시 가격 API" : "공식 가격표", destination: price.sourceURL)
                        if price.sourceURL.host == "openrouter.ai", let modelURL = URL(string: "https://openrouter.ai/\(selection)") {
                            Link("모델 설명", destination: modelURL)
                        }
                        Text("\(price.asOf) 기준")
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("직접 입력한 모델의 가격은 제공자에서 확인해 주세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let note = selectedChoice?.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }
                Text("공시 참고 단가입니다. 실제 공급자·할인·추론 토큰·요청 조건에 따라 비용이 달라질 수 있으며, 가격은 변경될 수 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }
}
