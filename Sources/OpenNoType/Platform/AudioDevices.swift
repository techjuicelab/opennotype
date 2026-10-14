import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let uid: String
    let name: String
    let deviceID: AudioDeviceID
    var id: String { uid }
}

enum AudioDevices {
    /// A nil UID means the current system default; selecting a device never changes that default.
    static func inputDevices() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        try devices.withUnsafeMutableBytes { bytes in
            if let base = bytes.baseAddress {
                try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, base))
            }
        }
        return devices.compactMap { device in
            guard (try? inputChannelCount(device)) ?? 0 > 0,
                  let uid = try? string(device, selector: kAudioDevicePropertyDeviceUID),
                  let name = try? string(device, selector: kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(uid: uid, name: name, deviceID: device)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func resolveInputDevice(uid: String?) throws -> AudioDeviceID {
        if let uid, !uid.isEmpty {
            return try selectInputDevice(uid: uid, devices: inputDevices(), defaultDeviceID: kAudioObjectUnknown)
        }
        let device = try defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        guard device != kAudioObjectUnknown, try inputChannelCount(device) > 0 else {
            throw AudioRecorder.RecordingError.inputDeviceUnavailable
        }
        return device
    }

    /// A missing saved UID is an explicit error, never an unnoticed fallback to another microphone.
    static func selectInputDevice(uid: String?, devices: [AudioInputDevice], defaultDeviceID: AudioDeviceID) throws -> AudioDeviceID {
        if let uid, !uid.isEmpty {
            guard let device = devices.first(where: { $0.uid == uid }) else {
                throw AudioRecorder.RecordingError.inputDeviceUnavailable
            }
            return device.deviceID
        }
        guard defaultDeviceID != kAudioObjectUnknown else { throw AudioRecorder.RecordingError.inputDeviceUnavailable }
        return defaultDeviceID
    }

    static func defaultOutputDevice() throws -> AudioDeviceID {
        try defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value))
        return value
    }

    private static func string(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer))
        }
        return value as String
    }

    private static func inputChannelCount(_ device: AudioDeviceID) throws -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage))
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
