import XCTest
@testable import OpenNoTypeCore

/// Semantic labels are supplied by the fixture, not inferred by this offline test.
/// The real runner must preserve those decisions and the exact reviewed candidate.
final class PromptCompositionSemanticFlowTests: XCTestCase {
    func testMissingSecondaryRequirementGetsOneRepairAgainstTheOriginalSource() async throws {
        let source = "배송 앱에서 주소를 수정할 수 있게 해 주세요. 저장이 실패하면 기존 주소를 보존하고 다시 시도할 수 있어야 합니다."
        let draft = "배송 앱에서 주소 수정과 재시도를 지원해 주세요."
        let repaired = "배송 앱에서 주소를 수정할 수 있게 해 주세요. 저장 실패 시 기존 주소를 보존하고 다시 시도할 수 있게 해 주세요."
        let first = review(holding: .omissions, choice: .fail)
        let ledger = SemanticFlowLedger(outputs: [draft, repaired], results: [first, review()])

        let result = try await run(source, ledger: ledger)

        XCTAssertEqual(result.text, repaired)
        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.generations.count, 2)
        XCTAssertEqual(calls.generations.map(\.transcript), [source, source])
        XCTAssertEqual(calls.generations[1].promptDraft, draft)
        XCTAssertEqual(calls.generations[1].promptReviewIssues, [.omissions])
        XCTAssertNil(calls.generations[1].previousOutput)
        XCTAssertEqual(calls.reviewRequests, [.init(transcript: source, prompt: draft),
                                             .init(transcript: source, prompt: repaired)])
        XCTAssertEqual(calls.observations.map(\.request), calls.reviewRequests)
        XCTAssertEqual(calls.observations.first?.result.assessments, first.assessments)
        XCTAssertEqual(calls.observations.last?.stage, "reviewingFinal")
    }

    func testFinalConditionExpansionIsHeldEvenAfterAnInitialPassAndAFaithfulPolish() async throws {
        let source = "문서 앱에서 공동 편집 중일 때만 변경 알림을 표시해 주세요. 개인 문서를 편집할 때는 알리지 마세요."
        let expanded = "문서 앱에서 문서를 편집할 때마다 변경 알림을 표시해 주세요."
        let faithful = "문서 앱에서 공동 편집 중일 때만 변경 알림을 표시하고 개인 문서 편집에는 알리지 마세요."
        for choice in [PromptCompositionReviewChoice.fail, .uncertain] {
            let final = review(holding: .intent, choice: choice)
            let ledger = SemanticFlowLedger(outputs: [expanded, faithful], results: [review(), final])

            do {
                _ = try await run(source, ledger: ledger)
                XCTFail("A final condition-scope rejection must not publish any candidate")
            } catch {
                XCTAssertEqual(error as? PromptCompositionFailure, .reviewHeld)
            }

            let calls = await ledger.snapshot()
            XCTAssertEqual(calls.generations.count, 2)
            // Initial acceptance keeps the draft stable; a held final review cannot switch
            // to the generated but unreviewed polish as an implicit fallback.
            XCTAssertEqual(calls.reviewRequests.map(\.prompt), [expanded, expanded])
            XCTAssertEqual(calls.observations.last?.request, .init(transcript: source, prompt: expanded))
            XCTAssertEqual(calls.observations.last?.result.assessments, final.assessments)
            XCTAssertEqual(calls.observations.last?.result.issues, [.intent])
            XCTAssertEqual(calls.stages, ["drafting", "reviewingDraft", "polishing", "reviewingFinal"])
        }
    }

    func testAcceptedConditionalDraftCannotExpandToAdditionalUsersDuringPolishing() async throws {
        let source = "초대 앱에서 관리자가 승인한 멤버에게만 다운로드를 허용해 주세요. 초대받지 않은 사람은 다운로드할 수 없어야 합니다."
        let draft = "초대 앱에서 관리자 승인을 받은 멤버만 다운로드할 수 있게 하고, 초대받지 않은 사람의 다운로드는 막아 주세요."
        let expanded = "초대 앱에서 모든 사용자가 다운로드할 수 있게 해 주세요."
        let ledger = SemanticFlowLedger(outputs: [draft, expanded], results: [review(), review()])

        let result = try await run(source, ledger: ledger)

        let calls = await ledger.snapshot()
        XCTAssertEqual(result.text, draft)
        XCTAssertEqual(calls.generations.count, 2)
        XCTAssertEqual(calls.reviewRequests, [.init(transcript: source, prompt: draft),
                                             .init(transcript: source, prompt: draft)])
        XCTAssertEqual(calls.observations.last?.request.prompt, result.text)
        XCTAssertEqual(calls.observations.last?.result.accepted, true)
    }

    func testRepairThatAddsANewConditionIsHeldWithoutAnotherRepairOrDraftFallback() async throws {
        let source = "메모 앱에서 첨부 파일 검색을 지원해 주세요. 오프라인 검색도 원하지만 도입 여부는 아직 결정하지 않았습니다."
        let draft = "메모 앱에 첨부 파일 검색을 추가해 주세요."
        let invented = "메모 앱에 첨부 파일 검색을 추가하고, 유료 사용자에게만 오프라인 검색을 제공해 주세요."
        let first = review(holding: .omissions, choice: .fail)
        let final = review(holding: .unsupportedAdditions, choice: .fail)
        let ledger = SemanticFlowLedger(outputs: [draft, invented], results: [first, final])

        do {
            _ = try await run(source, ledger: ledger)
            XCTFail("An invented eligibility condition must remain held")
        } catch {
            XCTAssertEqual(error as? PromptCompositionFailure, .reviewHeld)
        }

        let calls = await ledger.snapshot()
        XCTAssertEqual(calls.generations.count, 2)
        XCTAssertEqual(calls.generations[1].promptReviewIssues, [.omissions])
        XCTAssertEqual(calls.reviewRequests, [.init(transcript: source, prompt: draft),
                                             .init(transcript: source, prompt: invented)])
        XCTAssertEqual(calls.observations.last?.request.prompt, invented)
        XCTAssertEqual(calls.observations.last?.result.issues, [.unsupportedAdditions])
        XCTAssertEqual(calls.stages.last, "reviewingFinal")
    }

    private func run(_ source: String, ledger: SemanticFlowLedger) async throws -> PromptCompositionOutput {
        try await PromptCompositionRunner.run(request: .init(mode: .prompt, transcript: source),
            process: { try await ledger.generate($0) }, review: { try await ledger.review($0) },
            onProgress: { stage, _ in await ledger.progress(stage) },
            onReview: { stage, request, result in await ledger.observe(stage, request, result) })
    }

    private func review(holding issue: PromptCompositionIssue? = nil,
                        choice: PromptCompositionReviewChoice = .pass) -> PromptCompositionReviewResult {
        let pass = PromptCompositionReviewAssessment(choice: .pass,
            probabilities: [.pass: 0.94, .fail: 0.03, .uncertain: 0.03], confidence: 0.9)
        var assessments = Dictionary(uniqueKeysWithValues: PromptCompositionIssue.allCases.map { ($0, pass) })
        if let issue {
            var probabilities: [PromptCompositionReviewChoice: Double] = [.pass: 0.03, .fail: 0.03, .uncertain: 0.03]
            probabilities[choice] = 0.94
            assessments[issue] = .init(choice: choice, probabilities: probabilities, confidence: 0.9)
        }
        return .init(assessments: assessments)
    }
}

private actor SemanticFlowLedger {
    struct Observation {
        var stage: String
        var request: PromptCompositionReviewRequest
        var result: PromptCompositionReviewResult
    }
    struct Snapshot {
        var generations: [ProcessingRequest]
        var reviewRequests: [PromptCompositionReviewRequest]
        var observations: [Observation]
        var stages: [String]
    }
    private var outputs: [String]
    private var results: [PromptCompositionReviewResult]
    private var generations: [ProcessingRequest] = []
    private var reviewRequests: [PromptCompositionReviewRequest] = []
    private var observations: [Observation] = []
    private var stages: [String] = []

    init(outputs: [String], results: [PromptCompositionReviewResult]) {
        self.outputs = outputs
        self.results = results
    }
    func generate(_ request: ProcessingRequest) throws -> String {
        guard generations.count < outputs.count else { throw DecisionError.invalidResponse }
        generations.append(request)
        return outputs[generations.count - 1]
    }
    func review(_ request: PromptCompositionReviewRequest) throws -> PromptCompositionReviewResult {
        guard reviewRequests.count < results.count else { throw DecisionError.invalidResponse }
        reviewRequests.append(request)
        return results[reviewRequests.count - 1]
    }
    func progress(_ stage: PromptCompositionStage) { stages.append(String(describing: stage)) }
    func observe(_ stage: PromptCompositionStage, _ request: PromptCompositionReviewRequest,
                 _ result: PromptCompositionReviewResult) {
        observations.append(.init(stage: String(describing: stage), request: request, result: result))
    }
    func snapshot() -> Snapshot {
        .init(generations: generations, reviewRequests: reviewRequests, observations: observations, stages: stages)
    }
}
