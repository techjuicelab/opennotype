import AppKit
import AVFoundation
import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class AppStartupTests: XCTestCase {
    private final class Gate<T> {
        private var continuation: CheckedContinuation<T, Never>?
        var waiting = false
        func wait() async -> T {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; waiting = true
            }
        }
        func release(_ value: T) {
            waiting = false; continuation?.resume(returning: value); continuation = nil
        }
    }

    private func store() throws -> SecureStore {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-Startup-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SecureStore(directory: directory, backend: StartupMemorySecrets())
    }

    private func runtime() -> AppRuntime {
        var runtime = AppRuntime()
        runtime.frontmostApplication = { nil }
        runtime.readKey = { _ in nil }
        runtime.readStartupKey = { _ in "synthetic-startup-key" }
        runtime.accessibilityPermitted = { false }
        runtime.microphonePermission = { .notDetermined }
        runtime.capture = { _ in XCTFail("Startup must not capture an input target"); return nil }
        runtime.requestMicrophone = { XCTFail("Startup must not request microphone access"); return false }
        runtime.startRecording = { _ in XCTFail("Startup must not record audio") }
        return runtime
    }

    private func wait(until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func testAuthenticationWaitKeepsMainActorAvailableAndBlocksRecording() async throws {
        let stored = try store(), gate = Gate<SecureStore>()
        var runtime = runtime()
        runtime.openStore = { await gate.wait() }
        let model = AppModel(runtime: runtime, startServices: false)
        let preparing = Task { await model.prepareStartup() }
        try await wait(until: { gate.waiting })
        XCTAssertEqual(model.startupState, .loading)
        model.page = .settings // The UI can still respond while authentication waits.
        await model.toggle(.dictation)
        XCTAssertEqual(model.page, .settings)
        XCTAssertTrue(model.phase == .idle)
        XCTAssertTrue(model.notice?.contains("Keychain") == true)
        gate.release(stored)
        await preparing.value
        XCTAssertEqual(model.startupState, .ready)
        XCTAssertTrue(model.keySaved)
        XCTAssertTrue(model.textKeySaved)
    }

    func testFailedAuthenticationCanRetryWithoutReopeningOrResettingTheStore() async throws {
        let stored = try store()
        let original = HistoryEntry(mode: .dictation, originalText: "합성 원문", resultText: "합성 기록", provider: .groq)
        _ = try await stored.appendHistory(original)
        var runtime = runtime(), openCount = 0, denyKey = true
        runtime.openStore = { openCount += 1; return stored }
        runtime.readStartupKey = { _ in
            if denyKey { throw SecretStorageError.keychain(-25293) }
            return "synthetic-retry-key"
        }
        let model = AppModel(runtime: runtime, startServices: false)
        await model.prepareStartup()
        XCTAssertEqual(model.startupState, .failed)
        XCTAssertTrue(model.startupError?.contains("기존 데이터는 보존") == true)
        denyKey = false
        model.retryStartup()
        try await wait(until: { model.startupState != .loading })
        XCTAssertEqual(model.startupState, .ready)
        XCTAssertEqual(openCount, 1)
        let preserved = try await stored.history()
        XCTAssertEqual(preserved.map(\.id), [original.id])
        XCTAssertEqual(preserved.first?.resultText, original.resultText)
    }

    func testReturningFromSystemSettingsRefreshesBothPermissionsWithoutAPrompter() {
        var microphone: AVAuthorizationStatus = .notDetermined, accessibility = false
        var runtime = runtime()
        runtime.microphonePermission = { microphone }
        runtime.accessibilityPermitted = { accessibility }
        let model = AppModel(runtime: runtime, startServices: false)
        XCTAssertFalse(model.microphoneAllowed)
        XCTAssertFalse(model.accessibilityAllowed)
        microphone = .authorized; accessibility = true
        model.applicationDidBecomeActive()
        XCTAssertTrue(model.microphoneAllowed)
        XCTAssertTrue(model.accessibilityAllowed)
        XCTAssertFalse(model.microphonePermissionNeedsSettings)
        microphone = .denied; accessibility = false
        model.applicationDidBecomeActive()
        XCTAssertFalse(model.microphoneAllowed)
        XCTAssertFalse(model.accessibilityAllowed)
        XCTAssertTrue(model.microphonePermissionNeedsSettings)
    }

    func testSharedProviderReadsItsStartupKeyOnlyOnce() async throws {
        let stored = try store()
        var runtime = runtime(), reads: [AIProvider] = []
        runtime.openStore = { stored }
        runtime.readStartupKey = { provider in reads.append(provider); return "synthetic-shared-key" }
        var preferences = Preferences(); preferences.provider = .groq
        let model = AppModel(runtime: runtime, startServices: false, preferences: preferences)
        await model.prepareStartup()
        XCTAssertEqual(reads, [.groq])
        XCTAssertEqual(model.apiKeyDraft, model.textAPIKeyDraft)
        XCTAssertEqual(model.startupState, .ready)
    }

    func testLocalTranscriptionDoesNotAuthenticateAnUnusedCloudKey() async throws {
        let stored = try store()
        var runtime = runtime(), reads: [AIProvider] = []
        runtime.openStore = { stored }
        runtime.readStartupKey = { provider in reads.append(provider); return "synthetic-text-key" }
        var preferences = Preferences()
        preferences.provider = .groq; preferences.textProvider = .openRouter
        preferences.useLocalTranscription = true
        let model = AppModel(runtime: runtime, startServices: false, preferences: preferences)
        model.localState = .ready // No installed model or cache is accessed by this test.
        await model.prepareStartup()
        XCTAssertEqual(reads, [.openRouter])
        XCTAssertFalse(model.keySaved)
        XCTAssertTrue(model.textKeySaved)
    }

    func testCachedConfigurationsIgnoreUnsavedDraftsAndNeverReadKeychainAgain() async throws {
        var runtime = runtime(), reads = 0
        runtime.readKey = { _ in XCTFail("Production cache must not use synchronous Keychain reads"); return nil }
        runtime.readStartupKey = { provider in reads += 1; return "saved-\(provider.rawValue)" }
        var preferences = Preferences(); preferences.provider = .groq; preferences.textProvider = .openRouter
        let model = AppModel(store: try store(), runtime: runtime, startServices: false,
                             preferences: preferences, useCachedKeys: true)
        await model.prepareStartup()
        model.apiKeyDraft = "unsaved-audio"; model.textAPIKeyDraft = "unsaved-text"
        for _ in 0..<3 {
            XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "saved-groq")
            XCTAssertEqual(try model.configuration(provider: .openRouter).apiKey, "saved-openRouter")
        }
        XCTAssertEqual(reads, 2)
    }

    func testSwitchingAwayAndBackDuringReadOrSaveKeepsCorrectProviderDraft() async throws {
        let loadGate = Gate<String?>(), saveGate = Gate<Void>()
        var keys: [AIProvider: String] = [.groq: "saved-groq", .openAI: "saved-openAI", .openRouter: "saved-router"]
        var holdRead = false, holdSave = false, runtime = runtime()
        runtime.readStartupKey = { provider in
            if provider == .groq, holdRead { return await loadGate.wait() }
            return keys[provider]
        }
        runtime.saveStoredKey = { value, provider in
            if holdSave { await saveGate.wait() }
            keys[provider] = value
        }
        var preferences = Preferences(); preferences.provider = .groq; preferences.textProvider = .openRouter
        let model = AppModel(store: try store(), runtime: runtime, startServices: false,
                             preferences: preferences, useCachedKeys: true)
        await model.prepareStartup()
        holdRead = true; model.loadKey()
        try await wait(until: { loadGate.waiting })
        XCTAssertThrowsError(try model.configuration(provider: .groq))
        await model.toggle(.dictation) // No target capture or microphone is allowed while pending.
        XCTAssertTrue(model.phase == .idle)
        model.preferences.provider = .openAI; model.loadKey()
        try await wait(until: { !model.keyOperationsInProgress.contains(.openAI) })
        XCTAssertEqual(model.apiKeyDraft, "saved-openAI")
        model.preferences.provider = .groq; model.loadKey()
        XCTAssertEqual(model.apiKeyDraft, "")
        loadGate.release("fresh-groq")
        try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(model.apiKeyDraft, "fresh-groq")
        holdRead = false; holdSave = true
        model.apiKeyDraft = "new-groq"; model.saveKey()
        try await wait(until: { saveGate.waiting })
        model.preferences.provider = .openAI; model.loadKey()
        try await wait(until: { !model.keyOperationsInProgress.contains(.openAI) })
        model.preferences.provider = .groq; model.loadKey()
        saveGate.release(())
        try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(model.apiKeyDraft, "new-groq")
        XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "new-groq")
    }

    func testLateReadPreservesEditedDraftAndSaveDeleteFailuresPreserveSavedCache() async throws {
        let gate = Gate<String?>()
        var holdRead = false, failSave = true, failDelete = true, runtime = runtime()
        runtime.readStartupKey = { provider in
            if holdRead { return await gate.wait() }
            return "saved-\(provider.rawValue)"
        }
        runtime.saveStoredKey = { _, _ in if failSave { throw SecretStorageError.keychain(-25293) } }
        runtime.deleteStoredKey = { _ in if failDelete { throw SecretStorageError.keychain(-25293) } }
        var preferences = Preferences(); preferences.provider = .groq
        let model = AppModel(store: try store(), runtime: runtime, startServices: false,
                             preferences: preferences, useCachedKeys: true)
        await model.prepareStartup()
        holdRead = true; model.loadKey()
        try await wait(until: { gate.waiting })
        model.apiKeyDraft = "user-edit"
        gate.release("fresh-saved")
        try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(model.apiKeyDraft, "user-edit")
        XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "fresh-saved")
        model.saveKey(); try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "fresh-saved")
        XCTAssertTrue(model.keyDraftIsChanged)
        failSave = false; model.saveKey(); try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "user-edit")
        model.apiKeyDraft = ""; model.saveKey(); try await wait(until: { !model.keyOperationInProgress })
        XCTAssertEqual(try model.configuration(provider: .groq).apiKey, "user-edit")
        failDelete = false; model.saveKey(); try await wait(until: { !model.keyOperationInProgress })
        XCTAssertThrowsError(try model.configuration(provider: .groq))
        XCTAssertFalse(model.keySaved)
        XCTAssertFalse(model.textKeySaved)
    }

    func testRecoveryPreparesOlderProvidersWithoutChangingSelectedStageDrafts() async throws {
        var runtime = runtime(), reads: [AIProvider] = []
        runtime.readStartupKey = { provider in reads.append(provider); return "saved-\(provider.rawValue)" }
        var preferences = Preferences(); preferences.provider = .groq; preferences.textProvider = .openRouter
        let model = AppModel(store: try store(), runtime: runtime, startServices: false,
                             preferences: preferences, useCachedKeys: true)
        await model.prepareStartup()
        try await model.prepareStoredKeys(for: [.openAI, .anthropic])
        XCTAssertEqual(Set(reads), [.groq, .openRouter, .openAI, .anthropic])
        XCTAssertEqual(try model.configuration(provider: .openAI).apiKey, "saved-openAI")
        XCTAssertEqual(try model.configuration(provider: .anthropic).apiKey, "saved-anthropic")
        XCTAssertEqual(model.apiKeyDraft, "saved-groq")
        XCTAssertEqual(model.textAPIKeyDraft, "saved-openRouter")
    }

    func testCancelledRecoveryDoesNotContinueAfterDelayedHistoricalKeyRead() async throws {
        let gate = Gate<String?>()
        var runtime = runtime()
        runtime.readStartupKey = { provider in
            if provider == .openAI { return await gate.wait() }
            return "saved-\(provider.rawValue)"
        }
        var preferences = Preferences(); preferences.provider = .groq; preferences.textProvider = .openRouter
        let model = AppModel(store: try store(), runtime: runtime, startServices: false,
                             preferences: preferences, useCachedKeys: true)
        await model.prepareStartup()
        let recovery = Task { try await model.prepareStoredKeys(for: [.openAI]) }
        try await wait(until: { gate.waiting })
        recovery.cancel(); gate.release("saved-openAI")
        do { try await recovery.value; XCTFail("Cancelled recovery must not continue") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(model.apiKeyDraft, "saved-groq")
        XCTAssertEqual(model.textAPIKeyDraft, "saved-openRouter")
    }
}

private final class StartupMemorySecrets: SecretBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
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
