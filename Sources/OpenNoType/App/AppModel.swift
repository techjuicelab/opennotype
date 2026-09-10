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
        var writingProfile: WritingProfile
    }
    var preferences = Preferences() {
        didSet {
            if persistPreferences { preferences.save() }
            if !preferences.automaticLearningEnabled { learningTask?.cancel() }
            if oldValue.usageTrackingEnabled != preferences.usageTrackingEnabled { usageResetGeneration = UUID() }
        }
    }
    var page: AppPage = .home
    var settingsSection: SettingsSection = .connection
    var usageRecords: [UsageRecord] = []
    var usageTrackingStartedAt: Date?
    var usageDiscardedCount = 0
    var usageStorageError: String?
    @ObservationIgnored private var usageResetGeneration = UUID()
    var phase: Phase = .idle
    var mode: InputMode = .dictation
    var elapsed: TimeInterval = 0
    var level: Double = 0
    var notice: String?
    var error: String?
    var result: String = ""
    var inputTestArmed = false
    var inputDiagnostics = ""
    var lastProcessingTimings: String?
    var hotkeyConflicts: [String] = []
    /// Short outcome summary shown on the floating bar for a few seconds after work ends.
    var transientMessage: String?
    var history: [HistoryEntry] = []
    var dictionary: [DictionaryEntry] = []
    var failures: [FailedRecording] = []
    var apiKeyDraft = ""
    var retrySelection = ""
    var keySaved = false
    var savedKeyDraft = ""
    var keyDraftIsChanged: Bool { apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != savedKeyDraft }
    var launchAtLoginEnabled = false
    var loginItemStatusText: String?
    var microphonePermissionNeedsSettings = false
    var processingStage: ProcessingTimings.Stage = .audioPreparation
    var canUndoLastLearning = false
    var localState: LocalModelState = .notPrepared
    var speakerState: LocalModelState = .notPrepared
    var hasSpeakerProfile = false
    var learningCandidate: LearningCandidate?
    var accessibilityAllowed = false
    var microphoneAllowed = false
    @ObservationIgnored private var store: SecureStore?
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let client: ProviderClient
    @ObservationIgnored private let runtime: AppRuntime
    @ObservationIgnored private var persistPreferences = true
    @ObservationIgnored private var dataRefreshGeneration = UUID()
    @ObservationIgnored private var learningChangeGeneration = UUID()
    @ObservationIgnored private var lastLearnedChange: (applied: DictionaryEntry, previous: DictionaryEntry?)?
    @ObservationIgnored private var localPreparation: Task<Bool, Never>?
    @ObservationIgnored private var speakerPreparation: Task<Bool, Never>?
    @ObservationIgnored private var localPreparationID = UUID()
    @ObservationIgnored private var speakerPreparationID = UUID()
    @ObservationIgnored private let local = LocalTranscriber()
    @ObservationIgnored private var speaker: LocalSpeakerRecognizer?
    @ObservationIgnored private lazy var hotkeys = HotkeyManager()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var learningTask: Task<Void, Never>?
    @ObservationIgnored private var housekeepingTask: Task<Void, Never>?
    @ObservationIgnored private var inputTestTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var target: InputTarget?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cancelledInsertion: (job: UUID, replacementGeneration: UUID)?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var foreignActivation: String?
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
        case .processing: processingStage.title + " 중이에요"
        }
    }

    init(store injectedStore: SecureStore? = nil, runtime: AppRuntime? = nil,
         client: ProviderClient = ProviderClient(), startServices: Bool = true,
         preferences initialPreferences: Preferences? = nil) {
        self.runtime = runtime ?? AppRuntime(); self.client = client; persistPreferences = startServices
        preferences = initialPreferences ?? (startServices ? Preferences.load() : Preferences())
        if preferences.usageAccountingIncomplete { usageStorageError = "일부 사용량이 기록되지 않았습니다. 표시된 합계가 실제 사용보다 적을 수 있습니다." }
        if !startServices {
            store = injectedStore
            if let injectedStore { speaker = LocalSpeakerRecognizer(profileStore: SpeakerStoreAdapter(store: injectedStore)) }
            loadKey(); refreshPermissions()
            return
        }
        do { try TemporaryAudioFiles.cleanupDeadSessions() }
        catch { self.error = "이전 임시 녹음을 정리하지 못했습니다. \(error.localizedDescription)" }
        do {
            let store = try SecureStore(); self.store = store
            speaker = LocalSpeakerRecognizer(profileStore: SpeakerStoreAdapter(store: store))
        } catch { self.error = "저장소를 열지 못했습니다. 기존 데이터는 보존됩니다. \(error.localizedDescription)" }
        hotkeys.onPress = { [weak self] mode in Task { await self?.toggle(mode) } }
        recorder.onAutomaticFinish = { [weak self] in self?.stop() }
        recorder.onFailure = { [weak self] in self?.recordingFailed() }
        do { try hotkeys.register(preferences.hotkeys) } catch { self.error = error.localizedDescription }
        refreshHotkeyConflicts()
        if !hotkeyConflicts.isEmpty { notice = hotkeyConflicts.joined(separator: "\n") }
        loadKey()
        refreshPermissions()
        Task {
            await refreshData()
            if preferences.needsLocal { _ = await prepareLocalModel(download: false) }
            if preferences.speakerFilterEnabled { _ = await prepareSpeakerModel(download: false) }
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
                self?.cancelLocalPreparation(); self?.cancelSpeakerPreparation()
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
        accessibilityAllowed = runtime.accessibilityPermitted()
        let permission = runtime.microphonePermission()
        microphoneAllowed = permission == .authorized
        microphonePermissionNeedsSettings = permission == .denied || permission == .restricted
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        loginItemStatusText = status == .requiresApproval ? "시스템 설정에서 로그인 항목 승인이 필요합니다." : nil
    }
    func requestMicrophone() async {
        switch runtime.microphonePermission() {
        case .authorized: microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await runtime.requestMicrophone()
            microphonePermissionNeedsSettings = !microphoneAllowed
            if !microphoneAllowed { notice = "마이크 사용을 허용하려면 시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 OpenNoType을 켜 주세요." }
        case .denied, .restricted:
            microphonePermissionNeedsSettings = true
            notice = "시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 OpenNoType을 허용한 뒤 돌아와 주세요."
            openMicrophoneSettings()
        @unknown default: microphonePermissionNeedsSettings = true
        }
    }
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
    }
    func openLoginItemSettings() { SMAppService.openSystemSettingsLoginItems() }
    private func startRecording(maximumDuration: TimeInterval = RecordingPolicy.maximumDuration) async throws {
        if let start = runtime.startRecording { try await start(maximumDuration) }
        else { try await recorder.start(maximumDuration: maximumDuration) }
    }
    private func stopRecording() -> URL? {
        if let stop = runtime.stopRecording { return stop() }
        return recorder.stop()
    }
    func loadKey() {
        do { apiKeyDraft = try runtime.readKey(preferences.provider) ?? ""; savedKeyDraft = apiKeyDraft; keySaved = !apiKeyDraft.isEmpty }
        catch { self.error = error.localizedDescription; apiKeyDraft = ""; keySaved = false }
    }
    func saveKey() {
        do {
            let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { try KeychainSecrets.delete(for: preferences.provider) }
            else { try KeychainSecrets.save(key, for: preferences.provider) }
            apiKeyDraft = key; savedKeyDraft = key
            keySaved = !key.isEmpty; notice = keySaved ? "API 키를 이 Mac의 Keychain에 저장했습니다." : "API 키를 삭제했습니다."
        } catch { self.error = error.localizedDescription }
    }
    func updateHotkey(_ binding: HotkeyBinding, index: Int) {
        var replacements = preferences.hotkeys
        guard replacements.indices.contains(index) else { return }
        replacements[index] = binding
        do { try hotkeys.register(replacements); preferences.hotkeys = replacements; notice = "단축키를 변경했습니다."; refreshHotkeyConflicts() }
        catch { self.error = error.localizedDescription }
    }
    /// Carbon shortcuts are shared: every app registered for the same combination is notified.
    func refreshHotkeyConflicts() { hotkeyConflicts = HotkeyConflicts.warnings(for: preferences.hotkeys) }
    /// Shows a short message on the floating bar without activating any window.
    func flash(_ message: String, seconds: TimeInterval = 4) {
        transientTask?.cancel()
        transientMessage = message; onPhaseChange?()
        transientTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            transientMessage = nil; onPhaseChange?()
        }
    }
    /// Another app reacting to the same shortcut shows up as a frontmost change right after the press.
    private func noteForeignActivation(since previous: NSRunningApplication?) {
        foreignActivation = nil
        guard let front = runtime.frontmostApplication(), front.processIdentifier != previous?.processIdentifier,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = front.localizedName ?? "다른 앱"
        foreignActivation = name
        notice = "단축키를 누르자 \(name)이(가) 앞으로 나왔습니다. 같은 단축키를 쓰는 앱이 있으면 자동입력이 실패할 수 있으니 한쪽 단축키를 바꿔 주세요. 이번에는 원래 앱을 다시 앞으로 가져와 입력합니다."
        flash("\(name)이(가) 같은 단축키에 반응했습니다. 원래 앱으로 돌아가 입력합니다.", seconds: 3)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.launchAtLogin = enabled
            refreshPermissions()
        } catch { self.error = error.localizedDescription; refreshPermissions() }
    }
    private func configuration(provider: AIProvider? = nil) throws -> ProviderConfiguration {
        let provider = provider ?? preferences.provider
        guard let key = try runtime.readKey(provider), !key.isEmpty else { throw AppError.message("설정에서 \(provider.displayName) API 키를 저장해 주세요.") }
        let defaults = ProviderDefaults.forProvider(provider)
        func nonBlank(_ value: String?, fallback: String) -> String {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
            return value
        }
        return .init(provider: provider, apiKey: key,
            transcriptionModel: nonBlank(preferences.transcriptionModels[provider.rawValue], fallback: defaults.transcriptionModel),
            textModel: nonBlank(preferences.textModels[provider.rawValue], fallback: defaults.textModel))
    }
    func toggle(_ mode: InputMode) async {
        if inputTestArmed {
            if mode == .dictation, phase == .idle { await runInputTest(); return }
            if mode != .dictation { cancelInputTest() }
        }
        if isRecording { stop(); return }
        guard phase == .idle else { notice = "현재 녹음을 처리한 뒤 다시 시작해 주세요."; return }
        let frontBefore = runtime.frontmostApplication()
        if frontBefore?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Recording here could only end in a result to copy by hand; say so instead of recording.
            // The window is already in front (or there is none), so showing it steals nothing.
            notice = "OpenNoType 창에는 입력할 수 없습니다. 글을 입력할 앱의 입력창을 클릭한 뒤 단축키를 다시 눌러 주세요."
            showManager?()
            return
        }
        let job = UUID(); generation = job
        phase = .starting; self.mode = mode; target = nil; snapshot = nil
        learningTask?.cancel(); onPhaseChange?()
        defer {
            if generation == job, phase == .starting {
                recorder.discard(); target = nil; snapshot = nil; phase = .idle; onPhaseChange?()
            }
        }
        do {
            guard store != nil else { throw AppError.message("암호화 저장소를 열 수 없습니다. 기존 데이터를 보존한 상태로 앱을 다시 실행해 주세요.") }
            let startPreferences = preferences, startDictionary = dictionary
            let config = try configuration()
            guard runtime.accessibilityPermitted() else {
                TextInsertion.requestPermission(); refreshPermissions(); page = .home
                throw AppError.message("다른 앱에 글을 입력하려면 손쉬운 사용 권한이 필요합니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 OpenNoType을 허용한 뒤 다시 시도해 주세요.")
            }
            guard !runtime.secureInputActive() else {
                throw AppError.message("비밀번호 입력란 등 보안 입력이 켜진 상태에서는 녹음을 시작하지 않습니다. 터미널 앱의 Secure Keyboard Entry 옵션도 같은 상태를 만듭니다. 옵션을 끄거나 다른 입력창을 클릭한 뒤 다시 시도해 주세요.")
            }
            let capturedTarget = await runtime.capture(startPreferences.allowedContextApps)
            guard generation == job, !Task.isCancelled else { return }
            guard let capturedTarget else { throw AppError.message("입력할 앱이 바뀌었습니다. 원하는 입력창에서 단축키를 다시 눌러 주세요.") }
            target = capturedTarget
            if target?.secureField == true {
                throw AppError.message("비밀번호 입력란에는 글을 입력하지 않습니다. 다른 입력창을 클릭한 뒤 다시 시도해 주세요.")
            }
            if mode == .rewrite, target?.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw AppError.message("수정할 문장을 선택한 뒤 단축키로 시작해 주세요. 손쉬운 사용 권한도 필요합니다.")
            }
            snapshot = .init(configuration: config, needsLocal: startPreferences.needsLocal, speakerFilter: startPreferences.speakerFilterEnabled, targetLanguage: startPreferences.targetLanguage, dictionary: startDictionary, writingProfile: startPreferences.writingProfile(for: target?.bundleID))
            if startPreferences.needsLocal, localState != .ready {
                _ = await prepareLocalModel(download: false)
                guard generation == job, !Task.isCancelled else { return }
                guard localState == .ready else { page = .voice; throw AppError.message("먼저 로컬 음성 모델을 다운로드해 주세요.") }
            }
            if startPreferences.speakerFilterEnabled, speakerState != .ready {
                _ = await prepareSpeakerModel(download: false)
                guard generation == job, !Task.isCancelled else { return }
            }
            if startPreferences.speakerFilterEnabled, (!hasSpeakerProfile || speakerState != .ready) {
                page = .voice; throw AppError.message("내 목소리 필터를 사용하려면 화자 모델을 준비하고 목소리를 등록해 주세요.")
            }
            self.mode = mode; error = nil; notice = nil; result = ""; learningTask?.cancel()
            lastProcessingTimings = nil
            phase = .starting; onPhaseChange?()
            try await startRecording(); microphoneAllowed = true
            guard generation == job, !Task.isCancelled else { return }
            noteForeignActivation(since: frontBefore)
            phase = .recording; startTimer(); onPhaseChange?()
        } catch {
            guard generation == job else { return }
            self.error = error.localizedDescription; phase = .idle; onPhaseChange?(); showManager?()
        }
    }
    func armInputTest() {
        guard !isBusy else { return }
        cancelledInsertion = nil
        inputTestTask?.cancel(); inputTestTask = nil
        inputTestArmed = true
        notice = "입력창을 클릭한 뒤 받아쓰기 단축키를 누르세요. 음성·API 없이 테스트 문구만 입력합니다."
    }
    func cancelInputTest() {
        inputTestArmed = false
        inputTestTask?.cancel(); inputTestTask = nil
        notice = "입력 테스트 준비를 취소했습니다."
    }
    func scheduleInputTest() {
        guard !isBusy else { return }
        cancelledInsertion = nil
        inputTestArmed = true
        notice = "5초 안에 시험할 입력창을 클릭하세요. 녹음 없이 테스트 문구를 입력합니다."
        inputTestTask?.cancel()
        inputTestTask = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, inputTestArmed else { return }
            inputTestTask = nil
            guard !isBusy else { inputTestArmed = false; return }
            await runInputTest()
        }
    }
    private func runInputTest() async {
        guard !isBusy else { return }
        inputTestTask?.cancel(); inputTestTask = nil
        inputTestArmed = false; learningTask?.cancel()
        error = nil; notice = nil
        guard runtime.accessibilityPermitted() else {
            TextInsertion.requestPermission(); refreshPermissions()
            inputDiagnostics = "capture: " + TextInsertion.diagnosticSummary(target: nil)
            error = "손쉬운 사용 권한이 없어 입력 테스트를 실행하지 않았습니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 OpenNoType을 허용해 주세요."
            page = .settings; showManager?()
            return
        }
        let job = UUID(); generation = job
        phase = .starting; onPhaseChange?()
        defer { if generation == job, phase != .idle { phase = .idle; onPhaseChange?() } }
        let target = await runtime.capture([])
        guard generation == job, !Task.isCancelled else { return }
        inputDiagnostics = "capture: " + TextInsertion.diagnosticSummary(target: target)
        processingStage = .insertion
        phase = .processing; onPhaseChange?()
        try? await Task.sleep(for: .milliseconds(300))
        guard generation == job, !Task.isCancelled else { return }
        inputDiagnostics += "\nbefore: " + TextInsertion.diagnosticSummary(target: target)
        let text = "OpenNoType 입력 테스트입니다."
        let outcome = if let target {
            await TextInsertion.insertOutcome(text, at: target,
                isCancelled: { self.generation != job || Task.isCancelled },
                trace: { line in
                    guard self.generation == job, !Task.isCancelled else { return }
                    self.inputDiagnostics += "\n" + line
                })
        } else { InsertionOutcome.notSubmitted(.noTarget) }
        guard generation == job, !Task.isCancelled else {
            reportCancelledInsertion(outcome, job: job)
            return
        }
        inputDiagnostics += "\noutcome=\(outcome.diagnosticCode)\nafter: " + TextInsertion.diagnosticSummary(target: target)
        phase = .idle; onPhaseChange?()
        let feedback = InsertionFeedback(outcome: outcome)
        if feedback.isError { error = feedback.testMessage } else { notice = feedback.testMessage }
        flash(feedback.overlayMessage)
        if feedback.showResultPage { page = .settings; showManager?() }
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
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        let enrollment = phase == .enrolling
        ticker?.cancel()
        guard let url = stopRecording() else { phase = .idle; onPhaseChange?(); return }
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
        if elapsed < 0.25 || (runtime.recordingPeakDB?() ?? recorder.peakDB) < -65 {
            recorder.discard(); phase = .idle; notice = "음성이 감지되지 않아 입력하지 않았습니다."; onPhaseChange?(); return
        }
        phase = .processing; onPhaseChange?()
        let job = generation
        guard let snapshot else { cancel(); return }
        let target = self.target, capturedMode = mode
        processingTask = Task { await process(url: url, mode: capturedMode, target: target, job: job, failure: nil, snapshot: snapshot, stoppedAt: stoppedAt) }
    }
    private func recordingFailed() {
        guard isRecording else { return }
        let enrollment = phase == .enrolling, job = generation
        ticker?.cancel()
        guard let url = stopRecording() else { phase = .idle; error = "녹음이 중단되었습니다."; onPhaseChange?(); return }
        if enrollment {
            recorder.discard(); phase = .idle
            error = "목소리 등록 녹음이 중단되었습니다. 마이크 연결을 확인한 뒤 다시 등록해 주세요."
            onPhaseChange?(); return
        }
        let capturedSnapshot = snapshot, capturedMode = mode
        processingStage = .storage; phase = .processing; onPhaseChange?()
        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                if generation == job { phase = .idle; onPhaseChange?() }
            }
            guard let store, let capturedSnapshot else { error = "녹음이 중단되어 원음을 복구하지 못했습니다."; return }
            do {
                let config = capturedSnapshot.configuration
                let item = FailedRecording(mode: capturedMode, provider: config.provider,
                    targetLanguage: capturedSnapshot.targetLanguage, transcriptionModel: config.transcriptionModel,
                    textModel: config.textModel, usedLocalTranscription: capturedSnapshot.needsLocal,
                    usedSpeakerFilter: capturedSnapshot.speakerFilter, writingProfile: capturedSnapshot.writingProfile)
                try Task.checkCancellation()
                try await store.saveFailure(item, audio: Data(contentsOf: url))
                guard generation == job, !Task.isCancelled else { return }
                await refreshData()
                guard generation == job, !Task.isCancelled else { return }
                error = "마이크 녹음이 중단되었습니다. 남은 원음을 암호화해 보관했으니 다시 처리에서 확인해 주세요."
            } catch {
                guard generation == job, !Task.isCancelled else { return }
                self.error = "녹음이 중단되었고 복구 원음 저장에도 실패했습니다: \(error.localizedDescription)"
            }
            showManager?()
        }
    }
    func cancel() {
        inputTestArmed = false; inputTestTask?.cancel()
        // Repeated cancellation still belongs to the same interrupted job until new work starts.
        let interruptedJob = cancelledInsertion?.replacementGeneration == generation ? cancelledInsertion!.job : generation
        let replacementGeneration = UUID()
        cancelledInsertion = (interruptedJob, replacementGeneration)
        generation = replacementGeneration; ticker?.cancel(); processingTask?.cancel(); learningTask?.cancel()
        recorder.discard(); target = nil; snapshot = nil
        phase = .idle; level = 0; onPhaseChange?(); notice = "취소했습니다. 녹음은 삭제했습니다."
    }
    private func reportCancelledInsertion(_ outcome: InsertionOutcome, job: UUID) {
        guard case .submittedUnverified = outcome,
              let cancellation = cancelledInsertion, cancellation.job == job,
              cancellation.replacementGeneration == generation else { return }
        // The cancelled job may report uncertainty, but must never reopen a window or replace results.
        notice = nil
        error = InsertionFeedback(outcome: outcome).message
    }
    private func process(url: URL, mode: InputMode, target: InputTarget?, job: UUID, failure: FailedRecording?, snapshot: ProcessingSnapshot, selectedTextOverride: String? = nil, stoppedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) async {
        var filteredURL: URL?
        var timings = ProcessingTimings(job: job, startedAt: stoppedAt)
        let usageEpoch = usageResetGeneration
        let tracksUsage = preferences.usageTrackingEnabled
        let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
            guard tracksUsage else { return }
            await self?.recordUsage(event, job: job, mode: mode, isRecovery: failure != nil, epoch: usageEpoch)
        }
        defer { if let filteredURL { try? FileManager.default.removeItem(at: filteredURL) }; try? FileManager.default.removeItem(at: url) }
        do {
            processingStage = .audioPreparation
            let config = snapshot.configuration
            var audioURL = url
            var localSamples: [Float]?
            if snapshot.speakerFilter {
                guard let speaker, speakerState == .ready, hasSpeakerProfile else {
                    throw AppError.message("화자 모델을 준비하고 목소리를 등록한 뒤 다시 처리해 주세요.")
                }
                let filtered = try await speaker.filter(audioURL: url)
                try Task.checkCancellation()
                guard job == generation else { return }
                guard !filtered.samples.isEmpty else { throw AppError.message("등록된 목소리를 확인하지 못했습니다. 녹음을 보관해 다시 처리할 수 있게 했습니다.") }
                if snapshot.needsLocal {
                    // The local engine accepts the filter's PCM directly; avoid a WAV write/read round trip.
                    localSamples = filtered.samples
                } else {
                    let processed = try runtime.makeTemporaryAudioURL(); filteredURL = processed
                    try Self.writeSamples(filtered.samples, to: processed); audioURL = processed
                }
                if !filtered.warning.isEmpty { notice = filtered.warning }
            }
            timings.mark(.audioPreparation)
            processingStage = .transcription
            let transcript: String
            if snapshot.needsLocal {
                var event = ProviderUsage(provider: nil, model: LocalSpeechModel.largeV3.variant,
                    stage: .transcription, outcome: .responseReceived,
                    audioSeconds: localSamples.map { Double($0.count) / 16_000 } ?? Self.audioDuration(at: audioURL))
                do {
                    if let localSamples {
                        transcript = try await local.transcribe(samples: localSamples, dictionary: snapshot.dictionary, writingProfile: snapshot.writingProfile)
                    } else {
                        transcript = try await local.transcribe(audioURL: audioURL, dictionary: snapshot.dictionary, writingProfile: snapshot.writingProfile)
                    }
                    await collectUsage(event)
                } catch {
                    event.outcome = (error is CancellationError || Task.isCancelled) ? .cancelled : .failed
                    await collectUsage(event)
                    throw error
                }
            } else {
                transcript = try await client.transcribe(audioURL: audioURL, configuration: config,
                    dictionary: snapshot.dictionary, writingProfile: snapshot.writingProfile,
                    audioSeconds: Self.audioDuration(at: audioURL), onUsage: collectUsage)
            }
            timings.mark(.transcription)
            try Task.checkCancellation()
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("인식된 말이 없습니다. 녹음을 다시 처리할 수 있습니다.") }
            let request = ProcessingRequest(mode: mode, transcript: transcript, selectedText: selectedTextOverride ?? target?.selectedText,
                context: target?.context, dictionary: snapshot.dictionary, targetLanguage: snapshot.targetLanguage, writingProfile: snapshot.writingProfile)
            processingStage = .textProcessing
            let output = try await client.process(request, configuration: config, onUsage: collectUsage)
            timings.mark(.textProcessing)
            try Task.checkCancellation(); guard job == generation else { return }
            result = output
            processingStage = .insertion
            let outcome = if let target {
                await TextInsertion.insertOutcome(output, at: target, requiresUnchangedTarget: mode == .rewrite,
                                                  isCancelled: { self.generation != job || Task.isCancelled })
            } else { InsertionOutcome.notSubmitted(.noTarget) }
            timings.mark(.insertion)
            guard generation == job, !Task.isCancelled else {
                reportCancelledInsertion(outcome, job: job)
                return
            }
            if outcome.isConfirmed, mode == .dictation, preferences.automaticLearningEnabled, let target { watchCorrection(output, target: target) }
            processingStage = .storage
            if preferences.historyEnabled {
                do {
                    guard let store else { throw AppError.message("암호화 저장소를 사용할 수 없습니다.") }
                    _ = try await store.appendHistory(.init(mode: mode, originalText: transcript, resultText: output, sourceBundleID: target?.bundleID, provider: config.provider))
                    guard generation == job, !Task.isCancelled else { return }
                } catch {
                    guard generation == job, !Task.isCancelled else { return }
                    self.error = "입력은 처리했지만 기록 저장에 실패했습니다: \(error.localizedDescription)"
                }
            }
            if let failure { try await store?.deleteFailure(id: failure.id) }
            guard generation == job, !Task.isCancelled else { return }
            if target == nil {
                // Retry from 다시 처리, or a start without another app in front: the result is meant to be copied.
                notice = "결과가 준비되었습니다. 복사해 원하는 입력창에 붙여넣으세요."; page = .home; showManager?()
            } else {
                let feedback = InsertionFeedback(outcome: outcome)
                switch feedback.severity {
                case .success: break
                case .info: notice = feedback.message
                case .warning:
                    notice = nil
                    let prefix = foreignActivation.map { "\($0)이(가) 단축키에 반응해 앞으로 나왔습니다. " } ?? ""
                    self.error = prefix + feedback.message
                }
                if feedback.severity != .success { flash(feedback.overlayMessage, seconds: feedback.isError ? 6 : 4) }
                // Only a delivery that never reached the target app brings the manager window forward.
                if feedback.showResultPage { page = .home; showManager?() }
            }
            await refreshData()
            guard generation == job, !Task.isCancelled else { return }
            timings.mark(.storage)
            lastProcessingTimings = timings.summary
        } catch {
            guard !Task.isCancelled, job == generation else { return }
            self.error = error.localizedDescription
            if failure == nil, let store {
                do {
                    let item = FailedRecording(mode: mode, provider: snapshot.configuration.provider, targetLanguage: snapshot.targetLanguage, transcriptionModel: snapshot.configuration.transcriptionModel, textModel: snapshot.configuration.textModel, usedLocalTranscription: snapshot.needsLocal, usedSpeakerFilter: snapshot.speakerFilter, writingProfile: snapshot.writingProfile)
                    try await store.saveFailure(item, audio: Data(contentsOf: url))
                    guard generation == job, !Task.isCancelled else { return }
                    await refreshData()
                    guard generation == job, !Task.isCancelled else { return }
                } catch {
                    guard generation == job, !Task.isCancelled else { return }
                    self.error = "처리와 복구 녹음 저장에 실패했습니다: \(error.localizedDescription)"
                }
            }
            guard generation == job, !Task.isCancelled else { return }
            showManager?()
        }
        guard job == generation, !Task.isCancelled else { return }
        phase = .idle; level = 0; onPhaseChange?()
    }
    private static func audioDuration(at url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return duration.isFinite && duration >= 0 ? duration : nil
    }

    /// Accounting is independent of result history and job cancellation. A received API response
    /// may be billable even when its content is rejected or the user has cancelled insertion.
    private func recordUsage(_ event: ProviderUsage, job: UUID, mode: InputMode, isRecovery: Bool, epoch: UUID) async {
        guard preferences.usageTrackingEnabled, usageResetGeneration == epoch else { return }
        guard let store else { preferences.usageAccountingIncomplete = true; usageStorageError = "사용량 저장소를 열 수 없습니다. 이번 요청은 통계에 포함되지 않았습니다."; return }
        let record = UsageRecord(jobID: job, mode: mode, isRecovery: isRecovery,
                                 event: event, cost: UsagePricing.cost(for: event))
        do {
            try await store.appendUsage(record)
            guard usageResetGeneration == epoch else { return }
            await refreshData()
        } catch {
            guard usageResetGeneration == epoch else { return }
            // Accounting errors must not discard a successfully transcribed or processed result.
            preferences.usageAccountingIncomplete = true
            usageStorageError = "일부 사용량을 저장하지 못했습니다. 표시된 합계가 실제 사용보다 적을 수 있습니다."
        }
    }

    func clearUsage() async {
        guard !isBusy, let store else { return }
        usageResetGeneration = UUID()
        do {
            try await store.clearUsage()
            preferences.usageAccountingIncomplete = false
            usageStorageError = nil
            await refreshData()
        } catch { usageStorageError = "사용량 기록을 초기화하지 못했습니다. 기존 기록은 보존됩니다." }
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
        let refresh = UUID(); dataRefreshGeneration = refresh
        do {
            let current = try await store.snapshot(retentionDays: preferences.retentionDays)
            guard dataRefreshGeneration == refresh else { return }
            history = current.history; dictionary = current.dictionary
            usageRecords = current.usageRecords; usageTrackingStartedAt = current.usageTrackingStartedAt
            usageDiscardedCount = current.usageDiscardedCount
            failures = current.failedRecordings; learningCandidate = current.learningCandidates.first
            hasSpeakerProfile = current.hasVoiceProfile
            if let change = lastLearnedChange { canUndoLastLearning = dictionary.contains(change.applied) }
        } catch { if dataRefreshGeneration == refresh { self.error = "기존 데이터를 보존했습니다. \(error.localizedDescription)" } }
    }
    @discardableResult func saveDictionaryEntry(spoken: String, written: String) async -> Bool {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines), written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, !written.isEmpty, spoken.count <= 100, written.count <= 100 else { return false }
        return await importDictionary([.init(spoken: spoken, written: written)])
    }
    func deleteDictionaryEntry(_ entry: DictionaryEntry) async {
        guard let store else { return }
        do { _ = try await store.deleteDictionaryEntry(id: entry.id); await refreshData() } catch { self.error = error.localizedDescription }
    }
    @discardableResult func importDictionary(_ entries: [DictionaryEntry]) async -> Bool {
        guard let store else { error = "암호화 저장소를 사용할 수 없습니다."; return false }
        do { _ = try await store.upsertDictionaryEntries(entries); await refreshData(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func updateDictionaryEntry(_ entry: DictionaryEntry, spoken: String, written: String) async -> Bool {
        guard let store else { return false }
        let from = spoken.trimmingCharacters(in: .whitespacesAndNewlines), to = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.count <= 100, to.count <= 100 else { return false }
        do { _ = try await store.updateDictionaryEntry(id: entry.id, spoken: from, written: to); await refreshData(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func deleteHistory(_ entry: HistoryEntry? = nil) async {
        guard let store else { return }
        do {
            if entry == nil { try await store.deleteAllHistory(); learningCandidate = nil }
            else if let entry { _ = try await store.deleteHistory(id: entry.id) }
            await refreshData()
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
    func retry(_ item: FailedRecording, useCurrentSettings: Bool = false) {
        guard !isBusy, let store else { return }
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        lastProcessingTimings = nil
        let selectedRetryText = retrySelection
        generation = UUID(); let job = generation; processingStage = .audioPreparation
        phase = .processing; error = nil; notice = nil; result = ""; learningTask?.cancel(); onPhaseChange?()
        processingTask = Task {
            do {
                let selection = selectedRetryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard item.mode != .rewrite || !selection.isEmpty else { throw AppError.message("원래 선택 문장은 저장하지 않습니다. 수정할 원문을 붙여넣은 뒤 다시 처리해 주세요.") }
                var config = try configuration(provider: useCurrentSettings ? preferences.provider : item.provider)
                func stored(_ value: String?) -> String? {
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                    return value
                }
                if !useCurrentSettings {
                    config.transcriptionModel = stored(item.transcriptionModel) ?? config.transcriptionModel
                    config.textModel = stored(item.textModel) ?? config.textModel
                }
                let snapshot = ProcessingSnapshot(configuration: config,
                    needsLocal: useCurrentSettings ? preferences.needsLocal : item.usedLocalTranscription ?? (item.provider == .anthropic),
                    speakerFilter: useCurrentSettings ? preferences.speakerFilterEnabled : item.usedSpeakerFilter ?? false,
                    targetLanguage: useCurrentSettings ? preferences.targetLanguage : item.targetLanguage,
                    dictionary: dictionary, writingProfile: item.writingProfile ?? .init())
                if snapshot.needsLocal, localState != .ready { _ = await prepareLocalModel(download: false) }
                if snapshot.speakerFilter, speakerState != .ready { _ = await prepareSpeakerModel(download: false) }
                guard generation == job, !Task.isCancelled else { return }
                guard !snapshot.needsLocal || localState == .ready else { throw AppError.message("먼저 로컬 음성 모델을 다운로드해 주세요.") }
                let data = try await store.failureAudio(id: item.id)
                let url = try runtime.makeTemporaryAudioURL()
                defer { try? FileManager.default.removeItem(at: url) }
                // This disposable file is already reserved with mode 0600. Atomic writes
                // create extra sibling files that could survive a crash outside our cleanup contract.
                try data.write(to: url)
                try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: url.path)
                guard generation == job, !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
                await process(url: url, mode: item.mode, target: nil, job: job, failure: item, snapshot: snapshot, selectedTextOverride: item.mode == .rewrite ? selection : nil, stoppedAt: stoppedAt)
                if generation == job { retrySelection = "" }
            } catch { if generation == job { self.error = error.localizedDescription; phase = .idle; onPhaseChange?() } }
        }
    }
    func prepareLocal() {
        Task { _ = await prepareLocalModel(download: true) }
    }
    func prepareSpeaker() {
        Task { _ = await prepareSpeakerModel(download: true) }
    }
    private func prepareLocalModel(download: Bool) async -> Bool {
        if let localPreparation { return await localPreparation.value }
        if localState == .ready { return true }
        let id = UUID(); localPreparationID = id; localState = .loading
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            let progress: @Sendable (LocalModelState) -> Void = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.localPreparationID == id else { return }
                    self.localState = state
                }
            }
            do {
                let ready: Bool
                if download { try await local.prepare(progress: progress); ready = true }
                else { ready = try await local.prepareCached(progress: progress) }
                guard localPreparationID == id, !Task.isCancelled else { return false }
                localState = ready ? .ready : .notPrepared
                return ready
            } catch {
                guard localPreparationID == id, !Task.isCancelled else { return false }
                localState = .failed("모델 준비 실패: \(error.localizedDescription)")
                if download { self.error = error.localizedDescription }
                return false
            }
        }
        localPreparation = task
        let ready = await task.value
        if localPreparationID == id { localPreparation = nil; localPreparationID = UUID() }
        return ready
    }
    private func prepareSpeakerModel(download: Bool) async -> Bool {
        if let speakerPreparation { return await speakerPreparation.value }
        if speakerState == .ready { return true }
        guard let speaker else { error = "화자 저장소를 사용할 수 없습니다."; return false }
        let id = UUID(); speakerPreparationID = id; speakerState = .loading
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            let progress: @Sendable (LocalModelState) -> Void = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.speakerPreparationID == id else { return }
                    self.speakerState = state
                }
            }
            do {
                let ready: Bool
                if download { try await speaker.prepare(progress: progress); ready = true }
                else { ready = try await speaker.prepareCached(progress: progress) }
                guard speakerPreparationID == id, !Task.isCancelled else { return false }
                speakerState = ready ? .ready : .notPrepared
                return ready
            } catch {
                guard speakerPreparationID == id, !Task.isCancelled else { return false }
                speakerState = .failed("모델 준비 실패: \(error.localizedDescription)")
                if download { self.error = error.localizedDescription }
                return false
            }
        }
        speakerPreparation = task
        let ready = await task.value
        if speakerPreparationID == id { speakerPreparation = nil; speakerPreparationID = UUID() }
        return ready
    }
    func cancelLocalPreparation() {
        localPreparationID = UUID(); localPreparation?.cancel(); localPreparation = nil; localState = .notPrepared
    }
    func cancelSpeakerPreparation() {
        speakerPreparationID = UUID(); speakerPreparation?.cancel(); speakerPreparation = nil; speakerState = .notPrepared
    }
    func enrollVoice() async {
        guard !isBusy else { return }
        guard speakerState == .ready else { error = "먼저 화자 모델을 준비해 주세요."; return }
        let job = UUID(); generation = job; phase = .starting; onPhaseChange?()
        do {
            try await startRecording(maximumDuration: 30)
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
                guard let self, !Task.isCancelled, self.preferences.automaticLearningEnabled,
                      !TextInsertion.observationShouldStop(original: output, target: target) else { return }
                guard let edited = TextInsertion.editedInsertion(original: output, target: target), !edited.isEmpty else { stableSamples = 0; continue }
                if edited != pending { pending = edited; stableSamples = 0; continue }
                stableSamples += 1
                guard stableSamples >= 3, edited != committed else { continue }
                committed = edited
                if let entry = CorrectionLearner.suggestion(original: output, edited: edited) {
                    if await self.applyLearnedEntry(entry) {
                        self.notice = "개인 사전에 ‘\(entry.written)’ 표기를 학습했습니다."
                        self.flash("‘\(entry.written)’ 표기를 개인 사전에 기억했어요.")
                    }
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
    @discardableResult func applyLearnedEntry(_ entry: DictionaryEntry) async -> Bool {
        guard preferences.automaticLearningEnabled, !Task.isCancelled, let store else { return false }
        let operation = UUID(); learningChangeGeneration = operation
        do {
            let change = try await store.applyLearnedDictionaryEntry(entry)
            if learningChangeGeneration == operation { lastLearnedChange = change }
            await refreshData()
            return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    func undoLastLearning() async {
        guard let store, let change = lastLearnedChange else { return }
        let operation = UUID(); learningChangeGeneration = operation
        do {
            let undone = try await store.undoDictionaryChange(applied: change.applied, previous: change.previous)
            if learningChangeGeneration == operation {
                lastLearnedChange = nil; canUndoLastLearning = false
                notice = undone ? "방금 학습한 표기를 되돌렸습니다." : "표기가 이미 변경되어 현재 사전을 유지했습니다."
            }
            await refreshData()
        } catch { self.error = error.localizedDescription }
    }
    enum AppError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
