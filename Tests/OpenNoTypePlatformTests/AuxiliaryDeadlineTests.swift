import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class AuxiliaryDeadlineTests: KoreanPresentationTestCase {
    func testExpiredGenerationDeadlineExplainsTheFailureAndKeepsPromptRetryable() async {
        do {
            _ = try await jevWithDeadline(seconds: 0.01) {
                try await Task.sleep(for: .seconds(10))
                return "late result"
            }
            XCTFail("The deadline must stop the pending generation")
        } catch {
            var composition = PromptCompositionPresentation(transcript: "음성 기록 기능을 개선해 주세요.", status: "pending")
            composition.stop(with: error)

            XCTAssertEqual(composition.status, "AI 응답 대기 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.")
            XCTAssertEqual(composition.interruption, .generationFailed)
            XCTAssertEqual(composition.title, "프롬프트 생성 실패")
            XCTAssertFalse(composition.isProcessing)
            XCTAssertNil(composition.output)
            XCTAssertTrue(composition.canRegenerate(with: composition.transcript))
        }
    }

    func testDeadlinePreservesSuccessfulResult() async throws {
        let result = try await jevWithDeadline(seconds: 1) { "completed result" }
        XCTAssertEqual(result, "completed result")
    }

    func testDeadlinePreservesCancellation() async {
        do {
            _ = try await jevWithDeadline(seconds: 1) { () -> String in throw CancellationError() }
            XCTFail("Cancellation must not produce a result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
