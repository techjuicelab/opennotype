import AppKit
import Charts
import SwiftUI
import OpenNoTypeCore

struct UsageView: View {
    @Bindable var model: AppModel
    @State private var period: UsagePeriod = .month
    @State private var provider = "all"
    @State private var showsClearConfirmation = false
    @State private var expandedRequest: UUID?

    private var analytics: UsageAnalytics { .init(records: model.usageRecords, period: period, provider: provider) }

    var body: some View {
        let report = analytics
        let groups = report.models
        VStack(alignment: .leading, spacing: 8) {
            Text(L("내가 쓴 만큼, 한눈에", "Your usage at a glance")).font(.system(size: 25, weight: .semibold)).tracking(-0.6)
            Text(L("이 Mac의 OpenNoType에서 사용한 음성과 API 요청을 모델별로 확인하세요.", "See speech processing and API requests made by OpenNoType on this Mac, grouped by model."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        HStack(spacing: 16) {
            Picker(L("조회 기간", "Period"), selection: $period) {
                ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 340)
            Spacer(minLength: 0)
            Picker(L("제공자", "Provider"), selection: $provider) {
                Text(L("모든 제공자", "All providers")).tag("all")
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                Text(L("TypeSafe · Jev 직접 연결", "TypeSafe · Direct Jev")).tag(DecisionProvider.typeSafe.rawValue)
                Text(L("이 Mac · 로컬", "This Mac · Local")).tag("local")
            }.frame(maxWidth: 220)
        }
        if !model.preferences.usageTrackingEnabled {
            Surface {
                Label(L("사용량 기록이 꺼져 있습니다", "Usage tracking is off"), systemImage: "pause.circle").font(.system(size: 14, weight: .medium))
                Text(L("새 요청 수집은 중단됩니다. 끄기 전에 수집해 저장 중이던 기록은 뒤늦게 반영될 수 있습니다.", "New requests are not collected. Records already being saved when tracking was turned off may still appear.")).font(.system(size: 13)).foregroundStyle(.secondary)
                Button(L("통계 기록 설정", "Usage tracking settings")) { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
            }
        }
        if let error = model.usageStorageError {
            Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(.orange)
        }
        qualityComparison(report)
        if report.records.isEmpty {
            emptyState
        } else {
            costSummary(report.totals)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 14) {
                metric(L("API 요청", "API requests"), value: L("\(report.totals.apiRequests.formatted())회", "\(report.totals.apiRequests.formatted()) requests"), detail: L("작업 \(report.totals.jobs)회 · 재시도 \(report.totals.retries)회", "\(report.totals.jobs) jobs · \(report.totals.retries) retries"), icon: "arrow.up.right")
                metric(L("음성 처리 길이", "Audio duration"), value: report.totals.audioCount == 0 ? L("미제공", "Not provided") : UsageFormat.duration(report.totals.audioSeconds), detail: L("재처리·재시도 포함", "Includes reprocessing and retries"), icon: "waveform")
                metric(L("집계된 토큰", "Recorded tokens"), value: UsageFormat.tokens(report.totals.tokens), detail: L("입력 + 출력 · 미제공 제외", "Input + output · Missing usage excluded"), icon: "text.alignleft")
            }
            activityChart(report)
            Surface(L("모델별 사용량", "Usage by model")) {
                Text(L("응답에 모델명이 있으면 실제 응답 모델로 묶습니다. 음성 인식과 문장 처리는 각각 집계합니다.", "Uses the returned model name when available. Speech recognition and text processing are counted separately."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(groups) { group in
                    modelRow(group)
                    if group.id != groups.last?.id { Divider() }
                }
            }
            recentRequests(report.records)
        }
        accountingNotes
    }

    private func qualityComparison(_ report: UsageAnalytics) -> some View {
        let groups = report.qualityModels(model.jevQualityMetrics)
        return Surface(L("문장 정리 모델 비교 · 이번 실행", "Text model comparison · This session")) {
            Text(L("모델별 문장 생성·Jev 검토와 개선안 사용을 집계합니다. 원문은 저장하지 않으며, 앱을 다시 열거나 통계를 초기화하거나 사용량 기록을 끄면 이 집계는 지워집니다.", "Counts text generation, Jev reviews and improvement use by text model. No text is stored in these counters. Restarting the app, resetting usage or turning off tracking clears them."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            if groups.isEmpty {
                Text(!model.preferences.usageTrackingEnabled
                     ? L("사용량 기록을 켠 뒤 완료한 문장 생성과 검토부터 집계합니다.", "Completed generations and reviews are counted after usage tracking is enabled.")
                     : model.jevQualityMetrics.isEmpty
                     ? L("이번 실행에서 집계한 문장 생성이나 Jev 검토가 없습니다. 모델 정보가 없는 과거 기록은 특정 모델의 결과로 추정하지 않습니다.", "No text generations or Jev reviews have been counted in this session. Older history without model information is not attributed to a guessed model.")
                     : L("선택한 제공자의 이번 실행 집계가 없습니다.", "There are no session counts for the selected provider."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    qualityModelRow(group)
                    if group.id != groups.last?.id { Divider() }
                }
                Text(L("생성·검토·주의 신호·개선안 횟수와 평균 생성·검토 시간은 이번 실행 기준이며, 위의 조회 기간을 바꿔도 변하지 않습니다. 비용은 위에서 선택한 기간에 해당 모델로 요청한 모든 문장 처리의 보고 비용·추정 합계입니다. 검토된 문장만의 비용이나 Jev API 비용은 아닙니다.", "Generation, review, warning and improvement counts and average generation and review times cover this session; changing the period above does not change them. Costs combine reported and estimated costs for all text-processing requests to that model in the selected period. They are not limited to reviewed text and do not include Jev API costs."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Text(L("주의 신호는 Jev의 판단이며 정확도나 모델 순위가 아닙니다. 모델마다 처리한 문장이 다르고, 같은 결과를 다시 검토한 횟수도 포함합니다. ‘개선안 복사’는 사용자가 개선안을 처음 복사한 횟수이며 내용의 정확성을 보증하지 않습니다.", "Warnings are Jev’s judgments, not accuracy scores or model rankings. Each model processes different text, and reviewing the same result again counts again. ‘Improvement copied’ counts the first explicit copy of an improvement, not proof that its contents are correct."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private func qualityModelRow(_ group: JevQualityModelGroup) -> some View {
        let metric = group.metric
        let costs = group.textProcessingCosts
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.id.model).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                    Text(L("\(metric.provider.displayName) · 요청한 문장 정리 모델", "\(metric.provider.displayName) · Requested text model"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L("선택 기간 문장 처리 비용", "Text-processing cost · Selected period"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(costs.hasKnownCost ? UsageFormat.usd(costs.knownUSD) : L("금액 미확인", "Cost unknown"))
                        .font(.system(size: 14, weight: .medium)).monospacedDigit()
                    if costs.unknownCosts > 0 {
                        Text(L("미확인 \(costs.unknownCosts)회 제외", "Excludes \(costs.unknownCosts) unknown costs"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            LazyVGrid(columns: [.init(.flexible(), alignment: .leading), .init(.flexible(), alignment: .leading)], alignment: .leading, spacing: 11) {
                qualityFact(L("생성 완료 건수", "Completed text generations"), value: L("\(metric.generationCount)건", "\(metric.generationCount)"))
                qualityFact(L("평균 문장 생성 시간", "Average text generation time"), value: UsageFormat.reviewLatency(metric.meanGenerationDuration))
                qualityFact(L("완료한 Jev 검토", "Completed Jev reviews"), value: L("\(metric.reviewCount)회", "\(metric.reviewCount)"))
                qualityFact(L("주의 신호가 나온 검토", "Reviews with warnings"), value: L("\(metric.warningCount)회", "\(metric.warningCount)"))
                qualityFact(L("평균 Jev 검토 시간", "Average Jev review time"), value: UsageFormat.reviewLatency(metric.meanReviewDuration))
                qualityFact(L("개선안 생성 / 개선안 복사", "Improvements offered / copied"), value: "\(metric.improvementOfferedCount) / \(metric.improvementAdoptedCount)")
            }
            Text(L("생성 시간은 문장 처리 호출의 시작부터 완료까지이며 네트워크 대기와 재시도를 포함합니다. Jev 검토 시간은 별도로 집계하며, 두 시간 모두 음성 인식 시간은 제외합니다.", "Generation time runs from the start to completion of a text-processing call, including network waits and retries. Jev review time is counted separately. Neither includes speech recognition."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func qualityFact(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        Surface {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 34, weight: .light)).foregroundStyle(AppTheme.accentForeground)
                Text(!model.preferences.usageTrackingEnabled && model.usageRecords.isEmpty ? L("사용량 기록을 켜면 시작됩니다", "Turn on usage tracking to start") : model.usageRecords.isEmpty ? L("첫 사용부터 기록됩니다", "Usage appears after your first request") : L("선택한 조건에 사용 기록이 없습니다", "No usage matches these filters"))
                    .font(.system(size: 18, weight: .semibold))
                Text(model.preferences.usageTrackingEnabled ? L("음성 인식이나 문장 처리를 사용하면 요청 횟수, 모델, 토큰과 확인 가능한 비용이 여기에 표시됩니다. 이전 버전의 기록에서 비용을 추측해 채우지는 않습니다.", "Speech and text processing requests appear here with their models, tokens and available costs. Costs are not guessed for older records.") : L("현재 새 사용량을 기록하지 않습니다. 설정에서 사용량 기록을 켜면 이후 요청부터 표시됩니다. 기록이 꺼져 있던 기간은 나중에 채워지지 않습니다.", "New usage is not being recorded. Turn on tracking in Settings to see future requests. Usage from periods when tracking was off is not filled in later."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 450)
                Button(model.preferences.usageTrackingEnabled ? L("사용할 모델 확인", "Review your models") : L("통계 기록 설정", "Usage tracking settings")) {
                    model.settingsSection = model.preferences.usageTrackingEnabled ? .connection : .privacy
                    model.page = .settings
                }.disabled(AppLaunch.isPreview)
            }.padding(.vertical, 28).frame(maxWidth: .infinity)
        }
    }

    private func costSummary(_ totals: UsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L("확인 가능한 비용 · USD", "Available cost · USD"), systemImage: "creditcard").font(.system(size: 13, weight: .medium))
                Spacer()
                if totals.unknownCosts > 0 {
                    Text(L("일부 비용 미확인", "Some costs are unknown")).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5).background(.background.opacity(0.6), in: Capsule())
                }
            }
            Text(totals.hasKnownCost ? UsageFormat.usd(totals.knownUSD) : L("금액 미확인", "Cost unknown"))
                .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(alignment: .top, spacing: 24) {
                costPart(L("공급자 보고", "Provider-reported"), value: totals.hasReportedCost ? UsageFormat.usd(totals.reportedUSD) : L("보고 없음", "Not reported"))
                costPart(L("단가 기반 추정", "Rate-based estimate"), value: totals.hasEstimatedCost ? UsageFormat.usd(totals.estimatedUSD) : L("추정 없음", "Not estimated"))
                costPart(L("금액 미확인", "Cost unknown"), value: L("\(totals.unknownCosts)회", "\(totals.unknownCosts) requests"))
                Spacer(minLength: 0)
            }
            Text(L("제공자 응답의 비용과 공개 단가로 계산한 추정치의 합계입니다. 미확인 요청은 합계에서 제외되며, 최종 청구액과 다를 수 있습니다.", "Combines provider-reported costs and estimates based on published rates. Requests with unknown costs are excluded. The total may differ from your final bill."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.accent.opacity(0.15), lineWidth: 1))
    }
    private func costPart(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .medium)).monospacedDigit()
        }
    }
    private func metric(_ title: String, value: String, detail: String, icon: String) -> some View {
        Surface {
            Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func activityChart(_ report: UsageAnalytics) -> some View {
        Surface(L("일별 처리 활동", "Daily activity")) {
            Text(L("선택한 기간·제공자의 활동 중 최대 최근 30일을 표시합니다. 재시도는 각각의 요청으로 집계합니다.", "Shows up to the last 30 days within the selected period and provider. Each retry counts as a separate request."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Chart(report.recentDays) { day in
                BarMark(x: .value(L("날짜", "Date"), day.date, unit: .day), y: .value(L("처리 횟수", "Operations"), day.requests))
                    .foregroundStyle(by: .value(L("구분", "Type"), L("API 요청", "API requests")))
                BarMark(x: .value(L("날짜", "Date"), day.date, unit: .day), y: .value(L("처리 횟수", "Operations"), day.localOperations))
                    .foregroundStyle(by: .value(L("구분", "Type"), L("로컬 음성 인식", "Local speech recognition")))
            }
            .chartForegroundStyleScale([L("API 요청", "API requests"): AppTheme.accent, L("로컬 음성 인식", "Local speech recognition"): AppTheme.warm])
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month().day().locale(AppLocalization.shared.language.locale)) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
            .accessibilityLabel(L("선택한 기간 중 차트에 표시된 API 요청 \(report.recentDays.reduce(0) { $0 + $1.requests })회, 로컬 음성 인식 \(report.recentDays.reduce(0) { $0 + $1.localOperations })회", "The chart shows \(report.recentDays.reduce(0) { $0 + $1.requests }) API requests and \(report.recentDays.reduce(0) { $0 + $1.localOperations }) local speech operations within the selected period"))
        }
    }
    private func modelRow(_ group: UsageModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.id.model).font(.system(size: 14, weight: .semibold)).textSelection(.enabled).lineLimit(2)
                    Text("\(group.providerName) · \(group.id.stage.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(group.totals.hasKnownCost ? UsageFormat.usd(group.totals.knownUSD) : L("금액 미확인", "Cost unknown"))
                        .font(.system(size: 16, weight: .medium)).monospacedDigit()
                    Text(group.id.provider == "local" ? L("API 비용 없음", "No API cost") : group.totals.unknownCosts > 0 ? L("미확인 \(group.totals.unknownCosts)회 제외", "Excludes \(group.totals.unknownCosts) unknown costs") : L("보고 비용 + 추정", "Reported + estimated"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text(L("\(group.totals.records.count)회", "\(group.totals.records.count) requests") +
                 (group.id.provider == "local" ? "" : L(" · 입력 \(UsageFormat.tokens(group.totals.inputTokens)) / 출력 \(UsageFormat.tokens(group.totals.outputTokens)) 토큰", " · Input \(UsageFormat.tokens(group.totals.inputTokens)) / output \(UsageFormat.tokens(group.totals.outputTokens)) tokens")) +
                 (group.totals.audioCount > 0 ? L(" · 음성 \(UsageFormat.duration(group.totals.audioSeconds))", " · Audio \(UsageFormat.duration(group.totals.audioSeconds))") : ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func recentRequests(_ records: [UsageRecord]) -> some View {
        Surface(L("최근 요청 · 최대 20개", "Recent requests · Up to 20")) {
            ForEach(Array(records.prefix(20))) { record in
                DisclosureGroup(isExpanded: Binding(get: { expandedRequest == record.id }, set: { expandedRequest = $0 ? record.id : nil })) {
                    requestDetails(record).padding(.top, 10)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.event.effectiveModel).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("\(record.event.stage.title) · \(record.event.outcome.title)" + (record.isRecovery ? L(" · 다시 처리", " · Reprocessed") : "") + (record.event.attempt > 1 ? L(" · 자동 재시도", " · Automatic retry") : ""))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(UsageFormat.usd(record.cost.usd)).font(.system(size: 13)).monospacedDigit()
                            Text(record.event.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    private func requestDetails(_ record: UsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(record.event.providerDisplayName) · \(record.mode.title) · \(record.cost.kind.title)")
            if record.event.effectiveModel != record.event.model { Text(L("요청 모델: \(record.event.model)", "Requested model: \(record.event.model)")) }
            Text(L("\(record.event.provider == .anthropic ? "캐시 제외 입력" : "입력") \(UsageFormat.tokens(record.event.inputTokens)) · 출력 \(UsageFormat.tokens(record.event.outputTokens)) 토큰", "\(record.event.provider == .anthropic ? "Uncached input" : "Input") \(UsageFormat.tokens(record.event.inputTokens)) · Output \(UsageFormat.tokens(record.event.outputTokens)) tokens"))
            if let cached = record.event.cachedInputTokens { Text(L("캐시 읽기: \(cached.formatted()) 토큰", "Cache read: \(cached.formatted()) tokens")) }
            if let written = record.event.cacheWriteTokens { Text(L("캐시 쓰기: \(written.formatted()) 토큰", "Cache write: \(written.formatted()) tokens")) }
            if let audio = record.event.audioInputTokens { Text(L("입력 중 오디오: \(audio.formatted()) 토큰", "Audio input: \(audio.formatted()) tokens")) }
            if let reasoning = record.event.reasoningTokens { Text(L("출력 중 추론: \(reasoning.formatted()) 토큰", "Reasoning output: \(reasoning.formatted()) tokens")) }
            if let duration = record.event.audioSeconds { Text(L("음성 처리 길이: \(UsageFormat.duration(duration))", "Audio duration: \(UsageFormat.duration(duration))")) }
            if let note = record.cost.note { Text(note) }
            if let checked = record.cost.checkedAt { Text(L("단가 확인: \(checked)", "Rates checked: \(checked)")) }
            if let source = record.cost.sourceURL, let url = URL(string: source), url.scheme == "https" { Link(L("비용 근거 확인", "View cost source"), destination: url) }
        }.font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
    }
    private var accountingNotes: some View {
        Surface(L("통계와 비용을 읽는 방법", "Understanding usage and costs")) {
            Text(L("음성 인식과 문장 처리의 사용량을 따로 기록합니다. 실패·취소한 요청도 이미 처리되었다면 과금될 수 있어 기록에 남깁니다. 앱 밖에서 사용한 요청이나 이 기능을 켜기 전의 사용량은 포함되지 않습니다.", "Speech recognition and text processing are recorded separately. Failed or canceled requests can still be billed if already processed, so they remain in usage. Requests made outside this app or before tracking was enabled are not included."))
            Text(L("사용량 응답이 없는 모델은 토큰을 추측하지 않습니다. 비용은 USD 기준이며 무료 한도·세금·크레딧·계정별 할인·환율은 반영하지 않습니다. 실제 청구는 제공자 대시보드에서 확인하세요.", "Token counts are not guessed when a model provides no usage. Costs are in USD and exclude free allowances, taxes, credits, account discounts and exchange rates. Check the provider’s dashboard for your actual bill."))
            if let start = model.usageTrackingStartedAt {
                let date = start.formatted(.dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale))
                Text(L("기록 시작: \(date)", "Tracking started: \(date)"))
            }
            Text(L("모델·횟수·수신 토큰·음성 길이·비용 정보만 이 Mac에 암호화해 최근 10,000건까지 보관합니다. 문장 내용·원음·API 키는 통계에 저장하지 않습니다. 결과 기록의 보관 기간과는 별개입니다.", "Keeps up to 10,000 recent records encrypted on this Mac, containing only models, request counts, returned token usage, audio duration and cost information. Text, audio and API keys are not stored in usage records. This is separate from history retention."))
            if model.usageDiscardedCount > 0 {
                Label(L("보관 한도로 이전 \(model.usageDiscardedCount.formatted())건이 제외되어 전체 합계도 현재 보관된 기록 기준입니다.", "The storage limit removed \(model.usageDiscardedCount.formatted()) older records. Totals reflect only records currently stored."), systemImage: "info.circle")
            }
            HStack {
                Button(L("통계 기록 설정", "Usage tracking settings")) { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
                Spacer()
                Button(L("사용량 기록 초기화…", "Reset usage history…"), role: .destructive) { showsClearConfirmation = true }
                    .disabled(AppLaunch.isPreview || model.isBusy || (model.usageRecords.isEmpty && model.usageDiscardedCount == 0 && !model.preferences.usageAccountingIncomplete && model.jevQualityMetrics.isEmpty))
            }
            .confirmationDialog(L("이 Mac의 사용량 통계를 초기화할까요?", "Reset usage statistics on this Mac?"), isPresented: $showsClearConfirmation) {
                Button(L("사용량 기록 초기화", "Reset usage history"), role: .destructive) { Task { await model.clearUsage() } }
                Button(L("취소", "Cancel"), role: .cancel) { }
            } message: { Text(L("모델별 사용량·비용 통계와 이번 실행의 Jev 비교 집계가 삭제됩니다. 문장 기록·개인 사전·복구 녹음과 제공자의 실제 청구 내역은 바뀌지 않습니다.", "Deletes model usage and cost statistics and this session’s Jev comparison counts. Text history, your dictionary, recovery recordings and the provider’s actual billing history stay unchanged.")) }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
    }
}
