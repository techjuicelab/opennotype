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
        return L("\(title), 100만 토큰당 입력 \(Self.usd(price.inputUSDPerMillion)), 출력 \(Self.usd(price.outputUSDPerMillion))", "\(title), per million tokens: input \(Self.usd(price.inputUSDPerMillion)), output \(Self.usd(price.outputUSDPerMillion))")
    }

    private static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))
            .precision(.fractionLength(2...6)))
    }

    static func textChoices(for provider: AIProvider) -> [Self] {
        TextModelCatalog.entries(for: provider).map {
            Self(id: $0.id, title: $0.title + ($0.id == ProviderDefaults.forProvider(provider).textModel ? L(" · 기본", " · Default") : ""), price: $0.price, note: $0.note)
        }
    }
}

/// Curated production models, not an account-specific availability check.
/// Sources and text-token rates are maintained in TextModelCatalog.
enum GroqModelChoices {
    static var transcription: [ProviderModelChoice] { [
        ProviderModelChoice(id: "whisper-large-v3-turbo", title: L("Whisper Large v3 Turbo · 기본", "Whisper Large v3 Turbo · Default")),
        ProviderModelChoice(id: "whisper-large-v3", title: "Whisper Large v3")
    ] }
    static var text: [ProviderModelChoice] { ProviderModelChoice.textChoices(for: .groq) }
}

/// Public OpenRouter catalogue; each price carries its verification date. Account availability is checked on use.
enum OpenRouterModelChoices {
    static var text: [ProviderModelChoice] { ProviderModelChoice.textChoices(for: .openRouter) }
}

struct ProviderModelPicker: View {
    let title: String
    @Binding var selection: String
    let choices: [ProviderModelChoice]
    var isEnabled: Bool = true
    @State private var usesCustomModel: Bool
    @State private var showsModelDetails = false
    private let customTag = "__custom_model__"
    private var selectedChoice: ProviderModelChoice? { choices.first { $0.id == selection } }

    init(_ title: String, selection: Binding<String>, choices: [ProviderModelChoice], isEnabled: Bool = true) {
        self.title = title
        self._selection = selection
        self.choices = choices
        self.isEnabled = isEnabled
        self._usesCustomModel = State(initialValue: !choices.contains { $0.id == selection.wrappedValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title, help: L("기존 추천 목록 또는 직접 입력한 모델 ID를 사용합니다. 목록은 계정별 사용 가능 여부를 보장하지 않습니다. 메뉴 가격은 100만 토큰당 입력/출력 USD 참고 단가이며 실제 비용과 다를 수 있습니다.", "Use a catalog model or enter a model ID. The catalog does not guarantee availability for your account. Menu prices are reference USD input/output rates per million tokens, not actual charges."), state: usesCustomModel && choices.contains(where: { $0.price != nil }) ? L("직접 입력 모델 · 가격 확인 필요", "Custom model · Verify pricing") : nil) {
                Picker(title, selection: Binding(get: { usesCustomModel ? customTag : selection }, set: { value in
                    guard isEnabled else { return }
                    usesCustomModel = value == customTag
                    if !usesCustomModel { selection = value }
                })) {
                    ForEach(choices) { choice in
                        Text(choice.menuTitle).tag(choice.id).accessibilityLabel(choice.accessibilityTitle)
                    }
                    Text(L("직접 입력…", "Enter manually…")).tag(customTag)
                }.pickerStyle(.menu).labelsHidden().frame(width: 240).disabled(!isEnabled)
            }
            if usesCustomModel {
                SettingsRow(L("모델 ID", "Model ID")) {
                    TextField(L("모델 ID", "Model ID"), text: $selection).textFieldStyle(.roundedBorder)
                        .frame(width: 240).disabled(!isEnabled)
                        .accessibilityLabel(L("\(title) ID 직접 입력", "Enter a \(title) ID manually"))
                }
            }
            SettingsRow(L("가격 기준·모델 정보", "Pricing and model details"), help: L("공시 가격·확인일·출처와 모델별 주의를 확인합니다. 실제 공급자·할인·추론 토큰·요청 조건에 따라 비용이 달라질 수 있습니다.", "Check published prices, verification date, source, and model notes. Actual costs depend on the host, discounts, reasoning tokens, and request conditions.")) {
                Button(L("정보 보기", "View details")) { showsModelDetails = true }
            }
        }
        .popover(isPresented: $showsModelDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(AppTypography.sectionTitle)
                Text(selection).font(AppTypography.utility).textSelection(.enabled)
                if let price = selectedChoice?.price {
                    Text(L("100만 토큰당 USD · 입력 / 출력", "USD per million tokens · Input / output")).font(AppTypography.caption)
                    Text(selectedChoice?.menuTitle ?? "").font(AppTypography.body)
                    HStack {
                        Link(price.sourceURL.host == "openrouter.ai" ? L("공시 가격 API", "Published pricing API") : L("공식 가격표", "Official pricing"), destination: price.sourceURL)
                        Text(L("\(price.asOf) 기준", "As of \(price.asOf)")).font(AppTypography.caption)
                    }
                    if price.sourceURL.host == "openrouter.ai", let url = URL(string: "https://openrouter.ai/\(selection)") {
                        Link(L("모델 설명", "Model details"), destination: url)
                    }
                } else {
                    Text(L("가격은 제공자에서 확인해 주세요.", "Check pricing with your provider.")).font(AppTypography.body)
                }
                if let note = selectedChoice?.note { Text(note).font(AppTypography.body) }
                Text(L("목록은 입력·출력 토큰 수가 같을 때의 참고 단가 합계 기준으로 저렴한 순입니다. 실제 공급자·할인·추론 토큰·요청 조건에 따라 비용이 달라질 수 있으며 가격은 변경될 수 있습니다.", "Catalog order uses combined reference rates for equal input and output token counts. Actual charges depend on hosts, discounts, reasoning tokens, and request conditions. Prices may change."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }.padding(AppLayout.panelInset).frame(width: 360)
        }
    }
}
