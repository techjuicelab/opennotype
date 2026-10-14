import XCTest
import OpenNoTypeCore
@testable import OpenNoType

@MainActor
final class HotkeyRegistrationTests: XCTestCase {
    func testPromptTestShortcutsRegisterWithoutOverlappingNormalDefaults() throws {
        let testBindings = HotkeyBinding.promptTestDefaults
        XCTAssertEqual(testBindings.count, HotkeyBinding.defaults.count)
        XCTAssertFalse(testBindings.contains { HotkeyBinding.defaults.contains($0) })
        let backend = FakeHotkeyBackend(failures: [])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        try manager.register(testBindings)
        XCTAssertEqual(manager.registeredBindings, testBindings)
        XCTAssertEqual(backend.active.count, testBindings.count)
    }

    func testInitialFailureDoesNotSilentlyInstallDefaults() throws {
        let backend = FakeHotkeyBackend(failures: [2])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        XCTAssertThrowsError(try manager.register(custom)) { error in
            XCTAssertEqual(error as? HotkeyManager.HotkeyError, .conflict(self.custom[1].label, restored: false))
        }
        XCTAssertNil(manager.registeredBindings)
        XCTAssertEqual(backend.calls, 2)
        XCTAssertTrue(backend.active.isEmpty)
    }

    func testRegistrationFailureRestoresActualPreviousBindings() throws {
        let backend = FakeHotkeyBackend(failures: [custom.count + 2])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        try manager.register(custom)
        XCTAssertThrowsError(try manager.register(HotkeyBinding.defaults)) { error in
            XCTAssertEqual(error as? HotkeyManager.HotkeyError, .conflict(HotkeyBinding.defaults[1].label, restored: true))
        }
        XCTAssertEqual(manager.registeredBindings, custom)
        XCTAssertEqual(backend.active.count, custom.count)
    }

    func testRollbackFailureLeavesNoPhantomBindings() throws {
        let backend = FakeHotkeyBackend(failures: [custom.count + 2, custom.count + 4])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        try manager.register(custom)
        XCTAssertThrowsError(try manager.register(HotkeyBinding.defaults)) { error in
            XCTAssertEqual(error as? HotkeyManager.HotkeyError, .rollbackFailed(HotkeyBinding.defaults[1].label))
        }
        XCTAssertNil(manager.registeredBindings)
        XCTAssertTrue(backend.active.isEmpty)
        backend.failures = []
        try manager.register(custom)
        XCTAssertEqual(manager.registeredBindings, custom)
        XCTAssertEqual(backend.active.count, custom.count)
    }

    func testDuplicateValidationKeepsPreviouslyRegisteredShortcuts() throws {
        let backend = FakeHotkeyBackend(failures: [])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        try manager.register(custom)
        XCTAssertThrowsError(try manager.register(Array(repeating: custom[0], count: custom.count)))
        XCTAssertEqual(manager.registeredBindings, custom)
        XCTAssertEqual(backend.calls, custom.count)
    }

    func testPromptShortcutIsRegisteredAlongsideExistingModes() throws {
        let backend = FakeHotkeyBackend(failures: [])
        let manager = HotkeyManager(backend: backend, installSystemHandler: false)
        try manager.register(HotkeyBinding.defaults)
        XCTAssertEqual(manager.registeredBindings, HotkeyBinding.defaults)
        XCTAssertEqual(backend.active.count, 4)
        XCTAssertThrowsError(try manager.register(Array(HotkeyBinding.defaults.prefix(3))))
        XCTAssertEqual(manager.registeredBindings, HotkeyBinding.defaults)
    }

    func testSemanticHoldCallbacksDeferReleaseUntilRecordingBegins() {
        let manager = HotkeyManager(backend: FakeHotkeyBackend(failures: []), installSystemHandler: false)
        manager.activationMode = .hold
        var actions: [ShortcutActivationEvent] = []
        manager.onActivation = { actions.append(.init(mode: $0, action: $1)) }
        manager.handleKeyEvent(.dictation, isPressed: true, at: 0)
        manager.handleKeyEvent(.dictation, isPressed: false, at: 0.1)
        XCTAssertEqual(actions, [.init(mode: .dictation, action: .start)])
        manager.updateRecordingState(.starting(.dictation))
        manager.updateRecordingState(.recording(.dictation))
        XCTAssertEqual(actions, [.init(mode: .dictation, action: .start), .init(mode: .dictation, action: .stop)])
    }

    func testDefaultToggleRetainsLegacyOnPressCallback() {
        let manager = HotkeyManager(backend: FakeHotkeyBackend(failures: []), installSystemHandler: false)
        var modes: [InputMode] = []
        manager.onPress = { modes.append($0) }
        manager.handleKeyEvent(.prompt, isPressed: true, at: 0)
        manager.handleKeyEvent(.prompt, isPressed: true, at: 0.5)
        manager.handleKeyEvent(.prompt, isPressed: false, at: 1)
        XCTAssertEqual(manager.activationMode, .toggle)
        XCTAssertEqual(modes, [.prompt])
    }

    func testSemanticCallbackDoesNotAlsoInvokeLegacyCallback() {
        let manager = HotkeyManager(backend: FakeHotkeyBackend(failures: []), installSystemHandler: false)
        var legacyCalls = 0, semanticCalls = 0
        manager.onPress = { _ in legacyCalls += 1 }
        manager.onActivation = { _, _ in semanticCalls += 1 }
        manager.handleKeyEvent(.rewrite, isPressed: true, at: 0)
        XCTAssertEqual(semanticCalls, 1)
        XCTAssertEqual(legacyCalls, 0)
    }

    private var custom: [HotkeyBinding] {
        [.init(keyCode: 0, modifiers: 2048), .init(keyCode: 1, modifiers: 2048), .init(keyCode: 2, modifiers: 2048), .init(keyCode: 3, modifiers: 2048)]
    }
}

@MainActor
private final class FakeHotkeyBackend: HotkeyRegistrationBackend {
    var failures: Set<Int>
    var calls = 0
    var active: [UUID: HotkeyBinding] = [:]
    init(failures: Set<Int>) { self.failures = failures }
    func register(_ binding: HotkeyBinding, index: Int) throws -> UUID {
        calls += 1
        if failures.contains(calls) { throw HotkeyManager.HotkeyError.conflict(binding.label, restored: false) }
        let token = UUID(); active[token] = binding; return token
    }
    func unregister(_ token: UUID) { active[token] = nil }
}
