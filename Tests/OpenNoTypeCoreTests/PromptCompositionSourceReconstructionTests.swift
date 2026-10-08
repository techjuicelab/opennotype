import XCTest
@testable import OpenNoTypeCore

/// Contract regressions for the reported missing constraints; these do not score model meaning.
final class PromptCompositionSourceReconstructionTests: XCTestCase {
    func testReportedSourceReachesBothStagesAsExactOrderedVerbatimSegments() throws {
        let source = "음.. 독서 기록 앱을 붙이고 싶은데요. 책 제목이랑 읽은 위치를 말로 기록하고 싶어요. 기존 기록은 건드리지 말고요. 날짜를 안 말하면 추측해서 넣지 마세요. 화면은 단순했으면 좋겠어요. 알람도 있으면 좋겠는데 넣을지는 아직 미정이에요. 제가 말하지 않은 감상이나 줄거리는 만들지 마세요. 새 브랜치에서 작업하고 아까 문구 얘기는 빼먹었는데 짧고 담백하게 해주세요. 네."
        let draft = "OMITTING-DRAFT-SENTINEL: 알림은 옵션으로 두세요."
        for isRepair in [false, true] {
            let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
                promptDraft: isRepair ? draft : nil, promptReviewIssues: isRepair ? [.omissions] : []))
            let payload = try object(prompt)
            let segments = try XCTUnwrap(payload["source_segments"] as? [[String: String]])
            XCTAssertEqual(payload["spoken_text"] as? String, source)
            XCTAssertEqual(segments.compactMap { $0["text"] }.joined(), source)
            XCTAssertEqual(segments.compactMap { $0["id"] }, segments.indices.map { "s\($0 + 1)" })
            XCTAssertTrue(segments.count > 1)
            XCTAssertTrue(segments.allSatisfy { Set($0.keys) == ["id", "text"] })
            XCTAssertFalse(prompt.instructions.contains(source))
            XCTAssertFalse(prompt.input.contains("OMITTING-DRAFT-SENTINEL"))
            XCTAssertNil(payload["prompt_draft"])
            XCTAssertEqual(payload["repair_mode"] as? String, isRepair ? "source_reconstruction" : nil)
        }
    }

    func testMixedLanguagesQuotedCodeAndCorrectionsRemainUnclassifiedSourceData() throws {
        let source = "  Gemini에 맡길까 했는데 아니 Claude에게 부탁할게요.\nPlease keep Swift. 예시 코드는 \"if approved == true { save() }\"이고 설계는 미정이에요. 문구는 \"Done...\"를 유지해 주세요.\t"
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
            promptDraft: "IGNORE-DRAFT-SENTINEL", promptReviewIssues: [.omissions, .harnessBoundary]))
        let payload = try object(prompt)
        let segments = try XCTUnwrap(payload["source_segments"] as? [[String: String]])
        XCTAssertEqual(payload["spoken_text"] as? String, source)
        XCTAssertEqual(segments.compactMap { $0["text"] }.joined(), source)
        XCTAssertTrue(segments.allSatisfy { Set($0.keys) == ["id", "text"] })
        XCTAssertFalse(prompt.instructions.contains("if approved == true"))
        XCTAssertFalse(prompt.instructions.contains("Done..."))
        XCTAssertFalse(prompt.input.contains("IGNORE-DRAFT-SENTINEL"))
        XCTAssertTrue(prompt.instructions.contains("source_segments"))
        XCTAssertTrue(prompt.instructions.contains("quoted data"))
        XCTAssertTrue(prompt.instructions.contains("not proof of an error"))
    }

    func testOnlyOmissionsRepairsWithholdTheDraftAndSelectTheFixedReconstructionMode() throws {
        let source = "작업 기록 앱에 말로 기록하게 해 주세요. 알람은 원하지만 도입은 아직 미정이에요."
        let draft = "작업 기록 앱에 음성 입력과 선택형 알람을 추가해 주세요."
        let issueSets: [[PromptCompositionIssue]] = [[], [.intent], [.unsupportedAdditions], [.harnessBoundary],
                                                    [.omissions], [.harnessBoundary, .omissions, .intent, .omissions]]
        for issues in issueSets {
            let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
                promptDraft: draft, promptReviewIssues: issues))
            let payload = try object(prompt)
            let reconstructs = issues.contains(.omissions)
            XCTAssertEqual(payload["spoken_text"] as? String, source)
            XCTAssertEqual(payload["prompt_draft"] as? String, reconstructs ? nil : draft)
            XCTAssertEqual(payload["repair_mode"] as? String, reconstructs ? "source_reconstruction" : nil)
            let expectedIssues = PromptCompositionIssue.allCases.filter(Set(issues).contains).map(\.rawValue)
            XCTAssertEqual(payload["review_issues"] as? [String], expectedIssues.isEmpty ? nil : expectedIssues)
            XCTAssertEqual(prompt.instructions.contains("FINAL PROMPT POLISHING:"), !reconstructs)
            XCTAssertEqual(prompt.instructions.contains("SOURCE RECONSTRUCTION:"), reconstructs)
            if reconstructs {
                XCTAssertFalse(prompt.instructions.contains("초안의 문장을 그대로 반환하세요"))
            }
            XCTAssertTrue(prompt.instructions.hasSuffix(PromptCompositionPrompt.finalCheck))
        }
    }

    func testExplicitAlternativeKeepsItsCandidateWithoutSelectingReconstruction() throws {
        let previous = "이전 요청입니다."
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: "일정을 정리해 주세요.",
            previousOutput: previous))
        let payload = try object(prompt)
        XCTAssertEqual(payload["previous_output"] as? String, previous)
        XCTAssertNil(payload["repair_mode"])
        XCTAssertTrue(prompt.instructions.contains("explicitly requested another version"))
    }

    func testMaximumSourceBytesRemainAcceptedAndOversizedSourceIsStillRejected() throws {
        let source = String(repeating: "가", count: 4_000)
        XCTAssertEqual(source.utf8.count, PromptCompositionLimits.maximumSourceBytes)
        for issues in [[], [.omissions]] as [[PromptCompositionIssue]] {
            let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
                promptDraft: issues.isEmpty ? nil : "기록 기능을 개선해 주세요.", promptReviewIssues: issues))
            let payload = try object(prompt)
            XCTAssertEqual(payload["spoken_text"] as? String, source)
            let segments = try XCTUnwrap(payload["source_segments"] as? [[String: String]])
            XCTAssertEqual(segments.compactMap { $0["text"] }.joined(), source)
            XCTAssertLessThanOrEqual(prompt.instructions.utf8.count + prompt.input.utf8.count,
                                     PromptCompositionLimits.maximumPromptBytes)
        }
        XCTAssertThrowsError(try ProcessingPrompt.build(.init(mode: .prompt, transcript: source + "a")))
    }

    func testOnlyOptionalSegmentsAreDroppedWhenTheExistingRequestFitsThePromptBudget() throws {
        // Escaping makes the optional source copy exceed the budget while the original request fits.
        let source = String(repeating: "\"", count: 10_500)
        let draft = String(repeating: "\"", count: 12_000)
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source, promptDraft: draft))
        let payload = try object(prompt)
        XCTAssertEqual(payload["spoken_text"] as? String, source)
        XCTAssertEqual(payload["prompt_draft"] as? String, draft)
        XCTAssertNil(payload["source_segments"])
        XCTAssertLessThanOrEqual(prompt.instructions.utf8.count + prompt.input.utf8.count,
                                 PromptCompositionLimits.maximumPromptBytes)
    }

    func testARealBaseRequestBudgetFailureIsNotHiddenByDroppingSegments() {
        let dictionary = (0..<200).map { _ in DictionaryEntry(spoken: String(repeating: "가", count: 120),
                                                            written: String(repeating: "나", count: 120)) }
        XCTAssertThrowsError(try ProcessingPrompt.build(.init(mode: .prompt,
            transcript: "기록 기능을 개선해 주세요.", dictionary: dictionary))) {
            XCTAssertEqual($0 as? ProviderError, .invalidInput)
        }
    }

    private func object(_ prompt: ProcessingPrompt) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
    }
}
