import Carbon
import CoreGraphics
import XCTest
@testable import OpenNoType

final class PasteKeyEventsTests: XCTestCase {
    func testPasteIncludesNativeCommandTransitionsAroundV() throws {
        let events = try XCTUnwrap(PasteKeyEvents.make())
        XCTAssertEqual(events.count, 4, "Paste must include Command down, V down/up, and Command up")
        guard events.count == 4 else { return }

        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [55, 9, 9, 55])
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertTrue(events[0].flags.contains(.maskCommand))
        // IOKit IOLLEvent.h defines NX_DEVICELCMDKEYMASK as 0x00000008. Preserve the
        // native Command key event's device flag instead of replacing it with only maskCommand.
        XCTAssertNotEqual(events[0].flags.rawValue & 0x8, 0)
        XCTAssertEqual(events[1].flags, events[0].flags)
        XCTAssertEqual(events[2].flags, events[0].flags)
        XCTAssertFalse(events[3].flags.contains(.maskCommand))
        XCTAssertEqual(events[3].flags.rawValue & 0x8, 0)
        let sourceState = events[0].getIntegerValueField(.eventSourceStateID)
        // privateState requests a newly allocated table; events carry that unique ID,
        // not the -1 value used to request its creation.
        XCTAssertNotEqual(sourceState, 0, "The shortcut must not share combined session state")
        XCTAssertNotEqual(sourceState, 1, "The shortcut must not share HID system state")
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceStateID) == sourceState },
                      "All shortcut events must share the same independent source state")
    }
}
