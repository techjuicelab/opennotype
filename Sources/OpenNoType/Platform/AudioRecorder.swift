import OpenNoTypeCore
import AVFoundation
import AppKit
import AudioToolbox
import Foundation
import OpenNoTypeObjC
import os

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
    /// Identifies the current tap and capture; events from a replaced capture are ignored.
    private var captureGeneration: UUID?
    private var tapFormat: AVAudioFormat?
    private var reconfigureCount = 0
    /// The microphone chosen in Settings; nil while the engine follows the system default.
    private var selectedDevice: AudioDeviceID?
    private var firstAudioCheck: Task<Void, Never>?
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
            // Validates that an input exists even when the engine follows the system default.
            let device = try AudioDevices.resolveInputDevice(uid: inputDeviceUID)
            let engine = AVAudioEngine()
            self.engine = engine
            reconfigureCount = 0
            selectedDevice = nil
            // Only a microphone chosen in Settings is selected on the input unit. Selecting the
            // default device explicitly as well makes AirPods run their headset microphone at
            // 24 kHz while the engine keeps 48 kHz, so the tap never receives audio; the engine's
            // own default-device path handles that switch.
            if let inputDeviceUID, !inputDeviceUID.isEmpty {
                guard let unit = engine.inputNode.audioUnit else { throw RecordingError.cannotSelectInputDevice }
                var deviceID = device
                guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                           &deviceID, UInt32(MemoryLayout.size(ofValue: deviceID))) == noErr else {
                    throw RecordingError.cannotSelectInputDevice
                }
                selectedDevice = device
            }
            try installTap(url: url, session: session)
            if muteSystemAudio {
                do { muteSession = try RecordingMuteSession(access: .systemOutput()) }
                catch let error as RecordingError { throw error }
                catch { throw RecordingError.cannotMuteSystemAudio }
            }
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handle(.failure(RecordingError.captureInterrupted), session: session)
                }
            }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.configurationChanged(session: session) }
            }
            engine.prepare()
            try engine.start()
            // A Bluetooth headset can switch profile as the input starts, before the notification.
            if hardwareFormatDiffersFromTap() { reconfigure(session: session) }
            else { checkFirstAudio(session: session) }
            // A failed reconfiguration has already finished the engine; no audio can arrive.
            guard engine.isRunning, self.engine === engine else { throw lastFailure ?? RecordingError.cannotStart }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard sessionID == session, !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError()); return
                    }
                    readiness = continuation
                    armReadinessTimeout(session: session)
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

    /// Adds the capture and tap at the input node's current format. When the node lags a hardware
    /// format change, the client format is first set to the hardware format so the tap matches it.
    private func installTap(url: URL, session: UUID) throws {
        guard let engine else { throw RecordingError.cannotStart }
        let input = engine.inputNode
        let hardware = currentHardwareFormat(input)
        if let hardware, !Self.matches(input.outputFormat(forBus: 0), hardware),
           let unit = input.audioUnit,
           let client = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: hardware.channelCount) {
            var description = client.streamDescription.pointee
            let status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                              &description, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
            Self.log.info("input client format set to \(hardware.sampleRate, privacy: .public) Hz, status \(status, privacy: .public)")
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecordingError.inputDeviceUnavailable }
        let generation = UUID()
        captureGeneration = generation
        let capture = try AudioCapture(url: url, inputFormat: format, maximumDuration: durationLimit) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event, session: session, generation: generation) }
        }
        var reason: NSString?
        // installTap raises an Objective-C exception, which Swift cannot catch and which would
        // terminate the app, when its format no longer matches the hardware.
        let installed = ONTPerformCatchingException({
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in capture.enqueue(buffer) }
        }, &reason)
        guard installed else {
            Self.log.error("input tap rejected at \(format.sampleRate, privacy: .public) Hz: \((reason as String?) ?? "", privacy: .public)")
            captureGeneration = nil
            capture.finish()
            throw RecordingError.cannotSelectInputDevice
        }
        tapFormat = format
        self.capture = capture
    }

    /// For a selected device, Core Audio's sample rate wins over the input node's, which can still
    /// hold the rate from before a Bluetooth profile switch.
    private func currentHardwareFormat(_ input: AVAudioInputNode) -> AVAudioFormat? {
        let reported = input.inputFormat(forBus: 0)
        guard reported.sampleRate > 0, reported.channelCount > 0 else { return nil }
        guard let selectedDevice, let rate = AudioDevices.nominalSampleRate(selectedDevice),
              rate != reported.sampleRate else { return reported }
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: reported.channelCount)
    }

    private func armReadinessTimeout(session: UUID) {
        readinessTimeout?.cancel()
        readinessTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.sessionID == session, !self.captureReady else { return }
            self.handle(.failure(RecordingError.captureTimedOut), session: session)
        }
    }

    private static func matches(_ format: AVAudioFormat, _ hardware: AVAudioFormat) -> Bool {
        // An unreported hardware format cannot be compared; the tap then follows the node as before.
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { return true }
        return format.sampleRate == hardware.sampleRate && format.channelCount == hardware.channelCount
    }

    private func hardwareFormatDiffersFromTap() -> Bool {
        guard let engine else { return false }
        guard let tapFormat else { return true }
        guard let hardware = currentHardwareFormat(engine.inputNode) else { return false }
        return !Self.matches(tapFormat, hardware)
    }

    private func configurationChanged(session: UUID) {
        guard sessionID == session, let engine else { return }
        if captureReady {
            guard !engine.isRunning else { return }
            handle(.failure(RecordingError.captureInterrupted), session: session)
            return
        }
        // Before the first PCM nothing has been recorded, so a changed or stopped input is set up
        // again instead of failing. A selected AirPods microphone switches to its headset profile
        // when input starts and runs at 24 kHz under a tap installed at 48 kHz.
        if hardwareFormatDiffersFromTap() || !engine.isRunning { reconfigure(session: session) }
    }

    /// Reinstalls the tap and capture at the new hardware format on the same engine, which keeps the
    /// device selected. Past the limit the readiness timeout reports the failure.
    private func reconfigure(session: UUID) {
        guard sessionID == session, !captureReady, reconfigureCount < Self.maximumReconfigurations,
              let engine, let url = fileURL else { return }
        reconfigureCount += 1
        Self.log.info("reconfiguring input before first audio, attempt \(self.reconfigureCount, privacy: .public)")
        engine.stop()
        if tapFormat != nil { engine.inputNode.removeTap(onBus: 0) }
        tapFormat = nil; captureGeneration = nil
        // No audio was written; the next capture rewrites the same owner-only reserved file.
        capture?.finish(); capture = nil
        do {
            try installTap(url: url, session: session)
            engine.prepare()
            try engine.start()
            if readiness != nil { armReadinessTimeout(session: session) }
            checkFirstAudio(session: session)
        } catch {
            // Before readiness the pending start owns the error and the temporary-file cleanup.
            lastFailure = error
            finish(playSound: false, readinessError: error)
        }
    }

    /// A selected Bluetooth microphone can finish its profile switch without a notification and leave
    /// the tap silent. It normally delivers audio within half a second, so a silent start is set up
    /// again early instead of waiting for the readiness timeout. Wired microphones are left alone:
    /// a slow one must not be restarted before it delivers.
    private func checkFirstAudio(session: UUID) {
        firstAudioCheck?.cancel(); firstAudioCheck = nil
        guard let selectedDevice, AudioDevices.isBluetooth(selectedDevice) else { return }
        firstAudioCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, self.sessionID == session, !self.captureReady else { return }
            self.firstAudioCheck = nil
            Self.log.info("selected Bluetooth input delivered no audio yet")
            self.reconfigure(session: session)
        }
    }

    private static let maximumReconfigurations = 3
    private static let log = Logger(subsystem: "app.opennotype.mac", category: "recording")

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

    private func handle(_ event: AudioCapture.Event, session: UUID, generation: UUID? = nil) {
        guard sessionID == session, engine != nil else { return }
        if let generation, generation != captureGeneration { return }
        switch event {
        case .ready:
            guard !captureReady else { return }
            captureReady = true
            if reconfigureCount > 0 { Self.log.info("input ready after \(self.reconfigureCount, privacy: .public) reconfiguration(s)") }
            startedAt = ProcessInfo.processInfo.systemUptime
            watchdog = RecordingWatchdog(readyAt: RecordingWatchdog.now)
            readinessTimeout?.cancel(); readinessTimeout = nil
            firstAudioCheck?.cancel(); firstAudioCheck = nil
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
        firstAudioCheck?.cancel(); firstAudioCheck = nil
        durationTask?.cancel(); durationTask = nil
        watchdogTask?.cancel(); watchdogTask = nil
        watchdog = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
        let shouldPlaySound = playSound && captureReady && audioFeedback
        lastElapsed = elapsed
        if tapFormat != nil { engine?.inputNode.removeTap(onBus: 0) }
        engine?.stop()
        if let error = capture?.finish(), lastFailure == nil { lastFailure = error }
        if capture?.isAbandoned == true, let abandonedURL = fileURL {
            // A writer that never drained may still hold this incomplete WAV. Recovery, transcription
            // and insertion must not read it, so stop() reports no recording and the file is removed.
            fileURL = nil
            try? FileManager.default.removeItem(at: abandonedURL)
        }
        lastElapsed = min(durationLimit, max(lastElapsed, capture?.currentMetrics().elapsed ?? 0))
        lastPeakDB = capture?.currentMetrics().peakDB ?? lastPeakDB
        engine = nil; startedAt = nil; captureReady = false
        captureGeneration = nil; tapFormat = nil
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
