import XCTest
@testable import OpenNoTypeCore

/// Structural coverage is a wire contract, not evidence that model meaning is complete.
final class PromptCompositionSegmentResponseTests: XCTestCase {
    func testSchemaExposesOnlyTheExpectedIDsAndStrictSegmentFields() throws {
        let ids = ["s1", "s2"]
        let schema = PromptCompositionSegmentResponse.schema(ids: ids)
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["segments"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["segments"])
        let array = try XCTUnwrap(properties["segments"] as? [String: Any])
        XCTAssertEqual(array["minItems"] as? Int, ids.count)
        XCTAssertEqual(array["maxItems"] as? Int, ids.count)
        let item = try XCTUnwrap(array["items"] as? [String: Any])
        XCTAssertEqual(item["required"] as? [String], ["id", "text"])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        let fields = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["id", "text"])
        XCTAssertEqual((fields["id"] as? [String: Any])?["enum"] as? [String], ids)
    }

    func testDecoderJoinsOnlyNonemptyTrimmedFragmentsInOriginalOrder() throws {
        let segments = [["id": "s1", "text": "  책 제목을 말로 기록해 주세요.\n"],
                        ["id": "s2", "text": " \t\r\n"],
                        ["id": "s3", "text": "\n알람은 원하지만 도입은 미정입니다.  "]]
        let result = try PromptCompositionSegmentResponse.decode(["segments": segments], ids: ["s1", "s2", "s3"])
        XCTAssertEqual(result, "책 제목을 말로 기록해 주세요.\n알람은 원하지만 도입은 미정입니다.")
    }

    func testDecoderRejectsUnknownFieldsTypesMissingDuplicateAndReorderedIDs() {
        let valid: [[String: Any]] = [["id": "s1", "text": "첫 요청입니다."], ["id": "s2", "text": "둘째 요청입니다."]]
        let malformed: [[String: Any]] = [
            [:], ["text": "일반 응답입니다."], ["segments": valid, "text": "추가 필드"],
            ["segments": NSNull()], ["segments": "not an array"], ["segments": []],
            ["segments": [valid[0]]], ["segments": valid + [valid[1]]],
            ["segments": [valid[1], valid[0]]], ["segments": [valid[0], valid[0]]],
            ["segments": [valid[0], ["id": "s3", "text": "다른 ID"]]],
            ["segments": [valid[0], ["id": "s2"]]],
            ["segments": [valid[0], ["text": "ID가 없음"]]],
            ["segments": [valid[0], ["id": 2, "text": "숫자 ID"]]],
            ["segments": [valid[0], ["id": "s2", "text": 2]]],
            ["segments": [valid[0], ["id": "s2", "text": NSNull()]]],
            ["segments": [valid[0], ["id": "s2", "text": "요청", "reason": "추가 필드"]]]
        ]
        for object in malformed {
            XCTAssertThrowsError(try PromptCompositionSegmentResponse.decode(object, ids: ["s1", "s2"])) {
                XCTAssertEqual($0 as? ProviderError, .invalidResponse)
            }
        }
    }

    func testDecoderDistinguishesAnEmptyTaskFromInvalidResponseStructure() {
        XCTAssertThrowsError(try PromptCompositionSegmentResponse.decode(
            ["segments": [["id": "s1", "text": " \t\n"]]], ids: ["s1"])) {
            XCTAssertEqual($0 as? PromptCompositionFailure, .invalidOutput)
        }
        for ids in [[], ["s1", "s1"], (1...65).map { "s\($0)" }] as [[String]] {
            XCTAssertThrowsError(try PromptCompositionSegmentResponse.decode(["segments": []], ids: ids)) {
                XCTAssertEqual($0 as? ProviderError, .invalidResponse)
            }
        }
    }

    func testOnlyBoundedOmissionsRepairsSelectStructuredSegmentResponses() throws {
        let source = "책 제목을 말로 기록하게 해 주세요. 알람은 원하지만 도입은 미정이에요. 문구는 짧고 담백하게 해 주세요."
        let issueSets: [[PromptCompositionIssue]] = [[], [.intent], [.unsupportedAdditions], [.harnessBoundary],
                                                    [.omissions], [.intent, .omissions, .harnessBoundary]]
        for issues in issueSets {
            let request = ProcessingRequest(mode: .prompt, transcript: source,
                promptDraft: "불완전한 요청입니다.", promptReviewIssues: issues)
            let prompt = try ProcessingPrompt.build(request)
            let object = try payload(prompt)
            let segments = try XCTUnwrap(object["source_segments"] as? [[String: String]])
            let expectedIDs = segments.compactMap { $0["id"] }
            XCTAssertEqual(prompt.reconstructionSegmentIDs, issues.contains(.omissions) ? expectedIDs : nil)
            XCTAssertEqual(object["spoken_text"] as? String, source)
            XCTAssertEqual(segments.compactMap { $0["text"] }.joined(), source)
            XCTAssertEqual(object["prompt_draft"] as? String, issues.contains(.omissions) ? nil : request.promptDraft)
            if issues.contains(.omissions) {
                XCTAssertTrue(prompt.instructions.contains("SEGMENT RESPONSE:"))
                XCTAssertTrue(prompt.instructions.contains("every distinct clause within each segment"))
                XCTAssertFalse(prompt.instructions.contains("single JSON text field"))
                XCTAssertFalse(prompt.instructions.contains("{\"text\":"))
            } else {
                XCTAssertFalse(prompt.instructions.contains("SEGMENT RESPONSE:"))
                XCTAssertTrue(prompt.instructions.contains("{\"text\":"))
            }
        }
        let first = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source))
        XCTAssertNil(first.reconstructionSegmentIDs)
        XCTAssertFalse(first.instructions.contains("SEGMENT RESPONSE:"))
    }

    func testMoreThanSixtyFourSegmentsUsePlainTextWithoutLosingSource() throws {
        let source = String(repeating: "기록을 유지해 주세요.\n", count: 65)
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
            promptDraft: "기록을 유지해 주세요.", promptReviewIssues: [.omissions]))
        let object = try payload(prompt)
        let segments = try XCTUnwrap(object["source_segments"] as? [[String: String]])
        XCTAssertTrue(segments.count > 64)
        XCTAssertNil(prompt.reconstructionSegmentIDs)
        XCTAssertEqual(object["spoken_text"] as? String, source)
        XCTAssertEqual(segments.compactMap { $0["text"] }.joined(), source)
        XCTAssertTrue(prompt.instructions.contains("{\"text\":"))
        XCTAssertFalse(prompt.instructions.contains("SEGMENT RESPONSE:"))
    }

    func testExactlySixtyFourSegmentsRemainEligibleForStructuredRepair() throws {
        let source = String(repeating: "기록을 유지해 주세요.\n", count: 64)
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source,
            promptDraft: "기록을 유지해 주세요.", promptReviewIssues: [.omissions]))
        XCTAssertEqual(prompt.reconstructionSegmentIDs, (1...64).map { "s\($0)" })
        XCTAssertTrue(prompt.instructions.contains("SEGMENT RESPONSE:"))
    }

    func testBudgetFallbackAlsoSelectsPlainTextAndPreservesTheOriginalSpeech() throws {
        let source = String(repeating: "\"", count: 12_000)
        let dictionary = (0..<20).map { _ in DictionaryEntry(spoken: String(repeating: "a", count: 120),
                                                           written: String(repeating: "b", count: 120)) }
        let prompt = try ProcessingPrompt.build(.init(mode: .prompt, transcript: source, dictionary: dictionary,
            promptDraft: "원문을 보존해 주세요.", promptReviewIssues: [.omissions]))
        let object = try payload(prompt)
        XCTAssertNil(prompt.reconstructionSegmentIDs)
        XCTAssertNil(object["source_segments"])
        XCTAssertNil(object["prompt_draft"])
        XCTAssertEqual(object["spoken_text"] as? String, source)
        XCTAssertTrue(prompt.instructions.contains("{\"text\":"))
        XCTAssertLessThanOrEqual(prompt.instructions.utf8.count + prompt.input.utf8.count,
                                 PromptCompositionLimits.maximumPromptBytes)
    }

    private func payload(_ prompt: ProcessingPrompt) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.input.utf8)) as? [String: Any])
    }
}
