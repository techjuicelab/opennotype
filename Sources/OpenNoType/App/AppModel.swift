import AppKit
import AVFoundation
import Observation
import OpenNoTypeCore
import ServiceManagement

@MainActor @Observable
final class AppModel {
    enum Phase { case idle, starting, recording, enrolling, processing }
    enum StartupState: Equatable { case loading, ready, failed }
    var startupState: StartupState = .ready
    var startupError: String?
    private struct ProcessingSnapshot {
        var transcriptionConfiguration: ProviderConfiguration
        var textConfiguration: ProviderConfiguration
        var needsLocal: Bool
        var speakerFilter: Bool
        var targetLanguage: String
        var dictionary: [DictionaryEntry]
        var writingProfile: WritingProfile
        var decisionReviewMode: DecisionReviewMode
        var decisionReviewEpoch: UUID
        var decisionConfiguration: DecisionConfiguration?
    }
    struct HistoryReprocessing: Identifiable {
        let id: UUID
        let entryID: UUID
        let settingsDescription: String
        var isProcessing = true
        var result: String?
        var error: String?
    }
    var preferences = Preferences() {
        didSet {
            if oldValue.interfaceLanguage != preferences.interfaceLanguage {
                AppLocalization.shared.language = preferences.interfaceLanguage
            }
            if persistPreferences { preferences.save() }
            if !preferences.automaticLearningEnabled { learningTask?.cancel() }
            if oldValue.usageTrackingEnabled != preferences.usageTrackingEnabled { usageResetGeneration = UUID() }
            if oldValue.decisionReviewMode != .off && preferences.decisionReviewMode == .off
                || oldValue.historyEnabled && !preferences.historyEnabled
                || oldValue.decisionProvider != preferences.decisionProvider {
                stopDecisionReview()
            }
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
    private(set) var decisionReviewSummary: String?
    private(set) var decisionTermSuggestions: [String] = []
    private(set) var decisionOriginalText: String?
    var hotkeyConflicts: [String] = []
    /// Short outcome summary shown on the floating bar for a few seconds after work ends.
    var transientMessage: String?
    var history: [HistoryEntry] = []
    private(set) var historyReprocessing: HistoryReprocessing?
    var dictionary: [DictionaryEntry] = []
    var failures: [FailedRecording] = []
    var apiKeyDraft = ""
    var retrySelection = ""
    var keySaved = false
    var savedKeyDraft = ""
    var keyDraftIsChanged: Bool { apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != savedKeyDraft }
    var textAPIKeyDraft = ""
    var textSavedKeyDraft = ""
    var textKeySaved = false
    var textKeyDraftIsChanged: Bool { textAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != textSavedKeyDraft }
    var decisionAPIKeyDraft = "" {
        didSet { if oldValue != decisionAPIKeyDraft { decisionKeyStatus = nil } }
    }
    private(set) var decisionKeySaved = false
    private(set) var decisionKeyOperationInProgress = false
    private(set) var decisionKeyStatus: String?
    private(set) var decisionConnectionTestInProgress = false
    private(set) var decisionConnectionTestStatus: String?
    var decisionKeyDraftIsChanged: Bool { decisionAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (savedDecisionKey ?? "") }
    var keyOperationsInProgress: Set<AIProvider> = []
    var keyOperationInProgress: Bool { !keyOperationsInProgress.isEmpty || decisionKeyOperationInProgress }
    var transcriptionKeyOperationInProgress: Bool { keyOperationsInProgress.contains(preferences.provider) }
    var textKeyOperationInProgress: Bool { keyOperationsInProgress.contains(preferences.effectiveTextProvider) }
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
    @ObservationIgnored private let decisionClient: any DecisionEvaluating
    @ObservationIgnored private let runtime: AppRuntime
    @ObservationIgnored private let usesCachedKeys: Bool
    @ObservationIgnored private var savedKeys: [AIProvider: String] = [:]
    @ObservationIgnored private var loadedKeyProviders: Set<AIProvider> = []
    @ObservationIgnored private var savedDecisionKey: String?
    @ObservationIgnored private var decisionKeyLoaded = false
    @ObservationIgnored private var decisionKeyOperationID: UUID?
    @ObservationIgnored private var decisionKeyTask: Task<Void, Never>?
    @ObservationIgnored private var decisionConnectionTask: Task<Void, Never>?
    @ObservationIgnored private var keyOperationIDs: [AIProvider: UUID] = [:]
    @ObservationIgnored private var keyOperationTasks: [AIProvider: Task<Void, Never>] = [:]
    @ObservationIgnored private var primaryDraftProvider: AIProvider?
    @ObservationIgnored private var textDraftProvider: AIProvider?
    @ObservationIgnored private var primaryDraftSelection = UUID()
    @ObservationIgnored private var textDraftSelection = UUID()
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
    @ObservationIgnored private var decisionReviewTask: Task<DecisionResult?, Never>?
    @ObservationIgnored private var decisionObservationTask: Task<Void, Never>?
    @ObservationIgnored private var decisionReviewEpoch = UUID()
    @ObservationIgnored private var housekeepingTask: Task<Void, Never>?
    @ObservationIgnored private var inputTestTask: Task<Void, Never>?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var runningAppsObservation: NSKeyValueObservation?
    @ObservationIgnored private var runningKnownApps: Set<String> = []
    @ObservationIgnored private var announcedConflicts: Set<String> = []
    @ObservationIgnored private var target: InputTarget?
    @ObservationIgnored private var generation = UUID() {
        didSet { stopDecisionReview() }
    }
    @ObservationIgnored private var cancelledInsertion: (job: UUID, replacementGeneration: UUID)?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var foreignActivation: String?
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var snapshot: ProcessingSnapshot?
    @ObservationIgnored var showManager: (() -> Void)?
    @ObservationIgnored var onPhaseChange: (() -> Void)?

    var isBusy: Bool { phase != .idle || decisionConnectionTestInProgress }
    var isRecording: Bool { phase == .recording || phase == .enrolling }
    var countdown: Int? { phase == .enrolling ? max(0, Int(ceil(30 - elapsed))) : RecordingPolicy.countdown(elapsed: elapsed) }
    var status: String {
        switch phase {
        case .idle: L("말할 준비가 되었어요", "Ready when you are")
        case .starting: L("마이크를 준비하고 있어요", "Preparing the microphone")
        case .recording: mode == .translation ? L("번역할 내용을 말해 주세요", "Speak to translate") : mode == .rewrite ? L("수정할 내용을 말해 주세요", "Describe your edit") : L("듣고 있어요", "Listening")
        case .enrolling: L("평소 목소리로 10초 이상 말해 주세요", "Speak in your normal voice for at least 10 seconds")
        case .processing: L("\(processingStage.title) 중이에요", "\(processingStage.title)…")
        }
    }

    init(store injectedStore: SecureStore? = nil, runtime: AppRuntime? = nil,
         client: ProviderClient = ProviderClient(), decisionClient: any DecisionEvaluating = DecisionClient(), startServices: Bool = true,
         preferences initialPreferences: Preferences? = nil, useCachedKeys: Bool? = nil) {
        self.runtime = runtime ?? AppRuntime(); self.client = client; self.decisionClient = decisionClient; persistPreferences = startServices
        usesCachedKeys = startServices || useCachedKeys == true
        preferences = initialPreferences ?? (startServices ? Preferences.load() : Preferences())
        AppLocalization.shared.language = preferences.interfaceLanguage
        if preferences.usageAccountingIncomplete { usageStorageError = L("일부 사용량이 기록되지 않았습니다. 표시된 합계가 실제 사용보다 적을 수 있습니다.", "Some usage was not recorded. The totals shown may be lower than your actual usage.") }
        if !startServices {
            store = injectedStore
            if let injectedStore { speaker = LocalSpeakerRecognizer(profileStore: SpeakerStoreAdapter(store: injectedStore)) }
            if !usesCachedKeys { loadKey(); loadTextKey() }
            refreshPermissions()
            return
        }
        do { try TemporaryAudioFiles.cleanupDeadSessions() }
        catch { self.error = L("이전 임시 녹음을 정리하지 못했습니다. \(error.localizedDescription)", "Could not clean up previous temporary recordings. \(error.localizedDescription)") }
        hotkeys.onPress = { [weak self] mode in Task { await self?.toggle(mode) } }
        recorder.onAutomaticFinish = { [weak self] in self?.stop() }
        recorder.onFailure = { [weak self] in self?.recordingFailed() }
        do { try hotkeys.register(preferences.hotkeys) } catch { self.error = error.localizedDescription }
        refreshHotkeyConflicts()
        if !hotkeyConflicts.isEmpty { notice = hotkeyConflicts.joined(separator: "\n") }
        observeKnownApps()
        refreshPermissions()
        startupState = .loading
        retryStartup()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidBecomeActive() }
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startupTask?.cancel()
                self?.keyOperationTasks.values.forEach { $0.cancel() }
                self?.decisionKeyTask?.cancel()
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
    /// Retrying reads the same encrypted store and its existing key; it never resets either.
    func retryStartup() {
        guard startupTask == nil, startupState != .ready else { return }
        startupState = .loading; startupError = nil
        startupTask = Task { [weak self] in
            guard let self else { return }
            await prepareStartup()
            startupTask = nil
        }
    }
    func prepareStartup() async {
        startupState = .loading; startupError = nil
        do {
            if store == nil {
                let opened = try await runtime.openStore()
                try Task.checkCancellation()
                store = opened
                speaker = LocalSpeakerRecognizer(profileStore: SpeakerStoreAdapter(store: opened))
            }
            let provider = preferences.provider, textProvider = preferences.effectiveTextProvider
            let needsTranscriptionKey = !preferences.needsLocal || provider == textProvider
            let key = needsTranscriptionKey ? (try await runtime.readStartupKey(provider) ?? "") : ""
            try Task.checkCancellation()
            let textKey = textProvider == provider ? key : (try await runtime.readStartupKey(textProvider) ?? "")
            try Task.checkCancellation()
            guard preferences.provider == provider, preferences.effectiveTextProvider == textProvider else {
                throw AppError.message(L("AI 연결 설정이 변경되었습니다. 준비를 다시 시도해 주세요.", "AI connection settings changed. Please try setup again."))
            }
            apiKeyDraft = key; savedKeyDraft = key; keySaved = !key.isEmpty
            textAPIKeyDraft = textKey; textSavedKeyDraft = textKey; textKeySaved = !textKey.isEmpty
            primaryDraftProvider = provider; textDraftProvider = textProvider
            savedKeys[provider] = key.isEmpty ? nil : key
            savedKeys[textProvider] = textKey.isEmpty ? nil : textKey
            if needsTranscriptionKey { loadedKeyProviders.insert(provider) }
            loadedKeyProviders.insert(textProvider)
            refreshPermissions()
            await refreshData()
            startupState = .ready
            // Jev is optional: a separate Keychain prompt must never gate dictation readiness.
            if preferences.decisionProvider == .typeSafe, preferences.decisionReviewMode != .off { loadDecisionKey() }
            if preferences.needsLocal { _ = await prepareLocalModel(download: false) }
            if preferences.speakerFilterEnabled { _ = await prepareSpeakerModel(download: false) }
        } catch is CancellationError {
            return
        } catch {
            startupState = .failed
            startupError = L("저장된 설정을 준비하지 못했습니다. 기존 데이터는 보존됩니다. \(error.localizedDescription)", "Could not load saved settings. Your existing data is preserved. \(error.localizedDescription)")
            refreshPermissions()
        }
    }
    /// This observer is owned by the application model, so closing the manager window does
    /// not leave permission state stale when the user returns from System Settings.
    func applicationDidBecomeActive() {
        refreshPermissions()
        guard startupState == .ready else { return }
        Task { [weak self] in await self?.refreshData() }
    }
    func refreshPermissions() {
        accessibilityAllowed = runtime.accessibilityPermitted()
        let permission = runtime.microphonePermission()
        microphoneAllowed = permission == .authorized
        microphonePermissionNeedsSettings = permission == .denied || permission == .restricted
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        loginItemStatusText = status == .requiresApproval ? L("시스템 설정에서 로그인 항목 승인이 필요합니다.", "Approve the login item in System Settings.") : nil
    }
    func requestMicrophone() async {
        defer { refreshPermissions() }
        switch runtime.microphonePermission() {
        case .authorized: microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await runtime.requestMicrophone()
            microphonePermissionNeedsSettings = !microphoneAllowed
            if !microphoneAllowed { notice = L("마이크 사용을 허용하려면 시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 OpenNoType을 켜 주세요.", "To allow microphone access, enable OpenNoType in System Settings › Privacy & Security › Microphone.") }
        case .denied, .restricted:
            microphonePermissionNeedsSettings = true
            notice = L("시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 OpenNoType을 허용한 뒤 돌아와 주세요.", "Allow OpenNoType in System Settings › Privacy & Security › Microphone, then return here.")
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
        guard startupState != .loading else { return }
        if usesCachedKeys {
            guard !preferences.needsLocal || preferences.provider == preferences.effectiveTextProvider else {
                apiKeyDraft = ""; savedKeyDraft = ""; keySaved = false
                return
            }
            loadProviderKey(preferences.provider)
            return
        }
        do { apiKeyDraft = try runtime.readKey(preferences.provider) ?? ""; savedKeyDraft = apiKeyDraft; keySaved = !apiKeyDraft.isEmpty }
        catch { self.error = error.localizedDescription; apiKeyDraft = ""; savedKeyDraft = ""; keySaved = false }
    }
    func saveKey() {
        guard startupState == .ready else { return }
        saveProviderKey(preferences.provider, draft: apiKeyDraft)
    }
    func loadTextKey() {
        guard startupState != .loading else { return }
        if usesCachedKeys { loadProviderKey(preferences.effectiveTextProvider); return }
        do {
            textAPIKeyDraft = try runtime.readKey(preferences.effectiveTextProvider) ?? ""
            textSavedKeyDraft = textAPIKeyDraft; textKeySaved = !textAPIKeyDraft.isEmpty
        } catch {
            self.error = error.localizedDescription; textAPIKeyDraft = ""; textSavedKeyDraft = ""; textKeySaved = false
        }
    }
    func saveTextKey() {
        guard startupState == .ready else { return }
        saveProviderKey(preferences.effectiveTextProvider, draft: textAPIKeyDraft)
    }

    func loadDecisionKey(force: Bool = false) {
        guard !AppLaunch.isPreview, preferences.decisionProvider == .typeSafe,
              !decisionKeyOperationInProgress, force || !decisionKeyLoaded else { return }
        if force { stopDecisionReview() }
        let id = UUID(), draft = decisionAPIKeyDraft
        decisionKeyOperationID = id; decisionKeyOperationInProgress = true; decisionKeyStatus = nil
        decisionKeyTask = Task { [weak self] in
            guard let self else { return }
            defer { finishDecisionKeyOperation(id) }
            do {
                let key = try await runtime.readDecisionKey(.typeSafe) ?? ""
                guard !Task.isCancelled, decisionKeyOperationID == id else { return }
                if force, preferences.decisionProvider == .typeSafe { stopDecisionReview() }
                savedDecisionKey = key.isEmpty ? nil : key
                decisionKeyLoaded = true; decisionKeySaved = !key.isEmpty
                if decisionAPIKeyDraft == draft { decisionAPIKeyDraft = key }
            } catch {
                guard !Task.isCancelled, decisionKeyOperationID == id else { return }
                // An optional reviewer must not fail startup or erase an already accepted key.
                decisionKeyStatus = L("TypeSafe 키를 읽지 못했습니다. 문장 검토 설정에서 다시 확인해 주세요.", "Could not read the TypeSafe key. Check it in the text review settings.")
            }
        }
    }

    func saveDecisionKey() {
        guard !AppLaunch.isPreview, preferences.decisionProvider == .typeSafe, !decisionKeyOperationInProgress else { return }
        stopDecisionReview()
        let id = UUID(), draft = decisionAPIKeyDraft
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        decisionKeyOperationID = id; decisionKeyOperationInProgress = true; decisionKeyStatus = nil
        decisionKeyTask = Task { [weak self] in
            guard let self else { return }
            defer { finishDecisionKeyOperation(id) }
            do {
                if key.isEmpty { try await runtime.deleteDecisionKey(.typeSafe) }
                else { try await runtime.saveDecisionKey(key, .typeSafe) }
                guard !Task.isCancelled, decisionKeyOperationID == id else { return }
                if preferences.decisionProvider == .typeSafe { stopDecisionReview() }
                savedDecisionKey = key.isEmpty ? nil : key
                decisionKeyLoaded = true; decisionKeySaved = !key.isEmpty
                if decisionAPIKeyDraft == draft { decisionAPIKeyDraft = key }
                if decisionKeyDraftIsChanged {
                    decisionKeyStatus = L("요청한 키 변경을 저장했습니다. 현재 입력란의 새 변경 사항은 아직 저장되지 않았습니다.", "The requested key change was saved. New edits currently in the field have not been saved yet.")
                } else {
                    decisionKeyStatus = key.isEmpty ? L("TypeSafe API 키를 삭제했습니다.", "Deleted the TypeSafe API key.") : L("TypeSafe API 키를 이 Mac의 Keychain에 저장했습니다.", "Saved the TypeSafe API key in this Mac's Keychain.")
                }
            } catch {
                guard !Task.isCancelled, decisionKeyOperationID == id else { return }
                decisionKeyStatus = L("TypeSafe 키 변경을 저장하지 못했습니다. 이전에 저장한 키를 유지합니다.", "Could not save the TypeSafe key change. The previously saved key is unchanged.")
            }
        }
    }

    private func finishDecisionKeyOperation(_ id: UUID) {
        guard decisionKeyOperationID == id else { return }
        decisionKeyOperationID = nil; decisionKeyTask = nil; decisionKeyOperationInProgress = false
    }

    private func decisionConfiguration(preferences selected: Preferences,
                                       textConfiguration: ProviderConfiguration? = nil) -> DecisionConfiguration? {
        switch selected.decisionProvider {
        case .openRouter:
            guard let textConfiguration, textConfiguration.provider == .openRouter else { return nil }
            return .init(provider: .openRouter, apiKey: textConfiguration.apiKey)
        case .typeSafe:
            // Never use an unsaved draft or wait for optional Keychain work on the recording path.
            return .init(provider: .typeSafe, apiKey: decisionKeyOperationInProgress ? "" : savedDecisionKey ?? "")
        }
    }

    func testDecisionConnection() {
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy, !keyOperationInProgress else { return }
        stopDecisionReview()
        let selected = preferences
        let config: DecisionConfiguration?
        if selected.decisionProvider == .typeSafe {
            config = decisionConfiguration(preferences: selected)
        } else {
            guard selected.effectiveTextProvider == .openRouter,
                  let textConfig = try? configuration(provider: .openRouter, preferences: selected) else {
                decisionConnectionTestStatus = L("연결을 확인하지 못했습니다. 문장 정리에 사용할 OpenRouter 키를 먼저 저장해 주세요.", "Could not check the connection. Save an OpenRouter key for text cleanup first.")
                return
            }
            config = decisionConfiguration(preferences: selected, textConfiguration: textConfig)
        }
        guard let config, !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            decisionConnectionTestStatus = L("연결을 확인하지 못했습니다. 선택한 연결의 API 키를 먼저 저장해 주세요.", "Could not check the connection. Save an API key for the selected connection first.")
            return
        }
        let job = UUID(), epoch = decisionReviewEpoch, usageEpoch = usageResetGeneration
        let tracksUsage = preferences.usageTrackingEnabled
        let request = DecisionRequest(transcript: "내일 오후 세 시에 회의를 시작해 주세요.",
                                      cleanedText: "내일 오후 3시에 회의를 시작해 주세요.")
        decisionConnectionTestInProgress = true
        decisionConnectionTestStatus = L("\(config.provider.displayName) 연결을 합성 문장으로 확인하고 있어요.", "Checking \(config.provider.displayName) with synthetic text.")
        decisionConnectionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if decisionReviewEpoch == epoch { decisionConnectionTestInProgress = false; decisionConnectionTask = nil }
            }
            let started = ProcessInfo.processInfo.systemUptime
            let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                guard tracksUsage else { return }
                await self?.recordUsage(event, job: job, mode: .dictation, isRecovery: false, epoch: usageEpoch)
            }
            do {
                let reviewed = try await decisionClient.evaluate(request, configuration: config, onUsage: collectUsage)
                guard !Task.isCancelled, decisionReviewEpoch == epoch else { return }
                let seconds = ProcessInfo.processInfo.systemUptime - started
                decisionConnectionTestStatus = L("연결 확인 완료 · \(config.provider.displayName) · \(reviewed.reportedModel) · \(String(format: "%.2f", seconds))초", "Connected · \(config.provider.displayName) · \(reviewed.reportedModel) · \(String(format: "%.2f", seconds))s")
            } catch {
                guard !Task.isCancelled, decisionReviewEpoch == epoch else { return }
                decisionConnectionTestStatus = L("연결을 확인하지 못했습니다. \((error as? DecisionError)?.localizedDescription ?? "잠시 뒤 다시 확인해 주세요.")", "Could not verify the connection. \((error as? DecisionError)?.localizedDescription ?? "Please try again later.")")
            }
        }
    }
    private func updateKeyDrafts(_ key: String, for provider: AIProvider,
                                 primaryDraft: String?, textDraft: String?,
                                 primarySelection: UUID, textSelection: UUID) {
        if preferences.provider == provider {
            if apiKeyDraft == primaryDraft || (primaryDraftSelection != primarySelection && apiKeyDraft.isEmpty) { apiKeyDraft = key }
            savedKeyDraft = key; keySaved = !key.isEmpty
        }
        if preferences.effectiveTextProvider == provider {
            if textAPIKeyDraft == textDraft || (textDraftSelection != textSelection && textAPIKeyDraft.isEmpty) { textAPIKeyDraft = key }
            textSavedKeyDraft = key; textKeySaved = !key.isEmpty
        }
    }
    private func resetDraftSelectionIfNeeded(_ provider: AIProvider) {
        if preferences.provider == provider, primaryDraftProvider != provider {
            primaryDraftProvider = provider; primaryDraftSelection = UUID()
            apiKeyDraft = ""; savedKeyDraft = ""; keySaved = false
        }
        if preferences.effectiveTextProvider == provider, textDraftProvider != provider {
            textDraftProvider = provider; textDraftSelection = UUID()
            textAPIKeyDraft = ""; textSavedKeyDraft = ""; textKeySaved = false
        }
    }
    private func finishKeyOperation(_ provider: AIProvider, id: UUID) {
        guard keyOperationIDs[provider] == id else { return }
        keyOperationsInProgress.remove(provider)
        keyOperationIDs[provider] = nil; keyOperationTasks[provider] = nil
    }
    private func loadProviderKey(_ provider: AIProvider) {
        resetDraftSelectionIfNeeded(provider)
        guard !keyOperationsInProgress.contains(provider) else { return }
        if preferences.provider == provider { apiKeyDraft = ""; savedKeyDraft = ""; keySaved = false }
        if preferences.effectiveTextProvider == provider { textAPIKeyDraft = ""; textSavedKeyDraft = ""; textKeySaved = false }
        let primaryDraft = preferences.provider == provider ? apiKeyDraft : nil
        let textDraft = preferences.effectiveTextProvider == provider ? textAPIKeyDraft : nil
        let primarySelection = primaryDraftSelection, textSelection = textDraftSelection
        let id = UUID(); keyOperationIDs[provider] = id; keyOperationsInProgress.insert(provider)
        keyOperationTasks[provider] = Task { [weak self] in
            guard let self else { return }
            defer { finishKeyOperation(provider, id: id) }
            do {
                let key = try await runtime.readStartupKey(provider) ?? ""
                guard !Task.isCancelled, keyOperationIDs[provider] == id else { return }
                savedKeys[provider] = key.isEmpty ? nil : key
                loadedKeyProviders.insert(provider)
                updateKeyDrafts(key, for: provider, primaryDraft: primaryDraft, textDraft: textDraft,
                               primarySelection: primarySelection, textSelection: textSelection)
            } catch {
                guard !Task.isCancelled, keyOperationIDs[provider] == id else { return }
                savedKeys[provider] = nil
                loadedKeyProviders.remove(provider)
                updateKeyDrafts("", for: provider, primaryDraft: primaryDraft, textDraft: textDraft,
                               primarySelection: primarySelection, textSelection: textSelection)
                if preferences.provider == provider || preferences.effectiveTextProvider == provider {
                    self.error = L("\(provider.displayName) API 키를 읽지 못했습니다. \(error.localizedDescription)", "Could not read the \(provider.displayName) API key. \(error.localizedDescription)")
                }
            }
        }
    }
    private func saveProviderKey(_ provider: AIProvider, draft: String) {
        guard !keyOperationsInProgress.contains(provider) else { return }
        if provider == .openRouter, preferences.decisionProvider == .openRouter { stopDecisionReview() }
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryDraft = preferences.provider == provider ? apiKeyDraft : nil
        let textDraft = preferences.effectiveTextProvider == provider ? textAPIKeyDraft : nil
        let primarySelection = primaryDraftSelection, textSelection = textDraftSelection
        let id = UUID(); keyOperationIDs[provider] = id; keyOperationsInProgress.insert(provider)
        keyOperationTasks[provider] = Task { [weak self] in
            guard let self else { return }
            defer { finishKeyOperation(provider, id: id) }
            do {
                if key.isEmpty { try await runtime.deleteStoredKey(provider) }
                else { try await runtime.saveStoredKey(key, provider) }
                guard !Task.isCancelled, keyOperationIDs[provider] == id else { return }
                if provider == .openRouter, preferences.decisionProvider == .openRouter { stopDecisionReview() }
                savedKeys[provider] = key.isEmpty ? nil : key
                loadedKeyProviders.insert(provider)
                updateKeyDrafts(key, for: provider, primaryDraft: primaryDraft, textDraft: textDraft,
                               primarySelection: primarySelection, textSelection: textSelection)
                notice = key.isEmpty ? L("\(provider.displayName) API 키를 삭제했습니다.", "Deleted the \(provider.displayName) API key.") : L("\(provider.displayName) API 키를 이 Mac의 Keychain에 저장했습니다.", "Saved the \(provider.displayName) API key in this Mac's Keychain.")
            } catch {
                guard !Task.isCancelled, keyOperationIDs[provider] == id else { return }
                self.error = L("\(provider.displayName) API 키를 저장하지 못했습니다. \(error.localizedDescription)", "Could not save the \(provider.displayName) API key. \(error.localizedDescription)")
            }
        }
    }
    /// Recovery may refer to providers that are no longer selected. Load only those required
    /// saved credentials asynchronously before freezing the recovery configurations.
    func prepareStoredKeys(for providers: Set<AIProvider>) async throws {
        guard usesCachedKeys else { return }
        for provider in providers.sorted(by: { $0.rawValue < $1.rawValue }) {
            try Task.checkCancellation()
            if !loadedKeyProviders.contains(provider) { loadProviderKey(provider) }
            if let task = keyOperationTasks[provider] { await task.value }
            try Task.checkCancellation()
            guard loadedKeyProviders.contains(provider) else {
                throw AppError.message(L("\(provider.displayName) API 키를 읽지 못했습니다. AI 연결 설정에서 다시 확인해 주세요.", "Could not read the \(provider.displayName) API key. Check it in AI connection settings."))
            }
        }
    }
    func updateHotkey(_ binding: HotkeyBinding, index: Int) {
        var replacements = preferences.hotkeys
        guard replacements.indices.contains(index) else { return }
        replacements[index] = binding
        do { try hotkeys.register(replacements); preferences.hotkeys = replacements; notice = L("단축키를 변경했습니다.", "Shortcuts updated."); refreshHotkeyConflicts() }
        catch { self.error = error.localizedDescription }
    }
    /// Carbon shortcuts are shared: every app registered for the same combination is notified.
    func refreshHotkeyConflicts() { hotkeyConflicts = runtime.hotkeyConflictWarnings(preferences.hotkeys) }
    /// Known apps launched after OpenNoType (or quit while it runs) change the overlap without any
    /// settings interaction, so the list follows `NSWorkspace.runningApplications` (KVO covers
    /// menu-bar-only apps such as notype, for which the launch notifications did not arrive here)
    /// instead of waiting for the settings page.
    private func observeKnownApps() {
        runningKnownApps = Self.runningKnownApps()
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.runningKnownAppsChanged() }
        }
    }
    private static func runningKnownApps() -> Set<String> {
        let known = Set(HotkeyConflicts.knownApps.map(\.bundleID))
        return Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).intersection(known)
    }
    private func runningKnownAppsChanged() {
        let running = Self.runningKnownApps()
        guard running != runningKnownApps else { return }
        runningKnownApps = running
        knownAppChanged()
    }
    private func knownAppChanged() {
        let previous = hotkeyConflicts
        refreshHotkeyConflicts()
        if hotkeyConflicts.isEmpty, !previous.isEmpty, notice == previous.joined(separator: "\n") { notice = nil }
        announceHotkeyConflicts()
    }
    /// Keeps the full list in the main window notice and shows each overlap once on the floating bar.
    private func announceHotkeyConflicts() {
        guard !hotkeyConflicts.isEmpty else { return }
        if foreignActivation == nil { notice = hotkeyConflicts.joined(separator: "\n") }
        let fresh = hotkeyConflicts.filter { !announcedConflicts.contains($0) }
        guard let first = fresh.first else { return }
        announcedConflicts.formUnion(fresh)
        let headline = first.components(separatedBy: ". ").first ?? first
        flash(L("\(headline). 설정 › 입력·단축키를 확인해 주세요.", "\(headline). Check Settings › Input & shortcuts."), seconds: 6)
    }
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
        let name = front.localizedName ?? L("다른 앱", "Another app")
        foreignActivation = name
        notice = L("단축키를 누르자 \(name)이(가) 앞으로 나왔습니다. 같은 단축키를 쓰는 앱이 있으면 자동입력이 실패할 수 있으니 한쪽 단축키를 바꿔 주세요. 이번에는 원래 앱을 다시 앞으로 가져와 입력합니다.", "\(name) came to the front when you pressed the shortcut. Shared shortcuts can prevent automatic typing. Change the shortcut in one app. This time, OpenNoType will return to the original app to type.")
        flash(L("\(name)이(가) 같은 단축키에 반응했습니다. 원래 앱으로 돌아가 입력합니다.", "\(name) responded to the same shortcut. Returning to the original app to type."), seconds: 3)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.launchAtLogin = enabled
            refreshPermissions()
        } catch { self.error = error.localizedDescription; refreshPermissions() }
    }
    func configuration(provider: AIProvider, preferences selectedPreferences: Preferences? = nil, requiresKey: Bool = true) throws -> ProviderConfiguration {
        let selectedPreferences = selectedPreferences ?? preferences
        let key: String
        if requiresKey {
            guard !keyOperationsInProgress.contains(provider) else {
                throw AppError.message(L("\(provider.displayName) Keychain 작업을 마친 뒤 다시 시작해 주세요.", "Wait for the \(provider.displayName) Keychain operation to finish, then try again."))
            }
            let saved = usesCachedKeys ? savedKeys[provider] : try runtime.readKey(provider)
            guard let saved, !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.message(L("설정에서 \(provider.displayName) API 키를 저장해 주세요.", "Save your \(provider.displayName) API key in Settings."))
            }
            key = saved
        } else { key = "" }
        let defaults = ProviderDefaults.forProvider(provider)
        func nonBlank(_ value: String?, fallback: String) -> String {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
            return value
        }
        return .init(provider: provider, apiKey: key,
            transcriptionModel: nonBlank(selectedPreferences.transcriptionModels[provider.rawValue], fallback: defaults.transcriptionModel),
            textModel: nonBlank(selectedPreferences.textModels[provider.rawValue], fallback: defaults.textModel))
    }
    func toggle(_ mode: InputMode) async {
        refreshPermissions()
        guard startupState == .ready else {
            notice = startupState == .loading ? L("Keychain과 저장된 설정을 준비하고 있어요. 인증창이 나타나면 이 Mac에서 승인해 주세요.", "Preparing Keychain and saved settings. If an authentication dialog appears, approve it on this Mac.") : L("저장된 설정 준비를 다시 시도한 뒤 녹음을 시작해 주세요.", "Retry loading saved settings before starting a recording.")
            showManager?()
            return
        }
        // Interrupt pending work, but keep a completed preview until recording actually starts.
        if historyReprocessing?.isProcessing == true { dismissHistoryReprocessing() }
        if inputTestArmed {
            if mode == .dictation, phase == .idle { await runInputTest(); return }
            if mode != .dictation { cancelInputTest() }
        }
        if isRecording { stop(); return }
        guard phase == .idle else { notice = L("현재 녹음을 처리한 뒤 다시 시작해 주세요.", "Wait for the current recording to finish processing, then try again."); return }
        let frontBefore = runtime.frontmostApplication()
        if frontBefore?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Recording here could only end in a result to copy by hand; say so instead of recording.
            // The window is already in front (or there is none), so showing it steals nothing.
            notice = L("OpenNoType 창에는 입력할 수 없습니다. 글을 입력할 앱의 입력창을 클릭한 뒤 단축키를 다시 눌러 주세요.", "OpenNoType cannot type into its own window. Click a text field in another app, then press the shortcut again.")
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
            guard store != nil else { throw AppError.message(L("암호화 저장소를 열 수 없습니다. 기존 데이터를 보존한 상태로 앱을 다시 실행해 주세요.", "Could not open encrypted storage. Restart the app; your existing data is preserved.")) }
            let startPreferences = preferences, startDictionary = dictionary
            let startDecisionReviewEpoch = decisionReviewEpoch
            let transcriptionConfig = try configuration(provider: startPreferences.provider, preferences: startPreferences,
                                                        requiresKey: !startPreferences.needsLocal)
            let textConfig = try configuration(provider: startPreferences.effectiveTextProvider, preferences: startPreferences)
            let reviewConfig = decisionConfiguration(preferences: startPreferences, textConfiguration: textConfig)
            guard runtime.accessibilityPermitted() else {
                TextInsertion.requestPermission(); refreshPermissions(); page = .home
                throw AppError.message(L("다른 앱에 글을 입력하려면 손쉬운 사용 권한이 필요합니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 OpenNoType을 허용한 뒤 다시 시도해 주세요.", "Accessibility permission is required to type in other apps. Allow OpenNoType in System Settings › Privacy & Security › Accessibility, then try again."))
            }
            guard !runtime.secureInputActive() else {
                throw AppError.message(L("비밀번호 입력란 등 보안 입력이 켜진 상태에서는 녹음을 시작하지 않습니다. 터미널 앱의 Secure Keyboard Entry 옵션도 같은 상태를 만듭니다. 옵션을 끄거나 다른 입력창을 클릭한 뒤 다시 시도해 주세요.", "Recording cannot start while Secure Input is active, such as in a password field or Terminal's Secure Keyboard Entry mode. Turn that option off or click another text field, then try again."))
            }
            let capturedTarget = await runtime.capture(startPreferences.allowedContextApps)
            guard generation == job, !Task.isCancelled else { return }
            guard let capturedTarget else { throw AppError.message(L("입력할 앱이 바뀌었습니다. 원하는 입력창에서 단축키를 다시 눌러 주세요.", "The target app changed. Press the shortcut again in the text field you want to use.")) }
            target = capturedTarget
            if target?.secureField == true {
                throw AppError.message(L("비밀번호 입력란에는 글을 입력하지 않습니다. 다른 입력창을 클릭한 뒤 다시 시도해 주세요.", "OpenNoType does not type into password fields. Click another text field, then try again."))
            }
            if mode == .rewrite, target?.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw AppError.message(L("수정할 문장을 선택한 뒤 단축키로 시작해 주세요. 손쉬운 사용 권한도 필요합니다.", "Select the text to edit, then press the shortcut. Accessibility permission is also required."))
            }
            snapshot = .init(transcriptionConfiguration: transcriptionConfig, textConfiguration: textConfig,
                needsLocal: startPreferences.needsLocal, speakerFilter: startPreferences.speakerFilterEnabled,
                targetLanguage: startPreferences.targetLanguage, dictionary: startDictionary,
                writingProfile: startPreferences.writingProfile(for: target?.bundleID),
                decisionReviewMode: startPreferences.decisionReviewMode, decisionReviewEpoch: startDecisionReviewEpoch,
                decisionConfiguration: reviewConfig)
            if startPreferences.needsLocal, localState != .ready {
                _ = await prepareLocalModel(download: false)
                guard generation == job, !Task.isCancelled else { return }
                guard localState == .ready else { page = .voice; throw AppError.message(L("먼저 로컬 음성 모델을 다운로드해 주세요.", "Download the local speech model first.")) }
            }
            if startPreferences.speakerFilterEnabled, speakerState != .ready {
                _ = await prepareSpeakerModel(download: false)
                guard generation == job, !Task.isCancelled else { return }
            }
            if startPreferences.speakerFilterEnabled, (!hasSpeakerProfile || speakerState != .ready) {
                page = .voice; throw AppError.message(L("내 목소리 필터를 사용하려면 화자 모델을 준비하고 목소리를 등록해 주세요.", "To use the voice filter, prepare the speaker model and enroll your voice."))
            }
            self.mode = mode; error = nil; notice = nil; result = ""; learningTask?.cancel()
            lastProcessingTimings = nil
            phase = .starting; onPhaseChange?()
            try await startRecording(); microphoneAllowed = true
            guard generation == job, !Task.isCancelled else { return }
            dismissHistoryReprocessing()
            noteForeignActivation(since: frontBefore)
            phase = .recording; startTimer(); onPhaseChange?()
            // Re-check on the start press: the other app may have launched since OpenNoType did.
            refreshHotkeyConflicts(); announceHotkeyConflicts()
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
        notice = L("입력창을 클릭한 뒤 받아쓰기 단축키를 누르세요. 음성·API 없이 테스트 문구만 입력합니다.", "Click a text field, then press the dictation shortcut. Only a test sentence will be typed, without recording or API calls.")
    }
    func cancelInputTest() {
        inputTestArmed = false
        inputTestTask?.cancel(); inputTestTask = nil
        notice = L("입력 테스트 준비를 취소했습니다.", "Typing test preparation cancelled.")
    }
    func scheduleInputTest() {
        guard !isBusy else { return }
        cancelledInsertion = nil
        inputTestArmed = true
        notice = L("5초 안에 시험할 입력창을 클릭하세요. 녹음 없이 테스트 문구를 입력합니다.", "Click the text field to test within 5 seconds. A test sentence will be typed without recording.")
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
            error = L("손쉬운 사용 권한이 없어 입력 테스트를 실행하지 않았습니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 OpenNoType을 허용해 주세요.", "The typing test did not run because Accessibility permission is missing. Allow OpenNoType in System Settings › Privacy & Security › Accessibility.")
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
        let text = L("OpenNoType 입력 테스트입니다.", "This is an OpenNoType input test.")
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
                    guard let speaker else { throw AppError.message(L("화자 저장소를 사용할 수 없습니다.", "Speaker profile storage is unavailable.")) }
                    _ = try await speaker.enroll(consumingRecordingAt: url)
                    guard generation == job, !Task.isCancelled else { return }
                    hasSpeakerProfile = true; notice = L("목소리를 등록했습니다. 원본 녹음은 삭제했습니다.", "Your voice has been enrolled. The original recording was deleted.")
                } catch { if generation == job { self.error = error.localizedDescription } }
                guard generation == job else { return }
                phase = .idle; onPhaseChange?()
            }
            return
        }
        if elapsed < 0.25 || (runtime.recordingPeakDB?() ?? recorder.peakDB) < -65 {
            recorder.discard(); phase = .idle; notice = L("음성이 감지되지 않아 입력하지 않았습니다.", "No speech detected. Nothing was typed."); onPhaseChange?(); return
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
        guard let url = stopRecording() else { phase = .idle; error = L("녹음이 중단되었습니다.", "Recording was interrupted."); onPhaseChange?(); return }
        if enrollment {
            recorder.discard(); phase = .idle
            error = L("목소리 등록 녹음이 중단되었습니다. 마이크 연결을 확인한 뒤 다시 등록해 주세요.", "Voice enrollment was interrupted. Check the microphone connection and try enrolling again.")
            onPhaseChange?(); return
        }
        let capturedSnapshot = snapshot, capturedMode = mode
        processingStage = .storage; phase = .processing; onPhaseChange?()
        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                if generation == job { phase = .idle; onPhaseChange?() }
            }
            guard let store, let capturedSnapshot else { error = L("녹음이 중단되어 원음을 복구하지 못했습니다.", "Recording was interrupted and the audio could not be recovered."); return }
            do {
                let config = capturedSnapshot.transcriptionConfiguration
                let item = FailedRecording(mode: capturedMode, provider: config.provider, textProvider: capturedSnapshot.textConfiguration.provider,
                    targetLanguage: capturedSnapshot.targetLanguage, transcriptionModel: config.transcriptionModel,
                    textModel: capturedSnapshot.textConfiguration.textModel, usedLocalTranscription: capturedSnapshot.needsLocal,
                    usedSpeakerFilter: capturedSnapshot.speakerFilter, writingProfile: capturedSnapshot.writingProfile)
                try Task.checkCancellation()
                try await store.saveFailure(item, audio: Data(contentsOf: url))
                guard generation == job, !Task.isCancelled else { return }
                await refreshData()
                guard generation == job, !Task.isCancelled else { return }
                error = L("마이크 녹음이 중단되었습니다. 남은 원음을 암호화해 보관했으니 다시 처리에서 확인해 주세요.", "Microphone recording was interrupted. The remaining audio was encrypted and saved. Find it in Recovery.")
            } catch {
                guard generation == job, !Task.isCancelled else { return }
                self.error = L("녹음이 중단되었고 복구 원음 저장에도 실패했습니다: \(error.localizedDescription)", "Recording was interrupted and recovery audio could not be saved: \(error.localizedDescription)")
            }
            showManager?()
        }
    }
    func cancel() {
        if historyReprocessing?.isProcessing == true {
            dismissHistoryReprocessing()
            notice = L("문장 다시 처리를 취소했습니다.", "Text reprocessing cancelled.")
            return
        }
        inputTestArmed = false; inputTestTask?.cancel()
        // Repeated cancellation still belongs to the same interrupted job until new work starts.
        let interruptedJob = cancelledInsertion?.replacementGeneration == generation ? cancelledInsertion!.job : generation
        let replacementGeneration = UUID()
        cancelledInsertion = (interruptedJob, replacementGeneration)
        generation = replacementGeneration; ticker?.cancel(); processingTask?.cancel(); learningTask?.cancel()
        recorder.discard(); target = nil; snapshot = nil
        phase = .idle; level = 0; onPhaseChange?(); notice = L("취소했습니다. 녹음은 삭제했습니다.", "Cancelled. The recording was deleted.")
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
            let config = snapshot.transcriptionConfiguration
            var audioURL = url
            var localSamples: [Float]?
            if snapshot.speakerFilter {
                guard let speaker, speakerState == .ready, hasSpeakerProfile else {
                    throw AppError.message(L("화자 모델을 준비하고 목소리를 등록한 뒤 다시 처리해 주세요.", "Prepare the speaker model and enroll your voice before reprocessing."))
                }
                let filtered = try await speaker.filter(audioURL: url)
                try Task.checkCancellation()
                guard job == generation else { return }
                guard !filtered.samples.isEmpty else { throw AppError.message(L("등록된 목소리를 확인하지 못했습니다. 녹음을 보관해 다시 처리할 수 있게 했습니다.", "Your enrolled voice was not detected. The recording was saved so you can reprocess it.")) }
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
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message(L("인식된 말이 없습니다. 녹음을 다시 처리할 수 있습니다.", "No speech was transcribed. You can reprocess the recording.")) }
            let request = ProcessingRequest(mode: mode, transcript: transcript, selectedText: selectedTextOverride ?? target?.selectedText,
                context: target?.context, dictionary: snapshot.dictionary, targetLanguage: snapshot.targetLanguage, writingProfile: snapshot.writingProfile)
            processingStage = .textProcessing
            let output = try await client.process(request, configuration: snapshot.textConfiguration, onUsage: collectUsage)
            timings.mark(.textProcessing)
            try Task.checkCancellation(); guard job == generation else { return }
            result = output
            let shouldReview = mode == .dictation
                && snapshot.decisionReviewMode != .off && snapshot.decisionReviewEpoch == decisionReviewEpoch
                && preferences.decisionReviewMode != .off
            var heldForReview = false
            if shouldReview, snapshot.decisionReviewMode == .protect {
                processingStage = .decisionReview
                heldForReview = await reviewDecision(transcript: transcript, output: output, snapshot: snapshot,
                    job: job, onUsage: collectUsage)
                timings.mark(.decisionReview)
                try Task.checkCancellation(); guard job == generation else { return }
            }
            processingStage = .insertion
            let outcome = if !heldForReview, let target {
                await runtime.insertText(output, target, mode == .rewrite,
                                         { self.generation != job || Task.isCancelled })
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
                    guard let store else { throw AppError.message(L("암호화 저장소를 사용할 수 없습니다.", "Encrypted storage is unavailable.")) }
                    _ = try await store.appendHistory(.init(mode: mode, originalText: transcript, resultText: output, sourceBundleID: target?.bundleID, provider: snapshot.textConfiguration.provider))
                    guard generation == job, !Task.isCancelled else { return }
                } catch {
                    guard generation == job, !Task.isCancelled else { return }
                    self.error = L("입력은 처리했지만 기록 저장에 실패했습니다: \(error.localizedDescription)", "Typing was handled, but history could not be saved: \(error.localizedDescription)")
                }
            }
            if let failure { try await store?.deleteFailure(id: failure.id) }
            guard generation == job, !Task.isCancelled else { return }
            if heldForReview {
                notice = L("문장 정리에서 의미가 달라졌을 가능성이 있어 자동 입력을 보류했습니다. 원문과 결과를 확인한 뒤 복사해 주세요.", "Automatic typing was held because cleanup may have changed the meaning. Compare the transcript and result before copying.")
                page = .home; showManager?()
            } else if target == nil {
                // Retry from 다시 처리, or a start without another app in front: the result is meant to be copied.
                notice = L("결과가 준비되었습니다. 복사해 원하는 입력창에 붙여넣으세요.", "Your result is ready. Copy it and paste it into the text field you want."); page = .home; showManager?()
            } else {
                let feedback = InsertionFeedback(outcome: outcome)
                switch feedback.severity {
                case .success: break
                case .info: notice = feedback.message
                case .warning:
                    notice = nil
                    let prefix = foreignActivation.map { L("\($0)이(가) 단축키에 반응해 앞으로 나왔습니다. ", "\($0) responded to the shortcut and came to the front. ") } ?? ""
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
            if shouldReview, snapshot.decisionReviewMode == .observe {
                // Observe after insertion and storage, without extending the user's input wait.
                decisionObservationTask = Task { [weak self] in
                    _ = await self?.reviewDecision(transcript: transcript, output: output, snapshot: snapshot,
                        job: job, onUsage: collectUsage)
                }
            }
        } catch {
            guard !Task.isCancelled, job == generation else { return }
            self.error = error.localizedDescription
            if failure == nil, let store {
                do {
                    let item = FailedRecording(mode: mode, provider: snapshot.transcriptionConfiguration.provider,
                        textProvider: snapshot.textConfiguration.provider, targetLanguage: snapshot.targetLanguage,
                        transcriptionModel: snapshot.transcriptionConfiguration.transcriptionModel,
                        textModel: snapshot.textConfiguration.textModel, usedLocalTranscription: snapshot.needsLocal,
                        usedSpeakerFilter: snapshot.speakerFilter, writingProfile: snapshot.writingProfile)
                    try await store.saveFailure(item, audio: Data(contentsOf: url))
                    guard generation == job, !Task.isCancelled else { return }
                    await refreshData()
                    guard generation == job, !Task.isCancelled else { return }
                } catch {
                    guard generation == job, !Task.isCancelled else { return }
                    self.error = L("처리와 복구 녹음 저장에 실패했습니다: \(error.localizedDescription)", "Processing failed and recovery audio could not be saved: \(error.localizedDescription)")
                }
            }
            guard generation == job, !Task.isCancelled else { return }
            showManager?()
        }
        guard job == generation, !Task.isCancelled else { return }
        phase = .idle; level = 0; onPhaseChange?()
    }

    private func stopDecisionReview() {
        decisionReviewEpoch = UUID()
        decisionObservationTask?.cancel(); decisionObservationTask = nil
        decisionReviewTask?.cancel(); decisionReviewTask = nil
        decisionConnectionTask?.cancel(); decisionConnectionTask = nil
        decisionConnectionTestInProgress = false; decisionConnectionTestStatus = nil
        decisionReviewSummary = nil; decisionTermSuggestions = []; decisionOriginalText = nil
    }

    /// The review never writes text, learns a dictionary entry, or changes an existing result.
    /// Its probability threshold is provisional, not a calibrated accuracy guarantee.
    private func reviewDecision(transcript: String, output: String, snapshot: ProcessingSnapshot,
                                job: UUID, onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async -> Bool {
        let epoch = snapshot.decisionReviewEpoch
        guard !Task.isCancelled, generation == job, epoch == decisionReviewEpoch,
              preferences.decisionReviewMode != .off else { return false }
        guard let configuration = snapshot.decisionConfiguration else {
            decisionReviewSummary = L("검토하지 않았습니다. OpenRouter 연결은 문장 정리 제공자가 OpenRouter일 때 같은 키를 사용합니다.", "Not reviewed. The OpenRouter connection reuses the key only when OpenRouter is the text cleanup provider.")
            return false
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            decisionReviewSummary = L("검토하지 않았습니다. \(configuration.provider.displayName) API 키를 준비하지 못해 기존 문장 정리 결과를 유지합니다.", "Not reviewed. The \(configuration.provider.displayName) API key was unavailable. The original cleanup result is unchanged.")
            return false
        }
        let terms = Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary)
        let request = DecisionRequest(transcript: transcript, cleanedText: output, termCandidates: terms)
        decisionReviewSummary = snapshot.decisionReviewMode == .protect ? L("입력 전에 문장 의미를 검토하고 있어요.", "Reviewing meaning before typing.") : L("문장 정리 결과를 백그라운드에서 검토하고 있어요.", "Reviewing the cleanup result in the background.")
        let client = decisionClient
        let task = Task<DecisionResult?, Never> {
            do { return try await client.evaluate(request, configuration: configuration, onUsage: onUsage) }
            catch { return nil }
        }
        decisionReviewTask = task
        let review = await task.value
        guard !Task.isCancelled, !task.isCancelled, generation == job, epoch == decisionReviewEpoch else { return false }
        decisionReviewTask = nil
        guard let review else {
            decisionReviewSummary = L("검토를 완료하지 못했습니다. 기존 문장 정리 결과를 그대로 유지합니다.", "Review could not be completed. The original cleanup result is unchanged.")
            return false
        }
        let highRisk = review.maximumRiskProbability >= 0.9
        let held = snapshot.decisionReviewMode == .protect && highRisk
        if held {
            decisionReviewSummary = L("의미가 달라졌을 가능성이 있어 자동 입력을 보류했어요. 원문과 결과를 비교해 주세요.", "Automatic typing was held because the meaning may have changed. Compare the transcript and result.")
            decisionOriginalText = transcript
        } else if highRisk {
            decisionReviewSummary = L("의미가 달라졌을 가능성을 발견했어요. 문장 정리 결과는 변경하지 않았습니다.", "The review found a possible meaning change. The cleanup result has not been modified.")
        } else {
            decisionReviewSummary = L("이번 검토에서 뚜렷한 의미 변경 신호를 찾지 못했습니다. 정확성을 보장하는 판정은 아닙니다.", "This review found no clear sign of a meaning change. It does not guarantee accuracy.")
        }
        decisionTermSuggestions = Self.decisionSuggestions(review: review, terms: terms,
                                                          transcript: transcript, output: output)
        return held
    }

    static func decisionSuggestions(review: DecisionResult, terms: [DecisionTermCandidate],
                                    transcript: String, output: String) -> [String] {
        let candidatesByID = Dictionary(uniqueKeysWithValues: terms.map { ($0.id, $0) })
        return review.terms.compactMap { term in
            guard let candidate = candidatesByID[term.id] else { return nil }
            switch term.choice {
            case .useCandidate:
                // A term discarded by an explicit self-correction does not need a spelling proposal.
                guard output.contains(candidate.original), !output.contains(candidate.candidate) else { return nil }
                return "\(candidate.original) → \(candidate.candidate)"
            case .keepOriginal:
                // A spoken Latin term may coexist with its Korean name; never suggest a global reversal.
                guard output.contains(candidate.candidate), !transcript.contains(candidate.candidate) else { return nil }
                return L("\(candidate.candidate) → \(candidate.original) · 원문 표기 유지", "\(candidate.candidate) → \(candidate.original) · Keep original spelling")
            case .uncertain: return nil
            }
        }
    }

    /// Only bounded caller-authored spellings become choices; Jev cannot invent a new name.
    static func decisionTermCandidates(transcript: String, dictionary: [DictionaryEntry]) -> [DecisionTermCandidate] {
        let builtIns: [(String, String)] = [
            ("오픈 라우터", "OpenRouter"), ("오픈라우터", "OpenRouter"),
            ("원 패스워드", "1Password"), ("원패스워드", "1Password"),
            ("오픈 노타입", "OpenNoType"), ("오픈노타입", "OpenNoType"),
            ("타이프리스", "Typeless"), ("그록", "Groq"), ("깃허브", "GitHub"),
            ("노션", "Notion"), ("에이피아이", "API")
        ]
        let personal = dictionary.reversed().map { ($0.spoken, $0.written) }
        var seen: Set<String> = []
        var selected: [DecisionTermCandidate] = []
        for (spoken, written) in personal + builtIns {
            let original = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !candidate.isEmpty, original != candidate,
                  original.count <= 100, candidate.count <= 100,
                  original.utf8.count <= 256, candidate.utf8.count <= 256,
                  !(original + candidate).unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  candidate.unicodeScalars.contains(where: { (65...90).contains($0.value) || (97...122).contains($0.value) }),
                  transcript.localizedCaseInsensitiveContains(original), seen.insert(original.lowercased()).inserted else { continue }
            selected.append(.init(id: "term_\(selected.count)", original: original, candidate: candidate))
            if selected.count == 4 { break }
        }
        return selected
    }
    private static func audioDuration(at url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return duration.isFinite && duration >= 0 ? duration : nil
    }

    func historyReprocessingUnavailableReason(for entry: HistoryEntry) -> String? {
        if entry.mode == .rewrite {
            return L("이 기록에는 음성으로 말한 수정 지시만 있고, 당시 선택한 문장은 없어 다시 처리할 수 없어요.", "This entry contains only the spoken editing instruction. The text selected at the time was not saved, so it cannot be reprocessed.")
        }
        if entry.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("다시 처리할 인식 원문이 없어요.", "There is no transcript to reprocess.")
        }
        if entry.originalText.count > 80_000 { return L("인식 원문이 너무 길어 다시 처리할 수 없어요.", "The transcript is too long to reprocess.") }
        return nil
    }

    func historyReprocessingSettings(for entry: HistoryEntry) -> String {
        let profile = preferences.writingProfile(for: entry.sourceBundleID)
        var description = L("현재 설정: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · \(profile.kind.title) / \(profile.tone.title) · 현재 개인 사전", "Current settings: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · \(profile.kind.title) / \(profile.tone.title) · Current dictionary")
        if entry.mode == .translation { description += L(" · 번역 언어: \(preferences.targetLanguage)", " · Translation language: \(preferences.targetLanguage)") }
        return description
    }

    /// History contains recognized speech, but no selected text or surrounding cursor context.
    /// Reprocessing is an explicit text-only request whose output stays in a disposable preview.
    func reprocessHistory(_ entry: HistoryEntry) {
        guard startupState == .ready else { return }
        guard !isBusy else { notice = L("현재 처리가 끝난 뒤 다시 시도해 주세요.", "Wait for the current operation to finish, then try again."); return }
        guard let store, history.contains(where: { $0.id == entry.id }) else {
            notice = L("이 기록은 더 이상 보관되어 있지 않아요.", "This history entry is no longer available.")
            return
        }
        if let reason = historyReprocessingUnavailableReason(for: entry) { notice = reason; return }
        let config: ProviderConfiguration
        do { config = try configuration(provider: preferences.effectiveTextProvider) }
        catch { self.error = error.localizedDescription; return }
        let request = ProcessingRequest(mode: entry.mode, transcript: entry.originalText,
                                        dictionary: dictionary, targetLanguage: preferences.targetLanguage,
                                        writingProfile: preferences.writingProfile(for: entry.sourceBundleID))
        let job = UUID(), usageEpoch = usageResetGeneration
        let tracksUsage = preferences.usageTrackingEnabled
        let retentionDays = preferences.retentionDays
        generation = job
        historyReprocessing = .init(id: job, entryID: entry.id, settingsDescription: historyReprocessingSettings(for: entry))
        phase = .processing; processingStage = .textProcessing; error = nil; notice = nil
        learningTask?.cancel(); onPhaseChange?()
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == job, historyReprocessing?.id == job {
                    historyReprocessing?.isProcessing = false
                    phase = .idle; onPhaseChange?()
                }
            }
            do {
                // Recheck storage before sending, and again before publishing a delayed response.
                let before = try await store.snapshot(retentionDays: retentionDays)
                guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                guard before.history.contains(where: { $0.id == entry.id }) else {
                    dismissHistoryReprocessing(); await refreshData(); return
                }
                let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                    guard tracksUsage else { return }
                    await self?.recordUsage(event, job: job, mode: entry.mode, isRecovery: false, epoch: usageEpoch)
                }
                let output = try await client.process(request, configuration: config, onUsage: collectUsage)
                try Task.checkCancellation()
                let after = try await store.snapshot(retentionDays: retentionDays)
                guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                guard after.history.contains(where: { $0.id == entry.id }) else {
                    dismissHistoryReprocessing(); await refreshData(); return
                }
                historyReprocessing?.result = output
            } catch {
                guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                historyReprocessing?.error = error.localizedDescription
            }
        }
    }

    func dismissHistoryReprocessing() {
        guard let preview = historyReprocessing else { return }
        historyReprocessing = nil
        if preview.isProcessing, generation == preview.id {
            generation = UUID(); processingTask?.cancel()
            phase = .idle; onPhaseChange?()
        }
    }

    /// Accounting is independent of result history and job cancellation. A received API response
    /// may be billable even when its content is rejected or the user has cancelled insertion.
    private func recordUsage(_ event: ProviderUsage, job: UUID, mode: InputMode, isRecovery: Bool, epoch: UUID) async {
        guard preferences.usageTrackingEnabled, usageResetGeneration == epoch else { return }
        guard let store else { preferences.usageAccountingIncomplete = true; usageStorageError = L("사용량 저장소를 열 수 없습니다. 이번 요청은 통계에 포함되지 않았습니다.", "Could not open usage storage. This request was not included in the statistics."); return }
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
            usageStorageError = L("일부 사용량을 저장하지 못했습니다. 표시된 합계가 실제 사용보다 적을 수 있습니다.", "Some usage could not be saved. The totals shown may be lower than your actual usage.")
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
        } catch { usageStorageError = L("사용량 기록을 초기화하지 못했습니다. 기존 기록은 보존됩니다.", "Could not reset usage records. Existing records are preserved.") }
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
            if let preview = historyReprocessing, !history.contains(where: { $0.id == preview.entryID }) {
                dismissHistoryReprocessing()
            }
            usageRecords = current.usageRecords; usageTrackingStartedAt = current.usageTrackingStartedAt
            usageDiscardedCount = current.usageDiscardedCount
            failures = current.failedRecordings; learningCandidate = current.learningCandidates.first
            hasSpeakerProfile = current.hasVoiceProfile
            if let change = lastLearnedChange { canUndoLastLearning = dictionary.contains(change.applied) }
        } catch { if dataRefreshGeneration == refresh { self.error = L("기존 데이터를 보존했습니다. \(error.localizedDescription)", "Your existing data is preserved. \(error.localizedDescription)") } }
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
        guard let store else { error = L("암호화 저장소를 사용할 수 없습니다.", "Encrypted storage is unavailable."); return false }
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
        stopDecisionReview()
        guard let store else { return }
        if let preview = historyReprocessing, entry == nil || entry?.id == preview.entryID {
            dismissHistoryReprocessing()
        }
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
        guard startupState == .ready, !isBusy, let store else { return }
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        lastProcessingTimings = nil
        let selectedRetryText = retrySelection
        generation = UUID(); let job = generation; processingStage = .audioPreparation
        phase = .processing; error = nil; notice = nil; result = ""; learningTask?.cancel(); onPhaseChange?()
        processingTask = Task {
            do {
                let selection = selectedRetryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard item.mode != .rewrite || !selection.isEmpty else { throw AppError.message(L("원래 선택 문장은 저장하지 않습니다. 수정할 원문을 붙여넣은 뒤 다시 처리해 주세요.", "The original selection is not stored. Paste the text you want to edit before reprocessing.")) }
                let retryPreferences = preferences
                let retryDictionary = dictionary
                let retryDecisionReviewEpoch = decisionReviewEpoch
                let retryDecisionKey = decisionKeyOperationInProgress ? "" : savedDecisionKey ?? ""
                let transcriptionProvider = useCurrentSettings ? retryPreferences.provider : item.provider
                let textProvider = useCurrentSettings ? retryPreferences.effectiveTextProvider : item.textProvider ?? item.provider
                let needsLocal = useCurrentSettings ? retryPreferences.needsLocal : item.usedLocalTranscription ?? (item.provider == .anthropic)
                var requiredProviders: Set<AIProvider> = [textProvider]
                if !needsLocal { requiredProviders.insert(transcriptionProvider) }
                try await prepareStoredKeys(for: requiredProviders)
                guard generation == job, !Task.isCancelled else { return }
                var transcriptionConfig = try configuration(provider: transcriptionProvider, preferences: retryPreferences,
                                                            requiresKey: !needsLocal)
                var textConfig = try configuration(provider: textProvider, preferences: retryPreferences)
                func stored(_ value: String?) -> String? {
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                    return value
                }
                if !useCurrentSettings {
                    transcriptionConfig.transcriptionModel = stored(item.transcriptionModel) ?? transcriptionConfig.transcriptionModel
                    textConfig.textModel = stored(item.textModel) ?? textConfig.textModel
                }
                let reviewConfig: DecisionConfiguration? = retryPreferences.decisionProvider == .typeSafe
                    ? .init(provider: .typeSafe, apiKey: retryDecisionKey)
                    : decisionConfiguration(preferences: retryPreferences, textConfiguration: textConfig)
                let snapshot = ProcessingSnapshot(transcriptionConfiguration: transcriptionConfig, textConfiguration: textConfig,
                    needsLocal: needsLocal,
                    speakerFilter: useCurrentSettings ? retryPreferences.speakerFilterEnabled : item.usedSpeakerFilter ?? false,
                    targetLanguage: useCurrentSettings ? retryPreferences.targetLanguage : item.targetLanguage,
                    dictionary: retryDictionary, writingProfile: item.writingProfile ?? .init(),
                    decisionReviewMode: retryPreferences.decisionReviewMode, decisionReviewEpoch: retryDecisionReviewEpoch,
                    decisionConfiguration: reviewConfig)
                if snapshot.needsLocal, localState != .ready { _ = await prepareLocalModel(download: false) }
                if snapshot.speakerFilter, speakerState != .ready { _ = await prepareSpeakerModel(download: false) }
                guard generation == job, !Task.isCancelled else { return }
                guard !snapshot.needsLocal || localState == .ready else { throw AppError.message(L("먼저 로컬 음성 모델을 다운로드해 주세요.", "Download the local speech model first.")) }
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
                localState = .failed(L("모델 준비 실패: \(error.localizedDescription)", "Model setup failed: \(error.localizedDescription)"))
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
        guard let speaker else { error = L("화자 저장소를 사용할 수 없습니다.", "Speaker profile storage is unavailable."); return false }
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
                speakerState = .failed(L("모델 준비 실패: \(error.localizedDescription)", "Model setup failed: \(error.localizedDescription)"))
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
        guard startupState == .ready else {
            notice = L("저장된 설정 준비를 마친 뒤 목소리를 등록해 주세요.", "Wait for saved settings to finish loading before enrolling your voice.")
            return
        }
        guard !isBusy else { return }
        guard speakerState == .ready else { error = L("먼저 화자 모델을 준비해 주세요.", "Prepare the speaker model first."); return }
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
                        self.notice = L("개인 사전에 ‘\(entry.written)’ 표기를 학습했습니다.", "Learned ‘\(entry.written)’ in your dictionary.")
                        self.flash(L("‘\(entry.written)’ 표기를 개인 사전에 기억했어요.", "Remembered ‘\(entry.written)’ in your dictionary."))
                    }
                } else if let candidate = CorrectionLearner.reviewCandidate(original: output, edited: edited), self.preferences.historyEnabled {
                    do {
                        guard let store = self.store else { throw AppError.message(L("암호화 저장소를 사용할 수 없습니다.", "Encrypted storage is unavailable.")) }
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
                notice = undone ? L("방금 학습한 표기를 되돌렸습니다.", "Undid the last learned spelling.") : L("표기가 이미 변경되어 현재 사전을 유지했습니다.", "The spelling has already changed. The current dictionary was kept.")
            }
            await refreshData()
        } catch { self.error = error.localizedDescription }
    }
    enum AppError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
