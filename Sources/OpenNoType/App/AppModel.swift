import AppKit
import AVFoundation
import Observation
import OpenNoTypeCore
import ServiceManagement

@MainActor @Observable
final class AppModel {
    enum Phase { case idle, starting, recording, enrolling, processing }
    private struct ProcessingSnapshot {
        var configuration: ProviderConfiguration
        var needsLocal: Bool
        var speakerFilter: Bool
        var targetLanguage: String
        var dictionary: [DictionaryEntry]
    }
    var preferences = Preferences.load() { didSet { preferences.save() } }
    var page: AppPage = .home
    var phase: Phase = .idle
    var mode: InputMode = .dictation
    var elapsed: TimeInterval = 0
    var level: Double = 0
    var notice: String?
    var error: String?
    var result: String = ""
    var history: [HistoryEntry] = []
    var dictionary: [DictionaryEntry] = []
    var failures: [FailedRecording] = []
    var apiKeyDraft = ""
    var retrySelection = ""
    var keySaved = false
    var localState: LocalModelState = .notPrepared
    var speakerState: LocalModelState = .notPrepared
    var hasSpeakerProfile = false
    var learningCandidate: LearningCandidate?
    var accessibilityAllowed = TextInsertion.permitted
    var microphoneAllowed = AudioRecorder.permission == .authorized
    @ObservationIgnored private var store: SecureStore?
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let client = ProviderClient()
    @ObservationIgnored private let local = LocalTranscriber()
    @ObservationIgnored private var speaker: LocalSpeakerRecognizer?
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var learningTask: Task<Void, Never>?
    @ObservationIgnored private var housekeepingTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var target: InputTarget?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var snapshot: ProcessingSnapshot?
    @ObservationIgnored var showManager: (() -> Void)?
    @ObservationIgnored var onPhaseChange: (() -> Void)?

    var isBusy: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording || phase == .enrolling }
    var countdown: Int? { phase == .enrolling ? max(0, Int(ceil(30 - elapsed))) : RecordingPolicy.countdown(elapsed: elapsed) }
    var status: String {
        switch phase {
        case .idle: "말할 준비가 되었어요"
        case .starting: "마이크를 준비하고 있어요"
        case .recording: mode == .translation ? "번역할 내용을 말해 주세요" : mode == .rewrite ? "수정할 내용을 말해 주세요" : "듣고 있어요"
        case .enrolling: "평소 목소리로 10초 이상 말해 주세요"
        case .processing: "말씀하신 내용을 정리하고 있어요"
        }
    }

    init() {
        do { try TemporaryAudioFiles.cleanupDeadSessions() }
        catch { self.error = "이전 임시 녹음을 정리하지 못했습니다. \(error.localizedDescription)" }
        do {
            let store = try SecureStore(); self.store = store
            speaker = LocalSpeakerRecognizer(profileStore: SpeakerStoreAdapter(store: store))
        } catch { self.error = "저장소를 열지 못했습니다. 기존 데이터는 보존됩니다. \(error.localizedDescription)" }
        hotkeys.onPress = { [weak self] mode in Task { await self?.toggle(mode) } }
        recorder.onAutomaticFinish = { [weak self] in self?.stop() }
        do { try hotkeys.register(preferences.hotkeys) } catch { self.error = error.localizedDescription }
        loadKey()
        Task { await refreshData(); hasSpeakerProfile = (try? await speaker?.hasProfile()) ?? false }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
                try? TemporaryAudioFiles.cleanupCurrentSession()
            }
        }
        housekeepingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await self?.refreshData()
            }
        }
    }
    func refreshPermissions() {
        accessibilityAllowed = TextInsertion.permitted
        microphoneAllowed = AudioRecorder.permission == .authorized
    }
    func requestMicrophone() async {
        microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
    }
    func loadKey() {
        do { apiKeyDraft = try KeychainSecrets.read(for: preferences.provider) ?? ""; keySaved = !apiKeyDraft.isEmpty }
        catch { self.error = error.localizedDescription; apiKeyDraft = ""; keySaved = false }
    }
    func saveKey() {
        do {
            let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { try KeychainSecrets.delete(for: preferences.provider) }
            else { try KeychainSecrets.save(key, for: preferences.provider) }
            keySaved = !key.isEmpty; notice = keySaved ? "API 키를 이 Mac의 Keychain에 저장했습니다." : "API 키를 삭제했습니다."
        } catch { self.error = error.localizedDescription }
    }
    func updateHotkey(_ binding: HotkeyBinding, index: Int) {
        var replacements = preferences.hotkeys
        guard replacements.indices.contains(index) else { return }
        replacements[index] = binding
        do { try hotkeys.register(replacements); preferences.hotkeys = replacements; notice = "단축키를 변경했습니다." }
        catch { self.error = error.localizedDescription }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.launchAtLogin = enabled
        } catch { self.error = error.localizedDescription }
    }
    private func configuration(provider: AIProvider? = nil) throws -> ProviderConfiguration {
        let provider = provider ?? preferences.provider
        guard let key = try KeychainSecrets.read(for: provider), !key.isEmpty else { throw AppError.message("설정에서 \(provider.displayName) API 키를 저장해 주세요.") }
        let defaults = ProviderDefaults.forProvider(provider)
        return .init(provider: provider, apiKey: key, transcriptionModel: preferences.transcriptionModels[provider.rawValue] ?? defaults.transcriptionModel, textModel: preferences.textModels[provider.rawValue] ?? defaults.textModel)
    }
    func toggle(_ mode: InputMode) async {
        if isRecording { stop(); return }
        guard phase == .idle else { notice = "현재 녹음을 처리한 뒤 다시 시작해 주세요."; return }
        let job = UUID(); generation = job
        do {
            guard store != nil else { throw AppError.message("암호화 저장소를 열 수 없습니다. 기존 데이터를 보존한 상태로 앱을 다시 실행해 주세요.") }
            let config = try configuration()
            if preferences.needsLocal, localState != .ready { page = .voice; showManager?(); throw AppError.message("먼저 로컬 음성 모델을 준비해 주세요.") }
            if preferences.speakerFilterEnabled, (!hasSpeakerProfile || speakerState != .ready) {
                page = .voice; showManager?(); throw AppError.message("내 목소리 필터를 사용하려면 화자 모델을 준비하고 목소리를 등록해 주세요.")
            }
            target = TextInsertion.capture(allowedContextApps: preferences.allowedContextApps)
            if mode == .rewrite, target?.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw AppError.message("수정할 문장을 선택한 뒤 단축키로 시작해 주세요. 손쉬운 사용 권한도 필요합니다.")
            }
            snapshot = .init(configuration: config, needsLocal: preferences.needsLocal, speakerFilter: preferences.speakerFilterEnabled, targetLanguage: preferences.targetLanguage, dictionary: dictionary)
            self.mode = mode; error = nil; notice = nil; result = ""; learningTask?.cancel()
            phase = .starting; onPhaseChange?()
            try await recorder.start(); microphoneAllowed = true
            guard generation == job, !Task.isCancelled else { return }
            phase = .recording; startTimer(); onPhaseChange?()
        } catch {
            guard generation == job else { return }
            self.error = error.localizedDescription; phase = .idle; onPhaseChange?(); showManager?()
        }
    }
    private func startTimer() {
        startedAt = ProcessInfo.processInfo.systemUptime; elapsed = 0
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording else { return }
                self.elapsed = self.recorder.elapsed
                self.level = self.recorder.level()
                let limit = self.phase == .enrolling ? 30.0 : RecordingPolicy.maximumDuration
                if self.elapsed >= limit { self.stop(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    func stop() {
        guard isRecording else { return }
        let enrollment = phase == .enrolling
        ticker?.cancel()
        guard let url = recorder.stop() else { phase = .idle; onPhaseChange?(); return }
        if enrollment {
            let job = generation
            phase = .processing; onPhaseChange?()
            processingTask = Task {
                do {
                    guard let speaker else { throw AppError.message("화자 저장소를 사용할 수 없습니다.") }
                    _ = try await speaker.enroll(consumingRecordingAt: url)
                    guard generation == job, !Task.isCancelled else { return }
                    hasSpeakerProfile = true; notice = "목소리를 등록했습니다. 원본 녹음은 삭제했습니다."
                } catch { if generation == job { self.error = error.localizedDescription } }
                guard generation == job else { return }
                phase = .idle; onPhaseChange?()
            }
            return
        }
        if elapsed < 0.25 || recorder.peakDB < -65 {
            recorder.discard(); phase = .idle; notice = "음성이 감지되지 않아 입력하지 않았습니다."; onPhaseChange?(); return
        }
        phase = .processing; onPhaseChange?()
        let job = generation
        guard let snapshot else { cancel(); return }
        let target = self.target, capturedMode = mode
        processingTask = Task { await process(url: url, mode: capturedMode, target: target, job: job, failure: nil, snapshot: snapshot) }
    }
    func cancel() {
        generation = UUID(); ticker?.cancel(); processingTask?.cancel(); learningTask?.cancel()
        recorder.discard(); phase = .idle; level = 0; onPhaseChange?(); notice = "취소했습니다. 녹음은 삭제했습니다."
    }
    private func process(url: URL, mode: InputMode, target: InputTarget?, job: UUID, failure: FailedRecording?, snapshot: ProcessingSnapshot, selectedTextOverride: String? = nil) async {
        var filteredURL: URL?
        defer { if let filteredURL { try? FileManager.default.removeItem(at: filteredURL) }; try? FileManager.default.removeItem(at: url) }
        do {
            let config = snapshot.configuration
            var audioURL = url
            if snapshot.speakerFilter {
                guard let speaker, speakerState == .ready, hasSpeakerProfile else {
                    throw AppError.message("화자 모델을 준비하고 목소리를 등록한 뒤 다시 처리해 주세요.")
                }
                let filtered = try await speaker.filter(audioURL: url)
                guard !filtered.samples.isEmpty else { throw AppError.message("등록된 목소리를 확인하지 못했습니다. 녹음을 보관해 다시 처리할 수 있게 했습니다.") }
                let processed = try TemporaryAudioFiles.makeURL(); filteredURL = processed
                try Self.writeSamples(filtered.samples, to: processed); audioURL = processed
                if !filtered.warning.isEmpty { notice = filtered.warning }
            }
            let transcript: String
            if snapshot.needsLocal { transcript = try await local.transcribe(audioURL: audioURL, dictionary: snapshot.dictionary) }
            else { transcript = try await client.transcribe(audioURL: audioURL, configuration: config, dictionary: snapshot.dictionary) }
            try Task.checkCancellation()
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("인식된 말이 없습니다. 녹음을 다시 처리할 수 있습니다.") }
            let request = ProcessingRequest(mode: mode, transcript: transcript, selectedText: selectedTextOverride ?? target?.selectedText,
                context: target?.context, dictionary: snapshot.dictionary, targetLanguage: snapshot.targetLanguage)
            let output = try await client.process(request, configuration: config)
            try Task.checkCancellation(); guard job == generation else { return }
            result = output
            let inserted = if let target { await TextInsertion.insert(output, at: target, isCancelled: { self.generation != job || Task.isCancelled }) } else { false }
            guard generation == job, !Task.isCancelled else { return }
            if inserted, mode == .dictation, let target { watchCorrection(output, target: target) }
            if preferences.historyEnabled {
                var updated = history
                updated.insert(.init(mode: mode, originalText: transcript, resultText: output, sourceBundleID: target?.bundleID, provider: config.provider), at: 0)
                do {
                    guard let store else { throw AppError.message("암호화 저장소를 사용할 수 없습니다.") }
                    try await store.saveHistory(updated); history = updated
                } catch { self.error = "입력은 처리했지만 기록 저장에 실패했습니다: \(error.localizedDescription)" }
            }
            if let failure { try await store?.deleteFailure(id: failure.id) }
            if !inserted { notice = "결과가 준비되었습니다. 복사해 원하는 입력창에 붙여넣으세요."; showManager?() }
            await refreshData()
        } catch {
            guard !Task.isCancelled, job == generation else { return }
            self.error = error.localizedDescription
            if failure == nil, let store {
                do {
                    let item = FailedRecording(mode: mode, provider: snapshot.configuration.provider, targetLanguage: snapshot.targetLanguage, transcriptionModel: snapshot.configuration.transcriptionModel, textModel: snapshot.configuration.textModel, usedLocalTranscription: snapshot.needsLocal, usedSpeakerFilter: snapshot.speakerFilter)
                    try await store.saveFailure(item, audio: Data(contentsOf: url)); await refreshData()
                } catch { self.error = "처리와 복구 녹음 저장에 실패했습니다: \(error.localizedDescription)" }
            }
            showManager?()
        }
        guard job == generation else { return }
        phase = .idle; level = 0; onPhaseChange?()
    }
    private static func writeSamples(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey:kAudioFormatLinearPCM, AVSampleRateKey:16000, AVNumberOfChannelsKey:1, AVLinearPCMBitDepthKey:16, AVLinearPCMIsFloatKey:false], commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { pointer in buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: url.path)
    }
    func refreshData() async {
        guard let store else { return }
        do {
            history = try await store.history(retentionDays: preferences.retentionDays)
            dictionary = try await store.dictionary(); failures = try await store.failures()
            learningCandidate = try await store.learningCandidates().first
        } catch { self.error = "기존 데이터를 보존했습니다. \(error.localizedDescription)" }
    }
    @discardableResult func saveDictionaryEntry(spoken: String, written: String) async -> Bool {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines), written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, !written.isEmpty, spoken.count <= 100, written.count <= 100 else { return false }
        return await importDictionary([.init(spoken: spoken, written: written)])
    }
    func deleteDictionaryEntry(_ entry: DictionaryEntry) async {
        guard let store else { return }
        let updated = dictionary.filter { $0.id != entry.id }
        do { try await store.saveDictionary(updated); dictionary = updated } catch { self.error = error.localizedDescription }
    }
    @discardableResult func importDictionary(_ entries: [DictionaryEntry]) async -> Bool {
        guard let store else { error = "암호화 저장소를 사용할 수 없습니다."; return false }
        var merged = dictionary
        for entry in entries.prefix(10_000) {
            let from = entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines), to = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty, !to.isEmpty, from.count <= 100, to.count <= 100 else { continue }
            merged.removeAll { $0.spoken.caseInsensitiveCompare(from) == .orderedSame }
            merged.append(.init(spoken: from, written: to, learned: entry.learned))
        }
        do { try await store.saveDictionary(merged); dictionary = merged; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func updateDictionaryEntry(_ entry: DictionaryEntry, spoken: String, written: String) async -> Bool {
        guard let store else { return false }
        let from = spoken.trimmingCharacters(in: .whitespacesAndNewlines), to = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.count <= 100, to.count <= 100 else { return false }
        var updated = dictionary.filter { $0.id != entry.id && $0.spoken.caseInsensitiveCompare(from) != .orderedSame }
        updated.append(.init(id: entry.id, spoken: from, written: to, createdAt: entry.createdAt, learned: entry.learned))
        do { try await store.saveDictionary(updated); dictionary = updated; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func deleteHistory(_ entry: HistoryEntry? = nil) async {
        guard let store else { return }
        let updated = entry.map { item in history.filter { $0.id != item.id } } ?? []
        do {
            if entry == nil { try await store.deleteAllHistory(); learningCandidate = nil }
            else { try await store.saveHistory(updated) }
            history = updated
        } catch { self.error = error.localizedDescription }
    }
    func dismissLearningCandidate() async {
        guard let store else { return }
        do { try await store.saveLearningCandidates([]); learningCandidate = nil }
        catch { self.error = error.localizedDescription }
    }
    func deleteFailure(_ item: FailedRecording) async {
        do { try await store?.deleteFailure(id: item.id); await refreshData() } catch { self.error = error.localizedDescription }
    }
    func retry(_ item: FailedRecording) {
        guard !isBusy, let store else { return }
        let selectedRetryText = retrySelection
        generation = UUID(); let job = generation; phase = .processing; onPhaseChange?()
        processingTask = Task {
            do {
                let selection = selectedRetryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard item.mode != .rewrite || !selection.isEmpty else { throw AppError.message("원래 선택 문장은 저장하지 않습니다. 수정할 원문을 붙여넣은 뒤 다시 처리해 주세요.") }
                var config = try configuration(provider: item.provider)
                config.transcriptionModel = item.transcriptionModel ?? config.transcriptionModel
                config.textModel = item.textModel ?? config.textModel
                let snapshot = ProcessingSnapshot(configuration: config, needsLocal: item.usedLocalTranscription ?? (item.provider == .anthropic), speakerFilter: item.usedSpeakerFilter ?? false, targetLanguage: item.targetLanguage, dictionary: dictionary)
                guard !snapshot.needsLocal || localState == .ready else { throw AppError.message("먼저 로컬 음성 모델을 준비해 주세요.") }
                let data = try await store.failureAudio(id: item.id)
                let url = try TemporaryAudioFiles.makeURL()
                defer { try? FileManager.default.removeItem(at: url) }
                // This disposable file is already reserved with mode 0600. Atomic writes
                // create extra sibling files that could survive a crash outside our cleanup contract.
                try data.write(to: url)
                try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: url.path)
                guard generation == job, !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
                await process(url: url, mode: item.mode, target: nil, job: job, failure: item, snapshot: snapshot, selectedTextOverride: item.mode == .rewrite ? selection : nil)
                if generation == job { retrySelection = "" }
            } catch { if generation == job { self.error = error.localizedDescription; phase = .idle; onPhaseChange?() } }
        }
    }
    func prepareLocal() {
        Task {
            do { try await local.prepare { [weak self] state in Task { @MainActor in self?.localState = state } } }
            catch { self.error = error.localizedDescription }
        }
    }
    func prepareSpeaker() {
        Task {
            do { try await speaker?.prepare { [weak self] state in Task { @MainActor in self?.speakerState = state } } }
            catch { self.error = error.localizedDescription }
        }
    }
    func enrollVoice() async {
        guard !isBusy else { return }
        guard speakerState == .ready else { error = "먼저 화자 모델을 준비해 주세요."; return }
        let job = UUID(); generation = job; phase = .starting; onPhaseChange?()
        do {
            try await recorder.start(maximumDuration: 30)
            guard generation == job, !Task.isCancelled else { return }
            phase = .enrolling; startTimer(); onPhaseChange?()
        } catch { if generation == job { self.error = error.localizedDescription; phase = .idle; onPhaseChange?() } }
    }
    func deleteVoice() async {
        do { try await speaker?.deleteProfile(); hasSpeakerProfile = false; preferences.speakerFilterEnabled = false }
        catch { self.error = error.localizedDescription }
    }
    private func watchCorrection(_ output: String, target: InputTarget) {
        learningTask?.cancel()
        learningTask = Task { [weak self] in
            var pending = output
            var stableSamples = 0
            var committed: String?
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, !TextInsertion.observationShouldStop(original: output, target: target) else { return }
                guard let edited = TextInsertion.editedInsertion(original: output, target: target), !edited.isEmpty else { stableSamples = 0; continue }
                if edited != pending { pending = edited; stableSamples = 0; continue }
                stableSamples += 1
                guard stableSamples >= 3, edited != committed else { continue }
                committed = edited
                if let entry = CorrectionLearner.suggestion(original: output, edited: edited) {
                    if await self.importDictionary([entry]) { self.notice = "개인 사전에 ‘\(entry.written)’ 표기를 학습했습니다." }
                } else if let candidate = CorrectionLearner.reviewCandidate(original: output, edited: edited), self.preferences.historyEnabled {
                    do {
                        guard let store = self.store else { throw AppError.message("암호화 저장소를 사용할 수 없습니다.") }
                        try await store.saveLearningCandidates([candidate]); self.learningCandidate = candidate
                    }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
    enum AppError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
