import AppKit
import XCTest
@testable import OpenNoType

@MainActor
final class VoiceBarLayoutTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)

    func testDefaultOriginPlacesBarBottomCentered() {
        let size = NSSize(width: 376, height: 60)
        let origin = VoiceBarLayout.resolveOrigin(panelSize: size, visibleFrame: screenFrame, saved: nil)
        XCTAssertEqual(origin.x, screenFrame.midX - size.width / 2, accuracy: 0.5)
        XCTAssertEqual(origin.y, screenFrame.minY + VoiceBarLayout.defaultBottomOffset, accuracy: 0.5)
    }

    func testSavedPositionIsRestoredAndClampedInsideVisibleFrame() {
        let size = NSSize(width: 440, height: 170)
        let saved = VoiceBarSavedPosition(xCenterRatio: 0.99, bottomOffset: 900)
        let origin = VoiceBarLayout.resolveOrigin(panelSize: size, visibleFrame: screenFrame, saved: saved)
        XCTAssertLessThanOrEqual(origin.x + size.width, screenFrame.maxX - VoiceBarLayout.margin + 0.5)
        XCTAssertLessThanOrEqual(origin.y + size.height, screenFrame.maxY - VoiceBarLayout.margin + 0.5)
        XCTAssertGreaterThanOrEqual(origin.x, screenFrame.minX + VoiceBarLayout.margin - 0.5)
        XCTAssertGreaterThanOrEqual(origin.y, screenFrame.minY + VoiceBarLayout.margin - 0.5)
    }

    func testAnchorResizePreservesHorizontalCenterAndBottomEdge() {
        let current = NSRect(x: 300, y: 120, width: 376, height: 60)
        let expanded = NSSize(width: 440, height: 126)
        let origin = VoiceBarLayout.anchorResize(currentFrame: current, newSize: expanded, visibleFrame: screenFrame)
        XCTAssertEqual(origin.x + expanded.width / 2, current.midX, accuracy: 0.5)
        XCTAssertEqual(origin.y, current.minY, accuracy: 0.5)
    }

    func testPositionStoreRoundTripsAndClearsPerDisplay() throws {
        let suiteName = "VoiceBarLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = VoiceBarPositionStore(defaults: defaults)
        let position = VoiceBarSavedPosition(xCenterRatio: 0.25, bottomOffset: 180)
        store.save(position, for: "display-1")
        XCTAssertEqual(store.position(for: "display-1"), position)
        XCTAssertNil(store.position(for: "display-2"))
        store.clear(for: "display-1")
        XCTAssertNil(store.position(for: "display-1"))
    }

    func testCompactToastIsSmallerThanExpandedActionToast() {
        let shortToast = VoiceBarLayout.panelSize(
            isBusy: false, hasWarning: false, hasPreview: false,
            transientMessage: "입력했습니다.", offersResultCopy: false, isTranslationMode: false
        )
        let actionToast = VoiceBarLayout.panelSize(
            isBusy: false, hasWarning: false, hasPreview: false,
            transientMessage: "자동입력을 하지 못했습니다.", offersResultCopy: true, isTranslationMode: false
        )
        XCTAssertLessThan(shortToast.width, actionToast.width)
        XCTAssertLessThan(shortToast.height, actionToast.height)
    }
}
