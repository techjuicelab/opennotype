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
        var outputLanguage: DictationOutputLanguage = .original
        var dictionary: [DictionaryEntry]
        var writingProfile: WritingProfile
        var decisionReviewMode: DecisionReviewMode
        var translationProtectionEnabled = false
        var decisionReviewEpoch: UUID
        var decisionConfiguration: DecisionConfiguration?
        var assistancePreferences = Preferences()
        var translationRefinementEpoch = UUID()
    }
    struct HistoryReprocessing: Identifiable {
        let id: UUID
        let entryID: UUID
        let settingsDescription: String
        var isProcessing = true
        var result: String?
        var error: String?
        var reviewTarget: JevReviewTarget?
        var translationRefinement: TranslationRefinementPresentation?
    }
    @ObservationIgnored private var restoringRejectedPreferences = false
    var preferences = Preferences() {
        didSet {
            // @Observable rewrites this as an accessor: assigning here re-enters didSet.
            // Reject a recovery-time edit once without recursively restoring itself.
            if restoringRejectedPreferences { return }
            // Programmatic bindings must not bypass the recovery gate. No setting, learning
            // policy or retention write takes effect until a recovery action is chosen.
            if preferences.recoveryState.requiresRecovery {
                if oldValue.recoveryState.requiresRecovery {
                    restoringRejectedPreferences = true
                    preferences = oldValue
                    restoringRejectedPreferences = false
                }
                else { suspendForPreferencesRecovery() }
                return
            }
            if oldValue.interfaceLanguage != preferences.interfaceLanguage {
                AppLocalization.shared.language = preferences.interfaceLanguage
            }
            if persistPreferences, !preferences.save(to: runtime.preferencesDefaults) {
                let recovered = Preferences.load(from: runtime.preferencesDefaults)
                if recovered.recoveryState.requiresRecovery {
                    preferences = recovered; suspendForPreferencesRecovery(); return
                }
            }
            // Recovery resumes through startup, which first synchronizes the selected
            // retention policy. An observer must not touch a stale vault before that step.
            if oldValue.recoveryState.requiresRecovery { return }
            if preferences.decisionProvider == .typeSafe,
               oldValue.jevClarifyEditsEnabled != preferences.jevClarifyEditsEnabled
                || oldValue.jevReRecognitionEnabled != preferences.jevReRecognitionEnabled { loadDecisionKey() }
            if !preferences.automaticLearningEnabled { learningTask?.cancel() }
            if oldValue.effectiveTextProvider != preferences.effectiveTextProvider || oldValue.textModel != preferences.textModel {
                // Initial preferences are assigned before the store. A scope change only
                // refreshes learning, so it cannot invalidate an awaited history/usage refresh.
                if store != nil { Task { await refreshJevLearnedIssues() } }
            }
            if oldValue.usageTrackingEnabled != preferences.usageTrackingEnabled { usageResetGeneration = UUID(); jevQualityMetrics.clear() }
            if oldValue.historyEnabled && !preferences.historyEnabled { recentDecisionTarget = nil }
            if oldValue.historyEnabled && !preferences.historyEnabled {
                if promptComposition?.isProcessing == true { stopDecisionReview() }
                promptComposition = nil
            }
            if promptCompositionJob == generation, phase != .idle,
               oldValue.effectiveTextProvider != preferences.effectiveTextProvider
                || oldValue.textModel != preferences.textModel
                || oldValue.decisionProvider != preferences.decisionProvider {
                cancel()
            }
            if oldValue.historyEnabled && !preferences.historyEnabled {
                historyWriteEpoch = UUID()
                Task { await eraseJevFeedbackLearning() }
            }
            if oldValue.translationRefinementEnabled && !preferences.translationRefinementEnabled
                || oldValue.historyEnabled && !preferences.historyEnabled {
                revokeTranslationRefinement(clearPresentation: oldValue.historyEnabled && !preferences.historyEnabled)
                if oldValue.historyEnabled && !preferences.historyEnabled { dismissHistoryReprocessing() }
            }
            if (translationProtectionJob == generation
                && (oldValue.translationProtectionEnabled && !preferences.translationProtectionEnabled
                    || oldValue.decisionReviewMode == .protect && preferences.decisionReviewMode != .protect))
                || oldValue.decisionReviewMode != .off && preferences.decisionReviewMode == .off
                || oldValue.historyEnabled && !preferences.historyEnabled
                || oldValue.decisionProvider != preferences.decisionProvider {
                stopDecisionReview()
            } else if (oldValue.effectiveTextProvider != preferences.effectiveTextProvider
                || oldValue.textModel != preferences.textModel || oldValue.improvementModel != preferences.improvementModel),
                manualDecisionReviewInProgress || jevRepairInProgress || decisionReviewTask != nil || decisionObservationTask != nil
                    || jevImprovement != nil || jevCorrectionReview != nil
                    || jevEditClarification != nil || jevReRecognition != nil || jevModelComparison.isRunning {
                // Explicit workflows follow their confirmation; a recording keeps its captured settings.
                stopDecisionReview()
            }
            if oldValue.jevDetailedReviewEnabled != preferences.jevDetailedReviewEnabled
                || oldValue.jevNameCatalog != preferences.jevNameCatalog
                || oldValue.jevEconomyEnabled != preferences.jevEconomyEnabled
                || oldValue.jevClarifyEditsEnabled != preferences.jevClarifyEditsEnabled
                || oldValue.jevReRecognitionEnabled != preferences.jevReRecognitionEnabled
                || oldValue.jevAutomaticImprovementEnabled != preferences.jevAutomaticImprovementEnabled
                || oldValue.jevFeedbackLearningEnabled != preferences.jevFeedbackLearningEnabled
                || (oldValue.decisionReviewMode != preferences.decisionReviewMode
                    && (oldValue.decisionReviewMode == .repair || preferences.decisionReviewMode == .repair
                        || phase != .recording)) {
                // Revocation also invalidates an in-flight automatic check before it publishes a preview.
                stopDecisionReview()
            }
        }
    }
    var page: AppPage = .home
    var settingsSection: SettingsSection = .connection
    var jevQualityMetrics = JevQualityMetrics()
    private(set) var jevImprovement: JevImprovement?
    private(set) var jevCorrectionReview: JevCorrectionReview?
    private(set) var jevEditClarification: JevEditClarification?
    private(set) var jevReRecognition: JevReRecognition?
    private(set) var jevModelComparisonPreparing = false
    private(set) var jevRepairInProgress = false
    private(set) var jevLearningSummary: String?
    private(set) var jevLearnedIssues: [JevRepairIssue] = []
    @ObservationIgnored private var jevLearningRefreshGeneration = UUID()
    @ObservationIgnored private var lastAutomaticReview: DecisionResult?
    @ObservationIgnored private var jevRepairTask: Task<JevRepairAttempt, Never>?
    @ObservationIgnored private var jevLessonWriteTask: Task<Void, Error>?
    @ObservationIgnored private var jevAssistanceOperation = UUID()
    private(set) var jevNameDiscoveryInProgress = false
    private(set) var jevNameDiscoveryStatus: String?
    let jevModelComparison = JevModelComparison()
    @ObservationIgnored private var automaticImprovementTarget: JevReviewTarget?
    @ObservationIgnored private var jevAssistanceTask: Task<Void, Never>?
    @ObservationIgnored private var jevAssistancePreferences: Preferences?
    @ObservationIgnored private var jevAssistanceDictionary: [DictionaryEntry] = []
    @ObservationIgnored private var jevAssistanceWritingProfile = WritingProfile()
    @ObservationIgnored private var jevWorkflowTask: Task<Void, Never>?
    var jevWorkflowInProgress: Bool { jevImprovement?.isProcessing == true || jevCorrectionReview?.isProcessing == true
        || jevNameDiscoveryInProgress || jevEditClarification?.isProcessing == true
        || jevReRecognition?.isProcessing == true || jevRepairInProgress
        || jevModelComparison.isRunning || jevModelComparisonPreparing }
    var usageRecords: [UsageRecord] = []
    var usageTrackingStartedAt: Date?
    var usageDiscardedCount = 0
    var usageStorageError: String?
    @ObservationIgnored private var usageResetGeneration = UUID()
    @ObservationIgnored private var historyWriteEpoch = UUID()
    var phase: Phase = .idle
    var mode: InputMode = .dictation
    var elapsed: TimeInterval = 0
    var level: Double = 0
    var notice: String?
    var error: String?
    var result: String = ""
    private(set) var translationRefinement: TranslationRefinementPresentation?
    private(set) var promptComposition: PromptCompositionPresentation?
    @ObservationIgnored private var translationRefinementEpoch = UUID()
    @ObservationIgnored private var translationRefinementJob: UUID?
    var inputTestArmed = false
    var inputDiagnostics = ""
    var lastProcessingTimings: String?
    private(set) var decisionReviewSummary: String?
    private(set) var decisionReviewFailure: JevReviewFailure?
    private(set) var decisionTermSuggestions: [String] = []
    private(set) var decisionOriginalText: String?
    private(set) var recentDecisionTarget: JevReviewTarget?
    private(set) var decisionReviewTarget: JevReviewTarget?
    private(set) var decisionProposals: [JevSpellingProposal] = []
    private(set) var decisionRiskSignals: [JevRiskSignal] = []
    private(set) var manualDecisionReviewInProgress = false
    private(set) var manualDecisionReviewStatus: String?
    private(set) var decisionProposalStatus: String?
    private(set) var decisionDictionaryOperationInProgress = false
    private(set) var canUndoDecisionDictionarySave = false
    var hotkeyConflicts: [String] = []
    private(set) var registeredHotkeys: [HotkeyBinding]?
    @ObservationIgnored private let startsSystemServices: Bool
    var hotkeysRegistered: Bool { !startsSystemServices || registeredHotkeys != nil }
    func hotkeyLabel(index: Int) -> String {
        let bindings = startsSystemServices ? registeredHotkeys : preferences.hotkeys
        guard let bindings, bindings.indices.contains(index) else { return L("등록되지 않음", "Not registered") }
        return bindings[index].label
    }
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
    @ObservationIgnored private var decisionReviewTask: Task<DecisionResult, Error>?
    @ObservationIgnored private var decisionObservationTask: Task<Void, Never>?
    @ObservationIgnored private var decisionReviewEpoch = UUID()
    @ObservationIgnored private var translationProtectionReviewEpoch: UUID?
    @ObservationIgnored private var manualDecisionReviewTask: Task<Void, Never>?
    @ObservationIgnored private var manualDecisionReviewID: UUID?
    @ObservationIgnored private var decisionDictionaryTask: Task<ReviewedDictionarySaveResult, Error>?
    @ObservationIgnored private var lastDecisionDictionaryChange: (applied: DictionaryEntry, previous: DictionaryEntry?)?
    @ObservationIgnored private var currentDecisionReviewID: UUID?
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
        didSet {
            recentDecisionTarget = nil; stopDecisionReview()
            promptCompositionJob = nil
            promptComposition = nil
            if translationRefinement?.isProcessing == true || translationRefinement?.held == true { result = "" }
            translationRefinement = nil; translationRefinementJob = nil
        }
    }
    @ObservationIgnored private var cancelledInsertion: (job: UUID, replacementGeneration: UUID)?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var foreignActivation: String?
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var translationProtectionJob: UUID?
    /// Marks the actual job before its first suspension; `mode` describes the last recording
    /// and cannot identify history previews or recovery jobs.
    @ObservationIgnored private var promptCompositionJob: UUID?
    @ObservationIgnored private var snapshot: ProcessingSnapshot?
    @ObservationIgnored var showManager: (() -> Void)?
    @ObservationIgnored var onPhaseChange: (() -> Void)?

    var isBusy: Bool { phase != .idle || decisionConnectionTestInProgress }
    var preferencesRecoveryRequired: Bool { preferences.recoveryState.requiresRecovery }
    private func suspendForPreferencesRecovery() {
        cancel(); startupState = .failed
        startupError = L("저장된 설정 일부를 읽지 못했습니다. 기존 설정과 기록을 보존했습니다. 설정 복구를 선택해 주세요.", "Some saved settings could not be read. Your settings and records are preserved. Choose how to recover settings.")
    }
    var canRestorePreviousPreferences: Bool { Preferences.canRestoreLastKnownGood(from: runtime.preferencesDefaults) }
    func restorePreviousPreferences() {
        guard preferencesRecoveryRequired,
              let restored = Preferences.restoreLastKnownGood(from: runtime.preferencesDefaults) else {
            startupError = L("복구할 이전 설정을 확인하지 못했습니다. 손상 원본은 보존됩니다.", "No previous settings could be verified for recovery. The damaged source is preserved.")
            return
        }
        preferences = restored; resumeAfterPreferencesRecovery()
    }
    func acceptRecoveredPreferences() {
        guard preferencesRecoveryRequired, let recovered = preferences.acceptRecovery(to: runtime.preferencesDefaults) else {
            startupError = L("설정 원본이 바뀌었거나 복구 내용을 저장하지 못했습니다. 앱을 다시 실행해 확인해 주세요.", "The settings source changed or recovery could not be saved. Restart the app to check it.")
            return
        }
        preferences = recovered; resumeAfterPreferencesRecovery()
    }
    private func resumeAfterPreferencesRecovery() {
        if startsSystemServices {
            do { try hotkeys.register(preferences.hotkeys) } catch { self.error = error.localizedDescription }
            registeredHotkeys = hotkeys.registeredBindings
        }
        startupError = nil; startupState = .failed
        retryStartup()
    }
    private func storageChangesPermitted() -> Bool {
        guard !preferencesRecoveryRequired else {
            error = L("기록을 보호하기 위해 설정 복구 선택 전에는 데이터 변경을 하지 않습니다.", "To protect your records, data cannot be changed until you choose how to recover settings.")
            return false
        }
        return true
    }
    var requiredJevIssue: JevPreflightIssue? {
        jevPreflightIssue(mode: .dictation, preferences: preferences, textProvider: preferences.effectiveTextProvider)
    }
    var requiredJevReady: Bool { requiredJevIssue == nil }
    var promptCompositionIssue: String? {
        switch preferences.decisionProvider {
        case .openRouter:
            guard preferences.effectiveTextProvider == .openRouter else {
                return L("프롬프트 만들기는 Jev 검토가 필요합니다. 문장 제공자를 OpenRouter로 선택하거나 Jev 직접 연결을 설정해 주세요.", "Prompt creation requires Jev review. Select OpenRouter for text processing or configure a direct Jev connection.")
            }
            if keyOperationsInProgress.contains(.openRouter) {
                return L("OpenRouter 키를 준비한 뒤 시작해 주세요.", "Start after the OpenRouter key is ready.")
            }
            if !(preferences.provider == .openRouter ? keySaved : textKeySaved) {
                return L("설정에서 프롬프트 생성과 Jev 검토에 사용할 OpenRouter 키를 저장해 주세요.", "Save an OpenRouter key in Settings for prompt creation and Jev review.")
            }
        case .typeSafe:
            if !decisionKeyLoaded || decisionKeyOperationInProgress {
                return L("Jev 키를 준비하고 있습니다. AI 연결에서 저장된 키를 확인해 주세요.", "Preparing the Jev key. Check the saved key in AI connections.")
            }
            if !decisionKeySaved {
                return L("프롬프트 만들기에 필요한 Jev 직접 연결 키를 설정에서 저장해 주세요.", "Save the direct Jev connection key in Settings to create prompts.")
            }
        }
        return nil
    }
    var promptRegenerationSettings: String {
        L("현재 설정: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · Jev: \(preferences.decisionProvider.displayName) / \(preferences.decisionProvider.model)",
          "Current settings: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · Jev: \(preferences.decisionProvider.displayName) / \(preferences.decisionProvider.model)")
    }
    var jevReviewMayDelayInput: Bool {
        preferences.decisionReviewMode == .protect || preferences.decisionReviewMode == .repair
            || (preferences.decisionReviewMode == .observe && preferences.jevReRecognitionEnabled)
    }
    private func jevPreflightIssue(mode: InputMode, preferences selected: Preferences,
                                   textProvider: AIProvider) -> JevPreflightIssue? {
        guard mode == .dictation, !selected.dictationOutputLanguage.isTranslation,
              selected.decisionReviewMode == .repair else { return nil }
        switch selected.decisionProvider {
        case .openRouter:
            return textProvider == .openRouter ? nil : .incompatibleTextProvider
        case .typeSafe:
            if decisionKeyOperationInProgress { return .keyLoading }
            return savedDecisionKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? nil : .keyMissing
        }
    }
    var isRecording: Bool { phase == .recording || phase == .enrolling }
    var countdown: Int? { phase == .enrolling ? max(0, Int(ceil(30 - elapsed))) : RecordingPolicy.countdown(elapsed: elapsed) }
    var status: String {
        switch phase {
        case .idle: return L("말할 준비가 되었어요", "Ready when you are")
        case .starting: return L("마이크를 준비하고 있어요", "Preparing the microphone")
        case .recording:
            if mode == .dictation, let language = snapshot?.outputLanguage, language.isTranslation {
                return L("\(language.title)로 옮길 내용을 듣고 있어요", "Listening to translate into \(language.title)")
            }
            return mode == .translation ? L("번역할 내용을 말해 주세요", "Speak to translate") : mode == .rewrite ? L("수정할 내용을 말해 주세요", "Describe your edit") : L("듣고 있어요", "Listening")
        case .enrolling: return L("평소 목소리로 10초 이상 말해 주세요", "Speak in your normal voice for at least 10 seconds")
        case .processing: return L("\(processingStage.title) 중이에요", "\(processingStage.title)…")
        }
    }

    init(store injectedStore: SecureStore? = nil, runtime: AppRuntime? = nil,
         client: ProviderClient = ProviderClient(), decisionClient: any DecisionEvaluating = DecisionClient(), startServices: Bool = true,
         preferences initialPreferences: Preferences? = nil, useCachedKeys: Bool? = nil) {
        self.runtime = runtime ?? AppRuntime(); self.client = client; self.decisionClient = decisionClient; persistPreferences = startServices
        startsSystemServices = startServices
        usesCachedKeys = startServices || useCachedKeys == true
        preferences = initialPreferences ?? (startServices ? Preferences.load(from: self.runtime.preferencesDefaults) : Preferences())
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
        if !preferencesRecoveryRequired {
            do { try hotkeys.register(preferences.hotkeys) } catch { self.error = error.localizedDescription }
        }
        registeredHotkeys = hotkeys.registeredBindings
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
        guard !preferencesRecoveryRequired else {
            startupState = .failed
            startupError = L("저장된 설정 일부를 읽지 못했습니다. 기존 설정과 기록을 보존했습니다. 이전 설정을 복구하거나 복구된 설정을 확인한 뒤 사용해 주세요.", "Some saved settings could not be read. Your settings and records are preserved. Restore previous settings or confirm recovered settings before using the app.")
            return
        }
        do {
            let opened = if let store { store } else { try await runtime.openStore() }
            try Task.checkCancellation()
            guard !preferencesRecoveryRequired else { return }
            // Settings may have been saved immediately before an earlier app exit, leaving
            // the vault's policy stale. Apply the selected policy before keys, profiles or
            // any ordinary store transaction can prune under the previous value.
            _ = try await opened.snapshot(retentionDays: preferences.retentionDays)
            try Task.checkCancellation()
            guard !preferencesRecoveryRequired else { return }
            if store == nil {
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
            guard !preferencesRecoveryRequired else { return }
            startupState = .ready
            // The manager stays usable while a separate Jev Keychain prompt waits.
            // Required repair readiness is checked separately before any recording starts.
            if preferences.decisionProvider == .typeSafe { loadDecisionKey() }
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
        if provider == preferences.effectiveTextProvider || (provider == .openRouter && preferences.decisionProvider == .openRouter) { stopDecisionReview() }
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
                if provider == preferences.effectiveTextProvider || (provider == .openRouter && preferences.decisionProvider == .openRouter) { stopDecisionReview() }
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
        guard storageChangesPermitted() else { return }
        var replacements = preferences.hotkeys
        guard replacements.indices.contains(index) else { return }
        replacements[index] = binding
        if !startsSystemServices { preferences.hotkeys = replacements; return }
        defer { registeredHotkeys = hotkeys.registeredBindings }
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
        guard !preferencesRecoveryRequired else {
            throw AppError.message(L("설정 복구를 선택한 뒤 AI 처리를 시작해 주세요.", "Choose how to recover settings before starting AI processing."))
        }
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
        guard !preferencesRecoveryRequired else { _ = storageChangesPermitted(); showManager?(); return }
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
        if let issue = requiredJevIssue, mode == .dictation {
            error = issue.message; page = .settings; settingsSection = .connection; showManager?(); return
        }
        if mode == .prompt, let issue = promptCompositionIssue {
            if preferences.decisionProvider == .typeSafe { loadDecisionKey() }
            error = issue; page = .settings; settingsSection = .connection; showManager?(); return
        }
        let frontBefore = runtime.frontmostApplication()
        if mode != .prompt, frontBefore?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Recording here could only end in a result to copy by hand; say so instead of recording.
            // The window is already in front (or there is none), so showing it steals nothing.
            notice = L("OpenNoType 창에는 입력할 수 없습니다. 글을 입력할 앱의 입력창을 클릭한 뒤 단축키를 다시 눌러 주세요.", "OpenNoType cannot type into its own window. Click a text field in another app, then press the shortcut again.")
            showManager?()
            return
        }
        let job = UUID(); generation = job
        promptCompositionJob = mode == .prompt ? job : nil
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
            let startRefinementEpoch = translationRefinementEpoch
            translationProtectionJob = TranslationProtectionPolicy.requiresReview(
                mode: mode == .dictation && startPreferences.dictationOutputLanguage.isTranslation ? .translation : mode,
                enabled: startPreferences.translationProtectionEnabled, reviewMode: startPreferences.decisionReviewMode) ? job : nil
            let startDecisionReviewEpoch = decisionReviewEpoch
            let transcriptionConfig = try configuration(provider: startPreferences.provider, preferences: startPreferences,
                                                        requiresKey: !startPreferences.needsLocal)
            let textConfig = try configuration(provider: startPreferences.effectiveTextProvider, preferences: startPreferences)
            let reviewConfig = decisionConfiguration(preferences: startPreferences, textConfiguration: textConfig)
            if mode != .prompt {
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
            }
            if target?.secureField == true {
                throw AppError.message(L("비밀번호 입력란에는 글을 입력하지 않습니다. 다른 입력창을 클릭한 뒤 다시 시도해 주세요.", "OpenNoType does not type into password fields. Click another text field, then try again."))
            }
            if mode == .rewrite, target?.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw AppError.message(L("수정할 문장을 선택한 뒤 단축키로 시작해 주세요. 손쉬운 사용 권한도 필요합니다.", "Select the text to edit, then press the shortcut. Accessibility permission is also required."))
            }
            snapshot = .init(transcriptionConfiguration: transcriptionConfig, textConfiguration: textConfig,
                needsLocal: startPreferences.needsLocal, speakerFilter: startPreferences.speakerFilterEnabled,
                targetLanguage: mode == .dictation
                    ? startPreferences.dictationOutputLanguage.targetLanguage ?? startPreferences.targetLanguage
                    : startPreferences.targetLanguage,
                outputLanguage: mode == .dictation ? startPreferences.dictationOutputLanguage : .original,
                dictionary: startDictionary,
                writingProfile: mode == .prompt ? .init() : startPreferences.writingProfile(for: target?.bundleID),
                decisionReviewMode: startPreferences.decisionReviewMode,
                translationProtectionEnabled: startPreferences.translationProtectionEnabled,
                decisionReviewEpoch: startDecisionReviewEpoch,
                decisionConfiguration: reviewConfig, assistancePreferences: startPreferences,
                translationRefinementEpoch: startRefinementEpoch)
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
            if mode != .prompt { noteForeignActivation(since: frontBefore) }
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
                self.elapsed = self.runtime.recordingElapsed?() ?? self.recorder.elapsed
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
        // The display timer can lag behind the final recording duration by a polling interval.
        elapsed = runtime.recordingElapsed?() ?? recorder.elapsed
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
                    usedSpeakerFilter: capturedSnapshot.speakerFilter, writingProfile: capturedSnapshot.writingProfile,
                    outputLanguage: capturedMode == .dictation ? capturedSnapshot.outputLanguage : nil)
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
        phase = .idle; level = 0; onPhaseChange?(); notice = L("취소했습니다.", "Cancelled.")
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
        // Keep the user's shortcut mode in recovery/history while routing translation through
        // the existing translation contract, never through same-language repair or learning.
        let processingMode: InputMode = mode == .dictation && snapshot.outputLanguage.isTranslation ? .translation : mode
        let protectsTranslation = TranslationProtectionPolicy.requiresReview(mode: processingMode,
            enabled: snapshot.translationProtectionEnabled, reviewMode: snapshot.decisionReviewMode)
        var filteredURL: URL?
        var timings = ProcessingTimings(job: job, startedAt: stoppedAt)
        let usageEpoch = usageResetGeneration
        let historyEpoch = historyWriteEpoch
        let tracksUsage = preferences.usageTrackingEnabled
        var pipelineOutcome: JevMetricOutcome = .failed
        defer {
            if tracksUsage, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                jevQualityMetrics.recordPipeline(provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, duration: ProcessInfo.processInfo.systemUptime - stoppedAt,
                    outcome: Task.isCancelled || generation != job ? .cancelled : pipelineOutcome)
            }
        }
        let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
            guard tracksUsage else { return }
            await self?.recordUsage(event, job: job, mode: processingMode, isRecovery: failure != nil, epoch: usageEpoch)
        }
        defer { if let filteredURL { try? FileManager.default.removeItem(at: filteredURL) }; try? FileManager.default.removeItem(at: url) }
        do {
            if processingMode == .prompt {
                guard snapshot.decisionReviewEpoch == decisionReviewEpoch,
                      let reviewConfig = snapshot.decisionConfiguration, !reviewConfig.apiKey.isEmpty else {
                    throw AppError.message(L("프롬프트 만들기에 필요한 Jev 연결을 준비한 뒤 다시 처리해 주세요.", "Prepare the Jev connection required for prompt creation, then reprocess the recording."))
                }
            }
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
            guard job == generation else { return }
            if processingMode == .dictation, snapshot.decisionReviewMode == .repair,
               let configuration = snapshot.decisionConfiguration {
                // Even an empty result cannot fit when the source alone exceeds the wire
                // budget. Preserve the transcribed source and recovery audio, without paying
                // for text generation which cannot possibly be reviewed.
                do {
                    try DecisionClient.validateReviewInput(.init(transcript: transcript, cleanedText: "",
                        termCandidates: Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary),
                        detailAxes: snapshot.assistancePreferences.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
                        expression: snapshot.writingProfile.expression), provider: configuration.provider)
                } catch {
                    result = transcript; decisionOriginalText = transcript
                    decisionReviewFailure = JevReviewFailure(error)
                    decisionReviewSummary = L("문장 정리 전에 검토 가능 길이를 확인했습니다. ", "Checked review capacity before text processing. ") + JevReviewFailure(error).message
                    pipelineOutcome = .held
                    throw AppError.message(decisionReviewSummary!)
                }
            }
            if mode == .rewrite, snapshot.assistancePreferences.jevClarifyEditsEnabled,
               snapshot.decisionReviewEpoch == decisionReviewEpoch, preferences.jevClarifyEditsEnabled {
                let source = selectedTextOverride ?? target?.selectedText ?? ""
                var assessment: DecisionEditAssessment?
                var assessmentFailure: JevReviewFailure?
                if let reviewConfig = snapshot.decisionConfiguration, !reviewConfig.apiKey.isEmpty {
                    do {
                        assessment = try await decisionClient.assessEditAmbiguity(originalText: source,
                            instruction: transcript, configuration: reviewConfig, onUsage: collectUsage)
                    } catch { assessmentFailure = JevReviewFailure(error) }
                }
                try Task.checkCancellation(); guard job == generation else { return }
                if snapshot.decisionReviewEpoch == decisionReviewEpoch,
                   !JevAssistancePolicy.editIsClear(assessment) {
                    jevEditClarification = .init(id: UUID(), original: source, instruction: transcript,
                        assessment: assessment, status: assessment == nil
                            ? (L("수정 지시를 검토하지 못해 자동 입력을 보류했습니다. ", "Editing review was unavailable, so typing was held. ")
                                + (assessmentFailure?.message ?? L("선택한 Jev 연결 키를 준비해 주세요.", "Prepare the key for the selected Jev connection.")))
                            : L("지시를 구체적으로 확인한 뒤 수정안을 만들 수 있습니다.", "Clarify the instruction before creating an edit preview."))
                    captureJevAssistance(snapshot)
                    pipelineOutcome = .held
                    phase = .idle; level = 0; page = .home; onPhaseChange?(); showManager?()
                    return
                }
            }
            var lessons: [JevRepairIssue]
            let lessonEpoch = decisionReviewEpoch
            if processingMode == .dictation, snapshot.assistancePreferences.jevFeedbackLearningEnabled,
               preferences.jevFeedbackLearningEnabled, preferences.historyEnabled, let store {
                lessons = (try? await store.jevRepairLessons(provider: snapshot.textConfiguration.provider,
                                                          model: snapshot.textConfiguration.textModel)) ?? []
            } else { lessons = [] }
            try Task.checkCancellation(); guard job == generation else { return }
            if lessonEpoch != decisionReviewEpoch || !preferences.jevFeedbackLearningEnabled || !preferences.historyEnabled {
                lessons = []
            }
            let request = ProcessingRequest(mode: mode, transcript: transcript, selectedText: selectedTextOverride ?? target?.selectedText,
                context: target?.context, dictionary: snapshot.dictionary, targetLanguage: snapshot.targetLanguage,
                outputLanguage: snapshot.outputLanguage, writingProfile: snapshot.writingProfile, reviewLessons: lessons)
            if processingMode == .prompt {
                pipelineOutcome = .held
                let output = try await composePrompt(request: request, configuration: snapshot.textConfiguration,
                    decisionConfiguration: snapshot.decisionConfiguration, epoch: snapshot.decisionReviewEpoch,
                    job: job, onUsage: collectUsage)
                try Task.checkCancellation(); guard generation == job else { return }
                if preferences.historyEnabled, historyEpoch == historyWriteEpoch, let store {
                    _ = try await store.appendHistory(.init(mode: .prompt, originalText: transcript, resultText: output,
                        provider: snapshot.textConfiguration.provider))
                    try Task.checkCancellation(); guard generation == job else { return }
                }
                if let failure { try await store?.deleteFailure(id: failure.id) }
                try Task.checkCancellation(); guard generation == job else { return }
                pipelineOutcome = .completed
                timings.mark(.textProcessing)
                await refreshData()
                guard generation == job, !Task.isCancelled else { return }
                lastProcessingTimings = timings.summary
                phase = .idle; level = 0; page = .home; onPhaseChange?(); showManager?()
                return
            }
            processingStage = .textProcessing
            let generationStarted = ProcessInfo.processInfo.systemUptime
            var output: String
            do { output = try await client.process(request, configuration: snapshot.textConfiguration, onUsage: collectUsage) }
            catch {
                if tracksUsage, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                    jevQualityMetrics.recordGeneration(provider: snapshot.textConfiguration.provider,
                        model: snapshot.textConfiguration.textModel, duration: ProcessInfo.processInfo.systemUptime - generationStarted,
                        outcome: Task.isCancelled || error is CancellationError ? .cancelled : .failed)
                }
                throw error
            }
            if tracksUsage, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                jevQualityMetrics.recordGeneration(provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, duration: ProcessInfo.processInfo.systemUptime - generationStarted)
            }
            timings.mark(.textProcessing)
            try Task.checkCancellation(); guard job == generation else { return }
            if request.requiresTranslation, snapshot.assistancePreferences.translationRefinementEnabled,
               snapshot.translationRefinementEpoch != translationRefinementEpoch {
                throw translationRefinementRevocationError
            }
            result = output
            let purpose: DecisionReviewPurpose
            switch processingMode {
            case .prompt: purpose = .promptComposition
            case .dictation: purpose = .dictation
            case .translation: purpose = .translation(targetLanguage: request.effectiveTargetLanguage)
            case .rewrite: purpose = .rewrite(originalText: request.selectedText ?? "")
            }
            recentDecisionTarget = .init(id: job, kind: .recent, transcript: transcript, output: output,
                purpose: purpose, textProvider: snapshot.textConfiguration.provider,
                textModel: snapshot.textConfiguration.textModel, writingProfile: snapshot.writingProfile)
            if request.requiresTranslation, snapshot.assistancePreferences.translationRefinementEnabled {
                processingStage = .translationRefinement
                output = try await refineTranslation(request: request, draft: output,
                    configuration: snapshot.textConfiguration, epoch: snapshot.translationRefinementEpoch,
                    job: job, onUsage: collectUsage)
                timings.mark(.translationRefinement)
                try Task.checkCancellation(); guard job == generation else { return }
                result = output
                recentDecisionTarget = .init(id: job, kind: .recent, transcript: transcript, output: output,
                    purpose: purpose, textProvider: snapshot.textConfiguration.provider,
                    textModel: snapshot.textConfiguration.textModel, writingProfile: snapshot.writingProfile)
            }
            let shouldReview = processingMode == .dictation
                && snapshot.decisionReviewMode != .off && snapshot.decisionReviewEpoch == decisionReviewEpoch
                && preferences.decisionReviewMode != .off
            var heldForReview = protectsTranslation
            if protectsTranslation, let reviewTarget = recentDecisionTarget {
                processingStage = .decisionReview
                heldForReview = await reviewTranslationBeforeInsertion(target: reviewTarget,
                    configuration: snapshot.decisionConfiguration, selected: snapshot.assistancePreferences,
                    epoch: snapshot.decisionReviewEpoch, job: job, provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, onUsage: collectUsage)
                timings.mark(.decisionReview)
                try Task.checkCancellation(); guard job == generation else { return }
            }
            if shouldReview, snapshot.decisionReviewMode == .protect || snapshot.decisionReviewMode == .repair
                || snapshot.assistancePreferences.jevReRecognitionEnabled {
                processingStage = .decisionReview
                heldForReview = await reviewDecision(transcript: transcript, output: output, snapshot: snapshot,
                    job: job, onUsage: collectUsage)
                timings.mark(.decisionReview)
                try Task.checkCancellation(); guard job == generation else { return }
            }
            if processingMode == .dictation, snapshot.decisionReviewMode == .repair {
                // A revoked, failed or skipped check can never authorize unreviewed automatic typing.
                heldForReview = true
                if shouldReview, let review = lastAutomaticReview,
                   JevRepairPolicy.reviewIsValid(review), snapshot.decisionReviewEpoch == decisionReviewEpoch {
                    let terms = Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary)
                    if !JevRepairPolicy.reviewMatchesCandidates(review, terms: terms) {
                        jevLearningSummary = L("표기 검토 응답을 확인하지 못해 자동 입력을 보류했습니다.", "The spelling review could not be verified, so automatic typing was held.")
                    } else if JevRepairPolicy.needsRepair(review: review, transcript: transcript, output: output, terms: terms, expression: snapshot.writingProfile.expression) {
                        if let repaired = await runAutomaticRepair(request: request, originalOutput: output,
                            initialReview: review, terms: terms, snapshot: snapshot, job: job, onUsage: collectUsage) {
                            output = repaired; result = repaired
                            recentDecisionTarget = .init(id: job, kind: .recent, transcript: transcript, output: repaired,
                                purpose: purpose, textProvider: snapshot.textConfiguration.provider,
                                textModel: snapshot.textConfiguration.textModel, writingProfile: snapshot.writingProfile)
                            heldForReview = false
                        }
                    } else { heldForReview = false }
                } else {
                    jevLearningSummary = L("입력 전 검토를 완료하지 못해 자동 입력을 보류했습니다.",
                                           "Automatic typing was held because the pre-typing review was unavailable.")
                }
                timings.mark(.decisionReview)
                try Task.checkCancellation(); guard job == generation else { return }
                if snapshot.decisionReviewEpoch != decisionReviewEpoch { heldForReview = true }
            }
            var heldForReRecognition = false
            let nameTerms = Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary)
                + JevNameCatalog.candidates(in: transcript, canonicalNames: snapshot.assistancePreferences.jevNameCatalog, limit: 4)
            let suspect = JevAssistancePolicy.needsNameRecheck(output: output, terms: nameTerms)
                || decisionRiskSignals.contains { $0.score >= 0.9 }
            if processingMode == .dictation, snapshot.assistancePreferences.jevReRecognitionEnabled,
               preferences.jevReRecognitionEnabled, !snapshot.needsLocal, suspect,
               snapshot.decisionReviewEpoch == decisionReviewEpoch,
               let alternate = JevAssistancePolicy.alternativeTranscriptionConfiguration(config),
               let reviewConfig = snapshot.decisionConfiguration, !reviewConfig.apiKey.isEmpty {
                processingStage = .transcription
                let id = UUID()
                jevReRecognition = .init(id: id, original: transcript)
                captureJevAssistance(snapshot)
                do {
                    let provider = client, seconds = Self.audioDuration(at: audioURL), currentURL = audioURL
                    let dictionary = snapshot.dictionary, profile = snapshot.writingProfile
                    let alternative = try await jevWithDeadline(seconds: 20) {
                        try await provider.transcribe(audioURL: currentURL, configuration: alternate,
                            dictionary: dictionary, writingProfile: profile, audioSeconds: seconds,
                            allowRetry: false, onUsage: collectUsage)
                    }
                    try Task.checkCancellation(); guard job == generation else { return }
                    guard snapshot.decisionReviewEpoch == decisionReviewEpoch, jevReRecognition?.id == id else {
                        phase = .idle; level = 0; onPhaseChange?(); return
                    }
                    jevReRecognition?.alternative = alternative
                    let assessment = try await decisionClient.compareTranscriptions(original: transcript,
                        alternative: alternative, configuration: reviewConfig, onUsage: collectUsage)
                    try Task.checkCancellation(); guard job == generation else { return }
                    guard snapshot.decisionReviewEpoch == decisionReviewEpoch, jevReRecognition?.id == id else {
                        phase = .idle; level = 0; onPhaseChange?(); return
                    }
                    jevReRecognition?.assessment = assessment
                    heldForReRecognition = !JevAssistancePolicy.transcriptsEquivalent(assessment)
                    jevReRecognition?.status = heldForReRecognition
                        ? L("두 인식문이 다르거나 불확실해 자동 입력을 보류했습니다. 실제로 말한 내용을 확인해 주세요.", "The transcripts differ or are uncertain, so typing was held. Compare them with what you said.")
                        : L("두 인식문에서 뚜렷한 뜻 차이를 찾지 못했습니다. 처음 정리 결과를 유지했습니다.", "No clear meaning difference was found. The original cleanup result was kept.")
                } catch {
                    guard !Task.isCancelled, job == generation else { return }
                    guard snapshot.decisionReviewEpoch == decisionReviewEpoch, jevReRecognition?.id == id else {
                        phase = .idle; level = 0; onPhaseChange?(); return
                    }
                    heldForReRecognition = true
                    jevReRecognition?.status = L("재인식 또는 비교를 완료하지 못해 자동 입력을 보류했습니다. 최근 결과를 직접 확인해 주세요.", "Retranscription or comparison was unavailable, so typing was held. Review the latest result yourself.")
                }
                jevReRecognition?.isProcessing = false
                heldForReview = heldForReview || heldForReRecognition
            }
            if protectsTranslation, snapshot.decisionReviewEpoch != decisionReviewEpoch
                || !preferences.translationProtectionEnabled || preferences.decisionReviewMode != .protect {
                heldForReview = true
            }
            processingStage = .insertion
            var submittedTarget = target
            let observedTarget = target?.observingSubmission { submittedTarget = $0 }
            let outcome = if !heldForReview, let observedTarget {
                await runtime.insertText(output, observedTarget, mode == .rewrite,
                                         { self.generation != job || Task.isCancelled
                                             || (request.requiresTranslation && snapshot.assistancePreferences.translationRefinementEnabled
                                                 && snapshot.translationRefinementEpoch != self.translationRefinementEpoch)
                                             || (protectsTranslation && (snapshot.decisionReviewEpoch != self.decisionReviewEpoch
                                                 || !self.preferences.translationProtectionEnabled
                                                 || self.preferences.decisionReviewMode != .protect)) })
            } else { InsertionOutcome.notSubmitted(.noTarget) }
            pipelineOutcome = heldForReview || heldForReRecognition ? .held : .completed
            timings.mark(.insertion)
            guard generation == job, !Task.isCancelled else {
                reportCancelledInsertion(outcome, job: job)
                return
            }
            if outcome.isConfirmed, processingMode == .dictation, preferences.automaticLearningEnabled, let submittedTarget {
                watchCorrection(output, target: submittedTarget)
            }
            processingStage = .storage
            if preferences.historyEnabled, historyEpoch == historyWriteEpoch {
                do {
                    guard let store else { throw AppError.message(L("암호화 저장소를 사용할 수 없습니다.", "Encrypted storage is unavailable.")) }
                    _ = try await store.appendHistory(.init(mode: mode, originalText: transcript, resultText: output,
                        sourceBundleID: target?.bundleID, provider: snapshot.textConfiguration.provider,
                        writingProfile: snapshot.writingProfile,
                        outputLanguage: mode == .dictation ? snapshot.outputLanguage : nil,
                        targetLanguage: request.requiresTranslation ? request.effectiveTargetLanguage : nil))
                    guard generation == job, !Task.isCancelled else { return }
                } catch {
                    guard generation == job, !Task.isCancelled else { return }
                    self.error = L("입력은 처리했지만 기록 저장에 실패했습니다: \(error.localizedDescription)", "Typing was handled, but history could not be saved: \(error.localizedDescription)")
                }
            }
            if let failure { try await store?.deleteFailure(id: failure.id) }
            guard generation == job, !Task.isCancelled else { return }
            if heldForReRecognition {
                notice = L("다시 인식한 내용과 처음 내용을 비교한 뒤 사용할 결과를 복사해 주세요.", "Compare both transcripts, then copy the result you want.")
                page = .home; showManager?()
            } else if heldForReview {
                notice = protectsTranslation
                    ? L("번역 검토에서 입력 조건을 확인하지 못해 자동 입력을 보류했습니다. 원문과 번역문을 비교한 뒤 복사해 주세요.", "Automatic typing was held because the translation review did not meet the typing checks. Compare the source and translation before copying.")
                    : snapshot.decisionReviewMode == .repair
                    ? L("검토·교정에서 입력 조건을 충족하지 못해 자동 입력을 보류했습니다. 원문과 결과를 확인해 주세요.", "Review and repair did not meet the typing checks. Compare the source and result.")
                    : L("문장 정리에서 의미가 달라졌을 가능성이 있어 자동 입력을 보류했습니다. 원문과 결과를 확인한 뒤 복사해 주세요.", "Automatic typing was held because cleanup may have changed the meaning. Compare the transcript and result before copying.")
                if snapshot.decisionReviewMode == .repair { decisionOriginalText = transcript }
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
                    guard let self else { return }
                    if !snapshot.assistancePreferences.jevReRecognitionEnabled {
                        _ = await self.reviewDecision(transcript: transcript, output: output, snapshot: snapshot,
                                                     job: job, onUsage: collectUsage)
                    }
                    guard !Task.isCancelled, generation == job, snapshot.decisionReviewEpoch == decisionReviewEpoch,
                          let review = lastAutomaticReview, JevRepairPolicy.reviewIsValid(review) else { return }
                    let terms = Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary)
                    if JevRepairPolicy.needsRepair(review: review, transcript: transcript, output: output, terms: terms, expression: snapshot.writingProfile.expression) {
                        _ = await runAutomaticRepair(request: request, originalOutput: output, initialReview: review,
                            terms: terms, snapshot: snapshot, job: job, onUsage: collectUsage)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, job == generation else { return }
            if processingMode == .translation, processingStage == .textProcessing,
               let providerError = error as? ProviderError,
               case .emptyOutput = providerError {
                self.error = L("번역 결과가 비어 있어 입력하지 않았습니다. 복구 녹음에서 다시 처리해 주세요.", "The translation was empty, so nothing was typed. Reprocess the saved recording to try again.")
            } else { self.error = error.localizedDescription }
            let refinementRevoked = processingMode == .translation && snapshot.assistancePreferences.translationRefinementEnabled
                && snapshot.translationRefinementEpoch != translationRefinementEpoch
            if refinementRevoked { pipelineOutcome = .held }
            if failure == nil, !refinementRevoked, let store {
                do {
                    let item = FailedRecording(mode: mode, provider: snapshot.transcriptionConfiguration.provider,
                        textProvider: snapshot.textConfiguration.provider, targetLanguage: snapshot.targetLanguage,
                        transcriptionModel: snapshot.transcriptionConfiguration.transcriptionModel,
                        textModel: snapshot.textConfiguration.textModel, usedLocalTranscription: snapshot.needsLocal,
                        usedSpeakerFilter: snapshot.speakerFilter, writingProfile: snapshot.writingProfile,
                        outputLanguage: mode == .dictation ? snapshot.outputLanguage : nil)
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
        startAutomaticJevImprovementIfReady()
    }

    /// Revocation stops a paid follow-up or a late insertion. A new operation captures a fresh epoch.
    private var translationRefinementRevocationError: AppError {
        .message(L("설정이 바뀌어 번역 처리와 입력을 중단했습니다. 새 작업에서 다시 시도해 주세요.", "Translation processing and typing stopped because settings changed. Try again in a new operation."))
    }

    private func revokeTranslationRefinement(clearPresentation: Bool = true) {
        translationRefinementEpoch = UUID()
        if clearPresentation || phase == .processing {
            if translationRefinement?.isProcessing == true || translationRefinement?.held == true { result = "" }
            if historyReprocessing?.translationRefinement?.isProcessing == true
                || historyReprocessing?.translationRefinement?.held == true { historyReprocessing?.result = nil }
            translationRefinement = nil
            historyReprocessing?.translationRefinement = nil
        }
        if phase == .processing, translationRefinementJob == generation {
            processingTask?.cancel()
            generation = UUID()
            historyReprocessing?.isProcessing = false
            historyReprocessing?.error = L("설정이 바뀌어 번역 처리를 중단했습니다.", "Translation processing stopped because settings changed.")
            phase = .idle; level = 0; onPhaseChange?()
            notice = L("번역 다듬기 설정 또는 보관 설정이 바뀌어 추가 처리와 입력을 중단했습니다.", "Refinement or retention settings changed, so the additional processing and typing were stopped.")
        }
    }

    private func refineTranslation(request: ProcessingRequest, draft: String, configuration: ProviderConfiguration,
                                   epoch: UUID, job: UUID, historyPreview: Bool = false,
                                   onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async throws -> String {
        try Task.checkCancellation()
        guard generation == job else { throw CancellationError() }
        guard epoch == translationRefinementEpoch, preferences.translationRefinementEnabled else {
            if historyPreview { historyReprocessing?.result = nil }
            else { result = ""; recentDecisionTarget = nil }
            throw translationRefinementRevocationError
        }
        translationRefinementJob = job
        func publish(_ presentation: TranslationRefinementPresentation) {
            if historyPreview { historyReprocessing?.translationRefinement = presentation }
            else { translationRefinement = presentation }
        }
        var presentation = TranslationRefinementPresentation(draft: draft,
            status: L("원문과 초안을 비교하며 번역을 다듬고 있습니다.", "Refining the translation against the source and draft."),
            isProcessing: true, held: false)
        publish(presentation)
        let provider = client
        let outcome = try await TranslationRefinementRunner.run(request: request, draft: draft) { refinement in
            try await provider.process(refinement, configuration: configuration, allowRetry: false, onUsage: onUsage)
        }
        try Task.checkCancellation()
        guard generation == job, epoch == translationRefinementEpoch else { throw CancellationError() }
        presentation.isProcessing = false
        switch outcome {
        case .unchanged(let output), .refined(let output):
            presentation.output = output
            presentation.status = output == draft
                ? L("다듬기 응답이 초안과 같습니다. 원문과 결과를 확인해 주세요.", "Refinement returned the same draft. Check it against the source.")
                : L("번역 다듬기 응답을 받았습니다. 원문과 결과를 확인해 주세요.", "A refined translation was received. Check it against the source.")
            publish(presentation)
            return output
        case .held(let failure):
            presentation.held = true
            presentation.status = failure.localizedDescription
            publish(presentation)
            throw failure
        }
    }

    /// An explicit text-only retry. Stored history and failed audio remain the original evidence.
    func regeneratePrompt(sourceID: UUID, sourceTranscript: String, correctedTranscript: String) {
        guard storageChangesPermitted(), startupState == .ready else { return }
        guard !isBusy else {
            notice = L("현재 처리가 끝난 뒤 다시 시도해 주세요.", "Wait for the current operation to finish, then try again.")
            return
        }
        guard let source = promptComposition, !source.isProcessing,
              source.id == sourceID, source.transcript == sourceTranscript else {
            notice = L("프롬프트 원문이 바뀌었습니다. 현재 화면의 원문을 확인한 뒤 다시 시도해 주세요.", "The prompt source has changed. Check the source currently shown, then try again.")
            return
        }
        if let failure = PromptCompositionPresentation.sourceValidationFailure(correctedTranscript) {
            error = failure.localizedDescription
            return
        }
        if let issue = promptCompositionIssue { error = issue; return }
        let selected = preferences
        let configuration: ProviderConfiguration
        do { configuration = try self.configuration(provider: selected.effectiveTextProvider, preferences: selected) }
        catch { self.error = error.localizedDescription; return }
        let reviewConfiguration = decisionConfiguration(preferences: selected, textConfiguration: configuration)
        guard let reviewConfiguration, !reviewConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = L("프롬프트 만들기에 필요한 Jev 연결 키를 준비해 주세요.", "Prepare the Jev connection key required to create prompts.")
            return
        }
        let request = ProcessingRequest(mode: .prompt, transcript: correctedTranscript, dictionary: dictionary)
        let originalTranscript = source.recognizedTranscript
        let job = UUID(), usageEpoch = usageResetGeneration
        let tracksUsage = selected.usageTrackingEnabled
        generation = job
        promptCompositionJob = job
        let epoch = decisionReviewEpoch
        mode = .prompt
        target = nil; snapshot = nil
        phase = .processing; processingStage = .textProcessing; error = nil; notice = nil
        learningTask?.cancel(); onPhaseChange?()
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == job {
                    phase = .idle; level = 0; onPhaseChange?()
                }
            }
            guard !Task.isCancelled, generation == job, decisionReviewEpoch == epoch else { return }
            let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                guard tracksUsage else { return }
                await self?.recordUsage(event, job: job, mode: .prompt, isRecovery: false, epoch: usageEpoch)
            }
            do {
                _ = try await composePrompt(request: request, configuration: configuration,
                    decisionConfiguration: reviewConfiguration, epoch: epoch, job: job,
                    originalTranscript: originalTranscript, onUsage: collectUsage)
                try Task.checkCancellation()
                guard generation == job, decisionReviewEpoch == epoch else { return }
                page = .home
            } catch {
                guard !Task.isCancelled, generation == job, decisionReviewEpoch == epoch else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func composePrompt(request: ProcessingRequest, configuration: ProviderConfiguration,
                               decisionConfiguration: DecisionConfiguration?, epoch: UUID, job: UUID,
                               originalTranscript: String? = nil,
                               onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async throws -> String {
        guard let decisionConfiguration, !decisionConfiguration.apiKey.isEmpty else {
            throw AppError.message(L("프롬프트 만들기에 필요한 Jev 연결 키를 준비해 주세요.", "Prepare the Jev connection key required to create prompts."))
        }
        guard generation == job, decisionReviewEpoch == epoch else { throw CancellationError() }
        promptComposition = .init(transcript: request.transcript, originalTranscript: originalTranscript,
            status: L("말한 내용을 짧은 작업 프롬프트로 정리하고 있습니다.", "Organizing your speech into a concise task prompt."))
        result = ""
        let provider = client, reviewer = decisionClient
        do {
            let outcome = try await PromptCompositionRunner.run(request: request, process: { request in
                try await jevWithDeadline(seconds: 30) {
                    try await provider.process(request, configuration: configuration, allowRetry: false, onUsage: onUsage)
                }
            }, review: { input in
                try await reviewer.reviewPromptComposition(input, configuration: decisionConfiguration, onUsage: onUsage)
            }, onProgress: { [weak self] stage, draft in
                guard let self else { throw CancellationError() }
                try await self.publishPromptProgress(stage, draft: draft, epoch: epoch, job: job)
            }, onReview: { [weak self] stage, input, review in
                guard let self else { throw CancellationError() }
                try await self.publishPromptReview(stage, input: input, review: review, epoch: epoch, job: job)
            })
            try Task.checkCancellation()
            guard generation == job, decisionReviewEpoch == epoch else { throw CancellationError() }
            promptComposition?.draft = outcome.draft
            promptComposition?.output = outcome.text
            promptComposition?.isProcessing = false
            promptComposition?.status = L("프롬프트가 준비되었습니다. 내용을 확인한 뒤 원하는 AI에 붙여넣으세요. Jev 판정이 정확성을 보장하지는 않습니다.", "Your prompt is ready. Review it and paste it into your chosen AI. Jev's verdict does not guarantee correctness.")
            return outcome.text
        } catch {
            guard generation == job, decisionReviewEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
            promptComposition?.stop(with: error)
            page = .home
            throw error
        }
    }

    private func publishPromptProgress(_ stage: PromptCompositionStage, draft: String?, epoch: UUID, job: UUID) throws {
        try Task.checkCancellation()
        guard generation == job, decisionReviewEpoch == epoch else { throw CancellationError() }
        promptComposition?.stage = .init(stage)
        if case .reviewingFinal = stage { promptComposition?.finalCandidate = draft }
        else { promptComposition?.draft = draft }
        switch stage {
        case .drafting:
            processingStage = .textProcessing
        case .reviewingDraft:
            processingStage = .decisionReview
            promptComposition?.status = L("Jev가 초안의 의도·추가·누락·기존 지침 존중 여부를 확인하고 있습니다.", "Jev is checking the draft's intent, additions, omissions and respect for existing instructions.")
        case .polishing:
            processingStage = .textProcessing
            promptComposition?.status = L("원문과 검토 항목을 기준으로 한 번 다듬고 있습니다.", "Polishing once against your source and the review signals.")
        case .reviewingFinal:
            processingStage = .decisionReview
            promptComposition?.status = L("선택된 최종 후보를 Jev로 다시 확인하고 있습니다.", "Jev is rechecking the selected final candidate.")
        }
        onPhaseChange?()
    }

    private func publishPromptReview(_ stage: PromptCompositionStage, input: PromptCompositionReviewRequest,
                                     review: PromptCompositionReviewResult, epoch: UUID, job: UUID) throws {
        try Task.checkCancellation()
        guard generation == job, decisionReviewEpoch == epoch else { throw CancellationError() }
        guard input.transcript == promptComposition?.transcript else { throw CancellationError() }
        switch stage {
        case .reviewingDraft:
            guard input.prompt == promptComposition?.draft else { throw CancellationError() }
            promptComposition?.draftReview = review
        case .reviewingFinal:
            guard input.prompt == promptComposition?.finalCandidate else { throw CancellationError() }
            promptComposition?.finalReview = review
        case .drafting, .polishing:
            return
        }
        onPhaseChange?()
    }

    private func stopDecisionReview() {
        if promptComposition?.isProcessing == true {
            promptComposition = nil
            processingTask?.cancel()
            historyReprocessing?.isProcessing = false
            phase = .idle; level = 0; onPhaseChange?()
        }
        if phase == .processing, jevReRecognition?.isProcessing == true {
            // Initial retranscription runs in the main audio job; revocation must cancel it too.
            processingTask?.cancel(); target = nil; snapshot = nil
            phase = .idle; level = 0; onPhaseChange?()
        }
        decisionReviewEpoch = UUID()
        translationProtectionReviewEpoch = nil
        jevRepairTask?.cancel(); jevRepairTask = nil; jevRepairInProgress = false
        jevLessonWriteTask?.cancel(); jevLessonWriteTask = nil
        lastAutomaticReview = nil; jevLearningSummary = nil
        decisionReviewFailure = nil
        jevAssistanceOperation = UUID(); jevModelComparisonPreparing = false
        jevAssistanceTask?.cancel(); jevAssistanceTask = nil
        jevEditClarification = nil; jevReRecognition = nil
        jevAssistancePreferences = nil; jevAssistanceDictionary = []
        jevNameDiscoveryInProgress = false; jevNameDiscoveryStatus = nil
        jevModelComparison.clearSensitiveData()
        automaticImprovementTarget = nil
        jevWorkflowTask?.cancel(); jevWorkflowTask = nil
        jevImprovement = nil; jevCorrectionReview = nil
        manualDecisionReviewTask?.cancel(); manualDecisionReviewTask = nil
        manualDecisionReviewID = nil; manualDecisionReviewInProgress = false; manualDecisionReviewStatus = nil
        decisionDictionaryTask?.cancel()
        currentDecisionReviewID = nil; decisionReviewTarget = nil
        decisionProposals = []; decisionRiskSignals = []; decisionProposalStatus = nil
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
        lastAutomaticReview = nil
        decisionReviewFailure = nil
        let epoch = snapshot.decisionReviewEpoch, qualityEpoch = usageResetGeneration
        guard !Task.isCancelled, generation == job, epoch == decisionReviewEpoch,
              preferences.decisionReviewMode != .off else { return false }
        decisionReviewTarget = recentDecisionTarget
        guard let configuration = snapshot.decisionConfiguration else {
            decisionReviewSummary = L("검토하지 않았습니다. OpenRouter 연결은 문장 정리 제공자가 OpenRouter일 때 같은 키를 사용합니다.", "Not reviewed. The OpenRouter connection reuses the key only when OpenRouter is the text cleanup provider.")
            return false
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            decisionReviewSummary = L("검토하지 않았습니다. \(configuration.provider.displayName) API 키를 준비하지 못해 기존 문장 정리 결과를 유지합니다.", "Not reviewed. The \(configuration.provider.displayName) API key was unavailable. The original cleanup result is unchanged.")
            return false
        }
        let terms = Self.decisionTermCandidates(transcript: transcript, dictionary: snapshot.dictionary)
        if snapshot.decisionReviewMode != .repair, snapshot.assistancePreferences.jevEconomyEnabled,
           JevAssistancePolicy.canSkipReview(transcript: transcript, output: output, terms: terms) {
            decisionReviewSummary = L("원문과 결과가 같고 표기 후보가 없어 절약 모드에서 검토를 생략했습니다.", "Economy mode skipped review because the source and result are identical and have no spelling candidates.")
            return false
        }
        let request = DecisionRequest(transcript: transcript, cleanedText: output, termCandidates: terms,
            detailAxes: snapshot.assistancePreferences.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
            expression: snapshot.writingProfile.expression)
        decisionReviewSummary = snapshot.decisionReviewMode == .protect ? L("입력 전에 문장 의미를 검토하고 있어요.", "Reviewing meaning before typing.") : L("문장 정리 결과를 백그라운드에서 검토하고 있어요.", "Reviewing the cleanup result in the background.")
        let client = decisionClient
        let task = Task<DecisionResult, Error> {
            try DecisionClient.validateReviewInput(request, provider: configuration.provider)
            return try await client.evaluate(request, configuration: configuration, onUsage: onUsage)
        }
        decisionReviewTask = task
        let reviewStarted = ProcessInfo.processInfo.systemUptime
        let review: DecisionResult
        do { review = try await task.value }
        catch {
            if preferences.usageTrackingEnabled, qualityEpoch == usageResetGeneration {
                jevQualityMetrics.recordReview(provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, warning: false,
                    duration: ProcessInfo.processInfo.systemUptime - reviewStarted,
                    outcome: Task.isCancelled || task.isCancelled || error is CancellationError ? .cancelled : .failed)
            }
            guard !Task.isCancelled, !task.isCancelled, generation == job, epoch == decisionReviewEpoch else { return false }
            decisionReviewTask = nil
            let failure = JevReviewFailure(error); decisionReviewFailure = failure
            decisionReviewSummary = L("검토를 완료하지 못했습니다. ", "Review could not be completed. ") + failure.message
                + L(" 기존 문장 정리 결과를 그대로 유지합니다.", " The original cleanup result is unchanged.")
            return false
        }
        guard !Task.isCancelled, !task.isCancelled, generation == job, epoch == decisionReviewEpoch else {
            if preferences.usageTrackingEnabled, qualityEpoch == usageResetGeneration {
                jevQualityMetrics.recordReview(provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, warning: false,
                    duration: ProcessInfo.processInfo.systemUptime - reviewStarted, outcome: .cancelled)
            }
            return false
        }
        decisionReviewTask = nil
        guard JevRepairPolicy.reviewIsValid(review) else {
            decisionReviewFailure = .malformed
            if preferences.usageTrackingEnabled, qualityEpoch == usageResetGeneration {
                jevQualityMetrics.recordReview(provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, warning: false,
                    duration: ProcessInfo.processInfo.systemUptime - reviewStarted, outcome: .failed)
            }
            decisionReviewSummary = L("검토 응답을 확인하지 못했습니다. 원문과 결과를 확인해 주세요.",
                                      "The review response could not be verified. Compare the source and result.")
            return false
        }
        lastAutomaticReview = review
        if preferences.usageTrackingEnabled, qualityEpoch == usageResetGeneration {
            jevQualityMetrics.recordReview(provider: snapshot.textConfiguration.provider,
                model: snapshot.textConfiguration.textModel, warning: review.maximumRiskProbability >= 0.9,
                duration: ProcessInfo.processInfo.systemUptime - reviewStarted)
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
        if let reviewTarget = recentDecisionTarget {
            publishDecisionDetails(review, terms: terms, target: reviewTarget, reviewID: epoch)
            if highRisk, snapshot.decisionReviewMode == .protect,
               snapshot.assistancePreferences.jevAutomaticImprovementEnabled, preferences.jevAutomaticImprovementEnabled {
                automaticImprovementTarget = reviewTarget
            }
        }
        return held
    }

    /// One opt-in translation check before typing. An unavailable or inconclusive review never authorizes insertion.
    private func reviewTranslationBeforeInsertion(target: JevReviewTarget, configuration: DecisionConfiguration?,
        selected: Preferences, epoch: UUID, job: UUID, provider: AIProvider, model: String,
        onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async -> Bool {
        func current() -> Bool {
            !Task.isCancelled && generation == job && decisionReviewEpoch == epoch
                && preferences.translationProtectionEnabled && preferences.decisionReviewMode == .protect
        }
        guard current(), case .translation = target.purpose else { return true }
        decisionReviewTarget = target
        decisionOriginalText = target.transcript
        decisionReviewFailure = nil
        guard let configuration, !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            decisionReviewSummary = L("번역 검토 연결을 준비하지 못해 자동 입력을 보류했습니다. 원문과 번역문을 확인해 주세요.", "Automatic typing was held because the translation review connection was unavailable. Compare the source and translation.")
            return true
        }
        let request = DecisionRequest(transcript: target.transcript, cleanedText: target.output,
            termCandidates: [], purpose: target.purpose,
            detailAxes: selected.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
            translationTone: target.writingProfile.tone)
        decisionReviewSummary = L("입력 전에 원문과 번역문을 검토하고 있어요.", "Reviewing the source and translation before typing.")
        let client = decisionClient, started = ProcessInfo.processInfo.systemUptime, usageEpoch = usageResetGeneration
        let task = Task<DecisionResult, Error> {
            try DecisionClient.validateReviewInput(request, provider: configuration.provider)
            return try await client.evaluate(request, configuration: configuration, onUsage: onUsage)
        }
        decisionReviewTask = task
        translationProtectionReviewEpoch = epoch
        defer {
            if decisionReviewEpoch == epoch { decisionReviewTask = nil }
            if translationProtectionReviewEpoch == epoch { translationProtectionReviewEpoch = nil }
        }
        do {
            let review = try await task.value
            guard current(), !task.isCancelled else { return true }
            let verdict = TranslationProtectionPolicy.verdict(for: review, detailed: selected.jevDetailedReviewEnabled)
            if selected.usageTrackingEnabled, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                jevQualityMetrics.recordReview(provider: provider, model: model,
                    warning: verdict == .meaningChanged, duration: ProcessInfo.processInfo.systemUptime - started,
                    outcome: verdict == .invalid ? .failed : .completed)
            }
            guard verdict != .invalid else {
                decisionReviewFailure = .malformed
                decisionReviewSummary = L("번역 검토 응답을 확인하지 못해 자동 입력을 보류했습니다. 원문과 번역문을 비교해 주세요.", "Automatic typing was held because the translation review response could not be verified. Compare the source and translation.")
                return true
            }
            publishDecisionDetails(review, terms: [], target: target, reviewID: epoch)
            switch verdict {
            case .accepted:
                decisionReviewSummary = L("이번 번역 검토에서 뚜렷한 의미 변경 신호를 찾지 못했습니다. 정확성을 보장하는 판정은 아닙니다.", "This translation review found no clear meaning-change signal. It does not guarantee accuracy.")
                return false
            case .meaningChanged:
                decisionReviewSummary = L("번역에서 의미 변경 신호가 있어 자동 입력을 보류했습니다. 원문과 번역문을 비교해 주세요.", "Automatic typing was held because the translation review found a meaning-change signal. Compare the source and translation.")
            case .uncertain:
                decisionReviewSummary = L("번역 검토의 판단이 불확실해 자동 입력을 보류했습니다. 원문과 번역문을 비교해 주세요.", "Automatic typing was held because the translation review was inconclusive. Compare the source and translation.")
            case .invalid: break
            }
            return true
        } catch {
            guard current() else { return true }
            let failure = JevReviewFailure(error)
            decisionReviewFailure = failure
            decisionReviewSummary = L("번역 검토를 완료하지 못해 자동 입력을 보류했습니다. ", "Automatic typing was held because the translation review could not finish. ") + failure.message
            if selected.usageTrackingEnabled, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                jevQualityMetrics.recordReview(provider: provider, model: model, warning: false,
                    duration: ProcessInfo.processInfo.systemUptime - started, outcome: .failed)
            }
            return true
        }
    }

    private func runAutomaticRepair(request: ProcessingRequest, originalOutput: String, initialReview: DecisionResult,
                                    terms: [DecisionTermCandidate], snapshot: ProcessingSnapshot, job: UUID,
                                    onUsage: @escaping @Sendable (ProviderUsage) async -> Void) async -> String? {
        let epoch = snapshot.decisionReviewEpoch
        func current() -> Bool {
            !Task.isCancelled && generation == job && decisionReviewEpoch == epoch
                && preferences.decisionReviewMode == snapshot.decisionReviewMode
        }
        guard current(), let reviewConfig = snapshot.decisionConfiguration, !reviewConfig.apiKey.isEmpty else { return nil }
        jevRepairInProgress = true
        jevLearningSummary = L("문제를 줄인 교정안을 만들고 다시 검사하고 있어요.", "Preparing a repair and checking it again.")
        if snapshot.decisionReviewMode == .repair { processingStage = .decisionReview }
        let generationClient = client, evaluator = decisionClient
        let task = Task {
            await JevRepairRunner.run(request: request, originalOutput: originalOutput, initialReview: initialReview,
                configuration: snapshot.textConfiguration, decisionConfiguration: reviewConfig, terms: terms,
                detailed: snapshot.assistancePreferences.jevDetailedReviewEnabled,
                client: generationClient, decisionClient: evaluator, onUsage: onUsage)
        }
        jevRepairTask = task
        let attempt = await task.value
        guard current(), !task.isCancelled else { return nil }
        jevRepairTask = nil; jevRepairInProgress = false
        switch attempt {
        case .cancelled: return nil
        case .held(let reason):
            jevLearningSummary = reason
            return nil
        case .repaired(let text, let review, let issues):
            let target = JevReviewTarget(id: job, kind: .recent, transcript: request.transcript,
                output: snapshot.decisionReviewMode == .repair ? text : originalOutput, purpose: .dictation,
                textProvider: snapshot.textConfiguration.provider, textModel: snapshot.textConfiguration.textModel,
                writingProfile: snapshot.writingProfile)
            if snapshot.decisionReviewMode == .repair {
                result = text; recentDecisionTarget = target
                decisionReviewSummary = L("교정안을 재검사해 입력 조건을 충족했습니다.", "The repaired text met the recheck conditions for typing.")
                publishDecisionDetails(review, terms: terms, target: target, reviewID: epoch)
            } else {
                var preview = JevImprovement(id: UUID(), target: target, provider: snapshot.textConfiguration.provider,
                    model: snapshot.textConfiguration.textModel, usageEpoch: usageResetGeneration)
                preview.output = text; preview.review = review; preview.isProcessing = false
                preview.status = L("입력 후 교정안을 재검사했습니다. 이미 입력한 글은 유지하며 개선안은 직접 복사할 수 있습니다.",
                                   "The background repair was rechecked. The typed text is unchanged; you can copy the alternative.")
                jevImprovement = preview
            }
            jevLearningSummary = L("교정안을 재검사했습니다. 오류 유형 학습은 꺼져 있습니다.",
                                   "The repair was rechecked. Learning of error patterns is off.")
            if snapshot.assistancePreferences.jevFeedbackLearningEnabled, preferences.jevFeedbackLearningEnabled,
               snapshot.assistancePreferences.historyEnabled, preferences.historyEnabled, let store {
                do {
                    guard current() else { return nil }
                    let write = Task {
                        try await store.recordJevRepairLesson(provider: snapshot.textConfiguration.provider,
                            model: snapshot.textConfiguration.textModel, issues: issues)
                    }
                    jevLessonWriteTask = write
                    try await write.value
                    guard current() else { return nil }
                    jevLessonWriteTask = nil
                    await refreshJevLearnedIssues()
                    guard current() else { return nil }
                    jevLearningSummary = L("해결한 오류 유형을 기억했습니다. 같은 문장 모델의 다음 받아쓰기에 반영합니다.",
                                           "Remembered the resolved error patterns for the next dictation with this text model.")
                } catch {
                    guard current() else { return nil }
                    jevLessonWriteTask = nil
                    jevLearningSummary = L("교정안은 검사했지만 오류 유형을 저장하지 못했습니다.",
                                           "The repair was checked, but its error patterns could not be saved.")
                }
            }
            return text
        }
    }

    func clearJevFeedbackLearning() async {
        guard storageChangesPermitted() else { return }
        stopDecisionReview()
        await eraseJevFeedbackLearning()
    }

    private func eraseJevFeedbackLearning() async {
        guard let store else { return }
        jevLearningRefreshGeneration = UUID()
        do {
            try await store.clearJevRepairLessons()
            jevLearningRefreshGeneration = UUID()
            jevLearnedIssues = []
            jevLearningSummary = L("모든 문장 모델의 오류 유형 기억을 지웠습니다.", "Cleared learned error patterns for all text models.")
        } catch {
            jevLearningSummary = L("오류 유형 기억을 지우지 못했습니다. 기존 기억은 보존했습니다.",
                                   "Could not clear the error patterns. Existing patterns were preserved.")
        }
    }

    static func decisionSuggestions(review: DecisionResult, terms: [DecisionTermCandidate],
                                    transcript: String, output: String) -> [String] {
        spellingProposals(review: review, terms: terms, transcript: transcript, output: output,
                          reviewID: UUID(), targetID: UUID()).map(\.title)
    }

    private static func spellingProposals(review: DecisionResult, terms: [DecisionTermCandidate],
                                         transcript: String, output: String,
                                         reviewID: UUID, targetID: UUID) -> [JevSpellingProposal] {
        let candidatesByID = Dictionary(uniqueKeysWithValues: terms.map { ($0.id, $0) })
        return review.terms.compactMap { term in
            guard let candidate = candidatesByID[term.id] else { return nil }
            switch term.choice {
            case .useCandidate:
                guard output.contains(candidate.original), !output.contains(candidate.candidate) else { return nil }
            case .keepOriginal:
                // Preserve Latin already spoken in any case; a proposal must never reverse it globally.
                guard output.contains(candidate.candidate),
                      !transcript.localizedCaseInsensitiveContains(candidate.candidate) else { return nil }
            case .uncertain:
                guard output.contains(candidate.original) || output.contains(candidate.candidate) else { return nil }
            }
            return .init(id: UUID(), reviewID: reviewID, targetID: targetID, original: candidate.original,
                         candidate: candidate.candidate, choice: term.choice, probabilities: term.probabilities, confidence: term.confidence)
        }
    }

    private func publishDecisionDetails(_ review: DecisionResult, terms: [DecisionTermCandidate],
                                        target: JevReviewTarget, reviewID: UUID) {
        currentDecisionReviewID = reviewID; decisionReviewTarget = target
        decisionRiskSignals = [.init(id: .meaningChanged, score: review.meaningChanged),
                               .init(id: .contentAdded, score: review.contentAdded),
                               .init(id: .contentOmitted, score: review.contentOmitted)]
        decisionRiskSignals += DecisionDetailAxis.allCases.compactMap { axis in
            guard let score = review.detailRisks[axis], let id = JevRiskSignal.Axis(rawValue: axis.rawValue) else { return nil }
            return .init(id: id, score: score)
        }
        decisionProposals = Self.spellingProposals(review: review, terms: terms,
            transcript: target.transcript, output: target.output, reviewID: reviewID, targetID: target.id)
        decisionTermSuggestions = decisionProposals.map(\.title)
    }

    /// Presentation follows the completed result's captured purpose, never today's language setting.
    var recentTranslationLanguage: String? {
        guard let target = recentDecisionTarget, !result.isEmpty, target.output == result,
              case .translation(let language) = target.purpose else { return nil }
        return Self.recordedTranslationLanguage(language)
    }

    /// Legacy explicit translations without a saved language cannot be evaluated by guessing a target.
    func historyReviewPurpose(for entry: HistoryEntry) -> DecisionReviewPurpose? {
        if entry.mode == .prompt { return .promptComposition }
        guard entry.mode == .dictation || entry.mode == .translation else { return nil }
        guard entry.effectiveMode == .translation else { return .dictation }
        let language = Self.recordedTranslationLanguage(entry.targetLanguage)
            ?? (entry.mode == .dictation ? entry.outputLanguage?.targetLanguage : nil)
        guard let language else { return nil }
        return .translation(targetLanguage: language)
    }

    private static func recordedTranslationLanguage(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              value.utf8.count <= 100,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return value
    }

    func reviewRecentResult() {
        guard let target = recentDecisionTarget else {
            manualDecisionReviewStatus = L("다시 검토할 최근 받아쓰기가 없습니다.", "There is no recent dictation to review."); return
        }
        beginManualDecisionReview(target)
    }

    func reviewHistory(_ entry: HistoryEntry) {
        guard let stored = history.first(where: { $0.id == entry.id }) else {
            manualDecisionReviewStatus = L("보관된 받아쓰기와 번역 기록만 검토할 수 있습니다.", "Only saved dictation and translation entries can be reviewed."); return
        }
        guard let purpose = historyReviewPurpose(for: stored) else {
            manualDecisionReviewStatus = stored.mode == .translation
                ? L("당시 번역 언어가 없거나 확인할 수 없어 직접 검토할 수 없습니다. 현재 설정으로 다시 처리한 미리보기를 검토해 주세요.", "The captured translation language is missing or invalid, so this saved result cannot be reviewed directly. Reprocess it with current settings and review that preview.")
                : L("보관된 받아쓰기와 번역 기록만 검토할 수 있습니다.", "Only saved dictation and translation entries can be reviewed.")
            return
        }
        beginManualDecisionReview(.init(id: stored.id, kind: .history, transcript: stored.originalText,
            output: stored.resultText, sourceHistoryID: stored.id, purpose: purpose,
            writingProfile: stored.writingProfile ?? .init()))
    }

    func reviewHistoryPreview() {
        guard let preview = historyReprocessing, !preview.isProcessing, let output = preview.result,
              let entry = history.first(where: { $0.id == preview.entryID }),
              let target = preview.reviewTarget else {
            manualDecisionReviewStatus = L("완료된 받아쓰기 미리보기만 검토할 수 있습니다.", "Only completed dictation previews can be reviewed."); return
        }
        guard target.transcript == entry.originalText, target.output == output else { return }
        beginManualDecisionReview(target)
    }

    func cancelManualDecisionReview() {
        guard manualDecisionReviewInProgress else { return }
        stopDecisionReview()
    }

    private func decisionTargetIsCurrent(_ target: JevReviewTarget) -> Bool {
        switch target.kind {
        case .recent:
            return recentDecisionTarget == target && result == target.output
        case .history:
            return history.contains { $0.id == target.sourceHistoryID && $0.effectiveMode == target.mode
                && $0.originalText == target.transcript && $0.resultText == target.output }
        case .reprocessed:
            guard let preview = historyReprocessing, preview.id == target.previewID,
                  preview.entryID == target.sourceHistoryID, !preview.isProcessing,
                  preview.result == target.output else { return false }
            return history.contains { $0.id == target.sourceHistoryID && $0.originalText == target.transcript }
        }
    }

    private func decisionTargetStillStored(_ target: JevReviewTarget) async throws -> Bool {
        guard decisionTargetIsCurrent(target) else { return false }
        guard let historyID = target.sourceHistoryID else { return true }
        guard let store else { return false }
        let snapshot = try await store.snapshot(retentionDays: preferences.retentionDays)
        return decisionTargetIsCurrent(target) && snapshot.history.contains {
            $0.id == historyID && (target.kind == .reprocessed || $0.effectiveMode == target.mode) && $0.originalText == target.transcript
                && (target.kind == .reprocessed || $0.resultText == target.output)
        }
    }

    /// A protected preview stays processing until its automatic check finishes; manual review still requires completion.
    private func protectedHistoryReviewIsCurrent(_ target: JevReviewTarget) -> Bool {
        guard target.kind == .reprocessed, case .translation = target.purpose,
              let preview = historyReprocessing, preview.isProcessing,
              preview.id == generation, translationProtectionJob == generation,
              translationProtectionReviewEpoch == decisionReviewEpoch, decisionReviewTask != nil,
              preferences.translationProtectionEnabled, preferences.decisionReviewMode == .protect,
              preview.id == target.previewID, preview.entryID == target.sourceHistoryID,
              preview.reviewTarget == target, preview.result == target.output else { return false }
        return history.contains { $0.id == target.sourceHistoryID && $0.originalText == target.transcript }
    }

    private func beginManualDecisionReview(_ target: JevReviewTarget, discoverNames: Bool = false) {
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy,
              !decisionDictionaryOperationInProgress, decisionTargetIsCurrent(target) else { return }
        stopDecisionReview()
        decisionReviewTarget = target
        guard !target.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              target.transcript.utf8.count + target.output.utf8.count + target.purpose.additionalTextBytes <= 24_000 else {
            manualDecisionReviewStatus = L("인식 원문이 없거나 선택 원문·지시·결과의 합계가 검사 가능한 크기(24 KB)를 넘었습니다.", "The transcript is empty, or the combined source, instruction and result exceed the 24 KB review limit."); return
        }
        let selected = preferences, epoch = decisionReviewEpoch, job = generation
        let reviewID = UUID(), usageJob = UUID(), usageEpoch = usageResetGeneration
        let tracksUsage = preferences.usageTrackingEnabled
        manualDecisionReviewID = reviewID; manualDecisionReviewInProgress = true
        jevNameDiscoveryInProgress = discoverNames
        manualDecisionReviewStatus = L("선택한 문장을 검토할 연결을 준비하고 있어요.", "Preparing to review the selected text.")
        manualDecisionReviewTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if manualDecisionReviewID == reviewID {
                    manualDecisionReviewInProgress = false; manualDecisionReviewTask = nil
                    jevNameDiscoveryInProgress = false
                }
            }
            @MainActor func current() -> Bool {
                !Task.isCancelled && manualDecisionReviewID == reviewID && decisionReviewEpoch == epoch
                    && generation == job && preferences.decisionProvider == selected.decisionProvider
                    && (selected.decisionProvider != .openRouter || preferences.effectiveTextProvider == selected.effectiveTextProvider)
                    && decisionTargetIsCurrent(target)
            }
            do {
                let configuration: DecisionConfiguration
                switch selected.decisionProvider {
                case .typeSafe:
                    // Optional Keychain loading is asynchronous; never send an unsaved draft.
                    loadDecisionKey()
                    if let pending = decisionKeyTask { await pending.value }
                    guard current() else { return }
                    guard let ready = decisionConfiguration(preferences: selected), !ready.apiKey.isEmpty else {
                        throw DecisionError.missingAPIKey
                    }
                    configuration = ready
                case .openRouter:
                    guard selected.effectiveTextProvider == .openRouter else { throw DecisionError.missingAPIKey }
                    try await prepareStoredKeys(for: [.openRouter])
                    guard current() else { return }
                    let textConfig = try self.configuration(provider: .openRouter, preferences: selected)
                    configuration = .init(provider: .openRouter, apiKey: textConfig.apiKey)
                }
                guard current() else { return }
                guard try await decisionTargetStillStored(target) else {
                    if current() { stopDecisionReview() }; return
                }
                guard current() else { return }
                let terms = target.mode == .dictation ? (discoverNames
                    ? JevNameCatalog.candidates(in: target.transcript, canonicalNames: selected.jevNameCatalog, limit: 4)
                    : Self.decisionTermCandidates(transcript: target.transcript, dictionary: dictionary)) : []
                if discoverNames, terms.isEmpty {
                    jevNameDiscoveryStatus = L("선택한 이름과 비슷한 표기를 찾지 못했습니다.", "No spelling resembling your selected names was found.")
                    manualDecisionReviewStatus = jevNameDiscoveryStatus
                    return
                }
                manualDecisionReviewStatus = L("선택한 원문과 결과를 검토하고 있어요.", "Reviewing the selected transcript and result.")
                let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                    guard tracksUsage else { return }
                    await self?.recordUsage(event, job: usageJob, mode: target.mode, isRecovery: false, epoch: usageEpoch)
                }
                let reviewStarted = ProcessInfo.processInfo.systemUptime
                let reviewed = try await decisionClient.evaluate(.init(transcript: target.transcript,
                    cleanedText: target.output, termCandidates: terms, purpose: target.purpose,
                    detailAxes: selected.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
                    expression: target.writingProfile.expression, translationTone: target.writingProfile.tone), configuration: configuration, onUsage: collectUsage)
                let reviewDuration = ProcessInfo.processInfo.systemUptime - reviewStarted
                guard current() else { return }
                if discoverNames { jevNameDiscoveryStatus = L("이름 후보를 문맥과 비교했습니다. 표기를 확인한 뒤 저장해 주세요.", "Name candidates were compared with the context. Check the spelling before saving.") }
                guard try await decisionTargetStillStored(target) else {
                    if current() { stopDecisionReview() }; return
                }
                guard current() else { return }
                if tracksUsage, usageEpoch == usageResetGeneration, preferences.usageTrackingEnabled,
                   let provider = target.textProvider, let model = target.textModel {
                    jevQualityMetrics.recordReview(provider: provider, model: model,
                        warning: reviewed.maximumRiskProbability >= 0.9,
                        duration: reviewDuration)
                }
                publishDecisionDetails(reviewed, terms: terms, target: target, reviewID: reviewID)
                decisionReviewSummary = reviewed.maximumRiskProbability >= 0.9
                    ? L("의미 변경 가능성을 발견했습니다. 원문과 결과를 비교해 주세요. 문장은 바꾸지 않았습니다.", "A possible meaning change was found. Compare the transcript and result. No text was changed.")
                    : L("뚜렷한 의미 변경 신호를 찾지 못했습니다. 정확성을 보장하는 판정은 아닙니다.", "No clear meaning-change signal was found. This does not guarantee accuracy.")
                manualDecisionReviewStatus = L("재검토를 마쳤습니다. 자동 입력·클립보드·문장 기록은 변경하지 않았습니다.", "Review complete. Automatic typing, clipboard contents, and text history were not changed.")
            } catch {
                guard current() else { return }
                let failure = JevReviewFailure(error); decisionReviewFailure = failure
                manualDecisionReviewStatus = L("재검토를 완료하지 못했습니다. ", "Review could not be completed. ") + failure.message
                    + L(" 문장은 변경하지 않았습니다.", " No text was changed.")
            }
        }
    }

    func canSaveDecisionProposal(_ proposal: JevSpellingProposal) -> Bool {
        guard proposal.canSave, !isBusy, !manualDecisionReviewInProgress, !decisionDictionaryOperationInProgress,
              proposal.reviewID == currentDecisionReviewID, decisionProposals.contains(proposal),
              let target = decisionReviewTarget, target.id == proposal.targetID,
              decisionTargetIsCurrent(target) else { return false }
        return true
    }

    /// The UI passes exactly the prior value displayed in the user's confirmation, not a refreshed guess.
    func saveDecisionProposal(_ proposal: JevSpellingProposal, replacing expected: DictionaryEntry?) async {
        guard !AppLaunch.isPreview, canSaveDecisionProposal(proposal), let store,
              let target = decisionReviewTarget else { return }
        let epoch = decisionReviewEpoch
        decisionDictionaryOperationInProgress = true; decisionProposalStatus = nil
        defer { decisionDictionaryOperationInProgress = false; decisionDictionaryTask = nil }
        do {
            let targetExists = try await decisionTargetStillStored(target)
            guard epoch == decisionReviewEpoch, currentDecisionReviewID == proposal.reviewID else { return }
            guard targetExists else {
                stopDecisionReview()
                let message = L("검토한 기록이 삭제되었거나 만료되어 표기를 저장하지 않았습니다.", "The reviewed history entry was deleted or expired, so the spelling was not saved.")
                decisionProposalStatus = message; notice = message
                await refreshData()
                return
            }
            let entry = DictionaryEntry(spoken: proposal.original, written: proposal.candidate, learned: false)
            let task = Task { try await store.applyReviewedDictionaryEntry(entry, expectedPrevious: expected) }
            decisionDictionaryTask = task
            let outcome = try await task.value
            // A committed write keeps its own undo token even if a new job starts during disk I/O.
            switch outcome {
            case .saved(let applied, let previous):
                lastDecisionDictionaryChange = (applied, previous); canUndoDecisionDictionarySave = true
                if epoch == decisionReviewEpoch {
                    decisionProposalStatus = L("확인한 표기를 개인 사전에 저장했습니다. 현재 문장은 바꾸지 않았습니다.", "Saved the confirmed spelling to your dictionary. The current text was not changed.")
                }
            case .alreadyExists:
                if epoch == decisionReviewEpoch { decisionProposalStatus = L("같은 표기가 이미 사전에 있습니다.", "This spelling is already in your dictionary.") }
            case .stale, .conflict:
                if epoch == decisionReviewEpoch {
                    decisionProposalStatus = L("확인하는 동안 사전이 바뀌었거나 충돌하는 항목이 있습니다. 사전을 확인한 뒤 다시 검토해 주세요.", "The dictionary changed while you were confirming, or a conflicting entry exists. Check it and review again.")
                }
            }
            await refreshData()
        } catch is CancellationError { }
        catch {
            if epoch == decisionReviewEpoch { decisionProposalStatus = L("표기를 저장하지 못했습니다. 기존 사전은 유지했습니다.", "The spelling could not be saved. Your existing dictionary was preserved.") }
        }
    }

    func undoDecisionDictionarySave() async {
        guard !AppLaunch.isPreview, !decisionDictionaryOperationInProgress,
              let store, let change = lastDecisionDictionaryChange else { return }
        decisionDictionaryOperationInProgress = true
        defer { decisionDictionaryOperationInProgress = false }
        do {
            let undone = try await store.undoDictionaryChange(applied: change.applied, previous: change.previous)
            lastDecisionDictionaryChange = nil; canUndoDecisionDictionarySave = false
            decisionProposalStatus = undone
                ? L("Jev 제안으로 저장한 마지막 표기를 되돌렸습니다.", "Undid the last spelling saved from a Jev proposal.")
                : L("표기가 이후에 변경되어 되돌리지 않았습니다. 현재 사전을 유지했습니다.", "The spelling changed afterward, so it was not undone. Your current dictionary was preserved.")
            await refreshData()
        } catch { decisionProposalStatus = L("되돌리지 못했습니다. 다시 시도해 주세요.", "Could not undo the spelling. Try again.") }
    }

    #if DEBUG
    /// Illustrates a completed Japanese result after the current output setting changed to English.
    func seedTranslationPreview() {
        guard AppLaunch.isPreview else { return }
        preferences.dictationOutputLanguage = .english
        let target = JevReviewTarget(id: UUID(), kind: .recent,
            transcript: "시간이 되시면 이 부분을 확인해 주실 수 있을까요? 급한 건 아니에요.",
            output: "お時間があれば、こちらをご確認いただけますか。急ぎではありません。",
            purpose: .translation(targetLanguage: "Japanese"))
        result = target.output; recentDecisionTarget = target; decisionOriginalText = target.transcript
    }

    /// Synthetic UI fixture only. No recording, storage, Keychain, or network operation is performed.
    func seedDecisionReviewPreview() {
        let target = JevReviewTarget(id: UUID(), kind: .recent,
            transcript: "오픈 라우터에서 내일 세 시 회의를 확인해 주세요", output: "오픈 라우터에서 내일 네 시 회의를 확인해 주세요.")
        result = target.output; recentDecisionTarget = target
        let terms = Self.decisionTermCandidates(transcript: target.transcript, dictionary: [])
        let reviewed = DecisionResult(meaningChanged: 0.95, contentAdded: 0.1, contentOmitted: 0.2,
            terms: terms.map { .init(id: $0.id, choice: .useCandidate,
                probabilities: [.useCandidate: 0.9, .keepOriginal: 0.05, .uncertain: 0.05], confidence: 0.9) })
        publishDecisionDetails(reviewed, terms: terms, target: target, reviewID: UUID())
        decisionReviewSummary = L("합성 예시: 시간 변경 가능성을 발견했습니다. 실제 사용자 기록이 아닙니다.", "Synthetic example: a possible time change was found. This is not a real user record.")
    }
    #endif

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
        if entry.mode == .prompt {
            if let issue = promptCompositionIssue { return issue }
            if entry.originalText.utf8.count > PromptCompositionLimits.maximumSourceBytes {
                return PromptCompositionFailure.inputTooLarge.localizedDescription
            }
        }
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
        if entry.mode == .prompt {
            return L("현재 설정: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · 간결한 프롬프트 · Jev 검토 2회 · 다듬기 1회", "Current settings: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · Concise prompt · Two Jev reviews · One polish pass")
        }
        let profile = preferences.writingProfile(for: entry.sourceBundleID)
        var description = L("현재 설정: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · \(profile.kind.title) / \(profile.tone.title) · 현재 개인 사전", "Current settings: \(preferences.effectiveTextProvider.displayName) · \(preferences.textModel) · \(profile.kind.title) / \(profile.tone.title) · Current dictionary")
        if entry.mode == .dictation, !preferences.dictationOutputLanguage.isTranslation, profile.expression.isActive {
            description += L(" · \(profile.expression.style.title) / 편집 강도 \(profile.expression.strength)", " · \(profile.expression.style.title) / editing strength \(profile.expression.strength)")
        }
        if entry.mode == .translation { description += L(" · 번역 언어: \(preferences.targetLanguage)", " · Translation language: \(preferences.targetLanguage)") }
        if entry.mode == .dictation {
            description += L(" · 출력 언어: \(preferences.dictationOutputLanguage.title)", " · Output language: \(preferences.dictationOutputLanguage.title)")
        }
        if preferences.translationRefinementEnabled,
           entry.mode == .translation || entry.mode == .dictation && preferences.dictationOutputLanguage.isTranslation {
            description += L(" · 번역 다듬기 1회", " · One translation refinement pass")
        }
        return description
    }

    /// History contains recognized speech, but no selected text or surrounding cursor context.
    /// Reprocessing is an explicit text-only request whose output stays in a disposable preview.
    func reprocessHistory(_ entry: HistoryEntry) {
        guard storageChangesPermitted() else { return }
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
                                        outputLanguage: entry.mode == .dictation ? preferences.dictationOutputLanguage : .original,
                                        writingProfile: entry.mode == .prompt ? .init() : preferences.writingProfile(for: entry.sourceBundleID))
        let job = UUID(), usageEpoch = usageResetGeneration
        let reprocessingPreferences = preferences
        let refinementEpoch = translationRefinementEpoch
        let protectsTranslation = TranslationProtectionPolicy.requiresReview(mode: request.effectiveMode,
            enabled: reprocessingPreferences.translationProtectionEnabled, reviewMode: reprocessingPreferences.decisionReviewMode)
        let reviewConfiguration = decisionConfiguration(preferences: reprocessingPreferences, textConfiguration: config)
        let tracksUsage = preferences.usageTrackingEnabled
        let retentionDays = preferences.retentionDays
        generation = job
        promptCompositionJob = entry.mode == .prompt ? job : nil
        // Starting a new generation revokes the previous review epoch before this job captures its own.
        let reviewEpoch = decisionReviewEpoch
        translationProtectionJob = protectsTranslation ? job : nil
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
                    await self?.recordUsage(event, job: job, mode: request.effectiveMode, isRecovery: false, epoch: usageEpoch)
                }
                let generationStarted = ProcessInfo.processInfo.systemUptime
                var output: String
                if request.mode == .prompt {
                    output = try await composePrompt(request: request, configuration: config,
                        decisionConfiguration: reviewConfiguration, epoch: reviewEpoch, job: job, onUsage: collectUsage)
                } else {
                    output = try await client.process(request, configuration: config, onUsage: collectUsage)
                }
                if tracksUsage, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                    jevQualityMetrics.recordGeneration(provider: config.provider, model: config.textModel,
                        duration: ProcessInfo.processInfo.systemUptime - generationStarted)
                }
                try Task.checkCancellation()
                let after = try await store.snapshot(retentionDays: retentionDays)
                guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                guard after.history.contains(where: { $0.id == entry.id }) else {
                    dismissHistoryReprocessing(); await refreshData(); return
                }
                if request.requiresTranslation, reprocessingPreferences.translationRefinementEnabled,
                   refinementEpoch != translationRefinementEpoch { throw translationRefinementRevocationError }
                historyReprocessing?.result = output
                if request.requiresTranslation, reprocessingPreferences.translationRefinementEnabled {
                    processingStage = .translationRefinement
                    output = try await refineTranslation(request: request, draft: output,
                        configuration: config, epoch: refinementEpoch, job: job,
                        historyPreview: true, onUsage: collectUsage)
                    try Task.checkCancellation()
                    let retained = try await store.snapshot(retentionDays: retentionDays)
                    guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                    guard retained.history.contains(where: { $0.id == entry.id }) else {
                        dismissHistoryReprocessing(); await refreshData(); return
                    }
                    historyReprocessing?.result = output
                }
                historyReprocessing?.reviewTarget = .init(id: job, kind: .reprocessed,
                    transcript: request.transcript, output: output, sourceHistoryID: entry.id, previewID: job,
                    purpose: request.mode == .prompt ? .promptComposition
                        : request.requiresTranslation ? .translation(targetLanguage: request.effectiveTargetLanguage) : .dictation,
                    textProvider: config.provider, textModel: config.textModel, writingProfile: request.writingProfile)
                if protectsTranslation, let target = historyReprocessing?.reviewTarget {
                    processingStage = .decisionReview
                    let held = await reviewTranslationBeforeInsertion(target: target, configuration: reviewConfiguration,
                        selected: reprocessingPreferences, epoch: reviewEpoch, job: job, provider: config.provider,
                        model: config.textModel, onUsage: collectUsage)
                    guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                    if held {
                        historyReprocessing?.error = L("번역 보호 검토에서 입력 조건을 확인하지 못했습니다. 원문과 미리보기를 직접 비교해 주세요.", "Translation protection did not meet the typing checks. Compare the source and preview yourself.")
                    }
                }
            } catch {
                guard generation == job, historyReprocessing?.id == job, !Task.isCancelled else { return }
                historyReprocessing?.error = error.localizedDescription
            }
        }
    }

    func dismissHistoryReprocessing() {
        guard let preview = historyReprocessing else { return }
        if decisionReviewTarget?.previewID == preview.id { stopDecisionReview() }
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
        guard storageChangesPermitted() else { return }
        guard !isBusy, let store else { return }
        usageResetGeneration = UUID(); jevQualityMetrics.clear()
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
    private func refreshJevLearnedIssues() async {
        guard let store else { return }
        let refresh = UUID(), provider = preferences.effectiveTextProvider, model = preferences.textModel
        jevLearningRefreshGeneration = refresh
        let issues = (try? await store.jevRepairLessons(provider: provider, model: model)) ?? []
        guard !Task.isCancelled, jevLearningRefreshGeneration == refresh,
              provider == preferences.effectiveTextProvider, model == preferences.textModel else { return }
        jevLearnedIssues = issues
    }

    func refreshData() async {
        if persistPreferences, !preferencesRecoveryRequired {
            let saved = Preferences.load(from: runtime.preferencesDefaults)
            if saved.recoveryState.requiresRecovery { preferences = saved }
        }
        guard let store else { return }
        let refresh = UUID(); dataRefreshGeneration = refresh
        let learningRefresh = UUID(); jevLearningRefreshGeneration = learningRefresh
        do {
            let current = if preferencesRecoveryRequired { try await store.snapshotPreservingRetention() }
                else { try await store.snapshot(retentionDays: preferences.retentionDays) }
            guard dataRefreshGeneration == refresh else { return }
            history = current.history; dictionary = current.dictionary
            if jevLearningRefreshGeneration == learningRefresh {
                jevLearnedIssues = current.jevLearningLessons.first {
                    $0.provider == preferences.effectiveTextProvider && $0.model == preferences.textModel
                }?.issues ?? []
            }
            if let reviewTarget = decisionReviewTarget, reviewTarget.sourceHistoryID != nil,
               !decisionTargetIsCurrent(reviewTarget), !protectedHistoryReviewIsCurrent(reviewTarget) { stopDecisionReview() }
            if let preview = historyReprocessing, !history.contains(where: { $0.id == preview.entryID }) {
                dismissHistoryReprocessing()
            }
            usageRecords = current.usageRecords; usageTrackingStartedAt = current.usageTrackingStartedAt
            usageDiscardedCount = current.usageDiscardedCount
            failures = current.failedRecordings; learningCandidate = current.learningCandidates.first
            if let reviewed = jevCorrectionReview, !current.learningCandidates.contains(reviewed.candidate) {
                jevWorkflowTask?.cancel(); jevCorrectionReview = nil
            }
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
        guard storageChangesPermitted() else { return }
        guard let store else { return }
        do { _ = try await store.deleteDictionaryEntry(id: entry.id); await refreshData() } catch { self.error = error.localizedDescription }
    }
    @discardableResult func importDictionary(_ entries: [DictionaryEntry]) async -> Bool {
        guard storageChangesPermitted() else { return false }
        guard let store else { error = L("암호화 저장소를 사용할 수 없습니다.", "Encrypted storage is unavailable."); return false }
        do { _ = try await store.upsertDictionaryEntries(entries); await refreshData(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func updateDictionaryEntry(_ entry: DictionaryEntry, spoken: String, written: String) async -> Bool {
        guard storageChangesPermitted() else { return false }
        guard let store else { return false }
        let from = spoken.trimmingCharacters(in: .whitespacesAndNewlines), to = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.count <= 100, to.count <= 100 else { return false }
        do { _ = try await store.updateDictionaryEntry(id: entry.id, spoken: from, written: to); await refreshData(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func deleteHistory(_ entry: HistoryEntry? = nil) async {
        guard storageChangesPermitted() else { return }
        if entry == nil { historyWriteEpoch = UUID() }
        recentDecisionTarget = nil
        if entry == nil || historyReprocessing?.entryID == entry?.id { revokeTranslationRefinement() }
        else {
            if translationRefinement?.isProcessing == true || translationRefinement?.held == true { result = "" }
            translationRefinement = nil
        }
        stopDecisionReview()
        promptComposition = nil
        guard let store else { return }
        if let preview = historyReprocessing, entry == nil || entry?.id == preview.entryID {
            dismissHistoryReprocessing()
        }
        do {
            if entry == nil {
                try await store.deleteAllHistory(); learningCandidate = nil
                try await store.clearJevRepairLessons(); jevLearningRefreshGeneration = UUID(); jevLearnedIssues = []
            }
            else if let entry { _ = try await store.deleteHistory(id: entry.id) }
            await refreshData()
        } catch { self.error = error.localizedDescription }
    }
    func dismissLearningCandidate() async {
        guard storageChangesPermitted() else { return }
        if jevCorrectionReview != nil { jevWorkflowTask?.cancel(); jevCorrectionReview = nil }
        guard let store, let candidate = learningCandidate else { return }
        do { try await store.dismissLearningCandidate(id: candidate.id); await refreshData() }
        catch { self.error = error.localizedDescription }
    }
    func deleteFailure(_ item: FailedRecording) async {
        guard storageChangesPermitted() else { return }
        do { try await store?.deleteFailure(id: item.id); await refreshData() } catch { self.error = error.localizedDescription }
    }
    func retry(_ item: FailedRecording, useCurrentSettings: Bool = false) {
        guard storageChangesPermitted() else { return }
        guard startupState == .ready, !isBusy, let store else { return }
        let retryTextProvider = useCurrentSettings ? preferences.effectiveTextProvider : item.textProvider ?? item.provider
        var retryPreflightPreferences = preferences
        if !useCurrentSettings { retryPreflightPreferences.dictationOutputLanguage = item.outputLanguage ?? .original }
        if let issue = jevPreflightIssue(mode: item.mode, preferences: retryPreflightPreferences, textProvider: retryTextProvider) {
            error = issue.message; page = .settings; settingsSection = .connection; showManager?(); return
        }
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        lastProcessingTimings = nil
        let selectedRetryText = retrySelection
        generation = UUID(); let job = generation; processingStage = .audioPreparation
        promptCompositionJob = item.mode == .prompt ? job : nil
        phase = .processing; error = nil; notice = nil; result = ""; learningTask?.cancel(); onPhaseChange?()
        processingTask = Task {
            do {
                let selection = selectedRetryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard item.mode != .rewrite || !selection.isEmpty else { throw AppError.message(L("원래 선택 문장은 저장하지 않습니다. 수정할 원문을 붙여넣은 뒤 다시 처리해 주세요.", "The original selection is not stored. Paste the text you want to edit before reprocessing.")) }
                let retryPreferences = preferences
                let retryRefinementEpoch = translationRefinementEpoch
                let retryOutputLanguage = item.mode == .dictation
                    ? (useCurrentSettings ? retryPreferences.dictationOutputLanguage : item.outputLanguage ?? .original) : .original
                translationProtectionJob = TranslationProtectionPolicy.requiresReview(
                    mode: item.mode == .dictation && retryOutputLanguage.isTranslation ? .translation : item.mode,
                    enabled: retryPreferences.translationProtectionEnabled, reviewMode: retryPreferences.decisionReviewMode) ? job : nil
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
                var retryProfile = item.writingProfile ?? .init()
                if useCurrentSettings { retryProfile.expression = retryPreferences.dictationExpression }
                let snapshot = ProcessingSnapshot(transcriptionConfiguration: transcriptionConfig, textConfiguration: textConfig,
                    needsLocal: needsLocal,
                    speakerFilter: useCurrentSettings ? retryPreferences.speakerFilterEnabled : item.usedSpeakerFilter ?? false,
                    targetLanguage: useCurrentSettings
                        ? (item.mode == .dictation ? retryPreferences.dictationOutputLanguage.targetLanguage ?? retryPreferences.targetLanguage : retryPreferences.targetLanguage)
                        : item.targetLanguage,
                    outputLanguage: item.mode == .dictation
                        ? (useCurrentSettings ? retryPreferences.dictationOutputLanguage : item.outputLanguage ?? .original)
                        : .original,
                    dictionary: retryDictionary, writingProfile: retryProfile,
                    decisionReviewMode: retryPreferences.decisionReviewMode,
                    translationProtectionEnabled: retryPreferences.translationProtectionEnabled,
                    decisionReviewEpoch: retryDecisionReviewEpoch,
                    decisionConfiguration: reviewConfig, assistancePreferences: retryPreferences,
                    translationRefinementEpoch: retryRefinementEpoch)
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
        guard storageChangesPermitted() else { return }
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
        guard storageChangesPermitted() else { return }
        guard !isBusy else { return }
        do { try await speaker?.deleteProfile(); hasSpeakerProfile = false; preferences.speakerFilterEnabled = false }
        catch { self.error = error.localizedDescription }
    }
    private func watchCorrection(_ output: String, target: InputTarget) {
        if let observe = runtime.observeCorrection { observe(output, target); return }
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
        guard storageChangesPermitted() else { return false }
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
        guard storageChangesPermitted() else { return }
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
    private func prepareDecisionConfiguration(_ selected: Preferences) async throws -> DecisionConfiguration {
        switch selected.decisionProvider {
        case .typeSafe:
            loadDecisionKey()
            if let task = decisionKeyTask { await task.value }
            try Task.checkCancellation()
            guard let ready = decisionConfiguration(preferences: selected), !ready.apiKey.isEmpty else {
                throw DecisionError.missingAPIKey
            }
            return ready
        case .openRouter:
            guard selected.effectiveTextProvider == .openRouter else { throw DecisionError.missingAPIKey }
            try await prepareStoredKeys(for: [.openRouter])
            let config = try configuration(provider: .openRouter, preferences: selected)
            return .init(provider: .openRouter, apiKey: config.apiKey)
        }
    }


    private func captureJevAssistance(_ snapshot: ProcessingSnapshot) {
        jevAssistancePreferences = snapshot.assistancePreferences
        jevAssistanceDictionary = snapshot.dictionary
        jevAssistanceWritingProfile = snapshot.writingProfile
    }

    private func startAutomaticJevImprovementIfReady() {
        guard let target = automaticImprovementTarget, !isBusy, !jevWorkflowInProgress,
              jevEditClarification == nil, jevReRecognition == nil, !manualDecisionReviewInProgress,
              preferences.jevAutomaticImprovementEnabled, decisionTargetIsCurrent(target) else { return }
        automaticImprovementTarget = nil
        createJevImprovement(for: target, automatically: true)
    }

    func addJevCatalogName(_ name: String) {
        guard !AppLaunch.isPreview, startupState == .ready else { return }
        preferences.jevNameCatalog = Preferences.normalizedJevCatalogNames(preferences.jevNameCatalog + [name])
    }

    func removeJevCatalogName(_ name: String) {
        guard !AppLaunch.isPreview else { return }
        preferences.jevNameCatalog.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func discoverJevNames(for target: JevReviewTarget) {
        guard target.mode == .dictation, !preferences.jevNameCatalog.isEmpty,
              !jevWorkflowInProgress, !manualDecisionReviewInProgress else { return }
        beginManualDecisionReview(target, discoverNames: true)
    }

    func dismissJevEditClarification() {
        jevAssistanceOperation = UUID(); jevAssistanceTask?.cancel(); jevAssistanceTask = nil
        jevEditClarification = nil; jevAssistancePreferences = nil; jevAssistanceDictionary = []
    }

    func dismissJevReRecognition() {
        if phase == .processing, jevReRecognition?.isProcessing == true { cancel(); return }
        jevAssistanceOperation = UUID(); jevAssistanceTask?.cancel(); jevAssistanceTask = nil
        jevReRecognition = nil; jevAssistancePreferences = nil; jevAssistanceDictionary = []
    }

    func resolveJevEditClarification(instruction: String) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = jevEditClarification, !source.isProcessing, !instruction.isEmpty,
              source.original.utf8.count + instruction.utf8.count <= 24_000 else { return }
        runJevAssistancePreview(id: source.id, transcript: instruction, original: source.original)
    }

    func processJevTranscriptAlternative() {
        guard let value = jevReRecognition, !value.isProcessing, let transcript = value.alternative,
              !transcript.isEmpty, transcript.utf8.count <= 24_000 else { return }
        runJevAssistancePreview(id: value.id, transcript: transcript, original: nil)
    }

    /// Explicitly requested previews are copy-only. They never reuse an old AX target.
    private func runJevAssistancePreview(id: UUID, transcript: String, original: String?) {
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy, !jevWorkflowInProgress,
              !manualDecisionReviewInProgress, !decisionDictionaryOperationInProgress,
              let selected = jevAssistancePreferences,
              selected.effectiveTextProvider == preferences.effectiveTextProvider,
              selected.textModel == preferences.textModel,
              selected.decisionProvider == preferences.decisionProvider else { return }
        let isEdit = original != nil, epoch = decisionReviewEpoch, operation = UUID(), usageEpoch = usageResetGeneration
        jevAssistanceOperation = operation
        let chosenDictionary = jevAssistanceDictionary, profile = jevAssistanceWritingProfile
        if isEdit { jevEditClarification?.isProcessing = true; jevEditClarification?.output = nil }
        else { jevReRecognition?.isProcessing = true; jevReRecognition?.output = nil }
        jevAssistanceTask = Task { [weak self] in
            guard let self else { return }
            @MainActor func current() -> Bool {
                !Task.isCancelled && jevAssistanceOperation == operation && decisionReviewEpoch == epoch
                    && (isEdit ? jevEditClarification?.id == id : jevReRecognition?.id == id)
            }
            @MainActor func status(_ value: String) {
                if isEdit { jevEditClarification?.status = value } else { jevReRecognition?.status = value }
            }
            defer {
                if jevAssistanceOperation == operation {
                    if isEdit { jevEditClarification?.isProcessing = false } else { jevReRecognition?.isProcessing = false }
                    jevAssistanceTask = nil
                }
            }
            let mode: InputMode = isEdit ? .rewrite : .dictation
            let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                guard selected.usageTrackingEnabled else { return }
                await self?.recordUsage(event, job: operation, mode: mode, isRecovery: false, epoch: usageEpoch)
            }
            do {
                let reviewConfig = try await prepareDecisionConfiguration(selected)
                guard current() else { return }
                try await prepareStoredKeys(for: [selected.effectiveTextProvider])
                guard current() else { return }
                let config = try configuration(provider: selected.effectiveTextProvider, preferences: selected)
                if let original {
                    let assessment = try await decisionClient.assessEditAmbiguity(originalText: original,
                        instruction: transcript, configuration: reviewConfig, onUsage: collectUsage)
                    guard current() else { return }
                    jevEditClarification?.assessment = assessment
                    guard JevAssistancePolicy.editIsClear(assessment) else {
                        status(L("아직 지시가 모호합니다. 바꿀 부분과 원하는 결과를 더 구체적으로 알려 주세요.", "The instruction is still unclear. Specify the change and intended result.")); return
                    }
                }
                status(L("확인할 결과를 한 개 만들고 있어요…", "Creating one preview…"))
                let request = ProcessingRequest(mode: mode, transcript: transcript, selectedText: original,
                    dictionary: chosenDictionary, writingProfile: profile)
                let provider = client
                let output = try await jevWithDeadline(seconds: 20) {
                    try await provider.process(request, configuration: config, allowRetry: false, onUsage: collectUsage)
                }
                guard current() else { return }
                if isEdit { jevEditClarification?.output = output } else { jevReRecognition?.output = output }
                let purpose: DecisionReviewPurpose = original.map { .rewrite(originalText: $0) } ?? .dictation
                do {
                    let review = try await decisionClient.evaluate(.init(transcript: transcript, cleanedText: output,
                        purpose: purpose, detailAxes: selected.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
                        expression: profile.expression),
                        configuration: reviewConfig, onUsage: collectUsage)
                    guard current() else { return }
                    status(review.maximumRiskProbability >= 0.9
                        ? L("결과에도 의미 변경 신호가 있습니다. 원문과 비교한 뒤 복사해 주세요.", "The preview also has a meaning-change signal. Compare it before copying.")
                        : L("검토를 마쳤습니다. 실제 의도와 비교한 뒤 원하는 결과를 복사해 주세요.", "Review complete. Compare the preview with your intent before copying."))
                } catch {
                    guard current() else { return }
                    status(L("결과를 만들었지만 검토를 완료하지 못했습니다. 미검토 결과를 직접 확인해 주세요.", "The preview is ready but could not be reviewed. Inspect this unreviewed result yourself."))
                }
            } catch {
                guard current() else { return }
                status(L("요청을 완료하지 못했습니다. 저장된 키와 모델 연결을 확인해 주세요.", "The request could not be completed. Check saved keys and model connections."))
            }
        }
    }

    func copyJevClarifiedEdit() {
        guard let value = jevEditClarification, !value.isProcessing, let output = value.output, !output.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
        notice = L("수정안을 복사했습니다. 원하는 위치에 붙여넣으세요.", "Edit copied. Paste it where you want.")
    }

    func copyJevTranscriptAlternative() {
        guard let value = jevReRecognition, !value.isProcessing,
              let output = value.output ?? value.alternative, !output.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
        notice = L("선택한 결과를 복사했습니다. 원하는 위치에 붙여넣으세요.", "Selected result copied. Paste it where you want.")
    }

    func cancelJevModelComparison() {
        jevAssistanceOperation = UUID(); jevAssistanceTask?.cancel(); jevAssistanceTask = nil
        jevModelComparisonPreparing = false; jevModelComparison.cancelAll()
    }

    func runJevModelComparison() {
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy, !jevWorkflowInProgress,
              !manualDecisionReviewInProgress, !decisionDictionaryOperationInProgress else { return }
        let cases = jevModelComparison.cases, models = jevModelComparison.selectedModels, budget = jevModelComparison.budgetUSD
        stopDecisionReview()
        jevModelComparison.cases = cases; jevModelComparison.selectedModels = models; jevModelComparison.budgetUSD = budget
        let selected = preferences, operation = UUID(), epoch = decisionReviewEpoch, usageEpoch = usageResetGeneration
        let chosenDictionary = dictionary
        jevAssistanceOperation = operation; jevModelComparisonPreparing = true
        jevAssistanceTask = Task { [weak self] in
            guard let self else { return }
            @MainActor func current() -> Bool {
                !Task.isCancelled && jevAssistanceOperation == operation && decisionReviewEpoch == epoch
                    && preferences.effectiveTextProvider == selected.effectiveTextProvider && preferences.textModel == selected.textModel
                    && jevModelComparison.cases == cases && jevModelComparison.selectedModels == models
                    && jevModelComparison.budgetUSD == budget
            }
            defer { if jevAssistanceOperation == operation { jevModelComparisonPreparing = false; jevAssistanceTask = nil } }
            do {
                let reviewConfig = try await prepareDecisionConfiguration(selected)
                guard current() else { return }
                try await prepareStoredKeys(for: [selected.effectiveTextProvider])
                guard current() else { return }
                let config = try configuration(provider: selected.effectiveTextProvider, preferences: selected)
                let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                    guard selected.usageTrackingEnabled else { return }
                    await self?.recordUsage(event, job: operation, mode: .dictation, isRecovery: false, epoch: usageEpoch)
                }
                await jevModelComparison.run(configuration: config, decisionConfiguration: reviewConfig,
                    dictionary: chosenDictionary, client: client, reviewer: decisionClient, onUsage: collectUsage)
            } catch {
                guard current() else { return }
                jevModelComparison.reportPreparationFailure()
            }
        }
    }

    func applyJevRecommendedModel(_ model: String) {
        guard !isBusy, !jevWorkflowInProgress, jevModelComparison.recommendedModel == model,
              TextModelCatalog.entries(for: preferences.effectiveTextProvider).contains(where: { $0.id == model }) else { return }
        preferences.textModels[preferences.effectiveTextProvider.rawValue] = model
        notice = L("선택한 비교 모델을 문장 정리에 적용했습니다.", "Applied the selected comparison model to text cleanup.")
    }

    func cancelJevWorkflow() {
        jevWorkflowTask?.cancel(); jevWorkflowTask = nil
        jevImprovement = nil; jevCorrectionReview = nil
    }

    /// Runs only after the visible target, model and two possible requests are confirmed.
    func createJevImprovement(for target: JevReviewTarget, automatically: Bool = false) {
        guard target.mode != .prompt else {
            notice = L("프롬프트는 기록의 다시 처리에서 생성·검토 전체 흐름으로 다듬어 주세요.", "Use Reprocess in history to refine prompts through the complete generation and review flow.")
            return
        }
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy, !jevWorkflowInProgress,
              !manualDecisionReviewInProgress, !decisionDictionaryOperationInProgress,
              decisionTargetIsCurrent(target) else { return }
        guard target.transcript.utf8.count + target.output.utf8.count + target.purpose.additionalTextBytes <= 24_000 else {
            manualDecisionReviewStatus = L("선택 원문·지시·결과의 합계가 24 KB를 넘어 개선안을 요청하지 않았습니다.", "The combined source, instruction and result exceed 24 KB, so no alternative was requested.")
            return
        }
        if automatically {
            let request = ProcessingRequest(mode: target.mode, transcript: target.transcript, dictionary: dictionary,
                writingProfile: target.writingProfile, previousOutput: target.output)
            guard let bytes = try? ProviderClient.processingInputBytes(request),
                  JevAssistancePolicy.automaticImprovementFitsBudget(model: preferences.improvementModel,
                    provider: preferences.effectiveTextProvider, promptBytes: bytes) else {
                decisionProposalStatus = L("참고 단가로 계산한 추가 호출 예산($0.05) 안의 모델을 확인하지 못해 자동 개선안을 생략했습니다.", "The reference-price reservation did not fit $0.05, so the automatic alternative was skipped.")
                return
            }
        }
        stopDecisionReview(); decisionReviewTarget = target
        let selected = preferences, epoch = decisionReviewEpoch, operation = UUID(), usageEpoch = usageResetGeneration
        let chosenDictionary = dictionary
        jevImprovement = .init(id: operation, target: target, provider: selected.effectiveTextProvider,
                              model: selected.improvementModel, usageEpoch: usageEpoch)
        jevWorkflowTask = Task { [weak self] in
            guard let self else { return }
            @MainActor func current() -> Bool {
                !Task.isCancelled && jevImprovement?.id == operation && epoch == decisionReviewEpoch
                    && decisionTargetIsCurrent(target)
                    && preferences.effectiveTextProvider == selected.effectiveTextProvider
                    && preferences.improvementModel == selected.improvementModel
            }
            defer { if jevImprovement?.id == operation { jevImprovement?.isProcessing = false; jevWorkflowTask = nil } }
            let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                guard selected.usageTrackingEnabled else { return }
                await self?.recordUsage(event, job: operation, mode: target.mode, isRecovery: false, epoch: usageEpoch)
            }
            do {
                // Prepare both connections before paying for generation; drafts never become credentials.
                let reviewConfig = try await prepareDecisionConfiguration(selected)
                guard current() else { return }
                try await prepareStoredKeys(for: [selected.effectiveTextProvider])
                guard current() else { return }
                let stored0 = try await decisionTargetStillStored(target)
                guard current() else { return }
                guard stored0 else { cancelJevWorkflow(); return }
                var config = try configuration(provider: selected.effectiveTextProvider, preferences: selected)
                config.textModel = selected.improvementModel
                var language = "English (United States)"
                var original: String?
                switch target.purpose {
                case .promptComposition: break
                case .dictation: break
                case .translation(let value): language = value
                case .rewrite(let value): original = value
                }
                let request = ProcessingRequest(mode: target.mode, transcript: target.transcript,
                    selectedText: original, dictionary: chosenDictionary, targetLanguage: language,
                    writingProfile: target.writingProfile, previousOutput: target.output)
                jevImprovement?.status = L("개선안 한 개를 만들고 있어요…", "Generating one alternative…")
                let generationStarted = ProcessInfo.processInfo.systemUptime
                let output: String
                if automatically {
                    let provider = client, capturedConfig = config
                    output = try await jevWithDeadline(seconds: 8) {
                        try await provider.process(request, configuration: capturedConfig, allowRetry: false, onUsage: collectUsage)
                    }
                } else {
                    output = try await client.process(request, configuration: config, allowRetry: false, onUsage: collectUsage)
                }
                if selected.usageTrackingEnabled, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                    jevQualityMetrics.recordGeneration(provider: config.provider, model: config.textModel,
                        duration: ProcessInfo.processInfo.systemUptime - generationStarted)
                }
                guard current() else { return }
                let stored1 = try await decisionTargetStillStored(target)
                guard current() else { return }
                guard stored1 else { cancelJevWorkflow(); return }
                jevImprovement?.output = output
                if selected.usageTrackingEnabled, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                    jevQualityMetrics.recordImprovementOffered(provider: config.provider, model: config.textModel)
                }
                jevImprovement?.status = L("개선안을 Jev로 검토하고 있어요…", "Reviewing the alternative with Jev…")
                let started = ProcessInfo.processInfo.systemUptime
                do {
                    let review = try await decisionClient.evaluate(.init(transcript: target.transcript,
                        cleanedText: output, purpose: target.purpose,
                        detailAxes: selected.jevDetailedReviewEnabled ? DecisionDetailAxis.allCases : [],
                        expression: target.writingProfile.expression, translationTone: target.writingProfile.tone), configuration: reviewConfig, onUsage: collectUsage)
                    let reviewDuration = ProcessInfo.processInfo.systemUptime - started
                    guard current() else { return }
                    let stored2 = try await decisionTargetStillStored(target)
                    guard current() else { return }
                    guard stored2 else { cancelJevWorkflow(); return }
                    jevImprovement?.review = review
                    jevImprovement?.status = review.maximumRiskProbability >= 0.9
                        ? L("개선안에도 의미 변경 신호가 있습니다. 원문과 비교해 주세요.", "This alternative also has a meaning-change signal. Compare it with the source.")
                        : L("검토를 마쳤습니다. 더 나은 결과인지는 직접 비교해 주세요.", "Review complete. Compare the texts to decide whether it is better.")
                    if selected.usageTrackingEnabled, preferences.usageTrackingEnabled, usageEpoch == usageResetGeneration {
                        jevQualityMetrics.recordReview(provider: config.provider, model: config.textModel,
                            warning: review.maximumRiskProbability >= 0.9, duration: reviewDuration)
                    }
                } catch {
                    guard current() else { return }
                    jevImprovement?.status = L("개선안 검토를 완료하지 못했습니다. 미검토 결과이므로 원문과 직접 비교해 주세요.", "The alternative could not be reviewed. Compare this unreviewed result with the source.")
                }
            } catch {
                guard current() else { return }
                jevImprovement?.status = L("개선안을 만들지 못했습니다. 저장된 키와 모델 연결을 확인해 주세요. 기존 결과는 유지됩니다.", "Could not generate an alternative. Check saved keys and model connections. The existing result is unchanged.")
            }
        }
    }

    func copyJevImprovement(_ id: UUID) async {
        guard let preview = jevImprovement, preview.id == id, !preview.isProcessing,
              let text = preview.output, !text.isEmpty, decisionTargetIsCurrent(preview.target) else { return }
        guard (try? await decisionTargetStillStored(preview.target)) == true,
              jevImprovement?.id == id, !Task.isCancelled else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        if jevImprovement?.adopted == false, preview.usageEpoch == usageResetGeneration, preferences.usageTrackingEnabled {
            jevQualityMetrics.recordImprovementAdopted(provider: preview.provider, model: preview.model)
        }
        jevImprovement?.adopted = true
        notice = L("개선안을 복사했습니다. 원하는 입력창에 붙여넣으세요.", "Alternative copied. Paste it into the text field you want.")
    }

    func reviewLearningCandidate(_ candidate: LearningCandidate) {
        guard !AppLaunch.isPreview, startupState == .ready, !isBusy, !jevWorkflowInProgress,
              !manualDecisionReviewInProgress, !decisionDictionaryOperationInProgress,
              preferences.historyEnabled, learningCandidate == candidate, let store,
              let entry = CorrectionLearner.reviewProposal(original: candidate.originalText, edited: candidate.editedText) else { return }
        stopDecisionReview()
        let selected = preferences, epoch = decisionReviewEpoch, id = UUID(), usageEpoch = usageResetGeneration
        jevCorrectionReview = .init(id: id, candidate: candidate, entry: entry)
        jevWorkflowTask = Task { [weak self] in
            guard let self else { return }
            @MainActor func current() -> Bool {
                !Task.isCancelled && jevCorrectionReview?.id == id && epoch == decisionReviewEpoch
                    && learningCandidate == candidate && preferences.historyEnabled
            }
            defer { if jevCorrectionReview?.id == id { jevCorrectionReview?.isProcessing = false; jevWorkflowTask = nil } }
            do {
                let config = try await prepareDecisionConfiguration(selected)
                guard current() else { return }
                let before = try await store.snapshot(retentionDays: preferences.retentionDays)
                guard current() else { return }
                guard before.learningCandidates.contains(candidate) else { cancelJevWorkflow(); return }
                let collectUsage: @Sendable (ProviderUsage) async -> Void = { [weak self] event in
                    guard selected.usageTrackingEnabled else { return }
                    await self?.recordUsage(event, job: id, mode: .dictation, isRecovery: false, epoch: usageEpoch)
                }
                let review = try await decisionClient.evaluate(.init(transcript: candidate.originalText,
                    cleanedText: candidate.editedText,
                    termCandidates: [.init(id: "correction", original: entry.spoken, candidate: entry.written)]),
                    configuration: config, onUsage: collectUsage)
                guard current() else { return }
                let after = try await store.snapshot(retentionDays: preferences.retentionDays)
                guard current() else { return }
                guard after.learningCandidates.contains(candidate) else { cancelJevWorkflow(); return }
                jevCorrectionReview?.review = review
                jevCorrectionReview?.isProcessing = false
                let canSave = jevCorrectionReview?.canSave == true
                jevCorrectionReview?.status = canSave
                    ? L("같은 말의 표기 교정으로 보입니다. 사전에 저장할지 직접 확인해 주세요.", "This appears to be a spelling correction of the same term. Confirm whether to save it.")
                    : L("교정의 의미나 표기가 확실하지 않습니다. 원문을 비교한 뒤 필요하면 직접 등록해 주세요.", "The correction's meaning or spelling is uncertain. Compare the source and register it manually if needed.")
            } catch {
                guard current() else { return }
                jevCorrectionReview?.status = L("교정을 검토하지 못했습니다. 사전은 변경하지 않았습니다.", "Could not review the correction. The dictionary is unchanged.")
            }
        }
    }

    func saveReviewedCorrection(_ id: UUID, replacing previous: DictionaryEntry?) async {
        guard !AppLaunch.isPreview, let review = jevCorrectionReview, review.id == id, review.canSave,
              !isBusy, !decisionDictionaryOperationInProgress, let store, preferences.historyEnabled else { return }
        let epoch = decisionReviewEpoch
        decisionDictionaryOperationInProgress = true
        defer { decisionDictionaryOperationInProgress = false }
        do {
            let days = preferences.retentionDays
            let task = Task { try await store.applyReviewedLearningCandidate(review.candidate, entry: review.entry,
                expectedPrevious: previous, retentionDays: days) }
            decisionDictionaryTask = task
            defer { decisionDictionaryTask = nil }
            let result = try await task.value
            switch result {
            case .saved(let applied, let previous):
                lastDecisionDictionaryChange = (applied, previous); canUndoDecisionDictionarySave = true
                if epoch == decisionReviewEpoch { decisionProposalStatus = L("확인한 교정을 사전에 저장했습니다.", "Saved the confirmed correction to your dictionary.") }
            case .alreadyExists:
                if epoch == decisionReviewEpoch { decisionProposalStatus = L("같은 표기가 이미 있습니다.", "This spelling already exists.") }
            case .conflict, .stale:
                if epoch == decisionReviewEpoch { decisionProposalStatus = L("교정 후보나 사전이 변경되어 저장하지 않았습니다. 다시 확인해 주세요.", "The correction or dictionary changed. Nothing was saved. Review it again.") }
            }
            if epoch == decisionReviewEpoch, jevCorrectionReview?.id == id { jevCorrectionReview = nil }
            await refreshData()
        } catch is CancellationError { }
        catch { if epoch == decisionReviewEpoch { decisionProposalStatus = L("교정을 저장하지 못했습니다.", "Could not save the correction.") } }
    }

    enum AppError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
