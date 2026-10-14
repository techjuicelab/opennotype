import AppKit
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class QuickDictationTests: KoreanPresentationTestCase {
    private func environment(beforeVaultCommit: (@Sendable () throws -> Void)? = nil) throws -> (SecureStore, AppRuntime, ProviderClient, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickDictation-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try SecureStore(directory: directory.appendingPathComponent("store"), backend: QuickMemorySecrets(),
                                    beforeVaultCommit: beforeVaultCommit)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = directory.appendingPathComponent("sample.wav")
        try Data([82, 73, 70, 70]).write(to: audio)
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.accessibilityPermitted = { true }; runtime.secureInputActive = { false }
        runtime.microphonePermission = { .authorized }
        runtime.hotkeyConflictWarnings = { _ in [] }
        runtime.readKey = { _ in XCTFail("Quick dictation must not read provider credentials"); return nil }
        runtime.readStartupKey = { _ in XCTFail("Quick retry must not read provider credentials"); return nil }
        runtime.capture = { _ in InputTarget(pid: 41001, bundleID: "test.editor", element: nil,
            originalValue: nil, range: nil, selectedText: nil, context: nil) }
        runtime.startRecording = { _ in }; runtime.stopRecording = { audio }
        runtime.recordingElapsed = { 1 }; runtime.recordingPeakDB = { -20 }
        runtime.prepareLocalModel = { _, download in XCTAssertFalse(download); return true }
        runtime.makeTemporaryAudioURL = { directory.appendingPathComponent("retry-\(UUID()).wav") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuickForbiddenNetwork.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return (store, runtime, ProviderClient(session: session), audio)
    }
    private var fastPreferences: Preferences {
        var preferences = Preferences.koreanForTesting
        preferences.dictationProcessing = .onDeviceVerbatim
        preferences.decisionReviewMode = .repair
        preferences.automaticLearningEnabled = false
        return preferences
    }
    func testQuickDictationTypesExactMixedTranscriptWithoutKeysOrAIRequests() async throws {
        let (store, base, client, audio) = try environment()
        var runtime = base
        let source = "음, OpenRouter API를 0.2.8에서 써요. 15,000원이에요."
        runtime.transcribeLocal = { _, _, _, model in XCTAssertEqual(model, .largeV3); return source }
        var inserted: [String] = []
        runtime.insertText = { text, _, _, _ in inserted.append(text); return .confirmed(.paste) }
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: fastPreferences, useCachedKeys: true)
        defer { model.cancel() }
        XCTAssertNil(model.requiredJevIssue)
        await model.toggle(.dictation)
        XCTAssertEqual(model.phase, .recording)
        let finished = expectation(description: "Quick dictation completes")
        model.onPhaseChange = { if model.phase == .idle { finished.fulfill() } }
        model.stop()
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil
        XCTAssertEqual(inserted, [source]); XCTAssertEqual(model.result, source)
        XCTAssertEqual(model.recentDecisionTarget?.transcript, source)
        XCTAssertEqual(model.recentDecisionTarget?.output, source)
        XCTAssertNil(model.decisionReviewSummary)
        let history = try await store.history()
        XCTAssertEqual(history.last?.originalText, source)
        XCTAssertEqual(history.last?.resultText, source)
        XCTAssertEqual(history.last?.skippedTextProcessing, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }
    func testQuickFailureRetryPreservesOriginalOfflineRouteAndModel() async throws {
        let (store, base, client, _) = try environment()
        var runtime = base
        var shouldFail = true
        var models: [LocalSpeechModel] = []
        runtime.transcribeLocal = { _, _, _, model in
            models.append(model)
            if shouldFail { throw LocalAudioError.noSpeech }
            return "GitHub에서 PR 29를 확인해요."
        }
        runtime.insertText = { _, _, _, _ in XCTFail("Recovery is copy-only"); return .confirmed(.paste) }
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: fastPreferences, useCachedKeys: true)
        defer { model.cancel() }
        await model.toggle(.dictation)
        let failed = expectation(description: "Failure saved")
        model.onPhaseChange = { if model.phase == .idle { failed.fulfill() } }
        model.stop(); await fulfillment(of: [failed], timeout: 5); model.onPhaseChange = nil
        let failures = try await store.failures()
        let item = try XCTUnwrap(failures.first)
        XCTAssertEqual(item.skippedTextProcessing, true); XCTAssertEqual(item.localSpeechModel, LocalSpeechModel.largeV3.rawValue)
        model.preferences.dictationProcessing = .aiCleanup
        model.preferences.localSpeechModel = .base
        shouldFail = false
        let recovered = expectation(description: "Quick retry completes")
        model.onPhaseChange = { if model.phase == .idle { recovered.fulfill() } }
        model.retry(item)
        await fulfillment(of: [recovered], timeout: 5); model.onPhaseChange = nil
        XCTAssertEqual(models, [.largeV3, .largeV3])
        XCTAssertEqual(model.result, "GitHub에서 PR 29를 확인해요.")
        let remaining = try await store.failures(); XCTAssertTrue(remaining.isEmpty)
    }
    func testFailureDiscoveredDuringStopSavesRecoveryWithoutRecognitionOrTyping() async throws {
        let (store, base, client, audio) = try environment()
        let originalAudio = try Data(contentsOf: audio)
        var runtime = base
        var finalizationFailure: Error?
        var stops = 0
        runtime.stopRecording = {
            stops += 1
            finalizationFailure = AudioRecorder.RecordingError.captureInterrupted
            return audio
        }
        runtime.recordingFailure = { finalizationFailure }
        runtime.transcribeLocal = { _, _, _, _ in
            XCTFail("An incomplete recording must not reach recognition"); return "앞부분만 인식됨"
        }
        runtime.insertText = { _, _, _, _ in
            XCTFail("An incomplete recording must not be typed"); return .confirmed(.paste)
        }
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: fastPreferences, useCachedKeys: true)
        defer { model.cancel() }
        await model.toggle(.dictation)
        XCTAssertEqual(model.phase, .recording)
        XCTAssertNil(finalizationFailure)
        let finished = expectation(description: "Interrupted audio is saved for recovery")
        model.onPhaseChange = { if model.phase == .idle { finished.fulfill() } }
        model.stop()
        await fulfillment(of: [finished], timeout: 5)
        model.onPhaseChange = nil
        XCTAssertEqual(stops, 1, "Recover the already finalized file without stopping twice")
        let failures = try await store.failures()
        let failure = try XCTUnwrap(failures.first)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failure.skippedTextProcessing, true)
        XCTAssertEqual(failure.localSpeechModel, LocalSpeechModel.largeV3.rawValue)
        let savedAudio = try await store.failureAudio(id: failure.id)
        XCTAssertEqual(savedAudio, originalAudio)
        let history = try await store.history()
        XCTAssertTrue(history.isEmpty)
        XCTAssertTrue(model.result.isEmpty)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testCancelBeforeInterruptedRecoveryStartsDoesNotSaveOrType() async throws {
        let (store, base, client, audio) = try environment()
        var runtime = base
        runtime.recordingFailure = { AudioRecorder.RecordingError.captureInterrupted }
        runtime.transcribeLocal = { _, _, _, _ in
            XCTFail("Cancelled incomplete audio must not be recognized"); return ""
        }
        runtime.insertText = { _, _, _, _ in
            XCTFail("Cancelled incomplete audio must not be typed"); return .confirmed(.paste)
        }
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: fastPreferences, useCachedKeys: true)
        await model.toggle(.dictation)
        model.stop()
        model.cancel()
        let disposed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: audio.path)
        }, object: nil)
        await fulfillment(of: [disposed], timeout: 5)
        let failures = try await store.failures()
        let history = try await store.history()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.result.isEmpty)
    }

    func testCancelDuringRecoveryCommitRemovesOnlyThisInterruptedRecording() async throws {
        let committing = expectation(description: "Interrupted recording reaches its atomic commit")
        let gate = QuickCommitGate(entered: committing)
        defer { gate.release.signal() }
        let (store, base, client, audio) = try environment(beforeVaultCommit: { try gate.beforeCommit() })
        let previous = FailedRecording(mode: .dictation, provider: .openRouter, targetLanguage: "English",
                                       transcriptionModel: "previous-stt", textModel: "previous-text",
                                       usedLocalTranscription: true, usedSpeakerFilter: false)
        try await store.saveFailure(previous, audio: Data("previous recording".utf8))
        var runtime = base
        runtime.recordingFailure = { AudioRecorder.RecordingError.captureInterrupted }
        runtime.transcribeLocal = { _, _, _, _ in
            XCTFail("Incomplete audio must not reach recognition"); return ""
        }
        runtime.insertText = { _, _, _, _ in
            XCTFail("Incomplete audio must not be typed"); return .confirmed(.paste)
        }
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: fastPreferences, useCachedKeys: true)
        await model.toggle(.dictation)
        gate.arm()
        model.stop()
        await fulfillment(of: [committing], timeout: 3)
        model.cancel()
        gate.release.signal()
        let disposed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: audio.path)
        }, object: nil)
        await fulfillment(of: [disposed], timeout: 5)
        let failures = try await store.failures()
        XCTAssertEqual(failures.map(\.id), [previous.id])
        XCTAssertTrue(model.failures.allSatisfy { $0.id == previous.id })
        let previousAudio = try await store.failureAudio(id: previous.id)
        XCTAssertEqual(previousAudio, Data("previous recording".utf8))
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.result.isEmpty)
    }
    func testFastPreferenceNeverBypassesTranslationKeyRequirements() async throws {
        let (store, base, client, _) = try environment()
        var runtime = base
        runtime.startRecording = { _ in XCTFail("Missing translation keys must prevent recording") }
        var preferences = fastPreferences
        preferences.dictationOutputLanguage = .english
        preferences.decisionReviewMode = .off
        let model = AppModel(store: store, runtime: runtime, client: client,
                             startServices: false, preferences: preferences, useCachedKeys: true)
        await model.toggle(.dictation)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNotNil(model.error)
    }
    func testLegacyPreferencesKeepExistingRecordingAndProcessingBehavior() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(preferences.shortcutActivation, .toggle)
        XCTAssertEqual(preferences.dictationProcessing, .aiCleanup)
        XCTAssertEqual(preferences.localSpeechModel, .largeV3)
        XCTAssertEqual(preferences.localModelUnloadPolicy, .never)
        XCTAssertNil(preferences.inputDeviceUID)
        XCTAssertFalse(preferences.localPreviewEnabled)
        XCTAssertFalse(preferences.recordingAudioFeedback)
        XCTAssertFalse(preferences.muteWhileRecording)
    }
    func testQuickDictationKeepsCapturedModelAndProcessingWhenSettingsChangeDuringCapture() async throws {
        let (store, base, client, _) = try environment()
        var runtime = base
        var app: AppModel!
        let originalCapture = runtime.capture
        runtime.capture = { allowed in
            app.preferences.dictationProcessing = .aiCleanup
            app.preferences.localSpeechModel = .base
            return await originalCapture(allowed)
        }
        runtime.prepareLocalModel = { model, _ in XCTAssertEqual(model, .small); return true }
        runtime.transcribeLocal = { _, _, _, model in XCTAssertEqual(model, .small); return "OpenNoType을 확인해요." }
        var insertions: [String] = []
        runtime.insertText = { text, _, _, _ in insertions.append(text); return .confirmed(.paste) }
        var preferences = fastPreferences; preferences.localSpeechModel = .small
        app = AppModel(store: store, runtime: runtime, client: client,
                       startServices: false, preferences: preferences, useCachedKeys: true)
        defer { app.cancel() }
        await app.toggle(.dictation)
        let done = expectation(description: "Captured quick route completes")
        app.onPhaseChange = { if app.phase == .idle { done.fulfill() } }
        app.stop(); await fulfillment(of: [done], timeout: 5); app.onPhaseChange = nil
        XCTAssertEqual(insertions, ["OpenNoType을 확인해요."])
    }
    func testCancelledLocalRecognitionNeverDeliversItsLateTranscript() async throws {
        let (store, base, client, audio) = try environment()
        var runtime = base
        var app: AppModel!
        runtime.transcribeLocal = { _, _, _, _ in app.cancel(); return "입력되면 안 되는 늦은 결과" }
        runtime.insertText = { _, _, _, _ in XCTFail("Cancelled recognition must not type"); return .confirmed(.paste) }
        app = AppModel(store: store, runtime: runtime, client: client,
                       startServices: false, preferences: fastPreferences, useCachedKeys: true)
        await app.toggle(.dictation)
        let done = expectation(description: "Recognition cancels")
        app.onPhaseChange = { if app.phase == .idle { done.fulfill() } }
        app.stop(); await fulfillment(of: [done], timeout: 5); app.onPhaseChange = nil
        let history = try await store.history()
        XCTAssertTrue(history.isEmpty); XCTAssertTrue(app.result.isEmpty)
        let disposed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: audio.path)
        }, object: nil)
        await fulfillment(of: [disposed], timeout: 5)
    }
}

private final class QuickForbiddenNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Quick dictation must never issue an HTTP request")
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}
private final class QuickMemorySecrets: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service + account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + account] = data
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[service + account] = nil
    }
}

private final class QuickCommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private let entered: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    init(entered: XCTestExpectation) { self.entered = entered }
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func beforeCommit() throws {
        lock.lock()
        let shouldWait = armed
        armed = false
        lock.unlock()
        guard shouldWait else { return }
        entered.fulfill()
        guard release.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
    }
}
