import OpenNoTypeCore
import AVFoundation
import AppKit
import AudioToolbox
import Foundation

@MainActor
final class AudioRecorder: NSObject {
    private var engine: AVAudioEngine?
    private var capture: AudioCapture?
    private var configurationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var muteSession: RecordingMuteSession?
    private var readiness: CheckedContinuation<Void, Error>?
    private var readinessTimeout: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var watchdog: RecordingWatchdog?
    private var captureReady = false
    private var audioFeedback = false
    private(set) var fileURL: URL?
    private(set) var activeSamples = 0
    private(set) var lastFailure: Error?
    private var sessionID: UUID?
    private var lastElapsed: TimeInterval = 0
    private var lastPeakDB: Float = -160
    private var startedAt: TimeInterval?
    private var durationLimit: TimeInterval = 540
    var onAutomaticFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    var onCaptureReady: (() -> Void)?
    var onAudioWarning: ((String) -> Void)?

    var peakDB: Float { capture?.currentMetrics().peakDB ?? lastPeakDB }
    var elapsed: TimeInterval {
        guard engine != nil else { return lastElapsed }
        let monotonic = startedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0
        return min(durationLimit, max(lastElapsed, capture?.currentMetrics().elapsed ?? 0, monotonic))
    }

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// Returns only once the selected device has delivered valid PCM, or throws a readiness error.
    func start(maximumDuration: TimeInterval = 540, inputDeviceUID: String? = nil,
               muteSystemAudio: Bool = false, audioFeedback: Bool = false) async throws {
        guard maximumDuration.isFinite, maximumDuration > 0, maximumDuration <= 540 else {
            throw RecordingError.cannotStart
        }
        discard()
        lastElapsed = 0; lastPeakDB = -160; lastFailure = nil; activeSamples = 0
        let session = UUID(); sessionID = session
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard sessionID == session, !Task.isCancelled else { throw CancellationError() }
        guard allowed else { sessionID = nil; throw RecordingError.permissionDenied }
        let url = try TemporaryAudioFiles.makeURL()
        fileURL = url
        durationLimit = maximumDuration
        self.audioFeedback = audioFeedback
        do {
            let device = try AudioDevices.resolveInputDevice(uid: inputDeviceUID)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            guard let unit = input.audioUnit else { throw RecordingError.cannotSelectInputDevice }
            var deviceID = device
            guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &deviceID, UInt32(MemoryLayout.size(ofValue: deviceID))) == noErr else {
                throw RecordingError.cannotSelectInputDevice
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw RecordingError.inputDeviceUnavailable }
            let capture = try AudioCapture(url: url, inputFormat: format, maximumDuration: maximumDuration) { [weak self] event in
                Task { @MainActor [weak self] in self?.handle(event, session: session) }
            }
            self.capture = capture
            self.engine = engine
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in capture.enqueue(buffer) }
            if muteSystemAudio {
                do { muteSession = try RecordingMuteSession(access: .systemOutput()) }
                catch let error as RecordingError { throw error }
                catch { throw RecordingError.cannotMuteSystemAudio }
            }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == session, self.engine?.isRunning == false else { return }
                    self.handle(.failure(RecordingError.captureInterrupted), session: session)
                }
            }
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handle(.failure(RecordingError.captureInterrupted), session: session)
                }
            }
            engine.prepare()
            try engine.start()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard sessionID == session, !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError()); return
                    }
                    readiness = continuation
                    readinessTimeout = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled, let self, self.sessionID == session, !self.captureReady else { return }
                        self.handle(.failure(RecordingError.captureTimedOut), session: session)
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == session else { return }
                    self.discard()
                }
            }
            guard sessionID == session, !Task.isCancelled else { throw CancellationError() }
        } catch {
            // An older start must not stop or delete a replacement recording after its await resumes.
            if sessionID == session {
                finish(playSound: false)
                sessionID = nil
                if let failedURL = fileURL {
                    fileURL = nil; capture = nil
                    do { try FileManager.default.removeItem(at: failedURL) }
                    catch { throw RecordingError.cleanupFailed }
                }
            }
            throw error
        }
    }

    func level() -> Double {
        guard engine != nil, let capture else { return 0 }
        let db = capture.currentMetrics().averageDB
        if db > -55 { activeSamples += 1 }
        return min(1, max(0, Double((db + 60) / 60)))
    }

    /// Copies a bounded tail for live preview without opening or racing the in-progress WAV.
    func pcmSnapshot(maximumSamples: Int? = nil) -> [Float] {
        capture?.snapshot(maximumSamples: maximumSamples) ?? []
    }

    /// Normal dictation can release its memory copy immediately; its finalized WAV and meters remain.
    func releaseStoppedSamples() {
        guard engine == nil else { return }
        if let capture { lastPeakDB = capture.currentMetrics().peakDB }
        capture = nil
    }

    func stop() -> URL? {
        // Stop can run immediately after suspension, before the next watchdog timer.
        if lastFailure == nil { lastFailure = captureProgressFailure() }
        finish(playSound: true)
        sessionID = nil
        return fileURL
    }

    func discard() {
        finish(playSound: true)
        sessionID = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil; capture = nil
    }

    private func handle(_ event: AudioCapture.Event, session: UUID) {
        guard sessionID == session, engine != nil else { return }
        switch event {
        case .ready:
            guard !captureReady else { return }
            captureReady = true
            startedAt = ProcessInfo.processInfo.systemUptime
            watchdog = RecordingWatchdog(readyAt: RecordingWatchdog.now)
            readinessTimeout?.cancel(); readinessTimeout = nil
            let continuation = readiness; readiness = nil
            // A muted output stays muted: the capture-ready visual signal still fires.
            if audioFeedback && muteSession == nil { RecordingFeedback.started() }
            onCaptureReady?()
            continuation?.resume()
            guard sessionID == session, engine != nil else { return }
            watchdogTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.sessionID == session, self.engine != nil else { return }
                    if let error = self.captureProgressFailure() {
                        self.handle(.failure(error), session: session)
                        return
                    }
                }
            }
            durationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(self?.durationLimit ?? 540))
                guard !Task.isCancelled, let self, self.sessionID == session else { return }
                self.handle(.durationLimit, session: session)
            }
        case .durationLimit:
            if let error = captureProgressFailure() {
                handle(.failure(error), session: session)
                return
            }
            finish(playSound: true)
            sessionID = nil
            if lastFailure != nil { onFailure?() }
            else { onAutomaticFinish?() }
        case .failure(let error):
            lastFailure = error
            let wasReady = captureReady
            // Before ready, start() owns the error and temporary-file cleanup.
            finish(playSound: false, readinessError: error)
            if wasReady { sessionID = nil; onFailure?() }
        }
    }

    private func captureProgressFailure() -> RecordingError? {
        guard captureReady, let watchdog, let capture else { return nil }
        let failure = watchdog.failure(at: RecordingWatchdog.now, progress: capture.progressSnapshot(),
                                       reachedDurationLimit: capture.currentMetrics().elapsed >= durationLimit)
        switch failure {
        case .callbackStalled: return .captureSignalStalled
        case .deliveryStalled: return .captureDeliveryStalled
        case nil: return nil
        }
    }

    private func finish(playSound: Bool, readinessError: Error = CancellationError()) {
        readinessTimeout?.cancel(); readinessTimeout = nil
        durationTask?.cancel(); durationTask = nil
        watchdogTask?.cancel(); watchdogTask = nil
        watchdog = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
        let shouldPlaySound = playSound && captureReady && audioFeedback
        lastElapsed = elapsed
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let error = capture?.finish(), lastFailure == nil { lastFailure = error }
        lastElapsed = min(durationLimit, max(lastElapsed, capture?.currentMetrics().elapsed ?? 0))
        lastPeakDB = capture?.currentMetrics().peakDB ?? lastPeakDB
        engine = nil; startedAt = nil; captureReady = false
        let continuation = readiness; readiness = nil
        continuation?.resume(throwing: readinessError)
        do { try muteSession?.restore() }
        catch { onAudioWarning?(RecordingError.cannotRestoreSystemAudio.localizedDescription) }
        muteSession = nil
        if shouldPlaySound && lastFailure == nil { RecordingFeedback.stopped() }
    }

    enum RecordingError: LocalizedError {
        case permissionDenied, cannotStart, cleanupFailed
        case inputDeviceUnavailable, cannotSelectInputDevice, captureTimedOut, captureInterrupted
        case captureSignalStalled, captureDeliveryStalled
        case cannotMuteSystemAudio, cannotRestoreSystemAudio, audioWriteFailed
        var errorDescription: String? {
            switch self {
            case .permissionDenied: L("마이크 권한이 필요합니다. 시스템 설정에서 OpenNoType의 마이크 사용을 허용해 주세요.", "Microphone access is required. Allow OpenNoType to use the microphone in System Settings.")
            case .cannotStart: L("마이크 녹음을 시작하지 못했습니다. 연결 상태를 확인해 주세요.", "Could not start recording. Check your microphone connection.")
            case .cleanupFailed: L("녹음 시작에 실패했고 임시 원음을 삭제하지 못했습니다. 앱을 종료한 뒤 저장소 상태를 확인해 주세요.", "Recording could not start, and the temporary audio could not be deleted. Quit the app and check local storage.")
            case .inputDeviceUnavailable: L("선택한 마이크를 찾지 못했습니다. 연결하거나 설정에서 다른 마이크를 선택해 주세요.", "The selected microphone is unavailable. Connect it or choose another microphone in Settings.")
            case .cannotSelectInputDevice: L("선택한 마이크로 녹음할 수 없습니다. 다른 입력 장치를 선택해 주세요.", "Could not record from the selected microphone. Choose another input device.")
            case .captureTimedOut: L("마이크에서 음성 데이터를 받지 못했습니다. 마이크 연결과 권한을 확인해 주세요.", "The microphone did not deliver audio in time. Check its connection and permissions.")
            case .captureInterrupted: L("마이크 입력이 중단되었습니다. 장치 연결과 다른 앱의 마이크 사용을 확인해 주세요.", "Microphone capture was interrupted. Check the device connection and other apps using the microphone.")
            case .captureSignalStalled: L("마이크의 음성 데이터 수신이 멈췄습니다. 장치 연결을 확인한 뒤 다시 녹음해 주세요.", "Audio stopped arriving from the microphone. Check its connection and record again.")
            case .captureDeliveryStalled: L("녹음 데이터 처리가 멈췄습니다. Mac의 부하와 저장 공간을 확인한 뒤 다시 녹음해 주세요.", "Recording data processing stopped. Check your Mac's workload and available storage, then record again.")
            case .cannotMuteSystemAudio: L("출력 장치를 음소거할 수 없어 녹음을 시작하지 않았습니다. 녹음 중 음소거를 끄거나 출력 장치를 변경해 주세요.", "Recording did not start because the output device could not be muted. Disable mute while recording or change the output device.")
            case .cannotRestoreSystemAudio: L("시스템 음소거를 복원하지 못했습니다. Mac의 음소거 상태를 확인해 주세요.", "System mute could not be restored. Check your Mac's mute setting.")
            case .audioWriteFailed: L("녹음 데이터를 저장하지 못했습니다. 저장 공간을 확인해 주세요.", "Could not save the recording. Check available disk space.")
            }
        }
    }
}
