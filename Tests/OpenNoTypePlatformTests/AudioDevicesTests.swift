import CoreAudio
import XCTest
@testable import OpenNoType

final class AudioDevicesTests: XCTestCase {
    func testSavedUIDRemainsStableWhenCoreAudioDeviceIDsChange() throws {
        let devices = [AudioInputDevice(uid: "usb-mic", name: "USB Microphone", deviceID: 82),
                       AudioInputDevice(uid: "built-in", name: "Built-in Microphone", deviceID: 93)]
        XCTAssertEqual(try AudioDevices.selectInputDevice(uid: "usb-mic", devices: devices, defaultDeviceID: 93), 82)
        let reconnected = [AudioInputDevice(uid: "usb-mic", name: "USB Microphone", deviceID: 104)]
        XCTAssertEqual(try AudioDevices.selectInputDevice(uid: "usb-mic", devices: reconnected, defaultDeviceID: 93), 104)
    }

    func testMissingSavedUIDDoesNotFallbackToDefault() {
        XCTAssertThrowsError(try AudioDevices.selectInputDevice(uid: "disconnected", devices: [], defaultDeviceID: 93)) { error in
            guard case AudioRecorder.RecordingError.inputDeviceUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDefaultSelectionUsesCurrentDefaultAndRequiresOneToExist() throws {
        XCTAssertEqual(try AudioDevices.selectInputDevice(uid: nil, devices: [], defaultDeviceID: 93), 93)
        XCTAssertEqual(try AudioDevices.selectInputDevice(uid: "", devices: [], defaultDeviceID: 104), 104)
        XCTAssertThrowsError(try AudioDevices.selectInputDevice(uid: nil, devices: [], defaultDeviceID: kAudioObjectUnknown))
    }
}
