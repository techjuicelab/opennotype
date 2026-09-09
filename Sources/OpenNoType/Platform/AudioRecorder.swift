import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?
    private(set) var peakDB: Float = -160
    private(set) var activeSamples = 0
    private var sessionID: UUID?
    private var lastElapsed: TimeInterval = 0
    private var startedAt: TimeInterval?
    private var durationLimit: TimeInterval = 540
    var onAutomaticFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    var elapsed: TimeInterval {
        guard let recorder else { return lastElapsed }
        return measuredElapsed(recorder)
    }

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    func start(maximumDuration: TimeInterval = 540) async throws {
        guard maximumDuration.isFinite, maximumDuration > 0, maximumDuration <= 540 else { throw RecordingError.cannotStart }
        discard()
        lastElapsed = 0
        let session = UUID(); sessionID = session
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard sessionID == session, !Task.isCancelled else { throw CancellationError() }
        guard allowed else { throw RecordingError.permissionDenied }
        let url = try TemporaryAudioFiles.makeURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ]
        var pending: AVAudioRecorder?
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            pending = recorder
            recorder.isMeteringEnabled = true
            recorder.delegate = self
            guard recorder.prepareToRecord() else { throw RecordingError.cannotStart }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            startedAt = ProcessInfo.processInfo.systemUptime; durationLimit = maximumDuration
            guard recorder.record(forDuration: maximumDuration) else { throw RecordingError.cannotStart }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            self.recorder = recorder; fileURL = url; peakDB = -160; activeSamples = 0
        } catch {
            pending?.delegate = nil; pending?.stop()
            startedAt = nil; sessionID = nil; fileURL = nil
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { throw RecordingError.cleanupFailed }
            }
            throw error
        }
    }
    func level() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        peakDB = max(peakDB, db)
        if db > -55 { activeSamples += 1 }
        return min(1, max(0, Double((db + 60) / 60)))
    }
    func stop() -> URL? {
        if let recorder { lastElapsed = measuredElapsed(recorder) }
        recorder?.stop(); recorder = nil
        startedAt = nil
        return fileURL
    }
    func discard() {
        sessionID = nil
        if let recorder { lastElapsed = measuredElapsed(recorder) }
        recorder?.stop(); recorder = nil
        startedAt = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            self.lastElapsed = self.measuredElapsed(current)
            if flag { self.onAutomaticFinish?() } else { self.onFailure?() }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            self.onFailure?()
        }
    }
    private func measuredElapsed(_ recorder: AVAudioRecorder) -> TimeInterval {
        let monotonic = startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0
        return min(durationLimit, max(lastElapsed, recorder.currentTime, monotonic))
    }
    enum RecordingError: LocalizedError {
        case permissionDenied, cannotStart, cleanupFailed
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "마이크 권한이 필요합니다. 시스템 설정에서 OpenNoType의 마이크 사용을 허용해 주세요."
            case .cannotStart: "마이크 녹음을 시작하지 못했습니다. 연결 상태를 확인해 주세요."
            case .cleanupFailed: "녹음 시작에 실패했고 임시 원음을 삭제하지 못했습니다. 앱을 종료한 뒤 저장소 상태를 확인해 주세요."
            }
        }
    }
}
