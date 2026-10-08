import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class PromptTestInstallationTests: XCTestCase {
    func testBatchKeySetupValidatesAllValuesBeforeWriting() {
        var reads = 0, writes = 0
        XCTAssertThrowsError(try AppLaunch.importPromptTestKeys([.groq: "synthetic-groq", .openRouter: "  "],
            read: { _ in reads += 1; return nil }, save: { _, _ in writes += 1 }))
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(writes, 0)
    }

    func testBatchKeySetupKeepsConfiguredKeysAndSavesOnlyMissingProvider() throws {
        var saved: [AIProvider: String] = [:]
        try AppLaunch.importPromptTestKeys([.groq: "synthetic-groq", .openRouter: "synthetic-router"],
            read: { $0 == .groq ? "existing-test-key" : nil }, save: { saved[$1] = $0 })
        XCTAssertNil(saved[.groq])
        XCTAssertEqual(saved[.openRouter], "synthetic-router")
    }

    func testFreshTestSettingsSelectPromptProvidersWithoutChangingAnotherDomain() throws {
        let testName = "app.opennotype.tests.prompt-installation.\(UUID().uuidString)"
        let normalName = "app.opennotype.tests.normal-installation.\(UUID().uuidString)"
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: testName))
        let normalDefaults = try XCTUnwrap(UserDefaults(suiteName: normalName))
        defer {
            testDefaults.removePersistentDomain(forName: testName)
            normalDefaults.removePersistentDomain(forName: normalName)
        }
        var normal = Preferences()
        normal.interfaceLanguage = .english
        normal.provider = .anthropic
        XCTAssertTrue(normal.save(to: normalDefaults))

        let test = AppLaunch.promptTestPreferences(from: testDefaults)
        XCTAssertEqual(test.interfaceLanguage, .korean)
        XCTAssertEqual(test.provider, .groq)
        XCTAssertEqual(test.effectiveTextProvider, .openRouter)
        XCTAssertEqual(test.textModel, "openai/gpt-oss-120b")
        XCTAssertEqual(test.hotkeys, HotkeyBinding.promptTestDefaults)
        XCTAssertFalse(test.automaticLearningEnabled)
        XCTAssertEqual(Preferences.load(from: normalDefaults).provider, .anthropic)
        XCTAssertEqual(Preferences.load(from: normalDefaults).interfaceLanguage, .english)
    }

    func testRelaunchPreservesSavedTestSettings() throws {
        let name = "app.opennotype.tests.prompt-relaunch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var saved = Preferences()
        saved.provider = .openAI
        saved.textProvider = .anthropic
        saved.interfaceLanguage = .english
        saved.hotkeys = HotkeyBinding.defaults
        XCTAssertTrue(saved.save(to: defaults))
        let restored = AppLaunch.promptTestPreferences(from: defaults)
        XCTAssertEqual(restored.provider, .openAI)
        XCTAssertEqual(restored.effectiveTextProvider, .anthropic)
        XCTAssertEqual(restored.interfaceLanguage, .english)
        XCTAssertEqual(restored.hotkeys, saved.hotkeys)
    }

    func testCorruptTestSettingsRemainInRecovery() throws {
        let name = "app.opennotype.tests.prompt-recovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let corrupt = Data("unreadable preferences".utf8)
        defaults.set(corrupt, forKey: "preferences.v1")
        let restored = AppLaunch.promptTestPreferences(from: defaults)
        XCTAssertTrue(restored.recoveryState.requiresRecovery)
        XCTAssertEqual(restored.retentionDays, -1)
        XCTAssertEqual(defaults.data(forKey: "preferences.v1"), corrupt)
    }
}
