import XCTest
@testable import OpenNoType

final class InsertionFeedbackTests: XCTestCase {
    private let blockReasons = InsertionBlockReason.allCases

    func testConfirmedDeliveryIsTheOnlySuccessAndDoesNotOpenResultPage() {
        for method in [InsertionMethod.accessibility, .paste] {
            let feedback = InsertionFeedback(outcome: .confirmed(method))
            XCTAssertEqual(feedback.severity, .success)
            XCTAssertFalse(feedback.isError)
            XCTAssertFalse(feedback.showResultPage)
            XCTAssertFalse(feedback.warnsAboutDuplicatePaste)
            XCTAssertTrue(feedback.message.contains("입력했습니다"))
            XCTAssertFalse(feedback.message.contains("다시 붙여넣지"))
        }
    }

    func testEveryBlockedDeliveryShowsAnActionableWarningAndResultPageWithoutDuplicateWarning() {
        for reason in blockReasons {
            let feedback = InsertionFeedback(outcome: .notSubmitted(reason))
            XCTAssertEqual(feedback.severity, .warning, reason.rawValue)
            XCTAssertTrue(feedback.isError, reason.rawValue)
            XCTAssertTrue(feedback.showResultPage, reason.rawValue)
            XCTAssertFalse(feedback.warnsAboutDuplicatePaste, reason.rawValue)
            XCTAssertFalse(feedback.message.contains("입력했습니다"), reason.rawValue)
            XCTAssertFalse(feedback.message.contains("입력 요청을 보냈"), reason.rawValue)
            XCTAssertFalse(feedback.message.contains("다시 붙여넣지"), reason.rawValue)
            XCTAssertTrue(feedback.message.contains(reason == .emptyText ? "다시 녹음" : "복사해"), reason.rawValue)
        }
    }

    func testUnverifiedDeliveryIsAQuietNoticeThatWarnsAboutDuplicatePasteAndKeepsTheUsersAppInFront() {
        for method in [InsertionMethod.accessibility, .paste] {
            for failure in [InsertionVerificationFailure.timedOut, .cancelled] {
                let feedback = InsertionFeedback(outcome: .submittedUnverified(method, failure))
                XCTAssertEqual(feedback.severity, .info)
                XCTAssertFalse(feedback.isError, "Submitted text must not be presented as a failure")
                XCTAssertFalse(feedback.showResultPage, "A submitted paste must never yank the manager window forward")
                XCTAssertTrue(feedback.warnsAboutDuplicatePaste)
                XCTAssertTrue(feedback.message.contains("최근 결과"))
                XCTAssertTrue(feedback.message.contains("다시 붙여넣지 마세요"))
                XCTAssertFalse(feedback.message.contains("입력했습니다"))
                XCTAssertFalse(feedback.message.contains("시작하지 않았습니다"))
            }
        }
    }

    func testOverlayAndTestWordingFollowSeverityWithoutCopyAdviceForTests() {
        let confirmed = InsertionFeedback(outcome: .confirmed(.paste))
        let unverified = InsertionFeedback(outcome: .submittedUnverified(.paste, .timedOut))
        let blocked = InsertionFeedback(outcome: .notSubmitted(.targetChanged))
        XCTAssertEqual(confirmed.overlayMessage, "입력했습니다.")
        XCTAssertTrue(unverified.overlayMessage.contains("확인하지 못했습니다"))
        XCTAssertTrue(blocked.overlayMessage.contains("복사"))
        for feedback in [confirmed, unverified, blocked] {
            XCTAssertLessThanOrEqual(feedback.overlayMessage.count, 60, "The floating bar shows two short lines at most")
            XCTAssertFalse(feedback.testMessage.contains("결과를 복사"), "The input test produces no result to copy")
        }
        XCTAssertTrue(blocked.testMessage.contains("앞으로 가져오지"))
        XCTAssertTrue(blocked.testMessage.contains("진단"))
    }

    func testCancellationBeforeAndAfterDispatchHaveDifferentDeliveryGuidance() {
        let before = InsertionFeedback(outcome: .notSubmitted(.cancelled))
        let after = InsertionFeedback(outcome: .submittedUnverified(.paste, .cancelled))
        XCTAssertTrue(before.message.contains("자동입력 전에"))
        XCTAssertTrue(after.message.contains("입력 요청을 보낸 뒤"))
        XCTAssertFalse(before.warnsAboutDuplicatePaste)
        XCTAssertTrue(after.warnsAboutDuplicatePaste)
    }

    func testReasonsHaveDistinctGuidanceWithoutExposingTechnicalDiagnosticCodes() {
        let feedback = blockReasons.map { InsertionFeedback(outcome: .notSubmitted($0)) }
        XCTAssertEqual(Set(feedback.map(\.message)).count, blockReasons.count)
        for (reason, presentation) in zip(blockReasons, feedback) {
            XCTAssertFalse(presentation.message.contains(reason.rawValue))
            XCTAssertFalse(presentation.message.contains("AXSelectedText"))
            XCTAssertFalse(presentation.message.contains("Cmd-V"))
        }
        XCTAssertTrue(InsertionFeedback(outcome: .notSubmitted(.noTarget)).message.contains("다른 앱"))
        XCTAssertTrue(InsertionFeedback(outcome: .notSubmitted(.permissionMissing)).message.contains("손쉬운 사용"))
        XCTAssertTrue(InsertionFeedback(outcome: .notSubmitted(.targetChanged)).message.contains("앞으로 가져오지"))
        XCTAssertTrue(InsertionFeedback(outcome: .notSubmitted(.secureInput)).message.contains("비밀번호"))
        XCTAssertTrue(InsertionFeedback(outcome: .notSubmitted(.clipboardChanged)).message.contains("새로 복사한 내용"))
    }
}
