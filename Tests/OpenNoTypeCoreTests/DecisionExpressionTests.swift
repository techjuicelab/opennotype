import Foundation
import XCTest
@testable import OpenNoTypeCore

final class DecisionExpressionTests: XCTestCase {
    private let transcript = "승인되면 JEV를 오후 3시에 검토하되 배포하지 마세요."

    private func request(expression: DictationExpression = .init(),
                         purpose: DecisionReviewPurpose = .dictation,
                         provider: DecisionProvider = .typeSafe) throws -> URLRequest {
        try DecisionClient.makeRequest(.init(transcript: transcript, cleanedText: "검토 결과",
            purpose: purpose, detailAxes: DecisionDetailAxis.allCases, expression: expression),
            apiKey: "synthetic-expression-key", provider: provider)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testZeroStrengthAndFaithfulLeaveDefaultWireBodyUnchanged() throws {
        for provider in DecisionProvider.allCases {
            let original = try request(provider: provider)
            for style in DictationExpressionStyle.allCases {
                XCTAssertEqual(try request(expression: .init(style: style, strength: 0), provider: provider).httpBody,
                               original.httpBody, style.rawValue)
            }
            XCTAssertEqual(try request(expression: .init(style: .faithful, strength: 100), provider: provider).httpBody,
                           original.httpBody)
        }
    }

    func testReviewReceivesTheSameControlledExpressionPolicyOnEverySemanticAndDetailAxis() throws {
        for provider in DecisionProvider.allCases {
            for style in DictationExpressionStyle.allCases where style != .faithful {
                let expression = DictationExpression(style: style, strength: 80)
                let payload = try body(request(expression: expression, provider: provider))
                let state = try XCTUnwrap(payload["state"] as? [String: Any])
                let settings = try XCTUnwrap(state["dictation_expression"] as? [String: Any])
                XCTAssertEqual(settings["style"] as? String, style.rawValue)
                XCTAssertEqual(settings["strength"] as? Int, 80)
                let questions = try XCTUnwrap(payload["questions"] as? [String: [String: Any]])
                XCTAssertEqual(questions.count, 8)
                for question in questions.values {
                    let instructions = try XCTUnwrap(question["instructions"] as? String)
                    XCTAssertTrue(instructions.contains(expression.reviewInstructions))
                    XCTAssertTrue(instructions.contains("quoted data"))
                    XCTAssertFalse(instructions.contains(transcript))
                }
                let additions = try XCTUnwrap(questions["content_added"]?["instructions"] as? String)
                XCTAssertTrue(additions.contains("unsupported by transcript"))
                let omissions = try XCTUnwrap(questions["content_omitted"]?["instructions"] as? String)
                XCTAssertTrue(omissions.contains("Permitted compression"))
                XCTAssertEqual(Set(questions.keys), Set(["meaning_changed", "content_added", "content_omitted"]
                    + DecisionDetailAxis.allCases.map { "detail_" + $0.rawValue }))
            }
        }
    }

    func testTranslationAndRewriteIgnoreActiveDictationExpressionByteForByte() throws {
        for provider in DecisionProvider.allCases {
            for purpose in [DecisionReviewPurpose.translation(targetLanguage: "English"),
                            .rewrite(originalText: "승인 후 검토합니다.")] {
                let original = try request(purpose: purpose, provider: provider)
                for style in DictationExpressionStyle.allCases {
                    let changed = try request(expression: .init(style: style, strength: 100),
                                              purpose: purpose, provider: provider)
                    XCTAssertEqual(changed.httpBody, original.httpBody, style.rawValue)
                }
            }
        }
    }

    func testSummaryReviewRejectsWishToCommandAndMixedModalityMergingOnEveryAxis() throws {
        let expression = DictationExpression(style: .summary, strength: 90)
        let payload = try body(request(expression: expression))
        let questions = try XCTUnwrap(payload["questions"] as? [String: [String: Any]])
        for question in questions.values {
            let instructions = try XCTUnwrap(question["instructions"] as? String)
            XCTAssertTrue(instructions.contains("preserve each clause's actor, speech act and modality independently"))
            XCTAssertTrue(instructions.contains("Do not merge different actions under one request"))
            XCTAssertTrue(instructions.contains("never turn it into an imperative"))
            XCTAssertTrue(instructions.contains("never weaken it into a suggestion"))
        }
    }
}
