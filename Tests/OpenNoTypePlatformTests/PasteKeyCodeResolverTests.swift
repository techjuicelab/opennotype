import Carbon
import XCTest
@testable import OpenNoType

@MainActor
final class PasteKeyCodeResolverTests: XCTestCase {
    func testInstalledLayoutsResolveTheirCommandLayerWithoutSelectingThem() throws {
        let original = try currentInputSourceID()
        for (identifier, expected): (String, CGKeyCode) in [
            ("com.apple.keylayout.ABC", 9),
            ("com.apple.keylayout.Dvorak", 47),
            ("com.apple.keylayout.DVORAK-QWERTYCMD", 9)
        ] {
            let data = try layoutData(identifier: identifier)
            XCTAssertEqual(PasteKeyCodeResolver.resolve(layoutData: data, keyboardType: UInt32(LMGetKbdType())),
                           expected, identifier)
        }
        XCTAssertEqual(try currentInputSourceID(), original, "Reading layout data must not select an input source")
    }

    func testMissingOrEmptyLayoutFallsBackToExistingANSIV() {
        XCTAssertEqual(PasteKeyCodeResolver.resolve(layoutData: nil, keyboardType: 0), 9)
        let empty = Data() as CFData
        XCTAssertEqual(PasteKeyCodeResolver.resolve(layoutData: empty, keyboardType: 0), 9)
    }

    func testFailedTranslationsOrLayoutsWithoutVFallBack() {
        XCTAssertEqual(PasteKeyCodeResolver.resolve { _ in nil }, 9)
        XCTAssertEqual(PasteKeyCodeResolver.resolve { _ in 0x314D }, 9)
    }

    func testResolverReevaluatesEachLayoutAndAcceptsUppercaseEquivalent() {
        var currentV: CGKeyCode = 47
        let translate: (CGKeyCode) -> UniChar? = { $0 == currentV ? 0x76 : nil }
        XCTAssertEqual(PasteKeyCodeResolver.resolve(translating: translate), 47)
        currentV = 9
        XCTAssertEqual(PasteKeyCodeResolver.resolve(translating: translate), 9)
        XCTAssertEqual(PasteKeyCodeResolver.resolve { $0 == 127 ? 0x56 : nil }, 127)
    }

    private func layoutData(identifier: String) throws -> CFData {
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        let list = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        let source = try XCTUnwrap(list.first, identifier)
        let property = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData), identifier)
        return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    }

    private func currentInputSourceID() throws -> String {
        let source = try XCTUnwrap(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue())
        let property = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyInputSourceID))
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}
