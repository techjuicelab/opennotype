import SwiftUI
import OpenNoTypeCore

/// A projected dictation job priced from the current models when there is too little history.
/// Prompt size comes from the real cleanup prompt for a sample utterance; the rest is stated.
enum BaselineDictationCost {
    static let audioSeconds: Double = 20
    static let bytesPerToken: Double = 4
    private static let sample = L("내일 오후 세 시에 디자인 팀과 회의가 있어서 자료를 미리 정리해 두고 회의실 예약도 확인해 주세요.",
                                  "I have a design meeting tomorrow at three, so please prepare the materials and confirm the room booking.")

    struct Estimate { var perJobUSD: Double; var unpricedParts: [String] }

    static func estimate(_ preferences: Preferences) -> Estimate {
        var total: Double = 0
        var unpriced: [String] = []
        if !preferences.needsLocalForDictation {
            if let (rate, _) = UsagePricing.transcriptionRate(provider: preferences.provider, model: preferences.transcriptionModel),
               let perMinute = rate.audioPerMinute {
                total += max(audioSeconds, rate.minimumAudioSeconds ?? 0) / 60 * perMinute
            } else { unpriced.append(CostRole.transcription.title) }
        }
        if !preferences.usesFastDictation {
            let model = preferences.textModel(for: InputMode.dictation)
            if let price = TextModelCatalog.entry(id: model, provider: preferences.effectiveTextProvider)?.price {
                let request = ProcessingRequest(mode: .dictation, transcript: sample, dictionary: [],
                                                outputLanguage: preferences.dictationOutputLanguage,
                                                writingProfile: preferences.writingProfile(for: nil))
                let inputBytes = (try? ProviderClient.processingInputBytes(request)) ?? sample.utf8.count * 8
                let inputTokens = Double(inputBytes) / bytesPerToken
                let outputTokens = Double(sample.utf8.count) / bytesPerToken
                total += inputTokens / 1_000_000 * price.inputUSDPerMillion + outputTokens / 1_000_000 * price.outputUSDPerMillion
            } else { unpriced.append(CostRole.cleanup.title) }
            if preferences.decisionReviewMode != .off {
                if preferences.decisionProvider == .typeSafe {
                    let reviewBytes = Double(sample.utf8.count * 3)
                    total += reviewBytes / bytesPerToken / 1_000_000 * 0.042
                } else { unpriced.append(CostRole.review.title) }
            }
        }
        return Estimate(perJobUSD: total, unpricedParts: unpriced)
    }
}

enum CostText {
    static func usd(_ value: Double, digits: Int = 4) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2...digits)))
    }
}

/// Three figures at the top of AI & Costs: this month, the monthly estimate and key status.
struct AICostSummaryStrip: View {
    @Bindable var model: AppModel
    let onShowCosts: () -> Void
    let onShowKeys: () -> Void

    var body: some View {
        let month = UsageCostSummary.monthToDate(model.usageRecords)
        let forecast = UsageCostSummary.recentForecast(model.usageRecords)
        let baseline = BaselineDictationCost.estimate(model.preferences)
        HStack(spacing: 0) {
            tile(L("이번 달", "This month"), value: CostText.usd(month.totalUSD),
                 caption: month.unknownRequests > 0 ? L("미확인 \(month.unknownRequests)건 제외", "\(month.unknownRequests) unpriced excluded")
                    : model.preferences.monthlyBudgetUSD.map { L("기준 \(CostText.usd($0, digits: 2)) 중 \(percent(month.totalUSD, of: $0))", "\(percent(month.totalUSD, of: $0)) of \(CostText.usd($0, digits: 2))") }
                    ?? L("\(month.requests)건 요청", "\(month.requests) requests"),
                 action: onShowCosts)
            Divider().frame(height: 40)
            tile(L("월 예상", "Est. / month"),
                 value: "~" + CostText.usd(forecast?.monthlyUSD ?? baseline.perJobUSD * 40 * 30, digits: 2),
                 caption: forecast.map { L("최근 \($0.activeDays)일 실측", "Last \($0.activeDays) days") } ?? L("기본 가정 · 하루 40회", "Baseline · 40 a day"),
                 action: onShowCosts)
            Divider().frame(height: 40)
            tile(L("API 키", "API keys"), value: L("\(savedKeys)개 저장", "\(savedKeys) saved"),
                 caption: uncheckedKeys > 0 ? L("확인 전 \(uncheckedKeys)개", "\(uncheckedKeys) not checked") : L("모두 확인됨", "All checked"),
                 action: onShowKeys)
        }
        .padding(.vertical, 10)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: AppLayout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.cornerRadius).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var savedKeys: Int { AIProvider.allCases.filter { model.providerKeyPresence[$0] == true }.count }
    private var uncheckedKeys: Int { AIProvider.allCases.filter { model.providerKeyPresence[$0] == nil }.count }

    private func percent(_ value: Double, of budget: Double) -> String {
        (value / budget).formatted(.percent.precision(.fractionLength(0)))
    }

    private func tile(_ title: String, value: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                Text(value).font(AppTypography.metricValue).monospacedDigit().foregroundStyle(AppTheme.textPrimary)
                Text(caption).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// This month's spending by task and a projection, collapsed to one line by default.
struct AICostDetailsCard: View {
    @Bindable var model: AppModel
    @Binding var isExpanded: Bool
    let isEditable: Bool
    @State private var tab: Tab = .month
    @State private var preset: Preset = .mine
    @State private var budgetDraft = ""

    enum Tab: String, CaseIterable, Identifiable { case month, forecast; var id: String { rawValue } }
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
        let forecast = UsageCostSummary.recentForecast(model.usageRecords)
        let baseline = BaselineDictationCost.estimate(model.preferences)
        SettingsCard(icon: "chart.bar.xaxis", title: L("비용 상세·예측", "Cost details & estimate"),
                     subtitle: L("이번 달 \(CostText.usd(month.totalUSD)) · 월 예상 ~\(CostText.usd(forecast?.monthlyUSD ?? baseline.perJobUSD * 40 * 30, digits: 2))",
                                 "This month \(CostText.usd(month.totalUSD)) · Est. ~\(CostText.usd(forecast?.monthlyUSD ?? baseline.perJobUSD * 40 * 30, digits: 2))/mo"),
                     help: costHelp) {
            SettingsLinkButton(L("전체 분석", "Full usage")) { model.page = .usage }
            Button(isExpanded ? L("접기", "Collapse") : L("펼치기", "Expand"), systemImage: isExpanded ? "chevron.up" : "chevron.down") { isExpanded.toggle() }
        } content: {
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.preferences.usageTrackingEnabled {
                        Label(L("사용량 기록이 꺼져 있어 새 요청은 집계되지 않습니다. 개인정보·기록에서 켤 수 있습니다.", "Usage records are off, so new requests are not counted. Turn them on in Privacy."),
                              systemImage: "info.circle")
                            .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                    }
                    SettingsSegmentedPicker(title: L("보기", "View"), selection: $tab, options: Tab.allCases,
                                            label: { $0 == .month ? L("이번 달 기능별", "By task this month") : L("예측 계산기", "Estimator") })
                    if tab == .month { monthView(month) } else { forecastView(forecast, baseline: baseline) }
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
                        Text(cost.requests == 0 ? "$0.0000" : CostText.usd(cost.knownUSD))
                            .font(AppTypography.body.weight(.semibold).monospacedDigit())
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

    private func roleDetail(_ role: CostRole, _ cost: RoleCost) -> String {
        guard cost.requests > 0 else { return L("사용 내역 없음", "No usage") }
        var parts = [L("\(cost.requests)회", "\(cost.requests) requests")]
        if role == .transcription, cost.audioSeconds > 0 {
            parts.append(L("\(Int((cost.audioSeconds / 60).rounded()))분", "\(Int((cost.audioSeconds / 60).rounded())) min"))
        }
        if cost.unknownRequests > 0 { parts.append(L("미확인 \(cost.unknownRequests)건", "\(cost.unknownRequests) unpriced")) }
        return parts.joined(separator: " · ")
    }

    private var budgetEditor: some View {
        HStack(spacing: 8) {
            Text(L("월 기준 금액(참고용)", "Monthly reference (USD)")).font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
            TextField("5.00", text: $budgetDraft).textFieldStyle(.roundedBorder).frame(width: 80).font(AppTypography.utility)
                .disabled(!isEditable)
            Button(L("저장", "Save")) {
                guard isEditable, let value = Double(budgetDraft.trimmingCharacters(in: .whitespaces)), value.isFinite, value > 0 else { return }
                model.preferences.monthlyBudgetUSD = value
            }
            .disabled(!isEditable || Double(budgetDraft.trimmingCharacters(in: .whitespaces)).map { !($0 > 0) } ?? true)
            if model.preferences.monthlyBudgetUSD != nil {
                Button(L("지우기", "Clear")) { model.preferences.monthlyBudgetUSD = nil; budgetDraft = "" }.disabled(!isEditable)
            }
            Spacer(minLength: 0)
        }
        .onAppear { budgetDraft = model.preferences.monthlyBudgetUSD.map { String(format: "%.2f", $0) } ?? "" }
    }

    @ViewBuilder private func forecastView(_ forecast: CostForecast?, baseline: BaselineDictationCost.Estimate) -> some View {
        let presets = forecast == nil ? Preset.allCases.filter { $0 != .mine } : Preset.allCases
        let selected = presets.contains(preset) ? preset : .typical
        let perJob = forecast?.perJobUSD ?? baseline.perJobUSD
        let jobsPerDay = selected.jobsPerDay ?? forecast?.dailyJobs ?? 40
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let forecast {
                    StatusBadge(kind: .info, text: L("최근 \(forecast.activeDays)일 실측 · \(forecast.sampleRequests)건", "Last \(forecast.activeDays) days · \(forecast.sampleRequests) requests"))
                } else {
                    StatusBadge(kind: .warning, text: L("기본 가정", "Baseline"))
                }
                Text(forecast == nil
                     ? L("기록이 5건 이상 쌓이면 실제 평균으로 바뀝니다. 지금은 현재 모델 단가와 실제 정리 프롬프트 크기, 20초 발화로 계산합니다.", "Switches to your real average after 5 requests. For now: current model prices, the real cleanup prompt size and a 20-second utterance.")
                     : L("1회 평균 비용을 원하는 사용량에 곱해 계산합니다.", "Multiplies your average cost per job by the volume you choose."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSegmentedPicker(title: L("사용량", "Volume"), selection: Binding(get: { selected }, set: { preset = $0 }),
                                    options: presets, label: \.title)
            HStack(spacing: 0) {
                figure(L("1회 평균", "Per job"), CostText.usd(perJob))
                figure(L("하루 \(Int(jobsPerDay.rounded()))회", "\(Int(jobsPerDay.rounded())) a day"), CostText.usd(perJob * jobsPerDay))
                figure(L("한 달 예상", "Per month"), CostText.usd(perJob * jobsPerDay * 30, digits: 2))
            }
            .padding(12)
            .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: AppLayout.nestedCornerRadius))
            if let budget = model.preferences.monthlyBudgetUSD, perJob > 0 {
                let remaining = max(0, budget - UsageCostSummary.monthToDate(model.usageRecords).totalUSD)
                Text(L("남은 월 기준(\(CostText.usd(remaining, digits: 2)))으로 이 조건을 약 \(Int(remaining / (perJob * jobsPerDay)))일 더 쓸 수 있습니다.",
                       "The remaining reference (\(CostText.usd(remaining, digits: 2))) covers about \(Int(remaining / (perJob * jobsPerDay))) more days at this rate."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if forecast == nil && !baseline.unpricedParts.isEmpty {
                Text(L("단가를 확인할 수 없어 빠진 항목: \(baseline.unpricedParts.joined(separator: ", "))", "Left out because the price is unknown: \(baseline.unpricedParts.joined(separator: ", "))"))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            if let unknown = forecast?.unknownRequests, unknown > 0 {
                Text(L("금액 미확인 요청 \(unknown)건은 평균에 넣지 않았습니다.", "\(unknown) unpriced requests are left out of the average."))
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
