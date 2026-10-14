import AppKit
import CoreAudio
import Foundation

@MainActor
enum RecordingFeedback {
    static func started() { NSSound(named: NSSound.Name("Tink"))?.play() }
    static func stopped() { NSSound(named: NSSound.Name("Pop"))?.play() }
}

/// Injectable device access keeps the ownership policy testable without changing system sound.
struct RecordingMuteAccess {
    var read: () throws -> Bool
    var write: (Bool) throws -> Void
    var observe: (@escaping (Bool) -> Void) throws -> (() -> Void)

    static func systemOutput() throws -> Self {
        let device = try AudioDevices.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { throw AudioRecorder.RecordingError.cannotMuteSystemAudio }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            throw AudioRecorder.RecordingError.cannotMuteSystemAudio
        }
        let queue = DispatchQueue(label: "app.opennotype.recording-output-mute")
        let read: () throws -> Bool = {
            var location = address
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            try AudioDevices.check(AudioObjectGetPropertyData(device, &location, 0, nil, &size, &value))
            return value != 0
        }
        return Self(read: read, write: { muted in
            var location = address
            var value: UInt32 = muted ? 1 : 0
            try AudioDevices.check(AudioObjectSetPropertyData(device, &location, 0, nil,
                                                              UInt32(MemoryLayout<UInt32>.size), &value))
        }, observe: { changed in
            var location = address
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                if let muted = try? read() { changed(muted) }
            }
            try AudioDevices.check(AudioObjectAddPropertyListenerBlock(device, &location, queue, listener))
            return {
                var location = address
                _ = AudioObjectRemovePropertyListenerBlock(device, &location, queue, listener)
            }
        })
    }
}

/// Only restores the output device this session muted, and yields to observed user changes.
final class RecordingMuteSession: @unchecked Sendable {
    private let access: RecordingMuteAccess
    private let lock = NSLock()
    private var removeObserver: (() -> Void)?
    private var applied = false
    private var userChanged = false
    private var finished = false

    init(access: RecordingMuteAccess) throws {
        self.access = access
        guard try !access.read() else { return } // An already-muted device belongs to the user.
        removeObserver = try access.observe { [weak self] muted in
            guard !muted, let self else { return }
            self.lock.lock(); self.userChanged = true; self.lock.unlock()
        }
        applied = true
        do {
            try access.write(true)
        } catch {
            do { try restore() }
            catch { throw AudioRecorder.RecordingError.cannotRestoreSystemAudio }
            throw error
        }
    }

    deinit { try? restore() }

    func restore() throws {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let shouldRestore = applied && !userChanged
        lock.unlock()
        removeObserver?(); removeObserver = nil
        guard shouldRestore, try access.read() else { return }
        try access.write(false)
    }
}
