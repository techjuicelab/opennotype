import AppKit
import XCTest
@testable import OpenNoType

/// Appended to ClipboardTransactionTests: representations whose data cannot be read are skipped
/// instead of blocking insertion.
@MainActor
final class ClipboardBestEffortTests: XCTestCase {
    private final class SilentProvider: NSObject, NSPasteboardItemDataProvider {
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            // Behaves like an owner app that has quit: the promised representation never arrives.
        }
    }

    private func isolatedPasteboard() throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenNoType-Tests-" + UUID().uuidString))
        pasteboard.clearContents()
        guard pasteboard.setString("probe", forType: .string), pasteboard.string(forType: .string) == "probe" else {
            pasteboard.releaseGlobally()
            throw XCTSkip("격리된 NSPasteboard 서비스에 연결할 수 없는 테스트 환경입니다. 일반 클립보드는 사용하지 않습니다.")
        }
        return pasteboard
    }

    func testUnreadablePromisedRepresentationIsSkippedAndReadableOnesAreRestored() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("kept text", forType: .string)
        let promised = NSPasteboard.PasteboardType("test.opennotype.promised")
        let provider = SilentProvider()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [promised]))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        guard pasteboard.pasteboardItems?.first?.data(forType: promised) == nil else {
            throw XCTSkip("이 환경의 pasteboard 서버가 지연 제공 데이터를 즉시 채워 재현할 수 없습니다.")
        }

        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard), "An unreadable representation must not block insertion")
        XCTAssertEqual(transaction.skippedRepresentations, 1)
        XCTAssertTrue(transaction.install("dictated text"))
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
        XCTAssertTrue(transaction.restore())
        XCTAssertEqual(pasteboard.string(forType: .string), "kept text")
        XCTAssertNil(pasteboard.pasteboardItems?.first?.data(forType: promised))
    }

    func testItemThatWouldLoseEveryRepresentationRefusesTheTransactionAndLeavesClipboardIntact() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        let huge = NSPasteboard.PasteboardType("test.opennotype.huge-only")
        item.setData(Data(count: 33_000_000), forType: huge)
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let before = pasteboard.changeCount
        XCTAssertNil(ClipboardTransaction(pasteboard: pasteboard), "An item with nothing preservable must not be replaced by an empty restore")
        XCTAssertEqual(pasteboard.changeCount, before)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: huge)?.count, 33_000_000)

        pasteboard.clearContents()
        let promisedOnly = NSPasteboardItem()
        let promised = NSPasteboard.PasteboardType("test.opennotype.promised-only")
        XCTAssertTrue(promisedOnly.setDataProvider(SilentProvider(), forTypes: [promised]))
        XCTAssertTrue(pasteboard.writeObjects([promisedOnly]))
        guard pasteboard.pasteboardItems?.first?.data(forType: promised) == nil else {
            throw XCTSkip("이 환경의 pasteboard 서버가 지연 제공 데이터를 즉시 채워 재현할 수 없습니다.")
        }
        XCTAssertNil(ClipboardTransaction(pasteboard: pasteboard))
    }

    func testOversizedRepresentationsAreSkippedWithoutBlocking() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("small", forType: .string)
        let huge = NSPasteboard.PasteboardType("test.opennotype.huge")
        item.setData(Data(count: 33_000_000), forType: huge)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard))
        XCTAssertEqual(transaction.skippedRepresentations, 1)
        XCTAssertTrue(transaction.install("dictated"))
        XCTAssertTrue(transaction.restore())
        XCTAssertEqual(pasteboard.string(forType: .string), "small")
    }
}
