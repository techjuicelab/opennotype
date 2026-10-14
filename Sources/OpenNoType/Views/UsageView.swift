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
    @State private var showsSessionComparison = false
    @State private var showsActivity = false

    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }

    private var analytics: UsageAnalytics { .init(records: model.usageRecords, period: period, provider: provider) }

    var body: some View {
        let report = analytics
        let groups = report.models
        AppPageHeader(L("사용량", "Usage"), help: L("이 Mac의 OpenNoType에서 사용한 요청만 집계합니다. 공급자 보고 비용과 공개 단가 추정치를 구분하며 미확인 비용은 합계에서 제외합니다. 실패·취소 요청도 이미 처리되었다면 과금될 수 있습니다. 최종 청구는 제공자 대시보드에서 확인하세요.", "Counts requests made by OpenNoType on this Mac. Provider-reported costs and public-rate estimates are distinguished; unknown costs are excluded. Failed or canceled requests may still be billed. Check the provider dashboard for final billing."))
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
                OptionHelp(title: L("사용량 기록 꺼짐", "Usage tracking off"), message: L("새 요청 수집은 중단됩니다. 끄기 전에 수집해 저장 중이던 기록은 뒤늦게 반영될 수 있습니다. 꺼져 있던 기간의 사용량은 나중에 채우지 않습니다.", "New requests are not collected. Records already being saved when tracking was turned off may still appear. Usage from the disabled period is not backfilled."))
                Button(L("통계 기록 설정", "Usage tracking settings")) { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
            }
        }
        if let error = model.usageStorageError {
            Label(error, systemImage: "exclamationmark.triangle").font(AppTypography.body).foregroundStyle(.orange)
        }
        if report.records.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 16) {
                costSummary(report.totals)
                metric(L("API 요청", "API requests"), value: L("\(report.totals.apiRequests.formatted())회", "\(report.totals.apiRequests.formatted()) requests"), detail: L("작업 \(report.totals.jobs)회 · 재시도 \(report.totals.retries)회", "\(report.totals.jobs) jobs · \(report.totals.retries) retries"), icon: "arrow.up.right")
                metric(L("집계된 토큰", "Recorded tokens"), value: UsageFormat.tokens(report.totals.tokens), detail: L("입력 + 출력 · 미제공 제외", "Input + output · Missing usage excluded"), icon: "text.alignleft")
            }
            HStack {
                Text(L("음성 처리 길이", "Audio duration")).foregroundStyle(.secondary)
                Text(report.totals.audioCount == 0 ? L("미제공", "Not provided") : UsageFormat.duration(report.totals.audioSeconds)).monospacedDigit()
                OptionHelp(title: L("음성 처리 길이", "Audio duration"), message: L("재처리·재시도를 포함해 제공자가 반환한 음성 길이를 합산합니다. 미제공 길이는 추측하지 않습니다.", "Adds audio durations returned by providers, including reprocessing and retries. Missing durations are not estimated."))
            }.font(AppTypography.caption)
            DisclosureGroup(L("일별 활동", "Daily activity"), isExpanded: $showsActivity) { activityChart(report).padding(.top, 12) }.font(AppTypography.body)
            Surface(L("모델별 사용량", "Usage by model")) {
                HStack {
                    Text(L("모델 · 처리 · 요청 · 비용", "Model · Stage · Requests · Cost")).font(AppTypography.caption).foregroundStyle(.secondary)
                    Spacer()
                    OptionHelp(title: L("모델별 사용량", "Usage by model"), message: L("응답에 모델명이 있으면 실제 응답 모델로 묶습니다. 음성 인식과 문장 처리는 각각 집계하며 로컬 처리에는 API 비용이 없습니다. 미확인 비용을 0으로 만들지 않습니다.", "Uses the returned model name when available and counts speech and text stages separately. Local processing has no API cost. Unknown costs are not treated as zero."))
                }
                ForEach(groups) { group in
                    modelRow(group)
                    if group.id != groups.last?.id { Divider() }
                }
            }
            recentRequests(report.records)
        }
        DisclosureGroup(L("문장 모델 품질·속도 비교 · 이번 앱 실행", "Text model quality & speed · This app session"), isExpanded: $showsSessionComparison) {
            qualityComparison(report).padding(.top, 12)
        }.font(AppTypography.body)
        accountingNotes
    }

    private func qualityComparison(_ report: UsageAnalytics) -> some View {
        let groups = report.qualityModels(model.jevQualityMetrics)
        return Surface(L("문장 정리 모델 비교 · 이번 실행", "Text model comparison · This session")) {
            HStack {
                Text(L("이번 실행 · 제공자 필터만 적용", "This session · Provider filter only")).font(AppTypography.caption).foregroundStyle(.secondary)
                Spacer()
                OptionHelp(title: L("이번 실행 집계", "This session's counters"), message: L("모델별 문장 생성·Jev 검토·개선안 사용을 집계하며 원문은 저장하지 않습니다. 기간 필터는 적용하지 않고 제공자 필터만 적용합니다. 앱 재실행·통계 초기화·사용량 기록 끄기로 지워집니다. 모델마다 처리한 문장이 다르며 같은 결과를 재검토한 횟수도 포함합니다. Jev 주의 신호와 개선안 첫 복사는 정확도나 모델 순위, 내용 정확성의 보증이 아닙니다.", "Counts generations, Jev reviews and improvement use by model without saving text. Only the provider filter applies. Restarting, resetting usage or disabling tracking clears these counters. Models process different texts and repeated reviews also count. Jev warnings and the first improvement copy are not accuracy scores, rankings or guarantees."))
            }
            if groups.isEmpty {
                Text(!model.preferences.usageTrackingEnabled
                     ? L("사용량 기록을 켠 뒤 완료한 문장 생성과 검토부터 집계합니다.", "Completed generations and reviews are counted after usage tracking is enabled.")
                     : model.jevQualityMetrics.isEmpty
                     ? L("이번 실행에서 집계한 문장 생성이나 Jev 검토가 없습니다. 모델 정보가 없는 과거 기록은 특정 모델의 결과로 추정하지 않습니다.", "No text generations or Jev reviews have been counted in this session. Older history without model information is not attributed to a guessed model.")
                     : L("선택한 제공자의 이번 실행 집계가 없습니다.", "There are no session counts for the selected provider."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    qualityModelRow(group)
                    if group.id != groups.last?.id { Divider() }
                }
            }

        }
    }

    private func qualityModelRow(_ group: JevQualityModelGroup) -> some View {
        let metric = group.metric
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.id.model).font(AppTypography.body.weight(.semibold)).textSelection(.enabled)
                    Text(L("\(metric.provider.displayName) · 요청한 문장 정리 모델", "\(metric.provider.displayName) · Requested text model"))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(L("이번 실행", "This session")).font(AppTypography.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [.init(.flexible(), alignment: .leading), .init(.flexible(), alignment: .leading)], alignment: .leading, spacing: 11) {
                qualityFact(L("문장 생성 완료 / 시도", "Text generations completed / attempted"), value: "\(metric.generationCount) / \(metric.generationAttemptCount)")
                qualityFact(L("생성 실패 / 취소", "Generation failures / cancellations"), value: "\(metric.generationFailureCount) / \(metric.generationCancellationCount)")
                qualityFact(L("Jev 검토 완료 / 시도", "Jev reviews completed / attempted"), value: "\(metric.reviewCount) / \(metric.reviewAttemptCount)")
                qualityFact(L("검토 실패 / 취소", "Review failures / cancellations"), value: "\(metric.reviewFailureCount) / \(metric.reviewCancellationCount)")
                qualityFact(L("문장 생성 시간 p50 / p95", "Generation time p50 / p95"), value: latencyPair(metric.p50GenerationDuration, metric.p95GenerationDuration))
                qualityFact(L("Jev 검토 시간 p50 / p95", "Jev review time p50 / p95"), value: latencyPair(metric.p50ReviewDuration, metric.p95ReviewDuration))
                qualityFact(L("전체 처리 시간 p50 / p95", "End-to-end time p50 / p95"), value: latencyPair(metric.p50PipelineDuration, metric.p95PipelineDuration))
                qualityFact(L("입력 보류 / 전체 시도", "Held inputs / total attempts"), value: "\(metric.pipelineHeldCount) / \(metric.pipelineAttemptCount) · \(heldRate(metric.heldRate))")
                qualityFact(L("처리 완료 / 실패 / 취소", "Pipeline completed / failed / cancelled"), value: "\(metric.pipelineCompletedCount) / \(metric.pipelineFailureCount) / \(metric.pipelineCancellationCount)")
                qualityFact(L("주의 신호가 나온 검토", "Reviews with warnings"), value: L("\(metric.warningCount)회", "\(metric.warningCount)"))
                qualityFact(L("개선안 생성 / 개선안 복사", "Improvements offered / copied"), value: "\(metric.improvementOfferedCount) / \(metric.improvementAdoptedCount)")
            }
            OptionHelp(title: L("처리 시간의 집계 범위", "Latency measurement scope"), message: L("p50은 중간값, p95는 95%의 측정이 그 시간 안에 끝났음을 뜻합니다. 각 단계의 최근 256개 유효 시간에 실패·취소도 포함합니다. 전체 처리는 녹음 종료부터 음성 인식·정리·검토·입력·저장 또는 보류·실패까지이며 녹음 시간은 제외합니다. 생성·검토 시간은 해당 API 단계만 집계합니다.", "p50 is the median; p95 means 95% of measurements ended within that duration. Each phase uses its latest 256 valid durations, including failures and cancellations. End-to-end runs from recording stop through transcription, cleanup, review, typing and storage, or a held/failed outcome; recording time is excluded. Generation and review times cover their respective API phases only."))
        }
    }

    private func latencyPair(_ p50: TimeInterval?, _ p95: TimeInterval?) -> String {
        "\(UsageFormat.reviewLatency(p50)) / \(UsageFormat.reviewLatency(p95))"
    }

    private func heldRate(_ value: Double?) -> String {
        value.map { $0.formatted(.percent.precision(.fractionLength(0...1))) } ?? L("미집계", "No data")
    }

    private func qualityFact(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(AppTypography.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        Surface {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 24, weight: .light)).foregroundStyle(AppTheme.accentForeground)
                Text(!model.preferences.usageTrackingEnabled && model.usageRecords.isEmpty ? L("사용량 기록을 켜면 시작됩니다", "Turn on usage tracking to start") : model.usageRecords.isEmpty ? L("첫 사용부터 기록됩니다", "Usage appears after your first request") : L("선택한 조건에 사용 기록이 없습니다", "No usage matches these filters"))
                    .font(AppTypography.sectionTitle)
                Text(model.preferences.usageTrackingEnabled ? L("음성·문장 처리를 사용하면 확인 가능한 사용량이 표시됩니다.", "Available usage appears after speech or text processing.") : L("기록을 켜면 이후 요청부터 표시됩니다. 꺼진 기간은 나중에 채우지 않습니다.", "Enable tracking to see future requests. Disabled periods are not backfilled."))
                    .font(AppTypography.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 450)
                if !model.usageRecords.isEmpty {
                    Button(L("전체 기록 보기", "Show all usage")) { period = .all; provider = "all" }
                } else {
                    Button(model.preferences.usageTrackingEnabled ? L("모델 설정 보기", "Review models") : L("통계 기록 설정", "Usage tracking settings")) {
                        model.settingsSection = model.preferences.usageTrackingEnabled ? .connection : .privacy
                        model.page = .settings
                    }.disabled(AppLaunch.isPreview)
                }
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
        }
    }

    private func costSummary(_ totals: UsageTotals) -> some View {
        Surface {
            HStack(spacing: 4) {
                Text(L("확인 가능한 비용", "Available cost")).font(AppTypography.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                OptionHelp(title: L("비용 집계", "Cost accounting"), message: L("USD 기준 공급자 보고 비용과 공개 단가 추정치의 합계입니다. 미확인 요청은 합계에서 제외되며 무료 한도·세금·크레딧·할인·환율은 반영하지 않습니다. 최종 청구와 다를 수 있습니다.", "Combines provider-reported costs and public-rate estimates in USD. Unknown costs are excluded; allowances, taxes, credits, discounts and exchange rates are not reflected. This may differ from final billing."))
            }
            Text(totals.hasKnownCost ? UsageFormat.usd(totals.knownUSD) : L("금액 미확인", "Cost unknown"))
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
            if totals.unknownCosts > 0 { Text(L("미확인 \(totals.unknownCosts)회 제외", "Excludes \(totals.unknownCosts) unknown costs")).font(AppTypography.caption).foregroundStyle(AppTheme.warm) }
            DisclosureGroup(L("비용 근거", "Cost details")) {
                VStack(alignment: .leading, spacing: 8) {
                    costPart(L("공급자 보고", "Provider-reported"), value: totals.hasReportedCost ? UsageFormat.usd(totals.reportedUSD) : L("보고 없음", "Not reported"))
                    costPart(L("단가 추정", "Rate estimate"), value: totals.hasEstimatedCost ? UsageFormat.usd(totals.estimatedUSD) : L("추정 없음", "Not estimated"))
                    costPart(L("금액 미확인", "Cost unknown"), value: L("\(totals.unknownCosts)회", "\(totals.unknownCosts) requests"))
                }.padding(.top, 8)
            }.font(AppTypography.caption)
        }.frame(maxHeight: .infinity, alignment: .top)
    }
    private func costPart(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(AppTypography.caption).foregroundStyle(.secondary)
            Text(value).font(AppTypography.body.weight(.medium)).monospacedDigit()
        }
    }
    private func metric(_ title: String, value: String, detail: String, icon: String) -> some View {
        Surface {
            Label(title, systemImage: icon).font(AppTypography.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(AppTypography.caption).foregroundStyle(.secondary)
        }
    }
    private func activityChart(_ report: UsageAnalytics) -> some View {
        Surface(L("일별 처리 활동", "Daily activity")) {
            OptionHelp(title: L("일별 활동", "Daily activity"), message: L("선택한 기간·제공자의 활동 중 최대 최근 30일을 표시합니다. 재시도는 각각의 요청으로 집계합니다.", "Shows up to the last 30 days within the selected period and provider. Each retry counts as a separate request."))
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
                    Text(group.id.model).font(AppTypography.body.weight(.semibold)).textSelection(.enabled).lineLimit(2)
                    Text("\(group.providerName) · \(group.id.stage.title)").font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(group.totals.hasKnownCost ? UsageFormat.usd(group.totals.knownUSD) : L("금액 미확인", "Cost unknown"))
                        .font(AppTypography.body.weight(.medium)).monospacedDigit()
                    Text(group.id.provider == "local" ? L("API 비용 없음", "No API cost") : group.totals.unknownCosts > 0 ? L("미확인 \(group.totals.unknownCosts)회 제외", "Excludes \(group.totals.unknownCosts) unknown costs") : L("보고 비용 + 추정", "Reported + estimated"))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
            }
            Text(L("\(group.totals.records.count)회", "\(group.totals.records.count) requests") +
                 (group.id.provider == "local" ? "" : L(" · 입력 \(UsageFormat.tokens(group.totals.inputTokens)) / 출력 \(UsageFormat.tokens(group.totals.outputTokens)) 토큰", " · Input \(UsageFormat.tokens(group.totals.inputTokens)) / output \(UsageFormat.tokens(group.totals.outputTokens)) tokens")) +
                 (group.totals.audioCount > 0 ? L(" · 음성 \(UsageFormat.duration(group.totals.audioSeconds))", " · Audio \(UsageFormat.duration(group.totals.audioSeconds))") : ""))
                .font(AppTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(UsageFormat.usd(record.cost.usd)).font(AppTypography.body).monospacedDigit()
                            Text(record.event.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)).font(AppTypography.caption).foregroundStyle(.secondary)
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
        }.font(AppTypography.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
    private var accountingNotes: some View {
        Surface {
            HStack {
                Text(L("사용량 보관", "Usage retention")).font(AppTypography.sectionTitle)
                Spacer()
                OptionHelp(title: L("통계 보관과 비용", "Usage retention and cost"), message: L("실패·취소한 요청도 이미 처리되었다면 과금될 수 있어 기록에 남깁니다. 앱 밖 요청이나 기능을 켜기 전 사용량은 포함하지 않으며 미제공 토큰은 추측하지 않습니다. 모델·횟수·수신 토큰·음성 길이·비용만 이 Mac에 암호화해 최근 10,000건까지 보관합니다. 문장 내용·원음·API 키는 통계에 저장하지 않으며 결과 기록의 보관 기간과는 별개입니다.", "Failed or canceled requests can still be billed and remain in usage. Requests outside this app or before tracking was enabled are excluded, and missing tokens are not guessed. Up to 10,000 recent records of models, counts, returned usage, audio duration and costs are encrypted on this Mac. Text, audio and API keys are not stored in usage, and history retention is separate."))
            }
            if let start = model.usageTrackingStartedAt {
                let date = start.formatted(.dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale))
                Text(L("기록 시작: \(date)", "Tracking started: \(date)"))
            }
            if model.usageDiscardedCount > 0 {
                Label(L("보관 한도로 이전 \(model.usageDiscardedCount.formatted())건이 제외되어 전체 합계도 현재 보관된 기록 기준입니다.", "The storage limit removed \(model.usageDiscardedCount.formatted()) older records. Totals reflect only records currently stored."), systemImage: "info.circle")
            }
            HStack {
                Button(L("통계 기록 설정", "Usage tracking settings")) { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
                Spacer()
                Button(L("사용량 기록 초기화…", "Reset usage history…"), role: .destructive) { showsClearConfirmation = true }
                    .disabled(!editable || model.isBusy || (model.usageRecords.isEmpty && model.usageDiscardedCount == 0 && !model.preferences.usageAccountingIncomplete && model.jevQualityMetrics.isEmpty))
            }
            .confirmationDialog(L("이 Mac의 사용량 통계를 초기화할까요?", "Reset usage statistics on this Mac?"), isPresented: $showsClearConfirmation) {
                Button(L("사용량 기록 초기화", "Reset usage history"), role: .destructive) {
                    guard editable, !model.isBusy else { return }
                    Task { await model.clearUsage() }
                }
                Button(L("취소", "Cancel"), role: .cancel) { }
            } message: { Text(L("모델별 사용량·비용 통계와 이번 실행의 Jev 비교 집계가 삭제됩니다. 문장 기록·개인 사전·복구 녹음과 제공자의 실제 청구 내역은 바뀌지 않습니다.", "Deletes model usage and cost statistics and this session’s Jev comparison counts. Text history, your dictionary, recovery recordings and the provider’s actual billing history stay unchanged.")) }
        }.font(AppTypography.caption).foregroundStyle(.secondary)
    }
}
