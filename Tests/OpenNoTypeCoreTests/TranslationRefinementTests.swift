import XCTest
@testable import OpenNoTypeCore

final class TranslationRefinementTests: XCTestCase {
    private var request: ProcessingRequest {
        .init(mode: .dictation, transcript: "가능하면 이 부분을 확인해 주세요.", outputLanguage: .english,
              writingProfile: .init(kind: .conversation, tone: .polite))
    }

    func testChangedResultMakesOneSourceGroundedRequestAndKeepsCapturedSettings() async throws {
        let ledger = RefinementCallLedger()
        let original = request
        let draft = "If possible, check this part, please."
        let result = try await TranslationRefinementRunner.run(request: original, draft: draft) { next in
            await ledger.record(next)
            return "Could you check this part if possible?"
        }
        XCTAssertEqual(result, .refined("Could you check this part if possible?"))
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.transcript, original.transcript)
        XCTAssertEqual(calls.first?.translationDraft, draft)
        XCTAssertEqual(calls.first?.outputLanguage, .english)
        XCTAssertEqual(calls.first?.writingProfile, original.writingProfile)
        XCTAssertNil(calls.first?.previousOutput)
        XCTAssertNil(original.translationDraft)
    }

    func testAlreadyNaturalResultMayRemainUnchangedWithoutAnotherCall() async throws {
        let ledger = RefinementCallLedger()
        let draft = "Could you check this part if possible?"
        let result = try await TranslationRefinementRunner.run(request: request, draft: draft) { next in
            await ledger.record(next)
            return " \n" + draft + "\n"
        }
        XCTAssertEqual(result, .unchanged(draft))
        XCTAssertEqual(result.text, draft)
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 1)
    }

    func testWrongModeAlternativeOrNestedRefinementCannotStartASecondCall() async throws {
        let ledger = RefinementCallLedger()
        let inputs = [ProcessingRequest(mode: .dictation, transcript: "원문"),
                      ProcessingRequest(mode: .rewrite, transcript: "짧게", selectedText: "원문"),
                      ProcessingRequest(mode: .translation, transcript: "원문", previousOutput: "alternative"),
                      ProcessingRequest(mode: .translation, transcript: "원문", translationDraft: "nested")]
        for input in inputs {
            let result = try await TranslationRefinementRunner.run(request: input, draft: "Draft.") { next in
                await ledger.record(next); return "Unexpected."
            }
            XCTAssertEqual(result, .held(.invalidRequest))
            XCTAssertNil(result.text)
        }
        let calls = await ledger.values()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCombinedTextLimitCountsUTF8BytesAndDoesNotTruncateTheDraft() async throws {
        let ledger = RefinementCallLedger()
        let input = ProcessingRequest(mode: .translation, transcript: "가")
        let exact = String(repeating: "나", count: 7_999)
        XCTAssertEqual(input.transcript.utf8.count + exact.utf8.count, 24_000)
        let accepted = try await TranslationRefinementRunner.run(request: input, draft: exact) { next in
            await ledger.record(next); return "A synthetic result."
        }
        XCTAssertEqual(accepted, .refined("A synthetic result."))
        let rejected = try await TranslationRefinementRunner.run(request: input, draft: exact + "나") { next in
            await ledger.record(next); return "Unexpected."
        }
        XCTAssertEqual(rejected, .held(.inputTooLarge))
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.translationDraft, exact)
    }

    func testEmptyOrControlCharacterDraftIsHeldBeforeCallingTheProvider() async throws {
        let ledger = RefinementCallLedger()
        for draft in [" \n\t", "Draft\u{0000}."] {
            let result = try await TranslationRefinementRunner.run(request: request, draft: draft) { next in
                await ledger.record(next); return "Unexpected."
            }
            XCTAssertEqual(result, .held(.invalidOutput))
        }
        let calls = await ledger.values()
        XCTAssertTrue(calls.isEmpty)
    }

    func testInvalidOrOversizedFinalResultNeverFallsBackToTheDraft() async throws {
        let ledger = RefinementCallLedger()
        for output in [" \n", "Result\u{0000}.", String(repeating: "가", count: 8_000)] {
            let result = try await TranslationRefinementRunner.run(request: request, draft: "Keep this draft.") { next in
                await ledger.record(next); return output
            }
            XCTAssertEqual(result, .held(output.hasPrefix("가") ? .outputTooLarge : .invalidOutput))
            XCTAssertNil(result.text)
        }
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 3)
    }

    func testProviderFailureIsHeldWithNoAutomaticRetryOrSourceFallback() async throws {
        let ledger = RefinementCallLedger()
        for error in [ProviderError.httpStatus(429), .timedOut, .invalidResponse, .emptyOutput] {
            let result = try await TranslationRefinementRunner.run(request: request, draft: "Draft.") { next in
                await ledger.record(next); throw error
            }
            XCTAssertEqual(result, .held([.invalidResponse, .emptyOutput].contains(error) ? .invalidOutput : .requestFailed))
            XCTAssertNil(result.text)
        }
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 4)
    }

    func testFinalLiteralAndClockChecksUseTheSourceRatherThanTheDraft() async throws {
        let cases = [("변수 이름은 `mira_key`입니다.", "The name is mira_key.", "The name is miraKey."),
                     ("내일 6시까지 확인해 주세요.", "Check it by 6 tomorrow.", "Check it by 6 PM tomorrow.")]
        for (source, draft, output) in cases {
            let result = try await TranslationRefinementRunner.run(
                request: .init(mode: .translation, transcript: source), draft: draft) { _ in output }
            XCTAssertEqual(result, .held(.protectedContentChanged))
            XCTAssertNil(result.text)
        }
        let repaired = try await TranslationRefinementRunner.run(
            request: .init(mode: .translation, transcript: "변수 이름은 `mira_key`입니다."),
            draft: "The name is miraKey.") { _ in "The name is mira_key." }
        XCTAssertEqual(repaired, .refined("The name is mira_key."))
    }

    func testUnsupportedTargetFailsBeforeTheCall() async throws {
        let ledger = RefinementCallLedger()
        var invalid = request
        invalid.targetLanguage = "invented language"
        invalid.outputLanguage = .original
        invalid.mode = .translation
        let result = try await TranslationRefinementRunner.run(request: invalid, draft: "Draft.") { next in
            await ledger.record(next); return "Unexpected."
        }
        XCTAssertEqual(result, .held(.invalidRequest))
        let calls = await ledger.values()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCancellationBeforeStartingDoesNotCallTheProvider() async throws {
        let ledger = RefinementCallLedger()
        let input = request
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TranslationRefinementRunner.run(request: input, draft: "Draft.") { next in
                await ledger.record(next); return "Unexpected."
            }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ledger.values()
        XCTAssertTrue(calls.isEmpty)
    }

    func testProviderCancellationPropagatesInsteadOfReturningHeldOrFallback() async throws {
        let ledger = RefinementCallLedger()
        do {
            _ = try await TranslationRefinementRunner.run(request: request, draft: "Draft.") { next in
                await ledger.record(next); throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 1)
    }

    func testCancellationAfterAResponseCannotPublishARefinedResult() async throws {
        let ledger = RefinementCallLedger()
        let input = request
        let task = Task {
            try await TranslationRefinementRunner.run(request: input, draft: "Draft.") { next in
                await ledger.record(next)
                withUnsafeCurrentTask { $0?.cancel() }
                return "A late result."
            }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ledger.values()
        XCTAssertEqual(calls.count, 1)
    }
}

private actor RefinementCallLedger {
    private var requests: [ProcessingRequest] = []
    func record(_ request: ProcessingRequest) { requests.append(request) }
    func values() -> [ProcessingRequest] { requests }
}
