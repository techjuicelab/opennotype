import SwiftUI
import OpenNoTypeCore

struct ProviderModelChoice: Identifiable {
    let id: String
    let title: String
    var price: TextModelPrice? = nil
    var note: String? = nil
    var sourceURL: URL? = nil
    var checkedAt: String? = nil

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

    static func speechChoices(for provider: AIProvider) -> [Self] {
        SpeechModelCatalog.entries(for: provider).map {
            Self(id: $0.id, title: $0.title + ($0.id == ProviderDefaults.forProvider(provider).transcriptionModel ? L(" · 기본", " · Default") : ""),
                 note: $0.note, sourceURL: $0.sourceURL, checkedAt: $0.asOf)
        }
    }
}

/// Curated production models, not an account-specific availability check.
/// Sources and text-token rates are maintained in TextModelCatalog.
enum GroqModelChoices {
    static var transcription: [ProviderModelChoice] { ProviderModelChoice.speechChoices(for: .groq) }
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
    let contextID: String
    @State private var pickerState: ProviderModelPickerState
    @State private var showsModelDetails = false
    private var selectedChoice: ProviderModelChoice? { choices.first { $0.id == selection } }
    private var hasTokenPricing: Bool { choices.contains { $0.price != nil } }
    private var choiceIDs: [String] { choices.map(\.id) }

    init(_ title: String, selection: Binding<String>, choices: [ProviderModelChoice], isEnabled: Bool = true, contextID: String? = nil) {
        self.title = title
        self._selection = selection
        self.choices = choices
        self.isEnabled = isEnabled
        let context = contextID ?? title
        self.contextID = context
        self._pickerState = State(initialValue: ProviderModelPickerState(selection: selection.wrappedValue,
                                                                        choiceIDs: choices.map(\.id), contextID: context))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title, help: modelSelectionHelp) {
                Picker(title, selection: menuBinding) {
                    ForEach(choices) { choice in
                        Text(choice.menuTitle).tag(ProviderModelMenuSelection.catalogID(choice.id))
                            .accessibilityLabel(choice.accessibilityTitle)
                    }
                    Text(L("직접 입력 (Custom)…", "Custom…")).tag(ProviderModelMenuSelection.custom)
                }.pickerStyle(.menu).labelsHidden().frame(width: 240).disabled(!isEnabled)
            }
            if displayedState.usesCustomModel {
                SettingsRow(L("모델 ID", "Model ID"), state: customState) {
                    HStack(spacing: 8) {
                        TextField(L("모델 ID", "Model ID"), text: customDraftBinding).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity).disabled(!isEnabled)
                            .accessibilityLabel(L("\(title) ID 직접 입력", "Enter a \(title) ID manually"))
                            .onSubmit(applyCustomModel)
                        Button(L("적용", "Apply"), action: applyCustomModel)
                            .disabled(!isEnabled || !displayedState.canApplyCustomModel)
                            .accessibilityLabel(L("\(title) 직접 입력 모델 적용", "Apply the custom \(title) model"))
                    }.frame(width: 240)
                }
            }
            SettingsRow(hasTokenPricing ? L("가격 기준·모델 정보", "Pricing and model details") : L("모델 정보", "Model details"), help: modelDetailsHelp) {
                Button(L("정보 보기", "View details")) { showsModelDetails = true }
            }
        }
        .onChange(of: selection) { _, _ in synchronizeState() }
        .onChange(of: choiceIDs) { _, _ in synchronizeState() }
        .onChange(of: contextID) { _, _ in synchronizeState(); showsModelDetails = false }
        .popover(isPresented: $showsModelDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(AppTypography.sectionTitle)
                Text(L("현재 적용 모델", "Applied model")).font(AppTypography.caption).foregroundStyle(.secondary)
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
                } else if hasTokenPricing {
                    Text(L("가격은 제공자에서 확인해 주세요.", "Check pricing with your provider.")).font(AppTypography.body)
                } else {
                    Text(L("모델 지원 범위와 처리 가격은 제공자에서 확인해 주세요.", "Check model support and pricing with your provider.")).font(AppTypography.body)
                    if let url = selectedChoice?.sourceURL {
                        Link(L("공식 모델 안내", "Official model documentation"), destination: url)
                    }
                    if let checkedAt = selectedChoice?.checkedAt {
                        Text(L("\(checkedAt) 기준", "As of \(checkedAt)")).font(AppTypography.caption)
                    }
                }
                if let note = selectedChoice?.note { Text(note).font(AppTypography.body) }
                if hasTokenPricing {
                    Text(L("목록은 입력·출력 토큰 수가 같을 때의 참고 단가 합계 기준으로 저렴한 순입니다. 실제 공급자·할인·추론 토큰·요청 조건에 따라 비용이 달라질 수 있으며 가격은 변경될 수 있습니다.", "Catalog order uses combined reference rates for equal input and output token counts. Actual charges depend on hosts, discounts, reasoning tokens, and request conditions. Prices may change."))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
            }.padding(AppLayout.panelInset).frame(width: 360)
        }
    }

    private var displayedState: ProviderModelPickerState {
        var state = pickerState
        state.synchronize(selection: selection, choiceIDs: choiceIDs, contextID: contextID)
        return state
    }

    private var menuBinding: Binding<ProviderModelMenuSelection> {
        Binding(get: { displayedState.menuSelection }, set: { value in
            synchronizeState()
            if let id = pickerState.select(value, isEnabled: isEnabled) { selection = id; synchronizeState() }
        })
    }

    private var customDraftBinding: Binding<String> {
        Binding(get: { displayedState.customDraft }, set: { value in
            synchronizeState()
            pickerState.editCustomDraft(value, isEnabled: isEnabled)
        })
    }

    private func synchronizeState() {
        pickerState.synchronize(selection: selection, choiceIDs: choiceIDs, contextID: contextID)
    }

    private func applyCustomModel() {
        synchronizeState()
        if let id = pickerState.applyCustomModel(isEnabled: isEnabled) { selection = id; synchronizeState() }
    }

    private var customState: String? {
        let state = displayedState
        if state.trimmedCustomDraft.isEmpty { return L("모델 ID 입력 필요 · 현재 선택 유지", "Enter a model ID · Current selection kept") }
        if state.hasUnappliedDraft {
            return L("적용 전 · 현재: \(selection.isEmpty ? "없음" : selection)", "Not applied · Current: \(selection.isEmpty ? "None" : selection)")
        }
        if hasTokenPricing, selectedChoice == nil { return L("목록 밖 모델 · 가격 확인 필요", "Model outside catalog · Verify pricing") }
        return nil
    }

    private var modelSelectionHelp: String {
        let common = L("목록에서 선택하거나 마지막 ‘직접 입력 (Custom)…’에서 모델 ID를 편집합니다. 직접 입력은 적용 또는 입력란의 Return을 눌러야 반영됩니다. 목록은 계정별 사용 가능 여부를 보장하지 않습니다.", "Select a catalog model or edit an ID with the final Custom… option. Custom edits apply only with Apply or Return in the field. The catalog does not guarantee availability for your account.")
        return common + (hasTokenPricing
            ? "\n\n" + L("메뉴 가격은 100만 토큰당 입력/출력 USD 참고 단가이며 실제 비용과 다를 수 있습니다.", "Menu prices are reference USD input/output rates per million tokens, not actual charges.")
            : "\n\n" + L("목록에 가격을 표시하지 않습니다. 제공자의 처리 가격과 지원 형식을 확인해 주세요.", "Prices are not shown in this catalog. Check the provider's pricing and supported formats."))
    }

    private var modelDetailsHelp: String {
        hasTokenPricing
            ? L("현재 적용 모델의 공시 가격·확인일·출처와 주의를 확인합니다. 직접 입력 중인 초안에는 아직 적용되지 않습니다. 실제 공급자·할인·추론 토큰·요청 조건에 따라 비용이 달라질 수 있습니다.", "Check the applied model's published prices, verification date, source, and notes. This does not describe an unapplied custom draft. Actual costs depend on the host, discounts, reasoning tokens, and request conditions.")
            : L("현재 적용 모델의 공식 안내·확인일과 지원 범위를 확인합니다. 가격은 제공자에서 확인하며, 목록은 계정 사용 권한이나 정확도를 보장하지 않습니다.", "Check the applied model's documentation, verification date, and supported behavior. Check pricing with the provider. The catalog does not guarantee account access or accuracy.")
    }
}
