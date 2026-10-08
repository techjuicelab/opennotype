import XCTest
@testable import OpenNoTypeCore

final class PromptCompositionRunnerTests: XCTestCase {
    private let request = ProcessingRequest(mode: .prompt, transcript: "OpenNoType에서 아이디어를 작업 프롬프트로 정리해 주세요. 코드는 넣지 마세요.",
              dictionary: [.init(spoken: "오픈노타입", written: "OpenNoType")])

    func testAcceptedDraftStaysStableThroughTwoGenerationsAndTwoReviewsInOrder() async throws {
        let ledger = PromptCompositionLedger(outputs: [" \n초안 요청\n", " 최종 요청 "],
                                             reviews: [acceptedReview(), acceptedReview()])
        let result = try await run(ledger)
        XCTAssertEqual(result, .init(draft: "초안 요청", text: "초안 요청"))
        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.events, ["stage:drafting", "generate", "stage:reviewingDraft", "review",
                                     "stage:polishing", "generate", "stage:reviewingFinal", "review"])
        XCTAssertEqual(calls.requests.count, 2)
        XCTAssertEqual(calls.requests.map(\.transcript), [request.transcript, request.transcript])
        XCTAssertNil(calls.requests[0].promptDraft)
        XCTAssertEqual(calls.requests[1].promptDraft, "초안 요청")
        XCTAssertEqual(calls.requests[1].dictionary, request.dictionary)
        XCTAssertEqual(calls.requests[1].promptReviewIssues, [])
        XCTAssertEqual(calls.reviews, [.init(transcript: request.transcript, prompt: "초안 요청"),
                                      .init(transcript: request.transcript, prompt: "초안 요청")])
    }

    func testFlaggedDraftSuppliesOnlyFixedIssuesToOnePolish() async throws {
        let flagged = review(overriding: .unsupportedAdditions, choice: .fail)
        let ledger = PromptCompositionLedger(outputs: ["초안", "정리한 요청"],
                                             reviews: [flagged, acceptedReview()])
        let result = try await run(ledger)
        XCTAssertEqual(result.text, "정리한 요청")
        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.requests.count, 2)
        XCTAssertEqual(calls.requests[1].promptReviewIssues, [.unsupportedAdditions])
        XCTAssertEqual(calls.requests[1].transcript, request.transcript)
        XCTAssertNil(calls.requests[1].previousOutput)
        XCTAssertNil(calls.requests[1].translationDraft)
    }

    func testAcceptedVoiceRetryDraftCannotLoseModalityDuringPolishing() async throws {
        let draft = "아이가 틀리면 기다렸다가 같은 문제에서 다시 말할 수 있게 해 주세요."
        let ledger = PromptCompositionLedger(outputs: [draft, "아이가 틀리면 같은 문제에 다시 답하게 해 주세요."],
                                             reviews: [acceptedReview(), acceptedReview()])
        let result = try await run(ledger)
        let calls = await ledger.snapshot()
        XCTAssertEqual(result.text, draft)
        XCTAssertEqual(calls.reviews.last?.prompt, draft)
        XCTAssertEqual(calls.requests.count, 2)
    }

    func testPassWithLowConfidenceStillUsesTheRepairedCandidate() async throws {
        let first = review(overriding: .intent, choice: .pass, confidence: 0.59)
        let ledger = PromptCompositionLedger(outputs: ["확인이 필요한 초안", "수정한 요청"],
                                             reviews: [first, acceptedReview()])
        let result = try await run(ledger)
        let calls = await ledger.snapshot()
        XCTAssertEqual(result.text, "수정한 요청")
        XCTAssertEqual(calls.requests[1].promptReviewIssues, [.intent])
        XCTAssertEqual(calls.reviews.last?.prompt, "수정한 요청")
    }

    func testFinalFailUncertaintyAndLowEvidenceNeverReturnDraftOrFinal() async throws {
        let finalReviews = [review(overriding: .intent, choice: .fail),
                            review(overriding: .omissions, choice: .uncertain),
                            review(overriding: .harnessBoundary, choice: .pass, confidence: 0.59)]
        for finalReview in finalReviews {
            let ledger = PromptCompositionLedger(outputs: ["초안", "최종 후보"],
                                                 reviews: [acceptedReview(), finalReview])
            do { _ = try await run(ledger); XCTFail("Expected final review to hold the result") }
            catch { XCTAssertEqual(error as? PromptCompositionFailure, .reviewHeld) }
            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.requests.count, 2)
            XCTAssertEqual(calls.reviews.count, 2)
        }
    }

    func testFinalHoldPreservesExactCandidateAndReviewAfterDraftRepair() async throws {
        let draft = "확인이 필요한 초안"
        let final = "원문에 맞춰 수정한 마지막 후보"
        let firstReview = review(overriding: .omissions, choice: .fail)
        let finalReview = review(overriding: .intent, choice: .uncertain)
        let ledger = PromptCompositionLedger(outputs: [draft, final], reviews: [firstReview, finalReview])
        do { _ = try await run(ledger); XCTFail("Expected the final review to hold publication") }
        catch { XCTAssertEqual(error as? PromptCompositionFailure, .reviewHeld) }
        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.progressCandidates["reviewingFinal"], final)
        XCTAssertEqual(calls.observedReviews.map(\.stage), ["reviewingDraft", "reviewingFinal"])
        XCTAssertEqual(calls.observedReviews.map(\.request), calls.reviews)
        XCTAssertEqual(calls.observedReviews.first?.request, .init(transcript: request.transcript, prompt: draft))
        XCTAssertEqual(calls.observedReviews.last?.request, .init(transcript: request.transcript, prompt: final))
        XCTAssertEqual(calls.observedReviews.first?.result.assessments, firstReview.assessments)
        XCTAssertEqual(calls.observedReviews.last?.result.assessments, finalReview.assessments)
        XCTAssertEqual(calls.observedReviews.last?.result.issues, [.intent])
        XCTAssertEqual(calls.requests.count, 2)
        XCTAssertEqual(calls.reviews.count, 2)
    }

    func testAcceptedDraftReviewCallbacksUseTheSameStableFinalCandidate() async throws {
        let ledger = PromptCompositionLedger(outputs: ["검토를 통과한 초안", "사용하지 않을 다듬기 후보"],
                                             reviews: [acceptedReview(), acceptedReview()])
        let result = try await run(ledger)
        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.progressCandidates["reviewingFinal"], result.text)
        XCTAssertEqual(calls.observedReviews.map(\.request), calls.reviews)
        XCTAssertEqual(calls.observedReviews.map(\.request.prompt), [result.draft, result.draft])
        XCTAssertTrue(calls.observedReviews.allSatisfy { $0.result.accepted })
    }

    func testMalformedFirstAndFinalReviewStopWithoutFurtherCalls() async throws {
        let malformed = PromptCompositionReviewResult(assessments: [:])
        for position in [0, 1] {
            let reviews = position == 0 ? [malformed] : [acceptedReview(), malformed]
            let ledger = PromptCompositionLedger(outputs: ["초안", "최종 후보"], reviews: reviews)
            do { _ = try await run(ledger); XCTFail("Expected invalid review to fail closed") }
            catch { XCTAssertEqual(error as? PromptCompositionFailure, .reviewUnavailable) }
            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.requests.count, position + 1)
            XCTAssertEqual(calls.reviews.count, position + 1)
            XCTAssertEqual(calls.observedReviews.count, position)
        }
    }

    func testReviewTransportFailureStopsWithoutAutomaticRetry() async throws {
        for position in [0, 1] {
            let ledger = PromptCompositionLedger(outputs: ["초안", "최종 후보"],
                reviews: [acceptedReview(), acceptedReview()], failReviewAt: position)
            do { _ = try await run(ledger); XCTFail("Expected review failure") }
            catch { XCTAssertEqual(error as? DecisionError, .invalidResponse) }
            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.requests.count, position + 1)
            XCTAssertEqual(calls.reviews.count, position + 1)
            XCTAssertEqual(calls.observedReviews.count, position)
        }
    }

    func testInvalidInputStagesAndControlCharactersStopBeforeAnyCall() async throws {
        let invalid: [ProcessingRequest] = [
            .init(mode: .dictation, transcript: "원문"),
            .init(mode: .prompt, transcript: " \n\t"),
            .init(mode: .prompt, transcript: "원문\u{0000}"),
            .init(mode: .prompt, transcript: "원문", promptDraft: "중첩 초안"),
            .init(mode: .prompt, transcript: "원문", translationDraft: "Translation"),
            .init(mode: .prompt, transcript: "원문", previousOutput: "이전 후보"),
            .init(mode: .prompt, transcript: "원문", promptReviewIssues: [.intent])
        ]
        for input in invalid {
            let ledger = PromptCompositionLedger(outputs: [], reviews: [])
            do { _ = try await run(ledger, request: input); XCTFail("Expected invalid input") }
            catch { XCTAssertEqual(error as? PromptCompositionFailure, .invalidInput) }
            let calls = await ledger.snapshot()
            XCTAssertTrue(calls.events.isEmpty)
        }
    }

    func testUTF8InputLimitIsCheckedBeforeGeneratingAndDoesNotTruncate() async throws {
        let exact = String(repeating: "가", count: 4_000)
        XCTAssertEqual(exact.utf8.count, PromptCompositionLimits.maximumSourceBytes)
        let ledger = PromptCompositionLedger(outputs: ["초안", "최종 요청"],
                                             reviews: [acceptedReview(), acceptedReview()])
        _ = try await run(ledger, request: .init(mode: .prompt, transcript: exact))
        let acceptedCalls = await ledger.snapshot()
        XCTAssertEqual(acceptedCalls.requests.first?.transcript, exact)
        let oversized = PromptCompositionLedger(outputs: [], reviews: [])
        do { _ = try await run(oversized, request: .init(mode: .prompt, transcript: exact + "a")); XCTFail("Expected source limit") }
        catch { XCTAssertEqual(error as? PromptCompositionFailure, .inputTooLarge) }
        let rejectedCalls = await oversized.snapshot()
        XCTAssertTrue(rejectedCalls.events.isEmpty)
    }

    func testEmptyOversizedControlAndCodeFenceOutputStopBeforeNextReview() async throws {
        let invalid = [" \n\t", "출력\u{0000}", String(repeating: "가", count: 4_001),
                       "```swift\nprint(1)\n```", "~~~python\nprint(1)\n~~~"]
        for output in invalid {
            for position in [0, 1] {
                let outputs = position == 0 ? [output] : ["초안", output]
                let ledger = PromptCompositionLedger(outputs: outputs, reviews: [acceptedReview(), acceptedReview()])
                do { _ = try await run(ledger); XCTFail("Expected invalid output") }
                catch { XCTAssertEqual(error as? PromptCompositionFailure, .invalidOutput) }
                let calls = await ledger.snapshot()
                XCTAssertEqual(calls.requests.count, position + 1)
                XCTAssertEqual(calls.reviews.count, position)
            }
        }
    }

    func testCancellationBeforeStartingHasNoCalls() async throws {
        let ledger = PromptCompositionLedger(outputs: [], reviews: [])
        let input = request
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await run(ledger, request: input)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ledger.snapshot()
        XCTAssertTrue(calls.events.isEmpty)
    }

    func testCancellationAfterEachExternalResponseCannotPublishOrStartNextCall() async throws {
        for index in 0..<4 {
            let ledger = PromptCompositionLedger(outputs: ["초안", "최종 후보"],
                reviews: [acceptedReview(), acceptedReview()], cancelExternalCallAt: index)
            let task = Task { try await run(ledger) }
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.requests.count + calls.reviews.count, index + 1)
            XCTAssertEqual(calls.observedReviews.count, index >= 2 ? 1 : 0)
        }
    }

    func testCancellationInsideReviewCallbackStopsBeforeNextCallOrPublication() async throws {
        for position in [0, 1] {
            let ledger = PromptCompositionLedger(outputs: ["초안", "다듬기 후보"],
                                                 reviews: [acceptedReview(), acceptedReview()])
            let input = request
            let task = Task {
                try await PromptCompositionRunner.run(request: input,
                    process: { try await ledger.generate($0) }, review: { try await ledger.review($0) },
                    onProgress: { stage, text in await ledger.progress(stage, candidate: text) },
                    onReview: { stage, request, result in
                        await ledger.observedReview(stage, request: request, result: result)
                        if String(describing: stage) == (position == 0 ? "reviewingDraft" : "reviewingFinal") {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    })
            }
            do { _ = try await task.value; XCTFail("Expected callback cancellation to stop publication") }
            catch { XCTAssertTrue(error is CancellationError) }
            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.requests.count, position + 1)
            XCTAssertEqual(calls.reviews.count, position + 1)
            XCTAssertEqual(calls.observedReviews.count, position + 1)
        }
    }

    func testProgressCancellationStopsBeforeFirstGeneration() async throws {
        let ledger = PromptCompositionLedger(outputs: [], reviews: [])
        do {
            _ = try await PromptCompositionRunner.run(request: request,
                process: { try await ledger.generate($0) }, review: { try await ledger.review($0) },
                onProgress: { _, _ in throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ledger.snapshot()
        XCTAssertTrue(calls.events.isEmpty)
    }

    private func run(_ ledger: PromptCompositionLedger, request supplied: ProcessingRequest? = nil) async throws -> PromptCompositionOutput {
        try await PromptCompositionRunner.run(request: supplied ?? request,
            process: { try await ledger.generate($0) }, review: { try await ledger.review($0) },
            onProgress: { stage, text in await ledger.progress(stage, candidate: text) },
            onReview: { stage, request, result in await ledger.observedReview(stage, request: request, result: result) })
    }

    private func acceptedReview() -> PromptCompositionReviewResult { review() }
    private func review(overriding issue: PromptCompositionIssue? = nil,
                        choice: PromptCompositionReviewChoice = .pass,
                        confidence: Double = 0.9) -> PromptCompositionReviewResult {
        let accepted = PromptCompositionReviewAssessment(choice: .pass,
            probabilities: [.pass: 0.94, .fail: 0.03, .uncertain: 0.03], confidence: 0.9)
        var assessments = Dictionary(uniqueKeysWithValues: PromptCompositionIssue.allCases.map { ($0, accepted) })
        if let issue {
            var probabilities: [PromptCompositionReviewChoice: Double] = [.pass: 0.03, .fail: 0.03, .uncertain: 0.03]
            probabilities[choice] = 0.94
            assessments[issue] = .init(choice: choice, probabilities: probabilities, confidence: confidence)
        }
        return .init(assessments: assessments)
    }
}

private actor PromptCompositionLedger {
    struct ReviewObservation {
        let stage: String
        let request: PromptCompositionReviewRequest
        let result: PromptCompositionReviewResult
    }
    struct Snapshot {
        let events: [String]
        let requests: [ProcessingRequest]
        let reviews: [PromptCompositionReviewRequest]
        let progressCandidates: [String: String]
        let observedReviews: [ReviewObservation]
    }
    private let outputs: [String]
    private let results: [PromptCompositionReviewResult]
    private let failReviewAt: Int?
    private let cancelExternalCallAt: Int?
    private var events: [String] = []
    private var requests: [ProcessingRequest] = []
    private var reviews: [PromptCompositionReviewRequest] = []
    private var progressCandidates: [String: String] = [:]
    private var observedReviews: [ReviewObservation] = []
    private var externalCalls = 0

    init(outputs: [String], reviews: [PromptCompositionReviewResult], failReviewAt: Int? = nil,
         cancelExternalCallAt: Int? = nil) {
        self.outputs = outputs; self.results = reviews; self.failReviewAt = failReviewAt
        self.cancelExternalCallAt = cancelExternalCallAt
    }
    func generate(_ request: ProcessingRequest) throws -> String {
        events.append("generate"); requests.append(request)
        cancelIfRequested()
        return outputs[requests.count - 1]
    }
    func review(_ request: PromptCompositionReviewRequest) throws -> PromptCompositionReviewResult {
        events.append("review"); reviews.append(request)
        cancelIfRequested()
        if failReviewAt == reviews.count - 1 { throw DecisionError.invalidResponse }
        return results[reviews.count - 1]
    }
    func progress(_ stage: PromptCompositionStage, candidate: String? = nil) {
        events.append("stage:\(stage)")
        progressCandidates[String(describing: stage)] = candidate
    }
    func observedReview(_ stage: PromptCompositionStage, request: PromptCompositionReviewRequest,
                        result: PromptCompositionReviewResult) {
        observedReviews.append(.init(stage: String(describing: stage), request: request, result: result))
    }
    func snapshot() -> Snapshot {
        .init(events: events, requests: requests, reviews: reviews,
              progressCandidates: progressCandidates, observedReviews: observedReviews)
    }
    private func cancelIfRequested() {
        if cancelExternalCallAt == externalCalls { withUnsafeCurrentTask { $0?.cancel() } }
        externalCalls += 1
    }
}
