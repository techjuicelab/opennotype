import AppKit
import AVFoundation
import Foundation
import OpenNoTypeCore

/// Synthetic design data is available only to the separately identified debug preview app.
/// A release build or the normal app bundle always constructs the real application model.
@MainActor
enum AppLaunch {
    static var isPreview: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier == "app.opennotype.usage-preview"
        #else
        false
        #endif
    }

    static func makeModel() -> AppModel {
        #if DEBUG
        if isPreview { return makePreviewModel() }
        #endif
        return AppModel()
    }

    #if DEBUG
    private static func makePreviewModel() -> AppModel {
        var preferences = Preferences()
        preferences.provider = .groq
        preferences.usageTrackingEnabled = true
        preferences.automaticLearningEnabled = false
        preferences.appearance = (ProcessInfo.processInfo.arguments.contains("--preview-dark") || Bundle.main.object(forInfoDictionaryKey: "OpenNoTypePreviewAppearance") as? String == "dark") ? "dark" : "light"

        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.capture = { _ in nil }
        runtime.accessibilityPermitted = { true }
        runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.requestMicrophone = { false }
        runtime.readKey = { _ in nil }
        runtime.makeTemporaryAudioURL = { throw PreviewOperationUnavailable() }
        runtime.startRecording = { _ in throw PreviewOperationUnavailable() }
        runtime.stopRecording = { nil }
        runtime.recordingPeakDB = { -160 }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewRejectNetwork.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let client = ProviderClient(session: URLSession(configuration: configuration))
        let model = AppModel(runtime: runtime, client: client, startServices: false, preferences: preferences)
        let now = Date()
        model.usageRecords = sampleRecords(now: now)
        model.usageTrackingStartedAt = model.usageRecords.map(\.event.createdAt).min()
        if ProcessInfo.processInfo.arguments.contains("--preview-history") || Bundle.main.object(forInfoDictionaryKey: "OpenNoTypePreviewPage") as? String == "history" {
            model.history = [
                .init(createdAt: now, mode: .dictation,
                      originalText: "어 자료에는 매출을 넣어 주세요 그 자료에는 매출하고 환불 건수도 넣어 주세요 환불 사유는 상위 세 개만 있으면 돼요",
                      resultText: "자료에는 매출과 환불 건수를 넣어 주세요. 환불 사유는 상위 세 개만 있으면 돼요.",
                      sourceBundleID: "com.openai.codex", provider: .groq),
                .init(createdAt: now.addingTimeInterval(-60), mode: .translation, originalText: "시간이 되면 이 부분만 봐주실 수 있을까요 급한 건 아니에요",
                      resultText: "If you have time, could you look at just this part? There's no rush.",
                      sourceBundleID: "com.apple.Notes", provider: .groq),
                .init(createdAt: now.addingTimeInterval(-120), mode: .rewrite, originalText: "9월 17일만 9월 24일로 바꿔 줘",
                      resultText: "기존 화면은 9월 24일까지 유지됩니다.", provider: .groq)
            ]
            model.page = .history
            model.notice = "디자인 검증용 합성 기록 · 실제 녹음이나 모델 평가 결과가 아닙니다."
        } else if ProcessInfo.processInfo.arguments.contains("--preview-updates") || Bundle.main.object(forInfoDictionaryKey: "OpenNoTypePreviewPage") as? String == "updates" {
            model.page = .settings
            model.settingsSection = .general
            model.notice = "디자인 검증용 샘플 · 업데이트 서버에 연결하지 않습니다."
        } else {
            model.page = .usage
            model.notice = "디자인 검증용 샘플 · 실제 사용량이 아닙니다."
        }
        return model
    }

    private static func sampleRecords(now: Date) -> [UsageRecord] {
        let calendar = Calendar.current
        var records: [UsageRecord] = []
        for day in 0..<7 {
            let createdAt = (calendar.date(byAdding: .day, value: -day, to: now) ?? now).addingTimeInterval(-900)
            let job = UUID()
            records.append(UsageRecord(jobID: job, mode: .dictation,
                event: ProviderUsage(createdAt: createdAt, provider: .groq, model: "whisper-large-v3-turbo",
                                     stage: .transcription, audioSeconds: Double(35 + day * 13))))
            records.append(UsageRecord(jobID: job, mode: .dictation,
                event: ProviderUsage(createdAt: createdAt.addingTimeInterval(3), provider: .groq,
                                     model: "openai/gpt-oss-120b", stage: .textProcessing,
                                     inputTokens: 1_900 + day * 180, outputTokens: 280 + day * 45,
                                     cachedInputTokens: 450)))
        }
        let sharedJob = UUID()
        records.append(UsageRecord(jobID: sharedJob, mode: .translation,
            event: ProviderUsage(createdAt: now.addingTimeInterval(-400), provider: .openAI,
                                 model: "gpt-4.1-mini", reportedModel: "gpt-4.1-mini-2025-04-14",
                                 stage: .textProcessing, inputTokens: 4_860, outputTokens: 1_020,
                                 cachedInputTokens: 3_200)))
        records.append(UsageRecord(jobID: UUID(), mode: .rewrite,
            event: ProviderUsage(createdAt: now.addingTimeInterval(-350), provider: .openRouter,
                                 model: "openai/gpt-4.1-mini", stage: .textProcessing,
                                 inputTokens: 1_850, outputTokens: 610, providerCostUSD: 0.0249)))
        records.append(UsageRecord(jobID: UUID(), mode: .dictation,
            event: ProviderUsage(createdAt: now.addingTimeInterval(-300), provider: .openRouter,
                                 model: "openai/gpt-oss-20b:free", stage: .textProcessing,
                                 inputTokens: 870, outputTokens: 190, providerCostUSD: 0)))
        records.append(UsageRecord(jobID: UUID(), mode: .dictation, isRecovery: true,
            event: ProviderUsage(createdAt: now.addingTimeInterval(-250), provider: .openRouter,
                                 model: "sample/unpriced-model", stage: .textProcessing,
                                 outcome: .failed, attempt: 2, httpStatus: 503)))
        for offset in 0..<3 {
            let createdAt = (calendar.date(byAdding: .day, value: -offset, to: now) ?? now).addingTimeInterval(-200)
            records.append(UsageRecord(jobID: UUID(), mode: .dictation,
                event: ProviderUsage(createdAt: createdAt, model: "Whisper Large v3",
                                     stage: .transcription, audioSeconds: Double(48 + offset * 26))))
        }
        return records
    }
    #endif
}

#if DEBUG
private struct PreviewOperationUnavailable: LocalizedError {
    var errorDescription: String? { "디자인 검증 앱에서는 녹음·입력·API 처리를 사용할 수 없습니다." }
}

/// Even if a UI path accidentally starts a provider request, the preview never opens the network.
private final class PreviewRejectNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: PreviewOperationUnavailable()) }
    override func stopLoading() {}
}
#endif
