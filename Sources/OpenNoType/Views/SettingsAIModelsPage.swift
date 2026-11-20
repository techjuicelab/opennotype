import SwiftUI
import OpenNoTypeCore

/// AI models by task, provider keys and model tools. Changes to a model are drafts until saved.
struct SettingsAIModelsPage: View {
    @Bindable var model: AppModel
    @State private var expandedCard: String?
    @State private var showsAdditionalRoles = false
    @State private var keyDrafts: [String: String] = [:]
    @State private var showsKeys = false
    @State private var showsCosts = false
    @State private var costTab: CostCardTab = .month
    @State private var dismissedSearchSummary: String?

    private var isEditable: Bool { !model.preferencesRecoveryRequired && !AppLaunch.isPreview }
    private var connectionsEditable: Bool { isEditable && model.startupState != .loading }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            AICostSummaryStrip(model: model,
                               onShowMonth: { costTab = .month; model.openSettings(SettingsDetail.costs) },
                               onShowForecast: { costTab = .forecast; model.openSettings(SettingsDetail.costs) },
                               onShowModels: { model.openSettings(SettingsDetail.text) },
                               onShowKeys: { model.openSettings(SettingsDetail.keys) })
            modelsCard.id("settings-card-models")
            keysCard.id("settings-card-keys")
            AICostDetailsCard(model: model, isExpanded: $showsCosts, tab: $costTab, isEditable: isEditable).id(SettingsDetail.costs.anchor)
            toolsCard
        }
        .onAppear {
            reveal(model.settingsDetail)
            #if DEBUG
            // Design previews can open one card's editor for review.
            if AppLaunch.isPreview, let card = Bundle.main.object(forInfoDictionaryKey: "OpenNoTypePreviewExpandedCard") as? String { expandedCard = card }
            #endif
        }
        .onChange(of: model.settingsDetail) { _, detail in reveal(detail) }
    }

    private func reveal(_ detail: SettingsDetail?) {
        switch detail {
        case .speech: expandedCard = "speech"
        case .text: break
        case .reviewConnection: expandedCard = "review"
        case .keys: showsKeys = true
        case .costs: showsCosts = true
        default: break
        }
    }

    // MARK: - Models by task

    private var modelsCard: some View {
        SettingsCard(icon: "cpu", title: L("기능별 AI 모델", "AI models by task"),
                     subtitle: modelsSubtitle, emphasized: true) {
            Button { model.searchModels() } label: {
                if model.modelSearchInProgress {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("검색 중…", "Checking…")) }
                } else {
                    Label(L("새 모델 검색", "Check models"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(!isEditable || model.modelSearchInProgress)
            .help(L("OpenRouter 공개 목록과, 이미 확인된 키가 있는 제공자의 모델 목록을 가져옵니다. 지금 쓰는 모델은 바뀌지 않습니다.", "Fetches OpenRouter's public list and lists from providers whose key is already checked. Your current models do not change."))
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if model.modelCatalog.newCount > 0 { newCandidatesBanner }
                if let summary = model.modelSearchSummary, summary != dismissedSearchSummary { searchSummaryBar(summary) }
                speechCard.id("settings-card-model-transcription")
                textProviderBar.padding(.top, 6)
                cleanupCard
                taskCard(.translation)
                taskCard(.rewrite)
                taskCard(.prompt)
                reviewCard.id("settings-card-model-review")
                Divider().padding(.top, 4)
                SettingsDisclosure(title: L("추가 역할 보기", "Additional roles"),
                                   summary: L("번역 다듬기 · 검토 개선안", "Refinement · Alternatives"),
                                   isExpanded: $showsAdditionalRoles, indentContent: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        taskCard(.refinement)
                        alternativeCard
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var modelsSubtitle: String {
        let base = L("기능마다 쓰는 모델과 단가를 확인하고 바꿉니다.", "See and change the model and price used for each task.")
        guard let date = model.modelCatalog.lastSearchAt else { return base }
        let when = date.formatted(.dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale))
        return base + L(" · 마지막 검색 \(when)", " · Checked \(when)")
    }

    private var newCandidatesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle").foregroundStyle(AppTheme.info)
            Text(L("새 호환 모델 후보 \(model.modelCatalog.newCount)건이 감지되었습니다. ‘변경’을 눌러 확인·테스트할 수 있습니다.",
                   "\(model.modelCatalog.newCount) new model candidates found. Open ‘Change’ to review and test."))
                .font(AppTypography.caption).foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SettingsLinkButton(L("모두 확인", "Mark seen"), systemImage: "checkmark") { model.acknowledgeNewModels() }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AppTheme.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.info.opacity(0.28), lineWidth: 1))
    }

    private func searchSummaryBar(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: summary.contains(":") ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(summary.contains(":") ? AppTheme.warm : AppTheme.accentForeground)
            Text(summary).font(AppTypography.caption).foregroundStyle(AppTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { dismissedSearchSummary = summary } label: { Image(systemName: "xmark") }
                .buttonStyle(AppIconButtonStyle(size: 22, bordered: false))
                .accessibilityLabel(L("닫기", "Dismiss"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Prices and status

    /// Catalog prices first, then prices reported by a provider's public model list.
    private func textPrice(_ provider: AIProvider, _ id: String) -> (input: Double, output: Double, source: String)? {
        if let price = TextModelCatalog.entry(id: id, provider: provider)?.price {
            return (price.inputUSDPerMillion, price.outputUSDPerMillion, "catalog")
        }
        if let found = model.modelCatalog.models.first(where: { $0.provider == provider && $0.modelID == id }),
           let input = found.inputUSDPerMillion, let output = found.outputUSDPerMillion {
            return (input, output, "list")
        }
        return nil
    }

    private func textRate(_ provider: AIProvider, _ id: String) -> String {
        guard let price = textPrice(provider, id) else { return L("단가 미확인", "Price unknown") }
        return L("입력 \(TextRateSummary.usd(price.input)) · 출력 \(TextRateSummary.usd(price.output)) / 1M",
                 "In \(TextRateSummary.usd(price.input)) · Out \(TextRateSummary.usd(price.output)) / 1M")
    }

    /// Compatibility of a saved model: passed or failed tests, or untested when outside the catalog.
    private func compatibilityBadges(_ provider: AIProvider, _ id: String, _ task: CompatibilityTask) -> (badges: [ModelBadge], failure: String?) {
        if let result = model.compatibilityResult(provider: provider, model: id, task: task) {
            return result.passed ? ([.init(kind: .accent, text: L("호환 확인", "Compatible"))], nil)
                : ([.init(kind: .error, text: L("호환 실패", "Incompatible"))], result.failure)
        }
        if TextModelCatalog.entry(id: id, provider: provider) == nil {
            return ([.init(kind: .warning, text: L("호환성 미확인", "Unverified"))], nil)
        }
        return ([], nil)
    }

    private func textChoices(_ provider: AIProvider) -> [ProviderModelChoice] {
        let catalog = ProviderModelChoice.textChoices(for: provider)
        let known = Set(catalog.map(\.id))
        let discovered = model.modelCatalog.models(for: provider, kind: .text).filter { !known.contains($0.modelID) }.map { found in
            ProviderModelChoice(id: found.modelID, title: found.name ?? found.modelID,
                                price: found.inputUSDPerMillion.flatMap { input in found.outputUSDPerMillion.map { output in
                                    TextModelPrice(inputUSDPerMillion: input, outputUSDPerMillion: output,
                                                   asOf: found.firstSeenAt.formatted(.iso8601.year().month().day()),
                                                   sourceURL: URL(string: "https://openrouter.ai/api/v1/models")!) } })
        }
        return catalog + discovered
    }

    private func newIDs(_ provider: AIProvider, kind: DiscoveredModel.Kind) -> Set<String> {
        Set(model.modelCatalog.models(for: provider, kind: kind).filter(\.isNew).map(\.modelID))
    }

    private func compatibilityHooks(_ provider: AIProvider, _ task: CompatibilityTask) -> ModelChoiceEditor.Compatibility {
        ModelChoiceEditor.Compatibility(
            canTest: connectionsEditable && model.startupState == .ready && !model.isBusy && (model.providerKeyPresence[provider] == true || model.loadedKey(provider) != nil),
            result: { model.compatibilityResult(provider: provider, model: $0, task: task) },
            isTesting: { model.isTestingCompatibility(provider: provider, model: $0, task: task) },
            run: { id in model.testCompatibility(provider: provider, model: id, task: task); model.markModelSeen(provider: provider, id: id) })
    }

    // Speech recognition

    private var speechUsesLocal: Bool { model.preferences.needsLocal }

    private var speechCard: some View {
        let provider = model.preferences.provider
        let local = speechUsesLocal
        return ModelFunctionCard(
            title: L("음성 인식", "Speech recognition"),
            description: L("녹음한 음성을 글자로 옮깁니다.", "Turns your recording into text."),
            modelID: local ? model.preferences.localSpeechModel.displayName : model.preferences.transcriptionModel,
            providerBadge: local ? L("이 Mac", "This Mac") : provider.displayName,
            rateSummary: local ? L("API 비용 없음", "No API cost") : SpeechRateSummary.text(provider: provider, model: model.preferences.transcriptionModel),
            rateUnknown: !local && UsagePricing.transcriptionRate(provider: provider, model: model.preferences.transcriptionModel) == nil,
            statusBadges: speechBadges,
            isExpanded: expandedCard == "speech",
            isEditable: connectionsEditable,
            onToggleExpand: { toggle("speech") }
        ) {
            SpeechModelEditor(model: model, isEditable: connectionsEditable) { expandedCard = nil }
        }
    }

    private var speechBadges: [ModelBadge] {
        var badges: [ModelBadge] = []
        if model.preferences.usesFastDictation {
            badges.append(.init(kind: .info, text: L("빠른 로컬 사용 중", "Quick local in use")))
        }
        if speechUsesLocal {
            if model.localState != .ready { badges.append(.init(kind: .warning, text: model.localState.label)) }
        } else if model.providerKeyPresence[model.preferences.provider] == false {
            badges.append(.init(kind: .warning, text: L("API 키 필요", "Key needed")))
        }
        let isDefault = !speechUsesLocal && (model.preferences.transcriptionModels[model.preferences.provider.rawValue] ?? "").isEmpty
        badges.insert(.init(kind: isDefault ? .neutral : .accent, text: isDefault ? L("기본값", "Default") : L("사용자 지정", "Custom")), at: 0)
        return badges
    }

    // Text provider shared by text tasks

    private var textProviderBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L("문장 처리 제공자", "Text provider")).font(AppTypography.body.weight(.medium))
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(AIProvider.allCases) { provider in
                        ProviderPill(title: provider.displayName, presence: model.providerKeyPresence[provider],
                                     selected: model.preferences.effectiveTextProvider == provider) {
                            guard connectionsEditable else { return }
                            model.preferences.textProvider = provider
                            model.loadTextKey()
                            if provider == model.preferences.provider { model.loadKey() }
                        }
                        .disabled(!connectionsEditable)
                    }
                }
            }
            Text(L("받아쓰기 정리·번역·선택 수정·프롬프트는 이 제공자의 모델과 API 키를 사용합니다.", "Cleanup, translation, edits and prompts use this provider's models and API key."))
                .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var cleanupCard: some View {
        let provider = model.preferences.effectiveTextProvider
        let isDefault = (model.preferences.textModels[provider.rawValue] ?? "").isEmpty
        var badges: [ModelBadge] = [.init(kind: isDefault ? .neutral : .accent, text: isDefault ? L("기본값", "Default") : L("사용자 지정", "Custom"))]
        if model.preferences.usesFastDictation { badges.append(.init(kind: .neutral, text: L("빠른 로컬 중 미적용", "Paused · Quick local"))) }
        if model.providerKeyPresence[provider] == false { badges.append(.init(kind: .warning, text: L("API 키 필요", "Key needed"))) }
        let compatibility = compatibilityBadges(provider, model.preferences.textModel, .cleanup)
        badges += compatibility.badges
        let newCount = newIDs(provider, kind: .text).count
        if newCount > 0 { badges.append(.init(kind: .accent, text: L("새 후보 \(newCount)", "\(newCount) new"))) }
        return ModelFunctionCard(
            title: L("받아쓰기 정리", "Dictation cleanup"),
            description: L("말실수·반복을 정리하고 말투를 맞춥니다. 따로 정하지 않은 문장 기능의 기본 모델입니다.", "Cleans up slips and repeats and applies your tone. Other text tasks use it unless you choose otherwise."),
            modelID: model.preferences.textModel,
            providerBadge: provider.displayName,
            rateSummary: textRate(provider, model.preferences.textModel),
            rateUnknown: textPrice(provider, model.preferences.textModel) == nil,
            failureSummary: compatibility.failure,
            statusBadges: badges,
            isExpanded: expandedCard == "cleanup",
            isEditable: connectionsEditable,
            onToggleExpand: { toggle("cleanup") }
        ) {
            ModelChoiceEditor(
                choices: textChoices(provider),
                current: model.preferences.textModel,
                defaultID: ProviderDefaults.forProvider(provider).textModel,
                rate: { textRate(provider, $0) },
                isEditable: connectionsEditable,
                contextID: "text-\(provider.rawValue)",
                newIDs: newIDs(provider, kind: .text),
                curatedCount: ProviderModelChoice.textChoices(for: provider).count,
                compatibility: compatibilityHooks(provider, .cleanup),
                onSave: { id in
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.markModelSeen(provider: provider, id: id)
                    model.preferences.textModels[provider.rawValue] = id
                    expandedCard = nil
                },
                onReset: {
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.preferences.textModels.removeValue(forKey: provider.rawValue)
                },
                onCancel: { expandedCard = nil })
        }
    }

    private func taskCard(_ task: TextTask) -> some View {
        let provider = model.preferences.effectiveTextProvider
        let own = model.preferences.hasOwnModel(task)
        let current = model.preferences.textModel(forTask: task)
        let parentTitle = task == .refinement ? L("번역 따름", "Follows translation") : L("받아쓰기 정리 따름", "Follows cleanup")
        let parentModel = task == .refinement ? model.preferences.textModel(forTask: .translation) : model.preferences.textModel
        var badges: [ModelBadge] = [.init(kind: own ? .accent : .neutral, text: own ? L("사용자 지정", "Custom") : parentTitle)]
        if task == .refinement && !model.preferences.translationRefinementEnabled {
            badges.append(.init(kind: .neutral, text: L("옵션 꺼짐", "Option off")))
        }
        let compatibility: (badges: [ModelBadge], failure: String?) = own ? compatibilityBadges(provider, current, CompatibilityTask(task)) : ([], nil)
        badges += compatibility.badges
        return ModelFunctionCard(
            title: task.title,
            description: task.detail,
            modelID: current,
            providerBadge: provider.displayName,
            rateSummary: textRate(provider, current),
            rateUnknown: textPrice(provider, current) == nil,
            compact: !own,
            compactDetail: own ? nil : parentModel,
            failureSummary: compatibility.failure,
            statusBadges: badges,
            isExpanded: expandedCard == task.rawValue,
            isEditable: connectionsEditable,
            onToggleExpand: { toggle(task.rawValue) }
        ) {
            ModelChoiceEditor(
                choices: textChoices(provider),
                current: current,
                defaultID: parentModel,
                defaultTitle: task == .refinement ? L("번역과 같게", "Same as translation") : L("받아쓰기 정리와 같게", "Same as cleanup"),
                rate: { textRate(provider, $0) },
                isEditable: connectionsEditable,
                contextID: "\(task.rawValue)-\(provider.rawValue)",
                resetEnabled: own,
                newIDs: newIDs(provider, kind: .text),
                curatedCount: ProviderModelChoice.textChoices(for: provider).count,
                compatibility: compatibilityHooks(provider, CompatibilityTask(task)),
                onSave: { id in
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.markModelSeen(provider: provider, id: id)
                    model.preferences.taskModels[provider.rawValue, default: [:]][task.rawValue] = id
                    expandedCard = nil
                },
                onReset: {
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.preferences.taskModels[provider.rawValue]?.removeValue(forKey: task.rawValue)
                },
                onCancel: { expandedCard = nil })
        }
    }

    private var alternativeCard: some View {
        let provider = model.preferences.effectiveTextProvider
        let follows = (model.preferences.improvementModels[provider.rawValue] ?? "").isEmpty
        return ModelFunctionCard(
            title: L("검토 개선안", "Review alternatives"),
            description: L("검토에서 주의 신호가 나오거나 직접 요청할 때 대안 문장 하나를 만듭니다.", "Writes one alternative when review flags a concern or you ask for one."),
            modelID: model.preferences.improvementModel,
            providerBadge: provider.displayName,
            rateSummary: textRate(provider, model.preferences.improvementModel),
            rateUnknown: textPrice(provider, model.preferences.improvementModel) == nil,
            compact: follows,
            compactDetail: follows ? model.preferences.textModel : nil,
            failureSummary: follows ? nil : compatibilityBadges(provider, model.preferences.improvementModel, .alternative).failure,
            statusBadges: [.init(kind: follows ? .neutral : .accent, text: follows ? L("받아쓰기 정리 따름", "Follows cleanup") : L("사용자 지정", "Custom"))]
                + (follows ? [] : compatibilityBadges(provider, model.preferences.improvementModel, .alternative).badges),
            isExpanded: expandedCard == "alternative",
            isEditable: connectionsEditable,
            onToggleExpand: { toggle("alternative") }
        ) {
            ModelChoiceEditor(
                choices: textChoices(provider),
                current: model.preferences.improvementModel,
                defaultID: model.preferences.textModel,
                defaultTitle: L("받아쓰기 정리와 같게", "Same as cleanup"),
                rate: { textRate(provider, $0) },
                isEditable: connectionsEditable,
                contextID: "alternative-\(provider.rawValue)",
                resetEnabled: !follows,
                newIDs: newIDs(provider, kind: .text),
                curatedCount: ProviderModelChoice.textChoices(for: provider).count,
                compatibility: compatibilityHooks(provider, .alternative),
                onSave: { id in
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.preferences.improvementModels[provider.rawValue] = id
                    expandedCard = nil
                },
                onReset: {
                    guard connectionsEditable, model.preferences.effectiveTextProvider == provider else { return }
                    model.preferences.improvementModels.removeValue(forKey: provider.rawValue)
                },
                onCancel: { expandedCard = nil })
        }
    }

    // Text review (Jev)

    private var reviewCard: some View {
        let decision = model.preferences.decisionProvider
        var badges: [ModelBadge] = [.init(kind: .neutral, text: L("고정 모델", "Fixed model"))]
        if let issue = reviewConnectionIssue { badges.append(.init(kind: .warning, text: issue)) }
        else if model.preferences.decisionReviewMode == .off { badges.append(.init(kind: .neutral, text: L("자동 검토 꺼짐", "Auto review off"))) }
        return ModelFunctionCard(
            title: L("문장 검토 (Jev)", "Text review (Jev)"),
            description: L("정리·번역 결과의 의미 변경·누락·표기를 점검합니다. 검토 방식은 받아쓰기·번역 탭에서 정합니다.", "Checks results for changed meaning, omissions and spelling. Choose the review mode in Dictation."),
            modelID: decision.model,
            providerBadge: decision == .typeSafe ? "TypeSafe" : L("OpenRouter 키", "OpenRouter key"),
            rateSummary: decision == .typeSafe ? L("입력 $0.042 / 1M · 출력 무료", "Input $0.042 / 1M · Output free") : L("요청별 보고 금액", "Reported per request"),
            statusBadges: badges,
            isExpanded: expandedCard == "review",
            isEditable: connectionsEditable,
            onToggleExpand: { toggle("review") }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsStackedItem(L("연결 방식", "Connection"),
                                    detail: decision == .typeSafe
                                        ? L("TypeSafe Jev API에 직접 연결합니다. 키는 아래 ‘제공자와 API 키’에서 저장합니다.", "Connects directly to the TypeSafe Jev API. Save its key in Providers and API keys below.")
                                        : L("저장된 OpenRouter 키를 재사용합니다. 문장 처리 제공자와 상관없이 사용할 수 있습니다.", "Reuses your saved OpenRouter key, whichever provider processes text."),
                                    help: L("Jev는 검토 전용 프로토콜에 맞춘 고정 모델이라 모델 ID를 바꿀 수 없습니다.", "Jev is a fixed model tied to its review protocol, so its model ID cannot be changed.")) {
                    SettingsSegmentedPicker(title: L("연결 방식", "Connection"), selection: $model.preferences.decisionProvider,
                                            options: [DecisionProvider.openRouter, .typeSafe],
                                            label: { $0 == .openRouter ? L("OpenRouter 키 재사용", "Reuse OpenRouter key") : L("Jev API 직접 연결", "Direct Jev API") },
                                            isEnabled: connectionsEditable)
                    .onChange(of: model.preferences.decisionProvider) { _, provider in if provider == .typeSafe { model.loadDecisionKey() } }
                }
                HStack(spacing: 10) {
                    Button(model.decisionConnectionTestInProgress ? L("확인 중…", "Testing…") : L("연결 테스트", "Test connection"), systemImage: "checkmark.seal") {
                        model.testDecisionConnection()
                    }
                    .disabled(!connectionsEditable || model.isBusy || model.keyOperationInProgress)
                    Text(model.decisionConnectionTestStatus ?? L("합성 문장 1회 · 소액 API 비용 발생", "One synthetic request · Small API charge"))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L("닫기", "Close")) { expandedCard = nil }
                }
            }
        }
    }

    private var reviewConnectionIssue: String? {
        if model.preferences.decisionProvider == .openRouter && model.preferences.effectiveTextProvider != .openRouter
            && model.providerKeyPresence[.openRouter] == false {
            return L("OpenRouter 키 필요", "OpenRouter key needed")
        }
        if model.preferences.decisionProvider == .typeSafe && !model.decisionKeySaved && !model.decisionKeyOperationInProgress {
            return L("Jev 키 필요", "Jev key needed")
        }
        return nil
    }

    // MARK: - Providers and keys

    private var keysCard: some View {
        SettingsCard(icon: "key", title: L("제공자와 API 키", "Providers and API keys"),
                     subtitle: L("키는 이 Mac의 Keychain에 저장하며, 직접 저장해야 적용됩니다.", "Keys are stored in this Mac's Keychain and apply only after you save them."),
                     help: keyHelp) {
            Button { showsKeys.toggle() } label: {
                Label(showsKeys ? L("접기", "Collapse") : L("키 관리", "Manage keys"), systemImage: showsKeys ? "chevron.up" : "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
            }
        } content: {
            if showsKeys || missingKeyInUse {
                SettingsRows {
                    ForEach(AIProvider.allCases) { provider in providerKeyRow(provider) }
                    jevKeyRow
                    HStack(spacing: 4) {
                        Text(L("키 발급:", "Get a key:")).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                        Link("OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        Text("·").foregroundStyle(AppTheme.textSecondary)
                        Link("OpenRouter", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                        Text("·").foregroundStyle(AppTheme.textSecondary)
                        Link(L("Groq 안내", "Groq guide"), destination: URL(string: "https://console.groq.com/docs/quickstart")!)
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(InlineLinkStyle())
                    .padding(.vertical, 10)
                }
            } else {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(AIProvider.allCases) { provider in
                        ProviderPill(title: provider.displayName, presence: model.providerKeyPresence[provider], selected: false) { showsKeys = true }
                    }
                    ProviderPill(title: "TypeSafe", presence: model.preferences.decisionProvider == .typeSafe ? model.decisionKeySaved : nil, selected: false) { showsKeys = true }
                }
            }
        }
    }

    /// A key a current task needs is known to be missing; the list opens so it can be entered.
    private var missingKeyInUse: Bool {
        let p = model.preferences
        if !p.needsLocal, model.providerKeyPresence[p.provider] == false { return true }
        if !p.usesFastDictation, model.providerKeyPresence[p.effectiveTextProvider] == false { return true }
        return false
    }

    private func providerKeyRow(_ provider: AIProvider) -> some View {
        let presence = model.providerKeyPresence[provider]
        let busy = model.keyOperationsInProgress.contains(provider)
        let draft = Binding(get: { keyDrafts[provider.rawValue] ?? "" }, set: { keyDrafts[provider.rawValue] = $0 })
        let trimmed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsItem(provider.displayName, detail: keyUsage(provider), state: busy ? .neutral(L("Keychain 확인 중…", "Checking Keychain…")) : nil) {
            keyBadge(presence)
            SecureField(presence == true ? L("새 키로 바꾸기", "Replace key") : L("API 키", "API key"), text: draft)
                .textFieldStyle(.roundedBorder).frame(minWidth: 130, idealWidth: 168, maxWidth: 190)
                .disabled(!connectionsEditable || busy)
            if trimmed.isEmpty && presence == nil {
                Button(L("키 확인", "Check key")) { model.checkProviderKey(provider) }
                    .disabled(!connectionsEditable || busy)
                    .help(L("저장된 키가 있는지 Keychain에서 읽습니다. 승인 창이 나타날 수 있습니다.", "Reads Keychain to see whether a key is saved. An approval dialog may appear."))
            } else if trimmed.isEmpty && presence == true {
                Button(L("삭제", "Delete"), role: .destructive) { model.storeProviderKey(provider, value: "") }
                    .disabled(!connectionsEditable || busy)
            } else {
                Button(L("저장", "Save")) {
                    model.storeProviderKey(provider, value: trimmed)
                    keyDrafts[provider.rawValue] = ""
                }
                .buttonStyle(AppActionButtonStyle(primary: true))
                .disabled(!connectionsEditable || busy || trimmed.isEmpty)
            }
        }
    }

    private var jevKeyRow: some View {
        let direct = model.preferences.decisionProvider == .typeSafe
        let trimmed = model.decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsItem("TypeSafe · Jev", detail: L("문장 검토를 Jev API에 직접 연결할 때 사용합니다.", "Used when text review connects directly to the Jev API."),
                            state: !direct ? .neutral(L("현재 OpenRouter 키 재사용 중 · 직접 연결을 고르면 사용", "Currently reusing OpenRouter · Used with direct connection"))
                                : SettingsItemState.from(model.decisionKeyStatus)) {
            keyBadge(direct ? (model.decisionKeyOperationInProgress ? nil : model.decisionKeySaved) : nil)
            SecureField(L("Jev API 키", "Jev API key"), text: $model.decisionAPIKeyDraft)
                .textFieldStyle(.roundedBorder).frame(minWidth: 130, idealWidth: 168, maxWidth: 190)
                .disabled(!connectionsEditable || !direct || model.decisionKeyOperationInProgress)
            Button(trimmed.isEmpty && model.decisionKeySaved ? L("삭제", "Delete") : L("저장", "Save"),
                   role: trimmed.isEmpty && model.decisionKeySaved ? .destructive : nil) { model.saveDecisionKey() }
                .disabled(!connectionsEditable || !direct || model.decisionKeyOperationInProgress || (trimmed.isEmpty && !model.decisionKeySaved) || !model.decisionKeyDraftIsChanged)
        }
    }

    @ViewBuilder private func keyBadge(_ presence: Bool?) -> some View {
        switch presence {
        case .some(true): StatusBadge(kind: .accent, text: L("저장됨", "Saved"), systemImage: "checkmark")
        case .some(false): StatusBadge(kind: .warning, text: L("없음", "None"))
        case .none: StatusBadge(kind: .neutral, text: L("확인 전", "Not checked"))
        }
    }

    private func keyUsage(_ provider: AIProvider) -> String {
        var uses: [String] = []
        if !model.preferences.needsLocal && model.preferences.provider == provider { uses.append(L("음성 인식", "Speech")) }
        if model.preferences.effectiveTextProvider == provider { uses.append(L("문장 처리", "Text")) }
        if provider == .openRouter && model.preferences.decisionProvider == .openRouter { uses.append(L("Jev 검토", "Jev review")) }
        return uses.isEmpty ? L("현재 사용하지 않음", "Not used now") : L("사용 중: ", "Used for: ") + uses.joined(separator: " · ")
    }

    private var keyHelp: String { L("서비스별 API 키는 Keychain에 명시 저장합니다. 저장됨과 연결 성공은 다릅니다. 제공자를 바꿔도 다른 키·모델을 지우거나 복사하지 않습니다. ‘확인 전’은 이번 실행에서 아직 읽지 않았다는 뜻이며, 확인할 때 Keychain 승인 창이 나타날 수 있습니다. 앱 구독과 API 비용은 별개입니다.", "Each service's API key is saved explicitly in Keychain. Saved is not the same as connected. Switching providers neither deletes nor copies other keys or models. Not checked means the key has not been read in this session; checking may show a Keychain approval dialog. App subscriptions and API charges are separate.") }

    // MARK: - Tools

    private var toolsCard: some View {
        SettingsCard(icon: "scalemass", title: L("모델 비교 도구", "Model comparison"),
                     subtitle: L("같은 입력으로 모델 결과를 나란히 비교합니다.", "Compares model results on the same input.")) {
            SettingsRows {
                SettingsItem(L("음성 모델 비교", "Compare speech models"),
                             detail: L("내려받은 로컬 모델로 같은 음성을 비교합니다. API 요청 없음.", "Compares downloaded local models on the same audio. No API requests.")) {
                    Button(L("비교 도구 열기…", "Open comparison…")) { model.openSettings(SettingsDetail.speechComparison) }
                }
                SettingsItem(L("문장 모델 비교", "Compare text models"),
                             detail: L("승인한 문장으로 모델을 비교합니다. 실행 시 API 요청·비용 발생.", "Compares models on approved text. Running adds API requests and charges.")) {
                    Button(L("비교 도구 열기…", "Open comparison…")) { model.openSettings(SettingsDetail.comparison) }
                        .disabled(!connectionsEditable)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        expandedCard = expandedCard == id ? nil : id
    }
}

// MARK: - Speech editor

private struct SpeechModelEditor: View {
    @Bindable var model: AppModel
    let isEditable: Bool
    let onClose: () -> Void

    private enum Location: String, Identifiable, CaseIterable { case local, online; var id: String { rawValue } }

    var body: some View {
        let provider = model.preferences.provider
        VStack(alignment: .leading, spacing: 12) {
            SettingsStackedItem(L("인식 위치", "Where speech is recognized"),
                                detail: provider == .anthropic ? L("Claude를 쓰면 음성은 이 Mac에서 인식합니다.", "With Claude, speech is recognized on this Mac.") : nil) {
                SettingsSegmentedPicker(title: L("인식 위치", "Where speech is recognized"),
                                        selection: Binding(get: { model.preferences.needsLocal ? Location.local : .online },
                                                           set: { value in
                                                               guard isEditable, model.preferences.provider != .anthropic else { return }
                                                               model.preferences.useLocalTranscription = value == .local
                                                               if value == .online { model.loadKey() }
                                                           }),
                                        options: Location.allCases,
                                        label: { $0 == .local ? L("이 Mac에서", "On this Mac") : L("온라인", "Online") },
                                        isEnabled: isEditable && provider != .anthropic)
            }
            if model.preferences.needsLocal {
                localEditor
            } else {
                SettingsStackedItem(L("음성 제공자", "Speech provider")) {
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(AIProvider.allCases.filter { $0 != .anthropic }) { option in
                            ProviderPill(title: option.displayName, presence: model.providerKeyPresence[option], selected: provider == option) {
                                guard isEditable else { return }
                                model.preferences.provider = option
                                model.loadKey(); model.loadTextKey()
                            }
                            .disabled(!isEditable)
                        }
                    }
                }
                ModelChoiceEditor(
                    choices: ProviderModelChoice.speechChoices(for: provider) + model.modelCatalog.models(for: provider, kind: .speech)
                        .filter { found in !SpeechModelCatalog.entries(for: provider).contains { $0.id == found.modelID } }
                        .map { ProviderModelChoice(id: $0.modelID, title: $0.name ?? $0.modelID) },
                    current: model.preferences.transcriptionModel,
                    defaultID: ProviderDefaults.forProvider(provider).transcriptionModel,
                    rate: { SpeechRateSummary.text(provider: provider, model: $0) },
                    isEditable: isEditable,
                    contextID: "speech-\(provider.rawValue)",
                    newIDs: Set(model.modelCatalog.models(for: provider, kind: .speech).filter(\.isNew).map(\.modelID)),
                    curatedCount: ProviderModelChoice.speechChoices(for: provider).count,
                    onSave: { id in
                        model.markModelSeen(provider: provider, id: id)
                        guard isEditable, model.preferences.provider == provider else { return }
                        model.preferences.transcriptionModels[provider.rawValue] = id
                        onClose()
                    },
                    onReset: {
                        guard isEditable, model.preferences.provider == provider else { return }
                        model.preferences.transcriptionModels.removeValue(forKey: provider.rawValue)
                    },
                    onCancel: onClose)
            }
        }
    }

    private var localEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("이 Mac의 모델", "Model on this Mac")).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(LocalSpeechModel.allCases) { option in
                    ModelChip(title: option.displayName, rateText: L("API 비용 없음", "No API cost"),
                              isSelected: model.preferences.localSpeechModel == option,
                              isDefault: option == Preferences().localSpeechModel) {
                        guard isEditable, !model.isBusy else { return }
                        model.preferences.localSpeechModel = option
                    }
                    .disabled(!isEditable || model.isBusy)
                }
            }
            HStack(spacing: 10) {
                if model.localState == .ready {
                    Label(L("준비됨", "Ready"), systemImage: "checkmark.circle.fill")
                        .font(AppTypography.caption.weight(.medium)).foregroundStyle(AppTheme.accentForeground)
                } else if case .downloading = model.localState {
                    Button(L("준비 취소", "Cancel setup")) { model.cancelLocalPreparation() }.disabled(!isEditable)
                } else if model.localState == .loading {
                    Button(L("준비 취소", "Cancel setup")) { model.cancelLocalPreparation() }.disabled(!isEditable)
                } else {
                    Button(L("다운로드·준비", "Download / prepare"), action: model.prepareLocal)
                        .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!isEditable || model.isBusy)
                }
                Text(model.localState.label).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 0)
                Button(L("파일·메모리 관리", "Files and memory"), systemImage: "arrow.up.right") {
                    model.settingsDetail = nil; model.page = .voice
                }
                Button(L("닫기", "Close"), action: onClose)
            }
            if case .downloading(let progress) = model.localState {
                ProgressView(value: min(1, max(0, progress)))
            }
        }
    }
}

// MARK: - Shared model editing

/// Picks a model from the catalog, a searched list or a typed ID. Nothing changes until Save.
struct ModelChoiceEditor: View {
    struct Compatibility {
        let canTest: Bool
        let result: (String) -> ModelCompatibilityResult?
        let isTesting: (String) -> Bool
        let run: (String) -> Void
    }
    enum Filter: String, CaseIterable, Identifiable { case curated, new, all; var id: String { rawValue } }

    let choices: [ProviderModelChoice]
    let current: String
    let defaultID: String
    var defaultTitle: String?
    let rate: (String) -> String
    let isEditable: Bool
    let contextID: String
    var resetEnabled: Bool?
    var newIDs: Set<String> = []
    /// Built-in catalog entries come first in `choices`; the rest came from a model search.
    var curatedCount: Int?
    var compatibility: Compatibility?
    let onSave: (String) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    @State private var draft = ""
    @State private var loadedContext = ""
    @State private var filter: Filter = .curated
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isCatalogModel: Bool { choices.contains { $0.id == trimmed } }
    private var visibleChoices: [ProviderModelChoice] {
        let base: [ProviderModelChoice]
        switch filter {
        case .curated: base = Array(choices.prefix(curatedCount ?? choices.count))
        case .new: base = choices.filter { newIDs.contains($0.id) }
        case .all: base = choices
        }
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = text.isEmpty ? base : base.filter { $0.id.lowercased().contains(text) || $0.title.lowercased().contains(text) }
        return Array(filtered.prefix(60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !choices.isEmpty {
                HStack(spacing: 6) {
                    Text(L("사용 가능한 모델", "Available models")).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 8)
                    if choices.count > (curatedCount ?? choices.count) || choices.count > 8 {
                        FilterPillButton(title: L("추천", "Curated"), selected: filter == .curated) { filter = .curated }
                        if !newIDs.isEmpty {
                            FilterPillButton(title: L("새 후보", "New"), count: newIDs.count, selected: filter == .new) { filter = .new }
                        }
                        FilterPillButton(title: L("전체", "All"), count: choices.count, selected: filter == .all) { filter = .all }
                        TextField(L("모델 검색…", "Filter…"), text: $query).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                }
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(visibleChoices) { choice in
                        ModelChip(title: choice.id, rateText: rate(choice.id), isSelected: trimmed == choice.id,
                                  isNew: newIDs.contains(choice.id),
                                  isVerified: compatibility?.result(choice.id)?.passed == true,
                                  isDefault: choice.id == defaultID) {
                            guard isEditable else { return }
                            draft = choice.id
                        }
                        .disabled(!isEditable)
                        .help(choice.note ?? choice.title)
                    }
                }
                if visibleChoices.isEmpty {
                    Text(L("조건에 맞는 모델이 없습니다.", "No models match.")).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("적용할 모델 ID", "Model ID to use")).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                TextField(L("모델 ID", "Model ID"), text: $draft)
                    .textFieldStyle(.roundedBorder).font(AppTypography.utility)
                    .disabled(!isEditable)
                    .onSubmit { if canSave { onSave(trimmed) } }
                Text(isCatalogModel || trimmed.isEmpty
                     ? L("목록에서 고르거나 새 모델 ID를 직접 입력할 수 있습니다.", "Choose from the list or type a new model ID.")
                     : L("목록에 없는 모델입니다. 저장 전에 호환성 테스트를 권장합니다.", "Not in the list. Testing compatibility before saving is recommended."))
                    .font(AppTypography.caption).foregroundStyle(isCatalogModel || trimmed.isEmpty ? AppTheme.textSecondary : AppTheme.warm)
                if let choice = choices.first(where: { $0.id == trimmed }) { sourceLine(choice) }
            }
            if let note = choices.first(where: { $0.id == trimmed })?.note {
                Label(note, systemImage: "info.circle")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
            }
            if let compatibility, !trimmed.isEmpty { resultBox(compatibility) }
            HStack(spacing: 8) {
                if let compatibility {
                    Button(L("호환성 테스트", "Test compatibility"), systemImage: "flask") { compatibility.run(trimmed) }
                        .disabled(!isEditable || trimmed.isEmpty || !compatibility.canTest || compatibility.isTesting(trimmed))
                        .help(compatibility.canTest
                              ? L("짧은 합성 문장 1회 전송 · 소액 API 비용 발생 · 기록에 저장 안 함", "Sends one synthetic text · Small API charge · Not saved to history")
                              : L("먼저 이 제공자의 API 키를 저장하거나 확인하세요.", "Save or check an API key for this provider first."))
                }
                Button(defaultTitle ?? L("기본값 복원", "Reset default")) { guard isEditable else { return }; onReset(); draft = defaultID }
                    .disabled(!isEditable || !(resetEnabled ?? (current != defaultID)))
                Spacer(minLength: 0)
                Button(L("취소", "Cancel")) { draft = current; onCancel() }
                Button(L("모델 저장", "Save model"), systemImage: "checkmark") { onSave(trimmed) }
                    .buttonStyle(AppActionButtonStyle(primary: true))
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { sync() }
        .onChange(of: contextID) { _, _ in sync() }
    }

    @ViewBuilder private func resultBox(_ compatibility: Compatibility) -> some View {
        let dark = colorScheme == .dark
        if compatibility.isTesting(trimmed) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("합성 문장으로 호환성을 확인하는 중…", "Testing compatibility with synthetic text…")).font(AppTypography.caption)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.separator, lineWidth: 1))
        } else if let result = compatibility.result(trimmed) {
            let tint = result.passed ? AppTheme.accent : AppTheme.destructive
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.passed ? AppTheme.accentForeground : AppTheme.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.passed ? resultLine(result) : L("호환 실패 · \(result.failure ?? "")", "Incompatible · \(result.failure ?? "")"))
                        .font(AppTypography.caption).fixedSize(horizontal: false, vertical: true)
                    Text(result.checkedAt.formatted(.dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(tint.opacity(dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.30), lineWidth: 1))
        }
    }

    private func resultLine(_ result: ModelCompatibilityResult) -> String {
        var parts = [L("호환 확인", "Compatible"), String(format: L("%.2f초", "%.2fs"), result.latencySeconds)]
        if let reported = result.reportedModel { parts.append(reported) }
        if let cost = result.costUSD { parts.append("~" + TextRateSummary.usd(cost)) }
        return parts.joined(separator: " · ")
    }

    private var canSave: Bool { isEditable && !trimmed.isEmpty && trimmed != current }

    @ViewBuilder private func sourceLine(_ choice: ProviderModelChoice) -> some View {
        let url = choice.price?.sourceURL ?? choice.sourceURL
        let date = choice.price?.asOf ?? choice.checkedAt
        if let url {
            HStack(spacing: 4) {
                Link(isSearchedChoice(choice) ? L("OpenRouter 공개 목록", "OpenRouter public list")
                     : choice.price == nil ? L("모델 문서", "Model docs") : L("공식 가격표", "Official pricing"), destination: url)
                if let date { Text(L("· \(date) 확인", "· checked \(date)")).foregroundStyle(AppTheme.textSecondary) }
            }
            .font(AppTypography.caption)
            .buttonStyle(InlineLinkStyle())
        }
    }

    private func isSearchedChoice(_ choice: ProviderModelChoice) -> Bool {
        guard let index = choices.firstIndex(where: { $0.id == choice.id }) else { return false }
        return index >= (curatedCount ?? choices.count)
    }

    private func sync() {
        guard loadedContext != contextID else { return }
        loadedContext = contextID
        draft = current
    }
}

struct ModelBadge { let kind: StatusBadge.Kind; let text: String }

/// Collapsed summary of one task's model, expanding into its editor.
struct ModelFunctionCard<Editor: View>: View {
    let title: String
    let description: String
    let modelID: String
    let providerBadge: String
    let rateSummary: String
    var rateUnknown = false
    /// A task that only follows another model shows a single line until it is opened.
    var compact = false
    var compactDetail: String?
    var failureSummary: String?
    let statusBadges: [ModelBadge]
    let isExpanded: Bool
    let isEditable: Bool
    let onToggleExpand: () -> Void
    @ViewBuilder var editor: () -> Editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                    Text(title).font(AppTypography.cardTitle).foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                    ForEach(Array(statusBadges.enumerated()), id: \.offset) { _, badge in
                        StatusBadge(kind: badge.kind, text: badge.text)
                    }
                    if compact && !isExpanded, let compactDetail {
                        Text(compactDetail).font(AppTypography.utility).foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { onToggleExpand() }
                } label: {
                    Label(isExpanded ? L("닫기", "Close") : L("변경", "Change"), systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .controlSize(.small)
                .accessibilityLabel(isExpanded ? L("\(title) 닫기", "Close \(title)") : L("\(title) 변경", "Change \(title)"))
            }
            if !compact || isExpanded {
            Text(description).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                Text(modelID).font(AppTypography.utility).foregroundStyle(AppTheme.textPrimary).textSelection(.enabled)
                StatusBadge(kind: .neutral, text: providerBadge)
                Text(rateSummary).font(AppTypography.caption.monospacedDigit()).foregroundStyle(rateUnknown ? AppTheme.warm : AppTheme.textSecondary)
            }
            .padding(.top, 8)
            if let failureSummary {
                Text(failureSummary).font(AppTypography.caption).foregroundStyle(AppTheme.destructive)
                    .lineLimit(2).padding(.top, 6)
            }
            }
            if isExpanded {
                Divider().padding(.vertical, 12)
                editor()
                    .transition(.opacity)
            }
        }
        .padding(compact && !isExpanded ? 10 : 14)
        .padding(.horizontal, compact && !isExpanded ? 4 : 0)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: AppLayout.nestedCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.nestedCornerRadius)
            .stroke(isExpanded ? AppTheme.accent.opacity(0.45) : AppTheme.separator, lineWidth: 1))
    }
}


struct ModelChip: View {
    let title: String
    let rateText: String?
    var isSelected: Bool
    var isNew = false
    var isVerified = false
    var isDefault = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isSelected ? AppTheme.accentForeground : AppTheme.textPrimary)
                        .lineLimit(1)
                    if isNew { Circle().fill(AppTheme.accentForeground).frame(width: 5, height: 5) }
                    if isVerified { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.accentForeground) }
                    if isDefault { Text(L("기본", "Default")).font(.system(size: 10)).foregroundStyle(AppTheme.textSecondary) }
                }
                if let rateText {
                    Text(rateText).font(.system(size: 11)).monospacedDigit().foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 42, alignment: .leading)
            .background(isSelected ? AppTheme.accent.opacity(0.13) : hovered ? AppTheme.hoverBackground : AppTheme.panelBackground,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppTheme.accent : AppTheme.separator, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Provider choice with a small dot for whether its key is known to be saved.
struct ProviderPill: View {
    let title: String
    let presence: Bool?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if let presence {
                        Circle().fill(presence ? AppTheme.accentForeground : AppTheme.warm)
                    } else {
                        Circle().stroke(AppTheme.textSecondary.opacity(0.65), lineWidth: 1.2)
                    }
                }
                .frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(selected ? AppTheme.accentForeground : AppTheme.textPrimary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(selected ? AppTheme.accent.opacity(0.13) : hovered ? AppTheme.hoverBackground : AppTheme.panelBackground, in: Capsule())
            .overlay(Capsule().stroke(selected ? AppTheme.accent.opacity(0.5) : AppTheme.separator, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(presence == true ? L("키 저장됨", "Key saved") : presence == false ? L("키 없음", "No key") : L("키 확인 전", "Key not checked"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Price summaries

enum TextRateSummary {
    static func text(provider: AIProvider, model: String) -> String {
        guard let price = TextModelCatalog.entry(id: model, provider: provider)?.price else {
            return L("단가 미확인", "Price unknown")
        }
        return L("입력 \(usd(price.inputUSDPerMillion)) · 출력 \(usd(price.outputUSDPerMillion)) / 1M",
                 "In \(usd(price.inputUSDPerMillion)) · Out \(usd(price.outputUSDPerMillion)) / 1M")
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2...4)))
    }
}

/// Published per-minute speech prices already verified in UsagePricing; others are not guessed.
enum SpeechRateSummary {
    static func text(provider: AIProvider, model: String) -> String {
        switch (provider, model) {
        case (.openAI, "gpt-transcribe"): return L("$0.27/시간", "$0.27/hour")
        case (.openAI, "whisper-1"): return L("$0.36/시간", "$0.36/hour")
        case (.groq, "whisper-large-v3-turbo"): return L("$0.04/시간 · 최소 10초", "$0.04/hour · 10 s minimum")
        case (.groq, "whisper-large-v3"): return L("$0.111/시간 · 최소 10초", "$0.111/hour · 10 s minimum")
        default: return L("단가 미확인", "Price unknown")
        }
    }
}

extension TextTask {
    var title: String {
        switch self {
        case .translation: L("번역", "Translation")
        case .rewrite: L("선택 문장 수정", "Edit selected text")
        case .prompt: L("프롬프트 만들기", "Prompt creation")
        case .refinement: L("번역 다듬기", "Translation refinement")
        }
    }
    var detail: String {
        switch self {
        case .translation: L("번역 단축키와 다른 언어로 출력하는 받아쓰기에 씁니다.", "Used by the translation shortcut and dictation into another language.")
        case .rewrite: L("다른 앱에서 선택한 글에 음성 수정 지시를 적용합니다.", "Applies a spoken edit to text selected in another app.")
        case .prompt: L("생각을 목표·조건이 정리된 AI 지시문으로 만듭니다.", "Turns your thoughts into an instruction with goals and constraints.")
        case .refinement: L("번역 초안을 원문과 대조해 한 번 더 다듬습니다.", "Polishes the draft translation against the source once more.")
        }
    }
}
