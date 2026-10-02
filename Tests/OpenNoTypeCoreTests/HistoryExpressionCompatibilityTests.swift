import Foundation
import XCTest
@testable import OpenNoTypeCore

final class HistoryExpressionCompatibilityTests: XCTestCase {
    func testLegacyHistoryDecodesWithoutOptingIntoExpression() throws {
        let original = HistoryEntry(mode: .dictation, originalText: "기존 원문", resultText: "기존 결과", provider: .groq)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "writingProfile")
        let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.writingProfile)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.resultText, original.resultText)
    }

    func testCapturedExpressionSurvivesHistoryRoundTrip() throws {
        let profile = WritingProfile(kind: .notes, tone: .preserve, expression: .init(style: .summary, strength: 75))
        let original = HistoryEntry(mode: .dictation, originalText: "합성 원문", resultText: "합성 요약", provider: .openRouter, writingProfile: profile)
        let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.writingProfile, profile)
        XCTAssertEqual(restored.originalText, original.originalText)
    }
}
