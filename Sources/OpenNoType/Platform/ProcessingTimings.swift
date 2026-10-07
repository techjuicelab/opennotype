import OpenNoTypeCore
import Foundation
import os

/// Local diagnostics contain durations only, never audio, text, context, or credentials.
struct ProcessingTimings {
    enum Stage: String {
        case audioPreparation, transcription, textProcessing, translationRefinement, decisionReview, insertion, storage
        var title: String {
            switch self {
            case .audioPreparation: L("음성 준비", "Audio preparation")
            case .transcription: L("음성 인식", "Transcription")
            case .textProcessing: L("문장 정리", "Text cleanup")
            case .translationRefinement: L("번역 다듬기", "Translation refinement")
            case .decisionReview: L("Jev 검토", "Jev review")
            case .insertion: L("입력·확인", "Insert and verify")
            case .storage: L("기록 갱신", "History update")
            }
        }
    }
    private static let logger = Logger(subsystem: "app.opennotype.mac", category: "pipeline")
    private let job: UUID
    private let startedAt: TimeInterval
    private var previous: TimeInterval
    private var measurements: [(Stage, TimeInterval)] = []

    init(job: UUID, startedAt: TimeInterval) {
        self.job = job; self.startedAt = startedAt; self.previous = startedAt
    }

    mutating func mark(_ stage: Stage) {
        let now = ProcessInfo.processInfo.systemUptime
        let duration = max(0, now - previous)
        measurements.append((stage, duration)); previous = now
        let jobID = job.uuidString
        let elapsedMS = Int(max(0, now - startedAt) * 1000)
        Self.logger.notice("job=\(jobID, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(Int(duration * 1000), privacy: .public) elapsed_ms=\(elapsedMS, privacy: .public)")
    }

    var summary: String {
        let stages = measurements.map { L("\($0.0.title) \(String(format: "%.2f", $0.1))초", "\($0.0.title) \(String(format: "%.2f", $0.1))s") }
        return (stages + [L("전체 \(String(format: "%.2f", max(0, previous - startedAt)))초", "Total \(String(format: "%.2f", max(0, previous - startedAt)))s")]).joined(separator: " · ")
    }
}
