import AppKit
import AVFoundation
import Observation
import OpenNoTypeCore
import UniformTypeIdentifiers

struct SpeechComparisonResult: Identifiable {
    let id = UUID()
    let model: LocalSpeechModel
    let preparationMilliseconds: Double?
    let transcriptionMilliseconds: Double?
    let transcript: String
    let score: SpeechComparisonScore?
    let error: String?
    var manuallyReviewed = false
    var numberErrors = 0
    var termErrors = 0
    var meaningErrors = 0
}

/// An isolated local experiment. PCM and results live only in this controller; it
/// never downloads a model, calls a provider, types into another app, or writes history.
@MainActor @Observable
final class SpeechComparisonLab {
    nonisolated static let maximumDuration: TimeInterval = 60
    static let exampleText = "오늘 오후 3시에 OpenNoType의 API 설정을 확인해 주세요. 브랜치는 feature/audio이고, 예산은 15,000원입니다."
    private enum Phase { case idle, choosingFile, preparing, recording, importing, comparing, cancelling }

    var expectedText = SpeechComparisonLab.exampleText
    var recordingDuration: TimeInterval = 30
    var selectedModels: Set<LocalSpeechModel> = []
    var results: [SpeechComparisonResult] = []
    private(set) var availableModels: [LocalModelCacheStatus] = []
    private(set) var comparedExpectedText: String?
    private(set) var sampleName: String?
    private(set) var sampleDuration: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Double = 0
    private(set) var status = ""
    private(set) var error: String?
    private(set) var warning: String?
    private(set) var audioCleanupRequired = false
    private var phase: Phase = .idle
    var isBusy: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording }
    var hasSample: Bool { !samples.isEmpty }
    var canCompare: Bool { !isBusy && hasSample && !selectedModels.isEmpty }

    @ObservationIgnored private var samples: [Float] = []
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var captureFailure: String?
    @ObservationIgnored private var loadedModelChoices = false
    @ObservationIgnored private var pendingTemporaryFiles: Set<URL> = []
    @ObservationIgnored private var cleanupWarning: String?

    init() {
        recorder.onAutomaticFinish = { [weak self] in self?.stopRecording() }
        recorder.onFailure = { [weak self] in
            self?.captureFailure = L("비교용 녹음이 중단되었습니다.", "The comparison recording was interrupted.")
            self?.stopRecording()
        }
        recorder.onAudioWarning = { [weak self] in self?.warning = $0 }
    }

    func refreshAvailableModels() async {
        let statuses = await LocalTranscriber().cacheStatuses()
        availableModels = statuses
        let downloaded = Set(statuses.filter(\.isDownloaded).map(\.model))
        if !loadedModelChoices { selectedModels = downloaded; loadedModelChoices = true }
        else { selectedModels.formIntersection(downloaded) }
    }

    func startRecording(preferences: Preferences) {
        guard !isBusy else { return }
        let duration = min(Self.maximumDuration, max(1, recordingDuration.isFinite ? recordingDuration : 30))
        discardSample()
        results = []; comparedExpectedText = nil
        captureFailure = nil; stopRequested = false; elapsed = 0; level = 0
        let job = begin(.preparing, status: L("마이크를 준비하고 있어요…", "Preparing the microphone…"))
        operation = Task { [weak self] in
            guard let self else { return }
            defer { discardRecorderAudio(); finishOperation(job) }
            do {
                try await recorder.start(maximumDuration: duration, inputDeviceUID: preferences.inputDeviceUID,
                    muteSystemAudio: preferences.muteWhileRecording, audioFeedback: preferences.recordingAudioFeedback)
                try Task.checkCancellation()
                guard generation == job else { return }
                phase = .recording
                status = L("같은 음성으로 비교할 내용을 말해 주세요.", "Speak the sample to compare across models.")
                while !stopRequested {
                    try Task.checkCancellation()
                    elapsed = recorder.elapsed; level = recorder.level()
                    try await Task.sleep(for: .milliseconds(100))
                }
                try Task.checkCancellation()
                guard generation == job else { return }
                if let captureFailure { throw LabError.message(captureFailure) }
                _ = recorder.stop()
                if let failure = recorder.lastFailure { throw failure }
                let captured = recorder.pcmSnapshot(maximumSamples: Int(Self.maximumDuration * 16_000))
                discardRecorderAudio()
                try Self.validate(captured)
                samples = captured; sampleDuration = Double(captured.count) / 16_000
                sampleName = L("비교용 녹음", "Comparison recording")
                status = L("음성을 메모리에 준비했습니다. 모델을 골라 비교하세요.", "Audio is ready in memory. Choose models to compare.")
            } catch is CancellationError { }
            catch { if generation == job { self.error = error.localizedDescription } }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        stopRequested = true
        status = L("녹음을 마무리하고 있어요…", "Finishing the recording…")
    }

    func importAudio() {
        guard !isBusy else { return }
        // Keep normal dictation blocked while the file chooser runs its modal loop.
        phase = .choosingFile
        let panel = NSOpenPanel()
        panel.title = L("60초 이내의 비교용 음성 선택", "Choose comparison audio up to 60 seconds")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { phase = .idle; return }
        discardSample(); results = []; comparedExpectedText = nil
        let job = begin(.importing, status: L("음성을 불러오고 있어요…", "Loading audio…"))
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(job) }
            let loading = Task.detached(priority: .userInitiated) { try Self.loadAudio(url) }
            do {
                let captured = try await withTaskCancellationHandler(operation: { try await loading.value },
                    onCancel: { loading.cancel() })
                try Task.checkCancellation()
                guard generation == job else { return }
                samples = captured; sampleDuration = Double(captured.count) / 16_000
                sampleName = url.lastPathComponent
                status = L("음성을 메모리에 준비했습니다. 모델을 골라 비교하세요.", "Audio is ready in memory. Choose models to compare.")
            } catch is CancellationError { }
            catch { if generation == job { self.error = error.localizedDescription } }
        }
    }

    func runComparison() {
        guard canCompare else { return }
        do { _ = try SpeechComparisonScoring.score(reference: expectedText, recognized: "") }
        catch { self.error = error.localizedDescription; return }
        let models = LocalSpeechModel.allCases.filter { selectedModels.contains($0) }
        let downloaded = Set(availableModels.filter(\.isDownloaded).map(\.model))
        guard models.allSatisfy({ downloaded.contains($0) }) else {
            error = L("이 Mac에 준비된 모델만 비교할 수 있습니다.", "Only models already downloaded on this Mac can be compared.")
            return
        }
        let audio = samples, reference = expectedText
        results = []; comparedExpectedText = reference
        let job = begin(.comparing, status: L("모델 비교를 시작합니다…", "Starting model comparison…"))
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(job) }
            for model in models {
                guard !Task.isCancelled, generation == job else { return }
                let engine = LocalTranscriber(model: model)
                var preparationMS: Double?, transcriptionMS: Double?
                status = L("\(model.displayName) 비교 중…", "Comparing \(model.displayName)…")
                do {
                    let preparedAt = ProcessInfo.processInfo.systemUptime
                    let prepared = try await engine.prepareCached()
                    preparationMS = (ProcessInfo.processInfo.systemUptime - preparedAt) * 1_000
                    guard prepared else { throw LabError.modelNotDownloaded }
                    try Task.checkCancellation()
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    let transcript = try await engine.transcribe(samples: audio, dictionary: [])
                    transcriptionMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                    try Task.checkCancellation()
                    let scoring = Task.detached(priority: .userInitiated) {
                        try SpeechComparisonScoring.score(reference: reference, recognized: transcript)
                    }
                    var score: SpeechComparisonScore?
                    var scoringError: String?
                    do {
                        score = try await withTaskCancellationHandler(operation: { try await scoring.value },
                            onCancel: { scoring.cancel() })
                    } catch is CancellationError { throw CancellationError() }
                    catch { scoringError = error.localizedDescription }
                    if generation == job, !Task.isCancelled {
                        results.append(.init(model: model, preparationMilliseconds: preparationMS,
                            transcriptionMilliseconds: transcriptionMS, transcript: transcript,
                            score: score, error: scoringError))
                    }
                } catch is CancellationError {
                    try? await engine.unloadModel()
                    return
                } catch {
                    if generation == job, !Task.isCancelled {
                        results.append(.init(model: model, preparationMilliseconds: preparationMS,
                            transcriptionMilliseconds: transcriptionMS, transcript: "", score: nil,
                            error: error.localizedDescription))
                    }
                }
                // Complete inference/cancellation before unloading; no concurrent engine maintenance.
                try? await engine.unloadModel()
            }
            if generation == job, !Task.isCancelled {
                status = L("비교를 마쳤습니다. 숫자·고유명사·의미는 직접 확인해 주세요.", "Comparison complete. Review numbers, names, and meaning yourself.")
            }
        }
    }

    func cancel() {
        generation = UUID()
        operation?.cancel()
        discardRecorderAudio()
        discardSample()
        if operationID != nil { phase = .cancelling; status = L("취소하고 모델 메모리를 정리하고 있어요…", "Cancelling and releasing model memory…") }
        else { phase = .idle; status = "" }
    }

    func clear() {
        error = nil; warning = nil
        cancel()
        results = []; comparedExpectedText = nil
    }

    func close() {
        clear()
        expectedText = Self.exampleText
    }

    private func begin(_ phase: Phase, status: String) -> UUID {
        let job = UUID(); generation = job; operationID = job
        self.phase = phase; self.status = status; error = nil; warning = nil
        return job
    }

    private func finishOperation(_ job: UUID) {
        guard operationID == job else { return }
        operation = nil; operationID = nil; phase = .idle; level = 0
        if generation != job { status = L("취소했습니다. 비교용 음성을 지웠습니다.", "Cancelled. Comparison audio was cleared.") }
    }

    private func discardSample() {
        samples.removeAll(keepingCapacity: false)
        sampleName = nil; sampleDuration = 0; elapsed = 0
    }

    private func discardRecorderAudio() {
        if let url = recorder.fileURL { pendingTemporaryFiles.insert(url) }
        recorder.discard()
        for url in Array(pendingTemporaryFiles) {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                pendingTemporaryFiles.remove(url)
            } catch {
                let message = L("비교용 임시 원음을 삭제하지 못했습니다. 비교 내용 지우기를 다시 눌러 주세요: \(error.localizedDescription)",
                    "Could not delete temporary comparison audio. Try Clear comparison again: \(error.localizedDescription)")
                cleanupWarning = message; warning = message
            }
        }
        audioCleanupRequired = !pendingTemporaryFiles.isEmpty
        if !audioCleanupRequired {
            if warning == cleanupWarning { warning = nil }
            cleanupWarning = nil
        }
    }

    private nonisolated static func validate(_ samples: [Float]) throws {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw LabError.invalidAudio }
        guard samples.count <= Int(maximumDuration * 16_000) else { throw LabError.tooLong }
    }

    private nonisolated static func loadAudio(_ url: URL) throws -> [Float] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, file.length > 0 else { throw LabError.invalidAudio }
        guard Double(file.length) / format.sampleRate <= maximumDuration,
              file.length <= 24_000_000 else { throw LabError.tooLong }
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                       channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: mono),
              let output = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(maximumDuration * 16_000 + 1))
        else { throw LabError.invalidAudio }
        try file.read(into: input)
        try Task.checkCancellation()
        converter.primeMethod = .none
        var supplied = false
        var conversionError: NSError?
        let conversion = converter.convert(to: output, error: &conversionError) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let conversionError { throw conversionError }
        guard conversion != .error, let channel = output.floatChannelData?.pointee else { throw LabError.invalidAudio }
        try Task.checkCancellation()
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        try validate(samples)
        return samples
    }

    private enum LabError: LocalizedError {
        case invalidAudio, tooLong, modelNotDownloaded, message(String)
        var errorDescription: String? {
            switch self {
            case .invalidAudio: L("비교할 수 있는 음성이 없습니다. 다시 녹음하거나 다른 파일을 선택해 주세요.", "No usable comparison audio. Record again or choose another file.")
            case .tooLong: L("비교용 음성은 최대 60초입니다.", "Comparison audio is limited to 60 seconds.")
            case .modelNotDownloaded: L("모델이 준비되어 있지 않습니다. 음성 모델 화면에서 먼저 다운로드해 주세요.", "The model is not downloaded. Prepare it on the Voice models screen first.")
            case .message(let text): text
            }
        }
    }
}
