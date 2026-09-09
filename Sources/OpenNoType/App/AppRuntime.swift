import AppKit
import AVFoundation
import OpenNoTypeCore

/// System boundaries are injectable so start/cancel races can be tested without permission prompts,
/// microphone access, global shortcuts, the user's preferences, or their Keychain.
@MainActor
struct AppRuntime {
    var frontmostApplication: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    var capture: (Set<String>) async -> InputTarget? = { await TextInsertion.capture(allowedContextApps: $0) }
    var accessibilityPermitted: () -> Bool = { TextInsertion.permitted }
    var secureInputActive: () -> Bool = { TextInsertion.secureInputActive }
    var microphonePermission: () -> AVAuthorizationStatus = { AudioRecorder.permission }
    var requestMicrophone: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    var readKey: (AIProvider) throws -> String? = { try KeychainSecrets.read(for: $0) }
    var makeTemporaryAudioURL: () throws -> URL = { try TemporaryAudioFiles.makeURL() }
    var startRecording: ((TimeInterval) async throws -> Void)?
    var stopRecording: (() -> URL?)?
    var recordingPeakDB: (() -> Float)?
}
