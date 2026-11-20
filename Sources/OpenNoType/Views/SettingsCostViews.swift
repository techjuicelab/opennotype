import SwiftUI
import OpenNoTypeCore

/// A monthly projection priced at the models selected now. Recent history supplies how often each
/// task runs and how large its requests are; without enough history a stated baseline is used.
struct CostProjection {
    var perJobUSD: Double
    var jobsPerDay: Double
    var basedOnHistory: Bool
    var activeDays: Int
    var sampleRequests: Int
    var unpricedRoles: [CostRole]
    var monthlyUSD: Double { perJobUSD * jobsPerDay * 30 }
    func monthlyUSD(jobsPerDay: Double) -> Double { perJobUSD * jobsPerDay * 30 }

    static let baselineAudioSeconds: Double = 20
    static let baselineJobsPerDay: Double = 40
    static let bytesPerToken: Double = 4
    private static let sample = L("내일 오후 세 시에 디자인 팀과 회의가 있어서 자료를 미리 정리해 두고 회의실 예약도 확인해 주세요.",
                                  "I have a design meeting tomorrow at three, so please prepare the materials and confirm the room booking.")
    private static let typeSafeInputPerMillion = 0.042

    static func make(_ preferences: Preferences, records: [UsageRecord]) -> CostProjection {
        if let recent = UsageCostSummary.recentUsage(records), recent.jobsPerDay > 0 {
            var daily: Double = 0
            var unpriced: [CostRole] = []
            for (role, average) in recent.byRole {
                if let cost = requestCost(role, average: average, preferences: preferences) { daily += cost * average.requestsPerDay }
                else { unpriced.append(role) }
            }
            return CostProjection(perJobUSD: daily / recent.jobsPerDay, jobsPerDay: recent.jobsPerDay, basedOnHistory: true,
                                  activeDays: recent.activeDays, sampleRequests: recent.sampleRequests,
                                  unpricedRoles: unpriced.sorted { $0.rawValue < $1.rawValue })
        }
        return baseline(preferences)
    }

    /// Prices one average request of a task at the current model. Falls back to the recorded
    /// average only when the current price cannot be applied; returns nil when neither exists.
    private static func requestCost(_ role: CostRole, average: RoleUsageAverage, preferences: Preferences) -> Double? {
        switch role {
        case .transcription:
            if preferences.needsLocalForDictation { return 0 }
            if let (rate, _) = UsagePricing.transcriptionRate(provider: preferences.provider, model: preferences.transcriptionModel),
               let perMinute = rate.audioPerMinute {
                let seconds = average.audioSeconds ?? baselineAudioSeconds
                return max(seconds, rate.minimumAudioSeconds ?? 0) / 60 * perMinute
            }
            return average.recordedUSD
        case .review:
            if preferences.decisionProvider == .typeSafe, let input = average.inputTokens {
                return input / 1_000_000 * typeSafeInputPerMillion
            }
            return average.recordedUSD
        case .cleanup, .translation, .rewrite, .prompt:
            let mode: InputMode = role == .cleanup ? .dictation : role == .translation ? .translation : role == .rewrite ? .rewrite : .prompt
            let model = preferences.textModel(for: mode)
            if let price = TextModelCatalog.entry(id: model, provider: preferences.effectiveTextProvider)?.price,
               let input = average.inputTokens, let output = average.outputTokens {
                return input / 1_000_000 * price.inputUSDPerMillion + output / 1_000_000 * price.outputUSDPerMillion
            }
            return average.recordedUSD
        }
    }

    private static func baseline(_ preferences: Preferences) -> CostProjection {
        var total: Double = 0
        var unpriced: [CostRole] = []
        if !preferences.needsLocalForDictation {
            if let (rate, _) = UsagePricing.transcriptionRate(provider: preferences.provider, model: preferences.transcriptionModel),
               let perMinute = rate.audioPerMinute {
                total += max(baselineAudioSeconds, rate.minimumAudioSeconds ?? 0) / 60 * perMinute
            } else { unpriced.append(.transcription) }
        }
        if !preferences.usesFastDictation {
            let model = preferences.textModel(for: InputMode.dictation)
            if let price = TextModelCatalog.entry(id: model, provider: preferences.effectiveTextProvider)?.price {
                let request = ProcessingRequest(mode: .dictation, transcript: sample, dictionary: [],
                                                outputLanguage: preferences.dictationOutputLanguage,
                                                writingProfile: preferences.writingProfile(for: nil))
                let inputBytes = (try? ProviderClient.processingInputBytes(request)) ?? sample.utf8.count * 8
                total += Double(inputBytes) / bytesPerToken / 1_000_000 * price.inputUSDPerMillion
                    + Double(sample.utf8.count) / bytesPerToken / 1_000_000 * price.outputUSDPerMillion
            } else { unpriced.append(.cleanup) }
            if preferences.decisionReviewMode != .off {
                if preferences.decisionProvider == .typeSafe {
                    total += Double(sample.utf8.count * 3) / bytesPerToken / 1_000_000 * typeSafeInputPerMillion
                } else { unpriced.append(.review) }
            }
        }
        return CostProjection(perJobUSD: total, jobsPerDay: baselineJobsPerDay, basedOnHistory: false,
                              activeDays: 0, sampleRequests: 0, unpricedRoles: unpriced)
    }
}

enum CostText {
    static func usd(_ value: Double, digits: Int = 4) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2...digits)))
    }
}

enum CostCardTab: String, CaseIterable, Identifiable { case month, forecast; var id: String { rawValue } }

/// Figures at the top of AI & Costs: this month, the monthly estimate, new models and key status.
struct AICostSummaryStrip: View {
    @Bindable var model: AppModel
    let onShowMonth: () -> Void
    let onShowForecast: () -> Void
    let onShowModels: () -> Void
    let onShowKeys: () -> Void

    var body: some View {
        let month = UsageCostSummary.monthToDate(model.usageRecords)
        let projection = CostProjection.make(model.preferences, records: model.usageRecords)
        HStack(spacing: 0) {
            SummaryTile(title: L("이번 달", "This month"), value: CostText.usd(month.totalUSD),
                        caption: month.unknownRequests > 0 ? L("미확인 \(month.unknownRequests)건 제외", "\(month.unknownRequests) unpriced excluded")
                            : model.preferences.monthlyBudgetUSD.map { L("기준 \(CostText.usd($0, digits: 2)) 중 \(percent(month.totalUSD, of: $0))", "\(percent(month.totalUSD, of: $0)) of \(CostText.usd($0, digits: 2))") }
                            ?? L("\(month.requests)건 요청", "\(month.requests) requests"),
                        warns: month.unknownRequests > 0, action: onShowMonth)
            Divider().frame(height: 40)
            SummaryTile(title: L("월 예상", "Est. / month"), value: "~" + CostText.usd(projection.monthlyUSD, digits: 2),
                        caption: projection.basedOnHistory ? L("최근 \(projection.activeDays)일 · 현재 모델 단가", "Last \(projection.activeDays) days · current prices")
                            : L("기본 가정 · 하루 40회", "Baseline · 40 a day"),
                        warns: !projection.unpricedRoles.isEmpty, action: onShowForecast)
            if model.modelCatalog.newCount > 0 {
                Divider().frame(height: 40)
                SummaryTile(title: L("새 후보", "New models"), value: L("\(model.modelCatalog.newCount)건", "\(model.modelCatalog.newCount) new"),
                            caption: L("최근 검색", "Last check"), valueTint: AppTheme.accentForeground, action: onShowModels)
            }
            Divider().frame(height: 40)
            SummaryTile(title: L("API 키", "API keys"), value: L("\(savedKeys)개 저장", "\(savedKeys) saved"),
                        caption: uncheckedKeys > 0 ? L("확인 전 \(uncheckedKeys)개", "\(uncheckedKeys) not checked") : L("모두 확인됨", "All checked"),
                        action: onShowKeys)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: AppLayout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.cornerRadius).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var keyedProviders: [Bool?] {
        AIProvider.allCases.map { model.providerKeyPresence[$0] }
            + (model.preferences.decisionProvider == .typeSafe ? [model.decisionKeyOperationInProgress ? nil : model.decisionKeySaved] : [])
    }
    private var savedKeys: Int { keyedProviders.filter { $0 == true }.count }
    private var uncheckedKeys: Int { keyedProviders.filter { $0 == nil }.count }

    private func percent(_ value: Double, of budget: Double) -> String {
        (value / budget).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let caption: String
    var warns = false
    var valueTint: Color = AppTheme.textPrimary
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(hovered ? 0.9 : 0.45))
                }
                Text(value).font(AppTypography.metricValue).monospacedDigit().foregroundStyle(valueTint)
                Text(caption).font(AppTypography.caption).foregroundStyle(warns ? AppTheme.warm : AppTheme.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(hovered ? AppTheme.hoverBackground.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint(caption)
    }
}

/// This month's spending by task and a projection, collapsed to one line by default.
struct AICostDetailsCard: View {
    @Bindable var model: AppModel
    @Binding var isExpanded: Bool
    @Binding var tab: CostCardTab
    let isEditable: Bool
    @State private var preset: Preset = .mine
    @State private var budgetDraft = ""

    enum Preset: String, CaseIterable, Identifiable {
        case mine, light, typical, heavy
        var id: String { rawValue }
        var jobsPerDay: Double? { switch self { case .mine: nil; case .light: 15; case .typical: 40; case .heavy: 100 } }
        var title: String {
            switch self {
            case .mine: L("내 평균", "My average")
            case .light: L("가벼운 15/일", "Light 15/d")
            case .typical: L("보통 40/일", "Typical 40/d")
            case .heavy: L("집중 100/일", "Heavy 100/d")
            }
        }
    }

    var body: some View {
        let month = UsageCostSummary.monthToDate(model.usageRecords)
        let projection = CostProjection.make(model.preferences, records: model.usageRecords)
        SettingsCard(icon: "chart.bar.xaxis", title: L("비용 상세·예측", "Cost details & estimate"),
                     subtitle: L("이번 달 \(CostText.usd(month.totalUSD)) · 월 예상 ~\(CostText.usd(projection.monthlyUSD, digits: 2))",
                                 "This month \(CostText.usd(month.totalUSD)) · Est. ~\(CostText.usd(projection.monthlyUSD, digits: 2))/mo"),
                     help: costHelp) {
            SettingsLinkButton(L("전체 분석", "Full usage")) { model.page = .usage }
            Button { isExpanded.toggle() } label: {
                Label(isExpanded ? L("접기", "Collapse") : L("펼치기", "Expand"), systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
            }
        } content: {
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.preferences.usageTrackingEnabled {
                        Label(L("사용량 기록이 꺼져 있어 새 요청은 집계되지 않습니다. 개인정보·기록에서 켤 수 있습니다.", "Usage records are off, so new requests are not counted. Turn them on in Privacy."),
                              systemImage: "info.circle")
                            .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    }
                    SettingsSegmentedPicker(title: L("보기", "View"), selection: $tab, options: CostCardTab.allCases,
                                            label: { $0 == .month ? L("이번 달 기능별", "By task this month") : L("예측 계산기", "Estimator") })
                    if tab == .month { monthView(month) } else { forecastView(projection) }
                }
            }
        }
    }

    @ViewBuilder private func monthView(_ month: CostSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let budget = model.preferences.monthlyBudgetUSD {
                ProgressView(value: min(1, month.totalUSD / budget))
                    .tint(month.totalUSD > budget ? AppTheme.warm : AppTheme.accent)
                HStack {
                    Text("\(CostText.usd(month.totalUSD)) / \(CostText.usd(budget, digits: 2))").font(AppTypography.body.monospacedDigit())
                    Spacer()
                    Text(month.totalUSD <= budget ? L("남은 금액 \(CostText.usd(budget - month.totalUSD))", "\(CostText.usd(budget - month.totalUSD)) left")
                         : L("기준 초과 \(CostText.usd(month.totalUSD - budget))", "\(CostText.usd(month.totalUSD - budget)) over"))
                        .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 6)
                Divider()
            }
            SettingsRows {
                ForEach(CostRole.allCases, id: \.self) { role in
                    let cost = month.byRole[role] ?? RoleCost()
                    SettingsItem(role.title, detail: roleDetail(role, cost)) {
                        if cost.requests > 0 && cost.unknownRequests == cost.requests {
                            Text(L("미확인", "Unpriced")).font(AppTypography.body.weight(.semibold)).foregroundStyle(AppTheme.warm)
                        } else {
                            Text(CostText.usd(cost.knownUSD)).font(AppTypography.body.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
            if month.unknownRequests > 0 {
                Text(L("금액을 확인할 수 없는 요청 \(month.unknownRequests)건은 합계에 넣지 않았습니다(0으로 계산하지 않음).", "\(month.unknownRequests) requests without a verified amount are left out of the total, not counted as zero."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm).padding(.top, 6)
            }
            budgetEditor.padding(.top, 10)
        }
    }

    private func currentModel(_ role: CostRole) -> String {
        let p = model.preferences
        switch role {
        case .transcription: return p.needsLocal ? p.localSpeechModel.displayName : p.transcriptionModel
        case .cleanup: return p.textModel
        case .translation: return p.textModel(forTask: .translation)
        case .rewrite: return p.textModel(forTask: .rewrite)
        case .prompt: return p.textModel(forTask: .prompt)
        case .review: return p.decisionProvider.model
        }
    }

    private func roleDetail(_ role: CostRole, _ cost: RoleCost) -> String {
        var parts = [currentModel(role)]
        guard cost.requests > 0 else { return (parts + [L("사용 내역 없음", "No usage")]).joined(separator: " · ") }
        parts.append(L("\(cost.requests)회", "\(cost.requests) requests"))
        if role == .transcription, cost.audioSeconds > 0 {
            parts.append(L("\(Int((cost.audioSeconds / 60).rounded()))분", "\(Int((cost.audioSeconds / 60).rounded())) min"))
        }
        if cost.unknownRequests > 0 { parts.append(L("미확인 \(cost.unknownRequests)건", "\(cost.unknownRequests) unpriced")) }
        return parts.joined(separator: " · ")
    }

    private var parsedBudget: Double? {
        guard let value = Double(budgetDraft.trimmingCharacters(in: .whitespaces)), value.isFinite, value > 0 else { return nil }
        return value
    }

    private var budgetEditor: some View {
        HStack(spacing: 6) {
            Text(L("월 기준 금액 (USD · 참고용)", "Monthly reference (USD)")).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
            Text("$").font(AppTypography.utility).foregroundStyle(AppTheme.textSecondary)
            TextField("5.00", text: $budgetDraft).textFieldStyle(.roundedBorder).frame(width: 80).font(AppTypography.utility)
                .disabled(!isEditable)
                .onSubmit { if isEditable, let value = parsedBudget { model.preferences.monthlyBudgetUSD = value } }
            Button(L("저장", "Save")) {
                guard isEditable, let value = parsedBudget else { return }
                model.preferences.monthlyBudgetUSD = value
            }
            .disabled(!isEditable || parsedBudget == nil || parsedBudget == model.preferences.monthlyBudgetUSD)
            if model.preferences.monthlyBudgetUSD != nil {
                Button(L("지우기", "Clear")) { model.preferences.monthlyBudgetUSD = nil; budgetDraft = "" }.disabled(!isEditable)
            }
            Spacer(minLength: 0)
        }
        .onAppear { budgetDraft = model.preferences.monthlyBudgetUSD.map { String(format: "%.2f", $0) } ?? "" }
    }

    @ViewBuilder private func forecastView(_ projection: CostProjection) -> some View {
        let presets = projection.basedOnHistory ? Preset.allCases : Preset.allCases.filter { $0 != .mine }
        let selected = presets.contains(preset) ? preset : .typical
        let jobsPerDay = selected.jobsPerDay ?? projection.jobsPerDay
        let perJob = projection.perJobUSD
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                if projection.basedOnHistory {
                    StatusBadge(kind: .info, text: L("최근 \(projection.activeDays)일 · \(projection.sampleRequests)건", "Last \(projection.activeDays) days · \(projection.sampleRequests) requests"))
                } else {
                    StatusBadge(kind: .warning, text: L("기본 가정", "Baseline"))
                }
                Text(projection.basedOnHistory
                     ? L("최근 사용 횟수와 요청 크기에 지금 선택한 모델의 단가를 적용합니다. 모델을 바꾸면 금액도 바뀝니다.", "Applies the prices of the models selected now to your recent volume and request sizes. Changing a model changes the estimate.")
                     : L("기록이 5건 이상 쌓이면 실제 사용량으로 바뀝니다. 지금은 현재 모델 단가와 실제 정리 프롬프트 크기, 20초 발화로 계산합니다.", "Switches to your real usage after 5 requests. For now: current model prices, the real cleanup prompt size and a 20-second utterance."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSegmentedPicker(title: L("사용량", "Volume"), selection: Binding(get: { selected }, set: { preset = $0 }),
                                    options: presets, label: \.title)
            HStack(spacing: 0) {
                figure(L("1회 평균", "Per job"), CostText.usd(perJob))
                figure(L("하루 \(Int(jobsPerDay.rounded()))회", "\(Int(jobsPerDay.rounded())) a day"), CostText.usd(perJob * jobsPerDay))
                figure(L("한 달 예상", "Per month"), CostText.usd(projection.monthlyUSD(jobsPerDay: jobsPerDay), digits: 2))
            }
            .padding(12)
            .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: AppLayout.nestedCornerRadius))
            if let budget = model.preferences.monthlyBudgetUSD, perJob > 0 {
                let remaining = max(0, budget - UsageCostSummary.monthToDate(model.usageRecords).totalUSD)
                Text(L("남은 월 기준(\(CostText.usd(remaining, digits: 2)))으로 이 조건을 약 \(Int(remaining / (perJob * jobsPerDay)))일 더 쓸 수 있습니다.",
                       "The remaining reference (\(CostText.usd(remaining, digits: 2))) covers about \(Int(remaining / (perJob * jobsPerDay))) more days at this rate."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if !projection.unpricedRoles.isEmpty {
                Text(L("단가를 확인할 수 없어 빠진 항목: \(projection.unpricedRoles.map(\.title).joined(separator: ", "))", "Left out because the price is unknown: \(projection.unpricedRoles.map(\.title).joined(separator: ", "))"))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
        }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
            Text(value).font(AppTypography.metricValue).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var costHelp: String {
        L("공급자가 보고한 금액과 확인된 공개 단가로 추정한 금액만 더합니다. 금액을 확인할 수 없는 요청은 0으로 계산하지 않고 따로 셉니다. 할인·크레딧·세금은 포함하지 않으며 실제 청구액은 각 제공자에서 확인하세요. 월 기준 금액은 참고용이며 요청을 막지 않습니다.",
          "Adds only provider-reported amounts and estimates from verified public prices. Requests without a verified amount are counted separately, not as zero. Discounts, credits and tax are not included; check actual bills with each provider. The monthly reference never blocks requests.")
    }
}
