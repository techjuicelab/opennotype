import Foundation
import os

/// Local diagnostics contain durations only, never audio, text, context, or credentials.
struct ProcessingTimings {
    enum Stage: String {
        case audioPreparation, transcription, textProcessing, insertion, storage
        var title: String {
            switch self {
            case .audioPreparation: "음성 준비"
            case .transcription: "음성 인식"
            case .textProcessing: "문장 정리"
            case .insertion: "입력·확인"
            case .storage: "기록 갱신"
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
        Self.logger.info("job=\(jobID, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(Int(duration * 1000)) elapsed_ms=\(elapsedMS)")
    }

    var summary: String {
        let stages = measurements.map { "\($0.0.title) \(String(format: "%.2f", $0.1))초" }
        return (stages + ["전체 \(String(format: "%.2f", max(0, previous - startedAt)))초"]).joined(separator: " · ")
    }
}
