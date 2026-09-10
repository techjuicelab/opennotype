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
            Text("내가 쓴 만큼, 한눈에").font(.system(size: 25, weight: .semibold)).tracking(-0.6)
            Text("이 Mac의 OpenNoType에서 사용한 음성과 API 요청을 모델별로 확인하세요.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        HStack(spacing: 16) {
            Picker("조회 기간", selection: $period) {
                ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 340)
            Spacer(minLength: 0)
            Picker("제공자", selection: $provider) {
                Text("모든 제공자").tag("all")
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                Text("이 Mac · 로컬").tag("local")
            }.frame(maxWidth: 180)
        }
        if !model.preferences.usageTrackingEnabled {
            Surface {
                Label("사용량 기록이 꺼져 있습니다", systemImage: "pause.circle").font(.system(size: 14, weight: .medium))
                Text("새 요청 수집은 중단됩니다. 끄기 전에 수집해 저장 중이던 기록은 뒤늦게 반영될 수 있습니다.").font(.system(size: 13)).foregroundStyle(.secondary)
                Button("통계 기록 설정") { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
            }
        }
        if let error = model.usageStorageError {
            Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(.orange)
        }
        if report.records.isEmpty {
            emptyState
        } else {
            costSummary(report.totals)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 14) {
                metric("API 요청", value: "\(report.totals.apiRequests.formatted())회", detail: "작업 \(report.totals.jobs)회 · 재시도 \(report.totals.retries)회", icon: "arrow.up.right")
                metric("음성 처리 길이", value: report.totals.audioCount == 0 ? "미제공" : UsageFormat.duration(report.totals.audioSeconds), detail: "재처리·재시도 포함", icon: "waveform")
                metric("집계된 토큰", value: UsageFormat.tokens(report.totals.tokens), detail: "입력 + 출력 · 미제공 제외", icon: "text.alignleft")
            }
            activityChart(report)
            Surface("모델별 사용량") {
                Text("응답에 모델명이 있으면 실제 응답 모델로 묶습니다. 음성 인식과 문장 처리는 각각 집계합니다.")
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

    private var emptyState: some View {
        Surface {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 34, weight: .light)).foregroundStyle(AppTheme.accentForeground)
                Text(!model.preferences.usageTrackingEnabled && model.usageRecords.isEmpty ? "사용량 기록을 켜면 시작됩니다" : model.usageRecords.isEmpty ? "첫 사용부터 기록됩니다" : "선택한 조건에 사용 기록이 없습니다")
                    .font(.system(size: 18, weight: .semibold))
                Text(model.preferences.usageTrackingEnabled ? "음성 인식이나 문장 처리를 사용하면 요청 횟수, 모델, 토큰과 확인 가능한 비용이 여기에 표시됩니다. 이전 버전의 기록에서 비용을 추측해 채우지는 않습니다." : "현재 새 사용량을 기록하지 않습니다. 설정에서 사용량 기록을 켜면 이후 요청부터 표시됩니다. 기록이 꺼져 있던 기간은 나중에 채워지지 않습니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 450)
                Button(model.preferences.usageTrackingEnabled ? "사용할 모델 확인" : "통계 기록 설정") {
                    model.settingsSection = model.preferences.usageTrackingEnabled ? .connection : .privacy
                    model.page = .settings
                }.disabled(AppLaunch.isPreview)
            }.padding(.vertical, 28).frame(maxWidth: .infinity)
        }
    }

    private func costSummary(_ totals: UsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("확인 가능한 비용 · USD", systemImage: "creditcard").font(.system(size: 13, weight: .medium))
                Spacer()
                if totals.unknownCosts > 0 {
                    Text("일부 비용 미확인").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5).background(.background.opacity(0.6), in: Capsule())
                }
            }
            Text(totals.hasKnownCost ? UsageFormat.usd(totals.knownUSD) : "금액 미확인")
                .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(alignment: .top, spacing: 24) {
                costPart("공급자 보고", value: totals.hasReportedCost ? UsageFormat.usd(totals.reportedUSD) : "보고 없음")
                costPart("단가 기반 추정", value: totals.hasEstimatedCost ? UsageFormat.usd(totals.estimatedUSD) : "추정 없음")
                costPart("금액 미확인", value: "\(totals.unknownCosts)회")
                Spacer(minLength: 0)
            }
            Text("제공자 응답의 비용과 공개 단가로 계산한 추정치의 합계입니다. 미확인 요청은 합계에서 제외되며, 최종 청구액과 다를 수 있습니다.")
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
        Surface("일별 처리 활동") {
            Text("선택한 기간·제공자의 활동 중 최대 최근 30일을 표시합니다. 재시도는 각각의 요청으로 집계합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Chart(report.recentDays) { day in
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("처리 횟수", day.requests))
                    .foregroundStyle(by: .value("구분", "API 요청"))
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("처리 횟수", day.localOperations))
                    .foregroundStyle(by: .value("구분", "로컬 음성 인식"))
            }
            .chartForegroundStyleScale(["API 요청": AppTheme.accent, "로컬 음성 인식": AppTheme.warm])
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
            .accessibilityLabel("선택한 기간 중 차트에 표시된 API 요청 \(report.recentDays.reduce(0) { $0 + $1.requests })회, 로컬 음성 인식 \(report.recentDays.reduce(0) { $0 + $1.localOperations })회")
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
                    Text(group.totals.hasKnownCost ? UsageFormat.usd(group.totals.knownUSD) : "금액 미확인")
                        .font(.system(size: 16, weight: .medium)).monospacedDigit()
                    Text(group.id.provider == "local" ? "API 비용 없음" : group.totals.unknownCosts > 0 ? "미확인 \(group.totals.unknownCosts)회 제외" : "보고 비용 + 추정")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text("\(group.totals.records.count)회" +
                 (group.id.provider == "local" ? "" : " · 입력 \(UsageFormat.tokens(group.totals.inputTokens)) / 출력 \(UsageFormat.tokens(group.totals.outputTokens)) 토큰") +
                 (group.totals.audioCount > 0 ? " · 음성 \(UsageFormat.duration(group.totals.audioSeconds))" : ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func recentRequests(_ records: [UsageRecord]) -> some View {
        Surface("최근 요청 · 최대 20개") {
            ForEach(Array(records.prefix(20))) { record in
                DisclosureGroup(isExpanded: Binding(get: { expandedRequest == record.id }, set: { expandedRequest = $0 ? record.id : nil })) {
                    requestDetails(record).padding(.top, 10)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.event.effectiveModel).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("\(record.event.stage.title) · \(record.event.outcome.title)" + (record.isRecovery ? " · 다시 처리" : "") + (record.event.attempt > 1 ? " · 자동 재시도" : ""))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(UsageFormat.usd(record.cost.usd)).font(.system(size: 13)).monospacedDigit()
                            Text(record.event.createdAt, format: .dateTime.month().day().hour().minute()).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    private func requestDetails(_ record: UsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(record.event.provider?.displayName ?? "이 Mac") · \(record.mode.title) · \(record.cost.kind.title)")
            if record.event.effectiveModel != record.event.model { Text("요청 모델: \(record.event.model)") }
            Text("\(record.event.provider == .anthropic ? "캐시 제외 입력" : "입력") \(UsageFormat.tokens(record.event.inputTokens)) · 출력 \(UsageFormat.tokens(record.event.outputTokens)) 토큰")
            if let cached = record.event.cachedInputTokens { Text("캐시 읽기: \(cached.formatted()) 토큰") }
            if let written = record.event.cacheWriteTokens { Text("캐시 쓰기: \(written.formatted()) 토큰") }
            if let audio = record.event.audioInputTokens { Text("입력 중 오디오: \(audio.formatted()) 토큰") }
            if let reasoning = record.event.reasoningTokens { Text("출력 중 추론: \(reasoning.formatted()) 토큰") }
            if let duration = record.event.audioSeconds { Text("음성 처리 길이: \(UsageFormat.duration(duration))") }
            if let note = record.cost.note { Text(note) }
            if let checked = record.cost.checkedAt { Text("단가 확인: \(checked)") }
            if let source = record.cost.sourceURL, let url = URL(string: source), url.scheme == "https" { Link("비용 근거 확인", destination: url) }
        }.font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
    }
    private var accountingNotes: some View {
        Surface("통계와 비용을 읽는 방법") {
            Text("음성 인식과 문장 처리의 사용량을 따로 기록합니다. 실패·취소한 요청도 이미 처리되었다면 과금될 수 있어 기록에 남깁니다. 앱 밖에서 사용한 요청이나 이 기능을 켜기 전의 사용량은 포함되지 않습니다.")
            Text("사용량 응답이 없는 모델은 토큰을 추측하지 않습니다. 비용은 USD 기준이며 무료 한도·세금·크레딧·계정별 할인·환율은 반영하지 않습니다. 실제 청구는 제공자 대시보드에서 확인하세요.")
            if let start = model.usageTrackingStartedAt {
                Text("기록 시작: \(start.formatted(date: .abbreviated, time: .shortened))")
            }
            Text("모델·횟수·수신 토큰·음성 길이·비용 정보만 이 Mac에 암호화해 최근 10,000건까지 보관합니다. 문장 내용·원음·API 키는 통계에 저장하지 않습니다. 결과 기록의 보관 기간과는 별개입니다.")
            if model.usageDiscardedCount > 0 {
                Label("보관 한도로 이전 \(model.usageDiscardedCount.formatted())건이 제외되어 전체 합계도 현재 보관된 기록 기준입니다.", systemImage: "info.circle")
            }
            HStack {
                Button("통계 기록 설정") { model.settingsSection = .privacy; model.page = .settings }.disabled(AppLaunch.isPreview)
                Spacer()
                Button("사용량 기록 초기화…", role: .destructive) { showsClearConfirmation = true }
                    .disabled(AppLaunch.isPreview || model.isBusy || (model.usageRecords.isEmpty && model.usageDiscardedCount == 0 && !model.preferences.usageAccountingIncomplete))
            }
            .confirmationDialog("이 Mac의 사용량 통계를 초기화할까요?", isPresented: $showsClearConfirmation) {
                Button("사용량 기록 초기화", role: .destructive) { Task { await model.clearUsage() } }
                Button("취소", role: .cancel) { }
            } message: { Text("모델별 사용량과 비용 통계가 삭제됩니다. 문장 기록·개인 사전·복구 녹음과 제공자의 실제 청구 내역은 바뀌지 않습니다.") }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
    }
}
