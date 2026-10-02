import AppKit
import AVFoundation
import OpenNoTypeCore

/// System boundaries are injectable so start/cancel races can be tested without permission prompts,
/// microphone access, global shortcuts, the user's preferences, or their Keychain.
@MainActor
struct AppRuntime {
    var frontmostApplication: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    var capture: (Set<String>) async -> InputTarget? = { await TextInsertion.capture(allowedContextApps: $0) }
    var insertText: (String, InputTarget, Bool, @escaping @MainActor () -> Bool) async -> InsertionOutcome = {
        await TextInsertion.insertOutcome($0, at: $1, requiresUnchangedTarget: $2, isCancelled: $3)
    }
    var accessibilityPermitted: () -> Bool = { TextInsertion.permitted }
    var hotkeyConflictWarnings: ([HotkeyBinding]) -> [String] = { HotkeyConflicts.warnings(for: $0) }
    var secureInputActive: () -> Bool = { TextInsertion.secureInputActive }
    var microphonePermission: () -> AVAuthorizationStatus = { AudioRecorder.permission }
    var requestMicrophone: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    var readKey: (AIProvider) throws -> String? = { try KeychainSecrets.read(for: $0) }
    /// Keychain can wait for the system authentication dialog. First launch must keep its
    /// window and permission controls responsive while that synchronous system call waits.
    var openStore: () async throws -> SecureStore = {
        try await Task.detached(priority: .userInitiated) { try SecureStore() }.value
    }
    var readStartupKey: (AIProvider) async throws -> String? = { provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.read(for: provider) }.value
    }
    var saveStoredKey: (String, AIProvider) async throws -> Void = { value, provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.save(value, for: provider) }.value
    }
    var deleteStoredKey: (AIProvider) async throws -> Void = { provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.delete(for: provider) }.value
    }
    var readDecisionKey: (DecisionProvider) async throws -> String? = { provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.readDecisionKey(for: provider) }.value
    }
    var saveDecisionKey: (String, DecisionProvider) async throws -> Void = { value, provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.saveDecisionKey(value, for: provider) }.value
    }
    var deleteDecisionKey: (DecisionProvider) async throws -> Void = { provider in
        try await Task.detached(priority: .userInitiated) { try KeychainSecrets.deleteDecisionKey(for: provider) }.value
    }
    var makeTemporaryAudioURL: () throws -> URL = { try TemporaryAudioFiles.makeURL() }
    var startRecording: ((TimeInterval) async throws -> Void)?
    var stopRecording: (() -> URL?)?
    var recordingPeakDB: (() -> Float)?
}
