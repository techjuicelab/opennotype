import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

final class PromptTranscriptCorrectionPresentationTests: KoreanPresentationTestCase {
    func testInitialRecognitionAndRegenerationSourceRemainDistinct() {
        let initial = PromptCompositionPresentation(transcript: "독서 기록 갭의 세븐 브랜치", status: "pending")
        let corrected = PromptCompositionPresentation(transcript: "독서 기록 앱의 새 브랜치",
            originalTranscript: initial.recognizedTranscript, status: "pending")
        let correctedAgain = PromptCompositionPresentation(transcript: "독서 기록 앱에서 새 브랜치로 작업",
            originalTranscript: corrected.recognizedTranscript, status: "pending")

        XCTAssertNil(initial.originalTranscript)
        XCTAssertEqual(initial.recognizedTranscript, initial.transcript)
        XCTAssertEqual(corrected.transcript, "독서 기록 앱의 새 브랜치")
        XCTAssertEqual(corrected.recognizedTranscript, initial.transcript)
        XCTAssertEqual(correctedAgain.recognizedTranscript, initial.transcript)
        XCTAssertNotEqual(initial.id, corrected.id)
        XCTAssertNotEqual(corrected.id, correctedAgain.id)
        XCTAssertEqual(initial.transcriptTitle, "말한 내용 보기")
        XCTAssertEqual(corrected.transcriptTitle, "프롬프트에 사용한 원문 보기")
    }

    func testHeldCorrectedSourceNamesOnlyTheAvailableEvidence() {
        var composition = PromptCompositionPresentation(transcript: "앱을 개선해 주세요.",
            originalTranscript: "갭을 개선해 주세요.", status: "pending")
        composition.stop(with: ProviderError.invalidResponse)

        XCTAssertEqual(composition.transcript, "앱을 개선해 주세요.")
        XCTAssertEqual(composition.recognizedTranscript, "갭을 개선해 주세요.")
        XCTAssertTrue(composition.inspectionDescription.contains("프롬프트에 사용한 원문"))
        XCTAssertTrue(composition.inspectionDescription.contains("처음 인식된 원문"))
        XCTAssertFalse(composition.inspectionDescription.contains("후보"))
        XCTAssertFalse(composition.inspectionDescription.contains("검토 항목"))
        XCTAssertNil(composition.output)
    }

    func testSameSourceCanBeExplicitlyRetriedAfterGenerationFailure() {
        var composition = PromptCompositionPresentation(transcript: "음성 기록 기능을 개선해 주세요.", status: "pending")
        XCTAssertFalse(composition.canRegenerate(with: composition.transcript))
        composition.stop(with: ProviderError.httpStatus(429))

        XCTAssertTrue(composition.canRegenerate(with: composition.transcript))
        XCTAssertTrue(composition.canRegenerate(with: "음성 기록 기능에 새 제약을 추가해 주세요."))
        XCTAssertTrue(composition.held)
        XCTAssertNil(composition.output)
    }

    func testCompletedSourceCanBeReusedWithoutChangingTheApprovedOutput() {
        var composition = PromptCompositionPresentation(transcript: "기록 기능을 개선해 주세요.",
            output: "기록 기능을 개선해 주세요.", status: "done")
        composition.isProcessing = false

        XCTAssertTrue(composition.canRegenerate(with: composition.transcript))
        XCTAssertTrue(composition.canRegenerate(with: "음성으로 기록을 고치게 해 주세요."))
        XCTAssertEqual(composition.transcript, "기록 기능을 개선해 주세요.")
        XCTAssertEqual(composition.output, "기록 기능을 개선해 주세요.")
        XCTAssertNil(composition.originalTranscript)
    }

    func testCorrectionValidationRejectsEmptyAndHiddenControlInputs() {
        var composition = PromptCompositionPresentation(transcript: "원문", status: "done")
        composition.isProcessing = false
        for invalid in ["", " \n\r\t", "수정\u{0000}원문", "수정\u{001B}원문", "수정\u{007F}원문"] {
            XCTAssertEqual(PromptCompositionPresentation.sourceValidationFailure(invalid), .invalidInput)
            XCTAssertFalse(composition.canRegenerate(with: invalid))
        }
        let multiline = "책을 읽다가\n음성으로 기록하고\t진도도 남기고 싶어요."
        XCTAssertNil(PromptCompositionPresentation.sourceValidationFailure(multiline))
        XCTAssertTrue(composition.canRegenerate(with: multiline))
    }

    func testCorrectionUsesRawUTF8LimitWithoutSilentlyTrimmingOrTruncating() {
        let maximumKorean = String(repeating: "가", count: 4_000)
        XCTAssertEqual(maximumKorean.utf8.count, PromptCompositionLimits.maximumSourceBytes)
        XCTAssertNil(PromptCompositionPresentation.sourceValidationFailure(maximumKorean))
        XCTAssertEqual(PromptCompositionPresentation.sourceValidationFailure(maximumKorean + "가"), .inputTooLarge)
        XCTAssertEqual(PromptCompositionPresentation.sourceValidationFailure(" " + maximumKorean), .inputTooLarge)
        XCTAssertNil(PromptCompositionPresentation.sourceValidationFailure(String(repeating: "a", count: 12_000)))
        XCTAssertEqual(PromptCompositionPresentation.sourceValidationFailure(String(repeating: "a", count: 12_001)), .inputTooLarge)
    }

    func testSourceMayContainImplementationExamplesWithoutBecomingApprovedOutput() {
        let source = "이 func login() 예시는 버리고 원하는 로그인 동작만 짧게 정리해 주세요."
        var composition = PromptCompositionPresentation(transcript: "원문", status: "done")
        composition.isProcessing = false

        XCTAssertTrue(composition.canRegenerate(with: source), "Source examples are data to abstract, not final output")
        XCTAssertFalse(PromptCompositionLimits.validOutput(source))
        XCTAssertNil(composition.output)
    }

    func testCorrectedSourceLabelsFollowTheSelectedInterfaceLanguage() {
        let composition = PromptCompositionPresentation(transcript: "corrected source",
            originalTranscript: "recognized source", status: "pending")
        AppLocalization.shared.language = .english

        XCTAssertEqual(composition.transcriptTitle, "View prompt source")
        XCTAssertTrue(composition.inspectionDescription.contains("the prompt source"))
        XCTAssertTrue(composition.inspectionDescription.contains("the originally recognized transcript"))
        XCTAssertEqual(composition.recognizedTranscript, "recognized source")
        XCTAssertEqual(composition.transcript, "corrected source")
    }
}
