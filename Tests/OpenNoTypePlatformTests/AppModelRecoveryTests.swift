import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class AppModelRecoveryTests: KoreanPresentationTestCase {
    func testDamagedPreferencesPreventStoreOpeningKeyReadsAndRecording() async throws {
        let defaults = try isolatedDefaults()
        let damaged = Data("{broken".utf8)
        defaults.set(damaged, forKey: "preferences.v1")
        var runtime = AppRuntime()
        runtime.preferencesDefaults = defaults
        runtime.accessibilityPermitted = { true }; runtime.microphonePermission = { .authorized }
        runtime.readKey = { _ in XCTFail("Recovery must not read a provider credential"); return nil }
        runtime.openStore = { XCTFail("Opening a store can prune before recovery"); throw URLError(.unknown) }
        runtime.readStartupKey = { _ in XCTFail("Recovery must not read startup keys"); return nil }
        runtime.capture = { _ in XCTFail("Recovery must not capture another app"); return nil }
        runtime.startRecording = { _ in XCTFail("Recovery must not start a microphone") }
        let model = AppModel(runtime: runtime, startServices: false,
                             preferences: Preferences.load(from: defaults), useCachedKeys: true)
        await model.prepareStartup()
        XCTAssertEqual(model.startupState, .failed)
        XCTAssertTrue(model.preferencesRecoveryRequired)
        await model.toggle(.dictation)
        XCTAssertTrue(model.phase == .idle)
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), damaged)
    }

    func testRecoveryRefreshAndBlockedMutationsKeepFortyDayOldHistory() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(Data("[]".utf8), forKey: "preferences.v1")
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-Recovery-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try SecureStore(directory: root, backend: RecoveryMemorySecrets())
        _ = try await store.snapshot(retentionDays: -1)
        var old = HistoryEntry(mode: .dictation, originalText: "합성 보관 원문", resultText: "합성 보관 결과", provider: .groq)
        old.createdAt = Date().addingTimeInterval(-40 * 86_400)
        _ = try await store.appendHistory(old)
        var runtime = AppRuntime(); runtime.preferencesDefaults = defaults
        runtime.readKey = { _ in nil }
        runtime.accessibilityPermitted = { true }; runtime.microphonePermission = { .authorized }
        let model = AppModel(store: store, runtime: runtime, startServices: false,
                             preferences: Preferences.load(from: defaults), useCachedKeys: true)
        await model.refreshData()
        XCTAssertEqual(model.history.map(\.id), [old.id])
        model.preferences.retentionDays = 30
        model.preferences.provider = .anthropic
        model.preferences.interfaceLanguage = .korean
        model.preferences.textModels["openRouter"] = "synthetic-other-model"
        XCTAssertEqual(model.preferences.retentionDays, -1)
        XCTAssertEqual(model.preferences.provider, .openAI)
        XCTAssertEqual(model.preferences.interfaceLanguage, .english)
        XCTAssertTrue(model.preferences.textModels.isEmpty)
        await model.deleteHistory()
        await model.refreshData()
        XCTAssertEqual(model.history.map(\.id), [old.id])
        let current = try await store.snapshotPreservingRetention()
        XCTAssertEqual(current.history.map(\.id), [old.id])
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), Data("[]".utf8))
    }

    func testExplicitRestoreResumesWithPreviousProviderAndRetention() async throws {
        let defaults = try isolatedDefaults()
        var original = Preferences.koreanForTesting
        original.provider = .groq; original.textProvider = .openRouter; original.retentionDays = -1
        original.textModels["openRouter"] = "synthetic-kept-model"
        XCTAssertTrue(original.save(to: defaults))
        let damaged = Data("{broken".utf8)
        defaults.set(damaged, forKey: "preferences.v1")
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OpenNoType-Restore-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try SecureStore(directory: root, backend: RecoveryMemorySecrets())
        var runtime = AppRuntime(); runtime.preferencesDefaults = defaults
        runtime.openStore = { store }; runtime.readKey = { _ in nil }
        runtime.readStartupKey = { _ in "synthetic-restored-key" }
        runtime.accessibilityPermitted = { true }; runtime.microphonePermission = { .authorized }
        let model = AppModel(runtime: runtime, startServices: false,
                             preferences: Preferences.load(from: defaults), useCachedKeys: true)
        await model.prepareStartup()
        XCTAssertTrue(model.canRestorePreviousPreferences)
        model.restorePreviousPreferences()
        for _ in 0..<300 where model.startupState == .loading { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.startupState, .ready)
        XCTAssertFalse(model.preferencesRecoveryRequired)
        XCTAssertEqual(model.preferences.provider, .groq)
        XCTAssertEqual(model.preferences.textModel, "synthetic-kept-model")
        XCTAssertEqual(model.preferences.retentionDays, -1)
        XCTAssertEqual(defaults.data(forKey: Preferences.recoveryOriginalKey), damaged)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "OpenNoType-Recovery-Defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}

private final class RecoveryMemorySecrets: SecretBackend, @unchecked Sendable {
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
