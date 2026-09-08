import AppKit
import ApplicationServices
import XCTest
@testable import OpenNoType

@MainActor
final class ClipboardTransactionTests: XCTestCase {
    private func isolatedPasteboard() throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenNoType-Tests-" + UUID().uuidString))
        pasteboard.clearContents()
        guard pasteboard.setString("probe", forType: .string), pasteboard.string(forType: .string) == "probe" else {
            pasteboard.releaseGlobally()
            throw XCTSkip("격리된 NSPasteboard 서비스에 연결할 수 없는 테스트 환경입니다. 일반 클립보드는 사용하지 않습니다.")
        }
        return pasteboard
    }

    func testRestorePreservesMultipleItemsAndEveryDataRepresentation() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("original text", forType: .string)
        first.setString("<b>original text</b>", forType: .html)
        let second = NSPasteboardItem()
        let binaryType = NSPasteboard.PasteboardType("test.opennotype.binary")
        second.setData(Data([0, 1, 255]), forType: binaryType)
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard))
        XCTAssertTrue(transaction.install("dictated text"))
        XCTAssertTrue(transaction.ownsContents)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
        XCTAssertTrue(transaction.restore())
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].string(forType: .string), "original text")
        XCTAssertEqual(restored[0].string(forType: .html), "<b>original text</b>")
        XCTAssertEqual(restored[1].data(forType: binaryType), Data([0, 1, 255]))
    }

    func testNewerUserCopyWinsOverRestoringSnapshot() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard))
        XCTAssertTrue(transaction.install("temporary dictated text"))
        pasteboard.clearContents()
        pasteboard.setString("new user copy", forType: .string)
        XCTAssertFalse(transaction.ownsContents)
        XCTAssertTrue(transaction.restore())
        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }

    func testChangedPasteboardDuringPreparationPreventsInstallation() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard))
        pasteboard.clearContents()
        pasteboard.setString("new content", forType: .string)
        XCTAssertFalse(transaction.install("must not replace"))
        XCTAssertEqual(pasteboard.string(forType: .string), "new content")
    }

    func testEmptyPasteboardIsRestoredAndRestoreIsIdempotent() throws {
        let pasteboard = try isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let transaction = try XCTUnwrap(ClipboardTransaction(pasteboard: pasteboard))
        XCTAssertTrue(transaction.install("temporary"))
        XCTAssertTrue(transaction.restore())
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty != false)
        pasteboard.setString("later copy", forType: .string)
        XCTAssertTrue(transaction.restore())
        XCTAssertEqual(pasteboard.string(forType: .string), "later copy")
    }

    func testCancelledTaskStillWaitsForClipboardDeliveryGracePeriod() async {
        let started = ProcessInfo.processInfo.systemUptime
        let task = Task { await TextInsertion.uncancellablePause(0.15) }
        task.cancel()
        await task.value
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 0.13)
    }

    func testCancelledInsertionDoesNotProceedToTargetOrClipboard() async {
        let fake = InputTarget(pid: getpid(), bundleID: nil, element: AXUIElementCreateApplication(getpid()),
                               originalValue: "", range: CFRange(location: 0, length: 0), selectedText: nil, context: nil)
        let inserted = await TextInsertion.insert("must not insert", at: fake, isCancelled: { true })
        XCTAssertFalse(inserted)
    }
}
